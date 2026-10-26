import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

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
  property var colours: [] // [{ name, label, hex }]: the border colours of this sidebar's theme
  property string theme: "" // this sidebar's own theme, if it has one
  property var pending: ({}) // changed, not yet saved
  property int index: 0
  property string lastColour: "accent"
  property var defaults: ({})
  property bool confirming: false // "Reset to defaults" pressed once
  // The rows, "Window style…" (with the Window Style plugin), then "Reset to
  // defaults".
  readonly property int extra: styled ? 1 : 0
  readonly property int count: rows.length + extra + 1

  // A row that does nothing while the switch it needs is off.
  function enabled(row) {
    return !row.needs || values[row.needs] === true
  }
  // Applied as they change, not only once saved.
  readonly property var live: ["dim", "margin", "rounding", "border", "border_size", "border_opacity"]

  // With the Window Style plugin the look rows are in its panel (the last row
  // here opens it).
  property bool styled: false
  readonly property var rows: styled ? allRows.filter(function(r) { return !r.look }) : allRows
  readonly property var allRows: [
    { key: "drawer", label: "Drawer slide", hint: "Slide in from the screen edge it's docked to", type: "bool" },
    { key: "fade", label: "Fade", hint: "Fade in and out instead of Omarchy's slide (without the drawer)", type: "bool" },
    { look: true, key: "dim", label: "Dim behind", hint: "How much the rest of the screen dims", type: "number", min: 0, max: 1, step: 0.05, unit: "%", fallback: 0.55 },
    { key: "width", label: "Default width", hint: "A new sidebar's width, as a share of the screen", type: "number", min: 0.15, max: 0.9, step: 0.01, unit: "%", fallback: 0.33 },
    { look: true, key: "margin", label: "Margin", hint: "Gap to the screen edges and the bar", type: "number", min: 0, max: 120, step: 4, unit: "px", fallback: 32 },
    { look: true, key: "rounding", label: "Rounding", hint: "Corner radius", type: "number", min: 0, max: 50, step: 2, unit: "px", fallback: 32 },
    { look: true, key: "border_on", label: "Border", hint: "Off: no border, whatever the options below say", type: "bool" },
    { look: true, key: "border", label: "Border colour", hint: "From the theme's colours", type: "colour", needs: "border_on" },
    { look: true, key: "border_size", label: "Border width", hint: "Omarchy's windows have 2", type: "number", min: 1, max: 20, step: 1, unit: "px", fallback: 6, needs: "border_on" },
    { look: true, key: "border_opacity", label: "Border opacity", hint: "0 is clear, 100 solid", type: "number", min: 0, max: 1, step: 0.05, unit: "%", fallback: 1, needs: "border_on" },
    { look: true, key: "shadow", label: "Shadow", hint: "A large, faint shadow around sidebars (with the Dock, its glow)", type: "bool" },
    { key: "click_outside", label: "Click outside hides", hint: "A click outside the sidebar hides it", type: "bool" },
    { key: "switcher", label: "Switcher previews", hint: "Live previews while Super is held", type: "bool" },
    { key: "switcher_style", label: "Preview style", hint: "Super + T swaps them while previews show", type: "enum", options: ["cards", "coverflow"], needs: "switcher" },
    { key: "follow_theme", label: "Follow system theme", hint: "Every sidebar in the system theme; themes picked per app (Super + Alt + T) are set aside", type: "bool" },
    { key: "floating_keys", label: "Keys for floating windows", hint: "Super + Shift + arrows move, Super + Alt + arrows stretch any floating window", type: "bool" }
  ]

  function show(payload) {
    var p = JSON.parse(payload)
    monitor = String(p.monitor || "")
    script = String(p.script || "")
    // The switch is `border` being "none"; turned on again, the colour it had.
    defaults = p.defaults || {}
    styled = p.styled === true
    confirming = false
    var v = Object.assign({}, p.values || {})
    v.border_on = v.border !== "none"
    lastColour = typeof v.border === "string" && v.border !== "none" ? v.border : "accent"
    values = v
    colours = Array.isArray(p.colours) ? p.colours : []
    theme = String(p.theme || "")
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
    if (row.type === "colour") {
      var c = colourOf(v)
      return c ? c.label : String(v)
    }
    if (typeof v !== "number") return "Omarchy's"
    return row.unit === "%" ? Math.round(v * 100) + "%" : Math.round(v) + " px"
  }

  function colourOf(name) {
    for (var i = 0; i < colours.length; i++) {
      if (colours[i].name === name) return colours[i]
    }
    return null
  }

  function change(row, step) {
    if (!enabled(row)) return
    if (row.key === "border_on") {
      var on = values.border_on !== true
      var c = Object.assign({}, values)
      c.border_on = on
      if (!on && typeof c.border === "string" && c.border !== "none") lastColour = c.border
      c.border = on ? lastColour : "none"
      values = c
      row = { key: "border" }
      var q = Object.assign({}, pending)
      q.border = c.border
      pending = q
      saver.restart()
      apply("border", c.border)
      return
    }
    var v = values[row.key]
    if (row.type === "colour") {
      var at = -1
      for (var j = 0; j < colours.length; j++) {
        if (colours[j].name === String(v)) at = j
      }
      v = colours[((at < 0 ? 0 : at + step) + colours.length) % colours.length].name
    } else if (row.type === "bool") {
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
    apply(row.key, v)
  }

  // The dim and the sidebars' look show at once; the rest once saved
  // (Hyprland reloads).
  function apply(key, v) {
    if (live.indexOf(key) >= 0)
      Quickshell.execDetached(["hyprctl", "eval", "sidebar.set_live('" + key + "', "
        + (typeof v === "string" ? "'" + v + "'" : String(v)) + ")"])
  }

  // Every option back to its default: shown at once (the live ones applied),
  // and their lines taken out of the file.
  function reset() {
    saver.stop()
    pending = {}
    var v = Object.assign({}, defaults)
    v.border_on = v.border !== "none"
    if (v.border_on) lastColour = String(v.border)
    values = v
    for (var i = 0; i < live.length; i++) {
      if (defaults[live[i]] !== undefined) apply(live[i], defaults[live[i]])
    }
    Quickshell.execDetached([script, "reset"])
    confirming = false
  }

  function activate(step) {
    if (styled && index === rows.length) {
      close()
      Quickshell.execDetached(["hyprctl", "eval", "window_style.open('sidebars')"])
      return
    }
    if (index >= rows.length) {
      if (confirming) reset()
      else confirming = true
    } else {
      change(rows[index], step)
    }
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
      color: Commons.Color.menu.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    BorderSurface {
      id: card

      width: Math.min(Style.space(560), panel.width - Style.gapsOut * 2)
      height: Math.min(panel.height - Style.gapsOut * 2, column.implicitHeight + Style.spacing.panelPadding * 2)
      anchors.centerIn: parent
      radius: Style.cornerRadius
      // As Omarchy's menus: their background, border and its width from
      // shell.toml's [menu] (the Window Style plugin's Menus tab).
      color: Commons.Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Commons.Color.menu.border, Math.max(1, Style.space(2)))

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keys
        anchors.fill: parent
        focus: true

        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.confirming) root.confirming = false
            else root.close()
          } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) {
            root.index = Math.max(0, root.index - 1)
            root.confirming = false
          } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
            root.index = Math.min(root.count - 1, root.index + 1)
          } else if (event.key === Qt.Key_Left) {
            if (root.index < root.rows.length) root.activate(-1)
          } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Space
              || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.activate(1)
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
          color: Commons.Color.menu.text
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
            color: current ? Commons.Color.menu.selectedBackground : "transparent"
            opacity: root.enabled(row.modelData) ? 1 : 0.4

            Column {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(14)
              anchors.right: value.left
              anchors.rightMargin: Style.space(40)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: row.modelData.label
                color: row.current ? Commons.Color.menu.selectedText : Commons.Color.menu.text
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.body
                font.weight: Font.Medium
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: row.modelData.key === "border" && root.theme
                  ? "From this sidebar's theme, " + root.theme : row.modelData.hint
                color: row.current ? Commons.Color.menu.selectedText : Commons.Color.menu.text
                opacity: 0.52
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }
            }

            // The border colour as this sidebar shows it.
            Rectangle {
              visible: row.modelData.type === "colour" && color.a > 0
              anchors.right: value.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(18)
              height: width
              radius: width / 4
              color: (root.colourOf(root.values.border) || {}).hex || "transparent"
              border.color: Util.alpha(Commons.Color.menu.text, 0.3)
              border.width: 1
            }

            Text {
              id: value
              anchors.right: parent.right
              anchors.rightMargin: Style.space(14)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: (row.modelData.type === "bool" ? "" : "‹  ") + root.shown(row.modelData) + (row.modelData.type === "bool" ? "" : "  ›")
              color: row.current ? Commons.Color.menu.selectedText : Commons.Color.menu.text
              opacity: row.modelData.type === "bool" && root.values[row.modelData.key] !== true ? 0.5 : 1
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.body
            }

            // A click on the left half steps down, anywhere else steps up.
            MouseArea {
              anchors.fill: parent
              onClicked: function(mouse) {
                root.index = row.index
                root.confirming = false
                root.change(row.modelData, row.modelData.type !== "bool" && mouse.x < width / 2 ? -1 : 1)
              }
            }
          }
        }

        Rectangle {
          visible: root.styled
          readonly property bool current: root.index === root.rows.length
          width: column.width
          height: visible ? Math.max(Style.space(40), Style.font.body + Style.spacing.rowPaddingX * 2) : 0
          radius: Style.cornerRadius
          color: current ? Commons.Color.menu.selectedBackground : "transparent"

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(14)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "Window style…  (border, rounding, shadow, dim, margin)"
            color: parent.current ? Commons.Color.menu.selectedText : Commons.Color.menu.text
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.body
            font.weight: Font.Medium
          }

          MouseArea {
            anchors.fill: parent
            onClicked: {
              root.index = root.rows.length
              root.activate(1)
            }
          }
        }

        Rectangle {
          readonly property bool current: root.index === root.rows.length + root.extra
          width: column.width
          height: Math.max(Style.space(40), Style.font.body + Style.spacing.rowPaddingX * 2)
          radius: Style.cornerRadius
          color: current ? Commons.Color.menu.selectedBackground : "transparent"

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(14)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.confirming ? "Press again to reset every option above" : "Reset to defaults"
            color: parent.current ? Commons.Color.menu.selectedText : Commons.Color.menu.text
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.body
            font.weight: Font.Medium
          }

          MouseArea {
            anchors.fill: parent
            onClicked: {
              root.index = root.rows.length + root.extra
              root.activate(1)
            }
          }
        }

        Text {
          width: parent.width
          topPadding: Style.space(8)
          textFormat: Text.PlainText
          text: "↑↓ choose · ←→ change · Esc close · saved to ~/.config/omarchy/sidebar.lua"
          color: Commons.Color.menu.text
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
