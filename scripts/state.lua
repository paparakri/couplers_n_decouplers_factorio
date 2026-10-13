-- scripts/state.lua
-- Global storage schema and helpers.
--
-- Schema:
--   storage.docked_pairs       = { [pair_id] = pair }
--   storage.port_to_pair       = { [unit_number] = pair_id }   -- ports A, B and B's clone
--   storage.host_paused_before = { [platform_index] = bool }   -- host's paused flag before its
--                                                               -- first guest (moving disabled)
--
-- A host can hold several guests (carrier docking); a guest belongs to one
-- pair; a platform is never both host and guest. Platform lookups scan
-- docked_pairs, which only ever holds a handful of records.
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
--   b_paused_before                      guest's paused flag to restore on undock
--   state                                "docking" | "docked" | "undock_pending"
--   anim_tick                            tick the docking countdown started

local State = {}

function State.init()
  storage.docked_pairs       = storage.docked_pairs       or {}
  storage.port_to_pair       = storage.port_to_pair       or {}
  storage.host_paused_before = storage.host_paused_before or {}
  -- Dropped in earlier reworks.
  storage.registered_ports = nil
  storage.platform_to_pair = nil

  for pair_id, pair in pairs(storage.docked_pairs) do
    if not pair.force_name then
      -- Pre-rework pair records can't be undocked by the new code; forget them.
      log("[State] Dropping legacy pair record " .. pair_id .. " (undock before updating the mod).")
      State.remove_pair(pair_id)
    elseif pair.a_paused_before ~= nil then
      -- Single-guest saves kept the host's paused flag on the pair.
      if storage.host_paused_before[pair.platform_a_index] == nil then
        storage.host_paused_before[pair.platform_a_index] = pair.a_paused_before
      end
      pair.a_paused_before = nil
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

--- Every pair a platform takes part in, as a list of pair ids (sorted, so
--- iteration order is the same on every machine in multiplayer).
---@param platform_index number
---@param except_pair_id number|nil  leave this pair out
---@return number[] pair_ids
function State.pair_ids_of(platform_index, except_pair_id)
  local ids = {}
  for id, pair in pairs(storage.docked_pairs) do
    if id ~= except_pair_id
       and (pair.platform_a_index == platform_index or pair.platform_b_index == platform_index) then
      ids[#ids + 1] = id
    end
  end
  table.sort(ids)
  return ids
end

--- The pair in which this platform is the guest, if any.
---@param platform_index number
---@param except_pair_id number|nil
---@return number|nil pair_id
function State.guest_pair_id(platform_index, except_pair_id)
  for id, pair in pairs(storage.docked_pairs) do
    if id ~= except_pair_id and pair.platform_b_index == platform_index then return id end
  end
  return nil
end

--- How many guests this platform currently hosts (including ones still docking).
---@param platform_index number
---@param except_pair_id number|nil
---@return number
function State.guest_count(platform_index, except_pair_id)
  local n = 0
  for id, pair in pairs(storage.docked_pairs) do
    if id ~= except_pair_id and pair.platform_a_index == platform_index then n = n + 1 end
  end
  return n
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

--- Has the force researched Carrier Clamps (multiple guests, in-flight launch)?
---@param force LuaForce|string
---@return boolean
function State.has_carrier(force)
  if type(force) == "string" then force = game.forces[force] end
  local tech = force and force.technologies["platform-docking-carrier"]
  return tech ~= nil and tech.researched
end

return State
