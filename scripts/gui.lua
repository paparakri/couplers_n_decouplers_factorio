-- scripts/gui.lua
-- All GUI logic for the Platform Docking mod.
--
--   Gui.open(player, port_entity)      build and show the GUI for a port
--   Gui.close(player)                  destroy the GUI
--   Gui.on_click(player, element)      button presses
--   Gui.on_selection_changed(player, element)  target dropdown changes
--   Gui.update_progress()              refresh open "connecting" progress bars

local OrbitCheck = require("scripts.orbit-check")
local State      = require("scripts.state")
local Merger     = require("scripts.merger")
local Corridor   = require("scripts.corridor")

local Gui = {}

local FRAME_NAME = "docking_port_frame"
Gui.FRAME_NAME = FRAME_NAME

local BUTTONS = {
  docking_close_btn    = true,
  docking_initiate_btn = true,
  docking_abort_btn    = true,
  docking_undock_btn   = true,
  docking_launch_btn   = true,
}
Gui.BUTTONS = BUTTONS

local DIR_KEYS = {
  [defines.direction.north] = "north",
  [defines.direction.east]  = "east",
  [defines.direction.south] = "south",
  [defines.direction.west]  = "west",
}

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

local function destroy_existing(player)
  local frame = player.gui.screen[FRAME_NAME]
  if frame and frame.valid then frame.destroy() end
end

---@param platform LuaSpacePlatform
---@return LocalisedString
local function location_label(platform)
  if platform.space_location then
    return platform.space_location.localised_name
  end
  return { "gui.docking-in-transit" }
end

--- Find a descendant element by name.
---@param root LuaGuiElement
---@param name string
---@return LuaGuiElement|nil
local function find(root, name)
  if root.name == name then return root end
  for _, child in pairs(root.children) do
    local hit = find(child, name)
    if hit then return hit end
  end
  return nil
end

---@param unit number|nil
---@return LuaEntity|nil
local function port_by_unit(unit)
  if not unit then return nil end
  local e = game.get_entity_by_unit_number(unit)
  if e and e.valid then return e end
  return nil
end

--- Corridor length/width typed into the idle view (clamped, defaults from settings).
---@param root LuaGuiElement
---@return number length, number width
local function read_corridor(root)
  local length_field = find(root, "docking_length_field")
  local width_field  = find(root, "docking_width_field")
  return Corridor.clamp(length_field and length_field.text, width_field and width_field.text)
end

--- Work out host/guest and check the geometry for a (my port, target port) pair.
---@return table|nil info  { platform_a, platform_b, port_a, port_b }
---@return LocalisedString|nil reason
local function resolve_dock(my_port, target_port, length, width)
  local my_platform = my_port.surface.platform
  local target_platform = target_port.surface.platform
  if not (my_platform and target_platform) then
    return nil, { "docking-message.platform-missing" }
  end
  local ok, reason = OrbitCheck.can_platforms_dock(my_platform, target_platform)
  if not ok then return nil, reason end

  local host, guest, role_err = OrbitCheck.choose_host(my_platform, target_platform)
  if not host then return nil, role_err end
  local port_a, port_b = my_port, target_port
  if host.index ~= my_platform.index then port_a, port_b = target_port, my_port end

  local plan, plan_err = Merger.plan(host, guest, port_a, port_b, length, width)
  if not plan then return nil, plan_err end
  return { platform_a = host, platform_b = guest, port_a = port_a, port_b = port_b }, nil
end

--- Refresh the host/guest preview line under the dropdown.
---@param content LuaGuiElement
local function update_preview(content)
  local dropdown = find(content, "docking_target_dropdown")
  local label = find(content, "docking_preview_label")
  if not (dropdown and label) then return end

  local tags = dropdown.tags
  local my_port = port_by_unit(tags.port_unit)
  local units = tags.target_units or {}
  local target_port = port_by_unit(units[dropdown.selected_index])
  if not (my_port and target_port) then
    label.caption = ""
    return
  end

  local length, width = read_corridor(content)
  local info, reason = resolve_dock(my_port, target_port, length, width)
  if info then
    label.caption = { "gui.docking-preview", info.platform_a.name, info.platform_b.name, length, width }
    label.style.font_color = { 0.6, 1, 0.6 }
  else
    label.caption = reason
    label.style.font_color = { 1, 0.5, 0.4 }
  end
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

