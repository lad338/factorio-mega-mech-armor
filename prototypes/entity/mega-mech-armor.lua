local torso_animation = require("prototypes.entity.mega-mech-armor-animations")

local VEHICLE_SCALE = 2.5

-- Dedicated icon, not the personal mech-armor's own
-- (__space-age__/graphics/icons/mech-armor.png) -- sharing it confused
-- the personal equipment with this vehicle in inventories/crafting menus.
local ICON = "__mega-mech-armor__/graphics/entity/mega-mech-armor/mega-mech-armor-icon.png"
local ICON_SIZE = 64

-- +5 percentage points to every resistance type, read live off vanilla
-- spidertron's own resistances so a future rebalance can't desync ours.
local resistances = {}
for _, r in pairs(data.raw["spider-vehicle"].spidertron.resistances) do
  resistances[#resistances + 1] = {
    type = r.type,
    decrease = r.decrease,
    percent = r.percent + 5,
  }
end

-- Spidertron's base health (3000) + half of tank's (2000) = 4000.
-- Quality scales this automatically, like every entity's max_health.
local BASE_HEALTH = 3000 + (2000 / 2)

-- Spidertron's trunk (80) + mech armor's own inventory_size_bonus (50).
local BASE_INVENTORY_SIZE = 80 + 50

local function out_of_map_layer_name()
  for _, candidate in pairs({"out-of-map", "out_of_map"}) do
    if data.raw["collision-layer"][candidate] then
      return candidate
    end
  end
  data:extend({{type = "collision-layer", name = "out-of-map"}})
  return "out-of-map"
end

