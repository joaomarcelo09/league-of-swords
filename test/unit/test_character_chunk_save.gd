extends GutTest

const TEST_ROOT := "user://test_chunk_saves"


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


func _base_dict() -> Dictionary:
	return {
		"version": 1,
		"id": "rowan",
		"status": "alive",
		"name": "Rowan",
		"appearance": {"body": "male_1"},
		"level": 3,
		"xp": 120,
		"stats": {
			"max_hp": 120.0,
			"atk": 15.0,
			"defense": 4.0,
			"attack_range": 1.5,
			"attack_interval": 1.0,
			"weapon_damage": 8.0
		},
		"zone": "floor1",
		"position": [5.0, 10.0],
	}


func test_chunk_round_trips_through_dict() -> void:
	var character := CharacterState.from_dict(_base_dict())
	assert_not_null(character)
	character.chunk = "c_2"

	var dict := character.to_dict()
	assert_eq(dict["chunk"], "c_2", "to_dict must write the chunk")

	var restored := CharacterState.from_dict(dict)
	assert_not_null(restored, "Loading a save with a chunk must succeed: %s" % CharacterState.last_error)
	assert_eq(restored.chunk, "c_2")
	assert_eq(restored.position, [5.0, 10.0], "position stays chunk-local")
	assert_eq(restored.zone, "floor1", "zone stays the floor/world id")
	assert_true(restored.equals(character), "Restored character must equal the original")
	assert_eq(restored.to_dict(), dict)


func test_chunk_round_trips_through_save_store() -> void:
	var character := CharacterState.from_dict(_base_dict())
	assert_not_null(character)
	character.chunk = "c_4"
	character.position = [31.0, 7.0]

	var store := SaveStore.new(TEST_ROOT)
	var save_res := store.save_character("slot_chunk", character)
	assert_true(save_res.get("ok", false), "save_character should succeed: %s" % str(save_res.get("error")))

	var load_res := store.load_character("slot_chunk", "rowan")
	assert_true(load_res.get("ok", false), "load_character should succeed: %s" % str(load_res.get("error")))

	var loaded: CharacterState = load_res.get("value")
	assert_not_null(loaded)
	assert_eq(loaded.chunk, "c_4")
	assert_eq(loaded.position, [31.0, 7.0])
	assert_true(loaded.equals(character), "Loaded character must equal the saved one")


func test_save_version_is_unchanged() -> void:
	assert_eq(CharacterState.SAVE_VERSION, 1, "Adding an optional chunk must not bump the save version")
	var character := CharacterState.from_dict(_base_dict())
	assert_not_null(character)
	assert_eq(character.to_dict()["version"], 1)


func test_old_save_without_chunk_loads_as_classic() -> void:
	var old_dict := _base_dict()
	assert_false(old_dict.has("chunk"))

	var character := CharacterState.from_dict(old_dict)
	assert_not_null(character, "An old save without 'chunk' must still load: %s" % CharacterState.last_error)
	assert_eq(character.chunk, "", "Old saves are classic single-zone saves")
	assert_eq(character.zone, "floor1")
	assert_eq(character.position, [5.0, 10.0])
	assert_eq(character.to_dict()["chunk"], "", "Re-saving an old character writes an empty chunk")


func test_non_string_chunk_is_rejected() -> void:
	for bad_value: Variant in [5, 1.5, true, ["c_2"], {"id": "c_2"}, null]:
		var bad_dict := _base_dict()
		bad_dict["chunk"] = bad_value
		var errs: Array = []
		var character := CharacterState.from_dict(bad_dict, errs)

		assert_null(character, "Non-String chunk %s must be rejected" % str(bad_value))
		assert_gt(errs.size(), 0, "Rejection must be reported")
		assert_true(str(errs[0]).contains("chunk"), "Error must name the field: %s" % str(errs[0]))


func test_equals_compares_chunk() -> void:
	var first := CharacterState.from_dict(_base_dict())
	var second := CharacterState.from_dict(_base_dict())
	assert_not_null(first)
	assert_not_null(second)
	assert_true(first.equals(second), "Characters equal except chunk must be equal")

	first.chunk = "c_1"
	assert_false(first.equals(second), "A different chunk must break equality")

	second.chunk = "c_1"
	assert_true(first.equals(second), "Same chunk must compare equal")
