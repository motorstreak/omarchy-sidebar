-- Omarchy Sidebar
--
-- A sidebar is a window docked to the left or right screen edge on its own
-- special workspace: floating, dimming the rest of the screen, shown and hidden
-- with a key. Move it to a regular workspace (SUPER + SHIFT + <n>) and it is an
-- ordinary window again, following every normal Omarchy binding.
--
-- Slots:
--   sidebar  the generic slot: SUPER + ALT + B turns the focused window into
--            the sidebar (or the sidebar back into a normal window); SUPER + B
--            shows/hides it. Converting another window returns the previous
--            one to your workspace.
--   agent    your Omarchy default coding agent (`omarchy default agent`) as a
--            sidebar with its own key; with Claude Code it also keeps saved,
--            searchable sessions (see bin/agent-sidebar).
--
-- In any sidebar, SUPER + SHIFT + LEFT/RIGHT docks it to that edge (remembered
-- per slot) and Omarchy's resize keys resize it while keeping it docked.
--
-- Loaded into the running Hyprland by Service.qml with SIDEBAR_DIR set to the
-- plugin folder. Keys and options can be overridden in
-- ~/.config/omarchy/sidebar.lua (a Lua file returning a table like `config`).

if SIDEBAR_LOADED then
  return
end
SIDEBAR_LOADED = true

local dir = SIDEBAR_DIR
local home = os.getenv("HOME")
local state_root = (os.getenv("XDG_STATE_HOME") or (home .. "/.local/state")) .. "/omarchy-sidebar"

