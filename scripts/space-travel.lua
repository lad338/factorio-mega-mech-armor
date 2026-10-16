local combat_mode = require("scripts.combat-mode")
-- Only used below for one-time cleanup of a GUI element an earlier
-- version of this mod created with this library (mod_gui.get_button_flow)
-- -- not part of this feature's own ongoing design, which no longer
-- uses mod-gui at all.
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

-- Must be 0, not merely small: transition_time's pan starts from the
-- camera's CURRENT position, which for a brand-new cutscene is the
-- vehicle's own (already-teleported) position -- centered on screen --
-- not the previous cutscene's last waypoint. Any nonzero value here
-- renders that centered frame for one tick before panning to
-- landing_position, which is exactly the "mech appears in the centre"
-- blink this constant exists to prevent. 0 makes the camera snap to
-- landing_position with no transition frame at all.
local CAMERA_SNAP_TICKS = 0

-- A cutscene waypoint's time_to_wait governs when the cutscene ends on
-- its own ("finishes naturally") -- not how long this module's own
-- tick-driven animation takes. Both waypoints below hold indefinitely;
-- this module ends the cutscene itself (begin_descend re-issues a new
-- one, finish_travel calls exit_cutscene), never the engine.
local WAYPOINT_HOLD_TICKS = 0xFFFFFFFF

-- Hard failsafe: a real trip should never take anywhere near this
-- long (ASCEND_TICKS + DESCEND_TICKS = 180). If one ever does, that
-- means something about the normal completion path silently didn't
-- work -- confirmed to be possible live: a player reported getting
-- completely stuck in a locked-out state after a full, error-free
-- trip, with no crash dialog to explain why. Rather than leave anyone
-- permanently stuck on an undiscovered bug, on_tick forces a cleanup
-- once a trip has run this long, regardless of phase or any other
-- state.
local MAX_TRIP_TICKS = 600

local function get_state(player_index)
  storage.mega_mech_armor_space_travel = storage.mega_mech_armor_space_travel or {}
  return storage.mega_mech_armor_space_travel[player_index]
end

-- On space_travel.internal (not just a local) so headless tests can
-- call it directly against real entities, without a real LuaPlayer.
function space_travel.internal.is_driving_mech(player)
  local vehicle = player.physical_vehicle
  if not (vehicle and vehicle.valid and vehicle.name == "mega-mech-armor") then
    return nil
  end
  -- allow_passengers defaults to true on VehiclePrototype, and this
  -- vehicle doesn't override it, so a passenger also has
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

-- Anchored to the right of the mega mech armor's own vehicle frame
-- (the middle, trunk/weapons/equipment column) via
-- relative_gui_type.spider_vehicle_gui, scoped by `name` to this
-- entity only -- it won't show on vanilla spidertron or any other
-- spider-vehicle. Built/destroyed by on_gui_opened/on_gui_closed for
-- that specific vehicle (see below), not by driving state alone --
-- driving state doesn't tell you WHICH mega-mech-armor's GUI is
-- currently open, and a player can open another, undriven
-- mega-mech-armor's trunk from outside it while still driving their
-- own.
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

-- Exit the ascend cutscene and re-enter a new one for descend within
-- the SAME tick/function call -- the two-tick split tried earlier
-- (exiting on one tick, teleporting and re-entering on the next) was
-- a hypothesis for a different, since-disproven bug, and left a
-- real, visible side effect: for that one in-between tick, the
-- player's camera rendered their normal, un-cutscened view -- still
-- on the ORIGIN planet, since the teleport hadn't happened yet --
-- before being locked back into the descend cutscene a tick later.
-- That's the visible "blink" this collapses away.
local function begin_descend(state)
  local internal = space_travel.internal
  if state.player.controller_type == defines.controllers.cutscene then
    -- on_cutscene_cancelled fires for a cutscene ended "by the player
    -- OR BY SCRIPT" -- this script's own exit_cutscene() call below
    -- counts as the latter. own_exit_in_progress tells
    -- space_travel.on_cutscene_cancelled to leave this trip's state
    -- alone for its own script-initiated exit, so only a genuine
    -- player-initiated cancellation actually tears the trip down.
    state.own_exit_in_progress = true
    pcall(function()
      state.player.exit_cutscene()
    end)
  end
  -- A real player can be ejected from the vehicle's driver seat as a
  -- side effect of exit_cutscene() restoring normal character control
  -- -- re-seat explicitly before relying on "the vehicle brings its
  -- driver along" for the upcoming cross-surface teleport.
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
    -- Teleport didn't fully take effect (surface still wrong, or the
    -- driver got separated from the vehicle) -- abort cleanly rather
    -- than hand the player back into a broken, driverless/vehicleless
    -- state.
    storage.mega_mech_armor_space_travel[state.player.index] = nil
    return
  end
  -- Camera snaps to and holds on the landing position almost
  -- instantly (CAMERA_SNAP_TICKS), rather than panning there over the
  -- whole descent -- the mech then visually flies INTO this static
  -- frame from off-screen (per ARRIVAL_OFFSET) as step_descend moves
  -- it, rather than the camera loosely tracking it the whole way.
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

