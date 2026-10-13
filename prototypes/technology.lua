-- "personal fusion reactor" from the proposal is fusion-reactor-equipment
-- (the equipment-grid-mounted personal version) -- there is no tech
-- literally named personal-fusion-reactor. Confirmed in
-- __space-age__/prototypes/technology.lua.
data:extend({
  {
    type = "technology",
    name = "mega-mech-armor",
    icon = "__space-age__/graphics/technology/mech-armor.png",
    icon_size = 256,
    effects = {
      {type = "unlock-recipe", recipe = "mega-mech-armor"},
    },
    prerequisites = {"fusion-reactor-equipment", "mech-armor", "railgun", "tesla-weapons"},
    unit = {
      count = 10000,
      ingredients = {
        {"automation-science-pack", 1},
        {"logistic-science-pack", 1},
        {"chemical-science-pack", 1},
        {"production-science-pack", 1},
        {"utility-science-pack", 1},
        {"space-science-pack", 1},
        {"metallurgic-science-pack", 1},
        {"agricultural-science-pack", 1},
        {"electromagnetic-science-pack", 1},
        {"cryogenic-science-pack", 1},
      },
      time = 60,
    },
  },
})