local config = {
  margin = 24, -- gap to the screen edges and bar
  width = 0.33, -- default width as a share of the monitor
  dim = true, -- dim the rest of the screen while a sidebar shows
  sidebar = {
    toggle = "SUPER + B",
    convert = "SUPER + ALT + B",
    escape = false, -- ESCAPE hides it; off since many apps use ESCAPE
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

local function merge(into, from)
  for k, v in pairs(from) do
    if type(v) == "table" and type(into[k]) == "table" then
      merge(into[k], v)
    else
      into[k] = v
    end
  end
end

local user_config = loadfile(home .. "/.config/omarchy/sidebar.lua")
if user_config then
  local ok, overrides = pcall(user_config)
  if ok and type(overrides) == "table" then
    merge(config, overrides)
  end
end

local slots = {
  sidebar = { name = "sidebar", workspace = "special:sidebar", escape = config.sidebar.escape },
}
if config.agent.enabled then
  slots.agent = { name = "agent", workspace = "special:agent", escape = config.agent.escape, class = config.agent.class }
end

local function slot_for_workspace(name)
  for _, slot in pairs(slots) do
    if slot.workspace == name then
      return slot
    end
  end
end

-- Sidebar windows by address, so a window leaving its slot can be told apart
-- from an ordinary window moving between workspaces.
local members = {}

local function selector(window)
  return "address:" .. window.address
end

local function dispatch_for(window, dsp, args)
  args.window = selector(window)
  hl.dispatch(dsp(args))
end

local function notify(message)
  hl.exec_cmd("notify-send 'Sidebar' '" .. message:gsub("'", "") .. "'")
end

-- Per-slot remembered side --------------------------------------------------

local function side_file(slot)
  return state_root .. "/" .. slot.name .. ".side"
end

local function read_side(slot)
  local f = io.open(side_file(slot), "r")
  if not f then
    return "right"
  end
  local side = f:read("l")
  f:close()
  return side == "left" and "left" or "right"
end

for _, slot in pairs(slots) do
  slot.side = read_side(slot)
end

local function save_side(slot, side)
  slot.side = side
  os.execute("mkdir -p '" .. state_root .. "'")
  local f = io.open(side_file(slot), "w")
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
  return {
    left = m.x + (r.left or 0) + margin,
    right = m.x + mw - (r.right or 0) - margin,
    top = m.y + (r.top or 0) + margin,
    bottom = m.y + mh - (r.bottom or 0) - margin,
    width = mw,
  }
end

-- Docks the window to its slot's edge at the given size (clamped to the
-- monitor), keeping the given top edge, or the top of the usable area.
local function dock(window, slot, width, height, top)
  local a = area(window.monitor)
  width = math.max(360, math.min(math.floor(width), a.right - a.left))
  top = math.max(a.top, top or a.top)
  height = math.max(300, math.min(math.floor(height), a.bottom - top))
  local x = slot.side == "left" and a.left or (a.right - width)

  dispatch_for(window, hl.dsp.window.resize, { x = width, y = height })
  dispatch_for(window, hl.dsp.window.move, { x = math.floor(x), y = math.floor(top) })
end

local function dock_default(window, slot)
  local a = area(window.monitor)
  dock(window, slot, a.width * config.width, a.bottom - a.top)
end

-- Entering and leaving sidebar mode -------------------------------------------

local function slot_shown(slot, monitor)
  local shown = (monitor or hl.get_active_monitor()).active_special_workspace
  return shown ~= nil and shown.name == slot.workspace
end

local function set_dim(window, on)
  if config.dim then
    dispatch_for(window, hl.dsp.window.set_prop, { prop = "dim_around", value = on and "1" or "0" })
  end
end

local function enter(window, slot)
  members[window.address] = slot
  if not window.floating then
    dispatch_for(window, hl.dsp.window.float, { action = "toggle" })
  end
  set_dim(window, true)
  -- Dock once floating has settled, or Hyprland restores the window's old
  -- floating position over ours.
  hl.timer(function()
    dock_default(window, slot)
  end, { timeout = 50, type = "oneshot" })
end

local function leave(window, slot)
  members[window.address] = nil
  -- Moved out silently, the now-empty slot workspace would stay on screen.
  if slot_shown(slot, window.monitor) then
    hl.dispatch(hl.dsp.workspace.toggle_special(slot.name))
  end
  set_dim(window, false)
  if window.floating then
    dispatch_for(window, hl.dsp.window.float, { action = "toggle" })
  end
end

local function slot_windows(slot)
  local found = {}
  for _, w in ipairs(hl.get_windows()) do
    if w.workspace ~= nil and w.workspace.name == slot.workspace then
      found[#found + 1] = w
    end
  end
  return found
end

-- Windows already in a slot when this loads (e.g. after a config reload).
for _, slot in pairs(slots) do
  for _, w in ipairs(slot_windows(slot)) do
    members[w.address] = slot
    set_dim(w, true)
  end
end

local function member_slot(window)
  if window == nil or window.workspace == nil then
    return nil
  end
  local slot = slot_for_workspace(window.workspace.name)
  if slot and members[window.address] == slot then
    return slot
  end
end

-- ESCAPE hides a visible, focused sidebar whose slot allows it; it is unbound
-- otherwise so ESCAPE reaches apps everywhere else.
local escape_bound = false
local function sync_escape()
  local window = hl.get_active_window()
  local slot = member_slot(window)
  local want = slot ~= nil and slot.escape and slot_shown(slot, window.monitor)
  if want then
    hl.unbind("ESCAPE")
    hl.bind("ESCAPE", hl.dsp.workspace.toggle_special(slot.name), { description = "Hide sidebar" })
  elseif escape_bound then
    hl.unbind("ESCAPE")
  end
  escape_bound = want
end

hl.on("window.active", sync_escape)
hl.on("workspace.special_active", sync_escape)

hl.on("window.open", function(window)
  local slot = window and window.workspace and slot_for_workspace(window.workspace.name)
  if slot then
    enter(window, slot)
  end
end)

hl.on("window.destroy", function(window)
  if window then
    members[window.address] = nil
  end
end)

hl.on("window.move_to_workspace", function(window, workspace)
  if window == nil then
    return
  end
  local target = slot_for_workspace(workspace.name)
  local current = members[window.address]
  if target then
    enter(window, target)
  elseif current then
    leave(window, current)
  end
  sync_escape()
end)

-- Keys -------------------------------------------------------------------------

local function bind(keys, description, fn)
  if keys then
    hl.unbind(keys)
    o.bind(keys, description, fn)
  end
end

local function find_window(slot)
  -- A slot's own windows first, then (for app slots) its app wherever it is.
  local inside = slot_windows(slot)
  if inside[1] then
    return inside[1]
  end
  if slot.class then
    for _, w in ipairs(hl.get_windows()) do
      if w.class == slot.class then
        return w
      end
    end
  end
end

-- Show/hide a slot. If its window was moved out to a regular workspace: jump to
-- it, or, when it already has focus there, send it back into the slot (hidden).
local function toggle(slot)
  local window = find_window(slot)
  if window == nil then
    if slot.launch then
      slot.launch()
    else
      notify("No sidebar yet: focus a window and press " .. config.sidebar.convert)
    end
    return
  end

  if member_slot(window) == slot then
    hl.dispatch(hl.dsp.workspace.toggle_special(slot.name))
    return
  end

  local active = hl.get_active_window()
  local on_screen = window.workspace.name == hl.get_active_workspace().name
  if active and active.address == window.address and on_screen then
    dispatch_for(window, hl.dsp.window.move, { workspace = slot.workspace, follow = false })
  else
    hl.dispatch(hl.dsp.focus({ window = selector(window) }))
  end
end

-- Make a slot's window visible without toggling: show the slot, or focus the
-- window if it was moved out to a workspace.
local function show(slot)
  local window = find_window(slot)
  if window == nil then
    return false
  end
  if member_slot(window) == slot then
    if not slot_shown(slot, window.monitor) then
      hl.dispatch(hl.dsp.workspace.toggle_special(slot.name))
    end
  end
  hl.dispatch(hl.dsp.focus({ window = selector(window) }))
  return true
end

-- Back into the slot, shown, at the default size on its remembered side.
local function reset(slot)
  local window = find_window(slot)
  if window == nil then
    return false
  end
  if member_slot(window) ~= slot then
    -- Following the move shows the slot; entering it docks the window.
    dispatch_for(window, hl.dsp.window.move, { workspace = slot.workspace })
    return true
  end
  enter(window, slot)
  if not slot_shown(slot, window.monitor) then
    hl.dispatch(hl.dsp.workspace.toggle_special(slot.name))
  end
  hl.dispatch(hl.dsp.focus({ window = selector(window) }))
  return true
end

-- Turn the focused window into a sidebar, or a sidebar back into a window on
-- the current workspace. App windows go to their own slot.
local function convert()
  local window = hl.get_active_window()
  if window == nil then
    return
  end

  local current = member_slot(window)
  if current then
    dispatch_for(window, hl.dsp.window.move, { workspace = window.monitor.active_workspace.name })
    return
  end

  local slot = slots.sidebar
  for _, s in pairs(slots) do
    if s.class and s.class == window.class then
      slot = s
    end
  end

  local here = hl.get_active_workspace().name
  for _, other in ipairs(slot_windows(slot)) do
    dispatch_for(other, hl.dsp.window.move, { workspace = here, follow = false })
  end
  dispatch_for(window, hl.dsp.window.move, { workspace = slot.workspace })
end

bind(config.sidebar.toggle, "Show/hide sidebar", function()
  toggle(slots.sidebar)
end)
bind(config.sidebar.convert, "Window to/from sidebar", convert)

if slots.agent then
  local script = dir .. "/bin/agent-sidebar"
  local function run(command)
    hl.exec_cmd("SIDEBAR_AGENT_CLASS='" .. slots.agent.class .. "' '" .. script .. "' " .. command)
  end

  hl.window_rule({
    match = { class = "^" .. slots.agent.class:gsub("%.", "\\.") .. "$" },
    float = true,
    workspace = slots.agent.workspace,
  })

  -- A second press while the agent is still starting would launch a second
  -- one (on the same session, for Claude); the script also guards this.
  local launched_at = 0
  slots.agent.launch = function()
    if os.time() - launched_at >= 5 then
      launched_at = os.time()
      run("launch")
    end
  end
  bind(config.agent.toggle, "Agent sidebar", function()
    toggle(slots.agent)
  end)
  bind(config.agent.new, "New agent sidebar session", function()
    run("new")
  end)
  bind(config.agent.load, "Load agent sidebar session", function()
    run("load")
  end)
  bind(config.agent.reset, "Reset agent sidebar", function()
    if not reset(slots.agent) then
      slots.agent.launch()
    end
  end)
end

-- Omarchy's swap keys: in a sidebar, LEFT/RIGHT dock it to that edge (keeping
-- its size) and remember the side; UP/DOWN do nothing. Others swap as usual.
local function swap(direction)
  local window = hl.get_active_window()
  local slot = member_slot(window)
  if slot and window.floating then
    if direction == "l" or direction == "r" then
      save_side(slot, direction == "l" and "left" or "right")
      dock(window, slot, window.size.x, window.size.y, window.at.y)
    end
  else
    hl.dispatch(hl.dsp.window.swap({ direction = direction }))
  end
end

for _, s in ipairs({
  { "LEFT", "l", "Swap window to the left" },
  { "RIGHT", "r", "Swap window to the right" },
  { "UP", "u", "Swap window up" },
  { "DOWN", "d", "Swap window down" },
}) do
  local key, direction, description = s[1], s[2], s[3]
  bind("SUPER + SHIFT + " .. key, description, function()
    swap(direction)
  end)
end

-- Omarchy's resize keys: in a sidebar they keep it docked to its edge (MINUS
-- widens, EQUAL narrows; with SHIFT they change the height from the top edge).
-- Others get Omarchy's usual relative resize.
local function resize(dx, dy)
  local window = hl.get_active_window()
  local slot = member_slot(window)
  if slot and window.floating then
    dock(window, slot, window.size.x - dx, window.size.y + dy, window.at.y)
  else
    hl.dispatch(hl.dsp.window.resize({ x = dx, y = dy, relative = true }))
  end
end

for _, r in ipairs({
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
}) do
  local keys, description, dx, dy = r[1], r[2], r[3], r[4]
  bind(keys, description, function()
    resize(dx, dy)
  end)
end

-- For testing and scripting: `hyprctl eval 'sidebar.toggle("agent")'` etc.
sidebar = {
  slots = slots,
  toggle = function(name)
    toggle(slots[name])
  end,
  reset = function(name)
    return reset(slots[name])
  end,
  show = function(name)
    return show(slots[name])
  end,
  convert = convert,
  swap = swap,
  resize = resize,
}