-- Clears this module's own tracking FIRST, then attempts
-- exit_cutscene defensively (pcall-wrapped) -- if that call itself is
-- ever wrong about controller_type/validity, our own state is already
-- clean and on_tick will never touch this player again regardless, so
-- a failed exit_cutscene here can no longer cause a permanent
-- cutscene-lock on its own. Real report: a player got stuck
-- completely locked out after a full, error-free trip -- the surest
-- sign is that no crash dialog appeared, meaning something here
-- silently didn't do what it looked like it did.
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

-- One-time migration: two earlier versions of this mod each created a
-- button this feature no longer uses -- one in the top-row mod-gui
-- flow, one anchored directly into player.gui.relative. Removing the
-- code that created either doesn't remove one that already exists in
-- a save from before this change, so both are swept away explicitly,
-- once, for every currently-known player.
-- _v2, deliberately not the original flag name: a save that already
-- ran the first (narrower, mod-gui-only) cleanup has that flag set to
-- true already, which would otherwise skip this expanded version
-- forever and never reach the second leftover location.
-- mod_gui's own button flow is shared by every mod that uses it, so
-- destroying our button can leave an empty (but still visible, bordered)
-- wrapper frame behind if nothing else happens to be using it. Safe to
-- remove: mod_gui.get_button_flow recreates this exact structure from
-- scratch for any mod that still needs it, so an empty one costs
-- nothing to lose. Only ever removes mod_gui's own well-known
-- "mod_gui_top_frame" wrapper specifically, never gui.top itself.
local function destroy_if_now_empty(element)
  if element and element.valid and #element.children == 0 then
    local parent = element.parent
    element.destroy()
    if parent and parent.valid and parent.name == "mod_gui_top_frame" and #parent.children == 0 then
      parent.destroy()
    end
  end
end

-- _v3: the user already confirmed v2's cleanup removed both buttons
-- (that flag is already true in their save), but v2 never destroyed
-- the now-empty wrapper frame those buttons were sitting in -- a new
-- flag is required again, same reasoning as the v1->v2 bump.
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
    -- Unconditional: the button itself may already be gone (an
    -- earlier cleanup round already removed it), leaving just the
    -- empty wrapper frame behind -- that's the exact case reported.
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

-- Fires both for a player-initiated cancel/skip AND for this module's
-- own exit_cutscene() calls (the event is documented as cancelled "by
-- the player OR BY SCRIPT"). own_exit_in_progress distinguishes the
-- two: set right before begin_descend's own intentional exit, and
-- cleared here without touching the trip's state, so only a genuine
-- player-initiated cancellation actually tears the trip down.
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

-- Driving state alone can't tell us WHICH mega-mech-armor's GUI is
-- open (there could be several), only whether this player is still
-- driving one at all -- used purely as a safety net to clear a stale
-- panel if they stop driving while it's still showing.
function space_travel.on_driving_state_changed(player)
  if not is_driving_mech(player) then
    destroy_frame(player)
  end
end

-- Builds or tears down the planet-list panel for the SPECIFIC
-- mega-mech-armor whose own GUI was just opened/closed -- not every
-- mega-mech-armor, and not based on driving state alone. A player can
-- open another, undriven mega-mech-armor's trunk from outside it
-- (e.g. to transfer cargo) while still driving their own; only the
-- one they're actually driving should show the panel.
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
