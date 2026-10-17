-- Restricts combat-mode equipment to the hidden carrier's own grid,
-- never the player's armor or the real vehicle's grid.
data:extend({
  {
    type = "equipment-category",
    name = "mega-mech-armor-combat-mode",
  },
})
