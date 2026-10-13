-- The proposal asks for the vehicle's color to track the driver's own
-- player color (like personal mech armor does), not an independent
-- per-vehicle setting the way spidertron's own color picker works.
-- Vanilla's vehicle GUI still exposes a color picker for this entity
-- (inherited generically from spider-vehicle) -- a color set there
-- while unmanned will be overwritten the next time someone drives it.
-- That's the accepted cost of matching the proposal's literal wording
-- rather than spidertron's independent-color behavior.
local function sync_color(entity, color)
  if entity and entity.valid and entity.name == "mega-mech-armor" then
    entity.color = color
  end
end

-- Picks up the driver's current color the moment they start driving,
-- not just on their next color change.
script.on_event(defines.events.on_player_driving_changed_state, function(event)
  local player = game.get_player(event.player_index)
  if not player then
    return
  end
  sync_color(player.vehicle, player.color)
end)

script.on_event(defines.events.on_player_color_changed, function(event)
  local player = game.get_player(event.player_index)
  if not player then
    return
  end
  sync_color(player.vehicle, player.color)
end)
