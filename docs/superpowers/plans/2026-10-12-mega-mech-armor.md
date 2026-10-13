# Mega Mech Armor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new `spider-vehicle` entity, "Mega Mech Armor" — a flying, remote-drivable, late-game vehicle that reuses mech armor's own art and spidertron's own capabilities, per `docs/proposal/init.md`.

**Architecture:** One `spider-vehicle` prototype with a single invisible leg (no terrain collision at all), torso art reused directly from mech-armor's own baked `character.animations` entry, 7 cloned/renamed vehicle weapons built in `data-final-fixes.lua` for cross-mod ammo robustness, a 19×19 equipment grid with quality-tier size limits enforced in `control.lua` (the engine has no per-prototype quality-grid-size field), and `control.lua` syncing the vehicle's tint to its driver's own player color.

**Tech Stack:** Factorio 2.0 data/control stage Lua modding (Space Age DLC: `space-age`, `quality`).

**Spec:** `docs/proposal/design.md` (and the original request, `docs/proposal/init.md`)

## Global Constraints

- `factorio_version` stays `"2.0"` in `info.json` (already set) — this project targets 2.0, not the 2.1 dual-release pattern used by the Space Age All in One mod.
- Dependencies required: `base >= 2.0.0`, `space-age >= 2.0.0` (mech-armor, teslagun, railgun, fusion-reactor-equipment all live there), `quality >= 2.0.0` (the 5 quality tiers this mod relies on for health/trunk/grid scaling).
- All new prototype names are prefixed `mega-mech-armor` (entity, leg, item, grid, recipe, technology) or `mega-mech-armor-<weapon>` (the 7 cloned guns) — no bare names that could collide with another mod.
- Every numeric baseline (health, trunk size, weapon cooldowns, grid sizes, tech cost) must be derived from a real vanilla value found in the game's own files, not invented — see `docs/proposal/design.md` for the citations; this plan's code comments repeat the key ones inline so the implementer doesn't have to re-derive them.
- No unit-test framework exists for Factorio data-stage modding. Every task's verification step is the same real-engine smoke test: `--dump-data` run from WSL against the real, installed Factorio engine. This catches syntax errors, missing-prototype-reference errors, and schema violations — it does NOT catch `control.lua` runtime logic bugs (those need an actual playtest, called out explicitly in Tasks 6, 7, and 8).

## Review Focus

1. **A player equips something into a lower-tier grid's "dead zone"** (e.g. a normal-quality Mega Mech Armor, equipment dropped into column 16+ or row 18+) — expected: the item is rejected and returned to the player's cursor/inventory, not silently kept in an inoperative cell. Covered in Task 6's control.lua equipment-grid test.
2. **A player drives a Mega Mech Armor whose color was never explicitly set (fresh spawn) before any `on_player_color_changed` event fires** — expected: it still picks up the driver's current color immediately on entering, not just on the next color change. Covered in Task 6 via the `on_player_driving_changed_state` handler, tested by entering the vehicle first and checking color before touching the color picker.
3. **Another mod also defines a gun item named one of our clone targets, or removes/renames one of the 6 source guns we clone from** (`tank-cannon`, `vehicle-machine-gun`, `tank-flamethrower`, `spidertron-rocket-launcher-1`, `teslagun`, `railgun`) — expected: a clear data-stage error naming which source was missing, not a silent `nil` crash deep in `attack_parameters.cooldown`. Covered in Task 5's `clone_gun` guard clause.
4. **A player tries to leave the vehicle while it's hovering over water or lava** — the proposal requires this to be blocked, but `spider-vehicle` entities don't collide with terrain at all here, so vanilla's own exit-safety logic (designed around car-type vehicles) may or may not already cover spider-vehicle sitting over hazards. Not assumed either way — Task 7 is a dedicated manual check before deciding whether `control.lua` needs an explicit `on_player_driving_changed_state` hazard check.
5. **A second Mega Mech Armor is crafted and both are driven by different players in the same game** — expected: each vehicle's color and equipment-grid enforcement apply independently per-entity, never cross-talking (e.g. player A's color change doesn't repaint player B's vehicle). Covered by keying every `control.lua` handler off the specific entity/grid from the event, never off a single cached reference.

---

### Task 1: Mod dependencies, skeleton, and locale

**Files:**
- Modify: `info.json`
- Create: `data.lua`
- Create: `locale/en/mega-mech-armor.cfg`
- Create (symlink, not tracked in git): a Factorio dev-mods test folder for every later task's smoke test

**Interfaces:**
- Produces: `data.lua` as the mod's single data-stage entry point — every later task adds one `require(...)` line to it.

- [ ] **Step 1: Update `info.json` dependencies**

Replace the `dependencies` array:

```json
{
  "name": "mega-mech-armor",
  "version": "0.1.0",
  "title": "Mega Mech Armor",
  "author": "lad338",
  "homepage": "https://github.com/lad338/factorio-mega-mech-armor",
  "description": "Adds mega mech armor.",
  "factorio_version": "2.0",
  "dependencies": [
    "base >= 2.0.0",
    "space-age >= 2.0.0",
    "quality >= 2.0.0"
  ]
}
```

- [ ] **Step 2: Create the mod-directory symlink used by every smoke test in this plan**

```bash
mkdir -p /mnt/c/repos/_plan_test_mods
ln -sfn /mnt/c/repos/factorio-mega-mech-armor /mnt/c/repos/_plan_test_mods/mega-mech-armor
```

