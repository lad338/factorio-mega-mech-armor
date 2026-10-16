-- 11x13 base size. Quality grows this automatically (engine default:
-- +level to each dimension), so the real per-tier sizes are 12x14,
-- 13x15, 14x16, 16x18 -- no control.lua enforcement needed.
data:extend({
  {
    type = "equipment-grid",
    name = "mega-mech-armor-equipment-grid",
    width = 11,
    height = 13,
    equipment_categories = {"armor"},
  },
})
