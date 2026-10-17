-- Runs after every mod's data-updates.lua, so clones are built from the
-- final state of their source prototypes regardless of load order.

-- Clones a gun with a new name, range, and cooldown. Range scales with
-- quality automatically (QualityPrototype.range_multiplier); cooldown
-- does not, so speed_multiplier is applied flat here instead.
local function clone_gun(source_name, new_name, localised_name, range, speed_multiplier)
  local source = data.raw.gun[source_name]
  if not source then
    error("mega-mech-armor: expected gun '" .. source_name .. "' to exist (needed to build '" .. new_name .. "') -- did another mod remove or rename it?")
  end
  if data.raw.gun[new_name] then
    error("mega-mech-armor: a gun named '" .. new_name .. "' already exists -- another mod collides with this name")
  end
  local clone = util.table.deepcopy(source)
  clone.name = new_name
  clone.localised_name = localised_name
  -- Built-in to the vehicle only, not separately craftable/placeable.
  clone.hidden = true
  clone.attack_parameters.cooldown = clone.attack_parameters.cooldown / speed_multiplier
  clone.attack_parameters.range = range
  return clone
end

data:extend({
  clone_gun("tank-cannon", "mega-mech-armor-cannon", {"item-name.mega-mech-armor-cannon"}, 36, 2),
  clone_gun("vehicle-machine-gun", "mega-mech-armor-machine-gun", {"item-name.mega-mech-armor-machine-gun"}, 25, 2),
  clone_gun("tank-flamethrower", "mega-mech-armor-flamethrower", {"item-name.mega-mech-armor-flamethrower"}, 25, 2),
  -- Two clones of the same tier, sharing one display name.
  clone_gun("spidertron-rocket-launcher-1", "mega-mech-armor-rocket-launcher-1", {"item-name.mega-mech-armor-rocket-launcher"}, 36, 2),
  clone_gun("spidertron-rocket-launcher-1", "mega-mech-armor-rocket-launcher-2", {"item-name.mega-mech-armor-rocket-launcher"}, 36, 2),
  clone_gun("teslagun", "mega-mech-armor-tesla-gun", {"item-name.mega-mech-armor-tesla-gun"}, 36, 4),
  clone_gun("railgun", "mega-mech-armor-railgun", {"item-name.mega-mech-armor-railgun"}, 45, 2),
})

-- Railgun ammo is shared with players/turrets, so the only way to stop
-- it friendly-firing this vehicle is to make it enemy-only everywhere.
local railgun_ammo = data.raw.ammo["railgun-ammo"]
if railgun_ammo then
  railgun_ammo.ammo_type.action.force = "enemy"
end

-- Visual origin point for combat-mode beams, so they appear to come
-- from the mech's floating torso rather than the ground.
local BEAM_SOURCE_OFFSET = {0, -5}

-- Range for both combat-mode auto-fire weapons. Kept below the vehicle's
-- own manual weapon ranges (railgun 45) to avoid triggering long-range
-- enemy AI scatter behavior.
local COMBAT_WEAPON_RANGE = 24

-- Combat Mode's laser equipment: a clone of personal-laser-defense-equipment.
local laser_source = data.raw["active-defense-equipment"]["personal-laser-defense-equipment"]
if not laser_source then
  error("mega-mech-armor: expected personal-laser-defense-equipment to exist")
end
local combat_laser = util.table.deepcopy(laser_source)
combat_laser.name = "mega-mech-armor-combat-laser"
combat_laser.localised_name = {"equipment-name.mega-mech-armor-combat-laser"}
combat_laser.categories = {"mega-mech-armor-combat-mode"}
combat_laser.attack_parameters.range = COMBAT_WEAPON_RANGE
combat_laser.attack_parameters.ammo_type.action.action_delivery.max_length = COMBAT_WEAPON_RANGE
-- No energy cost -- the carrier's isolated equipment grid has no power source.
combat_laser.attack_parameters.ammo_type.energy_consumption = nil
combat_laser.attack_parameters.ammo_type.action.action_delivery.source_offset = BEAM_SOURCE_OFFSET

