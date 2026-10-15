# Combat Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a toggleable "Combat Mode" to the Mega Mech Armor — a hotkey/shortcut-driven burst of native-mechanic auto-fire (laser + tesla, via equipment) and fixed-count combat robots (Destroyer/Distractor/Defender), scoped to whichever vehicle the player is currently manually driving.

**Architecture:** A hidden, never-selectable `car`-type carrier entity holds two new equipment types (a ranged-up laser clone, and a from-scratch tesla equivalent) in a grid isolated by a dedicated equipment category — reusing the engine's own native active-defense auto-targeting rather than any custom targeting code. The three combat robot types are real, unmodified vanilla entities, script-spawned directly (not through equipment) so their counts stay exactly fixed. Everything is driven by `on_player_driving_changed_state`, a `shortcut`/`custom-input` pair, and two `runtime-global` mod settings.

**Tech Stack:** Factorio 2.1 data/control stage Lua modding (Space Age DLC).

**Spec:** `docs/proposal/combat-mode-design.md` (and the original request, `docs/proposal/combat-mode.md`)

## Global Constraints

- Scope is exactly one vehicle per player: whichever `mega-mech-armor` they are currently **manually** driving (`player.physical_vehicle`, not remote driving, not any previously-driven vehicle). Confirmed scope decision, not open for reinterpretation mid-implementation.
- `LuaPlayer` has no `vehicle` attribute — always use `physical_vehicle`. (A real bug from this exact mistake was already found and fixed in the base mod's color-sync code; don't repeat it here.)
- Both new mod settings are `setting_type = "runtime-global"` — server-wide, no restart required.
- The 3 robot counts (5 Defender, 3 Distractor, 5 Destroyer) and the tesla equipment count (3) are fixed, not settings. Only the laser count is configurable (`mega-mech-armor-combat-mode-laser-count`, default `5`).
- No unit-test framework exists for this project. Every task's verification is `factorio.exe --dump-data` (data-stage) and, for `control.lua` changes, a throwaway headless `--create` + `--benchmark` run — the same methodology used throughout this mod so far. Manual in-game QA is still required for behavior no headless run can exercise (listed per-task and consolidated in Task 5).

## Review Focus

