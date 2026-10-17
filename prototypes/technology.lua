-- fusion-reactor-equipment is the personal (equipment-grid-mounted) fusion
-- reactor tech -- there is no tech named personal-fusion-reactor.
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
