# JGT-1 · Milestone 1 plan: first playable slice

Goal: a small, original SAO-inspired 2D RPG slice. The player walks a 3/4-view zone of floor 1 with right-click move,
fights one telegraphing enemy type with basic attack + Q/W/R + E dash, picks up a few items, and can die. On death
a new character starts in the same world. Tests run headless from the CLI. No SAO names, characters or logos anywhere.

## 1. Architecture (short)

```
project.godot            Godot 4 project (pinned version, see T2)
CLAUDE.md                rules for coders (T5)
tools/                   install_godot.sh, test.sh, screenshot.sh (no game code)
addons/gut/              GUT, vendored at a pinned version
data/                    ALL game data, JSON, hand-edited
  skills.json items.json enemies.json balance.json
  zones/floor1/<zone>.map   ASCII tile grid (one zone per file)
  zones/floor1/<zone>.json  zone meta: legend, spawns, entry point, exits
  sprites/layout_lpc.json   sprite sheet layout (frame size, rows per anim/direction)
src/logic/               PURE logic: RefCounted classes only, no Node, no Input, no rendering
  data/  sim/  combat/  items/  save/
src/view/                Nodes that DRAW logic state (tilemap, sprites, telegraphs, HUD)
src/input/               turns mouse/keys into logic Commands
scenes/                  main.tscn and view scenes (.tscn text)
assets/                  art/audio (Git LFS), with assets/CREDITS.md
test/unit/ test/integration/   GUT tests
```

- **Logic vs rendering.** `src/logic` holds a deterministic simulation: `WorldSim.step(dt)` gets a queue of
  `Command`s (`MoveTo(point)`, `AttackTarget(id)`, `CastSkill(slot, aim_point)`, `Dash(aim_point)`) and emits
  `Event`s (damage, death, telegraph_start, item_dropped...). Views only read sim state and events. Input only
  creates Commands. A future server runs the same `src/logic` without `src/view`/`src/input`. Rule: nothing in
  `src/logic` may reference `Node`, `Input`, `get_tree()`, textures or scenes (a test checks this, T6).
- **Units.** Logic works in tile units (float `Vector2`), fixed tick (e.g. 30 Hz, from `balance.json`). The view
  maps tiles to pixels. The "3/4 / LoL angle" is an art convention (tall sprites, Y-sort) on an orthogonal grid;
  the camera follows the player at a fixed offset, no rotation.
- **Data.** JSON files loaded by `DataRegistry` with validation (unknown ids, missing fields = load error with
  file + key). No game numbers in code; tunables live in `balance.json`.
- **Save model.** One slot = one world. `user://saves/<slot>/world.json` (version, seed, floors unlocked,
  bosses defeated, cemetery[], merchant/NPC stock, world containers) and
  `user://saves/<slot>/characters/<char_id>.json` (status alive|dead, name, appearance layers, level/xp, stats,
  inventory, equipment, position/zone). Every item instance has a unique `uid` and an `owner`
  (`character:<id>`, `merchant:<id>`, `container:<id>`, `ground:<zone>`), so items can move between owners.
  Autosave on zone load, item change and death; writes are atomic (temp file + rename). Every file has `"version"`.

## 2. Tasks

Legend: **Deps** = must be merged first. **Par** = can run in parallel with the listed tasks (disjoint files).
Default verify for every task: `tools/test.sh` exits 0 and Godot loads the project without script errors.

### Setup

