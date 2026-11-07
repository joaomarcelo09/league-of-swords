extends GutTest

const TMP_DIR := "user://test_data_registry_tmp"


func before_each() -> void:
	_clean_dir(TMP_DIR)
	DirAccess.make_dir_recursive_absolute(TMP_DIR)


func after_each() -> void:
	_clean_dir(TMP_DIR)


func _clean_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(path)
	if dir != null:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while not file_name.is_empty():
			if not dir.current_is_dir():
				DirAccess.remove_absolute(path.path_join(file_name))
			file_name = dir.get_next()
		dir.list_dir_end()
	DirAccess.remove_absolute(path)


func _write_file(filename: String, content: String) -> void:
	var path := TMP_DIR.path_join(filename)
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file, "Failed to create file: %s" % path)
	if file != null:
		file.store_string(content)
		file.close()


func test_good_load() -> void:
	_write_file("items.json", """{
		"sword_iron": {
			"name": "Iron Sword",
			"damage": 12.0
		},
		"shield_wood": {
			"name": "Wooden Shield",
			"defense": 5.0
		}
	}""")

	var registry := DataRegistry.new()
	registry.load_dir(TMP_DIR)

	var errors := registry.validate()
	assert_eq(errors.size(), 0, "Expected no errors on good load: %s" % str(errors))
	assert_true(registry.has_entry("items", "sword_iron"))
	assert_true(registry.has_entry("items", "shield_wood"))
	assert_false(registry.has_entry("items", "unknown_item"))

	var sword := registry.get_entry("items", "sword_iron")
	assert_eq(sword.get("name"), "Iron Sword")
	assert_eq(sword.get("damage"), 12.0)

	var ids := registry.ids("items")
	assert_eq(ids.size(), 2)
	assert_has(ids, "sword_iron")
	assert_has(ids, "shield_wood")


func test_dotted_balance_path() -> void:
	_write_file("balance.json", """{
		"dash": {
			"distance_tiles": 3.0,
			"cooldown_s": 6.0
		},
		"player": {
			"move_speed_tiles_per_s": 4.0
		}
	}""")

	var registry := DataRegistry.new()
	registry.load_dir(TMP_DIR)

	assert_eq(registry.get_balance("dash.distance_tiles"), 3.0)
	assert_eq(registry.get_balance("dash.cooldown_s"), 6.0)
	assert_eq(registry.get_balance("player.move_speed_tiles_per_s"), 4.0)

	assert_null(registry.get_balance("dash.unknown_key"))
	assert_null(registry.get_balance("nonexistent.section"))
	assert_eq(registry.get_balance("dash.unknown_key", -1.0), -1.0)
	assert_eq(registry.get_balance("", -1.0), -1.0)


func test_missing_field_error() -> void:
	_write_file("items.json", """{
		"sword_1": {
			"name": "Rusty Sword"
		}
	}""")

	var registry := DataRegistry.new()
	registry.set_schema("items", {
		"name": TYPE_STRING,
		"damage": TYPE_FLOAT
	})
	registry.load_dir(TMP_DIR)

	var errors := registry.validate()
	assert_gt(errors.size(), 0, "Should report missing field error")

	var found := false
	for err in errors:
		if "items.json" in err and "sword_1" in err and "damage" in err and "missing field" in err:
			found = true
			break
	assert_true(found, "Expected error matching missing field 'damage' for 'sword_1' in items.json, got: %s" % str(errors))


func test_wrong_type_error() -> void:
	_write_file("items.json", """{
		"sword_1": {
			"name": "Rusty Sword",
			"damage": "twelve"
		}
	}""")

	var registry := DataRegistry.new()
	registry.set_schema("items", {
		"damage": TYPE_FLOAT
	})
	registry.load_dir(TMP_DIR)

	var errors := registry.validate()
	assert_gt(errors.size(), 0, "Should report wrong type error")

	var found := false
	for err in errors:
		if "items.json" in err and "sword_1" in err and "damage" in err and "wrong type" in err:
			found = true
			break
	assert_true(found, "Expected error mentioning wrong type for 'damage' in items.json, got: %s" % str(errors))


