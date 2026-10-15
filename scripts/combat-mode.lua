local combat_mode = {}

-- Defender and destroyer are unmodified vanilla entities. Distractor is
-- this mod's own clone (mega-mech-armor-combat-distractor, built in
-- data-final-fixes.lua) so it actually follows the vehicle. All three
-- are script-spawned with a fixed count rather than through
-- equipment-grid auto-fire, which has no spawn cap.
local ROBOT_COUNTS = {
  defender = 3,
  ["mega-mech-armor-combat-distractor"] = 3,
  destroyer = 3,
}

-- ~2,270 years of ticks at 60/second: effectively infinite for any
-- realistic play session.
local INFINITE_TIME_TO_LIVE = 0xFFFFFFFF

local function get_state(player_index)
  storage.mega_mech_armor_combat_mode = storage.mega_mech_armor_combat_mode or {}
  return storage.mega_mech_armor_combat_mode[player_index]
end

local function is_available()
  return settings.global["mega-mech-armor-combat-mode-available"].value
end

local function laser_count()
  return settings.global["mega-mech-armor-combat-mode-laser-count"].value
end

local function spawn_carrier(vehicle)
  local carrier = vehicle.surface.create_entity({
    name = "mega-mech-armor-combat-carrier",
    position = vehicle.position,
    force = vehicle.force,
  })
  carrier.destructible = false
  local grid = carrier.grid
  for _ = 1, laser_count() do
    grid.put({name = "mega-mech-armor-combat-laser"})
  end
  for _ = 1, 3 do
    grid.put({name = "mega-mech-armor-combat-tesla"})
  end
  return carrier
end

local function spawn_robots(vehicle)
  local robots = {}
  for robot_name, count in pairs(ROBOT_COUNTS) do
    for _ = 1, count do
      local robot = vehicle.surface.create_entity({
        name = robot_name,
        position = vehicle.position,
        force = vehicle.force,
        quality = vehicle.quality,
      })
      robot.destructible = false
      robot.time_to_live = INFINITE_TIME_TO_LIVE
      robot.combat_robot_owner = vehicle
      robots[#robots + 1] = robot
    end
  end
  return robots
end

local function teardown(player_index)
  local state = get_state(player_index)
  if not state then
    return
  end
  if state.carrier and state.carrier.valid then
    state.carrier.destroy()
  end
  for _, robot in pairs(state.robots) do
    if robot.valid then
      robot.destroy()
    end
  end
  storage.mega_mech_armor_combat_mode[player_index] = nil
end

local function activate(player, vehicle)
  storage.mega_mech_armor_combat_mode = storage.mega_mech_armor_combat_mode or {}
  storage.mega_mech_armor_combat_mode[player.index] = {
    vehicle = vehicle,
    carrier = spawn_carrier(vehicle),
    robots = spawn_robots(vehicle),
  }
  player.set_shortcut_toggled("mega-mech-armor-toggle-combat-mode", true)
end

function combat_mode.toggle(player)
  if not is_available() then
    return
  end
  local vehicle = player.physical_vehicle
  if not (vehicle and vehicle.valid and vehicle.name == "mega-mech-armor") then
    return
  end
  if get_state(player.index) then
    teardown(player.index)
    player.set_shortcut_toggled("mega-mech-armor-toggle-combat-mode", false)
  else
    activate(player, vehicle)
  end
end

-- Covers both a normal exit and the vehicle being destroyed out from
-- under the player.
function combat_mode.on_driving_state_changed(player)
  local state = get_state(player.index)
  if not state then
    return
  end
  local still_driving_same_vehicle = player.physical_vehicle
    and player.physical_vehicle.valid
    and player.physical_vehicle == state.vehicle
  if not still_driving_same_vehicle then
    teardown(player.index)
    player.set_shortcut_toggled("mega-mech-armor-toggle-combat-mode", false)
  end
end

-- Keeps the carrier glued to the real vehicle's position every tick.
-- Only iterates players currently in combat mode, not all players.
function combat_mode.on_tick()
  local all_state = storage.mega_mech_armor_combat_mode
  if not all_state then
    return
  end
  for player_index, state in pairs(all_state) do
    if state.vehicle.valid and state.carrier.valid then
      state.carrier.teleport(state.vehicle.position, state.vehicle.surface)
    else
      teardown(player_index)
      local player = game.get_player(player_index)
      if player then
        player.set_shortcut_toggled("mega-mech-armor-toggle-combat-mode", false)
      end
    end
  end
end

-- The global availability setting turning off mid-game must not leave
-- orphaned carriers/robots for players currently active.
function combat_mode.on_setting_changed(setting_name)
  if setting_name ~= "mega-mech-armor-combat-mode-available" then
    return
  end
  if is_available() then
    return
  end
  local all_state = storage.mega_mech_armor_combat_mode
  if not all_state then
    return
  end
  for player_index, _ in pairs(all_state) do
    teardown(player_index)
    local player = game.get_player(player_index)
    if player then
      player.set_shortcut_toggled("mega-mech-armor-toggle-combat-mode", false)
    end
  end
end

return combat_mode
