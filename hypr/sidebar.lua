-- Omarchy Sidebar
--
-- A sidebar is a window docked by the left or right screen edge on its own
-- special workspace (special:sidebar, special:sidebar2, ...): floating, dimming
-- the rest of the screen, shown and hidden with a key. There can be several, but
-- only one shows at a time: a monitor shows one special workspace, so showing a
-- sidebar hides the one before. Move a sidebar to a regular workspace
-- (SUPER + SHIFT + <n>) and it is an ordinary window again, following every
-- normal Omarchy binding.
--
--   SUPER + ALT + B  the focused window becomes a sidebar (or a sidebar
--                    becomes a normal window again)
--   SUPER + B        show the sidebar last shown; while one shows, the next
--                    (in the order they were added, wrapping round), or hide it
--                    if it's the only one
--   SUPER + A        the agent sidebar: your Omarchy default coding agent
--                    (`omarchy default agent`) becomes a sidebar and shows,
--                    launched if needed; with Claude Code it also keeps saved,
--                    searchable sessions (see bin/agent-sidebar)
--
-- In the sidebar, SUPER + SHIFT + arrows move it in steps, SUPER + ALT +
-- LEFT/RIGHT dock it to that screen edge, and Omarchy's resize
-- keys resize it from the side nearer a screen edge; where it was put is
-- remembered separately for the agent and for other windows.
--
-- Loaded into the running Hyprland by Service.qml with SIDEBAR_DIR set to the
-- plugin folder. Keys and options can be overridden in
-- ~/.config/omarchy/sidebar.lua (a Lua file returning a table like `defaults`).
--
-- Errors inside Hyprland callbacks otherwise surface only as a bare Hyprland
-- notification, so every callback here runs through `guard`, which reports
-- failures once as a "Sidebar" desktop notification.

if SIDEBAR_LOADED then
  return
end
if SIDEBAR_DIR == nil then
  error("set SIDEBAR_DIR to the plugin folder before loading sidebar.lua")
end
SIDEBAR_LOADED = true

local dir = SIDEBAR_DIR
local home = os.getenv("HOME")
local state_home = os.getenv("XDG_STATE_HOME")
if state_home == nil or state_home == "" then
  state_home = home .. "/.local/state"
end
local state_root = state_home .. "/omarchy-sidebar"
local quote = o.shell_quote

-- The first sidebar's workspace; more are special:sidebar2, special:sidebar3...
local WORKSPACE = "special:sidebar"
local LEGACY_WORKSPACE = "special:agent" -- the agent's own slot before 0.2

local function is_sidebar_workspace(name)
  return name ~= nil and name:match("^special:sidebar%d*$") ~= nil
end

-- Reporting --------------------------------------------------------------------

local reported, reported_count = {}, 0

local function notify(message)
  hl.exec_cmd("notify-send -a Sidebar -- Sidebar " .. quote(message))
end

-- Each distinct error is reported once per load (and at most 20 in all), so a
-- failing callback that fires on every focus change can't flood the screen.
local function report(context, err)
  local message = context .. ": " .. tostring(err)
  if not reported[message] and reported_count < 20 then
    reported[message] = true
    reported_count = reported_count + 1
    notify(message)
  end
end