**T1 · Git repo + LFS.** Deps: none. Files: `.gitignore`, `.gitattributes`, `README.md`.
Approach: `git init -b main`; `.gitignore` for `.godot/`, `.tools/`, `*.import` cache, `export/`, `user://` copies;
`.gitattributes` tracks `*.png *.wav *.ogg *.mp3 *.aseprite` via LFS. git-lfs is NOT installed on this machine
(`pacman -S git-lfs` needs the owner's OK), then `git lfs install --local`.
AC: `git lfs track` lists the patterns; `git status` clean after first commit (git-coder commits).
Verify: `git check-attr filter assets/x.png` reports `lfs`.

**T2 · Pinned Godot binary.** Deps: T1. Files: `tools/install_godot.sh`, `tools/godot-version.txt`.
Approach: script downloads the pinned official Linux x86_64 build from the godotengine GitHub releases into
`.tools/godot/` (gitignored), checks the published SHA-512, makes it executable, prints `--version`. Version: the
latest **4.x stable whose GUT release officially supports it** (coder checks the GUT release notes and records
the exact `4.x.y-stable` + checksum in `godot-version.txt`); the plain build, not .NET. Other tools call
`tools/godot` (wrapper that runs `.tools/godot/<binary>`).
AC: fresh clone + `tools/install_godot.sh` → `tools/godot --version` prints the pinned version; re-running is a no-op.
Verify: run the script twice; `tools/godot --headless --quit` exits 0 on a minimal `project.godot`.

**T3 · GUT + headless test command.** Deps: T2. Files: `addons/gut/**` (vendored, pinned tag),
`.gutconfig.json`, `tools/test.sh`, `test/unit/test_smoke.gd`, `project.godot`.
Approach: vendor GUT at the tag matching T2; `tools/test.sh` runs
`tools/godot --headless -s addons/gut/gut_cmdln.gd -gconfig=.gutconfig.json -gexit` (imports first with
`--headless --import` if needed); exit code = test result. Optional arg filters a test file.
AC: smoke test passes; a deliberately failing assertion makes `test.sh` exit non-zero.
Verify: run `tools/test.sh` both ways (then revert the failing assert).

**T4 · Screenshot command.** Deps: T3. Files: `tools/screenshot.sh`, `src/view/debug/screenshot_runner.gd`.
Approach: `xvfb-run -a -s "-screen 0 1280x720x24" tools/godot --rendering-driver opengl3 -- --screenshot=out.png --frames=60 [--scene=...]`;
runner waits N frames, saves `get_viewport().get_texture().get_image()` to the path, quits. Output goes to
`.screenshots/` (gitignored).
AC: produces a non-black 1280x720 PNG of the main scene (any placeholder content).
Verify: run the script; open the PNG (agents read the image).

**T5 · Project rules for coders.** Deps: T2-T4 (needs real commands). Par: none. Files: `CLAUDE.md`.
Content: pinned Godot version, "Godot 4 syntax only" (typed GDScript, `@export`, `await`, no `yield`/`onready var`
without `@`), the logic/view/input boundary rule, data-in-JSON rule, test/screenshot commands, folder layout,
originality rule (no SAO names/characters/logos), LPC credit rule, "every logic change ships with a GUT test".
AC: ≤ 80 lines, every command in it runs as written.

### Logic core (no rendering; all tests headless)

**T6 · DataRegistry + boundary check.** Deps: T5. Files: `src/logic/data/data_registry.gd`,
`data/balance.json`, `test/unit/test_data_registry.gd`, `test/unit/test_logic_boundary.gd`.
Approach: load all `data/*.json` into typed dictionaries by id; `validate()` returns a list of errors with
file + key. Boundary test greps `src/logic/**/*.gd` for `extends Node`, `Input.`, `get_tree`, `load("res://scenes`.
AC: bad id / missing field in a fixture gives a clear error; boundary test fails if a forbidden token is added.

**T7 · Zone format + loader.** Deps: T6. Par: T8 after T6. Files: `src/logic/sim/zone.gd`,
`data/zones/floor1/test_small.map|.json`, `test/unit/test_zone.gd`.
Approach: `.map` is an ASCII grid; the `.json` legend maps chars to tile types (walkable, blocks, decor id);
meta holds `entry`, `spawns[]` (enemy id, tile, respawn s), `exits[]`. Builds an `AStarGrid2D` for walkable tiles.
AC: loads the fixture; `is_walkable`, `find_path(a,b)` around a wall; malformed map (ragged rows, unknown char) errors.

**T8 · WorldSim, Commands, movement.** Deps: T6, T7. Files: `src/logic/sim/world_sim.gd`, `entity.gd`,
`commands.gd`, `test/unit/test_movement.gd`.
Approach: entities (id, kind, pos, speed, hp...) in a dict; `step(dt)` processes commands at a fixed tick;
`MoveTo` follows the A* path at `speed` tiles/s; a new command replaces the current one (LoL style).
AC: entity reaches target in expected ticks ±1; path avoids walls; unreachable target = moves to nearest reachable.

**T9 · Stats + basic attack.** Deps: T8. Files: `src/logic/combat/combat.gd`, `stats.gd`,
`data/balance.json`, `test/unit/test_basic_attack.gd`.
Approach: `AttackTarget(id)` moves into range then attacks every `attack_interval` (attack speed, not a
cooldown); damage = formula from `balance.json` (atk, weapon, defense). Emits `damage` / `death` events.
AC: out of range → approaches then hits; damage matches formula; target death stops the attack; dead entities ignore commands.

**T10 · Data-driven skills (Q/W/R).** Deps: T9. Par: T11. Files: `src/logic/combat/skill_system.gd`,
`data/skills.json`, `test/unit/test_skills.gd`.
Approach: skill = {id, name, cooldown, cast_time, shape: line|cone|circle, range, width/angle/radius, effects:
[damage{mult}|heal{amount}|buff{stat,mult,duration}]}. `CastSkill(slot, aim)` checks cooldown, resolves the
shape at `aim` direction, applies effects. Start with 3 original skills (2 damage, 1 support).
AC: cooldown blocks recast and expires on time; cone/line hit only entities inside; heal capped at max hp;
adding a 4th skill in JSON needs no code change (test with a fixture skill).

**T11 · Dash (E).** Deps: T9. Par: T10. Files: `src/logic/combat/dash.gd`, `data/balance.json`, `test/unit/test_dash.gd`.
Approach: `Dash(aim)` moves `dash_distance` tiles toward aim over `dash_duration`, stops at walls,
cooldown `dash_cooldown`; cancels current move/attack; **no invincibility** (damage still applies mid-dash).
AC: distance/cooldown from JSON; wall stops it; hit during dash still deals damage.

**T12 · Enemy with telegraphed attack.** Deps: T9. Par: T10, T11. Files: `src/logic/sim/enemy_ai.gd`,
`data/enemies.json`, `test/unit/test_enemy_ai.gd`.
Approach: state machine idle → chase (aggro radius) → windup → active → recovery → chase; attack shape
and timings from JSON; the hit area is **locked at windup start** (so the player can step out); emits
`telegraph_start{shape, duration}`. Recovery = attack window (optional `recovery_damage_mult`). One original enemy type.
AC: player outside the locked area at `active` takes no damage; inside takes damage; timings match JSON; leash/reset when far.

**T13 · Items + inventory + ownership.** Deps: T9. Par: T10-T12. Files: `src/logic/items/item_db.gd`,
`inventory.gd`, `loot.gd`, `data/items.json`, `test/unit/test_items.gd`.
Approach: item defs (id, name, type weapon|armor|consumable, floor_tier, stats/effects); instances have `uid`
+ `owner`. Enemy drops from loot table → `ground:<zone>`; pickup when walking over/clicking; equip weapon/armor
changes stats; potion heals. ~5 original items.
AC: drop → pickup changes owner; equip changes damage; potion consumed once; uid unique across the world.

### Save + permadeath

**T14 · World/Character save model.** Deps: T13. Files: `src/logic/save/world_state.gd`,
`character_state.gd`, `save_store.gd`, `test/unit/test_save.gd`.
Approach: `to_dict()/from_dict()` with `version`; `SaveStore` reads/writes the layout of section 1 under a
configurable root (tests use a temp dir under `user://test_saves/`, deleted after); atomic write.
AC: round-trip equals; world and character in separate files; corrupt/old-version file → clear error, no crash.

**T15 · Permadeath flow.** Deps: T14, T12. Files: `src/logic/save/lifecycle.gd`, `test/integration/test_permadeath.gd`.
Approach: on player `death` event: character `status=dead` (file kept, read-only), cemetery entry
{name, level, zone, cause, date, appearance}, autosave; the character's items move to the world per the owner's
rule (placeholder: a `merchant:floor1_*` stock, see Q2); `new_character(name, appearance)` spawns at floor 1 entry.
World flags (e.g. a killed-enemy counter, `bosses_defeated`) persist.
AC: integration test: create world → char A picks item → dies → cemetery has A → item owner no longer A → char B at floor 1 entry, same world file, A cannot be loaded as playable.

### View + input (each checked by screenshot + manual run)

**T16 · Main scene + zone rendering + camera.** Deps: T7, T4. Par: T17. Files: `scenes/main.tscn`,
`src/view/zone_view.gd`, `src/view/game_camera.gd`, `assets/tiles/` (placeholder), `project.godot`.
Approach: `TileMapLayer` filled from `Zone`; Y-sort root for entities; camera follows player at fixed offset/zoom from `balance.json`.
AC: screenshot shows the zone; camera centred on the player.

**T17 · Layered sprite system.** Deps: T6. Par: T16. Files: `src/view/layered_sprite.gd`,
`data/sprites/layout_lpc.json`, `assets/characters/` (LPC subset), `assets/CREDITS.md`, `test/unit/test_sprite_layout.gd`.
Approach: N stacked `Sprite2D`/`AnimatedSprite2D` layers (body, hair, clothes, armor, weapon) sharing one layout
(frame size, row per anim+direction: walk/slash/hurt × up/left/down/right). Appearance = dict of layer→sheet.
Swapping sheets needs no code change. CREDITS lists every LPC file, author, license.
AC: unit test: layout maps (anim, dir, frame) → correct region; screenshot shows a composed character.

**T18 · Input controller.** Deps: T8, T16. Files: `src/input/player_input.gd`, `project.godot` (InputMap),
`test/unit/test_player_input.gd`.
Approach: right-click → pick enemy under cursor (`AttackTarget`) else `MoveTo(ground)`; Q/W/R → `CastSkill(slot, mouse_tile)`;
E → `Dash(mouse_tile)`; screen→tile conversion in one helper. Hold right-click repeats move (LoL feel).
AC: unit test feeds synthetic events and asserts the emitted Commands.

**T19 · Entity views + telegraphs.** Deps: T12, T17, T18. Files: `src/view/entity_view.gd`, `telegraph_view.gd`,
`floating_text.gd`, `scenes/entity.tscn`.
Approach: one view per sim entity, interpolated position, anim/direction from velocity/state; telegraph =
red ground shape that fills over the windup; damage numbers; small HP bar.
AC: screenshot during an enemy windup shows the telegraph shape where the hit will land.

**T20 · HUD + death screen.** Deps: T15, T19. Files: `scenes/hud.tscn`, `src/view/hud.gd`, `death_screen.gd`.
Approach: HP bar, Q/W/R/E slots with cooldown sweep, simple inventory list (equip/use), death screen showing
the cemetery entry and a "New character" name field.
AC: cooldown visibly counts down; death → name → new char in same world.

**T21 · Slice zone + save slot menu.** Deps: T15, T16. Par: T19/T20 (data only + menu). Files:
`data/zones/floor1/<slice>.map|.json`, `scenes/title.tscn`, `src/view/title_menu.gd`.
Approach: hand-built slice (see Q1), ~60×40 tiles, 6-10 enemy spawns, a merchant spot, a cemetery marker.
Title: New world / Continue world (slot 1) → resume living character or create one.
AC: zone loads with no validation errors; quit + continue restores position, inventory and world state.

**T22 · End-to-end check.** Deps: all. Files: `test/integration/test_slice_flow.gd`, `docs/milestone1-check.md`.
Approach: headless scripted run on the real slice zone (move, kill an enemy, loot, cast all skills, dash, die,
new char); plus a screenshot set (title, zone, telegraph, death screen) for the owner's review.
AC: test passes; screenshots attached for owner feedback.

**Parallel summary:** T1→T5 serial. After T6: T7. After T9: T10, T11, T12, T13 in parallel. T16 ∥ T17 (after T6/T7).
T21 zone data can start once T7 is merged. Shared files (`data/balance.json`, `project.godot`) cause conflicts:
each task only appends its own keys/section; the coordinator merges in order.

## 3. Risks and owner questions

Risks
- Godot/GUT version mismatch breaks headless tests → T2/T3 pin both together; never upgrade one alone.
- Headless screenshots: `--headless` has no renderer, so xvfb + `opengl3` is required; may need Mesa (llvmpipe) on CI.
- `.godot/` import cache: first headless run must `--import`, otherwise resources fail to load in tests.
- LPC licenses are mostly CC-BY-SA 3.0 / GPL 3 / OGA-BY; share-alike may affect how art can be redistributed in an
  AppImage and mixing licenses needs care. Mitigation: per-file CREDITS from the LPC generator credits file.
- Logic in tile units + fixed tick must stay deterministic for a future server; float drift in pathing is acceptable now.
- Shared JSON/`project.godot` edits by parallel coders → merge conflicts (see summary).
- 3/4 view on an orthogonal grid is not true LoL perspective; owner may expect something else (Q5).

Questions for the owner (not guessed)
1. Which slice for milestone 1: a city edge (gate, a few houses, cemetery, one merchant) + the first field, or fields only?
2. How do a dead character's items re-enter the world (all to one merchant? spread over merchants/NPCs? delay?).
   Placeholder in T15 until answered.
3. Cemetery entry content: name, level, floor reached, cause of death, appearance, date — which?
4. Save rules: autosave only, no manual reload (true hardcore)? Can the player delete a world? Several slots?
5. Is the camera "3/4 top-down with tall sprites, following the player" enough for the LoL feel? Edge-scrolling or camera lock toggle (LoL "Y")?
6. Numbers for the slice: dash distance/cooldown, cooldown-only skills or also a resource (mana/stamina)?
7. Can I install `git-lfs` system-wide (`pacman -S git-lfs`)? Is downloading the Godot binary from GitHub OK?
8. LPC art licenses (CC-BY-SA/GPL) acceptable for a distributed game, or placeholder art only until original art?
9. Working name for the game (needed for `project.godot`, window title, AppImage)?

## Roadmap (later milestones, rough)
M2 full floor 1 city (houses, shops, merchants, cemetery) · M3 fields + dungeon zones, more enemy types ·
M4 floor 1 boss (original, multi-phase) + boss persistence · M5 character customization UI · M6 headless
balance simulator (attack windows, dodge models) · M7 economy/item flow · M8 floors 2-5 · M9 AppImage packaging.