---@param player LuaPlayer
---@param port_entity LuaEntity
function Gui.open(player, port_entity)
  if not (player and player.valid) then return end
  if not (port_entity and port_entity.valid) then return end

  destroy_existing(player)

  local pair = State.get_pair_for_port(port_entity)
  local port_state = pair and pair.state or "idle"

  local my_platform = port_entity.surface.platform
  local platform_name = my_platform and my_platform.name or { "gui.docking-unknown-platform" }
  local platform_loc  = my_platform and location_label(my_platform) or { "gui.docking-unknown" }

  local frame = player.gui.screen.add{
    type      = "frame",
    name      = FRAME_NAME,
    direction = "vertical",
    tags      = { port_unit = port_entity.unit_number },
  }
  frame.auto_center = true

  -- Title bar
  local titles = {
    idle             = "gui.docking-port-title-idle",
    docking          = "gui.docking-port-title-connecting",
    docked           = "gui.docking-port-title-docked",
    undock_pending   = "gui.docking-port-title-undocking",
  }
  local title_bar = frame.add{ type = "flow", direction = "horizontal" }
  title_bar.add{ type = "label", caption = { titles[port_state] }, style = "frame_title" }
  local spacer = title_bar.add{ type = "empty-widget", style = "draggable_space_header" }
  spacer.drag_target = frame
  spacer.style.horizontally_stretchable = true
  spacer.style.height = 24
  title_bar.add{
    type    = "sprite-button",
    name    = "docking_close_btn",
    sprite  = "utility/close",
    style   = "frame_action_button",
    tooltip = { "gui.close" },
  }

  local content = frame.add{
    type      = "frame",
    direction = "vertical",
    style     = "inside_shallow_frame_with_padding",
  }
  content.style.minimal_width = 380

  content.add{ type = "label", caption = { "gui.docking-platform-info", platform_name, platform_loc } }
  content.add{ type = "label", caption = { "gui.docking-port-faces",
    { "gui.docking-dir-" .. (DIR_KEYS[port_entity.direction] or "unknown") } } }
  content.add{ type = "line", direction = "horizontal" }

  if port_state == "idle" then
    Gui._build_idle_content(content, port_entity)
  elseif port_state == "docking" then
    Gui._build_docking_content(content, port_entity, pair)
  else
    Gui._build_docked_content(content, port_entity, pair)
  end

  -- Register our frame as the opened GUI so ESC closes it and the
  -- vanilla combinator panel is suppressed.
  player.opened = frame
end

---@param content LuaGuiElement
---@param port_entity LuaEntity
function Gui._build_idle_content(content, port_entity)
  local targets = OrbitCheck.get_compatible_platforms(port_entity)
  local has_targets = #targets > 0

  local items, units = {}, {}
  for i, t in ipairs(targets) do
    items[i] = t.label
    units[i] = t.port.unit_number
  end
  if not has_targets then items[1] = { "gui.docking-no-targets" } end

  content.add{ type = "label", caption = { "gui.docking-select-target" } }
  local dropdown = content.add{
    type           = "drop-down",
    name           = "docking_target_dropdown",
    items          = items,
    selected_index = 1,
    -- Store port unit numbers, not list positions, so a target list that
    -- changes before Initiate is pressed can't dock to the wrong port.
    tags           = { port_unit = port_entity.unit_number, target_units = units },
  }
  dropdown.enabled = has_targets
  dropdown.style.horizontally_stretchable = true

  -- Corridor size for this dock.
  local length, width = Corridor.clamp(nil, nil)
  local size_flow = content.add{ type = "flow", direction = "horizontal" }
  size_flow.style.vertical_align = "center"
  local function add_field(name, caption, tooltip, value)
    size_flow.add{ type = "label", caption = caption, tooltip = tooltip }
    local field = size_flow.add{
      type           = "textfield",
      name           = name,
      text           = tostring(value),
      numeric        = true,
      allow_decimal  = false,
      allow_negative = false,
      tooltip        = tooltip,
      enabled        = has_targets,
    }
    field.style.width = 50
  end
  add_field("docking_length_field", { "gui.docking-corridor-length" },
    { "gui.docking-corridor-length-tooltip", Corridor.MAX_LENGTH }, length)
  add_field("docking_width_field", { "gui.docking-corridor-width" },
    { "gui.docking-corridor-width-tooltip", Corridor.MAX_WIDTH }, width)

  local preview = content.add{ type = "label", name = "docking_preview_label", caption = "" }
  preview.style.single_line = false
  if has_targets then update_preview(content) end

  content.add{ type = "line", direction = "horizontal" }

  local btn_flow = content.add{ type = "flow", direction = "horizontal" }
  btn_flow.add{ type = "empty-widget" }.style.horizontally_stretchable = true
  btn_flow.add{
    type    = "button",
    name    = "docking_initiate_btn",
    caption = { "gui.docking-initiate" },
    style   = "confirm_button",
    enabled = has_targets,
  }
end

---@param content LuaGuiElement
---@param port_entity LuaEntity
---@param pair table
function Gui._build_docking_content(content, port_entity, pair)
  content.add{
    type  = "progressbar",
    name  = "docking_progress_bar",
    value = Gui._progress(pair),
  }.style.horizontally_stretchable = true

  local btn_flow = content.add{ type = "flow", direction = "horizontal" }
  btn_flow.add{ type = "empty-widget" }.style.horizontally_stretchable = true
  btn_flow.add{
    type    = "button",
    name    = "docking_abort_btn",
    caption = { "gui.docking-abort" },
    style   = "red_button",
  }
end

