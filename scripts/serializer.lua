-- ADD UNDEGROIUND BELT ITEMS IN THE SNAPSHOT (otherwise they get lost in the pipeline when the belt is destroyed and recreated during restore)

local Serializer = {}

local CB_PROPS = {
  "circuit_enable_disable", "circuit_condition",
  "connect_to_logistic_network", "logistic_condition",
  "read_contents", "read_contents_mode",
  "circuit_set_filters", "circuit_read_hand_contents", "circuit_hand_read_mode",
  "circuit_set_stack_size", "circuit_stack_control_signal",
  "read_charge", "output_signal",
  "use_colors", "color_mode",
  "red_signal", "green_signal", "blue_signal", "rgb_signal",
  "circuit_parameters",
  "set_filter",
  "set_input_side",  "input_left_condition",  "input_right_condition",
  "set_output_side", "output_left_condition", "output_right_condition",
  "circuit_read_resources", "resource_read_mode",
  "circuit_set_recipe", "circuit_read_contents", "include_in_crafting",
  "include_fuel", "circuit_read_ingredients",
  "circuit_read_recipe_finished", "circuit_recipe_finished_signal",
  "circuit_read_working", "circuit_working_signal",
  "read_items_mode", "read_logistics", "read_robot_stats",
  "available_logistic_output_signal", "total_logistic_output_signal",
  "available_construction_output_signal", "total_construction_output_signal",
  "roboport_count_output_signal",
  "open_gate", "read_sensor",
  "parameters",
}

local function serialize_cb(cb)
  local t = {}
  for _, key in ipairs(CB_PROPS) do
    local ok, val = pcall(function() return cb[key] end)
    if ok and val ~= nil then t[key] = val end
  end
  return next(t) and t or nil
end

local function restore_cb(cb, t, debug_prefix)
  for key, val in pairs(t) do
    local ok, err = pcall(function() cb[key] = val end)
    if debug_prefix then
      if ok then
        log(debug_prefix .. "  CB set [" .. key .. "] = " .. tostring(val))
      else
        log(debug_prefix .. "  CB FAILED [" .. key .. "]: " .. tostring(err))
      end
    end
  end
end

--- Snapshots all entities and tiles on a platform's surface.
---@param platform LuaSpacePlatform
---@return table|nil snapshot
function Serializer.snapshot_platform(platform)
  if not (platform and platform.valid and platform.surface) then return nil end
  local surface = platform.surface

  local snapshot = {
    entities         = {},
    tiles            = {},
    platform_name    = platform.name,
    hub_unit_number  = platform.hub and platform.hub.unit_number or nil,
  }

  -- Tiles
  for _, tile in ipairs(surface.find_tiles_filtered{}) do
    table.insert(snapshot.tiles, {
      name     = tile.name,
      position = { x = tile.position.x, y = tile.position.y },
    })
  end

  -- Entities (hub handled separately by merger, skip it here)
  for _, entity in ipairs(surface.find_entities_filtered{}) do
    if entity.valid and entity.unit_number
       and entity.unit_number ~= snapshot.hub_unit_number then
      snapshot.entities[entity.unit_number] = Serializer.serialize_entity(entity)
    end
  end

  return snapshot
end

