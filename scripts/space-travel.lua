local combat_mode = require("scripts.combat-mode")
-- Only used for one-time cleanup of a legacy GUI button; this feature's
-- own design no longer uses mod-gui.
local mod_gui = require("mod-gui")

local space_travel = {}
space_travel.internal = {}

local FRAME_NAME = "mega-mech-armor-space-travel-frame"
local PLANET_ROW_PREFIX = "mega-mech-armor-space-travel-planet-"
local LEGACY_BUTTON_NAME = "mega-mech-armor-space-travel-button"

local ASCEND_TICKS = 90
local ASCEND_OFFSET = {x = 60, y = -40}
local CAMERA_ASCEND_TARGET_OFFSET = {x = 0, y = -8}
local DESCEND_TICKS = 90
local ARRIVAL_OFFSET = {x = -40, y = -30}
local FACING_RIGHT = 0.25

-- Must be 0: transition_time pans from the camera's CURRENT position
-- (the vehicle's own just-teleported position, centered on screen), not
-- the previous cutscene's last waypoint. Any nonzero value renders that
-- centered frame for a tick before panning to landing_position.
local CAMERA_SNAP_TICKS = 0

-- time_to_wait governs when a cutscene ends on its own; both waypoints
-- below hold indefinitely -- this module always ends its own cutscenes
-- (begin_descend re-issues a new one, finish_travel calls exit_cutscene).
local WAYPOINT_HOLD_TICKS = 0xFFFFFFFF

-- Failsafe: a real trip never takes anywhere near this long
-- (ASCEND_TICKS + DESCEND_TICKS = 180). If one does, the normal
-- completion path silently failed -- force a cleanup rather than leave
-- the player locked out indefinitely.
local MAX_TRIP_TICKS = 600

local function get_state(player_index)
  storage.mega_mech_armor_space_travel = storage.mega_mech_armor_space_travel or {}
  return storage.mega_mech_armor_space_travel[player_index]
end

function space_travel.internal.is_driving_mech(player)
  local vehicle = player.physical_vehicle
  if not (vehicle and vehicle.valid and vehicle.name == "mega-mech-armor") then
    return nil
  end
  -- allow_passengers defaults to true, so a passenger also has
  -- physical_vehicle set -- only the actual driver may trigger travel.
  local driver = vehicle.get_driver()
  if driver == player.character or driver == player then
    return vehicle
  end
  return nil
end
local is_driving_mech = space_travel.internal.is_driving_mech

local function destroy_frame(player)
  if player.gui.relative[FRAME_NAME] then
    player.gui.relative[FRAME_NAME].destroy()
  end
end

-- Anchored to the right of this vehicle's own GUI via
-- relative_gui_type.spider_vehicle_gui, scoped by `name` so it never
-- shows on vanilla spidertron or any other spider-vehicle.
local function build_planet_frame(player, vehicle)
  destroy_frame(player)
  local frame = player.gui.relative.add({
    type = "frame",
    name = FRAME_NAME,
    caption = {"gui.mega-mech-armor-space-travel-frame-title"},
    direction = "vertical",
    anchor = {
      gui = defines.relative_gui_type.spider_vehicle_gui,
      position = defines.relative_gui_position.right,
      name = "mega-mech-armor",
    },
  })
  local planets = space_travel.internal.get_eligible_planets(vehicle)
  if #planets == 0 then
    frame.add({type = "label", caption = {"gui.mega-mech-armor-space-travel-no-planets"}})
  else
    for _, planet in pairs(planets) do
      frame.add({
        type = "button",
        name = PLANET_ROW_PREFIX .. planet.name,
        caption = planet.prototype.localised_name,
      })
    end
  end
end

-- Exits the ascend cutscene and enters the descend one within the same
-- call, so no frame renders in between with the camera off a cutscene.
local function begin_descend(state)
  local internal = space_travel.internal
  if state.player.controller_type == defines.controllers.cutscene then
    -- on_cutscene_cancelled fires for a script-initiated exit too, not
    -- just a player-initiated one. own_exit_in_progress tells
    -- space_travel.on_cutscene_cancelled to ignore this one, so only a
    -- genuine player cancellation tears the trip down.
    state.own_exit_in_progress = true
    pcall(function()
      state.player.exit_cutscene()
    end)
  end
  -- exit_cutscene() can eject the player from the driver seat as a side
  -- effect -- re-seat before the upcoming cross-surface teleport.
  if state.vehicle.get_driver() == nil and state.player.character and state.player.character.valid then
    state.vehicle.set_driver(state.player.character)
  end
  local landing_position = internal.compute_landing_position(state.destination_surface, state.player.force)
  state.landing_position = landing_position
  state.arrival_position = {
    x = landing_position.x + ARRIVAL_OFFSET.x,
    y = landing_position.y + ARRIVAL_OFFSET.y,
  }
  internal.teleport_vehicle(state.vehicle, state.destination_surface, state.arrival_position)
  if state.vehicle.surface ~= state.destination_surface or state.vehicle.get_driver() == nil then
    -- Teleport didn't fully take, or the driver got separated -- abort
    -- rather than hand back a broken, driverless/vehicleless state.
    storage.mega_mech_armor_space_travel[state.player.index] = nil
    return
  end
  -- Camera snaps straight to the landing position; the mech then flies
  -- INTO this static frame from off-screen (ARRIVAL_OFFSET) as
  -- step_descend moves it.
  state.player.set_controller({
    type = defines.controllers.cutscene,
    waypoints = {
      {
        position = landing_position,
        transition_time = CAMERA_SNAP_TICKS,
        time_to_wait = WAYPOINT_HOLD_TICKS,
      },
    },
  })
  state.phase = "descend"
  state.tick = 0
end

-- Clears this module's own tracking first, so a failed exit_cutscene
-- below can never leave a trip permanently stuck.
local function finish_travel(player_index, state)
  storage.mega_mech_armor_space_travel[player_index] = nil
  if state.player and state.player.valid then
    pcall(function()
      if state.player.controller_type == defines.controllers.cutscene then
        state.player.exit_cutscene()
      end
    end)
  end
end

local function step_ascend(state)
  local internal = space_travel.internal
  state.tick = state.tick + 1
  local progress = internal.ease_in_quad(math.min(state.tick / ASCEND_TICKS, 1))
  state.vehicle.teleport({
    x = state.origin_position.x + ASCEND_OFFSET.x * progress,
    y = state.origin_position.y + ASCEND_OFFSET.y * progress,
  }, state.origin_surface)
  if state.tick >= ASCEND_TICKS then
    begin_descend(state)
  end
end

local function step_descend(player_index, state)
  local internal = space_travel.internal
  state.tick = state.tick + 1
  local progress = internal.ease_out_quad(math.min(state.tick / DESCEND_TICKS, 1))
  state.vehicle.teleport({
    x = internal.lerp(state.arrival_position.x, state.landing_position.x, progress),
    y = internal.lerp(state.arrival_position.y, state.landing_position.y, progress),
  }, state.destination_surface)
  if state.tick >= DESCEND_TICKS then
    finish_travel(player_index, state)
  end
end

local function start_travel(player, vehicle, planet)
  combat_mode.stop_if_active(player)
  destroy_frame(player)
  local origin_surface = vehicle.surface
  local origin_position = vehicle.position
  vehicle.orientation = FACING_RIGHT
  player.set_controller({
    type = defines.controllers.cutscene,
    waypoints = {
      {
        position = {
          x = origin_position.x + CAMERA_ASCEND_TARGET_OFFSET.x,
          y = origin_position.y + CAMERA_ASCEND_TARGET_OFFSET.y,
        },
        transition_time = ASCEND_TICKS,
        time_to_wait = WAYPOINT_HOLD_TICKS,
      },
    },
  })
  storage.mega_mech_armor_space_travel = storage.mega_mech_armor_space_travel or {}
  storage.mega_mech_armor_space_travel[player.index] = {
    player = player,
    vehicle = vehicle,
    phase = "ascend",
    tick = 0,
    started_tick = game.tick,
    origin_surface = origin_surface,
    origin_position = origin_position,
    destination_surface = planet.surface,
  }
end

-- mod_gui's button flow is shared by every mod that uses it, so
-- destroying our button can leave an empty wrapper frame behind.
-- Safe to remove: mod_gui recreates this structure from scratch for any
-- mod that still needs it.
local function destroy_if_now_empty(element)
  if element and element.valid and #element.children == 0 then
    local parent = element.parent
    element.destroy()
    if parent and parent.valid and parent.name == "mod_gui_top_frame" and #parent.children == 0 then
      parent.destroy()
    end
  end
end

-- One-time migration: earlier versions of this mod created a button
-- (in mod_gui's top-row flow, then directly in player.gui.relative)
-- that this feature no longer uses. Removing the code that created it
-- doesn't remove one already sitting in an existing save, so it's swept
-- away explicitly, once, for every known player. The flag name is
-- versioned (_v3) because each fix to this cleanup (what to destroy,
-- including the leftover empty wrapper frame) needed saves that already
-- ran an earlier version to run the improved one too.
local function cleanup_legacy_button_once()
  if storage.space_travel_legacy_button_cleaned_v3 then
    return
  end
  storage.space_travel_legacy_button_cleaned_v3 = true
  for _, player in pairs(game.players) do
    local flow = mod_gui.get_button_flow(player)
    if flow[LEGACY_BUTTON_NAME] then
      flow[LEGACY_BUTTON_NAME].destroy()
    end
    destroy_if_now_empty(flow)
    if player.gui.relative[LEGACY_BUTTON_NAME] then
      player.gui.relative[LEGACY_BUTTON_NAME].destroy()
    end
  end
end

function space_travel.on_tick()
  cleanup_legacy_button_once()
  local all_state = storage.mega_mech_armor_space_travel
  if not all_state then
    return
  end
  for player_index, state in pairs(all_state) do
    local vehicle_ok = state.vehicle and state.vehicle.valid
    local player_ok = state.player and state.player.valid
    local surfaces_ok = state.origin_surface.valid and state.destination_surface.valid
    local timed_out = state.started_tick and (game.tick - state.started_tick) > MAX_TRIP_TICKS
    if vehicle_ok and player_ok and surfaces_ok and not timed_out then
      if state.phase == "ascend" then
        step_ascend(state)
      elseif state.phase == "descend" then
        step_descend(player_index, state)
      end
    else
      storage.mega_mech_armor_space_travel[player_index] = nil
      if player_ok then
        pcall(function()
          if state.player.controller_type == defines.controllers.cutscene then
            state.player.exit_cutscene()
          end
        end)
      end
    end
  end
end

-- Fires both for a player-initiated cancel and for this module's own
-- exit_cutscene() calls. own_exit_in_progress (set by begin_descend)
-- distinguishes the two, so only a genuine player cancellation tears
-- the trip down.
function space_travel.on_cutscene_cancelled(player_index)
  local state = get_state(player_index)
  if not state then
    return
  end
  if state.own_exit_in_progress then
    state.own_exit_in_progress = false
    return
  end
  storage.mega_mech_armor_space_travel[player_index] = nil
end

-- Safety net: clears a stale panel if the player stops driving the mech
-- while it's still showing.
function space_travel.on_driving_state_changed(player)
  if not is_driving_mech(player) then
    destroy_frame(player)
  end
end

-- Builds the panel only for the specific mega-mech-armor whose GUI was
-- just opened, and only if the player is driving that one -- a player
-- can open another, undriven mech's trunk while still driving their own.
function space_travel.on_gui_opened(event)
  if event.gui_type ~= defines.gui_type.entity then
    return
  end
  local entity = event.entity
  if not (entity and entity.valid and entity.name == "mega-mech-armor") then
    return
  end
  local player = game.get_player(event.player_index)
  if not player then
    return
  end
  local vehicle = is_driving_mech(player)
  if vehicle and vehicle == entity and not get_state(player.index) then
    build_planet_frame(player, vehicle)
  end
end

function space_travel.on_gui_closed(event)
  if event.gui_type ~= defines.gui_type.entity then
    return
  end
  local entity = event.entity
  if not (entity and entity.valid and entity.name == "mega-mech-armor") then
    return
  end
  local player = game.get_player(event.player_index)
  if not player then
    return
  end
  destroy_frame(player)
end

function space_travel.on_gui_click(event)
  local element = event.element
  if not (element and element.valid) then
    return
  end
  local player = game.get_player(event.player_index)
  if not player then
    return
  end
  if element.name:find(PLANET_ROW_PREFIX, 1, true) == 1 then
    local vehicle = is_driving_mech(player)
    if vehicle and not get_state(player.index) then
      local planet_name = element.name:sub(#PLANET_ROW_PREFIX + 1)
      local planet = game.planets[planet_name]
      if planet and planet.surface then
        start_travel(player, vehicle, planet)
      end
    end
  end
end

function space_travel.internal.get_eligible_planets(vehicle)
  local current_planet = vehicle.surface.planet
  local planets = {}
  for _, planet in pairs(game.planets) do
    if planet.surface and planet ~= current_planet then
      planets[#planets + 1] = planet
    end
  end
  return planets
end

function space_travel.internal.compute_landing_position(surface, force)
  local pads = surface.find_entities_filtered({type = "cargo-landing-pad", force = force})
  if pads[1] then
    return pads[1].position
  end
  return force.get_spawn_position(surface)
end

function space_travel.internal.teleport_vehicle(vehicle, surface, position)
  return vehicle.teleport(position, surface)
end

function space_travel.internal.ease_in_quad(t)
  return t * t
end

function space_travel.internal.ease_out_quad(t)
  return 1 - (1 - t) * (1 - t)
end

function space_travel.internal.lerp(a, b, t)
  return a + (b - a) * t
end

return space_travel
