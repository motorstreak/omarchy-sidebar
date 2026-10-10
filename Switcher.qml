import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

// The sidebar switcher (SUPER + B with two or more sidebars): live previews of
// every sidebar in the middle of the focused screen over a dimmed backdrop, the
// highlighted one framed in the sidebar border colour. hypr/sidebar.lua owns
// the keys and the choice; it sends the whole state with each change. It takes
// no keyboard focus and no clicks, so SUPER's release still reaches Hyprland.
Scope {
  id: root

  property bool open: false
  property string session: ""
  property int seq: -1
  property int index: 0
  property var items: []
  property color accent: "white"
  property string monitor: ""

  // Messages come from separate processes and can arrive out of order: only a
  // newer one counts. Each load of sidebar.lua numbers them afresh under a new
  // session id ("<load time>-<random>"), so a later session's messages always
  // count, and a straggler from an earlier one never does.
  function sessionTime(id) {
    return Number(String(id).split("-")[0]) || 0
  }

  function newer(messageSession, messageSeq) {
    if (messageSession !== session) {
      if (sessionTime(messageSession) < sessionTime(session)) return false
      session = messageSession
      seq = messageSeq
      return true
    }
    if (messageSeq <= seq) return false
    seq = messageSeq
    return true
  }

  function show(payload) {
    var p = JSON.parse(payload)
    if (!newer(String(p.session), p.seq)) return
    // The shell's list of Hyprland windows follows its event connection, which
    // is never remade once Hyprland closes it (quickshell #989): fetched afresh
    // on opening, so new sidebars still have previews.
    if (!open) Hyprland.refreshToplevels()
    monitor = p.monitor || ""
    items = p.items
    index = p.index
    accent = p.accent || "white"
    open = true
  }

  // "<session> <seq>"
  function close(message) {
    var parts = String(message).split(" ")
    if (!newer(parts[0], Number(parts[1]))) return
    open = false
  }

  // The window to capture, by its Hyprland address (with or without "0x").
  function capture(address) {
    var wanted = String(address).replace(/^0x/, "")
    var all = Hyprland.toplevels.values
    for (var i = 0; i < all.length; i++) {
      if (String(all[i].address).replace(/^0x/, "") === wanted) return all[i].wayland
    }
    return null
  }

  IpcHandler {
    target: "sidebar-switcher"
    function show(payload: string): string { root.show(payload); return "ok" }
    function close(message: string): string { root.close(message); return "ok" }
    function state(): string { return (root.open ? "open" : "closed") + " " + root.session + " " + root.seq }
  }

  PanelWindow {
    id: panel

    // The focused monitor, as sidebar.lua sends it (not Hyprland.focusedMonitor,
    // which goes stale with the shell's event connection).
    screen: {
      var screens = Quickshell.screens
      for (var i = 0; i < screens.length; i++) {
        if (screens[i].name === root.monitor) return screens[i]
      }
      return screens.length > 0 ? screens[0] : null
    }
    visible: root.open || content.opacity > 0
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-sidebar-switcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}

    Item {
      id: content
      anchors.fill: parent
      opacity: root.open ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

      Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: 0.45
      }

      // Each preview keeps its window's shape at a common height, shrunk
      // together if the row would be wider than the screen allows.
      readonly property real gap: 28
      readonly property real labelHeight: 34
      readonly property real baseHeight: panel.height * 0.42
      readonly property real naturalWidth: {
        var total = 0
        for (var i = 0; i < root.items.length; i++) {
          var it = root.items[i]
          total += baseHeight * (it.width / Math.max(1, it.height))
        }
        return total + gap * Math.max(0, root.items.length - 1)
      }
      readonly property real fit: Math.min(1, (panel.width * 0.85) / Math.max(1, naturalWidth))

      Row {
        anchors.centerIn: parent
        spacing: content.gap * content.fit

        Repeater {
          // Dropped once faded out, so nothing is captured while it's closed.
          model: root.open || content.opacity > 0 ? root.items : []

          Column {
            id: card
            required property var modelData
            required property int index
            readonly property bool chosen: index === root.index
            readonly property real previewHeight: content.baseHeight * content.fit
            readonly property real previewWidth: previewHeight * (modelData.width / Math.max(1, modelData.height))
            spacing: 10

            Rectangle {
              width: card.previewWidth + 12
              height: card.previewHeight + 12
              color: "#1a1a1a"
              border.width: card.chosen ? 4 : 1
              border.color: card.chosen ? root.accent : Qt.rgba(1, 1, 1, 0.25)
              opacity: card.chosen ? 1 : 0.7
              Behavior on opacity { NumberAnimation { duration: 90 } }

              ScreencopyView {
                anchors.fill: parent
                anchors.margins: 6
                captureSource: root.capture(card.modelData.address)
                live: true
              }
            }

            Text {
              width: card.previewWidth + 12
              height: content.labelHeight
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideRight
              text: card.modelData.title
              color: card.chosen ? "white" : Qt.rgba(1, 1, 1, 0.6)
              font.pixelSize: 15
              font.bold: card.chosen
            }
          }
        }
      }
    }
  }
}
