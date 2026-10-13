-- data.lua
-- Prototype definitions for the Platform Docking mod.
-- Runs once at game startup. Requires a full game restart to reload.

-- ---------------------------------------------------------------------------
-- Helper: reuse a base-game sprite as a placeholder icon
-- ---------------------------------------------------------------------------
local placeholder_icon = "__base__/graphics/icons/blueprint.png"
local placeholder_icon_size = 64

-- ---------------------------------------------------------------------------
-- 1. Docking Port item
-- ---------------------------------------------------------------------------
local docking_port_item = {
  type = "item",
  name = "docking-port",
  icon = placeholder_icon,
  icon_size = placeholder_icon_size,
  subgroup = "other",
  order = "z[docking-port]",
  place_result = "docking-port",
  stack_size = 10,
}

-- ---------------------------------------------------------------------------
-- 2. Docking Port entity (container, 1×1, inventory size 0)
-- ---------------------------------------------------------------------------
-- constant-combinator: rotatable (4-way), fires on_gui_opened, no energy/fluid/crafting.
-- item_slot_count = 0 means no signals — vanilla GUI will be empty.
-- Borrow required LED/wire fields from the base game's own constant-combinator
-- so we don't have to hardcode offsets. Sprites replaced with proper art in Step 5.
local _base_cc = data.raw["constant-combinator"]["constant-combinator"]
local _sp = {
  filename = "__base__/graphics/entity/lab/lab.png",
  width = 174, height = 174, scale = 0.37,
}
local docking_port_entity = {
  type = "constant-combinator",
  name = "docking-port",
  icon = placeholder_icon,
  icon_size = placeholder_icon_size,
  -- get-by-unit-number lets scripts resolve ports with game.get_entity_by_unit_number.
  flags = { "placeable-neutral", "player-creation", "get-by-unit-number" },
  minable = { mining_time = 0.5, result = "docking-port" },
  max_health = 200,
  corpse = "small-remnants",
  collision_box = { { -0.4, -0.4 }, { 0.4, 0.4 } },
  selection_box = { { -0.5, -0.5 }, { 0.5, 0.5 } },
  item_slot_count = 0,
  sprites = { north = _sp, east = _sp, south = _sp, west = _sp },
  activity_led_sprite          = _base_cc.activity_led_sprite,
  activity_led_light           = _base_cc.activity_led_light,
  activity_led_light_offsets   = _base_cc.activity_led_light_offsets,
  circuit_wire_connection_points = _base_cc.circuit_wire_connection_points,
  -- Placement: on platform floor, with the docking face (north when unrotated)
  -- over empty space — same layers the asteroid collector uses. The front rule
  -- must not remove the port later, because docking lays bridge tiles there.
  tile_buildability_rules = {
    { area = { { -0.4, -0.4 }, { 0.4, 0.4 } },
      required_tiles = { layers = { ground_tile = true } },
      colliding_tiles = { layers = { empty_space = true } },
      remove_on_collision = true },
    { area = { { -0.4, -1.4 }, { 0.4, -0.6 } },
      required_tiles = { layers = { empty_space = true } },
      colliding_tiles = { layers = {} },
      remove_on_collision = false },
  },
  circuit_wire_max_distance = 9,
}

-- ---------------------------------------------------------------------------
-- 3. Corridor tile  (platform-docking-corridor)
-- Derived from space-platform-foundation visually; same walkability.
-- ---------------------------------------------------------------------------
local foundation = data.raw["tile"]["space-platform-foundation"]

