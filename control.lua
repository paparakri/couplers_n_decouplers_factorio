-- control.lua
-- Runtime entry point for the Platform Docking mod.
-- Keeps itself thin: requires scripts and registers event handlers only.

local State     = require("scripts.state")
local Gui       = require("scripts.gui")
local Merger    = require("scripts.merger")
local Logistics = require("scripts.logistics")

-- ---------------------------------------------------------------------------
-- Initialisation
-- ---------------------------------------------------------------------------

script.on_init(State.init)
script.on_configuration_changed(State.init)

-- ---------------------------------------------------------------------------
-- Port destruction — any way a registered port disappears (mined, died,
-- destroyed by script). Ports are registered when a dock starts.
-- ---------------------------------------------------------------------------

script.on_event(defines.events.on_object_destroyed, function(event)
  if event.type ~= defines.target_type.entity then return end
  Merger.on_port_destroyed(event.useful_id)
end)

-- ---------------------------------------------------------------------------
-- GUI
-- ---------------------------------------------------------------------------

script.on_event(defines.events.on_gui_opened, function(event)
  local entity = event.entity
  if not (entity and entity.valid and entity.name == "docking-port") then return end
  local player = game.get_player(event.player_index)
  if player then Gui.open(player, entity) end
end)

script.on_event(defines.events.on_gui_closed, function(event)
  -- Only react when OUR custom frame was closed (e.g. player pressed ESC).
  -- gui_type == entity fires when Factorio closes the entity's default GUI before
  -- we swap in our custom frame — catching that would destroy the frame immediately.
  if event.gui_type ~= defines.gui_type.custom then return end
  local element = event.element
  if not (element and element.valid and element.name == Gui.FRAME_NAME) then return end
  local player = game.get_player(event.player_index)
  if player then Gui.close(player) end
end)

script.on_event(defines.events.on_gui_click, function(event)
  local element = event.element
  if not (element and element.valid and Gui.BUTTONS[element.name]) then return end
  local player = game.get_player(event.player_index)
  if player then Gui.on_click(player, element) end
end)

script.on_event(defines.events.on_gui_selection_state_changed, function(event)
  local element = event.element
  if not (element and element.valid) then return end
  local player = game.get_player(event.player_index)
  if player then Gui.on_selection_changed(player, element) end
end)

script.on_event(defines.events.on_gui_text_changed, function(event)
  local element = event.element
  if not (element and element.valid) then return end
  local player = game.get_player(event.player_index)
  if player then Gui.on_text_changed(player, element) end
end)

-- ---------------------------------------------------------------------------
-- Platform lifecycle
-- ---------------------------------------------------------------------------

script.on_event(defines.events.on_space_platform_changed_state, function(event)
  local platform = event.platform
  if platform and platform.valid then
    local pair, pair_id = State.get_pair_for_platform(platform)
    if not pair then return end
    local before = pair.state
    Merger.on_platform_state_changed(platform)
    -- Docking GUIs show pair state; close them if it just changed.
    if not storage.docked_pairs[pair_id] or pair.state ~= before then
      Gui.close_all()
    end
  end
end)

script.on_event(defines.events.on_pre_surface_deleted, function(event)
  Merger.on_pre_surface_deleted(game.get_surface(event.surface_index))
end)

-- ---------------------------------------------------------------------------
-- Ticks — docking countdown, progress bars, hub logistics.
-- ---------------------------------------------------------------------------

script.on_event(defines.events.on_tick, function(event)
  if not next(storage.docked_pairs) then return end

  local anim_ticks = settings.global["docking-animation-ticks"].value
  local merged = false
  for pair_id, pair in pairs(storage.docked_pairs) do
    if pair.state == "docking" and event.tick >= pair.anim_tick + anim_ticks then
      Merger.execute_merge(pair_id)
      merged = true
    end
  end
  if merged then Gui.close_all() end

  if event.tick % 10 == 0 then Gui.update_progress() end
end)

script.on_nth_tick(Logistics.INTERVAL, function()
  if next(storage.docked_pairs) then Logistics.on_interval() end
end)
