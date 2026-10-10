import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

// The sidebar theme picker (SUPER + ALT + T in a sidebar): the installed
// Omarchy themes in a list beside the sidebar, each previewed on it as it's
// highlighted (bin/sidebar-theme preview). Enter keeps it for that app's
// sidebars; Escape, or a click outside, puts back the one they had. Typing
// filters the list. hypr/sidebar.lua opens it with the sidebar's place.
Scope {
  id: root

  property string pluginDir: ""
  readonly property string script: pluginDir + "/bin/sidebar-theme"

  property bool open: false
  property string address: ""
  property string app: ""
  property string saved: "" // the app's theme ("" follows Omarchy's)
  property string monitor: ""
  property int sidebarX: 0 // on its monitor
  property int sidebarWidth: 0

  // [{ slug, label }], following Omarchy's theme first.
  property var themes: []
  property string filter: ""
  property int index: 0
  property string previewed: "" // the theme on the sidebar now
  property bool changed: false // a preview has been shown

  readonly property var shown: {
    var f = filter.toLowerCase()
    return themes.filter(function(t) { return f === "" || t.label.toLowerCase().indexOf(f) >= 0 })
  }
  readonly property var selected: shown[index] || null

  function run(args) {
    Quickshell.execDetached([root.script].concat(args))
  }

  function show(payload) {
    var p = JSON.parse(payload)
    address = String(p.address || "")
    app = String(p.app || "")
    saved = String(p.theme || "")
    monitor = String(p.monitor || "")
    sidebarX = Number(p.x) || 0
    sidebarWidth = Number(p.width) || 0
    filter = ""
    previewed = saved
    changed = false
    lister.running = true
  }

  function listed(text) {
    var list = [{ slug: "", label: "Follow system theme" }]
    String(text).split("\n").forEach(function(line) {
      var parts = line.split("\t")
      if (parts.length === 2 && parts[0]) list.push({ slug: parts[0], label: parts[1] })
    })
    themes = list
    index = Math.max(0, list.findIndex(function(t) { return t.slug === root.saved }))
    open = true
    keys.forceActiveFocus()
  }

  function move(step) {
    if (shown.length === 0) return
    index = Math.max(0, Math.min(shown.length - 1, index + step))
  }

  function commit() {
    if (!open) return
    open = false
    if (selected) run(["set", address, app, selected.slug])
    else if (changed) run(["cancel", address, app])
  }

  function cancel() {
    if (!open) return
    open = false
    if (changed) run(["cancel", address, app])
  }

  onSelectedChanged: if (open) previewTimer.restart()
  onFilterChanged: index = 0

  // Holding a key down previews only where it stops.
  Timer {
    id: previewTimer
    interval: 60
    onTriggered: {
      if (!root.open || !root.selected || root.selected.slug === root.previewed) return
      root.previewed = root.selected.slug
      root.changed = true
      root.run(["preview", root.address, root.app, root.selected.slug])
    }
  }

  Process {
    id: lister
    command: [root.script, "list"]
    stdout: StdioCollector {
      onStreamFinished: root.listed(this.text)
    }
  }

  IpcHandler {
    target: "sidebar-theme-picker"
    function open(payload: string): string { root.show(payload); return "ok" }
    function state(): string { return (root.open ? "open " : "closed ") + (root.selected ? root.selected.slug : "") }
  }

  PanelWindow {
    id: panel

    screen: {
      var screens = Quickshell.screens
      for (var i = 0; i < screens.length; i++) {
        if (screens[i].name === root.monitor) return screens[i]
      }
      return screens.length > 0 ? screens[0] : null
    }
    visible: root.open
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-sidebar-theme-picker"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    MouseArea {
      anchors.fill: parent
      onClicked: root.cancel()
    }

    Rectangle {
      id: card

      readonly property int gap: Style.space(24)
      readonly property bool sidebarRight: root.sidebarX + root.sidebarWidth / 2 > panel.width / 2

      width: Style.space(300)
      height: Math.min(Style.space(560), panel.height - Style.gapsOut * 2)
      anchors.verticalCenter: parent.verticalCenter
      // Beside the sidebar, on the side away from the nearer screen edge.
      x: sidebarRight
        ? Math.max(Style.gapsOut, root.sidebarX - width - gap)
        : Math.min(panel.width - width - Style.gapsOut, root.sidebarX + root.sidebarWidth + gap)
      radius: Style.cornerRadius
      color: Color.menu.background
      border.color: Color.menu.border
      border.width: Math.max(1, Style.space(2))

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keys
        anchors.fill: parent
        focus: true

        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.filter) root.filter = ""
            else root.cancel()
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.commit()
          } else if (event.key === Qt.Key_Up) {
            root.move(-1)
          } else if (event.key === Qt.Key_Down) {
            root.move(1)
          } else if (event.key === Qt.Key_PageUp) {
            root.move(-8)
          } else if (event.key === Qt.Key_PageDown) {
            root.move(8)
          } else if (event.key === Qt.Key_Home) {
            root.index = 0
          } else if (event.key === Qt.Key_End) {
            root.index = Math.max(0, root.shown.length - 1)
          } else if (event.key === Qt.Key_Backspace) {
            root.filter = root.filter.slice(0, -1)
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32
              && event.text.charCodeAt(0) !== 127
              && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
            root.filter += event.text
          } else {
            return
          }
          event.accepted = true
        }
      }

      Column {
        anchors.fill: parent
        anchors.margins: Style.spacing.panelPadding
        spacing: Style.space(8)

        Text {
          id: title
          width: parent.width
          textFormat: Text.PlainText
          text: root.filter ? root.filter : "Sidebar theme"
          color: root.filter ? Color.menu.text : Util.alpha(Color.menu.text, 0.6)
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.heading
          elide: Text.ElideRight
          padding: Style.space(6)
        }

        ListView {
          id: list
          width: parent.width
          height: parent.height - title.height - parent.spacing
          clip: true
          model: root.shown
          currentIndex: root.index
          highlightMoveDuration: 0
          boundsBehavior: Flickable.StopAtBounds
          onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

          delegate: Rectangle {
            id: row
            required property var modelData
            required property int index
            readonly property bool current: index === root.index

            width: ListView.view.width
            height: Style.space(40)
            radius: Style.cornerRadius
            color: current ? Color.menu.selectedBackground : "transparent"

            Text {
              anchors.left: parent.left
              anchors.right: mark.left
              anchors.leftMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: row.modelData.label
              color: row.current ? Color.menu.selectedText : Color.menu.text
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }

            // The theme these sidebars have now.
            Text {
              id: mark
              anchors.right: parent.right
              anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: row.modelData.slug === root.saved ? "" : ""
              color: row.current ? Color.menu.selectedText : Color.menu.text
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.body
            }

            MouseArea {
              anchors.fill: parent
              onClicked: {
                root.index = row.index
                root.commit()
              }
            }
          }

          // The wheel moves the highlight (and so the preview), a row at a time.
          WheelHandler {
            onWheel: function(event) {
              root.move(event.angleDelta.y > 0 ? -1 : 1)
            }
          }
        }
      }
    }
  }
}
