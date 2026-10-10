import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

// The sidebar switcher (SUPER + TAB with two or more sidebars): live previews of
// every sidebar in the middle of the focused screen over a dimmed backdrop,
// styled like Omarchy's theme and background picker. hypr/sidebar.lua owns
// the keys and the choice; it sends the whole state with each change. It takes
// no keyboard focus and no clicks, so SUPER's release still reaches Hyprland.
Scope {
  id: root

  property bool open: false
  property string session: ""
  property int seq: -1
  property int index: 0
  property var items: []
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

    // Laid out like Omarchy's theme and background picker: the highlighted
    // sidebar as a large slanted card, the others as narrow slanted slices
    // overlapping on either side, in the picker's colours.
    Item {
      id: content
      anchors.fill: parent
      opacity: root.open ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

      Rectangle {
        anchors.fill: parent
        color: Color.imagePicker.scrim
      }

      readonly property int expandedHeight: 475
      readonly property int sliceWidth: 108
      readonly property int sliceHeight: 432
      readonly property int sliceSpacing: -30
      readonly property int skewOffset: 28
      readonly property real step: sliceWidth + sliceSpacing

      // The highlighted card is a little wider than its window's shape at the
      // picker's height; the preview fills it, cropped top and bottom.
      readonly property real widen: 1.4
      function cardWidth(it) {
        var w = expandedHeight * widen * (it.width / Math.max(1, it.height))
        return Math.max(260, Math.min(768, w))
      }

      // The window's preview at the card's width, at least the card's height.
      function previewHeight(it) {
        return Math.max(expandedHeight, cardWidth(it) * (it.height / Math.max(1, it.width)))
      }

      readonly property var chosenItem: root.items[root.index] || null
      readonly property real chosenWidth: chosenItem ? cardWidth(chosenItem) : 0

      Item {
        id: carousel
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -20
        width: content.chosenWidth
        height: content.expandedHeight

        Repeater {
          // Dropped once faded out, so nothing is captured while it's closed.
          model: root.open || content.opacity > 0 ? root.items : []

          delegate: Item {
            id: card
            required property var modelData
            required property int index

            readonly property int relative: index - root.index
            readonly property bool chosen: relative === 0
            // The window at the highlighted card's width; a slice shows its middle.
            readonly property real fullWidth: content.cardWidth(modelData)

            x: chosen ? 0 : (relative < 0
              ? relative * content.step
              : content.chosenWidth + content.sliceSpacing + (relative - 1) * content.step)
            y: chosen ? 0 : (content.expandedHeight - content.sliceHeight) / 2
            z: chosen ? 100 : 50 - Math.min(Math.abs(relative), 40)
            width: chosen ? fullWidth : content.sliceWidth
            height: chosen ? content.expandedHeight : content.sliceHeight

            readonly property real topLeft: content.skewOffset
            readonly property real topRight: width
            readonly property real bottomRight: width - content.skewOffset
            readonly property real bottomLeft: 0

            Item {
              id: maskShape
              anchors.fill: parent
              visible: false
              layer.enabled: true

              Shape {
                anchors.fill: parent
                antialiasing: true
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                  fillColor: "white"
                  strokeColor: "transparent"
                  startX: card.topLeft; startY: 0
                  PathLine { x: card.topRight; y: 0 }
                  PathLine { x: card.bottomRight; y: card.height }
                  PathLine { x: card.bottomLeft; y: card.height }
                  PathLine { x: card.topLeft; y: 0 }
                }
              }
            }

            Item {
              anchors.fill: parent
              layer.enabled: true
              layer.smooth: true
              layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: maskShape
                maskThresholdMin: 0.3
                maskSpreadAtMin: 0.3
              }

              Rectangle {
                anchors.fill: parent
                color: Color.background
              }

              ScreencopyView {
                anchors.centerIn: parent
                width: card.fullWidth
                height: content.previewHeight(card.modelData)
                captureSource: root.capture(card.modelData.address)
                live: true
              }

              Rectangle {
                anchors.fill: parent
                color: Util.alpha(Color.background, card.chosen ? 0 : 0.42)
              }
            }

            Shape {
              anchors.fill: parent
              antialiasing: true
              preferredRendererType: Shape.CurveRenderer
              ShapePath {
                fillColor: "transparent"
                strokeColor: card.chosen ? Color.imagePicker.selectedBorder : Color.imagePicker.unselectedBorder
                strokeWidth: card.chosen ? 3 : 1
                startX: card.topLeft; startY: 0
                PathLine { x: card.topRight; y: 0 }
                PathLine { x: card.bottomRight; y: card.height }
                PathLine { x: card.bottomLeft; y: card.height }
                PathLine { x: card.topLeft; y: 0 }
              }
            }
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        anchors.top: carousel.bottom
        anchors.topMargin: Style.space(16)
        anchors.horizontalCenter: carousel.horizontalCenter
        width: Math.max(content.chosenWidth, 480)
        text: content.chosenItem ? content.chosenItem.title : ""
        color: Color.imagePicker.text
        style: Text.Outline
        styleColor: Util.alpha(Color.background, 0.7)
        font.pixelSize: Style.font.display
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
      }
    }
  }
}
