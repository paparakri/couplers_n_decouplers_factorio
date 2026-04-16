-- scripts/orbit-check.lua
-- Determines whether two platforms are eligible to dock, and lists
-- compatible targets visible from a given docking port.

local OrbitCheck = {}

-- Direction names for human-readable labels in the dropdown.
local DIRECTION_NAMES = {
  [defines.direction.north] = "north",
  [defines.direction.east]  = "east",
  [defines.direction.south] = "south",
  [defines.direction.west]  = "west",
}

--- Returns true if two platforms are eligible to dock, plus an optional
--- human-readable reason string when they are NOT eligible.
---
---@param platform_a LuaSpacePlatform
---@param platform_b LuaSpacePlatform
---@return boolean can_dock
---@return string|nil reason   -- nil when can_dock is true
function OrbitCheck.can_platforms_dock(platform_a, platform_b)
  -- 1. Both must be stopped (space_location is nil while in transit).
  if not platform_a.space_location then
    return false, "Platform A is currently in transit."
  end
  if not platform_b.space_location then
    return false, "Platform B is currently in transit."
  end

  -- 2. Both must be at the same space location.
  if platform_a.space_location.name ~= platform_b.space_location.name then
    return false, "Platforms are at different space locations."
  end

  -- 3. Neither platform may already be part of a docked pair.
  if storage.platform_to_pair[platform_a.index] then
    return false, "Platform A is already docked."
  end
  if storage.platform_to_pair[platform_b.index] then
    return false, "Platform B is already docked."
  end

  -- 4. Both must belong to the same force (allied-force support can be added later).
  if platform_a.force.index ~= platform_b.force.index then
    return false, "Platforms belong to different forces."
  end

  return true, nil
end

--- Find all docking ports on a given platform surface.
---
---@param platform LuaSpacePlatform
---@return LuaEntity[]
local function find_ports_on_platform(platform)
  if not (platform and platform.valid and platform.surface) then return {} end
  return platform.surface.find_entities_filtered{ name = "docking-port" }
end

--- Build the list of compatible docking targets visible from a given port.
--- A "compatible target" is any docking port on a different platform that:
---   • passes OrbitCheck.can_platforms_dock(), AND
---   • belongs to a platform that has at least one docking port.
---
--- Returns a list of entries:
---   { platform = LuaSpacePlatform, port = LuaEntity, label = string }
---
---@param port_entity LuaEntity   -- the port the player opened
---@return table[] targets
function OrbitCheck.get_compatible_platforms(port_entity)
  local targets = {}

  if not (port_entity and port_entity.valid) then return targets end

  -- Identify which platform this port lives on.
  local my_platform = port_entity.surface.platform
  if not my_platform then return targets end

  -- Iterate all other platforms via game.surfaces
  for _, surface in pairs(game.surfaces) do
    local platform = surface.platform
    if not (platform and platform.valid) then goto continue end
    if platform.index == my_platform.index then goto continue end

    local can_dock, _ = OrbitCheck.can_platforms_dock(my_platform, platform)
    if can_dock then
      local ports = find_ports_on_platform(platform)
      for _, port in pairs(ports) do
        if port.valid then
          local dir_name = DIRECTION_NAMES[port.direction] or "unknown"
          local loc_name = platform.space_location
            and platform.space_location.name or "unknown location"
          table.insert(targets, {
            platform = platform,
            port     = port,
            label    = string.format("%s @ %s — port facing %s",
                         platform.name, loc_name, dir_name),
          })
        end
      end
    end

    ::continue::
  end

  return targets
end

return OrbitCheck
