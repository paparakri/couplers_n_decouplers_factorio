-- scripts/footprint.lua
-- Tile-set helpers used by the merger.
--
-- A "tile list" is an array of { x = int, y = int } tile positions.
-- A "key set" is { ["x,y"] = true } for fast membership tests.

local Footprint = {}

---@param x number
---@param y number
---@return string
function Footprint.key(x, y)
  return x .. "," .. y
end

---@param tiles table[]
---@return table<string, boolean>
function Footprint.keyset(tiles)
  local set = {}
  for _, t in ipairs(tiles) do set[t.x .. "," .. t.y] = true end
  return set
end

--- All non-empty-space tiles on a surface.
---@param surface LuaSurface
---@return table[] tiles
function Footprint.tiles_of(surface)
  local tiles = {}
  for _, tile in ipairs(surface.find_tiles_filtered{ name = "empty-space", invert = true }) do
    tiles[#tiles + 1] = { x = tile.position.x, y = tile.position.y }
  end
  return tiles
end

--- Tile positions covered by an entity's bounding box.
---@param entity LuaEntity
---@return table[] tiles
function Footprint.entity_tiles(entity)
  local box = entity.bounding_box
  local tiles = {}
  for x = math.floor(box.left_top.x), math.ceil(box.right_bottom.x) - 1 do
    for y = math.floor(box.left_top.y), math.ceil(box.right_bottom.y) - 1 do
      tiles[#tiles + 1] = { x = x, y = y }
    end
  end
  return tiles
end

--- The hub and every cargo bay on a platform's surface — these never leave B.
---@param platform LuaSpacePlatform
---@return LuaEntity[] entities, table[] tiles
function Footprint.hub_cluster(platform)
  local entities, tiles = {}, {}
  local hub = platform.hub
  if hub and hub.valid then entities[#entities + 1] = hub end
  for _, bay in ipairs(platform.surface.find_entities_filtered{ type = "cargo-bay" }) do
    entities[#entities + 1] = bay
  end
  for _, e in ipairs(entities) do
    for _, t in ipairs(Footprint.entity_tiles(e)) do tiles[#tiles + 1] = t end
  end
  return entities, tiles
end

--- Remove every tile in `remove_set` from `tiles`.
---@param tiles table[]
---@param remove_set table<string, boolean>
---@return table[]
function Footprint.subtract(tiles, remove_set)
  local out = {}
  for _, t in ipairs(tiles) do
    if not remove_set[t.x .. "," .. t.y] then out[#out + 1] = t end
  end
  return out
end

---@param tiles table[]
---@param offset table {x, y}
---@return table[]
function Footprint.shift(tiles, offset)
  local out = {}
  for i, t in ipairs(tiles) do out[i] = { x = t.x + offset.x, y = t.y + offset.y } end
  return out
end

--- Bounding box (in map coordinates) enclosing every tile in the list.
---@param tiles table[]
---@return BoundingBox|nil
function Footprint.bbox(tiles)
  if #tiles == 0 then return nil end
  local x1, y1, x2, y2 = math.huge, math.huge, -math.huge, -math.huge
  for _, t in ipairs(tiles) do
    if t.x < x1 then x1 = t.x end
    if t.y < y1 then y1 = t.y end
    if t.x > x2 then x2 = t.x end
    if t.y > y2 then y2 = t.y end
  end
  return { left_top = { x = x1, y = y1 }, right_bottom = { x = x2 + 1, y = y2 + 1 } }
end

--- Entities whose position lies on a tile of the key set.
---@param surface LuaSurface
---@param tiles table[]
---@param keyset table<string, boolean>
---@param force string|nil  only entities of this force when given
---@return LuaEntity[]
function Footprint.entities_in(surface, tiles, keyset, force)
  local area = Footprint.bbox(tiles)
  if not area then return {} end
  local out = {}
  for _, e in ipairs(surface.find_entities_filtered{ area = area, force = force }) do
    if e.valid and keyset[math.floor(e.position.x) .. "," .. math.floor(e.position.y)] then
      out[#out + 1] = e
    end
  end
  return out
end

--- Entities whose bounding box touches any tile of the key set.
---@param surface LuaSurface
---@param tiles table[]
---@param keyset table<string, boolean>
---@return LuaEntity[]
function Footprint.entities_touching(surface, tiles, keyset)
  local area = Footprint.bbox(tiles)
  if not area then return {} end
  local out = {}
  for _, e in ipairs(surface.find_entities_filtered{ area = area }) do
    if e.valid then
      for _, t in ipairs(Footprint.entity_tiles(e)) do
        if keyset[t.x .. "," .. t.y] then out[#out + 1] = e; break end
      end
    end
  end
  return out
end

return Footprint
