# Brief: plan the first playable slice (task JGT-1)

Read the task with `task_get JGT-1`: the description is the owner's design brief, the Details hold the decisions made so far. Do not re-read anything else about the game; they are summarized below.

## Goal
Produce an implementation plan for the **first milestone**: a small playable slice of an original SAO-inspired 2D RPG, split into **small coder tasks (each ~5-10 minutes of work, one concern, a handful of files)**, each with acceptance criteria and the test or check that proves it.

## Decisions to respect (all in JGT-1 Details)
- Godot 4 + GDScript, everything plain text, game data in data files, GUT tests runnable headless from the CLI, Git + LFS for art/audio. Native Linux. Single-player, but game logic must be separate from rendering/input so a server can own the world later.
- 2D graphics, layered customizable sprites (start with LPC assets, respect licenses, keep layouts swappable). LoL-style fixed angled camera and controls: right-click = move / attack enemy; Q, W, R = abilities with cooldown (data-driven sword skills, aimed at the mouse); E = short dash with cooldown, no invincibility; basic attack has no cooldown.
- Difficulty is mostly player skill: enemies/bosses use telegraphed attacks (wind-up, active, recovery) and open attack windows.
- Saves: **a save is the world, not the character**. World state and character state are separate models/files; characters die permanently (lost), the world persists (defeated bosses, items flowing to merchants/NPCs); new characters always start on floor 1; floor 1 has a cemetery of dead characters.
- Floor 1: big city (houses, shops), fields, dungeon, boss room, one zone per file, designed by hand in text. Boss is original (inspired by a first-floor "big melee boss with phases"), no SAO names/characters/logos.

## Current state
The project folder is empty and is NOT a git repository. Godot is not installed on this machine (xvfb-run is). Your plan must include setup tasks: git init + LFS, installing/pinning a Godot 4 version (say which and how, e.g. a downloaded binary kept out of the repo), GUT, a headless test command, a screenshot command via xvfb-run, project rules file (CLAUDE.md-style) for the coders.

## Scope of the milestone
Moves in the 3/4 view with click-to-move; one zone of floor 1 (a slice of the city or fields, not the full city); one enemy type with a telegraphed attack; basic attack + Q/W/R + E dash (a minimal data-driven skill system); a few items; world vs character save with permadeath working (die -> new character in the same world); tests running from the CLI. Out of scope: full floor 1, boss fight, balance simulator, customization UI beyond what the layered sprite needs (these come in later milestones; list them as a rough roadmap only).

## Output
Write the plan to `.team/plans/jgt1-milestone1.md`, with:
1. Proposed folder layout and architecture (logic vs rendering, data files, save model), short.
2. An ordered list of tasks T1..Tn: title, files to create/touch, approach in 2-4 lines, acceptance criteria, how to verify. Mark which can run in parallel (disjoint files).
3. Risks and questions that need the owner's decision (do not guess; list them).
Keep it concise (aim under ~250 lines). Do not write game code.
