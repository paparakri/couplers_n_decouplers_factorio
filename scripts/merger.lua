-- scripts/merger.lua
-- Orchestrates the dock / undock sequence.
--
-- Platform A is the host, platform B the guest. Docking copies B's layout
-- (everything except its hub and cargo bays) onto A's surface with
-- LuaSurface.clone_brush, then removes the originals from B. B stays hidden
-- and paused while docked; when A flies, B's content flies with it and B's
-- space_location is kept in sync with A's.
--
-- execute_merge(pair_id)
--   1. Plan geometry and check that every target tile on A is empty space
--   2. Clone B -> A, verify the clone count (roll back on mismatch)
--   3. Corridor tiles, hub-hole foundation, hub overlay
--   4. Destroy B's originals, hide + pause B
--
-- request_undock(pair_id) / execute_unmerge(pair_id)
--   1. If A is in transit, mark the pair pending and finish on arrival
--   2. Mine entities straddling B's footprint edge into A's hub
--   3. Clone the footprint A -> B, verify (stay docked on mismatch)
--   4. Destroy the footprint on A, turn its tiles back into empty space
--   5. Un-hide B, restore paused flags, forget the pair

local Footprint  = require("scripts.footprint")
local Corridor   = require("scripts.corridor")
local State      = require("scripts.state")
local OrbitCheck = require("scripts.orbit-check")

local Merger = {}

-- Set while we write space_location ourselves, so the state-change handler
-- doesn't react to our own changes.
local syncing = false

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

---@param pair table
---@param msg LocalisedString
local function notify(pair, msg)
  local force = game.forces[pair.force_name]
  if force then force.print(msg) end
end

