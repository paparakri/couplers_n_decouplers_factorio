-- scripts/state.lua
-- Global storage schema and initialisation helpers.
--
-- Schema:
--   storage.docked_pairs     = { [pair_id] = { ... } }   -- active dock records
--   storage.port_to_pair     = { [unit_number] = pair_id } -- reverse lookup: port -> pair
--   storage.platform_to_pair = { [platform_index] = pair_id } -- reverse: platform -> pair
--   storage.registered_ports = { [unit_number] = true }   -- all known docking port entities

local State = {}

--- Called from on_init (new game).  Sets up empty tables.
function State.init()
  storage.docked_pairs     = storage.docked_pairs     or {}
  storage.port_to_pair     = storage.port_to_pair     or {}
  storage.platform_to_pair = storage.platform_to_pair or {}
  storage.registered_ports = storage.registered_ports or {}
end

--- Called from on_load (every game load).  No writes allowed here — just
--- re-register metatables if we ever add them. Currently a no-op.
function State.load()
end

--- Register a newly placed docking port entity.
---@param entity LuaEntity
function State.register_port(entity)
  if entity and entity.valid then
    storage.registered_ports[entity.unit_number] = true
  end
end

--- Unregister a docking port that is being removed.
--- Returns the pair_id it belonged to (if any), so the caller can abort the dock.
---@param entity LuaEntity
---@return number|nil pair_id
function State.unregister_port(entity)
  if not (entity and entity.valid) then return nil end
  local unit_number = entity.unit_number
  storage.registered_ports[unit_number] = nil
  local pair_id = storage.port_to_pair[unit_number]
  storage.port_to_pair[unit_number] = nil
  return pair_id
end

--- Returns true if the given entity is a registered docking port.
---@param entity LuaEntity
---@return boolean
function State.is_registered_port(entity)
  return entity and entity.valid
    and storage.registered_ports[entity.unit_number] == true
end

--- Create a new docked pair record and update all lookup tables.
---@param platform_a LuaSpacePlatform
---@param platform_b LuaSpacePlatform
---@param port_a LuaEntity
---@param port_b LuaEntity
---@return number pair_id
function State.create_pair(platform_a, platform_b, port_a, port_b)
  -- Use a monotonically increasing counter as the pair id.
  storage._next_pair_id = (storage._next_pair_id or 0) + 1
  local pair_id = storage._next_pair_id

  storage.docked_pairs[pair_id] = {
    platform_a_index  = platform_a.index,
    platform_b_index  = platform_b.index,
    force_a_name      = platform_a.force.name,
    force_b_name      = platform_b.force.name,
    port_a_unit       = port_a.unit_number,
    port_b_unit       = port_b.unit_number,
    offset            = nil,            -- set during merge (Step 4)
    corridor_tiles    = {},             -- populated by corridor.lua (Step 4)
    b_snapshot        = nil,            -- populated by serializer.lua (Step 3)
    b_entity_ids      = {},             -- populated during merge (Step 4)
    linked_belt_pairs = {},             -- populated by linker.lua (Step 4)
    linked_pipe_pairs = {},             -- populated by linker.lua (Step 4)
    state             = "docking",
    anim_tick         = game.tick,
  }

  storage.port_to_pair[port_a.unit_number] = pair_id
  storage.port_to_pair[port_b.unit_number] = pair_id
  storage.platform_to_pair[platform_a.index] = pair_id
  storage.platform_to_pair[platform_b.index] = pair_id

  return pair_id
end

--- Remove a pair record and clean up all lookup tables.
---@param pair_id number
function State.remove_pair(pair_id)
  local pair = storage.docked_pairs[pair_id]
  if not pair then return end

  storage.platform_to_pair[pair.platform_a_index] = nil
  storage.platform_to_pair[pair.platform_b_index] = nil
  storage.port_to_pair[pair.port_a_unit] = nil
  storage.port_to_pair[pair.port_b_unit] = nil
  storage.docked_pairs[pair_id] = nil
end

--- Get the pair record for a given docking port entity (by unit_number).
---@param entity LuaEntity
---@return table|nil pair, number|nil pair_id
function State.get_pair_for_port(entity)
  if not (entity and entity.valid) then return nil, nil end
  local pair_id = storage.port_to_pair[entity.unit_number]
  if not pair_id then return nil, nil end
  return storage.docked_pairs[pair_id], pair_id
end

--- Get the pair record for a given platform (by index).
---@param platform LuaSpacePlatform
---@return table|nil pair, number|nil pair_id
function State.get_pair_for_platform(platform)
  if not platform then return nil, nil end
  local pair_id = storage.platform_to_pair[platform.index]
  if not pair_id then return nil, nil end
  return storage.docked_pairs[pair_id], pair_id
end

return State