1. **Grid/equipment isolation actually holds** — a player should never be able to insert the combat-mode laser/tesla equipment into their own armor or the real mega mech armor's own grid, and nothing else should fit into the carrier's grid. This is enforced entirely by the new equipment category matching nothing else in the game; Task 2's smoke test should confirm the category is genuinely unique (not accidentally reusing `"armor"`).
2. **Toggling off while a robot is mid-flight/mid-attack doesn't error** — `destructible = false` entities and in-progress attacks need to tear down cleanly even if a robot is actively engaged with a target when combat mode ends. Covered by Task 4's teardown function being defensive about `entity.valid`.
3. **The player stops driving (vehicle destroyed, not just exited) while combat mode is active** — the carrier and robots must not be left orphaned, belonging to a vehicle that no longer exists. `on_player_driving_changed_state` with `event.entity == nil` (ejected, including via destruction per that event's own exception note) must still trigger teardown.
4. **Two different players both running combat mode simultaneously** on two different mega mech armors never cross-contaminate each other's carrier/robots — the `storage` table is keyed by `player_index` throughout, matching the pattern already established for color sync.
5. **The global availability setting is switched off while players currently have combat mode active** — covered explicitly by Task 4's `on_runtime_mod_setting_changed` handler, not left as an unhandled edge case.

---

### Task 1: Mod settings, equipment category, and hidden carrier entity

**Files:**
- Create: `settings.lua`
- Create: `prototypes/combat-mode/equipment-category.lua`
- Create: `prototypes/combat-mode/carrier.lua`
- Modify: `data.lua`

**Interfaces:**
- Produces: mod settings `mega-mech-armor-combat-mode-available` (bool) and `mega-mech-armor-combat-mode-laser-count` (int); `equipment-category` prototype `"mega-mech-armor-combat-mode"`; `car` entity prototype `"mega-mech-armor-combat-carrier"`; `equipment-grid` prototype `"mega-mech-armor-combat-carrier-grid"`. Task 2's equipment and Task 4's control.lua both reference these names directly.

- [ ] **Step 1: Create `settings.lua`**

```lua
-- settings.lua is its own data-stage file, loaded before data.lua,
-- same as Tarantulator's own settings.lua (confirmed real shape by
-- reading that mod's actual file) -- but runtime-global here, not
-- startup, since this is a shared gameplay toggle that should take
-- effect immediately without restarting the save.
data:extend({
  {
    type = "bool-setting",
    name = "mega-mech-armor-combat-mode-available",
    setting_type = "runtime-global",
    default_value = true,
    order = "a",
  },
  {
    type = "int-setting",
    name = "mega-mech-armor-combat-mode-laser-count",
    setting_type = "runtime-global",
    default_value = 5,
    minimum_value = 1,
    order = "b",
  },
})
```

- [ ] **Step 2: Create `prototypes/combat-mode/equipment-category.lua`**

```lua
-- Dedicated category so the combat-mode laser/tesla equipment can
-- only ever be inserted into the hidden carrier's own grid below --
-- never the player's own armor, never the real mega-mech-armor's own
-- grid. This is what actually prevents grid-space contention and
-- player interaction with combat-mode equipment, not just hiding the
-- carrier entity.
data:extend({
  {
    type = "equipment-category",
    name = "mega-mech-armor-combat-mode",
  },
})
```

- [ ] **Step 3: Create `prototypes/combat-mode/carrier.lua`**

```lua
-- Hidden carrier: a plain "car" (not another spider-vehicle) since
-- the only thing it needs is an equipment_grid field, confirmed
-- available on CarPrototype. Never driven, never rendered
-- meaningfully, never player-selectable. Its own position is
-- teleported to match the real vehicle's every tick while combat mode
-- is active (Task 4), and it's destroyed outright when combat mode
-- ends.
data:extend({
  {
    type = "equipment-grid",
    name = "mega-mech-armor-combat-carrier-grid",
    -- 10x10 = 100 cells, comfortably more than the 5 (configurable,
    -- could be raised) laser + 3 tesla equipment actually need (each
    -- is a 2x2 = 4 cell shape, so 32 cells minimum at default
    -- settings).
    width = 10,
    height = 10,
    equipment_categories = {"mega-mech-armor-combat-mode"},
  },
  {
    type = "car",
    name = "mega-mech-armor-combat-carrier",
    -- Confirmed required fields on CarPrototype: consumption,
    -- effectivity, energy_source, inventory_size, rotation_snap_angle,
    -- rotation_speed. Confirmed required on VehiclePrototype:
    -- braking_force, energy_per_hit_point, friction_force, weight.
    -- All given nominal values -- this entity is teleported by script,
    -- never actually "driven," so none of the movement-physics fields
    -- do anything in practice.
    collision_box = {{0, 0}, {0, 0}},
    collision_mask = {layers = {}},
    flags = {"not-selectable-in-game", "placeable-off-grid", "not-on-map"},
    weight = 1,
    braking_force = 1,
    friction_force = 1,
    energy_per_hit_point = 1,
    consumption = "1W",
    effectivity = 1,
    energy_source = {type = "void"},
    inventory_size = 0,
    rotation_snap_angle = 0,
    rotation_speed = 0,
    max_health = 10,
    equipment_grid = "mega-mech-armor-combat-carrier-grid",
  },
})
```

- [ ] **Step 4: Add the requires to `data.lua`**

```lua
-- Entry point for the data stage. Each task below adds exactly one
-- require() here, in the order the prototypes depend on each other.
require("prototypes.entity.mega-mech-armor")
require("prototypes.equipment-grid")
require("prototypes.recipe")
require("prototypes.technology")
require("prototypes.combat-mode.equipment-category")
require("prototypes.combat-mode.carrier")
```

- [ ] **Step 5: Run the smoke test**

```bash
"/mnt/c/Program Files (x86)/Steam/steamapps/common/Factorio/bin/x64/factorio.exe" --dump-data --mod-directory "C:\repos\_plan_test_mods"
```

(Create the `_plan_test_mods` junction first if it doesn't already exist, same as every earlier task in this mod: `mkdir -p /mnt/c/repos/_plan_test_mods && cmd.exe /c mklink /J "C:\repos\_plan_test_mods\mega-mech-armor" "C:\repos\factorio-mega-mech-armor"`.)

Expected: no error. If `consumption`/`effectivity`/etc. are missing or wrong-typed, this is exactly where it will surface.

- [ ] **Step 6: Verify the settings and carrier actually dumped correctly**

```bash
python3 -c "
import json
data = json.load(open('/mnt/c/Users/dicky/AppData/Roaming/Factorio/script-output/data-raw-dump.json'))
print('bool setting default:', data['bool-setting']['mega-mech-armor-combat-mode-available']['default_value'])
print('int setting default:', data['int-setting']['mega-mech-armor-combat-mode-laser-count']['default_value'])
print('carrier grid:', data['car']['mega-mech-armor-combat-carrier']['equipment_grid'])
print('grid categories:', data['equipment-grid']['mega-mech-armor-combat-carrier-grid']['equipment_categories'])
"
```

Expected: `True`, `5`, `mega-mech-armor-combat-carrier-grid`, `['mega-mech-armor-combat-mode']`.

- [ ] **Step 7: Commit**

```bash
git add settings.lua prototypes/combat-mode/equipment-category.lua prototypes/combat-mode/carrier.lua data.lua
git commit -m "Add combat mode settings, equipment category, and hidden carrier entity"
```

---

### Task 2: Laser and tesla combat-mode equipment

**Files:**
- Modify: `data-final-fixes.lua`

**Interfaces:**
- Consumes: vanilla `personal-laser-defense-equipment` (`__base__/prototypes/equipment.lua`); this mod's own `mega-mech-armor-tesla-gun` (built earlier in this same file, confirmed present by the time this code runs since it's appended after); vanilla `tesla-ammo` item (`__space-age__/prototypes/item.lua`) for its embedded beam/chain action.
- Produces: `active-defense-equipment` prototypes `mega-mech-armor-combat-laser` and `mega-mech-armor-combat-tesla`, both `categories = {"mega-mech-armor-combat-mode"}`. Task 4's control.lua inserts these by name into the carrier's grid.

- [ ] **Step 1: Append to `data-final-fixes.lua`**

```lua
-- Combat Mode's laser equipment: a clone of personal-laser-defense-equipment
-- with double range. max_length inside the beam delivery must be
-- doubled to match -- otherwise the equipment would target enemies up
-- to the new range but the beam itself would visually (and
-- functionally) cut off at the old one.
local laser_source = data.raw["active-defense-equipment"]["personal-laser-defense-equipment"]
if not laser_source then
  error("mega-mech-armor: expected personal-laser-defense-equipment to exist")
end
local combat_laser = util.table.deepcopy(laser_source)
combat_laser.name = "mega-mech-armor-combat-laser"
combat_laser.localised_name = {"equipment-name.mega-mech-armor-combat-laser"}
combat_laser.categories = {"mega-mech-armor-combat-mode"}
combat_laser.attack_parameters.range = combat_laser.attack_parameters.range * 2
combat_laser.attack_parameters.ammo_type.action.action_delivery.max_length =
  combat_laser.attack_parameters.ammo_type.action.action_delivery.max_length * 2

-- Combat Mode's tesla equipment: no vanilla equivalent. Built from two
-- real sources combined -- mega-mech-armor-tesla-gun's own
-- attack_parameters (cooldown, range, source_offset,
-- source_direction_count, ammo_category -- our own already-decided
-- stats), plus tesla-ammo's own ammo_type (the actual chain/beam
-- damage action -- confirmed the gun's own attack_parameters has no
-- embedded action at all, since it's normally item-fed from whatever
-- tesla ammo is loaded; equipment needs a fully self-contained attack,
-- so that embedded action has to come from the real ammo item instead).
local tesla_gun = data.raw.gun["mega-mech-armor-tesla-gun"]
if not tesla_gun then
  error("mega-mech-armor: expected mega-mech-armor-tesla-gun to exist (built earlier in this same file)")
end
local tesla_ammo = data.raw.ammo["tesla-ammo"]
if not tesla_ammo then
  error("mega-mech-armor: expected tesla-ammo to exist")
end

local combat_tesla = util.table.deepcopy(laser_source)
combat_tesla.name = "mega-mech-armor-combat-tesla"
combat_tesla.localised_name = {"equipment-name.mega-mech-armor-combat-tesla"}
combat_tesla.categories = {"mega-mech-armor-combat-mode"}
combat_tesla.attack_parameters = util.table.deepcopy(tesla_gun.attack_parameters)
combat_tesla.attack_parameters.ammo_type = util.table.deepcopy(tesla_ammo.ammo_type)
-- active-defense-equipment requires "automatic" (not present on a gun's
-- own attack_parameters at all); personal-laser-defense-equipment's
-- own "50kJ" energy_consumption is reused as a reasonable starting
-- balance value for tesla too, pending manual playtesting.
combat_tesla.attack_parameters.ammo_type.energy_consumption = "50kJ"

data:extend({combat_laser, combat_tesla})
```

- [ ] **Step 2: Add locale entries**

Read `locale/en/mega-mech-armor.cfg`, then add an `[equipment-name]` section:

```ini
[equipment-name]
mega-mech-armor-combat-laser=Mega mech armor combat laser
mega-mech-armor-combat-tesla=Mega mech armor combat tesla
```

- [ ] **Step 3: Run the smoke test**

```bash
"/mnt/c/Program Files (x86)/Steam/steamapps/common/Factorio/bin/x64/factorio.exe" --dump-data --mod-directory "C:\repos\_plan_test_mods"
```

Expected: no error.

- [ ] **Step 4: Verify the dumped equipment matches expectations**

```bash
python3 -c "
import json
data = json.load(open('/mnt/c/Users/dicky/AppData/Roaming/Factorio/script-output/data-raw-dump.json'))
laser = data['active-defense-equipment']['mega-mech-armor-combat-laser']
print('laser range:', laser['attack_parameters']['range'])
print('laser max_length:', laser['attack_parameters']['ammo_type']['action']['action_delivery']['max_length'])
print('laser categories:', laser['categories'])
tesla = data['active-defense-equipment']['mega-mech-armor-combat-tesla']
print('tesla cooldown:', tesla['attack_parameters']['cooldown'])
print('tesla range:', tesla['attack_parameters']['range'])
print('tesla has chain action:', 'action' in tesla['attack_parameters']['ammo_type'])
print('tesla categories:', tesla['categories'])
"
```

Expected: laser range `30`, max_length `30`, categories `['mega-mech-armor-combat-mode']`; tesla cooldown `15`, range `36`, `action` present, categories `['mega-mech-armor-combat-mode']`.

- [ ] **Step 5: Confirm isolation (Review Focus #1) — deliberately try the wrong grid**

Temporarily change `mega-mech-armor-combat-laser`'s `categories` to `{"armor"}`, re-run `--dump-data`, and manually note (no automated check possible here, since grid-fit validation happens at runtime, not data-stage) that this would be the bug to watch for in Task 4's manual QA: equipment with the wrong category showing up as insertable into the player's own armor. Revert the change immediately (`git checkout -- data-final-fixes.lua` if needed, or re-apply Step 1's content) — this step is a reminder/sanity-check of the mechanism, not a permanent code change.

- [ ] **Step 6: Commit**

```bash
git add data-final-fixes.lua locale/en/mega-mech-armor.cfg
git commit -m "Add combat mode laser and tesla equipment"
```

---

### Task 3: Toggle shortcut and hotkey

**Files:**
- Create: `prototypes/combat-mode/shortcut.lua`
- Modify: `data.lua`
- Modify: `locale/en/mega-mech-armor.cfg`

**Interfaces:**
- Produces: `custom-input` `"mega-mech-armor-toggle-combat-mode"`; `shortcut` `"mega-mech-armor-toggle-combat-mode"`. Task 4's control.lua listens for both.

- [ ] **Step 1: Create `prototypes/combat-mode/shortcut.lua`**

```lua
data:extend({
  {
    type = "custom-input",
    name = "mega-mech-armor-toggle-combat-mode",
    key_sequence = "ALT + SHIFT + Q",
  },
  {
    type = "shortcut",
    name = "mega-mech-armor-toggle-combat-mode",
    action = "lua",
    toggleable = true,
    associated_control_input = "mega-mech-armor-toggle-combat-mode",
    icon = "__mega-mech-armor__/graphics/entity/mega-mech-armor/mega-mech-armor-icon.png",
    icon_size = 64,
    small_icon = "__mega-mech-armor__/graphics/entity/mega-mech-armor/mega-mech-armor-icon.png",
    small_icon_size = 64,
  },
})
```

- [ ] **Step 2: Add the require to `data.lua`**

```lua
require("prototypes.combat-mode.equipment-category")
require("prototypes.combat-mode.carrier")
require("prototypes.combat-mode.shortcut")
```

- [ ] **Step 3: Add locale entries**

```ini
[controls]
mega-mech-armor-toggle-combat-mode=Toggle Mega Mech Armor combat mode

[shortcut-name]
mega-mech-armor-toggle-combat-mode=Toggle Mega Mech Armor combat mode
```

- [ ] **Step 4: Run the smoke test**

```bash
"/mnt/c/Program Files (x86)/Steam/steamapps/common/Factorio/bin/x64/factorio.exe" --dump-data --mod-directory "C:\repos\_plan_test_mods"
```

Expected: no error. If `icon`/`small_icon` are missing this is where it surfaces (both practically required despite the docs marking them conditionally optional).

- [ ] **Step 5: Commit**

```bash
git add prototypes/combat-mode/shortcut.lua data.lua locale/en/mega-mech-armor.cfg
git commit -m "Add combat mode toggle shortcut and hotkey"
```

---

### Task 4: control.lua — activation, teardown, and all trigger points

**Files:**
- Create: `scripts/combat-mode.lua`
- Modify: `control.lua`

**Interfaces:**
- Consumes: `defines.events.on_player_driving_changed_state` (already handled in `control.lua` for color sync — this task adds a second concern to the same handler, not a duplicate registration), `defines.events.on_lua_shortcut`, custom-input event `"mega-mech-armor-toggle-combat-mode"`, `defines.events.on_runtime_mod_setting_changed`. Entity names from Tasks 1–3: `mega-mech-armor-combat-carrier`, `mega-mech-armor-combat-laser`, `mega-mech-armor-combat-tesla`, `mega-mech-armor-combat-mode-available`, `mega-mech-armor-combat-mode-laser-count`.
- Produces: `storage.mega_mech_armor_combat_mode[player_index] = {vehicle, carrier, robots}`, internal to this module.

- [ ] **Step 1: Create `scripts/combat-mode.lua`**

```lua
local combat_mode = {}

-- Real, unmodified vanilla combat-robot entity names -- never cloned,
-- per the design: equipment-grid auto-fire has no shot cap and would
-- spawn these unboundedly over time, so they're script-spawned once
-- with a fixed count instead.
local ROBOT_COUNTS = {
  defender = 5,
  distractor = 3,
  destroyer = 5,
}

-- ~2,270 years of ticks at 60/second -- not the field's actual
-- ceiling (uint64), just a large constant that outlasts any
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

-- Defensive about entity.valid throughout (Review Focus #2) -- a
-- robot mid-attack or a carrier mid-despawn when teardown runs should
-- never error here.
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

-- Called from control.lua's own on_player_driving_changed_state
-- handler (Review Focus #3) -- covers both a normal exit and the
-- vehicle being destroyed out from under the player (that event's own
-- documented exception doesn't apply to teardown here; we're reacting
-- to the player's state, not assuming the vehicle itself is still
-- valid).
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
-- Only iterates players currently in combat mode, not all players
-- every tick.
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

-- Review Focus #5: the global availability setting turning off mid-game
-- must not leave orphaned carriers/robots for players currently active.
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
```

- [ ] **Step 2: Wire it into `control.lua`**

Read the current `control.lua`, then add the require and the four new event registrations, folding the driving-state-changed call into the *existing* handler rather than registering a second one:

```lua
local combat_mode = require("scripts.combat-mode")

-- (existing sync_color function and its comment block stay as-is)

script.on_event(defines.events.on_player_driving_changed_state, function(event)
  local player = game.get_player(event.player_index)
  if not player then
    return
  end
  sync_color(player.physical_vehicle, player.color)
  combat_mode.on_driving_state_changed(player)
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
end)

script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
  combat_mode.on_setting_changed(event.setting)
end)
```

- [ ] **Step 3: Run the smoke test**

```bash
"/mnt/c/Program Files (x86)/Steam/steamapps/common/Factorio/bin/x64/factorio.exe" --dump-data --mod-directory "C:\repos\_plan_test_mods"
```

Expected: no error (confirms the mod as a whole, including `scripts/combat-mode.lua`'s `require`, still loads — `--dump-data` doesn't execute `control.lua`, but a `require` typo or syntax error in a file control.lua pulls in would still need to parse cleanly for Lua to accept it structurally; the real control.lua execution check is Step 4).

- [ ] **Step 4: Headless runtime check — reproduce the full activate/teardown cycle**

```bash
cat > /tmp/combat_mode_check.lua << 'EOF'
script.on_init(function()
  local surface = game.surfaces[1]
  local vehicle = surface.create_entity({name = "mega-mech-armor", position = {0, 0}, force = "player"})
  storage.check_vehicle = vehicle
end)
script.on_nth_tick(5, function(event)
  if event.tick == 5 then
    -- Simulate activation directly (no real player in headless mode)
    local ok, err = pcall(function()
      local combat_mode = require("scripts.combat-mode")
      storage.mega_mech_armor_combat_mode = storage.mega_mech_armor_combat_mode or {}
      storage.mega_mech_armor_combat_mode[1] = {
        vehicle = storage.check_vehicle,
        carrier = storage.check_vehicle.surface.create_entity({
          name = "mega-mech-armor-combat-carrier",
          position = storage.check_vehicle.position,
          force = storage.check_vehicle.force,
        }),
        robots = {},
      }
      local grid = storage.mega_mech_armor_combat_mode[1].carrier.grid
      local inserted_laser = grid.put({name = "mega-mech-armor-combat-laser"})
      local inserted_tesla = grid.put({name = "mega-mech-armor-combat-tesla"})
      helpers.write_file("combat-mode-check.txt", "laser inserted: " .. tostring(inserted_laser) .. "\n", true)
      helpers.write_file("combat-mode-check.txt", "tesla inserted: " .. tostring(inserted_tesla) .. "\n", true)
      local robot = storage.check_vehicle.surface.create_entity({
        name = "defender",
        position = storage.check_vehicle.position,
        force = storage.check_vehicle.force,
        quality = storage.check_vehicle.quality,
      })
      robot.destructible = false
      robot.time_to_live = 0xFFFFFFFF
      robot.combat_robot_owner = storage.check_vehicle
      helpers.write_file("combat-mode-check.txt", "robot spawned, destructible=" .. tostring(robot.destructible) .. " owner_valid=" .. tostring(robot.combat_robot_owner.valid) .. "\n", true)
    end)
    if not ok then
      helpers.write_file("combat-mode-check.txt", "ERROR: " .. tostring(err) .. "\n", true)
    end
  end
end)
EOF
cp control.lua /tmp/control.lua.bak
cat control.lua /tmp/combat_mode_check.lua > /tmp/control_with_check.lua
cp /tmp/control_with_check.lua control.lua
rm -f "/mnt/c/Users/dicky/AppData/Roaming/Factorio/script-output/combat-mode-check.txt"
mkdir -p /mnt/c/repos/_plan_test_mods/_saves
"/mnt/c/Program Files (x86)/Steam/steamapps/common/Factorio/bin/x64/factorio.exe" --create "C:\repos\_plan_test_mods\_saves\combatcheck.zip" --mod-directory "C:\repos\_plan_test_mods"
"/mnt/c/Program Files (x86)/Steam/steamapps/common/Factorio/bin/x64/factorio.exe" --benchmark "C:\repos\_plan_test_mods\_saves\combatcheck.zip" --benchmark-ticks 10 --mod-directory "C:\repos\_plan_test_mods"
cp /tmp/control.lua.bak control.lua
cat "/mnt/c/Users/dicky/AppData/Roaming/Factorio/script-output/combat-mode-check.txt"
rm -rf /mnt/c/repos/_plan_test_mods/_saves /tmp/combat_mode_check.lua /tmp/control_with_check.lua /tmp/control.lua.bak
```

Expected: `laser inserted: true`, `tesla inserted: true`, `robot spawned, destructible=false owner_valid=true`, no `ERROR:` line. This is the real proof that the equipment actually fits in the grid (Review Focus #1, the mechanical half — category matching) and that the robot ownership/destructibility calls succeed against a real engine, not just type-check in isolation.

- [ ] **Step 5: Commit**

```bash
git add scripts/combat-mode.lua control.lua
git commit -m "Add combat mode activation, teardown, and all trigger points"
```

---

### Task 5: Manual QA and native-behavior verification

No code changes — this closes out the open items the design doc explicitly carried into implementation, plus the full proposal checklist. None of these are verifiable headlessly.

- [ ] **Step 1: Verify `follows_player` tracks a vehicle owner correctly (design doc open item #2)**

In a real game: drive a mega mech armor manually, toggle combat mode on, move the vehicle around, and confirm the Defender and Destroyer robots actually follow it (not drift away, not stay fixed at the activation point). Distractor is expected to stay put (matches real distractor-capsule behavior, confirmed via its own prototype lacking `follows_player`).

- [ ] **Step 2: Verify equipment isolation end-to-end (Review Focus #1, the player-facing half)**

With combat mode active, open the mega mech armor's own equipment grid GUI and confirm `mega-mech-armor-combat-laser`/`-tesla` do **not** appear as insertable options there, and open the player's own armor grid (if wearing any) and confirm the same. Then confirm the laser/tesla *do* auto-fire at nearby enemies once combat mode is on (the actual payoff of the whole equipment-grid approach).

- [ ] **Step 3: Verify toggling off mid-combat (Review Focus #2)**

Engage enemies with combat mode on so at least one robot or the laser/tesla equipment is actively mid-attack, then toggle combat mode off (hotkey or shortcut button) and confirm no error appears and everything despawns cleanly.

- [ ] **Step 4: Verify vehicle destruction while combat mode is active (Review Focus #3)**

With combat mode on, have the mega mech armor destroyed (e.g. via console `/c` damage command or enemy fire) while the player is still in it, and confirm the carrier and robots are cleaned up rather than left behind as orphans.

- [ ] **Step 5: Verify two simultaneous players don't cross-contaminate (Review Focus #4)**

With two mega mech armors and two players (or one player plus a console-spawned second character/vehicle), activate combat mode on both and confirm each player's robots/carrier track only their own vehicle.

- [ ] **Step 6: Verify the global setting toggling off mid-game (Review Focus #5)**

With combat mode active for at least one player, use the mod settings menu to turn `mega-mech-armor-combat-mode-available` off, and confirm that player's combat mode is force-deactivated immediately (shortcut un-toggles, carrier/robots despawn) without needing them to press the hotkey again.

- [ ] **Step 7: Full proposal checklist pass**

Walk through `docs/proposal/combat-mode.md` bullet by bullet once, end to end: default hotkey `alt+shift+q` works, the laser count setting actually changes how many laser equipment pieces get inserted, 2x laser range is noticeably longer than un-doubled personal laser defense, tesla chains between enemies the same way a real tesla weapon does, and the 5/3/5 robot counts are exactly right (not more, not fewer) each time combat mode activates.

- [ ] **Step 8: Tune the tesla equipment's energy cost**

Task 2's `50kJ` `energy_consumption` for the tesla equipment was reused from the laser equipment as a starting value, not derived from any real tesla-specific source (tesla-ammo is a consumable item with no equivalent "energy per shot" field to copy). Adjust in `data-final-fixes.lua` if it reads as obviously too cheap or too expensive relative to the laser equipment during playtesting.
