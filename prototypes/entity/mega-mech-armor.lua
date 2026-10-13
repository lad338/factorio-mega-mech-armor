local torso_animation = require("prototypes.entity.mega-mech-armor-animations")

local VEHICLE_SCALE = 2.5

-- +5 percentage points to every resistance type, read live off vanilla
-- spidertron's own resistances rather than hand-copied, so a future
-- Wube rebalance of spidertron can't silently desync ours.
local resistances = {}
for _, r in pairs(data.raw["spider-vehicle"].spidertron.resistances) do
  resistances[#resistances + 1] = {
    type = r.type,
    decrease = r.decrease,
    percent = r.percent + 5,
  }
end

-- max_health = spidertron's own base health (3000) + half of tank's
-- own base health (2000) = 4000. Both source values confirmed in
-- __base__/prototypes/entity/entities.lua. Needs no quality-scaling
-- flags of its own -- max_health scales automatically and generically
-- for every entity via the engine's own quality system (confirmed via
-- real spidertron health 3000/3900/4800/5700/7500 across the 5 tiers).
local BASE_HEALTH = 3000 + (2000 / 2)

-- inventory_size = spidertron's own trunk (80) + mech armor's own
-- inventory_size_bonus (50, from __space-age__/prototypes/item.lua).
-- Same automatic quality-scaling note as max_health above.
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
    icon = "__space-age__/graphics/icons/mech-armor.png",
    icon_size = 64,
    collision_box = {{-1 * VEHICLE_SCALE, -1 * VEHICLE_SCALE}, {1 * VEHICLE_SCALE, 1 * VEHICLE_SCALE}},
    selection_box = {{-1 * VEHICLE_SCALE, -1 * VEHICLE_SCALE}, {1 * VEHICLE_SCALE, 1 * VEHICLE_SCALE}},
    -- Confirmed via the prototype docs: sticker_box is specifically
    -- "the area where the sticker animation can appear" -- acid damage
    -- stickers included. Scoped to half of collision_box (the actual
    -- mech-armor torso sprite sits in the middle of the much larger
    -- collision/selection area, which represents the whole leg-reach
    -- footprint, not the visible armor itself), rather than 1.5x
    -- collision_box (bigger than the full hitbox) as it was before.
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
    -- car/tank's own map triangle turned out to be hardcoded directly
    -- into the engine's car-type rendering (confirmed: not a sprite
    -- file anywhere in base/core graphics, and spider-vehicle has no
    -- equivalent fallback at all -- omitting these fields left nothing
    -- showing on the map, not a free triangle). Generated instead: the
    -- real mech-armor icon. Cropped to its actual 64x64 icon region
    -- *first* -- the source file is 120x64 and packs multiple unused
    -- character poses side by side; only the left 64px square is the
    -- real icon (confirmed against the vanilla item's own default
    -- icon_size). Scaling down before cropping was tried and rejected:
    -- shrinking the full 120-wide strip pulls part of the next pose
    -- into any 64x64 crop regardless of anchor point, since the gap
    -- between poses shrinks too. Once isolated, the single icon is
    -- scaled down to 70% and placed within a transparent 64x64 canvas
    -- (canvas size unchanged, only the content shrinks, for a margin
    -- around the silhouette) -- 1px right of mathematically centered
    -- (4px was tried first and overshot, leaning right instead of
    -- left). That padded result is recolored to a white fill with a
    -- red outline.
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
    -- Names created by Task 5's data-final-fixes.lua clones. Referencing
    -- them here before they exist is fine -- Factorio validates all
    -- cross-prototype references only after every mod's entire data
    -- stage (data.lua, data-updates.lua, data-final-fixes.lua) has run.
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
    -- Space Spidertron uses 0.2 (vanilla spidertron uses 0.005 -- fine
    -- for 5-legged walking, but reads as sluggish on a flying,
    -- single-leg vehicle); matched its near-instant turn rate.
    torso_rotation_speed = 0.2,
    chunk_exploration_radius = 3,
    selection_priority = 60,
    graphics_set = {
      animation = torso_animation,
    },
    energy_source = {type = "void"},
    movement_energy_consumption = "250kW",
    -- Both fields are required on spider-vehicle (no default -- confirmed
    -- via a real load error when they were omitted). automatic_weapon_cycling
    -- = false is the literal "no chain shooting" the proposal asks for;
    -- chain_shooting_cooldown_modifier is inert whenever cycling is false,
    -- so 1 (neutral) is fine.
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
    -- Can't be built where there's no gravity (space platforms),
    -- same restriction vanilla spidertron gets on Space Age -- despite
    -- flying, it's still not a space-rated vehicle.
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
    icon = "__space-age__/graphics/icons/mech-armor.png",
    icon_size = 64,
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
    icon = "__space-age__/graphics/icons/mech-armor.png",
    icon_size = 64,
    subgroup = "transport",
    order = "b[personal-transport]-d[mega-mech-armor]",
    place_result = "mega-mech-armor",
    -- 1 ton matches the rocket silo's own default lift_weight (1,000,000
    -- internal units = 1000kg, confirmed in
    -- core/prototypes/utility-constants.lua's default_rocket_lift_weight)
    -- exactly, the same value vanilla's own spidertron and tank items use
    -- for the same reason: caps it to exactly 1 per rocket launch to a
    -- space platform.
    weight = 1 * tons,
    stack_size = 1,
  },
})

-- Leg still can't walk off the edge of the actual map, same technique
-- the "Space Spidertron" reference mod uses for its own zero-collision
-- leg. The out-of-map tile already collides with this layer by
-- default (confirmed via the live data dump), so only the leg's own
-- mask needs the layer added.
local map_layer = out_of_map_layer_name()
data.raw["spider-leg"]["mega-mech-armor-leg"].collision_mask.layers[map_layer] = true
