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

Remove it with `omarchy plugin remove sidebar` (or disable it with
`omarchy plugin disable sidebar`): sidebar windows return to your workspace as
normal windows, and its keys and behaviour go away.

## Keys

| Key | Action |
|---|---|
| `Super + Alt + B` | Turn the focused window into the sidebar, or the sidebar back into a window |
| `Super + B` | Show/hide the sidebar |
| `Super + A` | Show/hide the agent sidebar (launches it the first time) |
| `Super + Shift + A` | New agent session (Claude: named with the date and time) |
| `Super + Alt + A` | Pick a saved session, Claude only (type to search its prompts) |
| `Super + Ctrl + Alt + A` | Reset the agent sidebar to its docked spot and size |
| `Escape` | Hide any sidebar while it has focus (in the agent sidebar, use `Ctrl + C` to stop Claude mid-answer) |

Inside any sidebar:

| Key | Action |
|---|---|
| `Super + Shift + Left/Right` | Dock to that edge, keeping its size (remembered) |
| `Super + Minus / Equal` | Wider / narrower, staying docked (`Alt` small steps, `Ctrl` big steps) |
| `Super + Shift + Minus / Equal` | Shorter / taller from the top edge |
| `Super + Shift + 1…0` | Move it to a workspace as a normal tiled window |

There is one generic sidebar at a time: converting a second window sends the
first back to your workspace. The agent sidebar has its own slot.

While a sidebar has focus, `Escape` hides it instead of reaching the app (a
browser's find bar or fullscreen video, for example), and so does clicking
anywhere outside it (the click still reaches what you clicked). Turn these off
in the config below. A hidden sidebar is still there: `Super + B` (or
`Super + A`) brings it back.

**Note:** the plugin re-binds `Super + Shift + A` (Omarchy's ChatGPT key). The
resize (`Super + [Shift/Alt/Ctrl] + Minus/Equal`) and swap
(`Super + Shift + arrows`) keys are only taken over while a sidebar has focus;
everywhere else they are Omarchy's own bindings, untouched.

## Configure

Create `~/.config/omarchy/sidebar.lua` returning any options to override, then
reload Hyprland (save any Hyprland config file, or `hyprctl reload`):

```lua
return {
  width = 0.4,               -- default width as a share of the screen
  margin = 16,               -- gap to screen edges and the bar
  dim = false,               -- don't dim behind sidebars
  click_outside = false,     -- clicking outside a sidebar doesn't hide it
  sidebar = { escape = false }, -- let Escape reach the app in the sidebar
  agent = {
    toggle = "SUPER + C",    -- any key can be changed, or set to false
    new = false,             -- keep Omarchy's ChatGPT key
  },
}
```

Set `agent = { enabled = false }` to leave out the agent sidebar.

## The agent sidebar

It runs your Omarchy default coding agent, set with
`omarchy default agent <name>`. With none set, `Super + A` opens Omarchy's agent
chooser (which starts the chosen agent in a normal window; press `Super + A`
again for the sidebar). Agents start through Omarchy's own launcher, exactly as
`Super + Shift + Ctrl + A` starts them.

Claude Code is the exception, because Omarchy's launcher can't pass it session
options: Claude is run directly, pinned to one session, so closing the sidebar
and pressing `Super + A` resumes the same conversation. New sessions are named
with the date and time and, once they have a message, show up in the
`Super + Alt + A` menu (your 50 newest; type to search their prompts) and in
Claude's `/resume` picker. Renaming one with Claude's `/rename` takes it out of
the menu. It uses your normal Claude settings rather than the
auto permission mode Omarchy's launcher starts Claude in.

## Requirements

Omarchy with Hyprland's Lua config (Hyprland 0.55+). The agent sidebar needs
a default agent installed (`omarchy default agent`). Like Omarchy's own agent
launcher, it runs in `~/Work` if that exists, otherwise in your home folder
(where Claude asks to trust the folder each time).

## How it works

Omarchy shell plugins can't ship Hyprland config, so the plugin's service loads
`hypr/sidebar.lua` into the running Hyprland with `hyprctl eval` at start and
after every Hyprland config reload; after a plugin update it reloads Hyprland
once to pick up the new code. Problems (including mistakes in
`~/.config/omarchy/sidebar.lua`) are shown as a "Sidebar" notification. State
(pinned Claude session, remembered sides) lives in
`$XDG_STATE_HOME/omarchy-sidebar/` (normally `~/.local/state`).
