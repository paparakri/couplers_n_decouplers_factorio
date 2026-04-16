-- scripts/gui.lua
-- All GUI logic for the Platform Docking mod.
--
-- Step 1 scope: idle state only.
--   Gui.open(player, port_entity)  -- build and show the GUI
--   Gui.close(player)              -- destroy the GUI
--   Gui.on_click(player, element)  -- handle button presses (stub in Step 1)

local OrbitCheck = require("scripts.orbit-check")
local State      = require("scripts.state")
local Merger     = require("scripts.merger")

local Gui = {}

-- The root frame name stored in player.gui.screen.
local FRAME_NAME = "docking_port_frame"

-- Tag keys used to associate GUI elements back to game state.
local TAG_PORT_UNIT   = "docking_port_unit_number"
local TAG_TARGET_IDX  = "docking_target_index"  -- index into the targets list

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

--- Destroy any existing docking GUI for this player.
local function destroy_existing(player)
  local frame = player.gui.screen[FRAME_NAME]
  if frame and frame.valid then
    frame.destroy()
  end
end

--- Return a short human-readable location name.
local function location_label(platform)
  if platform.space_location then
    return platform.space_location.name
  elseif platform.space_connection then
    return "in transit"
  else
    return "unknown"
  end
end

--- Translate a defines.direction value to a string.
local DIR_NAMES = {
  [defines.direction.north] = "North",
  [defines.direction.east]  = "East",
  [defines.direction.south] = "South",
  [defines.direction.west]  = "West",
}

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Open the docking port GUI for a player.
--- Builds the appropriate panel depending on the port's current state.
---
---@param player LuaPlayer
---@param port_entity LuaEntity
function Gui.open(player, port_entity)
  if not (player and player.valid) then return end
  if not (port_entity and port_entity.valid) then return end

  destroy_existing(player)

  -- Determine which state this port is in.
  local pair, _ = State.get_pair_for_port(port_entity)
  local port_state = pair and pair.state or "idle"

  -- Find what platform this port is on (for display).
  local my_platform = port_entity.surface.platform
  local platform_name = my_platform and my_platform.name or "Unknown Platform"
  local platform_loc  = my_platform and location_label(my_platform) or "unknown"

  -- -------------------------------------------------------------------------
  -- Build the root frame
  -- -------------------------------------------------------------------------
  local frame = player.gui.screen.add{
    type  = "frame",
    name  = FRAME_NAME,
    direction = "vertical",
  }
  frame.auto_center = true

  -- Title bar
  local title_bar = frame.add{ type = "flow", direction = "horizontal" }
  local title_text
  if port_state == "idle" then
    title_text = { "gui.docking-port-title-idle" }
  elseif port_state == "docking" then
    title_text = { "gui.docking-port-title-connecting" }
  else
    title_text = { "gui.docking-port-title-docked" }
  end
  title_bar.add{ type = "label", caption = title_text, style = "frame_title" }
  -- Spacer pushes close button to the right
  local spacer = title_bar.add{ type = "empty-widget", style = "draggable_space_header" }
  spacer.drag_target = frame
  spacer.style.horizontally_stretchable = true
  title_bar.add{
    type    = "sprite-button",
    name    = "docking_close_btn",
    sprite  = "utility/close",
    style   = "frame_action_button",
    tooltip = { "gui.close" },
    tags    = { [TAG_PORT_UNIT] = port_entity.unit_number },
  }

  -- Inner content panel
  local content = frame.add{
    type      = "frame",
    direction = "vertical",
    style     = "inside_shallow_frame_with_padding",
  }
  content.style.minimal_width = 350

  -- Platform / location info
  content.add{
    type    = "label",
    caption = { "gui.docking-platform-info",
                platform_name, platform_loc },
  }

  content.add{ type = "line", direction = "horizontal" }

  -- -------------------------------------------------------------------------
  -- State-specific content
  -- -------------------------------------------------------------------------

  if port_state == "idle" then
    Gui._build_idle_content(content, port_entity, my_platform)

  elseif port_state == "docking" then
    Gui._build_docking_content(content, port_entity, pair)

  else  -- "docked"
    Gui._build_docked_content(content, port_entity, pair)
  end

  -- Register our frame as the opened GUI so ESC closes it and the
  -- vanilla combinator panel is suppressed.
  player.opened = frame
end

--- Build the idle-state content (dropdown + Initiate Docking button).
---@param content LuaGuiElement
---@param port_entity LuaEntity
---@param my_platform LuaSpacePlatform|nil
function Gui._build_idle_content(content, port_entity, my_platform)
  local targets = OrbitCheck.get_compatible_platforms(port_entity)

  -- Build dropdown items
  local items = {}
  local has_targets = #targets > 0

  if has_targets then
    for _, t in ipairs(targets) do
      table.insert(items, t.label)
    end
  else
    table.insert(items, { "gui.docking-no-targets" })
  end

  content.add{
    type    = "label",
    caption = { "gui.docking-select-target" },
  }

  local dropdown = content.add{
    type          = "drop-down",
    name          = "docking_target_dropdown",
    items         = items,
    selected_index = 1,
    tags          = { [TAG_PORT_UNIT] = port_entity.unit_number },
  }
  dropdown.enabled = has_targets

  content.add{ type = "line", direction = "horizontal" }

  local btn_flow = content.add{ type = "flow", direction = "horizontal" }
  btn_flow.style.horizontal_align = "right"
  btn_flow.add{
    type    = "button",
    name    = "docking_initiate_btn",
    caption = { "gui.docking-initiate" },
    style   = "confirm_button",
    enabled = has_targets,
    tags    = { [TAG_PORT_UNIT] = port_entity.unit_number },
  }
