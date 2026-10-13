-- Normal-quality base size, 11x13. Grows with quality automatically
-- via QualityPrototype's equipment_grid_width_bonus/height_bonus
-- (both default to the quality's own `level` -- uncommon=1, rare=2,
-- epic=3, legendary=5 -- applied for free to every grid-bearing
-- entity in the game), so at 11x13 the real per-tier sizes become
-- 12x14, 13x15, 14x16, and 16x18. No extra control.lua enforcement --
-- the earlier version of this grid had custom per-tier target sizes
-- trimmed down at runtime; that's been dropped in favor of just
-- accepting whatever the engine's own default growth produces.
data:extend({
  {
    type = "equipment-grid",
    name = "mega-mech-armor-equipment-grid",
    width = 11,
    height = 13,
    equipment_categories = {"armor"},
  },
})