---@param content LuaGuiElement
---@param port_entity LuaEntity
---@param pair table
function Gui._build_docked_content(content, port_entity, pair)
  local platform_a, platform_b = State.get_platforms(pair)
  local name_a = platform_a and platform_a.name or "?"
  local name_b = platform_b and platform_b.name or "?"

  content.add{ type = "label", caption = { "gui.docking-status-docked", name_a, name_b } }
  if pair.state == "undock_pending" then
    content.add{ type = "label", caption = { "gui.docking-undock-pending" } }
  end
  content.add{ type = "line", direction = "horizontal" }

  local in_transit = not (platform_a and platform_a.space_location)
  local btn_flow = content.add{ type = "flow", direction = "horizontal" }
  btn_flow.add{ type = "empty-widget" }.style.horizontally_stretchable = true

  -- Launch is only offered while the host is flying.
  if in_transit then
    local can_launch, reason = Merger.can_launch(pair)
    btn_flow.add{
      type    = "button",
      name    = "docking_launch_btn",
      caption = { "gui.docking-launch" },
      enabled = can_launch,
      tooltip = can_launch and { "gui.docking-launch-tooltip" } or reason,
    }
  end

  btn_flow.add{
    type    = "button",
    name    = "docking_undock_btn",
    caption = { "gui.docking-undock" },
    style   = "red_button",
    enabled = pair.state == "docked",
    tooltip = in_transit and { "gui.docking-undock-in-transit" } or nil,
  }
end

---@param pair table
---@return number 0..1
function Gui._progress(pair)
  local anim_ticks = settings.global["docking-animation-ticks"].value
  return math.min((game.tick - (pair.anim_tick or game.tick)) / anim_ticks, 1.0)
end

---@param player LuaPlayer
function Gui.close(player)
  if player and player.valid then destroy_existing(player) end
end

--- Close every open docking GUI (after a merge/unmerge changed everything).
function Gui.close_all()
  for _, player in pairs(game.players) do Gui.close(player) end
end

--- Refresh progress bars for players watching a docking countdown.
function Gui.update_progress()
  for _, player in pairs(game.connected_players) do
    local frame = player.gui.screen[FRAME_NAME]
    if frame and frame.valid then
      local bar = find(frame, "docking_progress_bar")
      if bar then
        local pair = State.get_pair_for_port(port_by_unit(frame.tags.port_unit))
        if pair and pair.state == "docking" then bar.value = Gui._progress(pair) end
      end
    end
  end
end

---@param player LuaPlayer
---@param element LuaGuiElement
function Gui.on_selection_changed(player, element)
  if element.name ~= "docking_target_dropdown" then return end
  update_preview(element.parent)
end

--- Corridor length/width edited: re-check whether the dock fits.
---@param player LuaPlayer
---@param element LuaGuiElement
function Gui.on_text_changed(player, element)
  if element.name ~= "docking_length_field" and element.name ~= "docking_width_field" then return end
  local frame = player.gui.screen[FRAME_NAME]
  if frame and frame.valid then update_preview(frame) end
end

---@param player LuaPlayer
---@param element LuaGuiElement
function Gui.on_click(player, element)
  local name = element.name
  local frame = player.gui.screen[FRAME_NAME]
  if name == "docking_close_btn" or not (frame and frame.valid) then
    Gui.close(player)
    return
  end

  local my_port = port_by_unit(frame.tags.port_unit)
  if not my_port then
    player.print({ "", { "docking-message.prefix" }, { "docking-message.port-missing" } })
    Gui.close(player)
    return
  end

  if name == "docking_initiate_btn" then
    local dropdown = find(frame, "docking_target_dropdown")
    local units = dropdown and dropdown.tags.target_units or {}
    local target_port = dropdown and port_by_unit(units[dropdown.selected_index])
    if not target_port then
      player.print({ "", { "docking-message.prefix" }, { "docking-message.port-missing" } })
      Gui.open(player, my_port)
      return
    end

    local length, width = read_corridor(frame)
    local info, reason = resolve_dock(my_port, target_port, length, width)
    if not info then
      player.print({ "", { "docking-message.prefix" }, reason })
      Gui.open(player, my_port)
      return
    end

    State.create_pair(info.platform_a, info.platform_b, info.port_a, info.port_b, length, width)
    player.print({ "", { "docking-message.prefix" }, { "docking-message.dock-started" } })
    Gui.open(player, my_port)

  elseif name == "docking_abort_btn" then
    local pair, pair_id = State.get_pair_for_port(my_port)
    if pair_id and pair.state == "docking" then
      State.remove_pair(pair_id)
      player.print({ "", { "docking-message.prefix" }, { "docking-message.dock-cancelled" } })
    end
    Gui.open(player, my_port)

  elseif name == "docking_undock_btn" then
    local _, pair_id = State.get_pair_for_port(my_port)
    Gui.close(player)
    if pair_id then Merger.request_undock(pair_id) end

  elseif name == "docking_launch_btn" then
    local _, pair_id = State.get_pair_for_port(my_port)
    Gui.close(player)
    if pair_id then Merger.launch(pair_id) end
  end
end

return Gui