--- Serialises a single entity into a plain, save-safe Lua table.
---@param entity LuaEntity
---@return table
function Serializer.serialize_entity(entity)
  local data = {
    name      = entity.name,
    type      = entity.type,
    position  = { x = entity.position.x, y = entity.position.y },
    direction = entity.direction,
    force     = entity.force.name,
    health    = entity.health,
    quality   = entity.quality and entity.quality.name or "normal",
  }

  data.inventories = {}
  for i = 1, 10 do
    local inv = entity.get_inventory(i)
    if inv then
      data.inventories[i] = inv.get_contents()
    end
  end

  if entity.fluidbox and #entity.fluidbox > 0 then
    data.fluidbox = {}
    for i = 1, #entity.fluidbox do
      local seg_contents = entity.fluidbox.get_fluid_segment_contents(i)
      if seg_contents then
        for fluid_name, amount in pairs(seg_contents) do
          data.fluidbox[i] = { name = fluid_name, amount = amount }
          break
        end
      else
        data.fluidbox[i] = entity.fluidbox[i]
      end
    end
  end

  local belt_entity_types = {
    ["transport-belt"]  = true, ["underground-belt"] = true,
    ["splitter"]        = true, ["linked-belt"]      = true,
    ["loader"]          = true, ["loader-1x1"]       = true,
  }
  if belt_entity_types[entity.type] then
    local transport_lines = {}
    for i = 1, 16 do
      local ok, line = pcall(function() return entity.get_transport_line(i --[[@as defines.transport_line]]) end)
      if not (ok and line and line.valid) then break end
      if #line > 0 then
        local items = {}
        for j = 1, #line do
          local stack = line[j]
          if stack and stack.valid_for_read and stack.count > 0 then
            table.insert(items, {
              name    = stack.name,
              count   = stack.count,
              quality = stack.quality and stack.quality.name or "normal",
            })
          end
        end
        if #items > 0 then
          transport_lines[i] = items
        end
      end
    end
    if next(transport_lines) then
      data.transport_lines = transport_lines
    end
  end

  if entity.energy ~= nil then
    data.energy = entity.energy
  end

  if entity.type == "assembling-machine" then
    local recipe = entity.get_recipe()
    data.recipe = recipe and recipe.name or nil
  end

  if entity.type == "inserter" then
    data.inserter_stack_size_override = entity.inserter_stack_size_override
    data.use_filters                  = entity.use_filters
    data.inserter_filter_mode         = entity.inserter_filter_mode
    if entity.pickup_position then
      data.pickup_position = { x = entity.pickup_position.x, y = entity.pickup_position.y }
    end
    if entity.drop_position then
      data.drop_position = { x = entity.drop_position.x, y = entity.drop_position.y }
    end
    if entity.filter_slot_count and entity.filter_slot_count > 0 then
      data.filters = {}
      for i = 1, entity.filter_slot_count do
        data.filters[i] = entity.get_filter(i)
      end
    end
  end

  if entity.type == "linked-belt" then
    data.link_id          = entity.link_id
    data.linked_belt_type = entity.linked_belt_type
  end

  if entity.type == "underground-belt" then
    data.belt_to_ground_type = entity.belt_to_ground_type
  end

  data.wire_connections = {}
  local connectors = entity.get_wire_connectors and entity.get_wire_connectors(false)
  if connectors then
    for my_cid, connector in pairs(connectors) do
      for _, connection in ipairs(connector.real_connections) do
        local target_connector = connection.target          -- LuaWireConnector
        local target_entity    = target_connector.owner    -- LuaEntity
        if target_entity and target_entity.valid and target_entity.unit_number then
          table.insert(data.wire_connections, {
            my_connector_id     = my_cid,
            target_unit_number  = target_entity.unit_number,
            target_connector_id = target_connector.wire_connector_id,
          })
        end
      end
    end
  end

  if entity.type == "constant-combinator" then
    local cb = entity.get_control_behavior()
    if cb then
      data.constant_combinator_sections = {}
      for i = 1, cb.sections_count do
        local section = cb.get_section(i)
        if section then
          table.insert(data.constant_combinator_sections, {
            group      = section.group,
            active     = section.active,
            multiplier = section.multiplier,
            filters    = section.filters,
          })
        end
      end
    end
  end

  if entity.type ~= "constant-combinator" then
    local cb = entity.get_control_behavior()
    if cb then
      data.control_behavior = serialize_cb(cb)
    end
  end

  return data
end

