# Omarchy Sidebar

Turn any window into the **sidebar**: docked to the left or right screen edge,
floating over your workspace, dimming everything behind it, and shown or hidden
with one key. One key also makes your Omarchy default coding agent the sidebar,
with saved, searchable sessions when that agent is Claude Code.

There is only ever one sidebar: making a window the sidebar (including the
agent) sends the previous one back to your workspace as a normal window. Its
border uses your theme's foreground colour, so it's easy to tell apart from
normal windows wherever it is.

Move a sidebar to a regular workspace and it becomes an ordinary window again,
following every normal Omarchy binding. Turn it back into a sidebar any time.

## Install

```bash
omarchy plugin add https://github.com/motorstreak/omarchy-sidebar.git --enable
```

Update with `omarchy plugin update sidebar`; if an update changes
`Service.qml`, also run `omarchy restart shell`.

Remove it with `omarchy plugin remove sidebar`, or disable it with
`omarchy plugin disable sidebar`. A few seconds later, sidebar windows return
to your workspace as normal windows and the plugin's keys and behaviour go
away. Its saved state in `~/.local/state/omarchy-sidebar/` is left in place.

## Keys

| Key | Action |
|---|---|
| `Super + Alt + B` | Make the focused window the sidebar, or the sidebar a normal window again |
| `Super + B` | Show/hide the sidebar, whichever window it is |
| `Super + A` | Make the agent the sidebar and show it (launching it if needed); hide it if it's already showing |
| `Super + Shift + A` | New agent session (Claude: named with the date and time) |
| `Super + Alt + A` | Pick a saved session, Claude only (type to search its prompts) |
| `Super + Ctrl + Alt + A` | Make the agent the sidebar at its default docked spot and size |

Inside a sidebar that has focus:

| Key | Action |
|---|---|
| `Super + Escape` or a click outside it | Hide it (the click still reaches what you clicked) |
| `Super + Shift + Left/Right` | Dock it to that edge, keeping its size (the side is remembered, separately for the agent and other windows) |
| `Super + Minus / Equal` | Wider / narrower, staying docked (`Alt` small steps, `Ctrl` big steps) |
| `Super + Shift + Minus / Equal` | Shorter / taller; the top edge stays put |
| `Super + Shift + 1…0` | Move it to a workspace as a normal window |

A hidden sidebar is still there: `Super + B` (or `Super + A`) brings it back.

Plain `Escape` always reaches the app in the sidebar. While a sidebar has
focus, `Super + Escape` hides it instead of opening Omarchy's system menu (hide
the sidebar first, or turn this off per sidebar in the config). Clicks on the bar, its panels,
menus and notifications don't hide a sidebar; neither do keys or clicks while a
launcher, menu or screenshot selector is open. A click on an app's own menu
that reaches past the sidebar's edge counts as outside it and hides it.

A window that stops being the sidebar gets your theme's normal border colours
(the first colour of a gradient border), replacing any border colour a window
rule had given it; they follow theme changes while the plugin is installed.

### Keys the plugin uses

- `Super + Shift + A` replaces Omarchy's ChatGPT key, and every key option
  replaces whatever was bound to that key before.
- While a sidebar has focus, the plugin takes over `Super + Escape` (Omarchy's
  system menu), plain left click, and Omarchy's resize (`Super + [Shift/Alt/Ctrl] + Minus/Equal`) and
  swap (`Super + Shift + arrows`) keys. Everywhere else those are Omarchy's own
  bindings: they start out untouched, and after a sidebar has had focus they
  are re-bound exactly as Omarchy defines them. So if you've customised the
  system menu, resize or swap keys (or bound plain left click yourself), your
  version is replaced by Omarchy's until Hyprland reloads. With
  `omarchy_default_bindings = false` Omarchy's keys are left alone.

## Configure

Create `~/.config/omarchy/sidebar.lua` returning the options to change, then
reload Hyprland (save any Hyprland config file, or `hyprctl reload`). All
options, with their defaults:

```lua
return {
  width = 0.33,          -- default width as a share of the screen
  margin = 24,           -- gap to screen edges and the bar (0-200)
  dim = true,            -- dim the rest of the screen while a sidebar shows
  border = "theme",      -- sidebar border: "theme" (foreground colour), "#14B9B5", or false
  click_outside = true,  -- clicking outside a sidebar hides it
  sidebar = {
    toggle = "SUPER + B",
    convert = "SUPER + ALT + B",
    escape = true,       -- Super + Escape hides it (false: it opens the system menu)
  },
  agent = {
    enabled = true,      -- false leaves out the agent sidebar
    class = "sidebar.agent", -- window class of the agent's terminal
    toggle = "SUPER + A",
    new = "SUPER + SHIFT + A", -- false keeps Omarchy's ChatGPT key
    load = "SUPER + ALT + A",
    reset = "SUPER + CTRL + ALT + A",
    escape = true,       -- Super + Escape hides it (false: it opens the system menu)
  },
}
```

Any key can be changed or set to `false` to leave it unbound. A key that's
already bound (for example `SUPER + C`, Omarchy's copy) is replaced. Mistakes
in the file are shown as a "Sidebar" notification.

## The agent sidebar

It runs your Omarchy default coding agent, set with
`omarchy default agent <name>`. With none set, `Super + A` opens Omarchy's agent
chooser (which starts the chosen agent in a normal window; press `Super + A`
again for the sidebar). Agents start through Omarchy's own launcher, exactly as
`Super + Shift + Ctrl + A` starts them; `Super + Shift + A` closes the running
one and starts it fresh, without asking. Like any sidebar, the agent replaces
whatever window was the sidebar, which goes back to your workspace.

Claude Code is the exception, because Omarchy's launcher can't pass it session
options: Claude is run directly, pinned to one session, so closing the sidebar
and pressing `Super + A` resumes the same conversation. New sessions are named
with the date and time and, once they have a message, show up in the
`Super + Alt + A` menu (the newest 50; type to search their prompts) and in
Claude's `/resume` picker. Renaming one with Claude's `/rename` takes it out of
the menu. It uses your normal Claude settings rather than the auto permission
mode Omarchy's launcher starts Claude in.

## Requirements

Omarchy with Hyprland's Lua config (tested on Hyprland 0.56). The agent
sidebar needs a default agent installed (`omarchy default agent`). Like
Omarchy's own agent launcher, it runs in `~/Work` if that exists, otherwise in
your home folder (where Claude asks to trust the folder each time).

## How it works

Omarchy shell plugins can't ship Hyprland config, so the plugin's service loads
`hypr/sidebar.lua` into the running Hyprland with `hyprctl eval` at start and
after every Hyprland config reload; after a plugin update it reloads Hyprland
once to pick up the new code. Problems are shown as a "Sidebar" notification.
State (pinned Claude session, remembered sides) lives in
`$XDG_STATE_HOME/omarchy-sidebar/` (normally `~/.local/state`).