This points a throwaway, gitignored-by-location test folder at the real repo via symlink, so every later smoke test always runs against the current working tree with no copy step. It lives outside the repo; nothing to add to `.gitignore`.

- [ ] **Step 3: Create `data.lua`**

```lua
-- Entry point for the data stage. Each task below adds exactly one
-- require() here, in the order the prototypes depend on each other.
```

(Empty of requires for now — Task 2 adds the first one.)

- [ ] **Step 4: Create `locale/en/mega-mech-armor.cfg`**

```ini
[entity-name]
mega-mech-armor=Mega Mech Armor

[item-name]
mega-mech-armor=Mega Mech Armor
mega-mech-armor-cannon=Mega mech armor cannon
mega-mech-armor-machine-gun=Mega mech armor machine gun
mega-mech-armor-flamethrower=Mega mech armor flamethrower
mega-mech-armor-rocket-launcher=Mega mech armor rocket launcher
mega-mech-armor-tesla-gun=Mega mech armor tesla gun
mega-mech-armor-railgun=Mega mech armor railgun

[recipe-name]
mega-mech-armor=Mega Mech Armor

[technology-name]
mega-mech-armor=Mega mech armor

[technology-description]
mega-mech-armor=A flying vehicle that has the whole arsenal of weapons.

[mega-mech-armor]
equipment-grid-too-small=This equipment grid slot isn't unlocked at this quality tier yet.
```

- [ ] **Step 5: Run the smoke test**

```bash
"/mnt/c/Program Files (x86)/Steam/steamapps/common/Factorio/bin/x64/factorio.exe" --dump-data --mod-directory "C:\repos\_plan_test_mods"
```

