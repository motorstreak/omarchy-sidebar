# Omarchy Sidebar

Turn any window into a **sidebar**: docked to the left or right screen edge,
floating over your workspace, dimming everything behind it, and shown or hidden
with one key. Includes an **agent sidebar** for your Omarchy default coding
agent, with saved, searchable sessions when that agent is Claude Code.

Move a sidebar to a regular workspace and it becomes an ordinary window again,
following every normal Omarchy binding. Turn it back into a sidebar any time.

## Install

```bash
omarchy plugin add https://github.com/<you>/omarchy-sidebar.git --enable
```

Remove it with `omarchy plugin remove sidebar`; its keys and behaviour go away
immediately.

## Keys

| Key | Action |
|---|---|
| `Super + Alt + B` | Turn the focused window into the sidebar, or the sidebar back into a window |
| `Super + B` | Show/hide the sidebar |
| `Super + A` | Show/hide the agent sidebar (launches it the first time) |
| `Super + Shift + A` | New agent session (Claude: named with the date and time) |
| `Super + Alt + A` | Pick a saved session, Claude only (type to search all its prompts) |
| `Super + Ctrl + Alt + A` | Reset the agent sidebar to its docked spot and size |
| `Escape` | Hide the agent sidebar while it has focus |

Inside any sidebar:

| Key | Action |
|---|---|
| `Super + Shift + Left/Right` | Dock to that edge, keeping its size (remembered) |
| `Super + Minus / Equal` | Wider / narrower, staying docked (`Alt` small steps, `Ctrl` big steps) |
| `Super + Shift + Minus / Equal` | Shorter / taller from the top edge |
| `Super + Shift + 1…0` | Move it to a workspace as a normal tiled window |

There is one generic sidebar at a time: converting a second window sends the
first back to your workspace. The agent sidebar has its own slot.

**Note:** the plugin re-binds `Super + Shift + A` (Omarchy's ChatGPT key) and
wraps Omarchy's resize (`Super + [Shift/Alt/Ctrl] + Minus/Equal`) and swap
(`Super + Shift + arrows`) keys. Those behave exactly as before for every window
that isn't a sidebar.

## Configure

Create `~/.config/omarchy/sidebar.lua` returning any options to override, then
reload Hyprland (save any Hyprland config file, or `hyprctl reload`):

```lua
return {
  width = 0.4,               -- default width as a share of the screen
  margin = 16,               -- gap to screen edges and the bar
  dim = false,               -- don't dim behind sidebars
  sidebar = { escape = true }, -- Escape also hides the generic sidebar
  agent = {
    toggle = "SUPER + C",    -- any key can be changed, or set to false
    new = false,             -- keep Omarchy's ChatGPT key
  },
}
```

Set `agent = { enabled = false }` to leave out the agent sidebar.

## The agent sidebar

It runs your Omarchy default coding agent (`omarchy default agent <name>`; with
none set, `Super + A` offers the choice). Agents start through Omarchy's own
launcher, exactly as `Super + Shift + Ctrl + A` starts them.

Claude Code is the exception, because Omarchy's launcher can't pass it session
options: Claude is run directly, pinned to one session, so closing the sidebar
and pressing `Super + A` resumes the same conversation. New sessions are named
with the date and time and show up in the `Super + Alt + A` menu and in
Claude's `/resume` picker. It uses your normal Claude settings rather than the
auto permission mode Omarchy's launcher starts Claude in.

## Requirements

Omarchy with Hyprland's Lua config (Hyprland 0.55+). The agent sidebar needs
a default agent installed (`omarchy default agent`); it runs in `~/Work` if it
exists, otherwise your home folder.

## How it works

Omarchy shell plugins can't ship Hyprland config, so the plugin's service loads
`hypr/sidebar.lua` into the running Hyprland with `hyprctl eval` at start and
after every Hyprland config reload. State (pinned Claude session, remembered
sides) lives in `~/.local/state/omarchy-sidebar/`.
