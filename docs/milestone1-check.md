# Milestone 1 Vertical Slice End-to-End Verification

This document verifies the completeness and health of the Milestone 1 vertical slice for **League of Swords**, including an automated acceptance mapping, review screenshot set, commands to reproduce all checks, a play-test checklist for the owner, and documented known gaps.

---

## 1. Feature Acceptance Table

| Feature Area | Milestone 1 Scope | Automated Test / Verification Evidence | Status |
| :--- | :--- | :--- | :--- |
| **Movement** | Click-to-move pathfinding, grid navigation, collision, continuous path updates | `test/unit/test_zone.gd`, `test/unit/test_player_input.gd`, `test/integration/test_slice_flow.gd` | Pass |
| **Combat & Skills (Q/W/R)** | Basic melee attack interval/damage, Ember Lance (Q line), Crescent Sweep (W cone), Mending Gale (R circle heal/buff) | `test/unit/test_basic_attack.gd`, `test/unit/test_skills.gd`, `test/integration/test_slice_flow.gd` | Pass |
| **Dash (E)** | Targeted dash with cooldown, wall collisions, boundary clamping, invulnerability / movement | `test/unit/test_dash.gd`, `test/integration/test_slice_flow.gd` | Pass |
| **Enemies & Telegraphs** | AI states (idle, chase, telegraph windup, attack, recovery), attack shapes & visuals | `test/unit/test_enemy_ai.gd`, `test/unit/test_entity_views.gd`, `test/unit/test_zone_data.gd` | Pass |
| **Loot & Inventory** | Loot drop tables, roll chances, ground item creation, item pickup, equip weapon/armor, potion consumption | `test/unit/test_items.gd`, `test/integration/test_slice_flow.gd` | Pass |
| **HUD & Views** | Health bar, skill icons & cooldown overlays, inventory panel, floating combat text, loot indicators | `test/unit/test_hud.gd`, `test/unit/test_zone_view.gd`, `test/unit/test_entity_views.gd` | Pass |
| **Layered Sprites** | Modular character rendering (body, hair, clothes, armor, weapon) with proper draw order | `test/unit/test_sprite_layout.gd`, `src/view/debug/layered_sprite_preview.gd` | Pass |
| **Save & World State** | Atomic JSON persistence, slot directory structure, world state (seed, floors, flags, inventory), character state | `test/unit/test_save.gd`, `test/unit/test_save_helpers.gd`, `test/integration/test_continue_flow.gd` | Pass |
| **Permadeath & Cemetery** | Character death transition, equipment/item transfer to floor-1 merchant, deduplicated cemetery records | `test/unit/test_lifecycle.gd`, `test/integration/test_permadeath.gd`, `test/integration/test_slice_flow.gd` | Pass |
| **Death Screen** | Interactive death modal showing obituary details, name entry validation, respawn trigger at floor-1 entry | `test/unit/test_death_screen.gd`, `test/integration/test_death_screen_flow.gd`, `test/integration/test_slice_flow.gd` | Pass |
| **Title & Continue** | Title menu, slot summary inspection, Continue existing game, New World creation (with overwrite guard) | `test/unit/test_title_menu.gd`, `test/unit/test_slot_summary.gd`, `test/integration/test_continue_flow.gd` | Pass |
| **End-to-End Vertical Slice** | Full flow: zone entry -> move -> kill enemy -> loot drop/pickup -> Q/W/R skills -> dash -> death -> cemetery -> new character -> save/reload | `test/integration/test_slice_flow.gd` | Pass |

---

## 2. Screenshot Set for Owner Review

Screenshots were captured headless in virtual display mode using `tools/screenshot.sh` and output to `.screenshots/milestone1/`:

1. **Title Screen** (`--preview=title`):
   - Path: `/home/joaogomes/font/jg-sao-inspired/.team/worktrees/jgt-43/.screenshots/milestone1/title.png`
   - Description: Title screen showing game logo, Continue and New World options, and slot character summary (`Brannoc`, Level 14, floor1).

2. **Zone in Play** (Default scene `res://scenes/main.tscn`):
   - Path: `/home/joaogomes/font/jg-sao-inspired/.team/worktrees/jgt-43/.screenshots/milestone1/zone_in_play.png`
   - Description: Player entity rendered in the floor-1 slice zone (`test_arena`) with TileMap ground, player marker, and camera follow.

3. **Telegraph Windup** (`--preview=telegraph_windup`):
   - Path: `/home/joaogomes/font/jg-sao-inspired/.team/worktrees/jgt-43/.screenshots/milestone1/telegraph_windup.png`
   - Description: Active enemy attack telegraph area visualised during windup phase.

4. **Death Screen** (`--preview=death`):
   - Path: `/home/joaogomes/font/jg-sao-inspired/.team/worktrees/jgt-43/.screenshots/milestone1/death_screen.png`
   - Description: Cemetery obituary modal showing character details, cause of death, date, and text input for naming the successor.

