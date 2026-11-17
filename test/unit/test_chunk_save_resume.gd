extends GutTest

const TEST_ROOT := "user://test_chunk_save_resume"
const WORLD_PATH := "res://data/zones/floor1/world.json"
const ZONES_DIR := "res://data/zones/floor1"
const DUNGEON_MAP := "res://data/zones/floor1/floor1.map"
const DUNGEON_JSON := "res://data/zones/floor1/floor1.json"

var _registry: DataRegistry = null
var _item_db: ItemDB = null
var _store: SaveStore = null


func before_each() -> void:
	_clean_dir(TEST_ROOT)
	LaunchRequest.reset()
	_registry = DataRegistry.new()
	_registry.load_dir("res://data")
	_item_db = ItemDB.new(_registry)
	_store = SaveStore.new(TEST_ROOT, _item_db)


func after_each() -> void:
	LaunchRequest.reset()
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


func _chunked_world() -> ChunkedWorld:
	var chunked := ChunkedWorld.load_file(WORLD_PATH, ZONES_DIR)
	assert_true(chunked.is_valid(), "chunked floor must load: %s" % str(chunked.errors))
	return chunked


func _make_character(chunk: String, position: Array) -> CharacterState:
	var world := WorldState.new()
	world.inventory = Inventory.new(_item_db)
	var created := Lifecycle.new_character(
		world,
		"Rowan",
		{},
		Vector2i.ZERO,
		null,
		"",
		null,
		"floor1",
		_registry,
		chunk
	)
	assert_true(created.get("ok", false), str(created.get("error", "")))
	var character: CharacterState = created.get("value")
	character.position = position
	return character


func _save_and_load(character: CharacterState) -> CharacterState:
	var save_res := _store.save_character("slot", character)
	assert_true(save_res.get("ok", false), str(save_res.get("error", "")))
	var load_res := _store.load_character("slot", character.id)
	assert_true(load_res.get("ok", false), str(load_res.get("error", "")))
	return load_res.get("value")


func _new_view(root: String, slot: String) -> MainView:
	LaunchRequest.reset()
	var view := MainView.new()
	view.save_root = root
	view.save_slot = slot
	autofree(view)
	view._ready()
	return view


func test_plains_chunk_survives_save_and_resume() -> void:
	var chunked := _chunked_world()
	var map := chunked.map
	var character := _make_character("floor1_x5_y3", [5.0, 10.0])

	var loaded := _save_and_load(character)
	assert_not_null(loaded)
	assert_eq(loaded.chunk, "floor1_x5_y3", "the save keeps the chunk")
	assert_eq(loaded.position, [5.0, 10.0], "the save keeps the chunk-local position")

	var expected_world_tile := map.chunk_to_world("floor1_x5_y3", Vector2i(5, 10))
	var result := ChunkResume.resume(map, chunked.loader, loaded)

	assert_true(result.get("ok", false), str(result))
	assert_true(result.get("chunked", false))
	assert_eq(result.get("world_tile"), expected_world_tile, "the local position maps back to its world tile")
	assert_true(chunked.is_walkable(expected_world_tile), "the resumed tile is walkable in the plains")
	assert_true(chunked.is_loaded("floor1_x5_y3"), "the saved chunk is streamed back in")
	assert_eq(loaded.zone, "floor1", "resume keeps the floor id in zone")


func test_dungeon_door_save_resumes_on_the_chunked_floor() -> void:
	var chunked := _chunked_world()
	var map := chunked.map

	# The dungeon is a door's zone, not a chunk: entering it records the chunk
	# and tile the door returns to.
	# Floor 1 has no zone door yet (the boss gate comes later), so the door
	# return link is built the way world.json describes one.
	var door := {"return_chunk": "floor1_x4_y3", "return_to_tile": Vector2i(29, 16)}
	assert_false(map.has_chunk("floor1"), "the dungeon zone is not a chunk")
	var return_tile: Vector2i = door.get("return_to_tile")

	var character := _make_character("floor1_x4_y3", [float(return_tile.x), float(return_tile.y)])
	var capture := ChunkResume.capture_door_return(map, character, {
		"chunk": door.get("return_chunk"),
		"to_tile": return_tile,
	})
	assert_true(capture.get("ok", false), str(capture))
	assert_eq(character.chunk, "floor1_x4_y3")
	assert_eq(character.position, [float(return_tile.x), float(return_tile.y)])

	var loaded := _save_and_load(character)
	assert_not_null(loaded)
	assert_eq(loaded.chunk, "floor1_x4_y3")
	var expected_world_tile := map.chunk_to_world("floor1_x4_y3", return_tile)
	var result := ChunkResume.resume(map, chunked.loader, loaded)

	assert_true(result.get("ok", false), str(result))
	assert_eq(result.get("world_tile"), expected_world_tile, "loading resumes at the door's return tile")
	assert_true(result.get("loaded", []).has("floor1_x4_y3"), "the return chunk is streamed back in")
	assert_true(chunked.is_walkable(expected_world_tile), "the door's return tile is walkable")


