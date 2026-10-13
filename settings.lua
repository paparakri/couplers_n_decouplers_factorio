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
    default_value = true,
    order = "c",
  },
  {
    type = "int-setting",
    name = "docking-corridor-length",
    setting_type = "runtime-global",
    default_value = 6,
    minimum_value = 1,
    maximum_value = 10,
    order = "d",
  },
  {
    type = "int-setting",
    name = "docking-corridor-width",
    setting_type = "runtime-global",
    default_value = 1,
    minimum_value = 1,
    maximum_value = 9,
    order = "e",
  },
})
