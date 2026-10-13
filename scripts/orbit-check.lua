-- scripts/orbit-check.lua
-- Determines whether two platforms are eligible to dock, picks the host, and
-- lists compatible targets visible from a given docking port.
--
-- Roles: a platform already hosting guests must be the host again (carrier
-- docking, needs the Carrier Clamps technology). A guest can't dock to
-- anything else, and a host can't become a guest (no chains).

local State = require("scripts.state")

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
---@return LocalisedString|nil reason
local function platform_problem(platform)
  if not (platform and platform.valid) then
    return { "docking-message.platform-missing" }
  end
  if platform.scheduled_for_deletion > 0 then
    return { "docking-message.platform-deleting", platform.name }
  end
  if not platform.space_location then
    return { "docking-message.platform-in-transit", platform.name }
  end
  return nil
end

--- Location, force and lifecycle checks. Roles are checked by choose_host.
---@param platform_a LuaSpacePlatform
---@param platform_b LuaSpacePlatform
---@return boolean can_dock
---@return LocalisedString|nil reason
function OrbitCheck.can_platforms_dock(platform_a, platform_b)
  local problem = platform_problem(platform_a) or platform_problem(platform_b)
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

--- Decide which platform hosts. A platform that already hosts stays the host;
--- otherwise the larger one hosts (ties go to the platform whose port was opened).
---@param opened LuaSpacePlatform
---@param other LuaSpacePlatform
---@param own_pair_id number|nil  ignore this pair (re-checking a dock in progress)
---@return LuaSpacePlatform|nil host
---@return LuaSpacePlatform|nil guest
---@return LocalisedString|nil reason
function OrbitCheck.choose_host(opened, other, own_pair_id)
  for _, p in ipairs{ opened, other } do
    if State.guest_pair_id(p.index, own_pair_id) then
      return nil, nil, { "docking-message.platform-already-docked", p.name }
    end
  end

  local opened_hosts = State.guest_count(opened.index, own_pair_id) > 0
  local other_hosts  = State.guest_count(other.index, own_pair_id) > 0
  if opened_hosts and other_hosts then
    return nil, nil, { "docking-message.both-hosting" }
  end

  local host, guest
  if opened_hosts then
    host, guest = opened, other
  elseif other_hosts then
    host, guest = other, opened
  elseif tile_count(other) > tile_count(opened) then
    host, guest = other, opened
  else
    host, guest = opened, other
  end

  if State.guest_count(host.index, own_pair_id) > 0 and not State.has_carrier(host.force) then
    return nil, nil, { "docking-message.needs-carrier", host.name }
  end
  return host, guest, nil
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
       and OrbitCheck.can_platforms_dock(my_platform, platform)
       and OrbitCheck.choose_host(my_platform, platform) then
      for _, port in ipairs(platform.surface.find_entities_filtered{
          name = "docking-port", direction = wanted_dir }) do
        -- Ports already in a pair (including guests' ports cloned onto a host) are busy.
        if not storage.port_to_pair[port.unit_number] then
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
  end

  return targets
end

return OrbitCheck