--- Recreates all entities from a snapshot onto a surface.
--- Returns a mapping of old_unit_number -> new LuaEntity for the caller.
---@param surface LuaSurface
---@param snapshot table
---@param offset table|nil  {x=<int>, y=<int>} added to every position
---@return table unit_number_map
function Serializer.restore_platform(surface, snapshot, offset)
  offset = offset or { x = 0, y = 0 }
  local unit_number_map = {}

  local tiles_to_set = {}
  for _, t in ipairs(snapshot.tiles) do
    table.insert(tiles_to_set, {
      name     = t.name,
      position = { x = t.position.x + offset.x, y = t.position.y + offset.y },
    })
  end
  surface.set_tiles(tiles_to_set)

  local function create_and_restore(old_id, data)
    local new_pos = { x = data.position.x + offset.x, y = data.position.y + offset.y }
    local create_params = {
      name        = data.name,
      position    = new_pos,
      direction   = data.direction,
      force       = data.force,
      quality     = data.quality,
      raise_built = true,
    }
    if data.type == "underground-belt" and data.belt_to_ground_type then
      create_params.type = data.belt_to_ground_type
    end
    local entity = surface.create_entity(create_params)
    if not (entity and entity.valid) then return end

    unit_number_map[old_id] = entity

    if data.health then entity.health = data.health end
    if data.energy ~= nil and entity.energy ~= nil then entity.energy = data.energy end

    if data.inventories then
      for i, contents in pairs(data.inventories) do
        local inv = entity.get_inventory(i)
        if inv then
          for _, item in ipairs(contents) do
            inv.insert({ name = item.name, quality = item.quality, count = item.count })
          end
        end
      end
    end

    if data.recipe and data.type == "assembling-machine" then
      entity.set_recipe(data.recipe)
    end

    if data.type == "inserter" then
      if data.pickup_position then entity.pickup_position = data.pickup_position end
      if data.drop_position   then entity.drop_position   = data.drop_position   end
      if data.inserter_stack_size_override then
        entity.inserter_stack_size_override = data.inserter_stack_size_override
      end
      if data.inserter_filter_mode ~= nil then
        entity.inserter_filter_mode = data.inserter_filter_mode
      end
      if data.filters then
        for i, filter in pairs(data.filters) do entity.set_filter(i, filter) end
      end
      if data.use_filters ~= nil then entity.use_filters = data.use_filters end
    end

    if data.type == "linked-belt" and data.link_id then
      entity.link_id = data.link_id
    end

    if data.constant_combinator_sections then
      local cb = entity.get_control_behavior()
      if cb then
        for i, sec_data in ipairs(data.constant_combinator_sections) do
          local section = cb.get_section(i) or cb.add_section()
          if section then
            if sec_data.group      ~= nil then section.group      = sec_data.group      end
            if sec_data.active     ~= nil then section.active     = sec_data.active     end
            if sec_data.multiplier ~= nil then section.multiplier = sec_data.multiplier end
            if sec_data.filters then
              for j, filter in ipairs(sec_data.filters) do section.set_slot(j, filter) end
            end
          end
        end
      end
    end

    if data.control_behavior then
      local cb = entity.get_or_create_control_behavior()
      if cb then restore_cb(cb, data.control_behavior) end
    end
  end

  for old_id, data in pairs(snapshot.entities) do
    create_and_restore(old_id, data)
  end

  for old_id, data in pairs(snapshot.entities) do
    local entity = unit_number_map[old_id]
    if not (entity and entity.valid and data.fluidbox) then goto continue_fluid end

    for i, fluid in pairs(data.fluidbox) do
      if fluid then
        entity.fluidbox[i] = fluid
      end
    end
    ::continue_fluid::
  end

  for old_id, data in pairs(snapshot.entities) do
    local new_entity = unit_number_map[old_id]
    if new_entity and new_entity.valid and data.wire_connections then
      for _, conn in ipairs(data.wire_connections) do
        local target_entity = unit_number_map[conn.target_unit_number]
        if target_entity and target_entity.valid then
          local my_connector =
            new_entity.get_wire_connector(conn.my_connector_id, true)
          local target_connector =
            target_entity.get_wire_connector(conn.target_connector_id, true)
          if my_connector and target_connector then
            my_connector.connect_to(target_connector, false)
          end
        end
      end
    end
  end

  for old_id, data in pairs(snapshot.entities) do
    local entity = unit_number_map[old_id]
    if not (entity and entity.valid and data.transport_lines) then goto continue_tl end

    for i, items in pairs(data.transport_lines) do
      local ok, line = pcall(function() return entity.get_transport_line(i --[[@as defines.transport_line]]) end)
      if ok and line and line.valid then
        local total = #items
        for j, item in ipairs(items) do
          local position = (2 * j - 1) / (2 * total)
          pcall(function()
            line.insert_at(position,
              { name = item.name, count = item.count, quality = item.quality },
              item.count)
          end)
        end
      end
    end
    ::continue_tl::
  end

  return unit_number_map
