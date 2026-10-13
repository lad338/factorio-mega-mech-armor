-- Runs after every mod's own data-updates.lua, regardless of load
-- order, so if another mod ever edits one of these 6 source guns'
-- ammo_category or attack_parameters, we clone from the final result
-- rather than racing it.

-- range scales with quality automatically and generically for any
-- gun's attack_parameters -- confirmed via QualityPrototype.range_multiplier's
-- own docs ("Affects the range of attack parameters, e.g. those used
-- by combat robots, units, guns and turrets"), default
-- min(1 + 0.1*level, 3). No opt-in flag needed; just set the
-- normal-quality baseline range below, same as max_health/inventory_size.
--
-- Fire-rate (cooldown) has no equivalent quality multiplier anywhere
-- in QualityPrototype -- confirmed by listing every one of its fields;
-- there's no generic or opt-in way to make a gun fire faster at higher
-- quality. That's why the tesla gun's speed multiplier below is a
-- flat 4x rather than quality-scaled: it was asked for, and isn't
-- possible.
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
  -- Not separately craftable or placeable -- these only exist as the
  -- vehicle's own built-in guns, same as tank's embedded weapons.
  clone.hidden = true
  clone.attack_parameters.cooldown = clone.attack_parameters.cooldown / speed_multiplier
  clone.attack_parameters.range = range
  return clone
end

data:extend({
  clone_gun("tank-cannon", "mega-mech-armor-cannon", {"item-name.mega-mech-armor-cannon"}, 36, 2),
  clone_gun("vehicle-machine-gun", "mega-mech-armor-machine-gun", {"item-name.mega-mech-armor-machine-gun"}, 25, 2),
  clone_gun("tank-flamethrower", "mega-mech-armor-flamethrower", {"item-name.mega-mech-armor-flamethrower"}, 25, 2),
  -- 2 clones of the same source tier, sharing one display name --
  -- matches the proposal's literal wording ("2 'Spidertron rocket
  -- launcher'... with new name 'Mega mech armor rocket launcher'")
  -- rather than pulling in all 4 of spidertron's own upgrade tiers.
  clone_gun("spidertron-rocket-launcher-1", "mega-mech-armor-rocket-launcher-1", {"item-name.mega-mech-armor-rocket-launcher"}, 36, 2),
  clone_gun("spidertron-rocket-launcher-1", "mega-mech-armor-rocket-launcher-2", {"item-name.mega-mech-armor-rocket-launcher"}, 36, 2),
  clone_gun("teslagun", "mega-mech-armor-tesla-gun", {"item-name.mega-mech-armor-tesla-gun"}, 36, 4),
  clone_gun("railgun", "mega-mech-armor-railgun", {"item-name.mega-mech-armor-railgun"}, 45, 2),
})

-- The railgun was friendly-firing (including hitting the vehicle's own
-- torso). Vanilla's railgun doesn't use a travelling projectile entity
-- at all -- it's an instant line/hitscan action
-- (railgun-ammo.ammo_type.action = {type = "line", ...}) -- so there's
-- no gun-specific projectile to restrict; the only place a "don't hit
-- allies" filter (TriggerItem.force, a ForceCondition) can go is
-- directly on the shared "railgun-ammo" item's own action. Any gun
-- firing this ammo item -- a player's hand-held railgun, a railgun
-- turret, or this vehicle -- gets the same fix; there is no way to
-- scope it to just this vehicle while still accepting the same shared
-- ammo (confirmed: no gun-level override exists for an item-fed
-- weapon's fired behavior).
local railgun_ammo = data.raw.ammo["railgun-ammo"]
if railgun_ammo then
  railgun_ammo.ammo_type.action.force = "enemy"
end
