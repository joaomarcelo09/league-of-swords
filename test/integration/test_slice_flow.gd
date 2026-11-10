extends GutTest

const TEST_ROOT := "user://test_saves/slice_flow"
const TEST_SLOT := "slot_slice"
const FIXED_DT := 1.0 / 30.0  # Sim tick_hz is 30


func before_each() -> void:
	_clean_dir(TEST_ROOT)
	LaunchRequest.reset()
	Lifecycle.clear_cached_config()


func after_each() -> void:
	LaunchRequest.reset()
	_clean_dir(TEST_ROOT)
	Lifecycle.clear_cached_config()


func after_all() -> void:
	LaunchRequest.reset()
	_clean_dir(TEST_ROOT)
	Lifecycle.clear_cached_config()


func _clean_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(path)
	if dir != null:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while not file_name.is_empty():
			var full_sub := path.path_join(file_name)
			if dir.current_is_dir():
				if file_name != "." and file_name != "..":
					_clean_dir(full_sub)
			else:
				DirAccess.remove_absolute(full_sub)
			file_name = dir.get_next()
		dir.list_dir_end()
	DirAccess.remove_absolute(path)


func _step_ticks(view: MainView, count: int) -> void:
	for _i in range(count):
		view._process(FIXED_DT)


func test_milestone1_slice_end_to_end_flow() -> void:
	# -------------------------------------------------------------------------
	# 1. Spawn player at the zone entry in real slice zone data (test_arena)
	# -------------------------------------------------------------------------
	LaunchRequest.mode = "new"
	var view := MainView.new()
	view.save_root = TEST_ROOT
	view.save_slot = TEST_SLOT
	view._ready()

	assert_not_null(view.zone, "Zone data must be loaded")
	assert_true(view.zone.is_valid(), "Zone must be valid")
	assert_eq(view.zone_json_path, MainView.ZONE_JSON_PATH, "Must run against real slice zone json")
	assert_eq(view.zone_map_path, MainView.ZONE_MAP_PATH, "Must run against real slice zone map")

	assert_not_null(view.player, "Player entity must be spawned")
	assert_false(view.player.dead, "Player must be alive at start")
	assert_eq(Vector2i(view.player.pos), view.zone.entry, "Player must spawn at zone entry tile")

	assert_not_null(view.character_state, "CharacterState must exist")
	assert_eq(view.character_state.status, "alive", "CharacterState must be alive")
	var initial_char_id: String = view.character_state.id
	var initial_char_name: String = view.character_state.name
	assert_false(initial_char_id.is_empty(), "Character ID must be non-empty")
	assert_false(initial_char_name.is_empty(), "Character name must be non-empty")

	# Find real slice zone enemy (ash_stalker)
	var enemy: Entity = null
	for ent: Entity in view.world.entities.values():
		if ent.kind == "enemy" and ent.enemy_type_id == "ash_stalker":
			enemy = ent
			break
	assert_not_null(enemy, "Real slice zone enemy (ash_stalker) must be present in the world")
	assert_false(enemy.dead, "Enemy must initially be alive")
	assert_gt(enemy.hp, 0.0, "Enemy must have positive HP")

	# -------------------------------------------------------------------------
	# 2. Move via a Command
	# -------------------------------------------------------------------------
	var start_pos := view.player.pos
	var target_tile := Vector2i(3, 4)
	view.world.submit(Commands.move_to(view.player.id, target_tile))

	# Advance 20 ticks (speed is 4.0 tiles/s, distance is 2.0 tiles -> ~15 ticks)
	_step_ticks(view, 20)

	assert_gt(view.player.pos.distance_to(start_pos), 0.5, "Player must have moved from spawn entry")
	var expected_target := Vector2(target_tile.x + 0.5, target_tile.y + 0.5)
	assert_almost_eq(view.player.pos.x, expected_target.x, 0.15, "Player X should reach target tile center")
	assert_almost_eq(view.player.pos.y, expected_target.y, 0.15, "Player Y should reach target tile center")

	# -------------------------------------------------------------------------
	# 3. Kill a real zone enemy & its loot drops
	# -------------------------------------------------------------------------
	# Ensure deterministic drop: seed rng so roll succeeds
	view.world.rng.seed = 1337
	view.world.apply_damage(view.player.id, enemy, 9999.0)

	# Process 1 tick to resolve death and loot drop
	_step_ticks(view, 1)

	assert_true(enemy.dead, "Real zone enemy must be dead")
	assert_lte(enemy.hp, 0.0, "Enemy HP must be non-positive on death")

	# Advance further ticks: enemy must stay dead and not act
	_step_ticks(view, 5)
	assert_true(enemy.dead, "Killed enemy must stay dead across ticks")

	# Find dropped items on the ground
	var eff_zone := view.world.zone_id if not view.world.zone_id.is_empty() else "floor1"
	var ground_owner := "ground:" + eff_zone
	var ground_items := view.inventory.items_of(ground_owner)
	assert_gt(ground_items.size(), 0, "Killing real zone enemy must drop loot on ground")
	var loot_uid: int = ground_items[0]
	assert_gt(loot_uid, 0, "Loot UID must be valid positive integer")

	# -------------------------------------------------------------------------
	# 4. Pick up the loot
	# -------------------------------------------------------------------------
	var player_char_owner := "character:%d" % view.player.id
	var picked_up := view.inventory.pickup(loot_uid, player_char_owner)
	assert_true(picked_up, "Picking up dropped loot must succeed")
	assert_eq(view.inventory.owner_of(loot_uid), player_char_owner, "Loot owner must now be player")
	assert_true(view.inventory.items_of(player_char_owner).has(loot_uid), "Player inventory must contain loot")

	# -------------------------------------------------------------------------
	# 5. Cast every skill (Q, W, R)
	# -------------------------------------------------------------------------
	assert_true(view.player.skills.has("Q"), "Player must have Q skill")
	assert_true(view.player.skills.has("W"), "Player must have W skill")
	assert_true(view.player.skills.has("R"), "Player must have R skill")

	# Q: ember_lance (line, cast_time 0.2s = 6 ticks)
	var q_aim := view.player.pos + Vector2(2.0, 0.0)
	view.world.submit(Commands.cast_skill(view.player.id, "Q", q_aim))
	_step_ticks(view, 8)
	assert_gt(view.player.skill_ready_ticks.get("Q", 0.0), float(view.world.tick_count), "Q skill must enter cooldown")

	# Fast-forward Q cooldown so entity is clear
	view.player.skill_ready_ticks["Q"] = 0.0

	# W: crescent_sweep (cone, cast_time 0.3s = 9 ticks)
	var w_aim := view.player.pos + Vector2(0.0, 2.0)
	view.world.submit(Commands.cast_skill(view.player.id, "W", w_aim))
	_step_ticks(view, 12)
	assert_gt(view.player.skill_ready_ticks.get("W", 0.0), float(view.world.tick_count), "W skill must enter cooldown")

	# Fast-forward W cooldown
	view.player.skill_ready_ticks["W"] = 0.0

	# R: mending_gale (circle, cast_time 0.0s = instant)
	var r_aim := view.player.pos + Vector2(1.0, 0.0)
	view.world.submit(Commands.cast_skill(view.player.id, "R", r_aim))
	_step_ticks(view, 2)
	assert_gt(view.player.skill_ready_ticks.get("R", 0.0), float(view.world.tick_count), "R skill must enter cooldown")

	# -------------------------------------------------------------------------
	# 6. Dash (E)
	# -------------------------------------------------------------------------
	var pre_dash_pos := view.player.pos
	var dash_dir := Vector2(1.0, 0.0)
	view.world.submit(Commands.dash(view.player.id, dash_dir))

	# Dash duration is 0.15s (~5 ticks)
	_step_ticks(view, 7)
	assert_gt(view.player.pos.x, pre_dash_pos.x + 0.5, "Dash must move player forward along aim vector")
	assert_gt(view.player.dash_ready_tick, float(view.world.tick_count), "Dash must enter cooldown")

	# -------------------------------------------------------------------------
	# 7. Player dies via the sim
	# -------------------------------------------------------------------------
	view.world.apply_damage(enemy.id, view.player, 9999.0)
	assert_true(view.player.dead, "Player entity must be dead")

	# Process 1 frame to trigger death persistence and death screen
	view._process(FIXED_DT)

	# -------------------------------------------------------------------------
	# 8. Death handled by Lifecycle (cemetery entry, items to merchant)
	# -------------------------------------------------------------------------
	assert_true(view.death_screen.is_open(), "Death screen must be open")
	assert_eq(view.character_state.status, "dead", "Character status must be marked dead")

	# Cemetery entry recorded
	assert_gte(view.world_state.cemetery.size(), 1, "Cemetery must contain at least 1 entry")
	var cem_entry: Dictionary = view.world_state.cemetery[0]
	assert_eq(cem_entry.get("character_id"), initial_char_id, "Cemetery entry must match initial character id")
	assert_eq(cem_entry.get("name"), initial_char_name, "Cemetery entry must match initial character name")

	# Items moved to merchant stock upon death
	var merchant_owner := "merchant:floor1_smith"
	assert_eq(view.inventory.owner_of(loot_uid), merchant_owner, "Looted item must be transferred to merchant stock")
	assert_true(view.inventory.items_of(merchant_owner).has(loot_uid), "Merchant must have looted item in stock")

	# -------------------------------------------------------------------------
	# 9. New character spawns at the floor-1 entry in the same world
	# -------------------------------------------------------------------------
	var new_name := "Brannoc"
	view.death_screen.name_input.text = new_name
	view.death_screen.start_button.pressed.emit()

	assert_false(view.death_screen.is_open(), "Death screen must close after submitting new character")
	assert_not_null(view.character_state, "New character state must exist")
	assert_eq(view.character_state.name, new_name, "New character name must match submitted name")
	assert_eq(view.character_state.status, "alive", "New character must be alive")
	assert_ne(view.character_state.id, initial_char_id, "New character must have distinct id")

	# Positioned at floor-1 entry
	assert_not_null(view.player, "New player entity must be spawned")
	assert_false(view.player.dead, "New player entity must be alive")
	assert_eq(Vector2i(view.player.pos), view.zone.entry, "New player must spawn at floor-1 entry")

	# Cemetery still has initial dead character
	assert_gte(view.world_state.cemetery.size(), 1, "Cemetery must still hold prior death record")
	assert_eq(view.world_state.cemetery[0].get("character_id"), initial_char_id)

	# -------------------------------------------------------------------------
	# 10. Save and reload from a temp user:// root and check state
	# -------------------------------------------------------------------------
	var save_res := view.save_now()
	assert_true(save_res.get("ok", false), "Saving session state must succeed")
	var new_char_id: String = view.character_state.id

	view.free()

	# Reload session via Continue mode
	LaunchRequest.mode = "continue"
	LaunchRequest.character_id = new_char_id

	var reloaded_view := MainView.new()
	reloaded_view.save_root = TEST_ROOT
	reloaded_view.save_slot = TEST_SLOT
	autofree(reloaded_view)
	reloaded_view._ready()

	# Assert cemetery preserved
	assert_gte(reloaded_view.world_state.cemetery.size(), 1, "Reloaded world must preserve cemetery")
	assert_eq(reloaded_view.world_state.cemetery[0].get("character_id"), initial_char_id)
	assert_eq(reloaded_view.world_state.cemetery[0].get("name"), initial_char_name)

	# Assert killed enemy count preserved
	assert_gte(reloaded_view.world_state.killed_enemies, 1, "Reloaded world must preserve killed_enemies counter")

	# Assert dead character is NOT playable
	var dead_char_res := Lifecycle.load_playable(reloaded_view.save_store, TEST_SLOT, initial_char_id, reloaded_view.item_db)
	assert_false(dead_char_res.get("ok", true), "Lifecycle must refuse to load dead character as playable")
	assert_true(str(dead_char_res.get("error", "")).contains("dead"), "Error message must state character is dead")

	# Assert reloaded character is the alive new character
	assert_eq(reloaded_view.character_state.id, new_char_id, "Reloaded character ID must match new character")
	assert_eq(reloaded_view.character_state.name, new_name, "Reloaded character name must match new character")
	assert_eq(reloaded_view.character_state.status, "alive", "Reloaded character must be alive")
	assert_not_null(reloaded_view.player, "Reloaded player entity must exist")
	assert_false(reloaded_view.player.dead, "Reloaded player entity must be alive")

	# Assert merchant still retains items from dead character
	assert_eq(reloaded_view.inventory.owner_of(loot_uid), merchant_owner, "Reloaded inventory must preserve merchant stock")
	assert_true(reloaded_view.inventory.items_of(merchant_owner).has(loot_uid), "Reloaded merchant inventory must have loot item")