end


--- Verbose roundtrip test. Prints every snapshot value and every restore action.
--- /c remote.call("platform-docking", "test_serializer", game.forces["player"].platforms[1])
---@param platform LuaSpacePlatform
function Serializer.test_roundtrip(platform)
  if not (platform and platform.valid) then
    log("[Serializer] No valid platform provided.")
    return
  end
  local surface = platform.surface
  local p = "[SER] "
  log(p .. "=== ROUNDTRIP START: " .. platform.name .. " ===")

  -- ---- SNAPSHOT ----
  local snapshot = Serializer.snapshot_platform(platform)
  if not snapshot then log(p .. "Snapshot FAILED.") return end

  log(p .. "Snapshot: " .. (function()
    local n = 0; for _ in pairs(snapshot.entities) do n = n + 1 end; return n
  end)() .. " entities, " .. #snapshot.tiles .. " tiles.")

  for uid, data in pairs(snapshot.entities) do
    local prefix = p .. "[" .. data.name .. " #" .. uid .. "] "
    log(prefix .. "type=" .. data.type
      .. " pos=(" .. data.position.x .. "," .. data.position.y .. ")"
      .. " dir=" .. data.direction
      .. " quality=" .. (data.quality or "?"))

    -- Inventories
    for i, contents in pairs(data.inventories or {}) do
      if #contents > 0 then
        local items = {}
        for _, item in ipairs(contents) do
          table.insert(items, item.name .. "x" .. item.count)
        end
        log(prefix .. "  inv[" .. i .. "]: " .. table.concat(items, ", "))
      end
    end

    -- Fluidboxes
    for i, fluid in pairs(data.fluidbox or {}) do
      if fluid then
        log(prefix .. "  fluid[" .. i .. "]: " .. tostring(fluid.name)
          .. " amt=" .. tostring(fluid.amount))
      end
    end

    -- Recipe
    if data.recipe then
      log(prefix .. "  recipe=" .. data.recipe)
    end

    -- Inserter
    if data.type == "inserter" then
      log(prefix .. "  use_filters=" .. tostring(data.use_filters)
        .. " filter_mode=" .. tostring(data.inserter_filter_mode))
      for i, f in pairs(data.filters or {}) do
        log(prefix .. "  filter[" .. i .. "]=" .. tostring(f and f.name))
      end
    end

    -- CB
    if data.control_behavior then
      local parts = {}
      for k, v in pairs(data.control_behavior) do
        table.insert(parts, k .. "=" .. tostring(v))
      end
      log(prefix .. "  CB: " .. table.concat(parts, " | "))
    end
    if data.constant_combinator_sections then
      log(prefix .. "  CC sections=" .. #data.constant_combinator_sections)
    end

    -- Wires
    if data.wire_connections and #data.wire_connections > 0 then
      local wires = {}
      for _, w in ipairs(data.wire_connections) do
        table.insert(wires, "cid=" .. tostring(w.my_connector_id)
          .. "->uid=" .. tostring(w.target_unit_number)
          .. " cid=" .. tostring(w.target_connector_id))
      end
      log(prefix .. "  WIRES: " .. table.concat(wires, " | "))
    end

    -- Transport lines
    if data.transport_lines then
      for i, items in pairs(data.transport_lines) do
        local parts = {}
        for _, item in ipairs(items) do
          table.insert(parts, item.name .. "x" .. item.count
            .. (item.quality ~= "normal" and ("[" .. item.quality .. "]") or ""))
        end
        log(prefix .. "  transport_line[" .. i .. "]: " .. table.concat(parts, ", "))
      end
    end
  end

  -- ---- DESTROY ----
  log(p .. "--- Destroying entities ---")
  for _, e in ipairs(surface.find_entities_filtered{}) do
    if e.valid and e.unit_number ~= snapshot.hub_unit_number then
      log(p .. "  Destroying " .. e.name .. " #" .. tostring(e.unit_number))
      e.destroy({ raise_destroy = true })
    end
  end

  -- ---- RESTORE (verbose) ----
  log(p .. "--- Restoring ---")
  local offset = { x = 0, y = 0 }
  local unit_number_map = {}

  -- Tiles
  local tiles_to_set = {}
  for _, t in ipairs(snapshot.tiles) do
    table.insert(tiles_to_set, { name = t.name,
      position = { x = t.position.x + offset.x, y = t.position.y + offset.y } })
  end
  surface.set_tiles(tiles_to_set)
  log(p .. "  Tiles restored: " .. #tiles_to_set)

  -- First pass: create + restore properties
  for old_id, data in pairs(snapshot.entities) do
    local new_pos = { x = data.position.x + offset.x, y = data.position.y + offset.y }
    local prefix = p .. "[" .. data.name .. " #" .. old_id .. "] "
    local create_params = {
      name = data.name, position = new_pos, direction = data.direction,
      force = data.force, quality = data.quality, raise_built = true,
    }
    if data.type == "underground-belt" and data.belt_to_ground_type then
      create_params.type = data.belt_to_ground_type
    end
    local entity = surface.create_entity(create_params)
    if not (entity and entity.valid) then
      log(prefix .. "CREATE FAILED")
    else
      log(prefix .. "created -> new #" .. tostring(entity.unit_number))
      unit_number_map[old_id] = entity

      if data.health then entity.health = data.health end
      if data.energy ~= nil and entity.energy ~= nil then entity.energy = data.energy end

      -- Inventories
      for i, contents in pairs(data.inventories or {}) do
        local inv = entity.get_inventory(i)
        if inv then
          for _, item in ipairs(contents) do
            local inserted = inv.insert({ name = item.name, quality = item.quality, count = item.count })
            if inserted < item.count then
              log(prefix .. "  inv[" .. i .. "] partial insert " .. item.name
                .. " wanted=" .. item.count .. " got=" .. inserted)
            end
          end
        else
          log(prefix .. "  inv[" .. i .. "] slot missing on new entity")
        end
      end

      -- Recipe
      if data.recipe and data.type == "assembling-machine" then
        local ok, err = pcall(function() entity.set_recipe(data.recipe) end)
        if not ok then log(prefix .. "  recipe FAILED: " .. tostring(err)) end
      end

      -- Inserter
      if data.type == "inserter" then
        if data.pickup_position then entity.pickup_position = data.pickup_position end
        if data.drop_position   then entity.drop_position   = data.drop_position   end
        if data.inserter_stack_size_override then
          entity.inserter_stack_size_override = data.inserter_stack_size_override
        end
        if data.inserter_filter_mode ~= nil then entity.inserter_filter_mode = data.inserter_filter_mode end
        for i, filter in pairs(data.filters or {}) do entity.set_filter(i, filter) end
        if data.use_filters ~= nil then entity.use_filters = data.use_filters end
      end

      -- Linked belt
      if data.type == "linked-belt" and data.link_id then entity.link_id = data.link_id end

      -- Constant combinator sections
      if data.constant_combinator_sections then
        local cb = entity.get_control_behavior()
        if cb then
          for i, sec_data in ipairs(data.constant_combinator_sections) do
            local section = cb.get_section(i) or cb.add_section()
            if section then
              if sec_data.group      ~= nil then section.group      = sec_data.group      end
              if sec_data.active     ~= nil then section.active     = sec_data.active     end
              if sec_data.multiplier ~= nil then section.multiplier = sec_data.multiplier end
              for j, filter in ipairs(sec_data.filters or {}) do section.set_slot(j, filter) end
            end
          end
          log(prefix .. "  CC sections restored: " .. #data.constant_combinator_sections)
        else
          log(prefix .. "  CC: get_control_behavior() returned nil")
        end
      end

      -- Generic CB (all other types)
      if data.control_behavior then
        local cb = entity.get_or_create_control_behavior()
        if cb then
          restore_cb(cb, data.control_behavior, prefix)
        else
          log(prefix .. "  CB: get_or_create_control_behavior() returned nil")
        end
      end
    end
  end

  -- Second pass: restore fluid (same reason as restore_platform — thrusters drain
  -- the pipeline synchronously at creation if the tank is already full)
  log(p .. "--- Restoring fluid ---")
  for old_id, data in pairs(snapshot.entities) do
    local entity = unit_number_map[old_id]
    if entity and entity.valid and data.fluidbox then
      for i, fluid in pairs(data.fluidbox) do
        log("trying to restore [" .. data.name .. " #" .. old_id .. "] fluid[" .. i .. ":" .. (fluid and fluid.name or "nil") .. "] = "
          .. tostring(fluid and fluid.name) .. " x" .. tostring(fluid and fluid.amount))
        local ok, err = pcall(function() entity.fluidbox[i] = { name = fluid.name, amount = fluid.amount } end)
        if ok then
          log("[SER] [" .. data.name .. " #" .. old_id .. "]  fluid[" .. i .. "] restored: "
            .. tostring(fluid and fluid.name) .. " x" .. tostring(fluid and fluid.amount))
        else
          log("[SER] [" .. data.name .. " #" .. old_id .. "]  fluid[" .. i .. "] FAILED: " .. tostring(err))
        end
      end
    end
  end

  -- Third pass: wire connections
  log(p .. "--- Wiring ---")
  for old_id, data in pairs(snapshot.entities) do
    local new_entity = unit_number_map[old_id]
    if new_entity and new_entity.valid and data.wire_connections then
      for _, conn in ipairs(data.wire_connections) do
        local target_entity = unit_number_map[conn.target_unit_number]
        if target_entity and target_entity.valid then
          local my_con  = new_entity.get_wire_connector(conn.my_connector_id, true)
          local tgt_con = target_entity.get_wire_connector(conn.target_connector_id, true)
          if my_con and tgt_con then
            local ok, err = pcall(function() my_con.connect_to(tgt_con, false) end)
            if ok then
              log(p .. "  Wire: #" .. old_id .. " cid=" .. tostring(conn.my_connector_id)
                .. " -> #" .. conn.target_unit_number .. " cid=" .. tostring(conn.target_connector_id) .. " OK")
            else
              log(p .. "  Wire FAILED: " .. tostring(err))
            end
          else
            log(p .. "  Wire: connector missing for #" .. old_id
              .. " my_con=" .. tostring(my_con ~= nil)
              .. " tgt_con=" .. tostring(tgt_con ~= nil))
          end
        else
          log(p .. "  Wire: target #" .. conn.target_unit_number .. " not in map")
        end
      end
    end
  end

  -- Fourth pass: transport lines (items on belts)
  log(p .. "--- Restoring belt items ---")
  for old_id, data in pairs(snapshot.entities) do
    local entity = unit_number_map[old_id]
    if not (entity and entity.valid and data.transport_lines) then goto continue_tl end

    local prefix = p .. "[" .. data.name .. " #" .. old_id .. "] "
    for i, items in pairs(data.transport_lines) do
      local ok, line = pcall(function() return entity.get_transport_line(i --[[@as defines.transport_line]]) end)
      if ok and line and line.valid then
        local total = #items
        for j, item in ipairs(items) do
          local position = (2 * j - 1) / (2 * total)
          local ins_ok, ins_err = pcall(function()
            line.insert_at(position,
              { name = item.name, count = item.count, quality = item.quality },
              item.count)
          end)
          if ins_ok then
            log(prefix .. "  transport_line[" .. i .. "] @" .. string.format("%.3f", position)
              .. " inserted " .. item.name .. "x" .. item.count)
          else
            log(prefix .. "  transport_line[" .. i .. "] @" .. string.format("%.3f", position)
              .. " FAILED " .. item.name .. ": " .. tostring(ins_err))
          end
        end
      else
        log(prefix .. "  transport_line[" .. i .. "] get_transport_line FAILED")
      end
    end
    ::continue_tl::
  end

  log(p .. "=== ROUNDTRIP COMPLETE ===")
end

return Serializer
