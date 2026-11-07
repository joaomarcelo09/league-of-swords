# League of Swords

Original 2D action RPG inspired by Sword Art Online: Godot 4.7.2 (pinned), typed GDScript, Linux native, 100-floor tower, data-driven content, balance simulator, layered sprites. The owner writes no code; AI agents write everything.

## Environment & Commands
- Pinned versions: `tools/godot-version.txt` (Godot 4.7.2-stable, GUT v9.7.1).
- Setup: `tools/install_godot.sh` (installs into `.tools/`, gitignored; worktrees need their own install or symlink `.tools/godot` from main).
- Godot wrapper: run Godot only through `tools/godot` (e.g. `tools/godot --version`).
- Headless re-import: `tools/godot --headless --import` (required when adding new `class_name` scripts).
- Run tests: `tools/test.sh` (GUT headless; exit code is truth; supports filter like `tools/test.sh test_smoke.gd`).
- Capture visuals: `tools/screenshot.sh` (runs xvfb, saves PNG to `.screenshots/shot.png`; inspect with Read tool; supports `--scene=res://scenes/main.tscn --frames=60 --out=.screenshots/shot.png`).

## Folder Layout
- `src/logic/` (planned): pure simulation, NO Node/SceneTree/rendering APIs, headless-testable.
- `src/view/`: scenes and rendering reading logic state.
- `src/input/` (planned): turns input into logic commands.
- `data/` (planned): JSON content and balance numbers.
- `scenes/`: Godot scene files (`.tscn`).
- `assets/` (planned): Git LFS for png/audio.
- `test/unit/`: GUT unit tests (`test_*.gd`).
- `test/integration/`: GUT integration tests.
- `tools/`: project automation and tooling scripts.
- `docs/` (planned): documentation (none yet).

## Rules for Coders
- Godot 4 syntax only: typed GDScript, `@export`, `@onready`, `await` (no `yield`).
- Logic purity: logic never imports view or input.
- Data-driven content: no hardcoded gameplay numbers, content lives in JSON under `data/`.
- Test requirement: every logic change ships with a GUT test in `test/unit/` (name `test_*.gd`).
- Class cache: new `class_name` scripts need a re-import (`tools/godot --headless --import`) before tests see them.

## Originality & Art Credit
- Originality: inspired mechanics only; no Sword Art Online names, characters, logos, or copied text/art; original names and designs.
- Art credit: every third-party asset (e.g. LPC) must be listed in `assets/CREDITS.md` with author, license, and source in the same change.

## Saves & Design Pointers
- The save is the world.
- Characters are mortal (permadeath).
- LoL-style controls (right-click move/attack, Q/W/R skills, E dash).
- Full specifications: `.team/plans/jgt1-milestone1.md`.

## Git & Worktrees
- Work only in your task worktree on branch `jgt/jgt-n`.
- Never commit to main, push, force, or amend unless the brief explicitly says so.
- Do not touch `addons/gut/` (vendored).
- `.uid` files Godot generates are committed.
