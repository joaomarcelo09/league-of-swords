extends GutTest

const TEST_ROOT := "user://test_saves/death_flow"
const TEST_SLOT := "test_slot"


func before_each() -> void:
	_clean_dir(TEST_ROOT)


func after_each() -> void:
	_clean_dir(TEST_ROOT)


func after_all() -> void:
	_clean_dir(TEST_ROOT)


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


func test_death_screen_flow_full() -> void:
	# 1. Instantiate MainView with temporary save root
	var view := MainView.new()
	view.save_root = TEST_ROOT
	view.save_slot = TEST_SLOT
	autofree(view)
	view._ready()

	# Assert initial setup
	assert_not_null(view.player, "Player entity should be spawned")
	assert_not_null(view.character_state, "Character state should be created")
	assert_not_null(view.world_state, "World state should be created")
	assert_not_null(view.death_screen, "Death screen should be instantiated")
	assert_false(view.death_screen.is_open(), "Death screen should initially be closed")

	var char_a_id: String = view.character_state.id
	var char_a_name: String = view.character_state.name
	var char_a_level: int = view.character_state.level
	assert_false(char_a_id.is_empty(), "Character A ID must not be empty")

	# Spawn loot drop and capture old entities before death/respawn
	var loot_uid := view.inventory.create("iron_sword", "ground:floor1")
	view.hud.spawn_loot_drop({"type": "loot_drop", "items": [loot_uid], "tile": Vector2i(5, 5)})
	assert_gt(view.hud.get_loot_markers().size(), 0, "HUD should have loot markers before respawn")
	var old_enemy_entities := view.world.entities.values().duplicate()

	# 2. Kill the player
	view.world.apply_damage(99, view.player, 9999.0)
	assert_true(view.player.dead, "Player entity should be dead")

	# Step view to drain events and trigger death handler
	view._process(0.016)

	# 3. Assert DeathScreen is visible and shows cemetery entry
	assert_true(view.death_screen.is_open(), "Death screen should be open")
	assert_true(view.death_screen.visible, "Death screen should be visible")
	assert_eq(view.death_screen.name_label.text, char_a_name, "Name on death screen must match dead character")
	assert_eq(view.death_screen.level_label.text, str(char_a_level), "Level on death screen must match dead character")
	assert_eq(view.death_screen.zone_label.text, "floor1", "Zone on death screen must match dead character")
	assert_eq(view.death_screen.cause_label.text, "99", "Cause on death screen must match killer entity")
	assert_false(view.death_screen.date_label.text.is_empty(), "Date on death screen must not be empty")

	# Cemetery in WorldState has Char A
	assert_gte(view.world_state.cemetery.size(), 1, "Cemetery should have at least 1 entry")
	var cem_entry: Dictionary = view.world_state.cemetery[0]
	assert_eq(cem_entry.get("character_id", ""), char_a_id)
	assert_eq(cem_entry.get("name", ""), char_a_name)

	# Sim stepping should be stopped while death screen is open
	var tick_during: int = view.world.tick_count
	view._process(0.05)
	assert_eq(view.world.tick_count, tick_during, "Simulation must not step while death screen is open")

	# 4. Reject empty or whitespace name
	view.death_screen.name_input.text = "   "
	view.death_screen.start_button.pressed.emit()
	assert_true(view.death_screen.is_open(), "Death screen should remain open after empty name submission")
	assert_true(view.death_screen.error_label.visible, "Error label should be shown for empty name")

	# 5. Submit valid new character name
	var new_name := "Brand"
	view.death_screen.name_input.text = new_name
	view.death_screen.start_button.pressed.emit()

	# 6. Assert new character is alive, has different id, at entry, and cemetery preserved
	assert_false(view.death_screen.is_open(), "Death screen should close after valid respawn")
	assert_false(view.death_screen.visible, "Death screen should be hidden")
	assert_not_null(view.character_state, "New character state should exist")
	assert_eq(view.character_state.name, new_name, "New character name should match submitted name")
	assert_eq(view.character_state.status, "alive", "New character must be alive")
	assert_ne(view.character_state.id, char_a_id, "New character must have a different ID")
	assert_eq(view.character_state.position, [float(view.zone.entry.x), float(view.zone.entry.y)], "New character should be at floor entry")

	# Cemetery still has Char A's entry
	assert_gte(view.world_state.cemetery.size(), 1, "Cemetery must still contain prior entry")
	assert_eq(view.world_state.cemetery[0].get("character_id", ""), char_a_id)
	assert_eq(view.world_state.cemetery[0].get("name", ""), char_a_name)

	# New player entity in world is alive and positioned at zone entry
	assert_not_null(view.player, "New player entity should exist")
	assert_false(view.player.dead, "New player entity must be alive")
	assert_eq(Vector2i(view.player.pos), view.zone.entry, "New player entity position must be at zone entry")

	# Reset HUD loot markers and rebuild views verification
	assert_eq(view.hud.get_loot_markers().size(), 0, "HUD loot markers must be reset after respawn")
	assert_not_null(view.entity_layer, "EntityLayer must exist")
	var views := view.entity_layer.get_views()
	var new_enemy_count := 0
	for entity: Entity in view.world.entities.values():
		if entity.kind == "enemy":
			new_enemy_count += 1
			assert_true(view.entity_layer.has_entity_view(entity.id), "New enemy %d must have an EntityView" % entity.id)
			var ev: EntityView = view.entity_layer.get_entity_view(entity.id)
			assert_not_null(ev, "EntityView for enemy %d must not be null" % entity.id)
			assert_eq(ev.entity, entity, "EntityView.entity must match entity in new world")
			assert_false(old_enemy_entities.has(ev.entity), "EntityView must not point to an old entity from previous session")

	assert_gt(new_enemy_count, 0, "New world should have spawned enemies")
	for id_val: Variant in views.keys():
		var ev: EntityView = views[id_val]
		assert_true(view.world.entities.values().has(ev.entity), "Every EntityView.entity must belong to the new world")

	# 7. Sim runs again
	var tick_before_run: int = view.world.tick_count
	view._process(0.05)
	assert_gt(view.world.tick_count, tick_before_run, "Simulation should resume stepping after respawn")