data:extend({
  {
    type = "spider-vehicle",
    name = "mega-mech-armor",
    icon = ICON,
    icon_size = ICON_SIZE,
    collision_box = {{-1 * VEHICLE_SCALE, -1 * VEHICLE_SCALE}, {1 * VEHICLE_SCALE, 1 * VEHICLE_SCALE}},
    selection_box = {{-1 * VEHICLE_SCALE, -1 * VEHICLE_SCALE}, {1 * VEHICLE_SCALE, 1 * VEHICLE_SCALE}},
    -- Half of collision_box: the torso sprite sits in the middle of the
    -- much larger collision/selection area (the full leg-reach footprint,
    -- not the visible armor), so stickers should scope to the torso only.
    sticker_box = {{-0.5 * VEHICLE_SCALE, -0.5 * VEHICLE_SCALE}, {0.5 * VEHICLE_SCALE, 0.5 * VEHICLE_SCALE}},
    drawing_box_vertical_extension = 3 * VEHICLE_SCALE,
    mined_sound = {filename = "__core__/sound/deconstruct-large.ogg", volume = 0.8},
    open_sound = {filename = "__base__/sound/spidertron/spidertron-door-open.ogg", volume = 0.45},
    close_sound = {filename = "__base__/sound/spidertron/spidertron-door-close.ogg", volume = 0.4},
    weight = 1,
    braking_force = 1,
    friction_force = 1,
    flags = {"placeable-neutral", "player-creation", "placeable-off-grid"},
    minable = {mining_time = 1, result = "mega-mech-armor"},
    max_health = BASE_HEALTH,
    resistances = resistances,
    -- spider-vehicle has no built-in map-triangle fallback (unlike
    -- car/tank, where it's hardcoded into the engine's rendering), so a
    -- minimap icon is required here or nothing shows on the map at all.
    minimap_representation = {
      filename = "__mega-mech-armor__/graphics/entity/mega-mech-armor/mega-mech-armor-map.png",
      flags = {"icon"},
      size = {64, 64},
    },
    selected_minimap_representation = {
      filename = "__mega-mech-armor__/graphics/entity/mega-mech-armor/mega-mech-armor-map.png",
      flags = {"icon"},
      size = {64, 64},
    },
    corpse = "spidertron-remnants",
    dying_explosion = "spidertron-explosion",
    energy_per_hit_point = 1,
    -- Cloned in data-final-fixes.lua. Referencing them here before they
    -- exist is fine -- cross-prototype references are validated only
    -- after every mod's whole data stage has run.
    guns = {
      "mega-mech-armor-cannon",
      "mega-mech-armor-machine-gun",
      "mega-mech-armor-flamethrower",
      "mega-mech-armor-rocket-launcher-1",
      "mega-mech-armor-rocket-launcher-2",
      "mega-mech-armor-tesla-gun",
      "mega-mech-armor-railgun",
    },
    inventory_size = BASE_INVENTORY_SIZE,
    equipment_grid = "mega-mech-armor-equipment-grid",
    trash_inventory_size = 20,
    height = 1.5 * VEHICLE_SCALE,
    -- Vanilla spidertron uses 0.005, fine for 5-legged walking but
    -- sluggish on a flying, single-leg vehicle.
    torso_rotation_speed = 0.2,
    chunk_exploration_radius = 3,
    selection_priority = 60,
    graphics_set = {
      animation = torso_animation,
    },
    energy_source = {type = "void"},
    movement_energy_consumption = "250kW",
    -- Both required on spider-vehicle (no default). No chain shooting;
    -- chain_shooting_cooldown_modifier is inert when cycling is false.
    automatic_weapon_cycling = false,
    chain_shooting_cooldown_modifier = 1,
    spider_engine = {
      legs = {
        {
          leg = "mega-mech-armor-leg",
          mount_position = {0, 0},
          ground_position = {0, 0},
          walking_group = 1,
        },
      },
      military_target = "spidertron-military-target",
    },
    is_military_target = true,
    allow_remote_driving = true,
    -- Full flight: no terrain collides with this vehicle at all.
    collision_mask = {layers = {}},
    -- Same restriction as vanilla spidertron: not space-rated, despite flying.
    surface_conditions = {
      {
        property = "gravity",
        min = 1,
      },
    },
  },
  {
    type = "spider-leg",
    name = "mega-mech-armor-leg",
    localised_name = {"entity-name.mega-mech-armor"},
    collision_box = {{-0.1, -0.1}, {0.1, 0.1}},
    selection_box = {{-0.5, -0.5}, {0.5, 0.5}},
    icon = ICON,
    icon_size = ICON_SIZE,
    -- Invisible, centered, single leg -- no graphics_set at all, and
    -- the leg still collides with nothing except the map edge (added
    -- below) so the torso can fly anywhere.
    collision_mask = {layers = {}},
    target_position_randomisation_distance = 0.25,
    minimal_step_size = 0, -- prevents the single leg "rolling back" after moving
    stretch_force_scalar = 1,
    knee_height = 2.5,
    knee_distance_factor = 0.4,
    initial_movement_speed = 100,
    movement_acceleration = 100,
    max_health = 100,
    base_position_selection_distance = 6,
    movement_based_position_selection_distance = 4,
    selectable_in_game = false,
    alert_when_damaged = false,
    walking_sound_volume_modifier = 0,
    walking_sound_speed_modifier = 1,
  },
  {
    type = "item-with-entity-data",
    name = "mega-mech-armor",
    icon = ICON,
    icon_size = ICON_SIZE,
    subgroup = "transport",
    order = "b[personal-transport]-d[mega-mech-armor]",
    place_result = "mega-mech-armor",
    -- Matches the rocket silo's default lift_weight exactly, same as
    -- vanilla spidertron/tank: caps it to 1 per rocket launch.
    weight = 1 * tons,
    stack_size = 1,
  },
})

-- The out-of-map tile already collides with this layer by default, so
-- adding it to the leg's own mask is enough to keep it off the map edge
-- despite its otherwise-empty collision_mask.
local map_layer = out_of_map_layer_name()
data.raw["spider-leg"]["mega-mech-armor-leg"].collision_mask.layers[map_layer] = true
