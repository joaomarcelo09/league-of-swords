# Milestone 2 Check: Floor 1

This is the final check for Milestone 2: a playable floor 1 with the town, the enemy rooms, the boss warden, the locked exit, the merchant, skills and VFX.

## 1. End-to-end logic test

`test/integration/test_floor1_slice.gd` plays floor 1 headless through `WorldSim` alone. It builds no scene and no Node. Every number comes from `data/`: zone, balance, enemies and skills.

| Step | What the test does | What it checks |
| :--- | :--- | :--- |
| 1. Town | New world and new character (`Lifecycle.new_character`), real `floor1` zone, player spawned at `zone.entry` | Entry and merchant tiles are safe, the warden spawned, the boss exit is locked |
| 2. Leave town | A scripted pilot submits `Commands.move_to` towards the boss tile until the player leaves the safe tiles | Player alive, goal reached |
| 3. Save/load #1 | `SaveStore.save_character` + `save_world`, all live objects dropped, then `load_world` + `Lifecycle.load_playable` and a fresh `GameSession` | Position restored exactly, warden still alive |
| 4. Boss room | Walks on from the loaded state until the player is within the warden's `aggro_radius` | Player alive |
| 5. Kill the warden | Pilot uses `attack_target`, Q/W `cast_skill`, R heal when it would not be wasted, and dodges telegraphs (dash, or move out of `attack.range` before the windup ends) | Warden dead, player alive, exactly one `boss_defeated` with the right boss id, kill recorded in `WorldState.bosses_defeated`, Q or W was cast |
| 6. Save/load #2 | Same round trip | Warden does not respawn, exit is unlocked |
| 7. Exit | `move_to` the exit tile | Exactly one `floor_cleared` (`to_zone` and `tile` match the zone data), no `exit_locked` |

With the current data the player reaches the boss room at sim tick ~470. The warden dies at tick ~1430 (about 32 s of fighting at 30 Hz), leaving the player on 75.5/100 HP. The test caps each leg at 600 sim seconds, so a broken pilot fails instead of hanging.

Run it:

```bash
tools/test.sh test_floor1_slice.gd   # this test
tools/test.sh                        # whole suite (exit code is truth)
```

## 2. Screenshots

Captured with `tools/screenshot.sh` (xvfb, 1280x720). Map shots use `--focus-tile=X,Y` on `res://scenes/main.tscn`. HUD shots use the `--preview=` fixtures. Files are in `docs/img/milestone2/` (PNG, tracked by Git LFS).

| View | File | Command |
| :--- | :--- | :--- |
| Town (fountain, houses, Smith Orrin, player) | ![town](img/milestone2/town.png) | `tools/screenshot.sh --focus-tile=8,7 --frames=30 --out=docs/img/milestone2/town.png` |
| Ash Stalker room (north) | ![ash](img/milestone2/room_ash_stalker.png) | `--focus-tile=27,7` |
| Cinder Bat room (north-east) | ![bat](img/milestone2/room_cinder_bat.png) | `--focus-tile=44,7` |
| Bog Slime room (centre) | ![slime](img/milestone2/room_bog_slime.png) | `--focus-tile=27,21` |
| Boss room (Thornback Warden, exit on the east wall) | ![boss](img/milestone2/boss_warden.png) | `--focus-tile=51,33` |
| HUD (HP bar, Q/W/R/E slots, Q cooldown, inventory) | ![hud](img/milestone2/hud.png) | `--preview=hud` |
| HUD boss bar | ![hud boss](img/milestone2/hud_boss.png) | `--preview=hud_boss` |
| Floor-cleared panel | ![cleared](img/milestone2/hud_floor_cleared.png) | `--preview=hud_floor_cleared` |

Note: the main scene has no save-root override, so map shots load the local `user://saves/slot_1`. The check backed that slot up and compared checksums afterwards; it was not changed.

## 3. Known gaps

Logic:

- **No "out of range" cast fail.** `_begin_cast_skill` only fails for `unknown_slot`, `unknown_skill`, `invalid_skill`, `zero_direction` and `cooldown`. A cast aimed past the skill's range still goes off: the shape is just clipped to its range. The HUD has no `out_of_range` label.
- **Current HP is not saved.** `CharacterState` stores stats and position, not HP. Saving and reloading fully heals the player. The test showed this: the player had 75.5/100 HP after the warden and 100/100 after reload.
- **Normal enemies come back on reload, and never respawn in play.** Only `bosses_defeated` is saved. Every non-boss spawn is rebuilt on load, so a save/load clears a room's kills. `respawn_s` in `floor1.json` is never read, so dead enemies stay dead until the next load.
- **`floor_cleared` goes nowhere.** The exit names `to_zone: "floor2"`, but there is no floor 2 zone and no zone transition. `WorldState.floors_unlocked` is not raised when the floor is cleared.
- **`killed_enemies` is counted in the view, not in logic.** `MainView._on_event_emitted` increments it. A logic-only session such as this test never updates it.
- **Boss persistence needs manual wiring.** `GameSession` does not link `WorldSim.bosses_defeated` to `WorldState.bosses_defeated`. Every caller has to call `set_bosses_defeated(world_state.bosses_defeated)`, as `MainView` and this test do.
- **No XP or levels.** `CharacterState.level` and `xp` exist, but kills (including the boss) give nothing.
- **`permadeath.default_player_name` is not in `balance.json`.** `MainView` falls back to a hard-coded constant name.
- **`shadow_step` is unused.** It is defined in `skills.json` but not bound to any slot in `player.skills`.

View and art:

- **All enemy types look the same.** Ash Stalker, Cinder Bat, Bog Slime and the Thornback Warden all use `appearance: "ash_stalker"` and appear as the same red hexagon marker. The rooms can only be told apart by layout. In the boss-room shot the warden's `view_scale: 1.5` makes no clear size difference.
- **Skill slots show letters, not icons.** The HUD shows the fallback letters E/C/M/S instead of icon art.
- **The camera is not clamped to the map.** Near the map edges (the town, the boss room) a large grey void shows beyond the walls.
- **The HUD boss bar preview is a fixture.** It places a warden next to the player in town. In real play the bar appears in the boss room.
