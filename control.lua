-- control.lua
-- Runtime entry point for the Platform Docking mod.
-- Keeps itself thin: requires scripts and registers event handlers only.

local State      = require("scripts.state")
local Gui        = require("scripts.gui")
local OrbitCheck = require("scripts.orbit-check")
local Serializer = require("scripts.serializer")
local Merger     = require("scripts.merger")

-- ---------------------------------------------------------------------------
-- Initialisation
-- ---------------------------------------------------------------------------

script.on_init(function()
  State.init()
end)

script.on_load(function()
  State.load()
end)

-- Re-init new forces / migrations can call this too.
script.on_configuration_changed(function()
  State.init()
end)

-- ---------------------------------------------------------------------------
-- Entity placement — register docking ports
-- ---------------------------------------------------------------------------

local function on_entity_built(event)
  local entity = event.entity or event.created_entity
  if not (entity and entity.valid) then return end
  if entity.name == "docking-port" then
    State.register_port(entity)
  end
end

script.on_event(defines.events.on_built_entity,       on_entity_built,
  { { filter = "name", name = "docking-port" } })
script.on_event(defines.events.on_robot_built_entity, on_entity_built,
  { { filter = "name", name = "docking-port" } })

-- Handles entity placement via scripts (e.g. editor mode).
script.on_event(defines.events.on_entity_cloned, function(event)
  if event.destination and event.destination.valid
     and event.destination.name == "docking-port" then
    State.register_port(event.destination)
  end
end)

-- ---------------------------------------------------------------------------
-- Entity removal — unregister docking ports, abort active docks
-- ---------------------------------------------------------------------------

local function on_entity_removed(event)
  local entity = event.entity
  if not (entity and entity.valid) then return end
  if entity.name ~= "docking-port" then return end

  local pair_id = State.unregister_port(entity)
  if pair_id then
    -- A docked/docking port was destroyed — abort the dock.
    -- Full abort logic will be implemented in Step 4.
    -- For now, just clean up the pair record and warn.
    local pair = storage.docked_pairs[pair_id]
    if pair then
      log("[Docking Port] A docking port was destroyed — docking sequence aborted.")
      State.remove_pair(pair_id)
    end
  end
end

script.on_event(defines.events.on_pre_player_mined_item, on_entity_removed,
  { { filter = "name", name = "docking-port" } })
script.on_event(defines.events.on_entity_died,           on_entity_removed,
  { { filter = "name", name = "docking-port" } })
script.on_event(defines.events.on_robot_pre_mined,       on_entity_removed,
  { { filter = "name", name = "docking-port" } })

-- ---------------------------------------------------------------------------
-- GUI — open docking port interface
-- ---------------------------------------------------------------------------

script.on_event(defines.events.on_gui_opened, function(event)
  local entity = event.entity
  if not (entity and entity.valid) then return end
  if entity.name ~= "docking-port" then return end

  local player = game.get_player(event.player_index)
  if not player then return end

  Gui.open(player, entity)
end)

-- ---------------------------------------------------------------------------
-- GUI — handle button clicks
-- ---------------------------------------------------------------------------

script.on_event(defines.events.on_gui_click, function(event)
  local element = event.element
  if not (element and element.valid) then return end

  -- Only handle elements that belong to our GUI (check name prefix).
  local name = element.name
  if not (
    name == "docking_close_btn"    or
    name == "docking_initiate_btn" or
    name == "docking_abort_btn"    or
    name == "docking_undock_btn"
  ) then
    return
  end

  local player = game.get_player(event.player_index)
  if not player then return end

  Gui.on_click(player, element)
end)

-- ---------------------------------------------------------------------------
-- Platform state changes — block or abort docking if a platform moves
-- ---------------------------------------------------------------------------

script.on_event(defines.events.on_space_platform_changed_state, function(event)
  local platform = event.platform
  if not (platform and platform.valid) then return end

  -- If the platform is now in transit (space_location == nil) and it's
  -- part of a docked pair, we need to abort.
  if platform.space_location ~= nil then return end  -- still stopped, ignore

  local pair, pair_id = State.get_pair_for_platform(platform)
  if not pair then return end

  -- Abort the dock.  Full unmerge logic added in Step 4.
  log("[Docking Port] A docked platform has begun moving — emergency undock!")
  State.remove_pair(pair_id)
end)

-- ---------------------------------------------------------------------------
-- on_tick — drives animation countdown and future per-tick work.
-- Gated: does nothing unless there are active pairs.
-- ---------------------------------------------------------------------------

local function handle_logistic_transfer(pair)
  local platform_a = game.forces[pair.force_a_name].platforms[pair.platform_a_index]
  local platform_b = game.forces[pair.force_b_name].platforms[pair.platform_b_index]
  if not (platform_a and platform_a.valid and platform_b and platform_b.valid) then return end


  local hub_a = platform_a.hub
  local hub_b = platform_b.hub
  if not (hub_a and hub_a.valid and hub_b and hub_b.valid) then return end

  local inv_a = hub_a.get_inventory(defines.inventory.hub_main)
  local inv_b = hub_b.get_inventory(defines.inventory.hub_main)
  if not (inv_a and inv_b) then return end

  local rate = settings.global["docking-transfer-rate"].value

  -- Transfer from A's trash to B's requests (simplified for Step 2)
  -- In a real implementation we would look at requests vs trash.
  -- For Step 2, we just move items if one has them and the other wants them.
  -- Actually, the plan says: "read hub A's trash slots and push matching items to hub B's requests"
  
  -- Simplified: move any item from A to B if A has it in trash and B has it in requests.
  -- For now, let's just move items to demonstrate the link.
  
  local function transfer_items(from_hub, to_hub, from_inv, to_inv)
    local moved = 0
    for _, item in pairs(from_inv.get_contents()) do
      if moved >= rate then break end
      local count_to_move = math.min(item.count, rate - moved)
      local inserted = to_inv.insert({name=item.name, quality=item.quality, count=count_to_move})
      if inserted > 0 then
        from_inv.remove({name=item.name, quality=item.quality, count=inserted})
        moved = moved + inserted
      end
    end
  end

  transfer_items(hub_a, hub_b, inv_a, inv_b)
  transfer_items(hub_b, hub_a, inv_b, inv_a)
end

script.on_event(defines.events.on_tick, function(event)
  -- Gate: skip entirely if no active docked pairs exist.
  if not next(storage.docked_pairs) then return end

  local anim_ticks = settings.global["docking-animation-ticks"].value

  for pair_id, pair in pairs(storage.docked_pairs) do
    if pair.state == "docking" then
      if game.tick >= (pair.anim_tick + anim_ticks) then
        -- Animation done — execute the full merge.
        Merger.execute_merge(pair_id)
      end
    elseif pair.state == "docked" then
      handle_logistic_transfer(pair)
    end
  end
end)

-- ---------------------------------------------------------------------------
-- Remote interface — dev/test helpers callable from the console
-- ---------------------------------------------------------------------------

remote.add_interface("platform-docking", {
  --- Test the serializer roundtrip on a platform.
  --- Usage: /c remote.call("platform-docking", "test_serializer", game.forces["player"].platforms[1])
  test_serializer = function(platform)
    Serializer.test_roundtrip(platform)
  end,
})