---@param a table[]
---@param b table[]
---@return table[]
local function concat(a, b)
  local out = {}
  for _, t in ipairs(a) do out[#out + 1] = t end
  for _, t in ipairs(b) do out[#out + 1] = t end
  return out
end

---@param pos MapPosition
---@return table {x, y}
local function tile_of(pos)
  return { x = math.floor(pos.x), y = math.floor(pos.y) }
end

--- Set B's space_location to A's when A is stopped somewhere else.
---@param platform_a LuaSpacePlatform
---@param platform_b LuaSpacePlatform
local function sync_location(platform_a, platform_b)
  local loc = platform_a.space_location
  if not loc then return end
  if platform_b.space_location and platform_b.space_location.name == loc.name then return end
  syncing = true
  local ok, err = pcall(function() platform_b.space_location = loc end)
  syncing = false
  if ok then
    log("[Merger] Moved guest platform " .. platform_b.name .. " to " .. loc.name)
  else
    log("[Merger] Could not move guest platform to " .. loc.name .. ": " .. tostring(err))
  end
end

--- Players looking at (or sitting in) the guest are moved to the host once
--- the guest is hidden, so nobody is left staring at an empty platform.
---@param platform_a LuaSpacePlatform
---@param platform_b LuaSpacePlatform
---@param focus MapPosition  where to centre the view on A's surface
local function move_players_to_host(platform_a, platform_b, focus)
  local surface_b = platform_b.surface
  for _, player in pairs(game.connected_players) do
    local hub = player.hub
    if hub and hub.valid and hub.surface == surface_b then
      -- Physically in the guest's hub: move into the host's hub.
      if not player.enter_space_platform(platform_a) then
        log("[Merger] Could not move " .. player.name .. " into the host platform")
      end
    end
    if player.surface == surface_b then
      local ok, err = pcall(function()
        player.set_controller{
          type = defines.controllers.remote, surface = platform_a.surface, position = focus,
        }
      end)
      if not ok then log("[Merger] Could not move " .. player.name .. "'s view: " .. tostring(err)) end
    end
  end
end

--- On undock, players viewing the guest's part of the host follow it back to
--- the guest's own surface, at the same spot in its layout.
---@param surface_a LuaSurface
---@param platform_b LuaSpacePlatform
---@param footprint_set table<string, boolean>  guest tiles in host coordinates
---@param back_offset table {x, y}  host -> guest coordinate shift
local function move_players_to_guest(surface_a, platform_b, footprint_set, back_offset)
  for _, player in pairs(game.connected_players) do
    local pos = player.position
    if player.surface == surface_a
       and footprint_set[math.floor(pos.x) .. "," .. math.floor(pos.y)] then
      local ok, err = pcall(function()
        player.set_controller{
          type     = defines.controllers.remote,
          surface  = platform_b.surface,
          position = { x = pos.x + back_offset.x, y = pos.y + back_offset.y },
        }
      end)
      if not ok then log("[Merger] Could not move " .. player.name .. "'s view: " .. tostring(err)) end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Geometry
-- ---------------------------------------------------------------------------

--- Work out where B lands on A and check it fits. Pure read; changes nothing.
---@param platform_a LuaSpacePlatform
---@param platform_b LuaSpacePlatform
---@param port_a LuaEntity
---@param port_b LuaEntity
---@param length number  corridor length in tiles (already clamped)
---@param width number   corridor width in tiles (already clamped)
---@return table|nil plan
---@return LocalisedString|nil reason
function Merger.plan(platform_a, platform_b, port_a, port_b, length, width)
  local dir = port_a.direction
  local vec = Corridor.DIRECTION_VECTOR[dir]
  if not vec then return nil, { "docking-message.bad-direction" } end
  if port_b.direction ~= OrbitCheck.OPPOSITE[dir] then
    return nil, { "docking-message.ports-not-facing" }
  end

  local pa_tile = tile_of(port_a.position)
  local pb_tile = tile_of(port_b.position)
  local pb_new  = { x = pa_tile.x + vec.x * (length + 1), y = pa_tile.y + vec.y * (length + 1) }
  local offset  = { x = pb_new.x - pb_tile.x, y = pb_new.y - pb_tile.y }

  local surface_a = platform_a.surface
  local surface_b = platform_b.surface

  local hub_entities, hub_tiles = Footprint.hub_cluster(platform_b)
  local source_tiles = Footprint.subtract(Footprint.tiles_of(surface_b), Footprint.keyset(hub_tiles))
  local footprint    = Footprint.shift(source_tiles, offset)
  local hub_hole     = Footprint.shift(hub_tiles, offset)
  local corridor     = Corridor.tiles_between(dir, pa_tile, length, width)

  -- Every tile B needs on A must currently be empty space.
  local all = concat(concat(footprint, hub_hole), corridor)
  for _, t in ipairs(all) do
    local name = surface_a.get_tile(t.x, t.y).name
    -- out-of-map: chunk not generated yet; clone_brush expands the map there.
    if name ~= "empty-space" and name ~= "out-of-map" then
      return nil, { "docking-message.overlap" }
    end
  end
  -- …and nothing may stand there (asteroids drifting through are fine).
  for _, e in ipairs(Footprint.entities_touching(surface_a, all, Footprint.keyset(all))) do
    if e.type ~= "asteroid" then
      return nil, { "docking-message.overlap" }
    end
  end

  local hub = platform_b.hub
  return {
    offset         = offset,
    source_tiles   = source_tiles,
    footprint      = footprint,
    hub_hole       = hub_hole,
    hub_entities   = hub_entities,
    corridor       = corridor,
    port_b_new     = { x = pb_new.x + 0.5, y = pb_new.y + 0.5 },
    overlay_pos    = hub and hub.valid
                     and { x = hub.position.x + offset.x, y = hub.position.y + offset.y } or nil,
  }, nil
end

-- ---------------------------------------------------------------------------
-- Merge
-- ---------------------------------------------------------------------------

---@param pair_id number
---@param reason LocalisedString
local function fail_merge(pair_id, pair, reason)
  log("[Merger] Docking failed for pair " .. pair_id)
  notify(pair, { "", { "docking-message.prefix" }, { "docking-message.dock-failed" }, " ", reason })
  State.remove_pair(pair_id)
end

---@param pair_id number
function Merger.execute_merge(pair_id)
  local pair = storage.docked_pairs[pair_id]
  if not pair then return end

  local platform_a, platform_b = State.get_platforms(pair)
  local port_a = game.get_entity_by_unit_number(pair.port_a_unit)
  local port_b = game.get_entity_by_unit_number(pair.port_b_unit)
  if not (platform_a and platform_b) then
    return fail_merge(pair_id, pair, { "docking-message.platform-missing" })
  end
  if not (port_a and port_a.valid and port_b and port_b.valid) then
    return fail_merge(pair_id, pair, { "docking-message.port-missing" })
  end
  local ok, reason = OrbitCheck.can_platforms_dock(platform_a, platform_b, pair_id)
  if not ok then return fail_merge(pair_id, pair, reason) end

  -- 1. Plan + validate. Nothing has changed yet.
  local length, width = Corridor.clamp(pair.corridor_length, pair.corridor_width)
  local plan, plan_err = Merger.plan(platform_a, platform_b, port_a, port_b, length, width)
  if not plan then return fail_merge(pair_id, pair, plan_err) end

  local surface_a, surface_b = platform_a.surface, platform_b.surface
  local force = pair.force_name
  local source_set    = Footprint.keyset(plan.source_tiles)
  local footprint_set = Footprint.keyset(plan.footprint)

  local originals = Footprint.entities_in(surface_b, plan.source_tiles, source_set, force)
  log(string.format("[Merger] Pair %d: offset=(%d,%d) tiles=%d entities=%d",
    pair_id, plan.offset.x, plan.offset.y, #plan.source_tiles, #originals))

  -- 2. Clone B -> A.
  surface_b.clone_brush{
    source_positions           = plan.source_tiles,
    -- Required by the engine. With a zero source_offset, each tile lands at
    -- position + destination_offset.
    source_offset              = { x = 0, y = 0 },
    destination_surface        = surface_a,
    destination_offset         = plan.offset,
    destination_force          = force,
    clone_tiles                = true,
    clone_entities             = true,
    clone_decoratives          = true,
    clear_destination_entities = false,
    clear_destination_decoratives = true,
    create_build_effect_smoke  = false,
    expand_map                 = true,
    manual_collision_mode      = false,
  }

  -- Drifting asteroids get cloned too; they don't belong to anyone.
  local area = Footprint.bbox(plan.footprint)
  for _, e in ipairs(surface_a.find_entities_filtered{ area = area, type = "asteroid" }) do
    if footprint_set[math.floor(e.position.x) .. "," .. math.floor(e.position.y)] then e.destroy() end
  end

  local clones = Footprint.entities_in(surface_a, plan.footprint, footprint_set, force)
  log(string.format("[Merger] Pair %d: cloned %d / %d entities", pair_id, #clones, #originals))
  if #clones ~= #originals then
    -- Roll back: B is untouched, so just remove what we placed on A.
    for _, e in ipairs(Footprint.entities_touching(surface_a, plan.footprint, footprint_set)) do
      if e.valid then e.destroy() end
    end
    Corridor.clear_tiles(surface_a, plan.footprint)
    return fail_merge(pair_id, pair, { "docking-message.clone-mismatch", #clones, #originals })
  end

  -- 3. Corridor, hub hole, overlay.
  Corridor.place_bridge(surface_a, plan.corridor)
  local hole = {}
  for i, t in ipairs(plan.hub_hole) do hole[i] = { name = "space-platform-foundation", position = t } end
  surface_a.set_tiles(hole, true, false)
  if plan.overlay_pos then
    pair.overlay = surface_a.create_entity{
      name = "platform-docking-hub-overlay", position = plan.overlay_pos, force = force,
    }
  end

  -- 4. Remove B's originals. Unmap B's port first so its destruction isn't
  --    read as "a docking port was destroyed".
  storage.port_to_pair[pair.port_b_unit] = nil
  for _, e in ipairs(Footprint.entities_in(surface_b, plan.source_tiles, source_set, nil)) do
    if e.valid then e.destroy{ raise_destroy = true } end
  end

  local port_b_clone = surface_a.find_entities_filtered{
    name = "docking-port", position = plan.port_b_new, limit = 1 }[1]
  if port_b_clone then
    pair.port_b_clone_unit = port_b_clone.unit_number
    State.add_port(pair_id, port_b_clone)
  end

  pair.offset         = plan.offset
  pair.corridor_tiles = plan.corridor
  pair.footprint      = plan.footprint
  pair.hub_hole_tiles = plan.hub_hole

  pair.b_paused_before = platform_b.paused
  platform_b.paused = true
  platform_b.hidden = true
  if not settings.global["allow-moving-while-docked"].value then
    pair.a_paused_before = platform_a.paused
    platform_a.paused = true
  end

  pair.state = "docked"
  move_players_to_host(platform_a, platform_b, plan.port_b_new)
  log("[Merger] Pair " .. pair_id .. " docked.")
  notify(pair, { "", { "docking-message.prefix" },
    { "docking-message.docked", platform_a.name, platform_b.name, #clones } })
end

-- ---------------------------------------------------------------------------
-- Unmerge
-- ---------------------------------------------------------------------------

--- Guest platform is gone: whatever was copied onto A now just belongs to A.
---@param pair_id number
local function abandon(pair_id, pair, platform_a)
  if pair.overlay and pair.overlay.valid then pair.overlay.destroy() end
  if platform_a and pair.a_paused_before ~= nil then platform_a.paused = pair.a_paused_before end
  notify(pair, { "", { "docking-message.prefix" }, { "docking-message.guest-lost" } })
  State.remove_pair(pair_id)
end

--- Undock now, or as soon as the host stops if it is in transit.
---@param pair_id number
function Merger.request_undock(pair_id)
  local pair = storage.docked_pairs[pair_id]
  if not pair then return end

  if pair.state == "docking" then
    notify(pair, { "", { "docking-message.prefix" }, { "docking-message.dock-cancelled" } })
    State.remove_pair(pair_id)
    return
  end

  local platform_a = State.get_platform(pair.force_name, pair.platform_a_index)
  if platform_a and not platform_a.space_location then
    if pair.state ~= "undock_pending" then
      pair.state = "undock_pending"
      notify(pair, { "", { "docking-message.prefix" }, { "docking-message.undock-pending" } })
    end
    return
  end
  Merger.execute_unmerge(pair_id)
end

---@param pair_id number
---@param now boolean|nil  run even if the host is in transit (host surface being deleted)
---@return boolean success
function Merger.execute_unmerge(pair_id, now)
  local pair = storage.docked_pairs[pair_id]
  if not pair or not pair.footprint then return false end

  local platform_a, platform_b = State.get_platforms(pair)
  if not platform_a then
    -- Host surface already gone; nothing to copy back.
    log("[Merger] execute_unmerge: host platform missing, guest content lost.")
    if platform_b then
      platform_b.hidden = false
      if pair.b_paused_before ~= nil then platform_b.paused = pair.b_paused_before end
    end
    State.remove_pair(pair_id)
    return false
  end
  if not platform_b then
    abandon(pair_id, pair, platform_a)
    return false
  end
  if not platform_a.space_location and not now then
    Merger.request_undock(pair_id)
    return false
  end

  local surface_a, surface_b = platform_a.surface, platform_b.surface
  local force = pair.force_name
  local footprint     = pair.footprint
  local footprint_set = Footprint.keyset(footprint)
  local back_offset   = { x = -pair.offset.x, y = -pair.offset.y }

  -- 1. B must be where A is before its content goes back.
  sync_location(platform_a, platform_b)

  -- 2. Anything straddling B's footprint edge (corridor, hub hole, A's side)
  --    can't be split between platforms: mine it into A's hub.
  local hub_a = platform_a.hub
  local hub_inv = hub_a and hub_a.valid and hub_a.get_inventory(defines.inventory.hub_main) or nil
  local scan = concat(concat(footprint, pair.corridor_tiles or {}), pair.hub_hole_tiles or {})
  for _, e in ipairs(Footprint.entities_touching(surface_a, scan, Footprint.keyset(scan))) do
    if e.valid and e ~= pair.overlay and e.type ~= "asteroid" then
      local inside = true
      for _, t in ipairs(Footprint.entity_tiles(e)) do
        if not footprint_set[t.x .. "," .. t.y] then inside = false; break end
      end
      if not inside then
        log("[Merger] Mining boundary entity " .. e.name .. " into host hub")
        if hub_inv then e.mine{ inventory = hub_inv, force = true } else e.mine{} end
      end
    end
  end

  -- 3. Clone the footprint back onto B (B still has its own tiles).
  local originals = Footprint.entities_in(surface_a, footprint, footprint_set, force)
  local b_tiles = Footprint.shift(footprint, back_offset)
  local b_set   = Footprint.keyset(b_tiles)
  surface_a.clone_brush{
    source_positions           = footprint,
    source_offset              = { x = 0, y = 0 },
    destination_surface        = surface_b,
    destination_offset         = back_offset,
    destination_force          = force,
    clone_tiles                = false,
    clone_entities             = true,
    clone_decoratives          = false,
    clear_destination_entities = false,
    clear_destination_decoratives = false,
    create_build_effect_smoke  = false,
    expand_map                 = false,
    manual_collision_mode      = false,
  }

  -- 4. Verify before removing anything from A.
  local clones = Footprint.entities_in(surface_b, b_tiles, b_set, force)
  log(string.format("[Merger] Pair %d: restored %d / %d entities to guest", pair_id, #clones, #originals))
  if #clones ~= #originals then
    for _, e in ipairs(clones) do if e.valid then e.destroy() end end
    pair.state = "docked"
    notify(pair, { "", { "docking-message.prefix" },
      { "docking-message.undock-failed", #clones, #originals } })
    return false
  end

  -- 5. Remove B's content from A.
  for _, e in ipairs(Footprint.entities_touching(surface_a, footprint, footprint_set)) do
    if e.valid then e.destroy{ raise_destroy = true } end
  end
  if pair.overlay and pair.overlay.valid then pair.overlay.destroy() end
  Corridor.clear_tiles(surface_a, concat(concat(footprint, pair.hub_hole_tiles or {}), pair.corridor_tiles or {}))

  -- 6. Hand B back.
  platform_b.hidden = false
  if pair.b_paused_before ~= nil then platform_b.paused = pair.b_paused_before end
  if pair.a_paused_before ~= nil then platform_a.paused = pair.a_paused_before end
  move_players_to_guest(surface_a, platform_b, footprint_set, back_offset)

  log("[Merger] Pair " .. pair_id .. " undocked.")
  notify(pair, { "", { "docking-message.prefix" }, { "docking-message.undocked", platform_b.name } })
  State.remove_pair(pair_id)
  return true
end

-- ---------------------------------------------------------------------------
-- Event hooks (called from control.lua)
-- ---------------------------------------------------------------------------

--- A platform in a pair changed state (departed, arrived, paused, ...).
---@param platform LuaSpacePlatform
function Merger.on_platform_state_changed(platform)
  if syncing then return end
  local pair, pair_id = State.get_pair_for_platform(platform)
  if not pair then return end

  if pair.state == "docking" then
    if not platform.space_location then
      notify(pair, { "", { "docking-message.prefix" }, { "docking-message.dock-cancelled" } })
      State.remove_pair(pair_id)
    end
    return
  end

  local platform_a, platform_b = State.get_platforms(pair)
  if not (platform_a and platform_b) then return end

  if platform.index == pair.platform_b_index then
    -- The guest must not go anywhere on its own.
    if not platform_b.paused then platform_b.paused = true end
    sync_location(platform_a, platform_b)
    return
  end

  -- Host.
  if platform_a.space_location then
    if pair.state == "undock_pending" then
      Merger.execute_unmerge(pair_id)
    else
      sync_location(platform_a, platform_b)
    end
  elseif not settings.global["allow-moving-while-docked"].value then
    Merger.request_undock(pair_id)
  end
end

--- A docking port belonging to a pair was destroyed.
---@param unit_number number
function Merger.on_port_destroyed(unit_number)
  local pair_id = storage.port_to_pair[unit_number]
  if not pair_id then return end
  storage.port_to_pair[unit_number] = nil
  Merger.request_undock(pair_id)
end

--- A surface is about to be deleted.
---@param surface LuaSurface
function Merger.on_pre_surface_deleted(surface)
  local platform = surface and surface.platform
  if not platform then return end
  local pair, pair_id = State.get_pair_for_platform(platform)
  if not pair then return end

  if pair.state == "docking" then
    State.remove_pair(pair_id)
  elseif platform.index == pair.platform_a_index then
    Merger.execute_unmerge(pair_id, true)
  else
    abandon(pair_id, pair, State.get_platform(pair.force_name, pair.platform_a_index))
  end
end

return Merger
