extends GutTest

const CHUNK_SIZE := 32

var _calls: Array[String] = []
var _bad_chunk_ids: Dictionary = {}  # chunk id -> "null" | "invalid"


func before_each() -> void:
	_calls.clear()
	_bad_chunk_ids.clear()


func _make_world(load_radius: int) -> WorldMap:
	var chunks: Array = []
	for y in range(3):
		for x in range(3):
			chunks.append({
				"id": "c_%d_%d" % [x, y],
				"grid": [x, y],
				"zone": "test_small",
				"kind": "plains",
			})
	var map := WorldMap.load_from_dict({
		"chunk_size": [CHUNK_SIZE, CHUNK_SIZE],
		"load_radius": load_radius,
		"chunks": chunks,
	})
	assert_true(map.is_valid(), "test world must be valid: %s" % str(map.errors))
	return map


func _make_loader(map: WorldMap) -> ChunkLoader:
	return ChunkLoader.new(map, Callable(self, "_load_zone"))


func _load_zone(chunk_id: String) -> Zone:
	_calls.append(chunk_id)
	var behavior := str(_bad_chunk_ids.get(chunk_id, ""))
	if behavior == "null":
		return null
	if behavior == "invalid":
		return Zone.load_from_strings(
			"###\n#X#\n###",
			{"legend": {"#": {"type": "wall", "walkable": false}}, "entry": [1, 1]},
			"bad.map",
			"bad.json"
		)
	return _make_zone()


func _make_zone() -> Zone:
	return Zone.load_from_strings(
		"###\n#.#\n###",
		{
			"legend": {
				"#": {"type": "wall", "walkable": false},
				".": {"type": "floor", "walkable": true},
			},
			"entry": [1, 1],
		},
		"chunk.map",
		"chunk.json"
	)


func _assert_ids(actual: Array, expected: Array, message: String = "") -> void:
	assert_eq(actual.size(), expected.size(), "%s: expected %s, got %s" % [message, str(expected), str(actual)])
	for i in range(mini(actual.size(), expected.size())):
		assert_eq(actual[i], expected[i], "%s: expected %s, got %s" % [message, str(expected), str(actual)])


func _has_error(loader: ChunkLoader, fragment: String) -> bool:
	for err in loader.errors:
		if fragment in err:
			return true
	return false


func test_radius_zero_loads_only_player_chunk() -> void:
	var loader := _make_loader(_make_world(0))

	var result := loader.update(Vector2i(5, 5))

	_assert_ids(result["loaded"], ["c_0_0"], "loaded")
	_assert_ids(result["unloaded"], [], "unloaded")
	_assert_ids(loader.loaded_ids(), ["c_0_0"], "loaded_ids")
	assert_true(loader.is_loaded("c_0_0"))
	assert_false(loader.is_loaded("c_1_0"))
	var zone := loader.zone_for("c_0_0")
	assert_not_null(zone)
	assert_true(zone.is_valid())
	assert_null(loader.zone_for("c_1_0"))
	_assert_ids(loader.errors, [], "no errors expected")


func test_same_chunk_is_not_reloaded() -> void:
	var loader := _make_loader(_make_world(0))
	loader.update(Vector2i(5, 5))

	var result := loader.update(Vector2i(10, 10))

	_assert_ids(result["loaded"], [], "same chunk must not reload")
	_assert_ids(result["unloaded"], [], "same chunk must not unload")
	_assert_ids(_calls, ["c_0_0"], "zone loader must be called once")


func test_radius_zero_move_swaps_loaded_chunk() -> void:
	var loader := _make_loader(_make_world(0))
	loader.update(Vector2i(5, 5))

	var result := loader.update(Vector2i(40, 5))

	_assert_ids(result["loaded"], ["c_1_0"], "loaded")
	_assert_ids(result["unloaded"], ["c_0_0"], "unloaded")
	_assert_ids(loader.loaded_ids(), ["c_1_0"], "loaded_ids")
	assert_false(loader.is_loaded("c_0_0"))
	assert_null(loader.zone_for("c_0_0"))
	_assert_ids(_calls, ["c_0_0", "c_1_0"], "each chunk loaded once")


