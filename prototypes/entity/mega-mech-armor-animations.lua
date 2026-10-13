-- Reuses mech-armor's own flying-animation art directly, rather than
-- reimplementing the mech_anim() helper from
-- __space-age__/prototypes/entity/mech-armor-animations.lua (that
-- helper is `local` to its own file and not exported). Both source
-- animation and target field are confirmed RotatedAnimation, so no
-- shape conversion is needed -- only a deep copy plus a scale-up and
-- a static hover shift.

local VEHICLE_SCALE = 2.5 -- tuned down from 3x after visual testing
local HOVER_SHIFT = util.by_pixel(0, -12) -- modest upward shift; tune after visual testing

local mech_armor_animation_set
for _, armor_animation_set in pairs(data.raw.character.character.animations) do
  for _, armor_name in pairs(armor_animation_set.armors or {}) do
    if armor_name == "mech-armor" then
      mech_armor_animation_set = armor_animation_set
      break
    end
  end
  if mech_armor_animation_set then break end
end

if not mech_armor_animation_set then
  error("mega-mech-armor: could not find mech-armor's own character animation set to reuse -- is the space-age mod loaded?")
end

local torso_animation = util.table.deepcopy(mech_armor_animation_set.idle_with_gun_in_air)
for _, layer in pairs(torso_animation.layers) do
  layer.scale = (layer.scale or 1) * VEHICLE_SCALE
  -- These layers carry their own real anchor shift already (confirmed
  -- via the live data dump -- e.g. the body layer's own shift is
  -- {0, -0.96875}, not {0, 0}), inherited from how mech-armor
  -- positions this sprite relative to a character's feet. Scale that
  -- existing shift up with everything else, and only ADD the hover
  -- offset on top for non-shadow layers -- overwriting it outright
  -- (an earlier version of this file did exactly that) discards the
  -- real anchor and visibly misplaces the torso relative to the
  -- vehicle's own collision box.
  local existing_shift = layer.shift or {0, 0}
  local scaled_shift = {existing_shift[1] * VEHICLE_SCALE, existing_shift[2] * VEHICLE_SCALE}
  if layer.draw_as_shadow then
    layer.shift = scaled_shift
  else
    layer.shift = {scaled_shift[1] + HOVER_SHIFT[1], scaled_shift[2] + HOVER_SHIFT[2]}
  end
end

return torso_animation
