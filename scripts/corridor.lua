-- scripts/corridor.lua
-- Places and removes the bridge tiles between two docking ports.
--
-- Corridor geometry:
--   Port A faces a cardinal direction (north/east/south/west).
--   The corridor tiles fill the gap between Port A's tile and Port B's tile
--   along that axis (both port tiles themselves are excluded).
--   Width is 1 tile for now; can be widened in Step 5.
--
-- Tile removal:
--   Factorio has no "delete tile" API on platform surfaces. On undock, corridor
--   tiles revert to space-platform-foundation. They sit at A's outer edge, so
--   the player can mine them manually if desired.

local Corridor = {}

local DIRECTION_VECTOR = {
  [defines.direction.north] = { x =  0, y = -1 },
  [defines.direction.east]  = { x =  1, y =  0 },
  [defines.direction.south] = { x =  0, y =  1 },
  [defines.direction.west]  = { x = -1, y =  0 },
}

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Place corridor tiles between port_a and where port_b will land on A's surface.
--- Fills pair.corridor_tiles with the placed positions.
---
---@param pair          table        docked pair record (from storage.docked_pairs)
---@param surface       LuaSurface   platform A's surface
---@param port_b_new_pos table       {x, y} — port_b's position after the offset is applied
---@return boolean      success
---@return string|nil   err          human-readable reason on failure
function Corridor.place_bridge(pair, surface, port_b_new_pos)
  local port_a = surface.find_entities_filtered{ unit_number = pair.port_a_unit }[1]
  if not (port_a and port_a.valid) then
    return false, "Port A not found on platform A's surface."
  end

  local vec = DIRECTION_VECTOR[port_a.direction]
  if not vec then
    return false, "Port A has an unsupported direction."
  end

  -- Integer tile coordinates (1×1 entities: tile = floor of centre position).
  local pa = { x = math.floor(port_a.position.x), y = math.floor(port_a.position.y) }
  local pb = { x = math.floor(port_b_new_pos.x),  y = math.floor(port_b_new_pos.y)  }

  -- Total step count from pa to pb along the corridor axis.
  local total_steps
  if vec.x ~= 0 then
    total_steps = math.abs(pb.x - pa.x)
  else
    total_steps = math.abs(pb.y - pa.y)
  end

  -- Tiles strictly between the two port tiles.
  local corridor_len = total_steps - 1

  if corridor_len <= 0 then
    -- Ports are directly adjacent; no gap tiles required.
    pair.corridor_tiles = {}
    return true, nil
  end

  local max_len = settings.global["max-corridor-length"].value
  if corridor_len > max_len then
    return false, string.format(
      "Platforms are too far apart to dock (%d-tile gap, max %d).",
      corridor_len, max_len)
  end

  -- Build and place.
  local tiles_to_set  = {}
  pair.corridor_tiles = {}

  for i = 1, corridor_len do
    local pos = { x = pa.x + vec.x * i, y = pa.y + vec.y * i }
    table.insert(tiles_to_set,   { name = "platform-docking-corridor", position = pos })
    table.insert(pair.corridor_tiles, { x = pos.x, y = pos.y })
  end

  surface.set_tiles(tiles_to_set)

  log(string.format("[Corridor] Placed %d corridor tile(s) from (%d,%d) toward (%d,%d).",
    corridor_len, pa.x, pa.y, pb.x, pb.y))

  return true, nil
end

--- Remove the corridor tiles placed by place_bridge.
--- Must be called AFTER all entities on corridor tiles have been destroyed,
--- as platform tiles with entities on them cannot be removed.
--- Corridor tiles revert to space-platform-foundation (mineable by the player).
---
---@param pair    table       docked pair record
---@param surface LuaSurface  platform A's surface
function Corridor.remove_bridge(pair, surface)
  if not (pair.corridor_tiles and #pair.corridor_tiles > 0) then return end

  local tiles_to_set = {}
  for _, pos in ipairs(pair.corridor_tiles) do
    table.insert(tiles_to_set, { name = "space-platform-foundation", position = pos })
  end

  surface.set_tiles(tiles_to_set)

  log(string.format("[Corridor] Reverted %d corridor tile(s) to foundation.",
    #pair.corridor_tiles))

  pair.corridor_tiles = {}
end

return Corridor