Expected: completes without any "Incompatible Factorio version," missing-dependency, or Lua error mentioning `mega-mech-armor`. (It will still print normal, unrelated vanilla dump-data output — that's fine, we're only checking our mod doesn't error.)

- [ ] **Step 6: Commit**

```bash
git add info.json data.lua locale/en/mega-mech-armor.cfg
git commit -m "Add mod dependencies, data.lua entry point, and locale skeleton"
```

---

### Task 2: Torso animation module

**Files:**
- Create: `prototypes/entity/mega-mech-armor-animations.lua`
- Modify: `data.lua` (add one require line)

**Interfaces:**
- Consumes: `data.raw.character.character.animations` (populated by `space-age`'s own `mech-armor-animations.lua`, guaranteed loaded first since `space-age` is a hard dependency) — specifically the entry whose `armors` list contains `"mech-armor"`, and that entry's `idle_with_gun_in_air` field (confirmed `RotatedAnimation`-typed, structurally identical to what `SpiderVehicleGraphicsSet.animation` expects).
- Produces: a single `RotatedAnimation` table, returned by `require("prototypes.entity.mega-mech-armor-animations")`, ready to assign directly to `graphics_set.animation` on the Task 3 entity.

- [ ] **Step 1: Create `prototypes/entity/mega-mech-armor-animations.lua`**

```lua
-- Reuses mech-armor's own flying-animation art directly, rather than
-- reimplementing the mech_anim() helper from
-- __space-age__/prototypes/entity/mech-armor-animations.lua (that
-- helper is `local` to its own file and not exported). Both source
-- animation and target field are confirmed RotatedAnimation, so no
-- shape conversion is needed -- only a deep copy plus a scale-up and
-- a static hover shift.

local VEHICLE_SCALE = 1.5 -- 1.5x enlarged mech armor, per the proposal
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
  if not layer.draw_as_shadow then
    layer.shift = HOVER_SHIFT
  end
end

return torso_animation
```

- [ ] **Step 2: Add the require to `data.lua`**

```lua
-- Entry point for the data stage. Each task below adds exactly one
-- require() here, in the order the prototypes depend on each other.
require("prototypes.entity.mega-mech-armor-animations")
```

(This module is actually consumed via its own `require(...)` return value from Task 3's entity file, not used for side effects — but requiring it here too is harmless and keeps every prototype file's load order visible in one place. Task 3 will replace this line with the entity file's own require, which internally requires the animation module.)

- [ ] **Step 3: Run the smoke test**

```bash
"/mnt/c/Program Files (x86)/Steam/steamapps/common/Factorio/bin/x64/factorio.exe" --dump-data --mod-directory "C:\repos\_plan_test_mods"
```

Expected: no error. If you see `"could not find mech-armor's own character animation set"`, double check the `space-age >= 2.0.0` dependency from Task 1 Step 1 is present.

- [ ] **Step 4: Commit**

```bash
git add prototypes/entity/mega-mech-armor-animations.lua data.lua
git commit -m "Add torso animation module reusing mech-armor's flying animation"
```

---

### Task 3: Core entity, leg, and item

**Files:**
- Create: `prototypes/entity/mega-mech-armor.lua`
- Modify: `data.lua` (replace the Task 2 require with this file's)

**Interfaces:**
- Consumes: `require("prototypes.entity.mega-mech-armor-animations")` (Task 2's `RotatedAnimation`); `data.raw["spider-vehicle"].spidertron.resistances` (read directly off the live vanilla prototype, not hand-copied, so it can't drift out of sync).
- Produces: the `spider-vehicle` prototype `"mega-mech-armor"`, the `spider-leg` prototype `"mega-mech-armor-leg"`, and the `item-with-entity-data` prototype `"mega-mech-armor"` — Task 4 references the grid name, Task 5 references the entity name (for `guns`), Task 6 references the entity name in `control.lua`.

- [ ] **Step 1: Create `prototypes/entity/mega-mech-armor.lua`**

```lua
local torso_animation = require("prototypes.entity.mega-mech-armor-animations")

local VEHICLE_SCALE = 1.5

-- +5 percentage points to every resistance type, read live off vanilla
-- spidertron's own resistances rather than hand-copied, so a future
-- Wube rebalance of spidertron can't silently desync ours.
local resistances = {}
for _, r in pairs(data.raw["spider-vehicle"].spidertron.resistances) do
  resistances[#resistances + 1] = {
    type = r.type,
    decrease = r.decrease,
    percent = r.percent + 5,
  }
end

-- max_health = spidertron's own base health (3000) + half of tank's
-- own base health (2000) = 4000. Both source values confirmed in
-- __base__/prototypes/entity/entities.lua. Needs no quality-scaling
-- flags of its own -- max_health scales automatically and generically
-- for every entity via the engine's own quality system (confirmed via
-- real spidertron health 3000/3900/4800/5700/7500 across the 5 tiers).
local BASE_HEALTH = 3000 + (2000 / 2)

-- inventory_size = spidertron's own trunk (80) + mech armor's own
-- inventory_size_bonus (50, from __space-age__/prototypes/item.lua).
-- Same automatic quality-scaling note as max_health above.
local BASE_INVENTORY_SIZE = 80 + 50

local function out_of_map_layer_name()
  for _, candidate in pairs({"out-of-map", "out_of_map"}) do
    if data.raw["collision-layer"][candidate] then
      return candidate
    end
  end
  data:extend({{type = "collision-layer", name = "out-of-map"}})
  return "out-of-map"
end

data:extend({
  {
    type = "spider-vehicle",
    name = "mega-mech-armor",
    icon = "__space-age__/graphics/icons/mech-armor.png",
    icon_size = 256,
    collision_box = {{-1 * VEHICLE_SCALE, -1 * VEHICLE_SCALE}, {1 * VEHICLE_SCALE, 1 * VEHICLE_SCALE}},
    selection_box = {{-1 * VEHICLE_SCALE, -1 * VEHICLE_SCALE}, {1 * VEHICLE_SCALE, 1 * VEHICLE_SCALE}},
    sticker_box = {{-1.5 * VEHICLE_SCALE, -1.5 * VEHICLE_SCALE}, {1.5 * VEHICLE_SCALE, 1.5 * VEHICLE_SCALE}},
    drawing_box_vertical_extension = 3 * VEHICLE_SCALE,
    mined_sound = {filename = "__core__/sound/deconstruct-large.ogg", volume = 0.8},
    open_sound = {filename = "__base__/sound/spidertron/spidertron-door-open.ogg", volume = 0.45},
    close_sound = {filename = "__base__/sound/spidertron/spidertron-door-close.ogg", volume = 0.4},
    weight = 1,
    braking_force = 1,
    friction_force = 1,
    flags = {"placeable-neutral", "player-creation", "placeable-off-grid"},
    minable = {mining_time = 1, result = "mega-mech-armor"},
    max_health = BASE_HEALTH,
    resistances = resistances,
    minimap_representation = {
      filename = "__base__/graphics/entity/spidertron/spidertron-map.png",
      flags = {"icon"},
      size = {128, 128},
      scale = 0.5,
    },
    selected_minimap_representation = {
      filename = "__base__/graphics/entity/spidertron/spidertron-map-selected.png",
      flags = {"icon"},
      size = {128, 128},
      scale = 0.5,
    },
    corpse = "spidertron-remnants",
    dying_explosion = "spidertron-explosion",
    energy_per_hit_point = 1,
    -- Names created by Task 5's data-final-fixes.lua clones. Referencing
    -- them here before they exist is fine -- Factorio validates all
    -- cross-prototype references only after every mod's entire data
    -- stage (data.lua, data-updates.lua, data-final-fixes.lua) has run.
    guns = {
      "mega-mech-armor-cannon",
      "mega-mech-armor-machine-gun",
      "mega-mech-armor-flamethrower",
      "mega-mech-armor-rocket-launcher-1",
      "mega-mech-armor-rocket-launcher-2",
      "mega-mech-armor-tesla-gun",
      "mega-mech-armor-railgun",
    },
    inventory_size = BASE_INVENTORY_SIZE,
    equipment_grid = "mega-mech-armor-equipment-grid",
    trash_inventory_size = 20,
    height = 1.5 * VEHICLE_SCALE,
    torso_rotation_speed = 0.005,
    chunk_exploration_radius = 3,
    selection_priority = 60,
    graphics_set = {
      animation = torso_animation,
    },
    energy_source = {type = "void"},
    movement_energy_consumption = "250kW",
    -- Deliberately NOT setting automatic_weapon_cycling or
    -- chain_shooting_cooldown_modifier -- the proposal explicitly asks
    -- for no chain-fire; all 7 guns fire independently, same as tank's
    -- 3 guns do today.
    spider_engine = {
      legs = {
        {
          leg = "mega-mech-armor-leg",
          mount_position = {0, 0},
          ground_position = {0, 0},
          walking_group = 1,
        },
      },
      military_target = "spidertron-military-target",
    },
    is_military_target = true,
    allow_remote_driving = true,
    allow_passengers = false,
    -- Full flight: no terrain collides with this vehicle at all.
    collision_mask = {layers = {}},
  },
  {
    type = "spider-leg",
    name = "mega-mech-armor-leg",
    localised_name = {"entity-name.mega-mech-armor"},
    collision_box = {{-0.1, -0.1}, {0.1, 0.1}},
    selection_box = {{-0.5, -0.5}, {0.5, 0.5}},
    icon = "__space-age__/graphics/icons/mech-armor.png",
    icon_size = 256,
    -- Invisible, centered, single leg -- no graphics_set at all, and
    -- the leg still collides with nothing except the map edge (added
    -- below) so the torso can fly anywhere.
    collision_mask = {layers = {}},
    target_position_randomisation_distance = 0.25,
    minimal_step_size = 0, -- prevents the single leg "rolling back" after moving
    stretch_force_scalar = 1,
    knee_height = 2.5,
    knee_distance_factor = 0.4,
    initial_movement_speed = 100,
    movement_acceleration = 100,
    max_health = 100,
    base_position_selection_distance = 6,
    movement_based_position_selection_distance = 4,
    selectable_in_game = false,
    alert_when_damaged = false,
    walking_sound_volume_modifier = 0,
    walking_sound_speed_modifier = 1,
  },
  {
    type = "item-with-entity-data",
    name = "mega-mech-armor",
    icon = "__space-age__/graphics/icons/mech-armor.png",
    icon_size = 256,
    subgroup = "transport",
    order = "b[personal-transport]-d[mega-mech-armor]",
    place_result = "mega-mech-armor",
    weight = 2 * tons,
    stack_size = 1,
  },
})

-- Leg still can't walk off the edge of the actual map, same technique
-- the "Space Spidertron" reference mod uses for its own zero-collision leg.
local map_layer = out_of_map_layer_name()
data.raw["spider-leg"]["mega-mech-armor-leg"].collision_mask.layers[map_layer] = true
data.raw["tile"]["out-of-map"].collision_mask.layers[map_layer] = true
```

- [ ] **Step 2: Replace the require in `data.lua`**

```lua
-- Entry point for the data stage. Each task below adds exactly one
-- require() here, in the order the prototypes depend on each other.
require("prototypes.entity.mega-mech-armor")
```

(The animation module from Task 2 is now required transitively, from inside `mega-mech-armor.lua` -- no separate top-level require needed.)

- [ ] **Step 3: Run the smoke test**

```bash
"/mnt/c/Program Files (x86)/Steam/steamapps/common/Factorio/bin/x64/factorio.exe" --dump-data --mod-directory "C:\repos\_plan_test_mods"
```

Expected: no error. The `guns` list references 7 gun items that don't exist until Task 5 -- that's fine and won't error at `--dump-data` time either, since cross-prototype name validation happens after the full data stage finishes loading, same as noted in the code comment above. If this step *does* error about unresolved prototype names at this point, it means that assumption was wrong for this Factorio version -- stop and report back rather than guessing around it.

- [ ] **Step 4: Commit**

```bash
git add prototypes/entity/mega-mech-armor.lua data.lua
git commit -m "Add Mega Mech Armor spider-vehicle, leg, and item prototypes"
```

---

### Task 4: Equipment grid, recipe, and technology

**Files:**
- Create: `prototypes/equipment-grid.lua`
- Create: `prototypes/recipe.lua`
- Create: `prototypes/technology.lua`
- Modify: `data.lua` (add three require lines)

**Interfaces:**
- Produces: `equipment-grid` prototype `"mega-mech-armor-equipment-grid"` (referenced by Task 3's entity, already written), `recipe` prototype `"mega-mech-armor"`, `technology` prototype `"mega-mech-armor"`.

- [ ] **Step 1: Create `prototypes/equipment-grid.lua`**

```lua
-- Sized to the largest (legendary) quality tier; control.lua (Task 6)
-- enforces the smaller per-quality-tier rectangle at runtime, since
-- EquipmentGridPrototype has no per-prototype quality-size field --
-- only a shared, engine-wide quality bonus that every grid-bearing
-- entity in the game would be affected by equally.
data:extend({
  {
    type = "equipment-grid",
    name = "mega-mech-armor-equipment-grid",
    width = 19,
    height = 19,
    equipment_categories = {"armor"},
  },
})
```

- [ ] **Step 2: Create `prototypes/recipe.lua`**

```lua
data:extend({
  {
    type = "recipe",
    name = "mega-mech-armor",
    enabled = false,
    energy_required = 60,
    ingredients = {
      {type = "item", name = "fusion-reactor-equipment", amount = 1},
      {type = "item", name = "spidertron", amount = 1},
      {type = "item", name = "tank", amount = 1},
      {type = "item", name = "teslagun", amount = 1},
      {type = "item", name = "railgun", amount = 1},
    },
    results = {{type = "item", name = "mega-mech-armor", amount = 1}},
  },
})
```

- [ ] **Step 3: Create `prototypes/technology.lua`**

```lua
-- "personal fusion reactor" from the proposal is fusion-reactor-equipment
-- (the equipment-grid-mounted personal version) -- there is no tech
-- literally named personal-fusion-reactor. Confirmed in
-- __space-age__/prototypes/technology.lua.
data:extend({
  {
    type = "technology",
    name = "mega-mech-armor",
    icon = "__space-age__/graphics/technology/mech-armor.png",
    icon_size = 256,
    effects = {
      {type = "unlock-recipe", recipe = "mega-mech-armor"},
    },
    prerequisites = {"fusion-reactor-equipment", "mech-armor", "railgun", "tesla-weapons"},
    unit = {
      count = 10000,
      ingredients = {
        {"automation-science-pack", 1},
        {"logistic-science-pack", 1},
        {"chemical-science-pack", 1},
        {"production-science-pack", 1},
        {"utility-science-pack", 1},
        {"space-science-pack", 1},
        {"metallurgic-science-pack", 1},
        {"agricultural-science-pack", 1},
        {"electromagnetic-science-pack", 1},
        {"cryogenic-science-pack", 1},
      },
      time = 60,
    },
  },
})
```

- [ ] **Step 4: Add the three requires to `data.lua`**

```lua
-- Entry point for the data stage. Each task below adds exactly one
-- require() here, in the order the prototypes depend on each other.
require("prototypes.entity.mega-mech-armor")
require("prototypes.equipment-grid")
require("prototypes.recipe")
require("prototypes.technology")
```

- [ ] **Step 5: Run the smoke test**

```bash
"/mnt/c/Program Files (x86)/Steam/steamapps/common/Factorio/bin/x64/factorio.exe" --dump-data --mod-directory "C:\repos\_plan_test_mods"
```

Expected: no error.

- [ ] **Step 6: Commit**

```bash
git add prototypes/equipment-grid.lua prototypes/recipe.lua prototypes/technology.lua data.lua
git commit -m "Add equipment grid, recipe, and technology prototypes"
```

---

### Task 5: Weapon cloning in data-final-fixes.lua

**Files:**
- Create: `data-final-fixes.lua`

**Interfaces:**
- Consumes: vanilla `gun`-type items `tank-cannon`, `vehicle-machine-gun`, `tank-flamethrower`, `spidertron-rocket-launcher-1`, `teslagun`, `railgun` (all confirmed present in `item.lua`).
- Produces: `gun` items `mega-mech-armor-cannon`, `mega-mech-armor-machine-gun`, `mega-mech-armor-flamethrower`, `mega-mech-armor-rocket-launcher-1`, `mega-mech-armor-rocket-launcher-2`, `mega-mech-armor-tesla-gun`, `mega-mech-armor-railgun` — the exact 7 names Task 3's entity already lists in its `guns` field.

- [ ] **Step 1: Create `data-final-fixes.lua`**

```lua
-- Runs after every mod's own data-updates.lua, regardless of load
-- order, so if another mod ever edits one of these 6 source guns'
-- ammo_category or attack_parameters, we clone from the final result
-- rather than racing it.

local function clone_gun(source_name, new_name, localised_name)
  local source = data.raw.gun[source_name]
  if not source then
    error("mega-mech-armor: expected gun '" .. source_name .. "' to exist (needed to build '" .. new_name .. "') -- did another mod remove or rename it?")
  end
  local clone = util.table.deepcopy(source)
  clone.name = new_name
  clone.localised_name = localised_name
  -- Not separately craftable or placeable -- these only exist as the
  -- vehicle's own built-in guns, same as tank's embedded weapons.
  clone.hidden = true
  -- 4x base fire rate. Computed from the live deep-copied value, not
  -- hardcoded, so it tracks the source if it ever changes.
  clone.attack_parameters.cooldown = clone.attack_parameters.cooldown / 4
  return clone
end

data:extend({
  clone_gun("tank-cannon", "mega-mech-armor-cannon", {"item-name.mega-mech-armor-cannon"}),
  clone_gun("vehicle-machine-gun", "mega-mech-armor-machine-gun", {"item-name.mega-mech-armor-machine-gun"}),
  clone_gun("tank-flamethrower", "mega-mech-armor-flamethrower", {"item-name.mega-mech-armor-flamethrower"}),
  -- 2 clones of the same source tier, sharing one display name --
  -- matches the proposal's literal wording ("2 'Spidertron rocket
  -- launcher'... with new name 'Mega mech armor rocket launcher'")
  -- rather than pulling in all 4 of spidertron's own upgrade tiers.
  clone_gun("spidertron-rocket-launcher-1", "mega-mech-armor-rocket-launcher-1", {"item-name.mega-mech-armor-rocket-launcher"}),
  clone_gun("spidertron-rocket-launcher-1", "mega-mech-armor-rocket-launcher-2", {"item-name.mega-mech-armor-rocket-launcher"}),
  clone_gun("teslagun", "mega-mech-armor-tesla-gun", {"item-name.mega-mech-armor-tesla-gun"}),
  clone_gun("railgun", "mega-mech-armor-railgun", {"item-name.mega-mech-armor-railgun"}),
})
```

- [ ] **Step 2: Run the smoke test**

```bash
"/mnt/c/Program Files (x86)/Steam/steamapps/common/Factorio/bin/x64/factorio.exe" --dump-data --mod-directory "C:\repos\_plan_test_mods"
```

Expected: no error, and this is the point where Task 3's `guns` list finally resolves to real items — if there was ever going to be an "unknown gun" validation error from Task 3's forward references, it would surface here.

- [ ] **Step 3: Verify the clone_gun guard clause (Review Focus #3)**

Temporarily rename one source gun to confirm the error path works, then revert:

```bash
# Temporarily break it on purpose:
sed -i 's/data.raw.gun\["tank-cannon"\]/data.raw.gun["tank-cannon-typo"]/' data-final-fixes.lua
"/mnt/c/Program Files (x86)/Steam/steamapps/common/Factorio/bin/x64/factorio.exe" --dump-data --mod-directory "C:\repos\_plan_test_mods"
```

Expected: a clear error containing `"expected gun 'tank-cannon' to exist"` (not a raw "attempt to index a nil value" from deep inside `attack_parameters`).

```bash
# Revert the deliberate break:
git checkout -- data-final-fixes.lua
```

- [ ] **Step 4: Commit**

```bash
git add data-final-fixes.lua
git commit -m "Clone 7 vehicle weapons for Mega Mech Armor in data-final-fixes.lua"
```

---

### Task 6: control.lua — equipment grid enforcement and color sync

**Files:**
- Create: `control.lua`

**Interfaces:**
- Consumes: `defines.events.on_player_placed_equipment`, `defines.events.on_player_driving_changed_state`, `defines.events.on_player_color_changed` (all confirmed to exist with the fields used below); `LuaEquipment.position`/`.shape` (confirmed `{x,y}` / `{width,height}` tables); `LuaEntity.color` (confirmed writable for `spider-vehicle`); `LuaEquipmentGrid.take` (confirmed returns an `ItemWithQualityCount` or `nil`).
- Produces: the runtime behavior Task 7's manual QA checks against.

- [ ] **Step 1: Create `control.lua`**

```lua
-- Mega Mech Armor's equipment grid is authored at its largest
-- (legendary, 19x19) size -- see prototypes/equipment-grid.lua for why
-- there's no per-prototype way to size it per quality tier. This
-- table is what actually enforces the smaller rectangle per tier.
local QUALITY_GRID_SIZES = {
  normal = {width = 15, height = 17},
  uncommon = {width = 16, height = 17},
  rare = {width = 17, height = 17},
  epic = {width = 18, height = 18},
  legendary = {width = 19, height = 19},
}

local function equipment_exceeds_quality_bounds(equipment, allowed)
  local position = equipment.position
  local shape = equipment.shape
  local max_x = position.x + shape.width - 1
  local max_y = position.y + shape.height - 1
  return max_x >= allowed.width or max_y >= allowed.height
end

local function reject_oversized_equipment(player, grid, equipment)
  local allowed = QUALITY_GRID_SIZES[grid.entity_owner.quality.name]
  if not allowed then
    return
  end
  if not equipment_exceeds_quality_bounds(equipment, allowed) then
    return
  end

  local removed = grid.take({equipment = equipment})
  if not removed then
    return
  end

  local inserted = player.insert({name = removed.name, count = removed.count, quality = removed.quality})
  if inserted < removed.count then
    player.surface.spill_item_stack({
      position = player.position,
      stack = {name = removed.name, count = removed.count - inserted, quality = removed.quality},
    })
  end
  player.print({"mega-mech-armor.equipment-grid-too-small"})
end

script.on_event(defines.events.on_player_placed_equipment, function(event)
  local grid = event.grid
  if not (grid.valid and grid.entity_owner and grid.entity_owner.valid and grid.entity_owner.name == "mega-mech-armor") then
    return
  end
  local player = game.get_player(event.player_index)
  if not player then
    return
  end
  reject_oversized_equipment(player, grid, event.equipment)
end)

local function sync_color(entity, color)
  if entity and entity.valid and entity.name == "mega-mech-armor" then
    entity.color = color
  end
end

-- Covers Review Focus #2: picks up the driver's current color the
-- moment they start driving, not just on their next color change.
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
```

- [ ] **Step 2: Run the smoke test**

```bash
"/mnt/c/Program Files (x86)/Steam/steamapps/common/Factorio/bin/x64/factorio.exe" --dump-data --mod-directory "C:\repos\_plan_test_mods"
```

Expected: no error. Note this only confirms the mod still loads as a whole — `--dump-data` does not execute `control.lua` at all (that only runs inside an actual game), so this step cannot catch bugs in the logic above. That's what Step 3 is for.

- [ ] **Step 3: Manual in-game verification (control.lua has no automated test)**

Install the mod into the real Factorio mods folder (or point a real save at the `_plan_test_mods` directory from Task 1), start a game, research/console-unlock the `mega-mech-armor` technology and craft one, then check:

1. Equip something that fits a normal-quality grid's 15×17 area — confirm it stays.
2. Equip something into column 16+ or row 18+ of that same normal-quality grid — confirm it's rejected and returned to your cursor/inventory, with the `equipment-grid-too-small` message. (Review Focus #1.)
3. Enter the vehicle for the first time, before ever touching the player color picker — confirm the vehicle is already tinted your current player color. (Review Focus #2.)
4. Change your player color while driving — confirm the vehicle updates immediately.
5. Craft and drive a second Mega Mech Armor as a different player (or via `/c game.create_entity` + a second test character) — confirm its color and grid enforcement are independent of the first. (Review Focus #5.)

- [ ] **Step 4: Commit**

```bash
git add control.lua
git commit -m "Add equipment-grid size enforcement and driver color sync"
```

---

### Task 7: Exit-safety check and final manual QA

**Files:** none (verification only; may produce a follow-up code change if Step 1 finds vanilla doesn't already handle this)

- [ ] **Step 1: Check whether vanilla already refuses to disembark over hazards (Review Focus #4)**

In a test game, fly a Mega Mech Armor out over deep water or lava, then try to exit (manually, not via remote control). Vanilla's vehicle-exit logic was written with car-type vehicles in mind, not a vehicle with zero terrain collision — it's not known yet whether it already accounts for this case.

- If the game already refuses the exit (or safely repositions the character): nothing to do, the proposal's requirement is already satisfied natively. Note this finding in a short follow-up commit message for the record.
- If the game lets the character walk out onto water/lava: add a check to `control.lua` on `on_player_driving_changed_state` (the same event Task 6 already handles) that, when a player is about to leave a `mega-mech-armor`, tests whether their landing tile is walkable and blocks the exit (or teleports them back into the vehicle) if not. Write this as its own small follow-up task with its own commit — don't fold it into Task 6 speculatively before knowing it's needed.

- [ ] **Step 2: Full playtest against `docs/proposal/init.md`**

Walk through every bullet in the original proposal once, end to end, in a real game: movement feel (WASD, no steering), spidertron-remote compatibility, vision radius, renaming, color sync (re-check after Task 6's automated-but-unverified logic), all 7 weapons firing independently without chain-shooting, equipment grid behavior at each quality tier you can reach, vehicle logistics requests, trunk size at normal quality (130, per the design doc), and the research/recipe unlock path.

- [ ] **Step 3: Tune the hover shift and scale visually**

Task 2's `HOVER_SHIFT` and `VEHICLE_SCALE` were set to reasonable starting values, not visually tuned. Adjust `util.by_pixel(0, -12)` and `1.5` in `prototypes/entity/mega-mech-armor-animations.lua` / `prototypes/entity/mega-mech-armor.lua` if the in-game look doesn't match intent, per the proposal's own "could be updated after manual testing" allowance.

---

### Task 8: Auto-targeting mode toggle

The proposal's "Auto targeting could be selected from without gunner and with gunner" has no task above it — this closes that gap. `is_military_target = true` plus a non-empty `guns` list (both already set in Task 3) should make the vehicle auto-fire at enemies even when unmanned, matching real spidertron's signature behavior — but that's an assumption about how the engine treats *any* spider-vehicle with those fields, not something confirmed for a non-"spidertron"-named entity yet. Step 1 below verifies it before building the toggle on top of it.

**Files:**
- Create: `prototypes/custom-input.lua`
- Modify: `control.lua`
- Modify: `data.lua` (add one require line)
- Modify: `locale/en/mega-mech-armor.cfg` (add the mode-change message and keybind name)

**Interfaces:**
- Consumes: `defines.events.on_player_driving_changed_state` (already handled in Task 6 — this task adds a second handler for it), a new `custom-input` event `"mega-mech-armor-toggle-auto-targeting"`.
- Produces: `storage.mega_mech_armor_modes[unit_number]` (`"always"` or `"occupied-only"`, default `"always"` when absent) and `storage.mega_mech_armor_entities[unit_number]` (the `LuaEntity`, used by the periodic sweep) — internal to `control.lua`, nothing else in this plan reads them.

- [ ] **Step 1: Verify the two behaviors this task depends on, in a real game**

Spawn a Mega Mech Armor via the console (`/c game.player.surface.create_entity({name = "mega-mech-armor", position = game.player.position, force = game.player.force})`), leave it unmanned near an enemy, and confirm it auto-fires. Then, with a player driving it, run `/c game.player.vehicle.active = false` and confirm it stops firing/moving, then `/c game.player.vehicle.active = true` and confirm it resumes cleanly with no corruption (health, inventory, equipment grid all intact).

- If auto-fire-when-unmanned does *not* happen by default: the "without gunner" mode in Step 2 below needs no extra code (it's just the default state) — remove the `"always"` branch from `sync_vehicle_active_state` below, since there'd be nothing to "turn on."
- If toggling `active` breaks or corrupts anything: stop and report back — the toggle mechanism in Step 2 needs a different approach, and that's a design question, not an implementation detail.

- [ ] **Step 2: Create `prototypes/custom-input.lua`**

```lua
data:extend({
  {
    type = "custom-input",
    name = "mega-mech-armor-toggle-auto-targeting",
    key_sequence = "", -- unbound by default; player assigns a key in the controls settings
  },
})
```

- [ ] **Step 3: Add the require to `data.lua`**

```lua
-- Entry point for the data stage. Each task below adds exactly one
-- require() here, in the order the prototypes depend on each other.
require("prototypes.entity.mega-mech-armor")
require("prototypes.equipment-grid")
require("prototypes.recipe")
require("prototypes.technology")
require("prototypes.custom-input")
```

- [ ] **Step 4: Add the mode-change message and keybind name to `locale/en/mega-mech-armor.cfg`**

```ini
[controls]
mega-mech-armor-toggle-auto-targeting=Toggle Mega Mech Armor auto-targeting mode

[mega-mech-armor]
equipment-grid-too-small=This equipment grid slot isn't unlocked at this quality tier yet.
auto-targeting-mode-always=Auto-targeting: always active, even unmanned.
auto-targeting-mode-occupied-only=Auto-targeting: only while occupied.
```

(This replaces the single `[mega-mech-armor]` section Task 1 created — merge into the same section rather than duplicating the header.)

- [ ] **Step 5: Add the toggle logic to `control.lua`**

```lua
-- Appended to the control.lua Task 6 created.

local function register_vehicle(entity)
  storage.mega_mech_armor_entities = storage.mega_mech_armor_entities or {}
  storage.mega_mech_armor_entities[entity.unit_number] = entity
end

local function forget_vehicle(unit_number)
  if storage.mega_mech_armor_entities then
    storage.mega_mech_armor_entities[unit_number] = nil
  end
  if storage.mega_mech_armor_modes then
    storage.mega_mech_armor_modes[unit_number] = nil
  end
end

local function on_mega_mech_armor_built(entity)
  if entity.valid and entity.name == "mega-mech-armor" then
    register_vehicle(entity)
  end
end

script.on_event(defines.events.on_built_entity, function(event)
  on_mega_mech_armor_built(event.entity)
end)
script.on_event(defines.events.on_robot_built_entity, function(event)
  on_mega_mech_armor_built(event.entity)
end)
script.on_event(defines.events.script_raised_built, function(event)
  on_mega_mech_armor_built(event.entity)
end)

script.on_event(defines.events.on_entity_died, function(event)
  if event.entity.valid and event.entity.name == "mega-mech-armor" then
    forget_vehicle(event.entity.unit_number)
  end
end)
script.on_event(defines.events.on_player_mined_entity, function(event)
  if event.entity.valid and event.entity.name == "mega-mech-armor" then
    forget_vehicle(event.entity.unit_number)
  end
end)

local function get_target_vehicle(player)
  if player.vehicle and player.vehicle.valid and player.vehicle.name == "mega-mech-armor" then
    return player.vehicle
  end
  if player.selected and player.selected.valid and player.selected.name == "mega-mech-armor" then
    return player.selected
  end
  return nil
end

script.on_event("mega-mech-armor-toggle-auto-targeting", function(event)
  local player = game.get_player(event.player_index)
  if not player then
    return
  end
  local vehicle = get_target_vehicle(player)
  if not vehicle then
    return
  end

  storage.mega_mech_armor_modes = storage.mega_mech_armor_modes or {}
  local current_mode = storage.mega_mech_armor_modes[vehicle.unit_number] or "always"
  local next_mode = current_mode == "always" and "occupied-only" or "always"
  storage.mega_mech_armor_modes[vehicle.unit_number] = next_mode

  if next_mode == "always" then
    vehicle.active = true
  end
  player.print({"mega-mech-armor.auto-targeting-mode-" .. next_mode})
end)

-- Every half-second, any "occupied-only" vehicle with nobody driving
-- gets deactivated (stops auto-fire); re-activation on entering is
-- immediate, handled below via on_player_driving_changed_state rather
-- than waiting for the next sweep.
script.on_nth_tick(30, function()
  local modes = storage.mega_mech_armor_modes
  local entities = storage.mega_mech_armor_entities
  if not modes or not entities then
    return
  end
  for unit_number, mode in pairs(modes) do
    if mode == "occupied-only" then
      local entity = entities[unit_number]
      if entity and entity.valid then
        entity.active = (entity.get_driver() ~= nil)
      else
        forget_vehicle(unit_number)
      end
    end
  end
end)

script.on_event(defines.events.on_player_driving_changed_state, function(event)
  local player = game.get_player(event.player_index)
  if not player then
    return
  end
  -- Color sync (Task 6) still applies here too.
  sync_color(player.vehicle, player.color)

  local vehicle = player.vehicle
  if vehicle and vehicle.valid and vehicle.name == "mega-mech-armor" then
    local mode = storage.mega_mech_armor_modes and storage.mega_mech_armor_modes[vehicle.unit_number]
    if mode == "occupied-only" then
      vehicle.active = true -- a driver just entered
    end
  end
end)
```

This adds a *second* handler for `on_player_driving_changed_state` — Factorio allows multiple `script.on_event` registrations for the same event, both run. Don't delete Task 6's own handler for this event; the color-sync call above duplicates it deliberately for clarity of what belongs to this task, but if you're implementing both tasks in the same session, merge them into one handler body instead of registering twice.

- [ ] **Step 6: Run the smoke test**

```bash
"/mnt/c/Program Files (x86)/Steam/steamapps/common/Factorio/bin/x64/factorio.exe" --dump-data --mod-directory "C:\repos\_plan_test_mods"
```

Expected: no error.

- [ ] **Step 7: Manual in-game verification**

1. Bind the "Toggle Mega Mech Armor auto-targeting mode" key in Factorio's own controls settings (it ships unbound).
2. Toggle a vehicle to "occupied-only" while unmanned near an enemy — confirm it stops firing within half a second.
3. Enter it — confirm it resumes firing immediately, not after another half-second delay.
4. Toggle it back to "always" and exit — confirm it keeps firing while unmanned.
5. Mine the vehicle while it's registered — confirm no leftover `storage` entries linger (`/c game.print(table_size(storage.mega_mech_armor_entities or {}))` before and after, expect it to drop by one).

- [ ] **Step 8: Commit**

```bash
git add prototypes/custom-input.lua control.lua data.lua locale/en/mega-mech-armor.cfg
git commit -m "Add auto-targeting mode toggle (always active vs. occupied-only)"
```
