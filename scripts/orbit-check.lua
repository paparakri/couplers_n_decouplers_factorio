-- scripts/orbit-check.lua
-- Determines whether two platforms are eligible to dock, picks the host, and
-- lists compatible targets visible from a given docking port.

local OrbitCheck = {}

local DIRECTION_NAMES = {
  [defines.direction.north] = "north",
  [defines.direction.east]  = "east",
  [defines.direction.south] = "south",
  [defines.direction.west]  = "west",
}

-- B's layout is copied without rotation, so the two ports must face each other.
local OPPOSITE = {
  [defines.direction.north] = defines.direction.south,
  [defines.direction.east]  = defines.direction.west,
  [defines.direction.south] = defines.direction.north,
  [defines.direction.west]  = defines.direction.east,
}
OrbitCheck.OPPOSITE = OPPOSITE

---@param platform LuaSpacePlatform
---@param own_pair_id number|nil  a pair this platform may already belong to
---@return LocalisedString|nil reason
local function platform_problem(platform, own_pair_id)
  if not (platform and platform.valid) then
    return { "docking-message.platform-missing" }
  end
  if platform.scheduled_for_deletion > 0 then
    return { "docking-message.platform-deleting", platform.name }
  end
  if not platform.space_location then
    return { "docking-message.platform-in-transit", platform.name }
  end
  local pair_id = storage.platform_to_pair[platform.index]
  if pair_id and pair_id ~= own_pair_id then
    return { "docking-message.platform-already-docked", platform.name }
  end
  return nil
end

--- Returns true if two platforms are eligible to dock, otherwise false and a
--- localised reason.
---@param platform_a LuaSpacePlatform
---@param platform_b LuaSpacePlatform
---@param own_pair_id number|nil  ignore this pair when checking "already docked"
---@return boolean can_dock
---@return LocalisedString|nil reason
function OrbitCheck.can_platforms_dock(platform_a, platform_b, own_pair_id)
  local problem = platform_problem(platform_a, own_pair_id)
               or platform_problem(platform_b, own_pair_id)
  if problem then return false, problem end

  if platform_a.index == platform_b.index then
    return false, { "docking-message.same-platform" }
  end
  if platform_a.space_location.name ~= platform_b.space_location.name then
    return false, { "docking-message.different-locations" }
  end
  -- Allied-force support can be added later.
  if platform_a.force.index ~= platform_b.force.index then
    return false, { "docking-message.different-forces" }
  end
  return true, nil
end

--- Number of foundation tiles on a platform.
---@param platform LuaSpacePlatform
---@return number
local function tile_count(platform)
  return platform.surface.count_tiles_filtered{ name = "empty-space", invert = true }
end

--- The larger platform hosts; the smaller one is copied onto it.
--- Ties go to the platform whose port was opened.
---@param opened LuaSpacePlatform
---@param other LuaSpacePlatform
---@return LuaSpacePlatform host, LuaSpacePlatform guest
function OrbitCheck.choose_host(opened, other)
  if tile_count(other) > tile_count(opened) then
    return other, opened
  end
  return opened, other
end

--- Build the list of compatible docking targets visible from a given port.
--- Returns entries { platform, port, label }.
---@param port_entity LuaEntity
---@return table[] targets
function OrbitCheck.get_compatible_platforms(port_entity)
  local targets = {}
  if not (port_entity and port_entity.valid) then return targets end

  local my_platform = port_entity.surface.platform
  if not my_platform then return targets end
  local wanted_dir = OPPOSITE[port_entity.direction]

  for _, platform in pairs(port_entity.force.platforms) do
    if platform.valid and platform.index ~= my_platform.index
       and OrbitCheck.can_platforms_dock(my_platform, platform) then
      for _, port in ipairs(platform.surface.find_entities_filtered{
          name = "docking-port", direction = wanted_dir }) do
        targets[#targets + 1] = {
          platform = platform,
          port     = port,
          label    = { "gui.docking-target-label", platform.name,
                       { "gui.docking-dir-" .. (DIRECTION_NAMES[port.direction] or "unknown") },
                       string.format("%d, %d", math.floor(port.position.x), math.floor(port.position.y)) },
        }
      end
    end
  end

  return targets
end

return OrbitCheck
