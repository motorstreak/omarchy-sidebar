-- Omarchy Sidebar
--
-- The sidebar is one window docked to the left or right screen edge on its own
-- special workspace: floating, dimming the rest of the screen, shown and hidden
-- with a key. There is only ever one: making a window the sidebar sends the
-- previous one back to your workspace as a normal window. Move the sidebar to a
-- regular workspace (SUPER + SHIFT + <n>) and it is an ordinary window again,
-- following every normal Omarchy binding.
--
--   SUPER + ALT + B  the focused window becomes the sidebar (or the sidebar
--                    becomes a normal window again)
--   SUPER + B        show/hide the sidebar
--   SUPER + A        the agent sidebar: your Omarchy default coding agent
--                    (`omarchy default agent`) becomes the sidebar, launched if
--                    needed; with Claude Code it also keeps saved, searchable
--                    sessions (see bin/agent-sidebar)
--
-- In the sidebar, SUPER + SHIFT + LEFT/RIGHT docks it to that edge (remembered
-- separately for the agent and for other windows) and Omarchy's resize keys
-- resize it while keeping it docked.
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

local WORKSPACE = "special:sidebar"
local SPECIAL = "sidebar" -- the name toggle_special takes
local LEGACY_WORKSPACE = "special:agent" -- the agent's own slot before 0.2

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
  margin = 24, -- gap to the screen edges and bar
  width = 0.33, -- default width as a share of the monitor
  dim = true, -- dim the rest of the screen while the sidebar shows
  -- The sidebar's border colour: "theme" (the theme's foreground colour), a
  -- colour such as "#14B9B5" or "rgba(14b9b5ff)", or false for the usual border.
  border = "theme",
  click_outside = true, -- clicking outside the shown sidebar hides it
  sidebar = {
    toggle = "SUPER + B",
    convert = "SUPER + ALT + B",
    escape = true, -- SUPER + ESCAPE hides it (instead of opening the system menu)
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
    elseif type(v) == type(current) or (v == false and keys and keys[k]) then
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

  if config.width <= 0 or config.width > 1 then
    problems[#problems + 1] = "width must be between 0 and 1"
    config.width = 0.33
  end
  if config.margin < 0 or config.margin > 200 then
    problems[#problems + 1] = "margin must be between 0 and 200"
    config.margin = 24
  end
  if config.border and config.border ~= "theme" and not config.border:match("^#%x%x%x%x%x%x$")
      and not config.border:match("^rgba?%([%x, .]+%)$") then
    problems[#problems + 1] = "border must be \"theme\", a colour like \"#14B9B5\", or false"
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

local function is_agent(window)
  return agent_class ~= nil and window ~= nil and window.class == agent_class
end

-- Escape and the remembered side are per kind: the agent, or any other window.
local function kind(window)
  return is_agent(window) and "agent" or "sidebar"
end

-- Windows ---------------------------------------------------------------------

-- The sidebar window(s) by address, so a window leaving the sidebar can be told
-- apart from an ordinary window moving between workspaces, and whether each was
-- floating before, to put it back that way.
local members = {}
local was_floating = {}

local function selector(window)
  return "address:" .. window.address
end

local function dispatch_for(window, dsp, args)
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

local function sidebar_windows()
  return hl.get_workspace_windows(WORKSPACE) or {}
end

local function in_sidebar(window)
  return window ~= nil and window.workspace ~= nil and window.workspace.name == WORKSPACE
end

local function is_member(window)
  return in_sidebar(window) and members[window.address] == true
end

local function sidebar_shown(monitor)
  monitor = monitor or hl.get_active_monitor()
  local shown = monitor and monitor.active_special_workspace
  return shown ~= nil and shown.name == WORKSPACE
end

local function focus(window)
  hl.dispatch(hl.dsp.focus({ window = selector(window) }))
end

-- Remembered sides ------------------------------------------------------------

os.execute("mkdir -p " .. quote(state_root))

local sides = {}
for _, k in ipairs({ "agent", "sidebar" }) do
  sides[k] = "right"
  local f = io.open(state_root .. "/" .. k .. ".side", "r")
  if f then
    if f:read("l") == "left" then
      sides[k] = "left"
    end
    f:close()
  end
end

local function save_side(k, side)
  sides[k] = side
  local f = io.open(state_root .. "/" .. k .. ".side", "w")
  if f then
    f:write(side, "\n")
    f:close()
  end
end

-- Geometry -------------------------------------------------------------------

local function area(m)
  local r = m.reserved or {}
  local margin = config.margin
  local mw, mh = m.width / m.scale, m.height / m.scale
  -- Rotated by 90 or 270 degrees (also when flipped): width and height swap.
  if (m.transform or 0) % 2 == 1 then
    mw, mh = mh, mw
  end
  return {
    left = m.x + (r.left or 0) + margin,
    right = m.x + mw - (r.right or 0) - margin,
    top = m.y + (r.top or 0) + margin,
    bottom = m.y + mh - (r.bottom or 0) - margin,
    width = mw,
  }
end

-- The monitor the sidebar was last docked on, to re-dock it when it's shown on
-- another one.
local docked_monitor = nil

-- Docks the window to its edge at the given size (clamped to the monitor),
-- keeping the given top edge, or the top of the usable area.
local function dock(window, width, height, top)
  if window.monitor == nil then
    return
  end
  local a = area(window.monitor)
  local max_width, max_height = a.right - a.left, a.bottom - a.top
  width = math.floor(math.min(math.max(width, math.min(360, max_width)), max_width))
  height = math.floor(math.min(math.max(height, math.min(300, max_height)), max_height))
  top = math.floor(math.min(math.max(top or a.top, a.top), a.bottom - height))
  local x = math.floor(sides[kind(window)] == "left" and a.left or (a.right - width))

  dispatch_for(window, hl.dsp.window.resize, { x = width, y = height })
  dispatch_for(window, hl.dsp.window.move, { x = x, y = top })
  docked_monitor = window.monitor.id
end

local function dock_default(window)
  if window.monitor == nil then
    return
  end
  local a = area(window.monitor)
  dock(window, a.width * config.width, a.bottom - a.top)
end

-- Entering and leaving the sidebar --------------------------------------------

-- Defined further down; entering and leaving re-check the sidebar keys, since a
-- new window's focus event can arrive before it has entered the sidebar.
local sync_keys

local function set_dim(window, on)
  dispatch_for(window, hl.dsp.window.set_prop, { prop = "dim_around", value = on and "1" or "0" })
end

-- The sidebar's border colours (focused, unfocused), or nil to leave borders be.
local sidebar_border = nil
do
  local spec = config.border
  local hex = nil
  if spec == "theme" then
    local f = io.open(state_home .. "/omarchy/current/theme/colors.toml", "r")
    if f then
      hex = ("\n" .. f:read("a")):match('\n%s*foreground%s*=%s*"#?(%x%x%x%x%x%x)"')
      f:close()
    end
  elseif spec then
    hex = spec:match("^#(%x%x%x%x%x%x)$")
    if hex == nil then
      sidebar_border = { spec, spec }
    end
  end
  if hex then
    sidebar_border = { "rgba(" .. hex .. "ff)", "rgba(" .. hex .. "aa)" }
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

local function style(window)
  if sidebar_border then
    set_border(window, sidebar_border[1], sidebar_border[2])
  end
end

local function unstyle(window)
  set_border(window, theme_border("general:col.active_border"), theme_border("general:col.inactive_border"))
  remember_restored(window.address)
end

-- Hides the sidebar if it is on screen and `leaving` was the last window in it.
local function hide_if_empty(leaving)
  for _, w in ipairs(sidebar_windows()) do
    if w.address ~= leaving then
      return
    end
  end
  -- The dispatcher acts on the active monitor; showing it elsewhere is left be.
  if sidebar_shown(hl.get_active_monitor()) then
    hl.dispatch(hl.dsp.workspace.toggle_special(SPECIAL))
  end
end

local function leave(window)
  local floated = was_floating[window.address]
  members[window.address] = nil
  was_floating[window.address] = nil
  hide_if_empty(window.address)
  set_dim(window, false)
  unstyle(window)
  if floated then
    if window.floating then
      dispatch_for(window, hl.dsp.window.center, {})
    end
  elseif window.floating then
    dispatch_for(window, hl.dsp.window.float, { action = "toggle" })
  end
  sync_keys()
end

-- Sends a window in the sidebar workspace back to the regular workspace on its
-- monitor as a normal window. Leaving is done here rather than left to the move
-- event: Hyprland doesn't deliver events caused from inside another event's
-- handler, which is where a replaced sidebar is usually evicted from.
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
  -- Only one sidebar: anything else in it goes back to the workspace.
  for _, other in ipairs(sidebar_windows()) do
    if other.address ~= window.address then
      evict(other)
    end
  end

  if members[window.address] == nil then
    was_floating[window.address] = not opened and window.floating == true
  end
  members[window.address] = true
  if window.pinned then
    dispatch_for(window, hl.dsp.window.pin, {})
  end
  if window.fullscreen and window.fullscreen ~= 0 then
    dispatch_for(window, hl.dsp.window.fullscreen, { mode = window.fullscreen == 1 and "maximized" or "fullscreen" })
  end
  if not window.floating then
    dispatch_for(window, hl.dsp.window.float, { action = "toggle" })
  end
  set_dim(window, config.dim)
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

-- In the docked sidebar: MINUS widens and EQUAL narrows it away from its edge,
-- with SHIFT they change its height (the top edge stays). Any other window gets
-- Omarchy's resize.
local function resize(dx, dy)
  local window = hl.get_active_window()
  if is_member(window) and window.floating then
    dock(window, window.size.x - dx, window.size.y + dy, window.at.y)
  else
    hl.dispatch(hl.dsp.window.resize({ x = dx, y = dy, relative = true }))
  end
end

-- In the docked sidebar: LEFT/RIGHT dock it to that edge (keeping its size) and
-- remember the side; UP/DOWN do nothing. Any other window gets Omarchy's swap.
local function swap(direction)
  local window = hl.get_active_window()
  if is_member(window) and window.floating then
    if direction == "l" or direction == "r" then
      save_side(kind(window), direction == "l" and "left" or "right")
      dock(window, window.size.x, window.size.y, window.at.y)
    end
  else
    hl.dispatch(hl.dsp.window.swap({ direction = direction }))
  end
end

local function bind_sidebar_keys()
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
    o.bind(s[1], s[2], guard(s[2], function()
      swap(direction)
    end))
  end
end

local function bind_omarchy_keys()
  for _, r in ipairs(resize_keys) do
    hl.unbind(r[1])
    o.bind(r[1], r[2], hl.dsp.window.resize({ x = r[3], y = r[4], relative = true }))
  end
  for _, s in ipairs(swap_keys) do
    hl.unbind(s[1])
    o.bind(s[1], s[2], hl.dsp.window.swap({ direction = s[3] }))
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
  if not is_member(window) or not sidebar_shown(window.monitor) or keyboard_layer_open() then
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
  for _, l in ipairs(hl.get_layers()) do
    if l.mapped and (l.layer or 0) >= 2 and p.x >= l.x and p.x < l.x + l.w
        and p.y >= l.y and p.y < l.y + l.h then
      return
    end
  end
  -- The dispatcher acts on the active monitor, so only hide while the sidebar's
  -- monitor is still the active one (a click on another monitor makes that one
  -- active; toggling there would move the sidebar instead of hiding it).
  local monitor_id = window.monitor.id
  hl.timer(guard("hiding the sidebar", function()
    local m = hl.get_active_monitor()
    if m and m.id == monitor_id and sidebar_shown(m) then
      hl.dispatch(hl.dsp.workspace.toggle_special(SPECIAL))
      sync_keys()
    end
  end), { timeout = 30, type = "oneshot" })
end

-- While the visible sidebar has focus (and no launcher or menu has the
-- keyboard): SUPER + ESCAPE hides it if allowed for its kind, a click outside
-- hides it, and the resize/swap keys are the sidebar versions. Otherwise the
-- click is unbound (this owns plain left click: any other such binding is
-- dropped) and Omarchy's system menu and resize/swap keys are in place. With
-- `omarchy_default_bindings = false` Omarchy's keys are left alone.
local escape_bound = false
local sidebar_keys = false
local click_bound = false
function sync_keys()
  local window = hl.get_active_window()
  local visible = is_member(window) and sidebar_shown(window.monitor) and not keyboard_layer_open()

  local want_escape = visible and config[kind(window)].escape
  if want_escape ~= escape_bound then
    if want_escape then
      hl.unbind(HIDE_KEY)
      hl.bind(HIDE_KEY, hl.dsp.workspace.toggle_special(SPECIAL), { description = "Hide sidebar" })
    else
      hl.unbind(HIDE_KEY)
      if omarchy_default_bindings ~= false then
        o.bind(HIDE_KEY, "System menu", SYSTEM_MENU)
      end
    end
    escape_bound = want_escape
  end

  local want_click = visible and config.click_outside
  if want_click ~= click_bound then
    if want_click then
      hl.bind("mouse:272", guard("hiding the sidebar", hide_on_outside_click), {
        non_consuming = true,
        description = "Hide sidebar on a click outside it",
      })
    else
      hl.unbind("mouse:272")
    end
    click_bound = want_click
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

-- Windows already in the sidebar when this loads (e.g. after a config reload).
-- Only one stays: the focused one, else the first.
do
  local inside = sidebar_windows()
  local keep = inside[1]
  local active = hl.get_active_window()
  for _, w in ipairs(inside) do
    if active and w.address == active.address then
      keep = w
    end
  end
  for _, w in ipairs(inside) do
    if w == keep then
      members[w.address] = true
      set_dim(w, config.dim)
      if sidebar_border then
        style(w)
      else
        unstyle(w)
      end
      docked_monitor = w.monitor and w.monitor.id
    else
      set_dim(w, false)
      evict(w)
    end
  end
  -- Before 0.2 the agent had its own special workspace.
  -- The move's event fires before the handlers below are registered, so the
  -- window enters here.
  for _, w in ipairs(hl.get_workspace_windows(LEGACY_WORKSPACE) or {}) do
    if keep == nil then
      keep = w
      dispatch_for(w, hl.dsp.window.move, { workspace = WORKSPACE, follow = false })
      enter(w)
    else
      set_dim(w, false)
      evict(w)
    end
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
      if w and not in_sidebar(w) and not keep[address] then
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
  -- Shown on another monitor than it was docked on: dock it there.
  local monitor = hl.get_active_monitor()
  if monitor and sidebar_shown(monitor) and docked_monitor ~= nil and docked_monitor ~= monitor.id then
    for _, w in ipairs(sidebar_windows()) do
      if members[w.address] and w.floating then
        dock_default(w)
      end
    end
  end
  sync_keys()
end))

-- A new window lands on whatever special workspace is on screen. Only the agent
-- belongs in the sidebar (its window rule puts it there); anything else (a
-- dialog, a browser opened from the sidebar, a terminal opened while it had
-- focus) goes to the regular workspace instead of replacing the sidebar.
hl.on("window.open", guard("opening a window", function(window)
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
    was_floating[address] = nil
  end
  sync_soon()
end))

hl.on("window.move_to_workspace", guard("moving a window", function(window, workspace)
  if window == nil or workspace == nil then
    return
  end
  if workspace.name == WORKSPACE then
    enter(window)
  elseif members[window.address] then
    leave(window)
  end
end))

-- Actions -------------------------------------------------------------------------

local function sidebar_window()
  local inside = sidebar_windows()
  for _, w in ipairs(inside) do
    if members[w.address] then
      return w
    end
  end
  return inside[1]
end

local function agent_window()
  if agent_class == nil then
    return nil
  end
  for _, w in ipairs(hl.get_windows()) do
    if w.class == agent_class then
      return w
    end
  end
end

-- Show/hide the sidebar, whichever window it is.
local function toggle()
  local window = sidebar_window()
  if window == nil then
    if config.sidebar.convert then
      notify("No sidebar yet: focus a window and press " .. config.sidebar.convert)
    else
      notify("No sidebar yet")
    end
    return
  end
  if not members[window.address] then
    enter(window)
  end
  hl.dispatch(hl.dsp.workspace.toggle_special(SPECIAL))
end

-- Makes the window the sidebar and shows it. Moving it in (following it shows
-- the sidebar) sends the previous sidebar back to the workspace.
local function make_sidebar(window)
  if in_sidebar(window) then
    if not members[window.address] then
      enter(window)
    end
    if not sidebar_shown(window.monitor) then
      hl.dispatch(hl.dsp.workspace.toggle_special(SPECIAL))
    end
    focus(window)
  else
    dispatch_for(window, hl.dsp.window.move, { workspace = WORKSPACE })
  end
end

-- SUPER + A: the agent is the sidebar. Already the shown sidebar: hide it.
-- Anywhere else (hidden, on a workspace, or another window is the sidebar): it
-- becomes the sidebar, shown. Not running: launch it (its window rule puts it
-- in the sidebar).
local launch_agent
local function toggle_agent()
  local window = agent_window()
  if window == nil then
    launch_agent()
  elseif in_sidebar(window) and sidebar_shown(window.monitor) then
    hl.dispatch(hl.dsp.workspace.toggle_special(SPECIAL))
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

-- The agent as the sidebar, shown, at the default size on its remembered side.
local function reset_agent()
  local window = agent_window()
  if window == nil then
    return false
  end
  if is_member(window) then
    enter(window)
    if not sidebar_shown(window.monitor) then
      hl.dispatch(hl.dsp.workspace.toggle_special(SPECIAL))
    end
    focus(window)
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
  for _, name in ipairs({ WORKSPACE, LEGACY_WORKSPACE }) do
    for _, w in ipairs(hl.get_workspace_windows(name) or {}) do
      evict(w)
    end
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

if agent_class then
  local script = dir .. "/bin/agent-sidebar"
  local function run(command)
    hl.exec_cmd("SIDEBAR_AGENT_CLASS=" .. quote(agent_class) .. " " .. quote(script) .. " " .. command)
  end

  -- Escape every regex metacharacter so the class matches literally.
  local class_pattern = "^" .. agent_class:gsub("[%^%$%(%)%.%[%]%*%+%-%?%{%}|\\]", "\\%0") .. "$"
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
    local window = sidebar_window()
    if window then
      make_sidebar(window)
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
  convert = convert,
  swap = swap,
  resize = resize,
  release = release,
}