func test_death_save_failure_blocks_new_character() -> void:
	var temp_root := TEST_ROOT.path_join("fail_store")
	_clean_dir(temp_root)
	var view := MainView.new()
	view.save_root = temp_root
	view.save_slot = "fail_slot"
	autofree(view)
	view._ready()

	assert_not_null(view.player, "Player should be spawned")
	assert_not_null(view.character_state, "Character state should exist")
	var orig_char_name := view.character_state.name

	# Make store unwritable by pointing save_store to a subpath of a regular file
	var blocker := temp_root.path_join("file_blocker")
	var f := FileAccess.open(blocker, FileAccess.WRITE)
	f.store_string("blocker")
	f.close()
	view.save_store = SaveStore.new(blocker.path_join("unwritable_root"), view.item_db)

	# Kill the player
	view.world.apply_damage(99, view.player, 9999.0)
	assert_true(view.player.dead, "Player should be dead")

	# Step view to trigger death handler
	view._process(0.016)

	# Assert death screen is open and shows error
	assert_true(view.death_screen.is_open(), "Death screen should be open")
	assert_true(view.death_screen.error_label.visible, "Error label should be visible on save failure")
	assert_false(view.death_screen.error_label.text.is_empty(), "Error text should describe failure")
	assert_eq(view.death_screen.name_label.text, orig_char_name, "Death screen should show dying character name, not fallback")

	# Attempt to create new character while store is failing
	view.death_screen.name_input.text = "NewHero"
	view.death_screen.start_button.pressed.emit()

	# Assert new character is blocked: death screen stays open, error still visible, character not created
	assert_true(view.death_screen.is_open(), "Death screen must remain open when death persistence fails")
	assert_true(view.death_screen.error_label.visible, "Error label must stay visible")
	assert_true(view.player.dead, "Player entity must remain dead")
	assert_eq(view.character_state.name, orig_char_name, "No new character should be created")

	assert_engine_error_count(2, "Unwritable directory should trigger 2 engine errors on failed directory creation")

	_clean_dir(temp_root)


func test_corrupt_world_file_stays_byte_identical() -> void:
	var corrupt_root := TEST_ROOT.path_join("corrupt_test")
	_clean_dir(corrupt_root)
	var store := SaveStore.new(corrupt_root)
	var slot := "corrupt_slot"
	var world_path := store.get_world_file_path(slot)
	DirAccess.make_dir_recursive_absolute(world_path.get_base_dir())

	var corrupt_data := "{\"corrupted_json\": [bad_syntax_no_close..."
	var f := FileAccess.open(world_path, FileAccess.WRITE)
	f.store_string(corrupt_data)
	f.close()

	var original_bytes := FileAccess.get_file_as_bytes(world_path)
	assert_gt(original_bytes.size(), 0, "Corrupt world file should have bytes")

	var view := MainView.new()
	view.save_root = corrupt_root
	view.save_slot = slot
	autofree(view)
	view._ready()

	var after_bytes := FileAccess.get_file_as_bytes(world_path)
	assert_eq(after_bytes, original_bytes, "Corrupt world.json must stay byte-identical after starting MainView")
	assert_null(view.world_state, "world_state should remain null on load failure")

	assert_push_error_count(1, "Loading corrupt world file must push_error")

	_clean_dir(corrupt_root)
