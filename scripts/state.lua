-- scripts/state.lua
-- Global storage schema and helpers.
--
-- Schema:
--   storage.docked_pairs     = { [pair_id] = pair }
--   storage.port_to_pair     = { [unit_number] = pair_id }     -- ports A, B and B's clone
--   storage.platform_to_pair = { [platform_index] = pair_id }
--
-- Pair record:
--   platform_a_index, platform_b_index   host (A) and guest (B) platform indices
--   force_name                           both platforms belong to this force
--   port_a_unit, port_b_unit             original port unit numbers
--   port_b_clone_unit                    B's port as cloned onto A's surface (while docked)
--   corridor_length, corridor_width      corridor size chosen in the GUI
--   offset                               {x, y} added to B's coordinates to land on A
--   corridor_tiles                       tiles placed between the ports (A's coordinates)
--   footprint                            B's tiles in A's coordinates, hub cluster excluded
--   hub_hole_tiles                       B's hub cluster tiles in A's coordinates
--   overlay                              LuaEntity marking B's hub spot on A
--   a_paused_before, b_paused_before     paused flags to restore on undock
--   state                                "docking" | "docked" | "undock_pending"
--   anim_tick                            tick the docking countdown started

local State = {}

function State.init()
  storage.docked_pairs     = storage.docked_pairs     or {}
  storage.port_to_pair     = storage.port_to_pair     or {}
  storage.platform_to_pair = storage.platform_to_pair or {}
  -- Dropped in the merge/unmerge rework.
  storage.registered_ports = nil

  -- Pre-rework pair records can't be undocked by the new code; forget them.
  for pair_id, pair in pairs(storage.docked_pairs) do
    if not pair.force_name then
      log("[State] Dropping legacy pair record " .. pair_id .. " (undock before updating the mod).")
      State.remove_pair(pair_id)
    end
  end
end

--- Create a new pair record in the "docking" state.
---@param platform_a LuaSpacePlatform  host
---@param platform_b LuaSpacePlatform  guest
---@param port_a LuaEntity             port on the host
---@param port_b LuaEntity             port on the guest
---@param length number                corridor length chosen in the GUI
---@param width number                 corridor width chosen in the GUI
---@return number pair_id
function State.create_pair(platform_a, platform_b, port_a, port_b, length, width)
  storage._next_pair_id = (storage._next_pair_id or 0) + 1
  local pair_id = storage._next_pair_id

  storage.docked_pairs[pair_id] = {
    platform_a_index = platform_a.index,
    platform_b_index = platform_b.index,
    force_name       = platform_a.force.name,
    port_a_unit      = port_a.unit_number,
    port_b_unit      = port_b.unit_number,
    corridor_length  = length,
    corridor_width   = width,
    state            = "docking",
    anim_tick        = game.tick,
  }

  storage.port_to_pair[port_a.unit_number] = pair_id
  storage.port_to_pair[port_b.unit_number] = pair_id
  storage.platform_to_pair[platform_a.index] = pair_id
  storage.platform_to_pair[platform_b.index] = pair_id

  -- Fires on_object_destroyed however the port goes away (mined, died, script).
  script.register_on_object_destroyed(port_a)
  script.register_on_object_destroyed(port_b)

  return pair_id
end

--- Point an extra port unit number (B's clone) at a pair.
---@param pair_id number
---@param entity LuaEntity
function State.add_port(pair_id, entity)
  storage.port_to_pair[entity.unit_number] = pair_id
  script.register_on_object_destroyed(entity)
end

--- Remove a pair record and every lookup entry pointing at it.
---@param pair_id number
function State.remove_pair(pair_id)
  local pair = storage.docked_pairs[pair_id]
  if not pair then return end

  storage.platform_to_pair[pair.platform_a_index] = nil
  storage.platform_to_pair[pair.platform_b_index] = nil
  for unit, id in pairs(storage.port_to_pair) do
    if id == pair_id then storage.port_to_pair[unit] = nil end
  end
  storage.docked_pairs[pair_id] = nil
end

---@param entity LuaEntity
---@return table|nil pair, number|nil pair_id
function State.get_pair_for_port(entity)
  if not (entity and entity.valid and entity.unit_number) then return nil, nil end
  local pair_id = storage.port_to_pair[entity.unit_number]
  if not pair_id then return nil, nil end
  return storage.docked_pairs[pair_id], pair_id
end

---@param platform LuaSpacePlatform
---@return table|nil pair, number|nil pair_id
function State.get_pair_for_platform(platform)
  if not platform then return nil, nil end
  local pair_id = storage.platform_to_pair[platform.index]
  if not pair_id then return nil, nil end
  return storage.docked_pairs[pair_id], pair_id
end

--- Resolve a platform by force name + platform index.
---@param force_name string
---@param platform_index number
---@return LuaSpacePlatform|nil
function State.get_platform(force_name, platform_index)
  local force = game.forces[force_name]
  local platform = force and force.platforms[platform_index]
  if platform and platform.valid then return platform end
  return nil
end

---@param pair table
---@return LuaSpacePlatform|nil platform_a, LuaSpacePlatform|nil platform_b
function State.get_platforms(pair)
  return State.get_platform(pair.force_name, pair.platform_a_index),
         State.get_platform(pair.force_name, pair.platform_b_index)
end

return State
