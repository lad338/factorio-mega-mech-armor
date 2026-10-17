-- Reuses mech-armor's own flying-animation art directly rather than
-- reimplementing __space-age__'s mech_anim() helper (it's `local` to its
-- own file, not exported) -- just a deep copy, scale-up, and hover shift.

local VEHICLE_SCALE = 2.5
local HOVER_SHIFT = util.by_pixel(0, -12)

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
  -- Layers already carry a real anchor shift (positioning the sprite
  -- relative to a character's feet) -- scale it up, don't overwrite it,
  -- then add the hover offset on top for non-shadow layers only.
  local existing_shift = layer.shift or {0, 0}
  local scaled_shift = {existing_shift[1] * VEHICLE_SCALE, existing_shift[2] * VEHICLE_SCALE}
  if layer.draw_as_shadow then
    layer.shift = scaled_shift
  else
    layer.shift = {scaled_shift[1] + HOVER_SHIFT[1], scaled_shift[2] + HOVER_SHIFT[2]}
  end
end

return torso_animation