func test_bad_id_error() -> void:
	_write_file("items.json", """{
		"Sword-1": {
			"name": "Bad ID Sword"
		},
		"": {
			"name": "Empty ID Item"
		}
	}""")

	var registry := DataRegistry.new()
	registry.load_dir(TMP_DIR)

	var errors := registry.validate()
	assert_gt(errors.size(), 1, "Should report bad id errors for both invalid snake_case and empty id")

	var found_invalid_name := false
	var found_empty_id := false
	for err in errors:
		if "items.json" in err and "Sword-1" in err and "snake_case" in err:
			found_invalid_name = true
		if "items.json" in err and "empty" in err:
			found_empty_id = true
	assert_true(found_invalid_name, "Expected error mentioning invalid id 'Sword-1' in items.json, got: %s" % str(errors))
	assert_true(found_empty_id, "Expected error mentioning empty id in items.json, got: %s" % str(errors))


func test_top_level_not_dict_error() -> void:
	_write_file("items.json", """[
		{"name": "Array Top Level"}
	]""")

	var registry := DataRegistry.new()
	registry.load_dir(TMP_DIR)

	var errors := registry.validate()
	assert_gt(errors.size(), 0, "Should report top-level object error")

	var found := false
	for err in errors:
		if "items.json" in err and "must be an object" in err:
			found = true
			break
	assert_true(found, "Expected error mentioning top-level must be an object, got: %s" % str(errors))


func test_entry_not_dict_error() -> void:
	_write_file("items.json", """{
		"sword_1": "not an object"
	}""")

	var registry := DataRegistry.new()
	registry.load_dir(TMP_DIR)

	var errors := registry.validate()
	assert_gt(errors.size(), 0, "Should report entry object error")

	var found := false
	for err in errors:
		if "items.json" in err and "sword_1" in err and "must be an object" in err:
			found = true
			break
	assert_true(found, "Expected error mentioning entry must be an object, got: %s" % str(errors))


func test_bad_json_error() -> void:
	_write_file("items.json", """{
		"sword_1": { "unclosed
	""")

	var registry := DataRegistry.new()
	registry.load_dir(TMP_DIR)

	var errors := registry.validate()
	assert_gt(errors.size(), 0, "Should report bad JSON error")

	var found := false
	for err in errors:
		if "items.json" in err and ("JSON parse error" in err or "bad JSON" in err):
			found = true
			break
	assert_true(found, "Expected error mentioning bad JSON in items.json, got: %s" % str(errors))


func test_missing_entry_returns_empty() -> void:
	_write_file("items.json", """{
		"sword_1": {
			"name": "Valid Sword"
		}
	}""")

	var registry := DataRegistry.new()
	registry.load_dir(TMP_DIR)

	var missing_id_entry := registry.get_entry("items", "nonexistent")
	assert_eq(missing_id_entry, {}, "Missing id should return empty dict")
	assert_false(registry.has_entry("items", "nonexistent"))

	var missing_table_entry := registry.get_entry("skills", "dash")
	assert_eq(missing_table_entry, {}, "Missing table should return empty dict")
	assert_false(registry.has_entry("skills", "dash"))

	var missing_table_ids := registry.ids("skills")
	assert_eq(missing_table_ids.size(), 0, "Missing table ids should be empty array")


func test_real_res_data_loads_without_errors() -> void:
	var registry := DataRegistry.new()
	registry.load_dir("res://data")

	var errors := registry.validate()
	assert_eq(errors.size(), 0, "res://data should load and validate cleanly without errors: %s" % str(errors))

	assert_eq(registry.get_balance("dash.distance_tiles"), 3.0)
	assert_eq(registry.get_balance("dash.cooldown_s"), 6.0)
	assert_eq(registry.get_balance("player.move_speed_tiles_per_s"), 4.0)
	assert_eq(registry.get_balance("sim.tick_hz"), 30.0)