func test_classic_save_with_empty_chunk_is_unchanged() -> void:
	var chunked := _chunked_world()
	var before := chunked.loaded_ids()
	var character := _make_character("", [4.0, 8.0])

	var loaded := _save_and_load(character)
	assert_not_null(loaded)
	assert_eq(loaded.chunk, "", "a classic save keeps an empty chunk")
	assert_eq(loaded.position, [4.0, 8.0], "a classic save keeps its raw world position")

	var result := ChunkResume.resume(chunked.map, chunked.loader, loaded)
	assert_true(result.get("ok", false), str(result))
	assert_false(result.get("chunked", false))
	assert_false(result.has("world_tile"), "a classic save has no world tile to resume")
	assert_eq(chunked.loaded_ids(), before, "a classic save does not stream any chunk")


func test_failed_resume_falls_back_to_the_town_entry() -> void:
	var root := TEST_ROOT.path_join("fallback")
	var world := WorldState.new()
	world.inventory = Inventory.new(_item_db)
	var created := Lifecycle.new_character(
		world,
		"Lost",
		{},
		Vector2i(2, 3),
		SaveStore.new(root, _item_db),
		"slot_bad",
		null,
		"floor1",
		_registry,
		"missing_chunk"
	)
	assert_true(created.get("ok", false), str(created.get("error", "")))

	var view := _new_view(root, "slot_bad")
	var start := ChunkResume.start_position(view.chunked_world)
	assert_true(start.get("ok", false), str(start))
	var start_chunk := str(start.get("chunk"))
	var start_local: Vector2 = start.get("local_position")
	var start_pos: Vector2 = start.get("world_pos")

	assert_not_null(view.character_state)
	assert_eq(view.character_state.chunk, start_chunk, "the unreadable chunk is replaced by the start chunk")
	assert_eq(view.character_state.position, [start_local.x, start_local.y], "the start position is recorded")
	assert_eq(view.player.pos, start_pos, "the player spawns at the town entry")
	assert_true(view.chunked_world.is_loaded(start_chunk), "the start chunk is streamed")


func test_save_in_a_removed_chunk_falls_back_to_the_town_entry() -> void:
	# Saves made on the old 4-chunk strip name chunks the 9x4 grid no longer has.
	var root := TEST_ROOT.path_join("old_strip")
	var world := WorldState.new()
	world.inventory = Inventory.new(_item_db)
	var created := Lifecycle.new_character(
		world,
		"Veteran",
		{},
		Vector2i(5, 10),
		SaveStore.new(root, _item_db),
		"slot_old",
		null,
		"floor1",
		_registry,
		"floor1_plains_east"
	)
	assert_true(created.get("ok", false), str(created.get("error", "")))

	var view := _new_view(root, "slot_old")
	var start := ChunkResume.start_position(view.chunked_world)
	assert_true(start.get("ok", false), str(start))
	assert_eq(view.character_state.chunk, "floor1_x2_y1", "the old chunk id falls back to the city start chunk")
	assert_eq(view.player.pos, start.get("world_pos"), "the player spawns at the city entry")
	assert_true(view.zone.is_safe(Vector2i(view.player.pos)), "the fallback spawn is inside the safe city")


func test_new_character_starts_in_the_town_chunk() -> void:
	var root := TEST_ROOT.path_join("new")
	var view := _new_view(root, "slot_new")
	var start := ChunkResume.start_position(view.chunked_world)
	assert_true(start.get("ok", false), str(start))
	var start_chunk := str(start.get("chunk"))
	var start_tile: Vector2i = start.get("local_tile")
	var start_world_tile: Vector2i = start.get("world_tile")

	assert_not_null(view.character_state)
	assert_eq(start_chunk, "floor1_x2_y1", "the chunked floor starts in the town")
	assert_eq(view.character_state.chunk, "floor1_x2_y1")
	assert_eq(view.character_state.position, [float(start_tile.x), float(start_tile.y)], "the town entry is stored chunk-local")
	assert_eq(view.player.pos, WorldSim.tile_center(start_world_tile), "the player spawns at the town entry")

	var load_res := view.save_store.load_character("slot_new", view.character_state.id)
	assert_true(load_res.get("ok", false), str(load_res.get("error", "")))
	var saved: CharacterState = load_res.get("value")
	assert_eq(saved.chunk, "floor1_x2_y1", "the new character is saved already in the town chunk")
	assert_eq(saved.position, [float(start_tile.x), float(start_tile.y)])