end

--- Build the "docking in progress" content (progress bar + Abort).
function Gui._build_docking_content(content, port_entity, pair)
  local anim_ticks  = settings.global["docking-animation-ticks"].value
  local elapsed     = game.tick - (pair.anim_tick or game.tick)
  local progress    = math.min(elapsed / anim_ticks, 1.0)

  content.add{
    type     = "progressbar",
    name     = "docking_progress_bar",
    value    = progress,
    style    = "achievement_progressbar",
  }

  local btn_flow = content.add{ type = "flow", direction = "horizontal" }
  btn_flow.style.horizontal_align = "right"
  btn_flow.add{
    type    = "button",
    name    = "docking_abort_btn",
    caption = { "gui.docking-abort" },
    style   = "red_button",
    tags    = { [TAG_PORT_UNIT] = port_entity.unit_number },
  }
end

--- Build the "docked" content (status + Undock button).
function Gui._build_docked_content(content, port_entity, pair)
  -- Look up the two platform names from their indices.
  local name_a = "Platform A"
  local name_b = "Platform B"
  for _, surface in pairs(game.surfaces) do
    local p = surface.platform
    if p and p.valid then
      if p.index == pair.platform_a_index then name_a = p.name end
      if p.index == pair.platform_b_index then name_b = p.name end
    end
  end

  content.add{
    type    = "label",
    caption = { "gui.docking-status-docked", name_a, name_b },
  }

  content.add{ type = "line", direction = "horizontal" }

  local btn_flow = content.add{ type = "flow", direction = "horizontal" }
  btn_flow.style.horizontal_align = "right"
  btn_flow.add{
    type    = "button",
    name    = "docking_undock_btn",
    caption = { "gui.docking-undock" },
    style   = "red_button",
    tags    = { [TAG_PORT_UNIT] = port_entity.unit_number },
  }
end

--- Destroy the docking GUI for a player.
---@param player LuaPlayer
function Gui.close(player)
  if player and player.valid then
    destroy_existing(player)
  end
end

--- Handle GUI click events. Routes by button name.
--- Called from control.lua on_gui_click.
---
---@param player LuaPlayer
---@param element LuaGuiElement
function Gui.on_click(player, element)
  local name = element.name

  if name == "docking_close_btn" then
    Gui.close(player)

  elseif name == "docking_initiate_btn" then
    local dropdown = element.parent.docking_target_dropdown
    if not (dropdown and dropdown.valid) then
      -- Try searching in siblings if layout changed
      dropdown = element.parent.parent.docking_target_dropdown
    end
    if not (dropdown and dropdown.valid) then
      player.print("[Docking Port] Internal Error: Could not find target dropdown.")
      return
    end
    
    local port_unit = element.tags[TAG_PORT_UNIT]
    -- Port A is always on the same platform surface as the player.
    local port_a = player.surface.find_entities_filtered{ unit_number = port_unit }[1]
    if not (port_a and port_a.valid) then
      player.print("[Docking Port] Internal Error: Port A not found on this surface.")
      return
    end

    local targets = OrbitCheck.get_compatible_platforms(port_a)
    local target = targets[dropdown.selected_index]
    if not target then
      player.print("[Docking Port] Internal Error: Selected target not found.")
      return
    end
    
    local platform_a = port_a.surface.platform
    local platform_b = target.platform
    local port_b = target.port

    -- Verify again before creating
    local can_dock, reason = OrbitCheck.can_platforms_dock(platform_a, platform_b)
    if not can_dock then
      player.print({"", "[Docking Port] ", reason})
      return
    end

    State.create_pair(platform_a, platform_b, port_a, port_b)
    player.print("[Docking Port] Docking sequence initiated.")
    Gui.open(player, port_a)

  elseif name == "docking_abort_btn" then
    local port_unit = element.tags[TAG_PORT_UNIT]
    local port_a = player.surface.find_entities_filtered{ unit_number = port_unit }[1]
    local _, pair_id = State.get_pair_for_port(port_a)
    if pair_id then
      State.remove_pair(pair_id)
      player.print("[Docking Port] Docking aborted.")
      if port_a and port_a.valid then Gui.open(player, port_a) end
    end

  elseif name == "docking_undock_btn" then
    local port_unit = element.tags[TAG_PORT_UNIT]
    local port_a = player.surface.find_entities_filtered{ unit_number = port_unit }[1]
    local _, pair_id = State.get_pair_for_port(port_a)

    if pair_id then
      Gui.close(player)
      Merger.execute_unmerge(pair_id)
    end
  end
end

return Gui
