-- Hidden carrier: a plain "car" that exists only to host an
-- equipment_grid for combat mode's auto-fire weapons. Never driven or
-- player-visible; teleported to match the real vehicle's position every
-- tick while combat mode is active, and destroyed when it ends.
data:extend({
  {
    type = "equipment-grid",
    name = "mega-mech-armor-combat-carrier-grid",
    -- Comfortably more cells than the laser + tesla equipment need.
    width = 10,
    height = 10,
    equipment_categories = {"mega-mech-armor-combat-mode"},
  },
  {
    type = "car",
    name = "mega-mech-armor-combat-carrier",
    -- Movement-physics fields below are nominal placeholders -- this
    -- entity is teleported by script, never actually driven.
    collision_box = {{0, 0}, {0, 0}},
    collision_mask = {layers = {}},
    flags = {"not-selectable-in-game", "placeable-off-grid", "not-on-map"},
    is_military_target = true,
    weight = 1,
    braking_force = 1,
    friction_force = 1,
    energy_per_hit_point = 1,
    consumption = "1W",
    effectivity = 1,
    energy_source = {type = "void"},
    inventory_size = 0,
    rotation_snap_angle = 0,
    rotation_speed = 0,
    max_health = 10,
    equipment_grid = "mega-mech-armor-combat-carrier-grid",
  },
})
