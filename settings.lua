-- Runtime-global so these take effect immediately without a save restart.
data:extend({
  {
    type = "bool-setting",
    name = "mega-mech-armor-combat-mode-available",
    setting_type = "runtime-global",
    default_value = true,
    order = "a",
  },
  {
    type = "int-setting",
    name = "mega-mech-armor-combat-mode-laser-count",
    setting_type = "runtime-global",
    default_value = 5,
    minimum_value = 1,
    order = "b",
  },
})
