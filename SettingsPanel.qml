import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

// The sidebar settings (SUPER + ALT + S in a sidebar): the options worth
// flipping, as they are now, in the look of Omarchy's menus. Up/Down pick one,
// Left/Right (or Space/Enter, or a click) change it. Changes are saved a moment
// after the last one by bin/sidebar-settings, into
// ~/.config/omarchy/sidebar.lua, and Hyprland reloads to apply them, so they
// show while the panel stays open.
Scope {
  id: root

  property bool open: false
  property string monitor: ""
  property string script: ""
  property var values: ({})
  property var pending: ({}) // changed, not yet saved
  property int index: 0

  readonly property var rows: [
    { key: "drawer", label: "Drawer slide", hint: "Slide in from the screen edge it's docked to", type: "bool" },
    { key: "fade", label: "Fade", hint: "Fade in and out instead of Omarchy's slide (without the drawer)", type: "bool" },
    { key: "dim", label: "Dim behind", hint: "How much the rest of the screen dims", type: "number", min: 0, max: 1, step: 0.05, unit: "%", fallback: 0.55 },
    { key: "width", label: "Default width", hint: "A new sidebar's width, as a share of the screen", type: "number", min: 0.15, max: 0.9, step: 0.01, unit: "%", fallback: 0.33 },
    { key: "margin", label: "Margin", hint: "Gap to the screen edges and the bar", type: "number", min: 0, max: 120, step: 4, unit: "px", fallback: 32 },
    { key: "rounding", label: "Rounding", hint: "Corner radius", type: "number", min: 0, max: 50, step: 2, unit: "px", fallback: 32 },
    { key: "border", label: "Border colour", hint: "From the theme's colours", type: "enum", options: ["green", "cyan", "blue", "magenta", "red", "yellow", "foreground", "accent", "theme", "none"] },
    { key: "border_size", label: "Border width", hint: "Omarchy's windows have 2", type: "number", min: 1, max: 20, step: 1, unit: "px", fallback: 6 },
    { key: "border_opacity", label: "Border opacity", hint: "0 is clear, 100 solid", type: "number", min: 0, max: 1, step: 0.05, unit: "%", fallback: 1 },
    { key: "shadow", label: "Shadow", hint: "A large, faint shadow around sidebars", type: "bool" },
    { key: "click_outside", label: "Click outside hides", hint: "A click outside the sidebar hides it", type: "bool" },
    { key: "switcher", label: "Super + Tab previews", hint: "Live previews while Super is held", type: "bool" },
    { key: "switcher_style", label: "Preview style", hint: "Super + T swaps them while previews show", type: "enum", options: ["cards", "coverflow"] },
    { key: "floating_keys", label: "Keys for floating windows", hint: "Super + Shift + arrows move, Super + Alt + arrows stretch any floating window", type: "bool" }
  ]

  function show(payload) {
    var p = JSON.parse(payload)
    monitor = String(p.monitor || "")
    script = String(p.script || "")
    values = p.values || {}
    pending = {}
    open = true
    keys.forceActiveFocus()
  }

  function close() {
    save()
    open = false
  }

  function shown(row) {
    var v = values[row.key]
    if (row.type === "bool") return v === true ? "On" : "Off"
    if (row.type === "enum") return String(v)
    if (typeof v !== "number") return "Omarchy's"
    return row.unit === "%" ? Math.round(v * 100) + "%" : Math.round(v) + " px"
  }

  function change(row, step) {
    var v = values[row.key]
    if (row.type === "bool") {
      v = !(v === true)
    } else if (row.type === "enum") {
      var i = row.options.indexOf(String(v))
      v = row.options[((i < 0 ? 0 : i + step) + row.options.length) % row.options.length]
    } else {
      if (typeof v !== "number") v = row.fallback
      else v = Math.min(row.max, Math.max(row.min, Math.round((v + step * row.step) / row.step) * row.step))
      v = Math.round(v * 1000) / 1000
    }
    var copy = Object.assign({}, values)
    copy[row.key] = v
    values = copy
    var p = Object.assign({}, pending)
    p[row.key] = v
    pending = p
    saver.restart()
  }

  function save() {
    saver.stop()
    var args = []
    for (var k in pending) args.push(k, String(pending[k]))
    pending = {}
    if (args.length > 0) Quickshell.execDetached([script, "set"].concat(args))
  }

  // Changes made in a row (holding a key) go out together.
  Timer {
    id: saver
    interval: 600
    onTriggered: root.save()
  }

  IpcHandler {
    target: "sidebar-settings"
    function open(payload: string): string { root.show(payload); return "ok" }
    function close(): string { root.close(); return "ok" }
    function state(): string { return (root.open ? "open " : "closed ") + root.index + " " + JSON.stringify(root.values) }
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
    WlrLayershell.namespace: "omarchy-sidebar-settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    readonly property int rowHeight: Math.max(Style.space(54), Style.font.body + Style.font.caption + Style.spacing.rowPaddingX * 2)

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    Rectangle {
      id: card

      width: Math.min(Style.space(560), panel.width - Style.gapsOut * 2)
      height: Math.min(panel.height - Style.gapsOut * 2, column.implicitHeight + Style.spacing.panelPadding * 2)
      anchors.centerIn: parent
      radius: Style.cornerRadius
      color: Util.alpha(Color.menu.background, 0.97)
      border.color: Color.menu.border
      border.width: Math.max(1, Style.space(2))

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keys
        anchors.fill: parent
        focus: true

        Keys.onPressed: function(event) {
          var row = root.rows[root.index]
          if (event.key === Qt.Key_Escape) {
            root.close()
          } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) {
            root.index = Math.max(0, root.index - 1)
          } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
            root.index = Math.min(root.rows.length - 1, root.index + 1)
          } else if (event.key === Qt.Key_Left) {
            root.change(row, -1)
          } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Space
              || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.change(row, 1)
          } else {
            return
          }
          event.accepted = true
        }
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.spacing.panelPadding
        spacing: Style.space(2)

        Text {
          width: parent.width
          height: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
          verticalAlignment: Text.AlignVCenter
          textFormat: Text.PlainText
          text: "Sidebar settings"
          color: Color.menu.text
          opacity: 0.58
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.heading
        }

        Repeater {
          model: root.rows

          delegate: Rectangle {
            id: row
            required property var modelData
            required property int index
            readonly property bool current: index === root.index

            width: column.width
            height: panel.rowHeight
            radius: Style.cornerRadius
            color: current ? Color.menu.selectedBackground : "transparent"

            Column {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(14)
              anchors.right: value.left
              anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: row.modelData.label
                color: row.current ? Color.menu.selectedText : Color.menu.text
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.body
                font.weight: Font.Medium
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: row.modelData.hint
                color: row.current ? Color.menu.selectedText : Color.menu.text
                opacity: 0.52
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }
            }

            Text {
              id: value
              anchors.right: parent.right
              anchors.rightMargin: Style.space(14)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: (row.modelData.type === "bool" ? "" : "‹  ") + root.shown(row.modelData) + (row.modelData.type === "bool" ? "" : "  ›")
              color: row.current ? Color.menu.selectedText : Color.menu.text
              opacity: row.modelData.type === "bool" && root.values[row.modelData.key] !== true ? 0.5 : 1
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.body
            }

            // A click on the left half steps down, anywhere else steps up.
            MouseArea {
              anchors.fill: parent
              onClicked: function(mouse) {
                root.index = row.index
                root.change(row.modelData, row.modelData.type !== "bool" && mouse.x < width / 2 ? -1 : 1)
              }
            }
          }
        }

        Text {
          width: parent.width
          topPadding: Style.space(8)
          textFormat: Text.PlainText
          text: "↑↓ choose · ←→ change · Esc close · saved to ~/.config/omarchy/sidebar.lua"
          color: Color.menu.text
          opacity: 0.45
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.bodySmall
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
        }
      }
    }
  }
}
