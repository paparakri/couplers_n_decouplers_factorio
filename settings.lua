-- settings.lua
-- Mod settings for Platform Docking. All settings are map-level (per-save).

data:extend({
  {
    type = "int-setting",
    name = "docking-transfer-rate",
    setting_type = "runtime-global",
    default_value = 10,
    minimum_value = 1,
    maximum_value = 1000,
    order = "a",
  },
  {
    type = "int-setting",
    name = "docking-animation-ticks",
    setting_type = "runtime-global",
    default_value = 120,
    minimum_value = 1,
    maximum_value = 3600,
    order = "b",
  },
  {
    type = "bool-setting",
    name = "allow-moving-while-docked",
    setting_type = "runtime-global",
    default_value = false,
    order = "c",
  },
  {
    type = "int-setting",
    name = "max-corridor-length",
    setting_type = "runtime-global",
    default_value = 5,
    minimum_value = 1,
    maximum_value = 20,
    order = "d",
  },
})
