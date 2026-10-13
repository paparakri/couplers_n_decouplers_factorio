-- scripts/logistics.lua
-- Moves items between the two hubs of a docked pair, driven by each hub's
-- logistic requests. Only fills what a hub is missing, and only takes what
-- the other hub doesn't request itself, so items never bounce back and forth.

local State = require("scripts.state")

local Logistics = {}

-- How often transfers run. The docking-transfer-rate setting is per tick, so
-- each run moves up to rate * INTERVAL items per direction.
Logistics.INTERVAL = 60

--- Requested counts per "name|quality" for a hub.
---@param hub LuaEntity
---@return table<string, {name: string, quality: string, count: number}>
local function requests_of(hub)
  local out = {}
  local point = hub.get_requester_point()
  if not (point and point.filters) then return out end
  for _, f in pairs(point.filters) do
    local comparator = f.comparator
    if f.name and (f.count or 0) > 0 and (comparator == nil or comparator == "=") then
      local quality = f.quality or "normal"
      if type(quality) ~= "string" then quality = quality.name end
      local key = f.name .. "|" .. quality
      local entry = out[key]
      if entry then
        entry.count = math.max(entry.count, f.count)
      else
        out[key] = { name = f.name, quality = quality, count = f.count }
      end
    end
  end
  return out
end

--- Fill `to`'s requests from `from`'s surplus.
---@return number moved
local function fill(to_hub, to_inv, from_inv, from_requests, budget)
  local moved = 0
  for key, req in pairs(requests_of(to_hub)) do
    if moved >= budget then break end
    local item = { name = req.name, quality = req.quality }
    local missing = req.count - to_inv.get_item_count(item)
    if missing > 0 then
      local keep = from_requests[key] and from_requests[key].count or 0
      local surplus = from_inv.get_item_count(item) - keep
      local count = math.min(missing, surplus, budget - moved)
      if count > 0 then
        local inserted = to_inv.insert{ name = req.name, quality = req.quality, count = count }
        if inserted > 0 then
          from_inv.remove{ name = req.name, quality = req.quality, count = inserted }
          moved = moved + inserted
        end
      end
    end
  end
  return moved
end

---@param pair table
local function transfer(pair)
  local platform_a, platform_b = State.get_platforms(pair)
  if not (platform_a and platform_b) then return end
  local hub_a, hub_b = platform_a.hub, platform_b.hub
  if not (hub_a and hub_a.valid and hub_b and hub_b.valid) then return end

  local inv_a = hub_a.get_inventory(defines.inventory.hub_main)
  local inv_b = hub_b.get_inventory(defines.inventory.hub_main)
  if not (inv_a and inv_b) then return end

  local budget = settings.global["docking-transfer-rate"].value * Logistics.INTERVAL
  local req_a, req_b = requests_of(hub_a), requests_of(hub_b)
  fill(hub_a, inv_a, inv_b, req_b, budget)
  fill(hub_b, inv_b, inv_a, req_a, budget)
end

function Logistics.on_interval()
  for _, pair in pairs(storage.docked_pairs) do
    if pair.state ~= "docking" then transfer(pair) end
  end
end

return Logistics
