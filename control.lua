local combat_mode = require("scripts.combat-mode")
local space_travel = require("scripts.space-travel")

-- Keeps the vehicle's color synced to its driver's player color.
local function sync_color(entity, color)
  if entity and entity.valid and entity.name == "mega-mech-armor" then
    entity.color = color
  end
end

script.on_event(defines.events.on_player_driving_changed_state, function(event)
  local player = game.get_player(event.player_index)
  if not player then
    return
  end
  sync_color(player.physical_vehicle, player.color)
  combat_mode.on_driving_state_changed(player)
  space_travel.on_driving_state_changed(player)
end)

script.on_event(defines.events.on_player_color_changed, function(event)
  local player = game.get_player(event.player_index)
  if not player then
    return
  end
  sync_color(player.physical_vehicle, player.color)
end)

script.on_event(defines.events.on_lua_shortcut, function(event)
  if event.prototype_name ~= "mega-mech-armor-toggle-combat-mode" then
    return
  end
  local player = game.get_player(event.player_index)
  if player then
    combat_mode.toggle(player)
  end
end)

script.on_event("mega-mech-armor-toggle-combat-mode", function(event)
  local player = game.get_player(event.player_index)
  if player then
    combat_mode.toggle(player)
  end
end)

script.on_event(defines.events.on_tick, function()
  combat_mode.on_tick()
  space_travel.on_tick()
end)

script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
  combat_mode.on_setting_changed(event.setting)
end)

script.on_event(defines.events.on_gui_click, function(event)
  space_travel.on_gui_click(event)
end)

script.on_event(defines.events.on_gui_opened, function(event)
  space_travel.on_gui_opened(event)
end)

script.on_event(defines.events.on_gui_closed, function(event)
  space_travel.on_gui_closed(event)
end)

script.on_event(defines.events.on_cutscene_cancelled, function(event)
  space_travel.on_cutscene_cancelled(event.player_index)
end)