-- Combat Mode's tesla equipment: no vanilla equivalent, so it's built
-- from mega-mech-armor-tesla-gun's attack_parameters (cooldown, source
-- direction count, etc.) plus tesla-ammo's own damage action.
local tesla_gun = data.raw.gun["mega-mech-armor-tesla-gun"]
if not tesla_gun then
  error("mega-mech-armor: expected mega-mech-armor-tesla-gun to exist (built earlier in this same file)")
end
local tesla_ammo = data.raw.ammo["tesla-ammo"]
if not tesla_ammo then
  error("mega-mech-armor: expected tesla-ammo to exist")
end

-- Deep-copied from laser_source so active-defense-equipment's required
-- `automatic = true` field comes along; attack_parameters is replaced below.
local combat_tesla = util.table.deepcopy(laser_source)
combat_tesla.name = "mega-mech-armor-combat-tesla"
combat_tesla.localised_name = {"equipment-name.mega-mech-armor-combat-tesla"}
combat_tesla.categories = {"mega-mech-armor-combat-mode"}
combat_tesla.attack_parameters = util.table.deepcopy(tesla_gun.attack_parameters)
combat_tesla.attack_parameters.range = COMBAT_WEAPON_RANGE
combat_tesla.attack_parameters.ammo_type = util.table.deepcopy(tesla_ammo.ammo_type)
-- No energy cost, same reasoning as the laser equipment above.

-- Tesla's beam is nested inside a chain action-delivery's target_effects
-- (the chain-jump effect, then the actual beam at index 2).
combat_tesla.attack_parameters.ammo_type.action.action_delivery.target_effects[2]
  .action.action_delivery.source_offset = BEAM_SOURCE_OFFSET

-- Hidden items so EquipmentPrototype.take_result resolves at load time.
-- These can never actually be obtained -- the carrier's grid is never opened.
local combat_laser_item = {
  type = "item",
  name = "mega-mech-armor-combat-laser",
  icon = "__mega-mech-armor__/graphics/entity/mega-mech-armor/mega-mech-armor-icon.png",
  icon_size = 64,
  subgroup = "equipment",
  order = "z[mega-mech-armor-combat-laser]",
  hidden = true,
  stack_size = 1,
}
local combat_tesla_item = {
  type = "item",
  name = "mega-mech-armor-combat-tesla",
  icon = "__mega-mech-armor__/graphics/entity/mega-mech-armor/mega-mech-armor-icon.png",
  icon_size = 64,
  subgroup = "equipment",
  order = "z[mega-mech-armor-combat-tesla]",
  hidden = true,
  stack_size = 1,
}

-- Combat Mode's distractor: vanilla distractor doesn't move, so this
-- clone merges in destroyer's movement fields while keeping distractor's
-- own laser-beam attack.
local distractor_source = data.raw["combat-robot"]["distractor"]
local destroyer_source = data.raw["combat-robot"]["destroyer"]
if not (distractor_source and destroyer_source) then
  error("mega-mech-armor: expected both distractor and destroyer combat-robot prototypes to exist")
end
local combat_distractor = util.table.deepcopy(distractor_source)
combat_distractor.name = "mega-mech-armor-combat-distractor"
combat_distractor.localised_name = {"entity-name.mega-mech-armor-combat-distractor"}
combat_distractor.speed = destroyer_source.speed
combat_distractor.follows_player = destroyer_source.follows_player
combat_distractor.friction = destroyer_source.friction
combat_distractor.range_from_player = destroyer_source.range_from_player
combat_distractor.separation_range = destroyer_source.separation_range
combat_distractor.max_separation_force = destroyer_source.max_separation_force
combat_distractor.separation_force_factor = destroyer_source.separation_force_factor

data:extend({combat_laser, combat_tesla, combat_laser_item, combat_tesla_item, combat_distractor})