5. **HUD Preview** (`--preview=hud`):
   - Path: `/home/joaogomes/font/jg-sao-inspired/.team/worktrees/jgt-43/.screenshots/milestone1/hud.png`
   - Description: In-game HUD with player HP bar, skill action bar (Q, W, E dash, R), cooldown overlays, inventory panel, and floating loot markers.

6. **Layered Sprite Preview** (`--preview=layered_sprite`):
   - Path: `/home/joaogomes/font/jg-sao-inspired/.team/worktrees/jgt-43/.screenshots/milestone1/layered_sprite.png`
   - Description: Composite layered sprite assembly rendering body, hair, clothing, armor, and weapon components.

---

## 3. Reproduction Commands

### Run Test Suite
```bash
# Run all unit and integration tests (deterministic, exits 0 on success)
tools/test.sh
```

### Generate Screenshots
```bash
mkdir -p .screenshots/milestone1

# 1. Title Screen
tools/screenshot.sh --preview=title --out=.screenshots/milestone1/title.png

# 2. Zone in Play
tools/screenshot.sh --out=.screenshots/milestone1/zone_in_play.png

# 3. Telegraph Windup Preview
tools/screenshot.sh --preview=telegraph_windup --out=.screenshots/milestone1/telegraph_windup.png

# 4. Death Screen Preview
tools/screenshot.sh --preview=death --out=.screenshots/milestone1/death_screen.png

# 5. HUD Preview
tools/screenshot.sh --preview=hud --out=.screenshots/milestone1/hud.png

# 6. Layered Sprite Preview
tools/screenshot.sh --preview=layered_sprite --out=.screenshots/milestone1/layered_sprite.png
```

---

## 4. Play-Test Checklist for the Owner

Launch the game interactively with Godot:
```bash
tools/godot --path .
```

### Controls
- **Right-Click**:
  - Click on walkable ground to move the hero.
  - Click on an enemy entity to target and auto-attack with basic melee attacks.
- **Skills**:
  - `Q`: Cast **Ember Lance** (targeted skillshot line towards mouse cursor).
  - `W`: Cast **Crescent Sweep** (cone cleave in direction of mouse cursor).
  - `E`: **Dash** (quick dash towards mouse cursor).
  - `R`: Cast **Mending Gale** (instant PBAoE heal + attack buff).
- **Inventory & Items**:
  - `I`: Toggle Inventory window.
  - Left-Click on ground loot marker when in range to pick up items.
  - Left-Click items in inventory to equip gear or consume potions.

### What to Try
1. **Title Menu**: Verify that selecting **New World** prompts for character creation or confirmation if a save already exists.
2. **Exploration & Navigation**: Walk through `test_arena` corridors and rooms; test pathfinding around walls.
3. **Engaging Enemies**: Approach an Ash Stalker to trigger aggro. Watch the red telegraph cone during its windup, then dodge using `E` (dash).
4. **Combat & Loot**: Slay the enemy using basic attacks and skill combos (`Q`, `W`). Check that loot drops on the ground and click to collect it into inventory.
5. **Permadeath**: Let an enemy deplete player HP to 0. Verify the Death Screen appears with the character's obituary.
6. **Respawn & Cemetery**: Enter a new name (e.g. `Brannoc`) and click **Begin Anew**. Verify you spawn at the floor entry, and check that previous gear has been moved to the floor merchant.
7. **Continue**: Quit the game (`Alt+F4` or window close). Relaunch and click **Continue** on the title menu to confirm slot restoration.

### What to Report
- Any stutter or pathfinding hiccups when clicking rapid movement commands.
- Visual alignment or Z-sorting anomalies with layered sprites, telegraphs, or floating combat text.
- Cooldown timer display mismatches between HUD icons and actual skill availability.
- Any discrepancy in save file recovery or Continue slot summary info.

---

## 5. Known Gaps (Documented Follow-ups)

The following items are intentional out-of-scope follow-ups filed during milestone 1 architecture reviews:
1. **Entity.hp Not Persisted Across Zone Reloads**:
   - `WorldState` serializes world-level progress (floors unlocked, flags, inventory, cemetery, killed enemy counts), and `CharacterState` serializes player attributes and position. Non-boss zone enemy entities currently re-instantiate from zone definitions on complete game restart / session recreation rather than saving individual enemy HP and live positions.
2. **Corrupt-World Recovery UI**:
   - When a slot's `world.json` contains malformed/corrupted JSON, `TitleMenu` and `MainView` detect the parse error and disable Continue/New World to prevent destructive overwriting of user data. An interactive repair/recovery dialog is deferred to a future milestone.
3. **Death Retry on Save Failure**:
   - If an atomic disk write fails during player death persistence (e.g. read-only filesystem or full disk), the death screen surfaces the error and prevents spawning a new character until the write succeeds, ensuring save integrity. Automatic multi-path fallback is a post-M1 improvement.
