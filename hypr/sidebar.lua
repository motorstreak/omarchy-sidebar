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
-- ~/.config/omarchy/sidebar.lua (a Lua file returning a table like `defaults`).
--
-- Errors inside Hyprland callbacks otherwise surface only as a bare Hyprland
-- notification, so every callback here runs through `guard`, which reports
-- failures once as a "Sidebar" desktop notification.

if SIDEBAR_LOADED then
  return
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

-- Reporting --------------------------------------------------------------------

local reported = {}

local function notify(message)
  hl.exec_cmd("notify-send -a Sidebar Sidebar " .. quote(message))
end

-- Each distinct error is reported once per load, so a failing callback that
-- fires on every focus change can't flood the screen.
local function report(context, err)
  local message = context .. ": " .. tostring(err)
  if not reported[message] then
    reported[message] = true
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
  dim = true, -- dim the rest of the screen while a sidebar shows
  click_outside = true, -- clicking outside a shown sidebar hides it
  sidebar = {
    toggle = "SUPER + B",
    convert = "SUPER + ALT + B",
    escape = true, -- ESCAPE hides it (the app in it then doesn't get ESCAPE)
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

local key_options = {
  sidebar = { toggle = true, convert = true },
  agent = { toggle = true, new = true, load = true, reset = true },
}

-- Copies `overrides` onto `into` where the types fit the defaults (keys may also
-- be false to leave them unbound); anything else is reported and skipped.
local function apply(into, overrides, path, problems)
  for k, v in pairs(overrides) do
    local name = path .. tostring(k)
    local current = into[k]
    if current == nil then
      problems[#problems + 1] = "unknown option " .. name
    elseif type(current) == "table" then
      if type(v) == "table" then
        apply(current, v, name .. ".", problems)
      else
        problems[#problems + 1] = name .. " must be a table"
      end
    elseif type(v) == type(current) or (v == false and type(current) == "string") then
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
      apply(config, overrides, "", problems)
    end
  elseif load_err and not load_err:find("No such file", 1, true) then
    problems[#problems + 1] = load_err
  end

  if config.width <= 0 or config.width > 1 then
    problems[#problems + 1] = "width must be between 0 and 1"
    config.width = 0.33
  end
  if config.margin < 0 then
    problems[#problems + 1] = "margin can't be negative"
    config.margin = 24
  end

  -- Two options on one key would silently replace each other.
  local seen = {}
  for group, options in pairs(key_options) do
    if group ~= "agent" or config.agent.enabled then
      for option in pairs(options) do
        local keys = config[group][option]
        if keys then
          local id = keys:upper():gsub("%s+", "")
          if seen[id] then
            problems[#problems + 1] = group .. "." .. option .. " uses the same key as " .. seen[id]
            config[group][option] = false
          else
            seen[id] = group .. "." .. option
          end
        end
      end
    end
  end

  if #problems > 0 then
    notify("Problems in ~/.config/omarchy/sidebar.lua: " .. table.concat(problems, "; "))
  end
end

-- Slots ------------------------------------------------------------------------

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

local function slot_for_class(class)
  for _, slot in pairs(slots) do
    if slot.class and slot.class == class then
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

-- The window as it is now, or nil once it has closed.
local function current(address)
  for _, w in ipairs(hl.get_windows()) do
    if w.address == address then
      return w
    end
  end
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

-- Per-slot remembered side --------------------------------------------------

os.execute("mkdir -p " .. quote(state_root))

local function side_file(slot)
  return state_root .. "/" .. slot.name .. ".side"
end

for _, slot in pairs(slots) do
  local f = io.open(side_file(slot), "r")
  slot.side = "right"
  if f then
    if f:read("l") == "left" then
      slot.side = "left"
    end
    f:close()
  end
end

local function save_side(slot, side)
  slot.side = side
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

-- Docks the window to its slot's edge at the given size (clamped to the
-- monitor), keeping the given top edge, or the top of the usable area.
local function dock(window, slot, width, height, top)
  if window.monitor == nil then
    return
  end
  local a = area(window.monitor)
  local max_width, max_height = a.right - a.left, a.bottom - a.top
  width = math.floor(math.min(math.max(width, math.min(360, max_width)), max_width))
  height = math.floor(math.min(math.max(height, math.min(300, max_height)), max_height))
  top = math.floor(math.min(math.max(top or a.top, a.top), a.bottom - height))
  local x = math.floor(slot.side == "left" and a.left or (a.right - width))

  dispatch_for(window, hl.dsp.window.resize, { x = width, y = height })
  dispatch_for(window, hl.dsp.window.move, { x = x, y = top })
  slot.docked_monitor = window.monitor.id
end

local function dock_default(window, slot)
  if window.monitor == nil then
    return
  end
  local a = area(window.monitor)
  dock(window, slot, a.width * config.width, a.bottom - a.top)
end

-- Entering and leaving sidebar mode -------------------------------------------

-- Defined further down; entering and leaving re-check the sidebar keys, since a
-- new window's focus event can arrive before it has entered its slot.
local sync_keys

local function slot_shown(slot, monitor)
  monitor = monitor or hl.get_active_monitor()
  local shown = monitor and monitor.active_special_workspace
  return shown ~= nil and shown.name == slot.workspace
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

local function set_dim(window, on)
  dispatch_for(window, hl.dsp.window.set_prop, { prop = "dim_around", value = on and "1" or "0" })
end

local function enter(window, slot)
  members[window.address] = slot
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

  -- Dock once floating has settled, or Hyprland restores the window's old
  -- floating position over ours; by then it may have closed or moved on.
  local address = window.address
  hl.timer(guard("docking", function()
    local now = current(address)
    if now and members[address] == slot and now.floating and now.workspace and now.workspace.name == slot.workspace then
      dock_default(now, slot)
    end
    sync_keys()
  end), { timeout = 50, type = "oneshot" })
  sync_keys()
end

-- Hides the slot if it is on screen and `leaving` was the last window in it.
local function hide_if_empty(slot, leaving)
  for _, w in ipairs(slot_windows(slot)) do
    if w.address ~= leaving then
      return
    end
  end
  for _, m in ipairs(hl.get_monitors()) do
    if slot_shown(slot, m) then
      hl.dispatch(hl.dsp.workspace.toggle_special(slot.name))
      return
    end
  end
end

local function leave(window, slot)
  members[window.address] = nil
  hide_if_empty(slot, window.address)
  set_dim(window, false)
  if window.floating then
    dispatch_for(window, hl.dsp.window.float, { action = "toggle" })
  end
  sync_keys()
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

-- Keys that act on a sidebar differently from Omarchy are only taken over
-- while a sidebar has focus; the rest of the time Omarchy's own bindings are in
-- place untouched.
--
-- Omarchy's resize and swap keys (from default/hypr/bindings/tiling.lua),
-- restored exactly as Omarchy binds them when a sidebar loses focus.
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

-- In a docked sidebar: MINUS widens and EQUAL narrows it away from its edge,
-- with SHIFT they change its height from the top edge.
local function resize_docked(dx, dy)
  local window = hl.get_active_window()
  local slot = member_slot(window)
  if slot and window.floating then
    dock(window, slot, window.size.x - dx, window.size.y + dy, window.at.y)
  end
end

-- In a docked sidebar: LEFT/RIGHT dock it to that edge (keeping its size) and
-- remember the side; UP/DOWN do nothing.
local function swap_docked(direction)
  local window = hl.get_active_window()
  local slot = member_slot(window)
  if slot and window.floating and (direction == "l" or direction == "r") then
    save_side(slot, direction == "l" and "left" or "right")
    dock(window, slot, window.size.x, window.size.y, window.at.y)
  end
end

local function bind_sidebar_keys()
  for _, r in ipairs(resize_keys) do
    local dx, dy = r[3], r[4]
    hl.unbind(r[1])
    o.bind(r[1], r[2], guard(r[2], function()
      resize_docked(dx, dy)
    end))
  end
  for _, s in ipairs(swap_keys) do
    local direction = s[3]
    hl.unbind(s[1])
    o.bind(s[1], s[2], guard(s[2], function()
      swap_docked(direction)
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

-- ESCAPE hides a visible, focused sidebar whose slot allows it, and is unbound
-- otherwise so it reaches apps everywhere else (this owns plain ESCAPE:
-- unbinding it would also drop any other plain ESCAPE binding). The resize and
-- swap keys are the sidebar versions while a floating sidebar has focus.
-- A plain left click outside the focused sidebar hides it. The binding doesn't
-- consume the click, so whatever was clicked still gets it. Clicking a window
-- behind the sidebar can make Hyprland hide it too, so the hide waits until the
-- click has been handled and only happens if the sidebar is still shown (the
-- dispatcher toggles, so hiding twice would show it again).
local function hide_on_outside_click()
  local window = hl.get_active_window()
  local slot = member_slot(window)
  if slot == nil or not slot_shown(slot, window.monitor) then
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
  local monitor_id = window.monitor.id
  hl.timer(guard("hiding a sidebar", function()
    for _, m in ipairs(hl.get_monitors()) do
      if m.id == monitor_id and slot_shown(slot, m) then
        hl.dispatch(hl.dsp.workspace.toggle_special(slot.name))
      end
    end
  end), { timeout = 30, type = "oneshot" })
end

local escape_slot = nil
local sidebar_keys = false
local click_bound = false
function sync_keys()
  local window = hl.get_active_window()
  local slot = member_slot(window)
  local visible = slot ~= nil and slot_shown(slot, window.monitor)

  local want_escape = nil
  if visible and slot.escape then
    want_escape = slot
  end
  if want_escape ~= escape_slot then
    if escape_slot then
      hl.unbind("ESCAPE")
    end
    if want_escape then
      hl.bind("ESCAPE", hl.dsp.workspace.toggle_special(want_escape.name), { description = "Hide sidebar" })
    end
    escape_slot = want_escape
  end

  local want_click = visible and config.click_outside
  if want_click ~= click_bound then
    if want_click then
      hl.bind("mouse:272", guard("hiding a sidebar", hide_on_outside_click), {
        non_consuming = true,
        description = "Hide sidebar on a click outside it",
      })
    else
      hl.unbind("mouse:272")
    end
    click_bound = want_click
  end

  local want_sidebar_keys = visible and window.floating
  if want_sidebar_keys ~= sidebar_keys then
    if want_sidebar_keys then
      bind_sidebar_keys()
    else
      bind_omarchy_keys()
    end
    sidebar_keys = want_sidebar_keys
  end
end

-- Windows already in a slot when this loads (e.g. after a config reload).
for _, slot in pairs(slots) do
  for _, w in ipairs(slot_windows(slot)) do
    members[w.address] = slot
    set_dim(w, config.dim)
  end
end

hl.on("window.active", guard("focus change", sync_keys))

hl.on("workspace.special_active", guard("showing a sidebar", function()
  -- A slot shown on another monitor than it was docked on: dock it there.
  local monitor = hl.get_active_monitor()
  local shown = monitor and monitor.active_special_workspace
  local slot = shown and slot_for_workspace(shown.name)
  if slot and slot.docked_monitor ~= nil and slot.docked_monitor ~= monitor.id then
    for _, w in ipairs(slot_windows(slot)) do
      if members[w.address] == slot and w.floating then
        dock_default(w, slot)
      end
    end
  end
  sync_keys()
end))

-- A new window lands on whatever special workspace is on screen. Only an app
-- slot's own app belongs there; anything else (a dialog, a browser opened from
-- the sidebar, a terminal opened while it had focus) goes to the regular
-- workspace instead of being docked on top of the sidebar.
hl.on("window.open", guard("opening a window", function(window)
  if window == nil or window.workspace == nil then
    return
  end
  local slot = slot_for_workspace(window.workspace.name)
  if slot == nil then
    return
  end
  if slot_for_class(window.class) == slot then
    enter(window, slot)
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
  end
  hl.timer(guard("closing a window", sync_keys), { timeout = 1, type = "oneshot" })
end))

hl.on("window.move_to_workspace", guard("moving a window", function(window, workspace)
  if window == nil or workspace == nil then
    return
  end
  local target = slot_for_workspace(workspace.name)
  local from = members[window.address]
  if from and from ~= target then
    if target then
      -- Straight from one slot into another.
      members[window.address] = nil
      hide_if_empty(from, window.address)
    else
      leave(window, from)
    end
  end
  if target then
    enter(window, target)
  end
end))

-- Keys -------------------------------------------------------------------------

local function bind(keys, description, fn)
  if keys then
    hl.unbind(keys)
    o.bind(keys, description, guard(description, fn))
  end
end

-- A slot's own window (the member if there is one), else for app slots its app
-- wherever it is.
local function find_window(slot)
  local inside = slot_windows(slot)
  for _, w in ipairs(inside) do
    if members[w.address] == slot then
      return w
    end
  end
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

local function focus(window)
  hl.dispatch(hl.dsp.focus({ window = selector(window) }))
end

-- Show/hide a slot. If its window was moved out to a workspace: jump to it, or,
-- when it is already focused and on screen, send it back into the slot (hidden).
local function toggle(slot)
  local window = find_window(slot)
  if window == nil then
    if slot.launch then
      slot.launch()
    elseif config.sidebar.convert then
      notify("No sidebar yet: focus a window and press " .. config.sidebar.convert)
    else
      notify("No sidebar yet")
    end
    return
  end

  if window.workspace and window.workspace.name == slot.workspace then
    if members[window.address] ~= slot then
      enter(window, slot)
    end
    hl.dispatch(hl.dsp.workspace.toggle_special(slot.name))
    return
  end

  local active = hl.get_active_window()
  local monitor = window.monitor
  local ws = window.workspace and window.workspace.name
  local regular = regular_workspace(monitor)
  local special = monitor and monitor.active_special_workspace
  local on_screen = ws ~= nil and ((regular and ws == regular.name) or (special and ws == special.name))
  if active and active.address == window.address and on_screen then
    dispatch_for(window, hl.dsp.window.move, { workspace = slot.workspace, follow = false })
  else
    focus(window)
  end
end

-- Make a slot's window visible without toggling: show the slot, or focus the
-- window if it was moved out to a workspace.
local function show(slot)
  local window = find_window(slot)
  if window == nil then
    return false
  end
  if member_slot(window) == slot and not slot_shown(slot, window.monitor) then
    hl.dispatch(hl.dsp.workspace.toggle_special(slot.name))
  end
  focus(window)
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
  focus(window)
  return true
end

-- Turn the focused window into a sidebar, or a sidebar back into a window on
-- the current workspace. App windows go to their own slot.
local function convert()
  local window = hl.get_active_window()
  if window == nil then
    return
  end

  local regular = regular_workspace(window.monitor)
  local current_slot = member_slot(window)
  if current_slot then
    if regular then
      dispatch_for(window, hl.dsp.window.move, { workspace = workspace_target(regular.name) })
    end
    return
  end

  local slot = slot_for_class(window.class) or slots.sidebar
  for _, other in ipairs(slot_windows(slot)) do
    if regular then
      dispatch_for(other, hl.dsp.window.move, { workspace = workspace_target(regular.name), follow = false })
    end
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
    hl.exec_cmd("SIDEBAR_AGENT_CLASS=" .. quote(slots.agent.class) .. " " .. quote(script) .. " " .. command)
  end

  -- Escape every regex metacharacter so the class matches literally.
  local class_pattern = "^" .. slots.agent.class:gsub("[%^%$%(%)%.%[%]%*%+%-%?%{%}|\\]", "\\%0") .. "$"
  hl.window_rule({
    match = { class = class_pattern },
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

-- A sidebar may already have focus when this loads (e.g. after a reload).
guard("loading", sync_keys)()

-- For scripting and tests: `hyprctl eval 'sidebar.toggle("agent")'` etc.
-- Unknown or disabled slot names are ignored.
local function by_name(fn)
  return function(name, ...)
    local slot = slots[name]
    if slot then
      return fn(slot, ...)
    end
  end
end

-- Before the plugin unloads: every sidebar window back to its monitor's
-- workspace as a normal window, so none is left hidden with no key to show it.
local function release()
  for _, slot in pairs(slots) do
    for _, w in ipairs(slot_windows(slot)) do
      local regular = regular_workspace(w.monitor)
      if regular then
        dispatch_for(w, hl.dsp.window.move, { workspace = workspace_target(regular.name), follow = false })
      end
    end
  end
end

sidebar = {
  slots = slots,
  release = release,
  toggle = by_name(toggle),
  reset = by_name(reset),
  show = by_name(show),
  convert = convert,
  swap = swap_docked,
  resize = resize_docked,
}
