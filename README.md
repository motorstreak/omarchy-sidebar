# Omarchy Sidebar

Turn any window into a **sidebar**: docked to the left or right screen edge,
floating over your workspace, dimming everything behind it, and shown or hidden
with one key. Includes an **agent sidebar** for your Omarchy default coding
agent, with saved, searchable sessions when that agent is Claude Code.

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
| `Super + Alt + B` | Turn the focused window into the sidebar, or the sidebar back into a window |
| `Super + B` | Show/hide the sidebar |
| `Super + A` | Show/hide the agent sidebar (launches it the first time) |
| `Super + Shift + A` | New agent session (Claude: named with the date and time) |
| `Super + Alt + A` | Pick a saved session, Claude only (type to search its prompts) |
| `Super + Ctrl + Alt + A` | Reset the agent sidebar to its docked spot and size |

Inside a sidebar that has focus:

| Key | Action |
|---|---|
| `Escape` or a click outside it | Hide it (the click still reaches what you clicked) |
| `Super + Shift + Left/Right` | Dock it to that edge, keeping its size (the side is remembered) |
| `Super + Minus / Equal` | Wider / narrower, staying docked (`Alt` small steps, `Ctrl` big steps) |
| `Super + Shift + Minus / Equal` | Shorter / taller; the top edge stays put |
| `Super + Shift + 1…0` | Move it to a workspace as a normal window |

A hidden sidebar is still there: `Super + B` (or `Super + A`) brings it back.

There is one generic sidebar at a time: converting a second window sends the
first back to your workspace. The agent sidebar has its own slot.

While a sidebar has focus, `Escape` doesn't reach the app in it (a browser's
find bar or fullscreen video, or Claude's interrupt: use `Ctrl + C` in Claude,
or turn Escape off per sidebar in the config). Clicks on the bar, its panels,
menus and notifications don't hide a sidebar; neither do keys or clicks while a
launcher, menu or screenshot selector is open. A click on an app's own menu
that reaches past the sidebar's edge counts as outside it and hides it.

### Keys the plugin uses

- `Super + Shift + A` replaces Omarchy's ChatGPT key, and every key option
  replaces whatever was bound to that key before.
- While a sidebar has focus, the plugin takes over plain `Escape`, plain left
  click, and Omarchy's resize (`Super + [Shift/Alt/Ctrl] + Minus/Equal`) and
  swap (`Super + Shift + arrows`) keys. Everywhere else those are Omarchy's own
  bindings: they start out untouched, and after a sidebar has had focus they
  are re-bound exactly as Omarchy defines them. So if you've customised those
  resize or swap keys (or bound plain `Escape` or left click yourself), your
  version is replaced by Omarchy's until Hyprland reloads. With
  `omarchy_default_bindings = false` the resize and swap keys are left alone.

## Configure

Create `~/.config/omarchy/sidebar.lua` returning the options to change, then
reload Hyprland (save any Hyprland config file, or `hyprctl reload`). All
options, with their defaults:

```lua
return {
  width = 0.33,          -- default width as a share of the screen
  margin = 24,           -- gap to screen edges and the bar (0-200)
  dim = true,            -- dim the rest of the screen while a sidebar shows
  click_outside = true,  -- clicking outside a sidebar hides it
  sidebar = {
    toggle = "SUPER + B",
    convert = "SUPER + ALT + B",
    escape = true,       -- Escape hides it (false: Escape reaches the app)
  },
  agent = {
    enabled = true,      -- false leaves out the agent sidebar
    class = "sidebar.agent", -- window class of the agent's terminal
    toggle = "SUPER + A",
    new = "SUPER + SHIFT + A", -- false keeps Omarchy's ChatGPT key
    load = "SUPER + ALT + A",
    reset = "SUPER + CTRL + ALT + A",
    escape = true,       -- false: Escape reaches the agent (e.g. Claude's interrupt)
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
one and starts it fresh, without asking.

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
