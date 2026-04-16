-- scripts/linker.lua
-- Cross-corridor belt and pipe connections.
-- Step 4 stub — functions are no-ops until implemented.
--
-- connect_corridor(pair, surface_a)
--   Called after B's entities are recreated on A's surface.
--   Creates linked belts / underground pipe stubs across the corridor gap.
--
-- disconnect_corridor(pair, surface_a)
--   Called before B's entities are destroyed during unmerge.
--   Destroys linked belt / pipe entities and salvages any items on them.

local Linker = {}

---@param pair table        docked pair record
---@param surface_a LuaSurface  platform A's surface
function Linker.connect_corridor(pair, surface_a)
  -- TODO (Step 4): scan for belts/pipes at the A-side and B-side edges of the
  -- corridor and create linked-belt or underground-pipe stubs to bridge the gap.
  log("[Linker] connect_corridor: not yet implemented.")
end

---@param pair table        docked pair record
---@param surface_a LuaSurface  platform A's surface
function Linker.disconnect_corridor(pair, surface_a)
  -- TODO (Step 4): destroy linked belt / pipe stubs stored in
  -- pair.linked_belt_pairs and pair.linked_pipe_pairs.
  -- Move any items on linked belts to the nearest hub to prevent item loss.
  log("[Linker] disconnect_corridor: not yet implemented.")
end

return Linker
