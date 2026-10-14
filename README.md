# Omarchy Sidebar

Turn any window into a **sidebar**: docked by the left or right screen edge,
floating over your workspace, and shown or hidden
with one key. For your coding agent as a sidebar (with saved, searchable
Claude Code sessions), add the
[Agent Sidebar plugin](https://github.com/motorstreak/omarchy-agent-sidebar).

You can have several sidebars, one showing at a time: `Super + B` shows or
hides the one you used last. `Super + Left/Right` move between your windows
and the sidebar as between two windows, and `Super + Up/Down` (in a sidebar)
cycle through them, each replacing the one before. Sidebars keep a wider gap from the
screen edges than tiled windows, have well-rounded corners, and a border in your
theme's green so they stand out
(`margin`, `rounding`, `border`, `border_opacity` and `border_size` in the
config change it).
With the [Window Style plugin](https://github.com/motorstreak/omarchy-window-style)
installed, sidebars' border, rounding and shadow are set in its panel instead
(its Sidebars tab), and these options are left aside. That tab also has the
dim behind a sidebar and the margin (the same `dim` and `margin` options as
here), so the sidebar settings show only how sidebars behave.

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
| `Super + Alt + B` | Make the focused window a sidebar, or a sidebar a normal window again |
| `Super + B` | Show the sidebar you used last, or hide the one showing |

Inside a sidebar that has focus (the keys do what Omarchy's do on a window,
made to fit, and what the [Dock plugin](https://github.com/motorstreak/omarchy-dock)'s
do on a docked window):

| Key | Action |
|---|---|
| `Super + Escape` or a click outside it | Hide it (the click still reaches what you clicked) |
| `Super + Alt + T` | Pick an Omarchy theme for this app's sidebars (see [Sidebar themes](#sidebar-themes)) |
| `Super + Alt + S` | The sidebar settings: flip the options below in a panel (`←`/`→` change one, `Esc` closes). Changes are saved into `~/.config/omarchy/sidebar.lua`, keeping your comments, and apply straight away. "Reset to defaults" at the bottom (press it twice) puts them all back, taking their lines out of the file |
| `Super + Left/Right` | Back to the windows with the arrow pointing away from the sidebar's screen edge (it hides). From the windows, the arrow towards a sidebar's edge, on the last window before it, shows it: the sidebar is reached as a window beside would be |
| `Super + Down` / `Super + Up` | The next / previous sidebar. With two or more, keep `Super` held for live previews of them all in the middle of the screen: press the arrows again to move along, let go of `Super` to show the highlighted one (`Super + Escape` cancels). A quick tap just shows it. With one sidebar it stays |
| `Super + Shift + arrows` | Move it against that screen edge, keeping its size; from there, the next arrow takes it into a corner (where Omarchy swaps a window that way). Where you leave it is remembered, separately for the agent (with the Agent Sidebar plugin) and other windows |
| `Super + Alt + arrows` | Move every sidebar against that screen edge, keeping their sizes (as the Dock gathers its windows on one edge) |
| `Super + T` | Tile it: it leaves the sidebars and is a normal tiled window on the workspace on screen (`Super + Alt + B` makes it a sidebar again) |
| `Super + F` | Omarchy's fullscreen, and back to the sidebar |
| `Super + Minus / Equal` | Narrower / wider. Docked against one screen edge, that edge stays put; anywhere else it grows and shrinks on both sides, as Omarchy's floating windows do (`Alt` small steps, `Ctrl` big steps) |
| `Super + Shift + Minus / Equal` | Shorter / taller; the top edge stays put |
| `Super + Shift + 1…0` | Move it to a workspace as a normal window |

A hidden sidebar is still there: `Super + B` brings it back.
`Super + Escape` or a click outside hides whichever sidebar is showing.

Plain `Escape` always reaches the app in the sidebar. While a sidebar has
focus, `Super + Escape` hides it instead of opening Omarchy's system menu (hide
the sidebar first, or turn this off per sidebar in the config). Clicks on the bar, its panels,
menus and notifications don't hide a sidebar; neither do keys or clicks while a
launcher, menu or screenshot selector is open. A click on an app's own menu
that reaches past the sidebar's edge counts as outside it and hides it.

A window that stops being the sidebar gets your theme's normal border back: its
width, and its colours (the first colour of a gradient border), replacing any
border colour a window rule had given it; they follow theme changes while the
plugin is installed.

### Keys the plugin uses

- Every key option replaces whatever was bound to that key before.
- While a sidebar has focus, the plugin takes over `Super + Alt + S` (move to the scratchpad), `Super + Escape` (Omarchy's
  system menu), and Omarchy's resize (`Super + [Shift/Alt/Ctrl] + Minus/Equal`),
  swap (`Super + Shift + arrows`), focus (`Super + arrows`), float/tile (`Super + T`) and move-into-group (`Super + Alt + arrows`) keys. `Super + Tab` stays Omarchy's (the next workspace). Everywhere else those are Omarchy's own
  bindings: they start out untouched, and after a sidebar has had focus they
  are re-bound exactly as Omarchy defines them. So if you've customised the
  system menu, resize, swap, focus, float or group keys, your version is replaced by
  Omarchy's until Hyprland reloads. With `omarchy_default_bindings = false`
  Omarchy's keys are left alone.
- A plain left click has an extra binding (to hide a sidebar on a click
  outside it) that lets the click through and does nothing unless a sidebar
  has focus.

## Configure

Create `~/.config/omarchy/sidebar.lua` returning the options to change, then
reload Hyprland (save any Hyprland config file, or `hyprctl reload`). All
options, with their defaults:

```lua
return {
  width = 0.33,          -- default width as a share of the screen
  margin = 32,           -- gap from the sidebar's border to screen edges and the bar (0-200), or false for the same as tiled windows
  dim = 0.55,            -- dim the rest of the screen while a sidebar shows, 0-1 (0 or false: none; true: strong)
  border = "green",      -- sidebar border: a theme colour name or palette slot ("accent", "color2"), "theme" (foreground), "#14B9B5", "none", or false for the usual one
  border_size = 6,       -- its width in pixels (Omarchy's windows have 2), or false for Omarchy's
  border_opacity = 1,    -- 0 (clear) to 1 (solid), for a colour name or "#rrggbb" border
  rounding = 32,         -- sidebars' corner radius (Omarchy's popped-out windows have 8); 0 for square
  click_outside = true,  -- clicking outside a sidebar hides it
  fade = false,          -- true: fade sidebars in and out instead of sliding (see below)
  drawer = true,         -- slide sidebars in from their screen edge and back out (see below)
  switcher = true,       -- false: Super + Up/Down cycle sidebars directly, without previews
  floating_keys = false, -- true: Super + Shift/Alt + arrows also move/stretch floating windows (see below)
  convert_back = true,   -- false: the convert key only makes sidebars (leave one with Super + T)
  sidebar = {
    toggle = "SUPER + B",
    convert = "SUPER + ALT + B",
    escape = true,       -- Super + Escape hides it (false: it opens the system menu)
    cycle = true,        -- Super + Left/Right reach a sidebar and back, Up/Down cycle them (false: Omarchy's focus)
    theme = "SUPER + ALT + T", -- in a sidebar: pick a theme for that app's sidebars
    settings = "SUPER + ALT + S", -- in a sidebar: the settings panel
  },
}
```

Any key can be changed or set to `false` to leave it unbound. A key that's
already bound (for example `SUPER + C`, Omarchy's copy) is replaced. Mistakes
in the file are shown as a "Sidebar" notification.

`fade = true` swaps Omarchy's vertical slide for a fade, which also crossfades
from one sidebar to the next. Hyprland has a single animation for every special
workspace, so the scratchpad fades too, and it replaces any `specialWorkspace`
animation in your own Hyprland config while the plugin is enabled.

`floating_keys = true` gives every floating window, not only sidebars, the
sidebar's keys that Omarchy has no use for on a floating window:
`Super + Shift + arrows` move it against that screen edge (keeping its size),
and `Super + Alt + arrows` make it full width or height, and back to the edge
the arrow points to. Windows popped out with Omarchy's `Super + O` count as
floating too; the Dock's windows have keys of their own, and tiled windows keep
Omarchy's swap keys (and, with the Dock plugin, its gather on `Super + Alt + arrows`).

`drawer = true` (the default) slides a sidebar in from the screen edge it's
docked against, and back out to it when it hides, so it reads as a drawer
rather than another window. It uses your window move animation, and turns the
special workspace animation into a fade like `fade = true` (the scratchpad
fades too). An edge with another monitor beyond it gets a short slide, so the
sidebar doesn't show on that monitor on its way in. Set `drawer = false` for
Omarchy's vertical slide.

## Sidebar themes

`Super + Alt + T` in a sidebar lists your installed Omarchy themes; the one you
pick is used by every sidebar of that app (all the Agent Sidebar's sessions
share one, any other window goes by its app), until you pick "Follow system theme" again.

- The sidebar's border takes its colour from that theme.
- A terminal sidebar (Foot, or any terminal running one process per window)
  also takes the theme's background, text and palette, set the way Omarchy
  sets every Foot terminal's on a theme change. When it stops being a sidebar
  it goes back to the current theme's colours.
- An app that draws its own colours (a browser, say) only gets the border.
- Claude Code in the Agent Sidebar uses its "ANSI colours only" theme, so all
  of it, accents included, follows the terminal's colours and changes the
  moment you pick a theme. Its usual themes, Omarchy's included, use fixed
  colours.
- An app with a theme picker of its own (`own_themes`; cliamp by default)
  keeps its own colours: `Super + Alt + T` in its sidebar opens its picker
  instead (for cliamp, by pressing `T`).

The plugin adds a hook, `~/.config/omarchy/hooks/theme-set.d/omarchy-sidebar-themes`,
so a sidebar's theme survives Omarchy theme changes.

## Requirements

Omarchy with Hyprland's Lua config (tested on Hyprland 0.56).

## How it works

Omarchy shell plugins can't ship Hyprland config, so the plugin's service loads
`hypr/sidebar.lua` into the running Hyprland with `hyprctl eval` at start and
after every Hyprland config reload; after a plugin update it reloads Hyprland
once to pick up the new code. Problems are shown as a "Sidebar" notification.
Other plugins can add a kind of sidebar of their own (a window class whose
windows open straight into a sidebar, with their own place and theme) through
the `SIDEBAR_KINDS` table; the Agent Sidebar plugin does. State (remembered
places, themes) lives in
`$XDG_STATE_HOME/omarchy-sidebar/` (normally `~/.local/state`).