local corridor_tile = {
  type = "tile",
  name = "platform-docking-corridor",
  collision_mask = foundation and foundation.collision_mask or { layers = { ground_tile = true } },
  walking_speed_modifier = 1.0,
  layer = foundation and (foundation.layer or 60) or 60,
  variants = foundation and foundation.variants or {
    main = {
      {
        picture = "__space-age__/graphics/terrain/space-platform/space-platform-foundation-1.png",
        count = 1,
        size = 1,
      },
    },
    inner_corner = {
      picture = "__space-age__/graphics/terrain/space-platform/space-platform-foundation-1.png",
      count = 1,
    },
    outer_corner = {
      picture = "__space-age__/graphics/terrain/space-platform/space-platform-foundation-1.png",
      count = 1,
    },
    side = {
      picture = "__space-age__/graphics/terrain/space-platform/space-platform-foundation-1.png",
      count = 1,
    },
    u_transition = {
      picture = "__space-age__/graphics/terrain/space-platform/space-platform-foundation-1.png",
      count = 1,
    },
    o_transition = {
      picture = "__space-age__/graphics/terrain/space-platform/space-platform-foundation-1.png",
      count = 1,
    },
  },
  map_color = { r = 0.4, g = 0.6, b = 0.9 },  -- subtle blue tint to distinguish from normal
  ageing = 0,
  autoplace = nil,
}

-- ---------------------------------------------------------------------------
-- 4. Hub overlay entity (platform-docking-hub-overlay)
-- Purely visual — marks where Platform B's hub sits in B's layout while docked
-- (the real hub stays on B's own surface). Created/destroyed by scripts/merger.lua.
-- ---------------------------------------------------------------------------
local hub_overlay_entity = {
  type = "simple-entity",
  name = "platform-docking-hub-overlay",
  icon = placeholder_icon,
  icon_size = placeholder_icon_size,
  flags = { "not-blueprintable", "not-deconstructable" },
  collision_mask = { layers = {} },  -- no collision
  collision_box = { { 0, 0 }, { 0, 0 } },
  selection_box = { { -1, -1 }, { 1, 1 } },
  selectable_in_game = false,
  picture = {
    filename = "__base__/graphics/icons/blueprint.png",
    width = 64,
    height = 64,
    scale = 2,
    tint = { r = 0.3, g = 0.5, b = 1.0, a = 0.7 },
  },
  render_layer = "object",
}

-- ---------------------------------------------------------------------------
-- 5. Recipe
-- ---------------------------------------------------------------------------
local docking_port_recipe = {
  type = "recipe",
  name = "docking-port",
  enabled = false,  -- unlocked by technology
  energy_required = 10,
  ingredients = {
    { type = "item", name = "iron-plate",        amount = 20 },
    { type = "item", name = "steel-plate",       amount = 10 },
    { type = "item", name = "advanced-circuit",  amount = 5  },
  },
  results = {
    { type = "item", name = "docking-port", amount = 1 },
  },
}

-- ---------------------------------------------------------------------------
-- 6. Technology
-- ---------------------------------------------------------------------------
local docking_technology = {
  type = "technology",
  name = "platform-docking",
  icon = placeholder_icon,
  icon_size = placeholder_icon_size,
  prerequisites = { "space-platform" },
  unit = {
    count = 50,
    ingredients = {
      { "space-science-pack", 1 },
    },
    time = 30,
  },
  effects = {
    { type = "unlock-recipe", recipe = "docking-port" },
  },
}

-- Carrier Clamps: one host may hold several guests, and guests can launch
-- while the host is in flight. Both are scripted, hence "nothing" effects.
-- Costs are placeholders until the balance pass.
local carrier_technology = {
  type = "technology",
  name = "platform-docking-carrier",
  icon = placeholder_icon,
  icon_size = placeholder_icon_size,
  prerequisites = { "platform-docking" },
  unit = {
    count = 500,
    ingredients = {
      { "automation-science-pack", 1 },
      { "logistic-science-pack", 1 },
      { "chemical-science-pack", 1 },
      { "space-science-pack", 1 },
    },
    time = 30,
  },
  effects = {
    { type = "nothing", effect_description = { "modifier-description.platform-docking-multi-guest" } },
    { type = "nothing", effect_description = { "modifier-description.platform-docking-launch" } },
  },
}

-- ---------------------------------------------------------------------------
-- Register all prototypes
-- ---------------------------------------------------------------------------
data:extend({
  docking_port_item,
  docking_port_entity,
  corridor_tile,
  hub_overlay_entity,
  docking_port_recipe,
  docking_technology,
  carrier_technology,
})
