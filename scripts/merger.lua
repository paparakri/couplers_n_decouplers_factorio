-- scripts/merger.lua
-- Orchestrates the full dock / undock sequence.
--
-- execute_merge(pair_id)
--   1. Snapshot platform B
--   2. Calculate offset so port B lands 1 tile past the corridor gap from port A
--   3. Place corridor tiles
--   4. Destroy B's entities from B's surface
--   5. Restore B's tiles + entities on A's surface (at offset positions)
--   6. Connect cross-corridor belts / pipes via linker
--   7. Hide platform B
--
-- execute_unmerge(pair_id)
--   1. Teleport players off B's side
--   2. Disconnect linker
--   3. Re-snapshot B's entities from A (inventories may have changed)
--   4. Destroy B's entities from A
--   5. Remove corridor tiles
--   6. Restore B's entities on B's surface
--   7. Un-hide platform B, clean up state

local Serializer = require("scripts.serializer")
local Corridor   = require("scripts.corridor")
local State      = require("scripts.state")
local Linker     = require("scripts.linker")

local Merger = {}

-- Cardinal direction vectors (tile steps).
local DIRECTION_VECTOR = {
  [defines.direction.north] = { x =  0, y = -1 },
  [defines.direction.east]  = { x =  1, y =  0 },
  [defines.direction.south] = { x =  0, y =  1 },
  [defines.direction.west]  = { x = -1, y =  0 },
}

-- ---------------------------------------------------------------------------
-- Private helpers
-- ---------------------------------------------------------------------------

--- Find a platform by force name + platform index (handles multiple forces).
---@param force_name string
---@param platform_index number
---@return LuaSpacePlatform|nil
local function get_platform(force_name, platform_index)
  local force = game.forces[force_name]
  if not force then return nil end
  for _, p in pairs(force.platforms) do
    if p.index == platform_index then return p end
  end
  return nil
end

--- Print a message to all players currently on a surface.
local function notify_surface(surface, msg)
  for _, player in pairs(game.players) do
    if player.valid and player.surface == surface then
      player.print(msg)
    end
  end
end

--- Teleport any player standing on B's side of the corridor to safety on A's
--- side before entities are torn down.
local function evacuate_b_side(pair, surface_a, port_a)
  if not (pair.offset and port_a and port_a.valid) then return end
  local dir_vec = DIRECTION_VECTOR[port_a.direction]
  if not dir_vec then return end

  -- Safe landing spot: 2 tiles behind port A (away from the corridor).
  local safe = {
    x = port_a.position.x - dir_vec.x * 2,
    y = port_a.position.y - dir_vec.y * 2,
  }

  for _, player in pairs(game.players) do
    if not (player.valid and player.surface == surface_a) then goto continue end
    -- Dot product tells us whether the player is past port A in the facing direction.
    local dot
    if dir_vec.x ~= 0 then
      dot = (player.position.x - port_a.position.x) * dir_vec.x
    else
      dot = (player.position.y - port_a.position.y) * dir_vec.y
    end
    if dot > 0 then
      player.teleport(safe, surface_a)
      player.print("[Docking Port] You were moved to safety before undocking.")
    end
    ::continue::
  end
end

-- ---------------------------------------------------------------------------
-- execute_merge
-- ---------------------------------------------------------------------------

