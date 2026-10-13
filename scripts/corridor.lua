-- scripts/corridor.lua
-- Computes, places and removes the bridge tiles between two docking ports.
--
-- Corridor geometry:
--   Port A faces a cardinal direction. The corridor fills the tiles strictly
--   between port A's tile and port B's (post-offset) tile along that axis.
--   Length and width are chosen per dock in the port GUI (defaults from the
--   docking-corridor-length / docking-corridor-width settings).

local Corridor = {}

Corridor.DIRECTION_VECTOR = {
  [defines.direction.north] = { x =  0, y = -1 },
  [defines.direction.east]  = { x =  1, y =  0 },
  [defines.direction.south] = { x =  0, y =  1 },
  [defines.direction.west]  = { x = -1, y =  0 },
}

-- Limits for the player-chosen corridor size (settings use the same bounds).
Corridor.MAX_LENGTH = 10
Corridor.MAX_WIDTH  = 9

--- Clamp a requested size to whole numbers within limits.
---@param length number|nil
---@param width number|nil
---@return number length, number width
function Corridor.clamp(length, width)
  length = math.floor(tonumber(length) or settings.global["docking-corridor-length"].value)
  width  = math.floor(tonumber(width)  or settings.global["docking-corridor-width"].value)
  return math.max(1, math.min(length, Corridor.MAX_LENGTH)),
         math.max(1, math.min(width, Corridor.MAX_WIDTH))
end

--- Tiles between the two ports: `length` tiles out from port A's tile,
--- `width` tiles across, centred on the ports' row/column.
---@param direction defines.direction  port A's facing direction
---@param a_tile table  {x, y} port A's tile
---@param length number
---@param width number
---@return table[] tiles
function Corridor.tiles_between(direction, a_tile, length, width)
  local vec  = Corridor.DIRECTION_VECTOR[direction]
  local perp = (vec.x ~= 0) and { x = 0, y = 1 } or { x = 1, y = 0 }
  local first = -math.floor((width - 1) / 2)
  local tiles = {}
  for i = 1, length do
    for j = first, first + width - 1 do
      tiles[#tiles + 1] = {
        x = a_tile.x + vec.x * i + perp.x * j,
        y = a_tile.y + vec.y * i + perp.y * j,
      }
    end
  end
  return tiles
end

--- Place corridor tiles. Never removes entities: the merger has already
--- checked that these tiles are empty.
---@param surface LuaSurface  platform A's surface
---@param tiles table[]
function Corridor.place_bridge(surface, tiles)
  if #tiles == 0 then return end
  local to_set = {}
  for i, pos in ipairs(tiles) do
    to_set[i] = { name = "platform-docking-corridor", position = pos }
  end
  surface.set_tiles(to_set, true, false)
  log(string.format("[Corridor] Placed %d corridor tile(s).", #tiles))
end

--- Turn tiles back into empty space. Anything still standing on them is
--- removed by the engine, so callers clear entities first.
---@param surface LuaSurface
---@param tiles table[]
function Corridor.clear_tiles(surface, tiles)
  if #tiles == 0 then return end
  local to_set = {}
  for i, pos in ipairs(tiles) do
    to_set[i] = { name = "empty-space", position = pos }
  end
  surface.set_tiles(to_set, true, true)
end

return Corridor