func test_radius_one_loads_neighbours_and_reports_deltas() -> void:
	var loader := _make_loader(_make_world(1))

	var result := loader.update(Vector2i(5, 5))
	_assert_ids(result["loaded"], ["c_0_0", "c_0_1", "c_1_0", "c_1_1"], "initial 2x2 block at the corner")
	_assert_ids(result["unloaded"], [], "nothing to unload yet")

	result = loader.update(Vector2i(40, 5))  # player chunk cell (1, 0)
	_assert_ids(result["loaded"], ["c_2_0", "c_2_1"], "the new right column is added")
	_assert_ids(result["unloaded"], [], "nothing left the radius yet")
	_assert_ids(loader.loaded_ids(), ["c_0_0", "c_0_1", "c_1_0", "c_1_1", "c_2_0", "c_2_1"], "loaded_ids")

	result = loader.update(Vector2i(70, 5))  # player chunk cell (2, 0)
	_assert_ids(result["loaded"], [], "everything in range is already loaded")
	_assert_ids(result["unloaded"], ["c_0_0", "c_0_1"], "the old left column is unloaded")
	_assert_ids(loader.loaded_ids(), ["c_1_0", "c_1_1", "c_2_0", "c_2_1"], "loaded_ids after sliding")

	_assert_ids(_calls, ["c_0_0", "c_0_1", "c_1_0", "c_1_1", "c_2_0", "c_2_1"], "only new chunks are loaded")
	var unique_calls: Dictionary = {}
	for chunk_id: String in _calls:
		unique_calls[chunk_id] = true
	assert_eq(unique_calls.size(), _calls.size(), "no chunk may be loaded twice: %s" % str(_calls))


func test_moving_outside_defined_chunks_unloads_everything() -> void:
	var loader := _make_loader(_make_world(1))
	loader.update(Vector2i(5, 5))

	var result := loader.update(Vector2i(5000, 5000))

	_assert_ids(result["loaded"], [], "no chunk near an empty area")
	assert_gt(result["unloaded"].size(), 0, "previous chunks must be unloaded")
	_assert_ids(loader.loaded_ids(), [], "nothing stays loaded")
	assert_eq(loader.zone_for("c_0_0"), null)


func test_zone_returning_null_is_reported_not_loaded() -> void:
	var map := _make_world(0)
	_bad_chunk_ids["c_0_0"] = "null"
	var loader := _make_loader(map)

	var result := loader.update(Vector2i(5, 5))

	_assert_ids(result["loaded"], [], "failed chunk must not be loaded")
	assert_false(loader.is_loaded("c_0_0"))
	assert_null(loader.zone_for("c_0_0"))
	assert_gt(loader.errors.size(), 0, "failure must be reported")
	assert_true(_has_error(loader, "c_0_0"), "error must mention the chunk: %s" % str(loader.errors))


func test_invalid_zone_is_reported_not_loaded() -> void:
	var map := _make_world(0)
	_bad_chunk_ids["c_0_0"] = "invalid"
	var loader := _make_loader(map)

	var result := loader.update(Vector2i(5, 5))

	_assert_ids(result["loaded"], [], "invalid zone must not be loaded")
	assert_false(loader.is_loaded("c_0_0"))
	assert_gt(loader.errors.size(), 0)
	assert_true(_has_error(loader, "zone failed to load"), "errors: %s" % str(loader.errors))


func test_bad_chunk_does_not_stop_other_chunks_from_loading() -> void:
	var map := _make_world(1)
	_bad_chunk_ids["c_1_1"] = "invalid"
	var loader := _make_loader(map)

	var result := loader.update(Vector2i(40, 40))  # chunk cell (1, 1)

	assert_eq(result["loaded"].size(), 8, "the other 8 chunks must still load")
	assert_false(loader.is_loaded("c_1_1"))
	assert_eq(loader.loaded_ids().size(), 8)
	assert_gt(loader.errors.size(), 0)


func test_invalid_world_map_reports_error() -> void:
	var map := WorldMap.load_from_dict({"chunks": []})
	var loader := _make_loader(map)

	var result := loader.update(Vector2i(0, 0))

	_assert_ids(result["loaded"], [])
	_assert_ids(result["unloaded"], [])
	assert_gt(loader.errors.size(), 0)
	assert_true(_has_error(loader, "world map is invalid"), "errors: %s" % str(loader.errors))


func test_missing_zone_loader_reports_error() -> void:
	var loader := ChunkLoader.new(_make_world(0))

	var result := loader.update(Vector2i(5, 5))

	_assert_ids(result["loaded"], [], "nothing can load without a loader")
	_assert_ids(loader.loaded_ids(), [])
	assert_gt(loader.errors.size(), 0)
	assert_true(_has_error(loader, "no zone loader configured"), "errors: %s" % str(loader.errors))
