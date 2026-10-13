-- scripts/lane.lua
-- Keeps the bridge lane in front of every docking port clear.
--
-- The lane is the 1-tile-wide strip running straight out from a port's
-- docking face, up to the longest possible bridge. Floor tiles built there
-- (by a player, robot or the platform itself) are turned back into empty
-- space and the items refunded, because they would block docking later.

local Corridor = require("scripts.corridor")

local Lane = {}

--- Is this tile in the lane of any docking port on the surface?
---@param surface LuaSurface
---@param tx number
---@param ty number
---@return boolean
local function in_any_lane(surface, tx, ty)
  local reach = Corridor.MAX_LENGTH
  local ports = surface.find_entities_filtered{
    name = "docking-port",
    area = { { tx - reach, ty - reach }, { tx + reach + 1, ty + reach + 1 } },
  }
  for _, port in ipairs(ports) do
    local vec = Corridor.DIRECTION_VECTOR[port.direction]
    -- Docked ports already have a bridge in their lane; the guest's port copy
    -- points back across the host, so its lane must not block the host.
    local pair_id = storage.port_to_pair[port.unit_number]
    local pair = pair_id and storage.docked_pairs[pair_id]
    if pair and pair.state ~= "docking" then vec = nil end
    if vec then
      local dx = tx - math.floor(port.position.x)
      local dy = ty - math.floor(port.position.y)
      local along = dx * vec.x + dy * vec.y
      local across = dx * vec.y - dy * vec.x
      if across == 0 and along >= 1 and along <= reach then return true end
    end
  end
  return false
end

--- Revert tiles built in a lane. Shared handler for the three tile-built events.
---@param event EventData.on_player_built_tile|EventData.on_robot_built_tile|EventData.on_space_platform_built_tile
function Lane.on_tiles_built(event)
  local surface = game.get_surface(event.surface_index)
  if not (surface and surface.platform) then return end

  local revert = {}
  for _, t in ipairs(event.tiles) do
    if in_any_lane(surface, t.position.x, t.position.y) then
      revert[#revert + 1] = { name = t.old_tile.name, position = t.position }
    end
  end
  if #revert == 0 then return end

  surface.set_tiles(revert, true, true)

  -- Give the items back where they came from.
  local inv = event.inventory
  if inv and inv.valid and event.item then
    local stack = { name = event.item.name, count = #revert,
                    quality = event.quality and event.quality.name or nil }
    local inserted = inv.insert(stack)
    if inserted < #revert then
      local hub = surface.platform.hub
      local hub_inv = hub and hub.valid and hub.get_inventory(defines.inventory.hub_main)
      if hub_inv then hub_inv.insert{ name = stack.name, count = #revert - inserted, quality = stack.quality } end
    end
  end

  local player = event.player_index and game.get_player(event.player_index)
  if player then
    player.create_local_flying_text{
      text = { "docking-message.lane-blocked" },
      position = revert[1].position,
      surface = surface,
    }
  end
end

return Lane
