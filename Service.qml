import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Omarchy shell plugins can't ship Hyprland config, so this service loads
// hypr/sidebar.lua into the running Hyprland with `hyprctl eval`: once at start
// and again after every config reload (which discards anything loaded at
// runtime). Failures are shown as a "Sidebar" notification.
Item {
  id: root

  // Injected by omarchy-shell.
  property var shell: null

  readonly property string pluginDir: decodeURIComponent(Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "")).replace(/\/$/, "")

  // A Lua long-bracket string that can hold any path: [==[ ... ]==] with
  // enough "=" that the path can't close it early.
  function luaString(value) {
    var level = ""
    while (value.indexOf("]" + level + "]") !== -1) level += "="
    return "[" + level + "[" + value + "]" + level + "]"
  }

  // Loads sidebar.lua unless this exact source is already loaded. Changed source
  // (a plugin update) can't be loaded over the old one, whose handlers stay
  // registered, so it reloads Hyprland, which brings it back here fresh.
  function load() {
    if (loader.running) {
      loader.pending = true
      return
    }
    loader.command = ["hyprctl", "eval",
      "SIDEBAR_DIR = " + luaString(root.pluginDir) + "; " +
      "local f = io.open(SIDEBAR_DIR .. '/hypr/sidebar.lua'); " +
      "local source = f and f:read('a'); if f then f:close() end; " +
      "if SIDEBAR_LOADED and SIDEBAR_SOURCE ~= source then SIDEBAR_SOURCE = source; hl.exec_cmd('hyprctl reload'); return end; " +
      "SIDEBAR_SOURCE = source; " +
      "local ok, err = pcall(dofile, SIDEBAR_DIR .. '/hypr/sidebar.lua'); " +
      "if not ok then error(err, 0) end"]
    loader.running = true
  }

  function report(message) {
    console.warn("sidebar: loading into Hyprland failed: " + message)
    Quickshell.execDetached(["notify-send", "-a", "Sidebar", "--", "Sidebar failed to load", message])
  }

  // Hyprland may not answer yet right at shell start; try a few more times
  // before reporting that.
  property int connectRetries: 0
  Timer {
    id: retry
    interval: 1000
    onTriggered: root.load()
  }

  Process {
    id: loader
    property bool pending: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var result = text.trim()
        if (result === "ok" || result === "") {
          root.connectRetries = 0
        } else if (result.indexOf("Couldn't connect") === 0 && root.connectRetries < 5) {
          root.connectRetries += 1
          retry.restart()
        } else {
          root.report(result)
        }
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (text.trim() !== "") root.report(text.trim())
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

  // The shell destroys services on every plugin rescan and restart, not only
  // when this plugin is disabled. So wait, and unload only if it really is
  // disabled or removed: hand sidebar windows back to the workspace first (or
  // they'd stay hidden with no key to show them), then reload Hyprland to drop
  // the keys and handlers.
  // The shell answers plugin queries only once it is up again, so keep asking
  // for a while; without a clear "not enabled" answer, leave everything as is.
  Component.onDestruction: Quickshell.execDetached(["bash", "-c",
    "sleep 3; " +
    "for i in $(seq 30); do out=$(omarchy plugin list --json 2>/dev/null) && [ -n \"$out\" ] && break; out=; sleep 1; done; " +
    "[ -n \"$out\" ] || exit 0; " +
    "jq -e 'type == \"array\"' >/dev/null <<<\"$out\" || exit 0; " +
    "jq -e '.[] | select(.id == \"sidebar\" and .enabled)' >/dev/null <<<\"$out\" && exit 0; " +
    "hyprctl eval 'if sidebar then sidebar.release() end' >/dev/null; sleep 0.5; hyprctl reload >/dev/null"])
}