local function guard(context, fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then
      report(context, err)
    end
  end
end

-- Config -----------------------------------------------------------------------

local defaults = {
  -- Gap from the sidebar's border to the screen edges and the bar, in pixels
  -- (wider than tiled windows' by default), or false for the one tiled windows
  -- have (Hyprland's outer gap).
  margin = 32,
  width = 0.33, -- default width as a share of the monitor
  -- How much to dim the rest of the screen while a sidebar shows, 0 to 1 (0 or
  -- false: none, not even Omarchy's light dim behind special workspaces; true:
  -- the old strong dim).
  dim = 0.55,
  -- The sidebar's border: a colour name from the theme's colors.toml
  -- ("green", "foreground", "cyan", "background", ...), "theme" (the foreground), a
  -- colour such as "#14B9B5" or "rgba(14b9b5ff)", "none", or false for the usual
  -- border. (In "background" and wide, it reads as padding around the content.)
  border = "green",
  border_size = 6, -- its width in pixels (Omarchy's windows have 2), or false for Omarchy's
  border_opacity = 1, -- 0 (clear) to 1 (solid), for a border given as a colour name or "#rrggbb"
  shadow = false, -- true: a large, faint shadow around sidebars
  rounding = 32, -- corner radius of sidebars (Omarchy's popped-out windows have 8); 0 for square
  click_outside = true, -- clicking outside the shown sidebar hides it
  -- Fade sidebars in and out instead of Omarchy's vertical slide. Hyprland has
  -- one animation for every special workspace, so this fades the scratchpad
  -- too, and it replaces any specialWorkspace animation in your Hyprland config.
  fade = false,
  -- Slide sidebars in from the screen edge they're docked against, and back out
  -- to it when they hide, like a drawer. Next to another monitor they start a
  -- short way in, so they don't show on that monitor. Hyprland's own show/hide
  -- animation becomes a fade (scratchpad too), as with `fade`.
  drawer = true,
  -- With two or more sidebars, SUPER + B shows live previews of them all in the
  -- middle of the screen while SUPER is held; false cycles them directly.
  switcher = true,
  sidebar = {
    toggle = "SUPER + B",
    convert = "SUPER + ALT + B",
    escape = true, -- SUPER + ESCAPE hides it (instead of opening the system menu)
    cycle = true, -- SUPER + TAB shows the next sidebar (instead of the next workspace)
  },
  agent = {
    enabled = true,
    class = "sidebar.agent",
    toggle = "SUPER + A",
    new = "SUPER + SHIFT + A",
    load = "SUPER + ALT + A",
    reset = "SUPER + CTRL + ALT + A",
    escape = true,
  },
}

-- Omarchy's resize and swap keys (from default/hypr/bindings/tiling.lua). The
-- plugin takes them over only while the sidebar has focus, and otherwise binds
-- them exactly as Omarchy does.
local resize_keys = {
  { "SUPER + code:20", "Expand window left", -100, 0 },
  { "SUPER + code:21", "Shrink window left", 100, 0 },
  { "SUPER + SHIFT + code:20", "Shrink window up", 0, -100 },
  { "SUPER + SHIFT + code:21", "Expand window down", 0, 100 },
  { "SUPER + ALT + code:20", "Expand window left a little", -25, 0 },
  { "SUPER + ALT + code:21", "Shrink window left a little", 25, 0 },
  { "SUPER + SHIFT + ALT + code:20", "Shrink window up a little", 0, -25 },
  { "SUPER + SHIFT + ALT + code:21", "Expand window down a little", 0, 25 },
  { "SUPER + CTRL + code:20", "Expand window left a lot", -300, 0 },
  { "SUPER + CTRL + code:21", "Shrink window left a lot", 300, 0 },
  { "SUPER + CTRL + SHIFT + code:20", "Shrink window up a lot", 0, -300 },
  { "SUPER + CTRL + SHIFT + code:21", "Expand window down a lot", 0, 300 },
}
local swap_keys = {
  { "SUPER + SHIFT + LEFT", "Swap window to the left", "l" },
  { "SUPER + SHIFT + RIGHT", "Swap window to the right", "r" },
  { "SUPER + SHIFT + UP", "Swap window up", "u" },
  { "SUPER + SHIFT + DOWN", "Swap window down", "d" },
}
-- Omarchy's keys for moving a window into the group beside it; in the sidebar
-- they dock it to that screen edge.
local group_keys = {
  { "SUPER + ALT + LEFT", "Move window to group on left", "l" },
  { "SUPER + ALT + RIGHT", "Move window to group on right", "r" },
}
-- Omarchy's key for the next workspace; in the sidebar (with `cycle`) it shows
-- the next sidebar, like SUPER + B.
local CYCLE_KEY = { "SUPER + TAB", "Next workspace", "e+1" }

-- Hides the focused sidebar. Omarchy binds it to the system menu
-- (default/hypr/bindings/utilities.lua); that comes back whenever the sidebar
-- doesn't have focus.
local HIDE_KEY = "SUPER + ESCAPE"
local SYSTEM_MENU = "omarchy-menu toggle system"

local key_options = {
  [""] = { border = true },
  sidebar = { toggle = true, convert = true },
  agent = { toggle = true, new = true, load = true, reset = true },
}

-- Copies `overrides` onto `into` where the types fit the defaults (key options
-- may also be false to leave them unbound); anything else is reported and
-- skipped.
local function apply(into, overrides, path, problems, keys)
  for k, v in pairs(overrides) do
    local name = path .. tostring(k)
    local current = into[k]
    if current == nil then
      problems[#problems + 1] = "unknown option " .. name
    elseif type(current) == "table" then
      if type(v) == "table" then
        apply(current, v, name .. ".", problems, key_options[k])
      else
        problems[#problems + 1] = name .. " must be a table"
      end
    elseif type(v) == type(current) or (v == false and keys and keys[k])
        or (name == "dim" and type(v) == "boolean")
        or ((name == "margin" or name == "border_size") and (type(v) == "number" or v == false)) then
      into[k] = v
    else
      problems[#problems + 1] = name .. " must be a " .. type(current)
    end
  end
end

local config = defaults
do
  local problems = {}
  local path = home .. "/.config/omarchy/sidebar.lua"
  local chunk, load_err = loadfile(path)
  if chunk then
    local ok, overrides = pcall(chunk)
    if not ok then
      problems[#problems + 1] = tostring(overrides)
    elseif type(overrides) ~= "table" then
      problems[#problems + 1] = "the file must return a table"
    else
      apply(config, overrides, "", problems, key_options[""])
    end
  elseif load_err and not load_err:find("No such file", 1, true) then
    problems[#problems + 1] = load_err
  end

  if type(config.dim) == "number" and (config.dim < 0 or config.dim > 1) then
    problems[#problems + 1] = "dim must be between 0 and 1, or true/false"
    config.dim = 0.55
  end
  if config.width <= 0 or config.width > 1 then
    problems[#problems + 1] = "width must be between 0 and 1"
    config.width = 0.33
  end
  if type(config.margin) == "number" and (config.margin < 0 or config.margin > 200) then
    problems[#problems + 1] = "margin must be false or between 0 and 200"
    config.margin = 32
  end
  if config.rounding < 0 or config.rounding > 50 then
    problems[#problems + 1] = "rounding must be between 0 and 50"
    config.rounding = 32
  end
  if config.border_opacity < 0 or config.border_opacity > 1 then
    problems[#problems + 1] = "border_opacity must be between 0 and 1"
    config.border_opacity = 1
  end
  if type(config.border_size) == "number" and (config.border_size < 1 or config.border_size > 60) then
    problems[#problems + 1] = "border_size must be false or between 1 and 60"
    config.border_size = false
  end
  if config.border and not config.border:match("^[%a_]+$")
      and not config.border:match("^#%x%x%x%x%x%x$") and not config.border:match("^rgba?%([%x, .]+%)$") then
    problems[#problems + 1] = "border must be a theme colour name, a colour like \"#14B9B5\", \"none\", or false"
    config.border = "theme"
  end
  -- Used as a terminal app id and in a window rule: keep it to a plain id.
  if not config.agent.class:match("^[%w][%w._-]*$") then
    problems[#problems + 1] = "agent.class must be letters, digits, '.', '_' or '-'"
    config.agent.class = "sidebar.agent"
  end

  -- Two options on one key would silently replace each other, and the keys the
  -- plugin takes over while the sidebar has focus can't be used for options.
  -- Modifiers are compared in any order.
  local function normalise(keys)
    local parts = {}
    for part in keys:gmatch("[^+]+") do
      parts[#parts + 1] = part:gsub("^%s+", ""):gsub("%s+$", ""):upper()
    end
    local key = table.remove(parts)
    table.sort(parts)
    parts[#parts + 1] = key
    return table.concat(parts, "+")
  end
  local seen = { [normalise(HIDE_KEY)] = "Super + Escape (hides the sidebar)" }
  for _, k in ipairs(resize_keys) do
    seen[normalise(k[1])] = "Omarchy's resize keys"
  end
  for _, k in ipairs(swap_keys) do
    seen[normalise(k[1])] = "Omarchy's swap keys"
  end
  for _, k in ipairs(group_keys) do
    seen[normalise(k[1])] = "Omarchy's group keys"
  end
  for _, option in ipairs({ { "sidebar", "toggle" }, { "sidebar", "convert" }, { "agent", "toggle" },
    { "agent", "new" }, { "agent", "load" }, { "agent", "reset" } }) do
    local group, name = option[1], option[2]
    local keys = config[group][name]
    if keys and (group ~= "agent" or config.agent.enabled) then
      local id = normalise(keys)
      if seen[id] then
        problems[#problems + 1] = group .. "." .. name .. " uses the same key as " .. seen[id]
        config[group][name] = false
      else
        seen[id] = group .. "." .. name
      end
    end
  end

  if #problems > 0 then
    notify("Problems in ~/.config/omarchy/sidebar.lua: " .. table.concat(problems, "; "))
  end
end

local agent_class = config.agent.enabled and config.agent.class or nil

-- Loaded after your Hyprland config (and again on every reload), so this wins.
-- Omarchy's speed and curve, with its "slidevert" style swapped for a fade.
if config.fade or config.drawer then
  hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 3, bezier = "easeOutQuint", style = "fade" })
end

-- The agent's windows: its class, or for Claude "<class>.<session>" (each
-- session has its own window; see bin/agent-sidebar).
local function is_agent(window)
  local class = agent_class ~= nil and window ~= nil and window.class
  return class and (class == agent_class or class:sub(1, #agent_class + 1) == agent_class .. ".") or false
end

-- Escape and the remembered place are per kind: the agent, or any other window.
local function kind(window)
  return is_agent(window) and "agent" or "sidebar"
end

-- Windows ---------------------------------------------------------------------

-- The sidebar windows by address, so a window leaving a sidebar can be told
-- apart from an ordinary window moving between workspaces, and whether each was
-- floating before, to put it back that way. Each member's value is a sequence
-- number: SUPER + B cycles through them in the order they were added.
local members = {}
-- Also kept in a file: a Hyprland reload runs this file afresh, and a window
-- already in a sidebar must still go back floating when it leaves.
local floating_file = state_root .. "/was-floating"
local was_floating = {}
do
  local f = io.open(floating_file, "r")
  if f then
    for address in f:lines() do
      was_floating[address] = true
    end
    f:close()
  end
end
local function save_floating()
  local f = io.open(floating_file, "w")
  if f then
    for address, floated in pairs(was_floating) do
      if floated then
        f:write(address, "\n")
      end
    end
    f:close()
  end
end
local sequence = 0
local function next_sequence()
  sequence = sequence + 1
  return sequence
end
-- The sidebar shown last (by address), for SUPER + B to bring back.
local last_shown = nil

local function selector(window)
  return "address:" .. window.address
end

-- Hyprland can crash floating, centring, moving or resizing a window while its
-- monitor is being reconfigured (unplugged, or connected but still 0x0, as when
-- monitors are switched): so those are skipped unless the window is on a monitor
-- that's connected and has a size. Other commands (borders, tags) go ahead.
local GEOMETRY = {
  [hl.dsp.window.float] = true, [hl.dsp.window.center] = true, [hl.dsp.window.move] = true,
  [hl.dsp.window.resize] = true, [hl.dsp.window.pin] = true, [hl.dsp.window.alter_zorder] = true,
}

local function usable_monitor(m)
  if m == nil or (m.width or 0) <= 0 or (m.height or 0) <= 0 then
    return false
  end
  for _, other in ipairs(hl.get_monitors()) do
    if other.name == m.name then
      return true
    end
  end
  return false
end

local function dispatch_for(window, dsp, args)
  if GEOMETRY[dsp] then
    local now = hl.get_window(selector(window))
    if now == nil or not usable_monitor(now.monitor) then
      return
    end
  end
  args.window = selector(window)
  hl.dispatch(dsp(args))
end

-- The window as it is now, or nil once it has closed.
local function current(address)
  return hl.get_window("address:" .. address)
end

-- A workspace selector for moving a window to a regular workspace by name.
local function workspace_target(name)
  if tonumber(name) then
    return name
  end
  return "name:" .. name
end

-- The regular workspace on screen (never a special one).
local function regular_workspace(monitor)
  monitor = monitor or hl.get_active_monitor()
  return monitor and monitor.active_workspace
end

-- The windows in every sidebar workspace.
local function sidebar_windows()
  local inside = {}
  for _, w in ipairs(hl.get_windows()) do
    if w.workspace and is_sidebar_workspace(w.workspace.name) then
      inside[#inside + 1] = w
    end
  end
  return inside
end

local function in_sidebar(window)
  return window ~= nil and window.workspace ~= nil and is_sidebar_workspace(window.workspace.name)
end

local function is_member(window)
  return in_sidebar(window) and members[window.address] ~= nil
end

-- The sidebar workspace the monitor shows, or nil.
local function shown_sidebar(monitor)
  monitor = monitor or hl.get_active_monitor()
  local shown = monitor and monitor.active_special_workspace
  if shown ~= nil and is_sidebar_workspace(shown.name) then
    return shown.name
  end
end

local function sidebar_shown(monitor)
  return shown_sidebar(monitor) ~= nil
end

-- Whether the window's own sidebar is the one on screen.
local function showing(window)
  return in_sidebar(window) and shown_sidebar(window.monitor) == window.workspace.name
end

-- The dim behind the sidebar is Hyprland's dim_special (which dims everything
-- behind a shown special workspace): raised while a sidebar shows with `dim`,
-- or none at all without it. It crossfades smoothly between sidebars, where a
-- dim on each window doubled up for a moment and then vanished in one frame.
-- Hyprland takes the value when a special workspace appears, so it is set just
-- before a sidebar shows and set back to Omarchy's once something else shows
-- (or nothing), for the scratchpad.
local base_dim = tonumber(hl.get_config("decoration:dim_special")) or 0.2
local special_dim = base_dim
local function dim_behind(sidebar)
  local value = base_dim
  if sidebar then
    if config.dim == true then
      value = 1 - (1 - base_dim) * 0.6
    elseif type(config.dim) == "number" then
      value = config.dim
    else
      value = 0
    end
  end
  if value ~= special_dim then
    hl.config({ decoration = { dim_special = value } })
    special_dim = value
  end
end

-- The drawer (`drawer`), defined with the geometry further down: the sidebars
-- sliding out (sidebar workspace -> token of that slide), and where each
-- sidebar window sits while it's off its place (address -> { x, y }).
local away, home = {}, {}
local drawer_prepare, drawer_in, drawer_out, drawer_back, drawer_restore

local function toggle_special(name)
  hl.dispatch(hl.dsp.workspace.toggle_special(name:sub(#"special:" + 1)))
end

-- Shows or hides a sidebar workspace on the active monitor; `instant` skips the
-- drawer's slide.
local function toggle_workspace(name, instant)
  local slide = config.drawer and not instant
  if shown_sidebar() == name then
    if slide and away[name] then
      drawer_back(name) -- hidden halfway: it comes back
    elseif slide then
      drawer_out(name)
    else
      away[name] = nil
      dim_behind(false)
      toggle_special(name)
      drawer_restore(name)
    end
    return
  end
  dim_behind(true)
  local sliding = slide and drawer_prepare(name)
  toggle_special(name)
  if sliding then
    drawer_in(sliding)
  end
end

-- Hides the sidebar on the active monitor, if one shows (and isn't hiding).
local function hide_shown()
  local shown = shown_sidebar()
  if shown and not away[shown] then
    toggle_workspace(shown)
  end
end

-- A sidebar workspace with no window in it.
local function free_workspace()
  local used = {}
  for _, w in ipairs(sidebar_windows()) do
    used[w.workspace.name] = true
  end
  if not used[WORKSPACE] then
    return WORKSPACE
  end
  local n = 2
  while used[WORKSPACE .. n] do
    n = n + 1
  end
  return WORKSPACE .. n
end

local function focus(window)
  hl.dispatch(hl.dsp.focus({ window = selector(window) }))
end

-- Remembered places -----------------------------------------------------------

-- Where each kind of sidebar (the agent, any other window) was last put: the
-- screen edge it's nearer to, its distance from that edge, and its distance
-- from the top, all within the usable area. Kept in <kind>.side as
-- "<side> <offset> <top>" (before 0.6 it held only the side).
os.execute("mkdir -p " .. quote(state_root))

local places = {}
for _, k in ipairs({ "agent", "sidebar" }) do
  places[k] = { side = "right", offset = 0, top = 0 }
  local f = io.open(state_root .. "/" .. k .. ".side", "r")
  if f then
    local side, offset, top = (f:read("l") or ""):match("^(%a+)%s*(%-?%d*)%s*(%-?%d*)")
    if side == "left" or side == "right" then
      places[k] = { side = side, offset = tonumber(offset) or 0, top = tonumber(top) or 0 }
    end
    f:close()
  end
end

local function save_place(k, place)
  local saved = places[k]
  if saved.side == place.side and saved.offset == place.offset and saved.top == place.top then
    return
  end
  places[k] = place
  local f = io.open(state_root .. "/" .. k .. ".side", "w")
  if f then
    f:write(string.format("%s %d %d\n", place.side, place.offset, place.top))
    f:close()
  end
end

-- Geometry -------------------------------------------------------------------

-- The gap from the screen edges and the bar (top, right, bottom, left): the
-- `margin` option, or by default where a tiled window's border starts, so a
-- sidebar lines up with tiled windows (Hyprland's outer gap, plus the border
-- width if sidebars have one, as positions are inside the border).
local function margins()
  local top, right, bottom, left = 0, 0, 0, 0
  if type(config.margin) == "number" then
    top, right, bottom, left = config.margin, config.margin, config.margin, config.margin
  else
    local g = hl.get_config("general:gaps_out")
    if type(g) == "number" then
      top, right, bottom, left = g, g, g, g
    elseif g then
      top, right, bottom, left = g.top or 0, g.right or 0, g.bottom or 0, g.left or 0
    end
  end
  -- The sidebar's own border width (positions are inside the border).
  local b = 0
  if config.border == false or (config.border ~= "none" and not config.border_size) then
    local size = hl.get_config("general:border_size")
    b = type(size) == "number" and size or 0
  elseif config.border ~= "none" then
    b = math.floor(config.border_size)
  end
  return top + b, right + b, bottom + b, left + b
end

-- The space the Dock plugin reserves for windows pinned to the monitor's left
-- and right edges (its invisible strips): sidebars slide over pinned windows
-- rather than keep out of their way, as they only show for a moment.
local function dock_strips(m, mw)
  local left, right = 0, 0
  for _, l in ipairs(hl.get_layers()) do
    if l.mapped and l.namespace == "omarchy-dock-strip" then
      if math.abs(l.x - m.x) < 2 and l.x + l.w < m.x + mw then
        left = math.max(left, l.w)
      elseif math.abs(l.x + l.w - (m.x + mw)) < 2 and l.x > m.x then
        right = math.max(right, l.w)
      end
    end
  end
  return left, right
end

local function area(m)
  local r = m.reserved or {}
  local top, right, bottom, left = margins()
  local mw, mh = m.width / m.scale, m.height / m.scale
  -- Rotated by 90 or 270 degrees (also when flipped): width and height swap.
  if (m.transform or 0) % 2 == 1 then
    mw, mh = mh, mw
  end
  local dock_left, dock_right = dock_strips(m, mw)
  return {
    left = m.x + math.max(0, (r.left or 0) - dock_left) + left,
    right = m.x + mw - math.max(0, (r.right or 0) - dock_right) - right,
    top = m.y + (r.top or 0) + top,
    bottom = m.y + mh - (r.bottom or 0) - bottom,
    width = mw,
  }
end

-- The monitor each sidebar was last docked on, to re-dock it when it's shown on
-- another one.
local docked_on = {}

-- Puts the window at x, y with the given size, kept inside the usable area of
-- its monitor, and remembers the place for its kind.
local function place(window, width, height, x, y)
  if window.monitor == nil then
    return
  end
  local a = area(window.monitor)
  local max_width, max_height = a.right - a.left, a.bottom - a.top
  width = math.floor(math.min(math.max(width, math.min(360, max_width)), max_width))
  height = math.floor(math.min(math.max(height, math.min(300, max_height)), max_height))
  x = math.floor(math.min(math.max(x, a.left), a.right - width))
  y = math.floor(math.min(math.max(y, a.top), a.bottom - height))

  dispatch_for(window, hl.dsp.window.resize, { x = width, y = height })
  dispatch_for(window, hl.dsp.window.move, { x = x, y = y })
  docked_on[window.address] = window.monitor.id

  local from_left, from_right = x - a.left, a.right - (x + width)
  save_place(kind(window), {
    side = from_left <= from_right and "left" or "right",
    offset = math.min(from_left, from_right),
    top = y - a.top,
  })
end

-- The default width, at the remembered place, reaching to the bottom.
local function dock_default(window)
  if window.monitor == nil then
    return
  end
  local a = area(window.monitor)
  local p = places[kind(window)]
  local width = math.floor(a.width * config.width) -- whole pixels, so x lines up
  local top = a.top + p.top
  local x = p.side == "left" and (a.left + p.offset) or (a.right - p.offset - width)
  place(window, width, a.bottom - top, x, top)
end

-- Defined further down; entering and leaving re-check the sidebar keys, since a
-- new window's focus event can arrive before it has entered the sidebar (and
-- the drawer once a sidebar has hidden).
local sync_keys

-- Drawer -------------------------------------------------------------------------

-- A window's own move isn't animated while its `no_anim` is on, but only from a
-- moment after it's turned on. And a floating window entirely off screen is put
-- back on it when its workspace appears. So hidden sidebars keep `no_anim` on;
-- once one shows, its windows jump off their edge and, after a pause, slide in.
-- Hiding waits for the slide out (Omarchy's window animation, about 380 ms,
-- mostly there by this), then for the fade out before the hidden windows go
-- back to their places.
local DRAWER_PAUSE = 30
local DRAWER_OUT = 200
local DRAWER_FADE = 400

local anim_off = {} -- address -> true: `no_anim` on
local sliding = {} -- address -> true from showing until its slide in starts

-- The monitor's left edge and width in layout pixels.
local function span(m)
  local w = m.width / m.scale
  if (m.transform or 0) % 2 == 1 then
    w = m.height / m.scale
  end
  return m.x, w
end

-- The floating sidebar windows of a sidebar workspace, on a usable monitor.
local function drawer_windows(name)
  local list = {}
  for _, w in ipairs(hl.get_workspace_windows(name) or {}) do
    if members[w.address] and w.floating and usable_monitor(w.monitor) then
      list[#list + 1] = w
    end
  end
  return list
end

-- Where the window slides from and to for a place at x: off its nearer screen
-- edge, or a short way in from it when another monitor is beyond that edge.
local function off_x(window, x)
  local m = window.monitor
  local a = area(m)
  local mx, mw = span(m)
  local width = window.size.x
  local left = x - a.left <= a.right - (x + width)
  for _, o in ipairs(hl.get_monitors()) do
    if o.id ~= m.id and o.y < m.y + m.height / m.scale and m.y < o.y + o.height / o.scale then
      local ox, ow = span(o)
      if (left and math.abs(ox + ow - mx) < 2) or (not left and math.abs(ox - (mx + mw)) < 2) then
        local step = math.floor(width * 0.3)
        return left and x - step or x + step
      end
    end
  end
  return left and (mx - width - 64) or (mx + mw + 64)
end

-- The window's place: kept while it's away, else where it is, inside the
-- usable area (a reload mid-slide can leave it off screen).
local function place_of(window)
  local h = home[window.address]
  if h == nil then
    local a = area(window.monitor)
    h = {
      x = math.floor(math.min(math.max(window.at.x, a.left), math.max(a.left, a.right - window.size.x))),
      y = window.at.y,
    }
    home[window.address] = h
  end
  return h
end

local function set_anim(window, on)
  if on then
    dispatch_for(window, hl.dsp.window.set_prop, { prop = "no_anim", value = "unset" })
    anim_off[window.address] = nil
  else
    dispatch_for(window, hl.dsp.window.set_prop, { prop = "no_anim", value = "1" })
    anim_off[window.address] = true
  end
end

local function slide(window, x, y)
  dispatch_for(window, hl.dsp.window.move, { x = x, y = y })
end

local function after(ms, context, fn)
  hl.timer(guard(context, fn), { timeout = ms, type = "oneshot" })
end

-- Before showing: the sidebar windows that will slide in (ready, as they've
-- been hidden a while, and not shown on another monitor than they were docked
-- on: those get docked there instead). Returns their addresses, or nil.
function drawer_prepare(name)
  away[name] = nil
  local monitor = hl.get_active_monitor()
  local list = {}
  for _, w in ipairs(drawer_windows(name)) do
    if monitor and anim_off[w.address]
        and (docked_on[w.address] == nil or docked_on[w.address] == monitor.id) then
      place_of(w)
      sliding[w.address] = true
      list[#list + 1] = w.address
    end
  end
  return #list > 0 and list or nil
end

-- Just shown: they jump off their edge, then slide to their places.
function drawer_in(addresses)
  for _, address in ipairs(addresses) do
    local w, h = current(address), home[address]
    if w and h then
      slide(w, off_x(w, h.x), h.y)
    end
  end
  after(DRAWER_PAUSE, "sliding the sidebar in", function()
    for _, address in ipairs(addresses) do
      local w, h = current(address), home[address]
      sliding[address] = nil
      if w and h then
        set_anim(w, true)
        slide(w, h.x, h.y)
      end
      home[address] = nil
    end
  end)
end

-- Hiding: the windows slide off their edge, then the sidebar hides (unless
-- it's been shown again or replaced meanwhile) and they go back to their
-- places, out of sight.
function drawer_out(name)
  local token = {}
  away[name] = token
  local monitor = hl.get_active_monitor()
  for _, w in ipairs(drawer_windows(name)) do
    local h = place_of(w)
    slide(w, off_x(w, h.x), h.y)
  end
  after(DRAWER_OUT, "hiding the sidebar", function()
    if away[name] ~= token then
      return
    end
    local m = hl.get_active_monitor()
    -- The dispatcher acts on the active monitor: with another one active now
    -- the sidebar can't hide from here, so it slides back instead.
    if m and monitor and m.id == monitor.id and shown_sidebar(m) == name then
      dim_behind(false)
      toggle_special(name)
      sync_keys()
      after(DRAWER_FADE, "putting the sidebar back", function()
        if away[name] == token then
          away[name] = nil
          drawer_restore(name)
        end
      end)
    elseif shown_sidebar(monitor) == name then
      drawer_back(name)
    else
      away[name] = nil
      drawer_restore(name)
    end
  end)
end

-- Hiding was undone: the windows slide back to their places.
function drawer_back(name)
  away[name] = nil
  for _, w in ipairs(drawer_windows(name)) do
    local h = home[w.address]
    if h then
      slide(w, h.x, h.y)
      home[w.address] = nil
    end
  end
end

-- Hidden: the windows go back to their places, ready to jump next time.
function drawer_restore(name)
  for _, w in ipairs(drawer_windows(name)) do
    set_anim(w, false)
    local h = home[w.address]
    if h then
      slide(w, h.x, h.y)
      home[w.address] = nil
    end
  end
end

-- After any show or hide: shown sidebar windows animate as usual, hidden ones
-- are ready to jump (also those hidden some other way, like one sidebar taking
-- another's place). Without `drawer`, `no_anim` is handed back to the rules.
local function drawer_sync()
  for _, w in ipairs(sidebar_windows()) do
    if members[w.address] and not sliding[w.address] and not away[w.workspace.name] then
      local hidden = not showing(w)
      if config.drawer and w.floating and hidden and not anim_off[w.address] then
        set_anim(w, false)
      elseif (not hidden or not config.drawer) and anim_off[w.address] then
        set_anim(w, true)
      end
    end
  end
end

-- Entering and leaving the sidebar --------------------------------------------


local function set_dim(window, on)
  dispatch_for(window, hl.dsp.window.set_prop, { prop = "dim_around", value = on and "1" or "0" })
end

-- The sidebar's border colours (focused, unfocused), or nil to leave borders be.
local sidebar_border = nil
local no_border = config.border == "none"
-- A colour from the current theme's colors.toml, as "rrggbb".
local theme_colors = ""
do
  local f = io.open(state_home .. "/omarchy/current/theme/colors.toml", "r")
  if f then
    theme_colors = "\n" .. f:read("a")
    f:close()
  end
end
-- Colour names some themes leave out, giving only the terminal palette
-- (color0-color15): the standard ANSI slot for each.
local PALETTE = {
  red = "color1", green = "color2", yellow = "color3", blue = "color4", magenta = "color5", cyan = "color6",
  bright_red = "color9", bright_green = "color10", bright_yellow = "color11",
  bright_blue = "color12", bright_magenta = "color13", bright_cyan = "color14",
}
local function theme_colour(name)
  local pattern = '%s*=%s*"#?(%x%x%x%x%x%x)"'
  return theme_colors:match("\n%s*" .. name .. pattern)
    or (PALETTE[name] and theme_colors:match("\n%s*" .. PALETTE[name] .. pattern))
end
-- The switcher's highlight.
local theme_foreground = theme_colour("foreground")
do
  local spec = config.border
  if spec and not no_border then
    local hex = spec:match("^#(%x%x%x%x%x%x)$")
    if spec == "theme" then
      hex = theme_foreground
    elseif spec:match("^[%a_]+$") then
      hex = theme_colour(spec)
      if hex == nil then
        notify("No colour \"" .. spec .. "\" in the theme; sidebars keep the usual border")
      end
    elseif hex == nil then
      sidebar_border = { spec, spec }
    end
    -- The same focused or not, so it reads as part of the window.
    if hex then
      local alpha = string.format("%02x", math.floor(config.border_opacity * 255 + 0.5))
      sidebar_border = { "rgba(" .. hex .. alpha .. ")", "rgba(" .. hex .. alpha .. ")" }
    end
  end
end

-- The theme's border colour for normal windows, as a set_prop value. Only the
-- first colour of a gradient is kept (set_prop takes a single colour).
local function theme_border(option)
  local g = hl.get_config(option)
  local c = g and g.colors and g.colors[1]
  if type(c) == "number" then
    c = string.format("0x%08X", c)
  end
  local alpha, rgb = tostring(c):match("^0[xX](%x%x)(%x%x%x%x%x%x)$")
  return alpha and ("rgba(" .. rgb .. alpha .. ")") or nil
end

local function set_border(window, active, inactive)
  if active then
    dispatch_for(window, hl.dsp.window.set_prop, { prop = "active_border_color", value = active })
  end
  if inactive then
    dispatch_for(window, hl.dsp.window.set_prop, { prop = "inactive_border_color", value = inactive })
  end
end

-- A window's border colour can't be handed back to the theme, only set, and it
-- survives config reloads. So windows given the theme's colours on leaving the
-- sidebar are remembered, and get the current theme's colours again on every
-- load (a theme change reloads Hyprland).
local restored_file = state_root .. "/restored-borders"

local function remember_restored(address)
  local f = io.open(restored_file, "a")
  if f then
    f:write(address, "\n")
    f:close()
  end
end

-- Hyprland turns shadows on and off for all windows at once, and Omarchy has
-- them off. So, if they're off: on, with a rule taking them off every window,
-- which sidebars override. Every other window looks as before. (If you have
-- shadows on, sidebars already have one.) Large and soft, but faint: on a
-- dark theme (its colors.toml says `mode = "dark"`) a black shadow barely
-- shows, so it's darker there to look as faint as on a light one. A theme
-- change reloads Hyprland, which loads this again.
local shadow_rule = false
if config.shadow and hl.get_config("decoration:shadow:enabled") == false then
  local dark = theme_colors:match('\n%s*mode%s*=%s*"(%a+)"') == "dark"
  hl.config({ decoration = { shadow = {
    enabled = true, range = 60, render_power = 2, offset = { 0, 0 },
    color = dark and "rgba(00000066)" or "rgba(00000030)" } } })
  hl.window_rule({ match = { class = ".*" }, no_shadow = true })
  shadow_rule = true
end

local function style(window)
  if shadow_rule then
    dispatch_for(window, hl.dsp.window.set_prop, { prop = "no_shadow", value = "0" })
  end
  dispatch_for(window, hl.dsp.window.set_prop, {
    prop = "rounding", value = config.rounding > 0 and tostring(math.floor(config.rounding)) or "unset" })
  if no_border then
    dispatch_for(window, hl.dsp.window.set_prop, { prop = "border_size", value = "0" })
  elseif config.border ~= false then
    -- The width even if the colour wasn't found (the usual colour then).
    dispatch_for(window, hl.dsp.window.set_prop, {
      prop = "border_size", value = config.border_size and tostring(math.floor(config.border_size)) or "unset" })
    if sidebar_border then
      set_border(window, sidebar_border[1], sidebar_border[2])
    end
  end
end

local function unstyle(window)
  -- Unlike a colour, these can be handed back to the config (and rules).
  dispatch_for(window, hl.dsp.window.set_prop, { prop = "border_size", value = "unset" })
  dispatch_for(window, hl.dsp.window.set_prop, { prop = "rounding", value = "unset" })
  if shadow_rule then
    dispatch_for(window, hl.dsp.window.set_prop, { prop = "no_shadow", value = "unset" })
  end
  set_border(window, theme_border("general:col.active_border"), theme_border("general:col.inactive_border"))
  remember_restored(window.address)
end

-- Hides the sidebar on screen if `leaving` was the last window in it.
local function hide_if_empty(leaving)
  -- The dispatcher acts on the active monitor; showing it elsewhere is left be.
  local shown = shown_sidebar(hl.get_active_monitor())
  if shown == nil then
    return
  end
  for _, w in ipairs(hl.get_workspace_windows(shown) or {}) do
    if w.address ~= leaving then
      return
    end
  end
  toggle_workspace(shown)
end

local function leave(window)
  local floated = was_floating[window.address]
  members[window.address] = nil
  if floated ~= nil then
    was_floating[window.address] = nil
    save_floating()
  end
  hide_if_empty(window.address)
  set_dim(window, false)
  unstyle(window)
  -- Back to floating (centred) or tiled a moment later, not inside the event
  -- that moved it out: that can come from a monitor being reconfigured, and
  -- Hyprland crashed centring a window then. Left be if it went back in.
  local address = window.address
  hl.timer(guard("returning the window", function()
    local now = current(address)
    if now == nil or members[address] then
      return
    end
    if floated then
      if now.floating then
        dispatch_for(now, hl.dsp.window.center, {})
      end
    elseif now.floating then
      dispatch_for(now, hl.dsp.window.float, { action = "toggle" })
    end
  end), { timeout = 50, type = "oneshot" })
  sync_keys()
end

-- Sends a window in a sidebar workspace back to the regular workspace on its
-- monitor as a normal window. Leaving is done here rather than left to the move
-- event: Hyprland doesn't deliver events caused from inside another event's
-- handler, which is where a stray window is usually evicted from.
local function evict(window)
  local regular = regular_workspace(window.monitor)
  if regular == nil then
    return
  end
  dispatch_for(window, hl.dsp.window.move, { workspace = workspace_target(regular.name), follow = false })
  if members[window.address] then
    leave(window)
  else
    set_dim(window, false)
    unstyle(window)
  end
end

-- `opened` is true for a window that opened straight into the sidebar (the
-- agent): it has no earlier state, so it leaves as a normal tiled window.
local function enter(window, opened)
  window = current(window.address) or window
  -- One window per sidebar workspace: another sidebar already in this one
  -- moves to a workspace of its own, anything else back to the workspace.
  if window.workspace then
    for _, other in ipairs(hl.get_workspace_windows(window.workspace.name) or {}) do
      if other.address ~= window.address then
        if members[other.address] then
          dispatch_for(other, hl.dsp.window.move, { workspace = free_workspace(), follow = false })
        else
          evict(other)
        end
      end
    end
  end

  if members[window.address] == nil then
    was_floating[window.address] = not opened and window.floating == true
    if was_floating[window.address] then
      save_floating()
    end
    members[window.address] = next_sequence()
  end
  if window.pinned then
    dispatch_for(window, hl.dsp.window.pin, {})
  end
  -- A window popped out with SUPER + O: drop Omarchy's "pop" tag, or its
  -- pop-out look (rounded corners) comes back once it leaves the sidebar.
  dispatch_for(window, hl.dsp.window.tag, { tag = "-pop" })
  if window.fullscreen and window.fullscreen ~= 0 then
    dispatch_for(window, hl.dsp.window.fullscreen, { mode = window.fullscreen == 1 and "maximized" or "fullscreen" })
  end
  if not window.floating then
    dispatch_for(window, hl.dsp.window.float, { action = "toggle" })
  end
  set_dim(window, false) -- dimmed by the window before 0.3.1
  style(window)

  -- Dock once floating has settled, or Hyprland restores the window's old
  -- floating position over ours; by then it may have closed or moved on.
  local address = window.address
  hl.timer(guard("docking", function()
    local now = current(address)
    if now and members[address] and now.floating and in_sidebar(now) then
      dock_default(now)
    end
    sync_keys()
  end), { timeout = 50, type = "oneshot" })
  sync_keys()
end

-- Focus-scoped keys -----------------------------------------------------------

-- In the sidebar: MINUS widens and EQUAL narrows it, keeping the side nearer a
-- screen edge in place; with SHIFT they change its height (the top edge stays).
-- Any other window gets Omarchy's resize.
local function resize(dx, dy)
  local window = hl.get_active_window()
  if is_member(window) and window.floating then
    local width = window.size.x - dx
    local x = window.at.x
    if window.monitor then
      local a = area(window.monitor)
      if a.right - (x + window.size.x) < x - a.left then
        x = x + window.size.x - width -- nearer the right edge: that edge stays
      end
    end
    place(window, width, window.size.y + dy, x, window.at.y)
  else
    hl.dispatch(hl.dsp.window.resize({ x = dx, y = dy, relative = true }))
  end
end

-- In the sidebar: the arrows move it a step that way (repeating while held),
-- up to the edges of the screen. Any other window gets Omarchy's swap.
local MOVE_STEP = 50
local moves = { l = { -1, 0 }, r = { 1, 0 }, u = { 0, -1 }, d = { 0, 1 } }
local function swap(direction)
  local window = hl.get_active_window()
  if is_member(window) and window.floating then
    local m = moves[direction]
    place(window, window.size.x, window.size.y, window.at.x + m[1] * MOVE_STEP, window.at.y + m[2] * MOVE_STEP)
  else
    hl.dispatch(hl.dsp.window.swap({ direction = direction }))
  end
end

-- In the sidebar: LEFT/RIGHT dock it to that screen edge, keeping its size and
-- height on screen. Any other window gets Omarchy's move into a group.
local function dock_to(direction)
  local window = hl.get_active_window()
  if is_member(window) and window.floating and window.monitor then
    local a = area(window.monitor)
    local x = direction == "l" and a.left or (a.right - window.size.x)
    place(window, window.size.x, window.size.y, x, window.at.y)
  else
    hl.dispatch(hl.dsp.window.move({ into_group = direction }))
  end
end

-- Defined with the switcher further down.
local cycle

local function bind_sidebar_keys()
  if config.sidebar.cycle then
    hl.unbind(CYCLE_KEY[1])
    o.bind(CYCLE_KEY[1], "Next sidebar", guard("showing the next sidebar", function()
      cycle()
    end))
  end
  for _, r in ipairs(resize_keys) do
    local dx, dy = r[3], r[4]
    hl.unbind(r[1])
    o.bind(r[1], r[2], guard(r[2], function()
      resize(dx, dy)
    end))
  end
  for _, s in ipairs(swap_keys) do
    local direction = s[3]
    hl.unbind(s[1])
    o.bind(s[1], "Move sidebar", guard(s[2], function()
      swap(direction)
    end), { repeating = true })
  end
  for _, g in ipairs(group_keys) do
    local direction = g[3]
    hl.unbind(g[1])
    o.bind(g[1], "Dock sidebar to the edge", guard(g[2], function()
      dock_to(direction)
    end))
  end
end

local function bind_omarchy_keys()
  if config.sidebar.cycle then
    hl.unbind(CYCLE_KEY[1])
    o.bind(CYCLE_KEY[1], CYCLE_KEY[2], hl.dsp.focus({ workspace = CYCLE_KEY[3] }))
  end
  for _, r in ipairs(resize_keys) do
    hl.unbind(r[1])
    o.bind(r[1], r[2], hl.dsp.window.resize({ x = r[3], y = r[4], relative = true }))
  end
  for _, s in ipairs(swap_keys) do
    hl.unbind(s[1])
    o.bind(s[1], s[2], hl.dsp.window.swap({ direction = s[3] }))
  end
  for _, g in ipairs(group_keys) do
    hl.unbind(g[1])
    o.bind(g[1], g[2], hl.dsp.window.move({ into_group = g[3] }))
  end
end

-- A launcher, menu, prompt or screenshot selector taking the keyboard leaves
-- the sidebar focused as far as windows go, but keys and clicks belong to it.
local function keyboard_layer_open()
  for _, l in ipairs(hl.get_layers()) do
    if l.mapped and (l.interactivity or 0) ~= 0 then
      return true
    end
  end
  return false
end

-- A plain left click outside the focused sidebar hides it. The binding doesn't
-- consume the click, so whatever was clicked still gets it. Clicking a window
-- behind the sidebar can make Hyprland hide it too, so the hide waits until the
-- click has been handled and only happens if the sidebar is still shown (the
-- dispatcher toggles, so hiding twice would show it again).
local function hide_on_outside_click()
  local window = hl.get_active_window()
  if not is_member(window) or not showing(window) or keyboard_layer_open() then
    return
  end
  local p = hl.get_cursor_pos()
  if p == nil then
    return
  end
  if p.x >= window.at.x and p.x < window.at.x + window.size.x
      and p.y >= window.at.y and p.y < window.at.y + window.size.y then
    return
  end
  -- Clicks on the bar, its panels, menus and notifications (layer surfaces
  -- above windows) leave the sidebar alone; closing such a panel would hand
  -- focus back to the hidden sidebar and show it again. The desktop
  -- background is a layer too, but below windows, so clicking it still hides.
  -- The Dock plugin's strips are layers too, invisible and taking no input,
  -- laid over the windows it pins: a click there is on the pinned window.
  for _, l in ipairs(hl.get_layers()) do
    if l.mapped and (l.layer or 0) >= 2 and l.namespace ~= "omarchy-dock-strip"
        and p.x >= l.x and p.x < l.x + l.w and p.y >= l.y and p.y < l.y + l.h then
      return
    end
  end
  -- The dispatcher acts on the active monitor, so only hide while the sidebar's
  -- monitor is still the active one (a click on another monitor makes that one
  -- active; toggling there would move the sidebar instead of hiding it).
  local monitor_id = window.monitor.id
  hl.timer(guard("hiding the sidebar", function()
    local m = hl.get_active_monitor()
    local shown = m and m.id == monitor_id and shown_sidebar(m)
    if shown and not away[shown] then
      toggle_workspace(shown)
      sync_keys()
    end
  end), { timeout = 30, type = "oneshot" })
end

-- While the visible sidebar has focus (and no launcher or menu has the
-- keyboard): SUPER + ESCAPE hides it if allowed for its kind, and the
-- resize/swap keys are the sidebar versions. Otherwise Omarchy's system menu
-- and resize/swap keys are in place. With `omarchy_default_bindings = false`
-- Omarchy's keys are left alone. (A click outside hides it through the left
-- click binding below, which is always there.)
local escape_bound = false
local switching = false -- the switcher holds HIDE_KEY while it's open
local sidebar_keys = false
function sync_keys()
  local window = hl.get_active_window()
  local visible = is_member(window) and showing(window) and not keyboard_layer_open()

  -- With Omarchy's bindings turned off, SUPER + ESCAPE may be yours: left alone.
  local want_escape = visible and config[kind(window)].escape
  if want_escape ~= escape_bound and not switching and omarchy_default_bindings ~= false then
    if want_escape then
      hl.unbind(HIDE_KEY)
      hl.bind(HIDE_KEY, guard("hiding the sidebar", hide_shown), { description = "Hide sidebar" })
    else
      hl.unbind(HIDE_KEY)
      o.bind(HIDE_KEY, "System menu", SYSTEM_MENU)
    end
    escape_bound = want_escape
  end

  local want_sidebar_keys = visible and window.floating == true and omarchy_default_bindings ~= false
  if want_sidebar_keys ~= sidebar_keys then
    if want_sidebar_keys then
      bind_sidebar_keys()
    else
      bind_omarchy_keys()
    end
    sidebar_keys = want_sidebar_keys
  end
end

-- Loading -----------------------------------------------------------------------

-- Windows already in sidebars when this loads (e.g. after a config reload),
-- in workspace order. Each gets a workspace of its own (before 0.3 there was
-- one, and a reload could find several windows in it). The moves' events fire
-- before the handlers below are registered, so nothing else sees them.
do
  local inside = sidebar_windows()
  local function number(w)
    return tonumber(w.workspace.name:match("(%d+)$")) or 1
  end
  table.sort(inside, function(a, b)
    return number(a) < number(b)
  end)
  local taken = {}
  local shown = shown_sidebar()
  for _, w in ipairs(inside) do
    members[w.address] = next_sequence()
    set_dim(w, false)
    if not sidebar_border then
      unstyle(w) -- the usual border colours
    end
    style(w)
    docked_on[w.address] = w.monitor and w.monitor.id
    if taken[w.workspace.name] then
      local target = free_workspace()
      dispatch_for(w, hl.dsp.window.move, { workspace = target, follow = false })
      taken[target] = true
    else
      taken[w.workspace.name] = true
      if w.workspace.name == shown then
        last_shown = w.address
      end
    end
  end
  -- Before 0.2 the agent had its own special workspace.
  for _, w in ipairs(hl.get_workspace_windows(LEGACY_WORKSPACE) or {}) do
    dispatch_for(w, hl.dsp.window.move, { workspace = free_workspace(), follow = false })
    enter(w)
  end  -- For the next sidebar to show (a sidebar already showing keeps its dim).
  dim_behind(shown ~= nil)
  -- `no_anim` as the drawer wants it (an earlier load may have left it on).
  for _, w in ipairs(sidebar_windows()) do
    if members[w.address] then
      set_anim(w, not (config.drawer and w.floating and not showing(w)))
    end
  end
  -- Forget windows that left or closed while this wasn't loaded.
  local pruned = false
  for address in pairs(was_floating) do
    if members[address] == nil then
      was_floating[address] = nil
      pruned = true
    end
  end
  if pruned then
    save_floating()
  end

end

-- Windows that left the sidebar earlier: the current theme's border colours
-- again, and forget the ones that have closed.
do
  local f = io.open(restored_file, "r")
  local keep = {}
  if f then
    for address in f:lines() do
      local w = current(address)
      -- Not one pinned since (the Dock plugin gives those their own border).
      if w and not in_sidebar(w) and not w.pinned and not keep[address] then
        keep[address] = true
        set_border(w, theme_border("general:col.active_border"), theme_border("general:col.inactive_border"))
      end
    end
    f:close()
  end
  f = io.open(restored_file, "w")
  if f then
    for address in pairs(keep) do
      f:write(address, "\n")
    end
    f:close()
  end
end

-- Events --------------------------------------------------------------------------

local function sync_soon()
  hl.timer(guard("updating sidebar keys", sync_keys), { timeout = 1, type = "oneshot" })
end

hl.on("window.active", guard("focus change", sync_keys))
hl.on("layer.opened", guard("updating sidebar keys", sync_soon))
hl.on("layer.closed", guard("updating sidebar keys", sync_soon))

hl.on("workspace.special_active", guard("showing the sidebar", function()
  local monitor = hl.get_active_monitor()
  local shown = monitor and shown_sidebar(monitor)
  if shown then
    for _, w in ipairs(hl.get_workspace_windows(shown) or {}) do
      if members[w.address] then
        last_shown = w.address
        -- Shown on another monitor than it was docked on: dock it there.
        if w.floating and docked_on[w.address] ~= nil and docked_on[w.address] ~= monitor.id then
          dock_default(w)
        end
      end
    end
  end
  dim_behind(shown ~= nil)
  drawer_sync()
  sync_keys()
end))

-- A new window lands on whatever special workspace is on screen. Only the agent
-- belongs in the sidebar (its window rule puts it there); anything else (a
-- dialog, a browser opened from the sidebar, a terminal opened while it had
-- focus) goes to the regular workspace instead of replacing the sidebar.
hl.on("window.open", guard("opening a window", function(window)
  -- Omarchy's screensaver (a fullscreen window per monitor): a sidebar shown
  -- there would stay on top of it, so it hides. The dispatcher acts on the
  -- active monitor, which is the one the screensaver is opening on.
  if window.class == "org.omarchy.screensaver" then
    local m = hl.get_active_monitor()
    local shown = m and shown_sidebar(m)
    if shown and window.monitor and window.monitor.id == m.id then
      toggle_workspace(shown, true)
      -- Hiding hands focus back to the workspace, and the screensaver quits
      -- when it loses focus: so it gets it back.
      local address = window.address
      hl.timer(guard("refocusing the screensaver", function()
        if current(address) then
          focus(current(address))
        end
      end), { timeout = 20, type = "oneshot" })
    end
    return
  end
  if not in_sidebar(window) then
    return
  end
  if is_agent(window) then
    enter(window, true)
  else
    local regular = regular_workspace(window.monitor)
    if regular then
      dispatch_for(window, hl.dsp.window.move, { workspace = workspace_target(regular.name) })
    end
  end
end))

-- `window.close` rather than `window.destroy`: by destroy time the window has
-- expired and its fields read as nil.
hl.on("window.close", guard("closing a window", function(window)
  local address = window and window.address
  if address then
    members[address] = nil
    if was_floating[address] ~= nil then
      was_floating[address] = nil
      save_floating()
    end
    docked_on[address] = nil
  end
  sync_soon()
end))

hl.on("window.move_to_workspace", guard("moving a window", function(window, workspace)
  if window == nil or workspace == nil then
    return
  end
  if is_sidebar_workspace(workspace.name) then
    enter(window)
  elseif members[window.address] then
    leave(window)
  end
end))

-- Actions -------------------------------------------------------------------------

-- The sidebars in the order they were added. A window in a sidebar workspace
-- that isn't one yet (left there by something else) becomes one.
local function sidebar_list()
  local list = {}
  for _, w in ipairs(sidebar_windows()) do
    if members[w.address] == nil then
      enter(w)
    end
    list[#list + 1] = w
  end
  table.sort(list, function(a, b)
    return members[a.address] < members[b.address]
  end)
  return list
end

-- The sidebar shown last, else the first.
local function last_sidebar(list)
  for _, w in ipairs(list) do
    if w.address == last_shown then
      return w
    end
  end
  return list[1]
end

-- Shows the window's sidebar (hiding any other) and focuses it.
local function show(window)
  if shown_sidebar() ~= window.workspace.name then
    toggle_workspace(window.workspace.name)
  end
  last_shown = window.address
  focus(window)
end

local function read_line(path)
  local f = io.open(path, "r")
  if f == nil then
    return nil
  end
  local line = f:read("l")
  f:close()
  return line
end

-- The current session's window (bin/agent-sidebar keeps the earlier ones
-- running, hidden). A window with the plain class is another agent's, or a
-- Claude window from before 0.14.0: current unless legacy-session says it runs
-- another session.
local function agent_window()
  if agent_class == nil then
    return nil
  end
  local session = read_line(state_root .. "/agent/session-id") or ""
  local legacy = read_line(state_root .. "/agent/legacy-session")
  local own = agent_class .. "." .. session:sub(1, 8)
  local plain
  for _, w in ipairs(hl.get_windows()) do
    if session ~= "" and w.class == own then
      return w
    elseif w.class == agent_class then
      plain = w
    end
  end
  if plain and (legacy == nil or legacy == session) then
    return plain
  end
end

-- Switcher ----------------------------------------------------------------------

-- SUPER + B with two or more sidebars opens the switcher: Service.qml draws a
-- live preview of each sidebar in the middle of the screen, one highlighted.
-- Each further B (SUPER still held) highlights the next; letting go of SUPER
-- shows the highlighted one, and SUPER + ESCAPE closes it without a change.
-- Every message carries the whole state and a sequence number, as each one is a
-- separate process and they can arrive out of order. The numbers start again
-- whenever Hyprland reloads this file, while the shell keeps running, so they
-- also carry an id for this load: the shell takes any message from a new one.
--
-- Letting go of SUPER is watched for by polling: a release binding on SUPER
-- only fires if SUPER was the last key pressed, and here B came after it.
local SUPER_KEYS = { "Super_L", "Super_R" }
local POLL_MS = 20
local switcher = nil -- { windows, index, seq } while open
local switcher_seq = 0
math.randomseed(os.time() + math.floor(os.clock() * 1000000))
local switcher_session = string.format("%d-%d", os.time(), math.random(1, 1000000000))

local function json_string(value)
  local escaped = tostring(value):gsub('[%c"\\]', function(c)
    local named = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\t"] = "\\t", ["\r"] = "\\r" }
    return named[c] or string.format("\\u%04x", c:byte())
  end)
  return '"' .. escaped .. '"'
end

local function switcher_send(method, argument)
  hl.exec_cmd("omarchy-shell -q sidebar-switcher " .. method .. " " .. quote(argument))
end

local function switcher_update()
  switcher_seq = switcher_seq + 1
  switcher.seq = switcher_seq
  local items = {}
  for i, w in ipairs(switcher.windows) do
    items[i] = string.format('{"address":%s,"title":%s,"width":%d,"height":%d}',
      json_string(w.address), json_string(w.title or w.class or ""), w.size.x, w.size.y)
  end
  local monitor = hl.get_active_monitor()
  switcher_send("show", string.format('{"session":%s,"seq":%d,"index":%d,"monitor":%s,"items":[%s]}',
    json_string(switcher_session), switcher.seq, switcher.index - 1,
    json_string(monitor and monitor.name or ""), table.concat(items, ",")))
end

local function switcher_close()
  if switcher == nil then
    return
  end
  if omarchy_default_bindings ~= false then
    hl.unbind(HIDE_KEY)
    escape_bound = nil -- sync_keys binds HIDE_KEY afresh, whichever way it wants
  end
  switcher_seq = switcher_seq + 1
  switcher_send("close", switcher_session .. " " .. switcher_seq)
  switcher = nil
  switching = false
  sync_keys()
end

-- SUPER let go: the highlighted sidebar shows (if it's still one).
local function switcher_commit()
  if switcher == nil then
    return
  end
  local chosen = current(switcher.windows[switcher.index].address)
  switcher_close()
  if chosen and is_member(chosen) then
    show(chosen)
  end
end

local function super_down()
  for _, key in ipairs(SUPER_KEYS) do
    local ok, down = pcall(hl.is_key_down, key)
    if ok and down then
      return true
    end
  end
  return false
end

-- Checks for SUPER let go until this switcher closes (by choice or cancel).
local function watch_super(open)
  hl.timer(guard("choosing a sidebar", function()
    if switcher ~= open then
      return
    end
    if super_down() then
      watch_super(open)
    else
      switcher_commit()
    end
  end), { timeout = POLL_MS, type = "oneshot" })
end

local function switcher_open(list, index)
  switcher = { windows = list, index = index }
  switching = true
  watch_super(switcher)
  if omarchy_default_bindings ~= false then
    hl.unbind(HIDE_KEY)
    hl.bind(HIDE_KEY, guard("closing the switcher", switcher_close), { description = "Close the sidebar switcher" })
  end
  switcher_update()
end

-- SUPER + B: hidden, the sidebar shown last comes back. Shown, the next one
-- comes in its place (wrapping round), or it hides if it's the only one. With
-- the switcher, that's the one highlighted first.
local function toggle()
  if switcher then
    switcher.index = switcher.index % #switcher.windows + 1
    switcher_update()
    return
  end
  local list = sidebar_list()
  if #list == 0 then
    if config.sidebar.convert then
      notify("No sidebar yet: focus a window and press " .. config.sidebar.convert)
    else
      notify("No sidebar yet")
    end
    return
  end
  local shown = shown_sidebar()
  local at = 0
  for i, w in ipairs(list) do
    if w.workspace.name == shown then
      at = i
    end
  end
  if #list == 1 and at == 1 then
    toggle_workspace(shown)
    return
  end
  local index = at % #list + 1
  if shown == nil then
    local last = last_sidebar(list)
    for i, w in ipairs(list) do
      if w == last then
        index = i
      end
    end
  end
  -- The switcher closes when SUPER is let go, so it needs SUPER held now.
  if config.switcher and #list > 1 and super_down() then
    switcher_open(list, index)
  else
    show(list[index])
  end
end

-- SUPER + TAB in a sidebar: the next one, as with SUPER + B (with the switcher
-- while SUPER is held), but a lone sidebar stays rather than hiding.
function cycle()
  if switcher == nil and #sidebar_list() < 2 then
    return
  end
  toggle()
end

-- Makes the window a sidebar and shows it. A window that isn't one yet moves to
-- a sidebar workspace of its own (following it shows it).
local function make_sidebar(window)
  if in_sidebar(window) then
    if not members[window.address] then
      enter(window)
    end
    show(window)
  else
    -- Hyprland won't move a pinned window (SUPER + O pins) off its workspace.
    if window.pinned then
      dispatch_for(window, hl.dsp.window.pin, {})
    end
    dim_behind(true)
    dispatch_for(window, hl.dsp.window.move, { workspace = free_workspace() })
  end
end

-- SUPER + A: the agent sidebar. Already showing: hide it. Anywhere else
-- (hidden, on a workspace, or another sidebar showing): it becomes a sidebar
-- and shows. Not running: launch it (its window rule puts it in a sidebar).
local launch_agent
local function toggle_agent()
  local window = agent_window()
  if window == nil then
    launch_agent()
  elseif showing(window) then
    toggle_workspace(window.workspace.name)
  else
    make_sidebar(window)
  end
end

-- The agent as the sidebar, shown and focused, without toggling.
local function show_agent()
  local window = agent_window()
  if window == nil then
    return false
  end
  make_sidebar(window)
  return true
end

-- The agent as the sidebar, shown, at the default size against its edge.
local function reset_agent()
  local window = agent_window()
  if window == nil then
    return false
  end
  -- Back to its default spot: flush against its edge from the top, forgetting
  -- where it was moved to (the edge stays).
  save_place("agent", { side = places.agent.side, offset = 0, top = 0 })
  if is_member(window) then
    enter(window)
    show(window)
  else
    make_sidebar(window)
  end
  return true
end

-- SUPER + ALT + B: the focused window becomes the sidebar, or the sidebar
-- becomes a normal window on the current workspace.
local function convert()
  local window = hl.get_active_window()
  if window == nil then
    return
  end
  if is_member(window) then
    local regular = regular_workspace(window.monitor)
    if regular then
      dispatch_for(window, hl.dsp.window.move, { workspace = workspace_target(regular.name) })
    end
    return
  end
  make_sidebar(window)
end

-- When the plugin unloads: the sidebar back to its monitor's workspace as a
-- normal window, so it isn't left hidden with no key to show it.
local function release()
  for _, w in ipairs(sidebar_windows()) do
    evict(w)
  end
  for _, w in ipairs(hl.get_workspace_windows(LEGACY_WORKSPACE) or {}) do
    evict(w)
  end
end

-- Keys --------------------------------------------------------------------------

local function bind(keys, description, fn)
  if keys then
    hl.unbind(keys)
    o.bind(keys, description, guard(description, fn))
  end
end

bind(config.sidebar.toggle, "Show/hide sidebar", toggle)
bind(config.sidebar.convert, "Window to/from sidebar", convert)

-- A plain left click outside the focused sidebar hides it. Bound once and for
-- good, not only while a sidebar has focus: other plugins (the Dock) bind left
-- click too, and unbinding a key removes every binding on it. The handler does
-- nothing unless a sidebar is showing with focus. It doesn't consume the click.
if config.click_outside then
  hl.bind("mouse:272", guard("hiding the sidebar", hide_on_outside_click), {
    non_consuming = true,
    description = "Hide sidebar on a click outside it",
  })
end

if agent_class then
  local script = dir .. "/bin/agent-sidebar"
  local function run(command)
    dim_behind(true) -- the agent's window rule opens it into a sidebar
    hl.exec_cmd("SIDEBAR_AGENT_CLASS=" .. quote(agent_class) .. " " .. quote(script) .. " " .. command)
  end

  -- Escape every regex metacharacter so the class matches literally.
  -- Matches the plain class and each Claude session's "<class>.<session>".
  local class_pattern = "^" .. agent_class:gsub("[%^%$%(%)%.%[%]%*%+%-%?%{%}|\\]", "\\%0") .. "(\\..+)?$"
  hl.window_rule({
    match = { class = class_pattern },
    float = true,
    workspace = WORKSPACE,
  })

  -- A second press while the agent is still starting would launch a second
  -- one (on the same session, for Claude); the script also guards this.
  local launched_at = 0
  launch_agent = function()
    if os.time() - launched_at >= 5 then
      launched_at = os.time()
      run("launch")
    end
  end
  bind(config.agent.toggle, "Agent sidebar", toggle_agent)
  bind(config.agent.new, "New agent sidebar session", function()
    run("new")
  end)
  bind(config.agent.load, "Load agent sidebar session", function()
    run("load")
  end)
  bind(config.agent.reset, "Reset agent sidebar", function()
    if not reset_agent() then
      launch_agent()
    end
  end)
else
  launch_agent = function() end
end

-- The sidebar may already have focus when this loads (e.g. after a reload).
guard("loading", sync_keys)()

-- For scripting and tests: `hyprctl eval 'sidebar.toggle("agent")'` etc.
-- "sidebar" and "agent" are accepted; other names are ignored.
sidebar = {
  toggle = function(name)
    if name == "agent" then
      toggle_agent()
    elseif name == "sidebar" or name == nil then
      toggle()
    end
  end,
  show = function(name)
    if name == "agent" then
      return show_agent()
    end
    local window = last_sidebar(sidebar_list())
    if window then
      show(window)
      return true
    end
    return false
  end,
  reset = function(name)
    if name == "agent" then
      return reset_agent()
    end
    return false
  end,
  -- SUPER + ESCAPE, for testing without keys.
  hide = hide_shown,
  convert = convert,
  swap = swap,
  dock = dock_to,
  resize = resize,
  release = release,
  -- The switcher's SUPER release and SUPER + ESCAPE, for testing without keys.
  commit = switcher_commit,
  cancel = switcher_close,
  -- The dim behind a sidebar to suit what shows now. bin/agent-sidebar calls
  -- it on exit, as starting the agent raises it ahead of a sidebar that may
  -- never show (a cancelled menu, a failed start).
  settle = function()
    dim_behind(sidebar_shown())
  end,
  -- Whether the sidebar versions of Omarchy's resize, swap and group keys are
  -- bound now (a sidebar has focus). The Dock plugin, which takes the swap keys
  -- for pinned windows, checks this before handing them back to Omarchy.
  keys_taken = function()
    return sidebar_keys
  end,
}