---@param pair_id number
function Merger.execute_merge(pair_id)
  local pair = storage.docked_pairs[pair_id]
  if not pair then return end

  -- Resolve platforms.
  local platform_a = get_platform(pair.force_a_name, pair.platform_a_index)
  local platform_b = get_platform(pair.force_b_name, pair.platform_b_index)
  if not (platform_a and platform_a.valid and platform_b and platform_b.valid) then
    log("[Merger] execute_merge: platform(s) invalid — aborting.")
    State.remove_pair(pair_id)
    return
  end

  local surface_a = platform_a.surface
  local surface_b = platform_b.surface

  -- Resolve port entities by searching their respective surfaces directly.
  -- game.get_entity_by_unit_number does not search platform surfaces in 2.0.
  local port_a = surface_a.find_entities_filtered{ unit_number = pair.port_a_unit }[1]
  local port_b = surface_b.find_entities_filtered{ unit_number = pair.port_b_unit }[1]
  if not (port_a and port_a.valid and port_b and port_b.valid) then
    log("[Merger] execute_merge: port(s) not found on their surfaces — aborting.")
    State.remove_pair(pair_id)
    return
  end

  local dir_vec = DIRECTION_VECTOR[port_a.direction]
  if not dir_vec then
    log("[Merger] execute_merge: port A has unsupported direction.")
    State.remove_pair(pair_id)
    return
  end

  -- Capture port B's position now, before anything is destroyed.
  local port_b_orig = { x = port_b.position.x, y = port_b.position.y }

  -- 1. Snapshot platform B (entities + tiles).
  log("[Merger] Snapshotting platform B: " .. platform_b.name)
  local snapshot = Serializer.snapshot_platform(platform_b)
  if not snapshot then
    log("[Merger] Snapshot failed — aborting.")
    State.remove_pair(pair_id)
    return
  end
  pair.b_snapshot = snapshot

  -- 2. Calculate offset.
  --    Port B's new position = port A + facing direction * (corridor_gap + 1).
  --    corridor_gap = 1 tile  →  port B lands 2 tiles ahead of port A.
  local corridor_gap = 1
  -- Integer tile coordinates for both ports.
  local pa_tile = { x = math.floor(port_a.position.x), y = math.floor(port_a.position.y) }
  local pb_tile = { x = math.floor(port_b_orig.x),     y = math.floor(port_b_orig.y)     }

  -- Determine which axis is "facing" and which is perpendicular.
  local axis      = (dir_vec.x ~= 0) and "x" or "y"
  local perp_axis = (axis == "x")    and "y" or "x"
  local positive  = (dir_vec.x > 0 or dir_vec.y > 0)

  -- Find A's far edge in the facing direction (max/min tile coord on that axis).
  local a_far = pa_tile[axis]
  for _, tile in ipairs(surface_a.find_tiles_filtered{}) do
    local c = tile.position[axis]
    if positive then a_far = math.max(a_far, c) else a_far = math.min(a_far, c) end
  end

  -- Find B's near edge (the side of B closest to A, before any offset).
  local b_near = pb_tile[axis]
  for _, tile in ipairs(surface_b.find_tiles_filtered{}) do
    local c = tile.position[axis]
    if positive then b_near = math.min(b_near, c) else b_near = math.max(b_near, c) end
  end

  -- Offset along the facing axis: push B so its near edge lands corridor_gap+1
  -- tiles past A's far edge.  This guarantees A and B never overlap.
  local offset_axis
  if positive then
    offset_axis = (a_far + corridor_gap + 1) - b_near
  else
    offset_axis = (a_far - corridor_gap - 1) - b_near
  end

  -- Offset along the perpendicular axis: align the two ports on the same row/column.
  local offset_perp = pa_tile[perp_axis] - pb_tile[perp_axis]

  local offset = { x = 0, y = 0 }
  offset[axis]      = offset_axis
  offset[perp_axis] = offset_perp
  pair.offset = offset
  log(string.format("[Merger] Offset = (%d, %d)  a_far=%d  b_near=%d",
    offset.x, offset.y, a_far, b_near))

  -- Edge tiles for corridor: the tile just past A's far edge and the tile just
  -- before B's near edge (after offset), both at port A's perpendicular position.
  local a_edge_tile = { x = pa_tile.x, y = pa_tile.y }
  a_edge_tile[axis]      = a_far
  a_edge_tile[perp_axis] = pa_tile[perp_axis]

  local b_edge_tile = { x = pa_tile.x, y = pa_tile.y }
  b_edge_tile[axis]      = b_near + offset_axis
  b_edge_tile[perp_axis] = pa_tile[perp_axis]

  -- 3. Place corridor tiles on A's surface.
  local bridge_ok, bridge_err = Corridor.place_bridge(pair, surface_a,
                                                       port_a.direction,
                                                       a_edge_tile, b_edge_tile)
  if not bridge_ok then
    log("[Merger] Corridor placement failed: " .. tostring(bridge_err))
    notify_surface(surface_a, "[Docking Port] Docking failed: " .. tostring(bridge_err))
    State.remove_pair(pair_id)
    return
  end

  -- 4. Destroy B's entities from B's surface (leave hub intact).
  log("[Merger] Destroying B's entities from B's surface.")
  for _, entity in ipairs(surface_b.find_entities_filtered{}) do
    if entity.valid and entity.unit_number
       and entity.unit_number ~= snapshot.hub_unit_number then
      entity.destroy({ raise_destroy = true })
    end
  end

  -- 5. Restore B's tiles + entities on A's surface at the calculated offset.
  log("[Merger] Recreating B's content on A's surface.")
  local unit_map = Serializer.restore_platform(surface_a, snapshot, offset)

  -- 6. Record unit numbers of all of B's entities now on A's surface.
  pair.b_entity_ids = {}
  for old_id, new_entity in pairs(unit_map) do
    if new_entity and new_entity.valid then
      pair.b_entity_ids[new_entity.unit_number] = true
      -- Track port B's new unit number so we can find it quickly later.
      if old_id == pair.port_b_unit then
        pair.port_b_new_unit = new_entity.unit_number
      end
    end
  end

  -- 7. Connect cross-corridor belts and pipes.
  Linker.connect_corridor(pair, surface_a)

  -- 8. Hide platform B (API support may vary; wrapped in pcall).
  pcall(function() platform_b.hidden = true end)

  pair.state = "docked"
  log("[Merger] Merge complete — pair " .. pair_id .. " docked.")
  notify_surface(surface_a, "[Docking Port] Platforms docked!")