func test_new_character_after_death_starts_in_the_town_chunk() -> void:
	var root := TEST_ROOT.path_join("death")
	var view := _new_view(root, "slot_death")

	# Die in the eastern plains, far from the town.
	view.player.pos = Vector2(170.5, 110.5)
	view._process(0.016)
	view.world.apply_damage(99, view.player, 9999.0)
	view._process(0.016)
	assert_true(view.death_screen.is_open(), "the death screen opens")

	view.death_screen.name_input.text = "Wanderer"
	view.death_screen.start_button.pressed.emit()

	assert_false(view.death_screen.is_open(), "the new character starts")
	assert_not_null(view.character_state)
	assert_eq(view.character_state.status, "alive")
	assert_eq(view.character_state.chunk, "floor1_x2_y1", "the new character starts in the town chunk")

	assert_gte(view.world_state.cemetery.size(), 1, "the cemetery keeps the death entry")
	assert_eq(view.world_state.cemetery[0].get("chunk"), "floor1_x5_y3", "the cemetery entry keeps the death chunk")


func test_save_then_reload_resumes_in_the_plains() -> void:
	var root := TEST_ROOT.path_join("plains_reload")
	var first := _new_view(root, "slot_plains")
	var plains_tile: Vector2i = first.chunked_world.map.chunk_to_world("floor1_x5_y3", Vector2i(5, 10))
	var saved_world_pos := Vector2(plains_tile) + Vector2(0.25, 0.75)
	first.player.pos = saved_world_pos
	assert_true(first.save_now().get("ok", false), "saving on the chunked floor must succeed")

	var saved_res := first.save_store.load_character("slot_plains", first.character_state.id)
	assert_true(saved_res.get("ok", false), str(saved_res.get("error", "")))
	var saved: CharacterState = saved_res.get("value")
	assert_eq(saved.chunk, "floor1_x5_y3", "the save stores the chunk")
	assert_eq(saved.position, [5.25, 10.75], "the save stores the chunk-local position, sub-tile precision")

	var second := _new_view(root, "slot_plains")
	assert_not_null(second.character_state)
	assert_eq(second.character_state.chunk, "floor1_x5_y3")
	assert_eq(second.player.pos, saved_world_pos, "the player is back at the saved sub-tile position")
	assert_true(second.chunked_world.is_loaded("floor1_x5_y3"), "the saved chunk is streamed at load")


func test_save_inside_the_dungeon_records_the_door_return() -> void:
	var root := TEST_ROOT.path_join("dungeon")
	var view := _new_view(root, "slot_dungeon")

	# Put the session inside the dungeon the way its door does: a classic zone
	# world, with the chunked floor kept for the return link.
	var dungeon := Zone.load_files(DUNGEON_MAP, DUNGEON_JSON)
	assert_true(dungeon.is_valid(), str(dungeon.errors))
	var session := GameSession.new(dungeon, view.registry, view.inventory, view.item_db)
	session.chunked_world = view.chunked_world
	session.active_door = {
		"id": "boss_door",
		"zone": "floor1",
		"tile": Vector2i(20, 8),
		"chunk": "floor1_x4_y3",
		"to_tile": Vector2i(29, 16),
	}
	var dungeon_player := session.spawn_player(Vector2i(20, 7), 4.0)
	view.session = session
	view.world = session.world
	view.player = dungeon_player

	assert_false(view.in_chunked_mode(), "the session is inside the dungeon zone")
	assert_true(view.save_now().get("ok", false), "saving inside the dungeon must succeed")

	var saved_res := view.save_store.load_character("slot_dungeon", view.character_state.id)
	assert_true(saved_res.get("ok", false), str(saved_res.get("error", "")))
	var saved: CharacterState = saved_res.get("value")
	assert_eq(saved.chunk, "floor1_x4_y3", "the door's return chunk is recorded")
	assert_eq(saved.position, [29.0, 16.0], "the door's return tile replaces zone coordinates")

	var resumed := ChunkResume.resume(view.chunked_world.map, view.chunked_world.loader, saved)
	assert_true(resumed.get("ok", false), str(resumed))
	var expected: Vector2i = view.chunked_world.map.chunk_to_world("floor1_x4_y3", Vector2i(29, 16))
	assert_eq(resumed.get("world_tile"), expected, "loading resumes on the chunked floor at the door")
