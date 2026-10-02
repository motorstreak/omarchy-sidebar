import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Omarchy shell plugins can't ship Hyprland config, so this service loads
// hypr/sidebar.lua into the running Hyprland with `hyprctl eval`: once at start
// and again after every config reload (which discards anything loaded at
// runtime). Disabling the plugin reloads Hyprland to drop it all again.
Item {
  id: root

  // Injected by omarchy-shell.
  property var shell: null

  readonly property string pluginDir: decodeURIComponent(Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "")).replace(/\/$/, "")

  function load() {
    if (loader.running) {
      loader.pending = true
      return
    }
    loader.command = ["hyprctl", "eval",
      "SIDEBAR_DIR = [[" + root.pluginDir + "]]; dofile(SIDEBAR_DIR .. '/hypr/sidebar.lua')"]
    loader.running = true
  }

  Process {
    id: loader
    property bool pending: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (text.trim() !== "ok") console.warn("sidebar: loading into Hyprland failed: " + text.trim())
      }
    }
    onExited: function() {
      if (pending) {
        pending = false
        root.load()
      }
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (String(event && event.name ? event.name : "") === "configreloaded") root.load()
    }
  }

  Component.onCompleted: load()
  Component.onDestruction: Quickshell.execDetached(["hyprctl", "reload"])
}