end

-- ---------------------------------------------------------------------------
-- execute_unmerge
-- ---------------------------------------------------------------------------

---@param pair_id number
function Merger.execute_unmerge(pair_id)
  local pair = storage.docked_pairs[pair_id]
  if not pair then return end

  pair.state = "undocking"

  local platform_a = get_platform(pair.force_a_name, pair.platform_a_index)
  local platform_b = get_platform(pair.force_b_name, pair.platform_b_index)
  if not (platform_a and platform_a.valid) then
    log("[Merger] execute_unmerge: platform A invalid.")
    State.remove_pair(pair_id)
    return
  end

  local surface_a = platform_a.surface
  local surface_b = platform_b and platform_b.valid and platform_b.surface or nil

  local port_a = surface_a.find_entities_filtered{ unit_number = pair.port_a_unit }[1]

  -- 1. Move players off B's side before anything is destroyed.
  evacuate_b_side(pair, surface_a, port_a)

  -- 2. Disconnect cross-corridor belts and pipes.
  Linker.disconnect_corridor(pair, surface_a)

  -- 3. Collect B's current entities from A's surface.
  local b_entities = {}
  for _, entity in ipairs(surface_a.find_entities_filtered{}) do
    if entity.valid and entity.unit_number
       and pair.b_entity_ids[entity.unit_number] then
      table.insert(b_entities, entity)
    end
  end

  -- 4. Re-snapshot B's entities at their current state (inventories may have
  --    changed during docking). Tiles are omitted — B's surface still has them.
  local fresh_snapshot = {
    entities        = {},
    tiles           = {},
    hub_unit_number = pair.b_snapshot and pair.b_snapshot.hub_unit_number or nil,
    platform_name   = pair.b_snapshot and pair.b_snapshot.platform_name   or nil,
  }
  for _, entity in ipairs(b_entities) do
    if entity.valid and entity.unit_number then
      fresh_snapshot.entities[entity.unit_number] =
        Serializer.serialize_entity(entity)
    end
  end

  -- 5. Destroy B's entities from A's surface.
  log("[Merger] Destroying B's entities from A's surface.")
  for _, entity in ipairs(b_entities) do
    if entity.valid then
      entity.destroy({ raise_destroy = true })
    end
  end

  -- 6. Remove the corridor tiles (reverts to foundation, players can mine).
  Corridor.remove_bridge(pair, surface_a)

  -- 7. Restore B's entities on B's surface using the reverse offset.
  if surface_b then
    log("[Merger] Restoring B's entities on B's surface.")
    local reverse_offset = { x = -pair.offset.x, y = -pair.offset.y }
    Serializer.restore_platform(surface_b, fresh_snapshot, reverse_offset)
  else
    log("[Merger] WARNING: B's surface not found — B's entities are lost.")
  end

  -- 8. Un-hide platform B.
  if platform_b and platform_b.valid then
    pcall(function() platform_b.hidden = false end)
  end

  -- 9. Clean up.
  local msg = "[Docking Port] Platforms undocked."
  notify_surface(surface_a, msg)
  if surface_b then notify_surface(surface_b, msg) end

  log("[Merger] Unmerge complete — pair " .. pair_id .. " dissolved.")
  State.remove_pair(pair_id)
end

return Merger
