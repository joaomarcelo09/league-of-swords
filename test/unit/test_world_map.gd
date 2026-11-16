extends GutTest

const WORLD_PATH := "res://data/zones/floor1/world.json"


func _make_world(chunks: Array, chunk_size: Variant = [32, 32], load_radius: Variant = 1) -> Dictionary:
	return {
		"chunk_size": chunk_size,
		"load_radius": load_radius,
		"chunks": chunks,
	}


func _chunk(chunk_id: String, cell: Array, zone_name: String = "test_small", kind: String = "plains") -> Dictionary:
	return {"id": chunk_id, "grid": cell, "zone": zone_name, "kind": kind}


func _row_of_three() -> Array:
	return [
		_chunk("a", [0, 0]),
		_chunk("b", [1, 0]),
		_chunk("c", [2, 0]),
	]


func _grid_of_nine() -> Array:
	var chunks: Array = []
	for y in range(3):
		for x in range(3):
			chunks.append(_chunk("c_%d_%d" % [x, y], [x, y]))
	return chunks


func _all_ids_of_nine() -> Array:
	var ids: Array = []
	for y in range(3):
		for x in range(3):
			ids.append("c_%d_%d" % [x, y])
	ids.sort()
	return ids


func _assert_ids(actual: Array, expected: Array, message: String = "") -> void:
	assert_eq(actual.size(), expected.size(), "%s: expected %s, got %s" % [message, str(expected), str(actual)])
	for i in range(mini(actual.size(), expected.size())):
		assert_eq(actual[i], expected[i], "%s: expected %s, got %s" % [message, str(expected), str(actual)])


func _has_error(map: WorldMap, fragment: String) -> bool:
	for err in map.errors:
		if fragment in err:
			return true
	return false


func test_valid_world_parses_chunks() -> void:
	var map := WorldMap.load_from_dict(_make_world(_row_of_three()))
	assert_true(map.is_valid(), "world should be valid: %s" % str(map.errors))
	assert_eq(map.chunk_size, Vector2i(32, 32))
	assert_eq(map.load_radius, 1)
	_assert_ids(map.chunk_ids(), ["a", "b", "c"])
	assert_true(map.has_chunk("a"))
	assert_false(map.has_chunk("missing"))
	assert_eq(map.zone_stem("a"), "test_small")
	assert_eq(map.chunk_kind("a"), "plains")
	assert_eq(map.grid_cell("b"), Vector2i(1, 0))
	assert_eq(map.zone_stem("missing"), "")
	assert_eq(map.chunk_kind("missing"), "")
	assert_eq(map.grid_cell("missing"), Vector2i(-1, -1))


func test_whole_float_numbers_are_accepted() -> void:
	var map := WorldMap.load_from_dict(_make_world([_chunk("a", [0.0, 0.0])], [32.0, 32.0], 1.0))
	assert_true(map.is_valid(), "whole floats should be accepted: %s" % str(map.errors))
	assert_eq(map.chunk_size, Vector2i(32, 32))
	assert_eq(map.load_radius, 1)
	assert_eq(map.grid_cell("a"), Vector2i(0, 0))


func test_duplicate_chunk_id_is_error() -> void:
	var map := WorldMap.load_from_dict(_make_world([
		_chunk("same", [0, 0]),
		_chunk("same", [1, 0]),
	]))
	assert_false(map.is_valid())
	assert_true(_has_error(map, "id 'same' is duplicated"), "errors: %s" % str(map.errors))
	assert_eq(map.chunk_ids().size(), 1, "the first chunk with the duplicated id is kept")


func test_duplicate_grid_cell_is_error() -> void:
	var map := WorldMap.load_from_dict(_make_world([
		_chunk("a", [1, 1]),
		_chunk("b", [1, 1]),
	]))
	assert_false(map.is_valid())
	assert_true(_has_error(map, "grid cell [1, 1] is already used by 'a'"), "errors: %s" % str(map.errors))
	assert_eq(map.chunk_at_cell(Vector2i(1, 1)), "a")


func test_invalid_chunk_size_is_error() -> void:
	var bad_sizes: Array = [[0, 32], [32, 0], [-1, 32], [32], "wide", null]
	for bad_size: Variant in bad_sizes:
		var map := WorldMap.load_from_dict(_make_world([], bad_size))
		assert_false(map.is_valid(), "chunk_size %s must be invalid" % str(bad_size))
		assert_true(_has_error(map, "chunk_size"), "expected chunk_size error for %s, got %s" % [str(bad_size), str(map.errors)])

	var missing := WorldMap.load_from_dict({"load_radius": 0, "chunks": []})
	assert_false(missing.is_valid())
	assert_true(_has_error(missing, "Missing 'chunk_size' field"), "errors: %s" % str(missing.errors))


func test_invalid_load_radius_is_error() -> void:
	var bad_radii: Array = [-1, 1.5, "1", null]
	for bad_radius: Variant in bad_radii:
		var map := WorldMap.load_from_dict(_make_world([], [32, 32], bad_radius))
		assert_false(map.is_valid(), "load_radius %s must be invalid" % str(bad_radius))
		assert_true(_has_error(map, "load_radius"), "expected load_radius error for %s, got %s" % [str(bad_radius), str(map.errors)])

	var missing := WorldMap.load_from_dict({"chunk_size": [32, 32], "chunks": []})
	assert_false(missing.is_valid())
	assert_true(_has_error(missing, "Missing 'load_radius' field"), "errors: %s" % str(missing.errors))


func test_missing_chunk_fields_are_errors() -> void:
	for missing_key in ["id", "grid", "zone", "kind"]:
		var chunk := _chunk("x", [0, 0])
		chunk.erase(missing_key)
		var map := WorldMap.load_from_dict(_make_world([chunk]))
		assert_false(map.is_valid(), "chunk without '%s' must be invalid" % missing_key)
		var expected := "missing '%s' field" % missing_key
		assert_true(_has_error(map, expected), "expected '%s' error, got %s" % [expected, str(map.errors)])


func test_invalid_chunk_field_types_are_errors() -> void:
	var cases: Array = [
		{"id": 5, "grid": [0, 0], "zone": "test_small", "kind": "plains"},
		{"id": "", "grid": [0, 0], "zone": "test_small", "kind": "plains"},
		{"id": "x", "grid": "cell", "zone": "test_small", "kind": "plains"},
		{"id": "x", "grid": [0, 0], "zone": "", "kind": "plains"},
		{"id": "x", "grid": [0, 0], "zone": "test_small", "kind": 7},
	]
	for chunk: Dictionary in cases:
		var map := WorldMap.load_from_dict(_make_world([chunk]))
		assert_false(map.is_valid(), "chunk %s must be invalid" % str(chunk))
		assert_gt(map.errors.size(), 0)

	var not_object := WorldMap.load_from_dict(_make_world(["nope"]))
	assert_false(not_object.is_valid())
	assert_true(_has_error(not_object, "chunk[0] must be an object"), "errors: %s" % str(not_object.errors))


func test_invalid_top_level_and_missing_chunks() -> void:
	var not_object := WorldMap.load_from_dict([])
	assert_false(not_object.is_valid())
	assert_true(_has_error(not_object, "Top-level JSON must be an object"), "errors: %s" % str(not_object.errors))

	var missing := WorldMap.load_from_dict({"chunk_size": [32, 32], "load_radius": 0})
	assert_false(missing.is_valid())
	assert_true(_has_error(missing, "Missing 'chunks' field"), "errors: %s" % str(missing.errors))

	var not_array := WorldMap.load_from_dict({"chunk_size": [32, 32], "load_radius": 0, "chunks": {}})
	assert_false(not_array.is_valid())
	assert_true(_has_error(not_array, "'chunks' must be an array"), "errors: %s" % str(not_array.errors))


func test_chunk_at_cell_lookup() -> void:
	var map := WorldMap.load_from_dict(_make_world(_row_of_three()))
	assert_eq(map.chunk_at_cell(Vector2i(0, 0)), "a")
	assert_eq(map.chunk_at_cell(Vector2i(1, 0)), "b")
	assert_eq(map.chunk_at_cell(Vector2i(2, 0)), "c")
	assert_eq(map.chunk_at_cell(Vector2i(3, 0)), "")
	assert_eq(map.chunk_at_cell(Vector2i(9, 9)), "")
	assert_eq(map.chunk_at_cell(Vector2i(-1, 0)), "")


func test_world_to_chunk_edges_and_round_trip() -> void:
	var map := WorldMap.load_from_dict(_make_world(_row_of_three()))

	var at_31 := map.world_to_chunk(Vector2i(31, 31))
	assert_eq(at_31["chunk_id"], "a")
	assert_eq(at_31["local_tile"], Vector2i(31, 31))
	assert_eq(at_31["chunk_cell"], Vector2i(0, 0))

	var at_32 := map.world_to_chunk(Vector2i(32, 0))
	assert_eq(at_32["chunk_id"], "b", "tile 32 starts the next chunk")
	assert_eq(at_32["local_tile"], Vector2i(0, 0))
	assert_eq(at_32["chunk_cell"], Vector2i(1, 0))

	assert_eq(map.chunk_id_at_tile(Vector2i(31, 0)), "a")
	assert_eq(map.chunk_id_at_tile(Vector2i(32, 0)), "b")
	assert_eq(map.chunk_id_at_tile(Vector2i(64, 31)), "c")
	assert_eq(map.chunk_id_at_tile(Vector2i(96, 0)), "", "no chunk is placed on cell (3, 0)")

	var undefined_tile := map.world_to_chunk(Vector2i(96, 7))
	assert_eq(undefined_tile["chunk_id"], "")
	assert_eq(undefined_tile["local_tile"], Vector2i(0, 7))

	for tile: Vector2i in [Vector2i(0, 0), Vector2i(31, 31), Vector2i(32, 5), Vector2i(63, 10), Vector2i(70, 20)]:
		var info := map.world_to_chunk(tile)
		assert_ne(info["chunk_id"], "", "tile %s should belong to a chunk" % str(tile))
		assert_eq(map.chunk_to_world(info["chunk_id"], info["local_tile"]), tile, "round trip failed for %s" % str(tile))


func test_chunk_to_world_uses_chunk_size() -> void:
	var map := WorldMap.load_from_dict(_make_world([_chunk("a", [2, 3])], [10, 20]))
	assert_true(map.is_valid(), str(map.errors))

	assert_eq(map.chunk_to_world("a", Vector2i(0, 0)), Vector2i(20, 60))
	assert_eq(map.chunk_to_world("a", Vector2i(9, 19)), Vector2i(29, 79))
	assert_eq(map.chunk_to_world("missing", Vector2i(0, 0)), Vector2i(-1, -1))


func test_neighbors() -> void:
	var map := WorldMap.load_from_dict(_make_world(_grid_of_nine()))
	_assert_ids(
		map.neighbors("c_1_1"),
		["c_0_0", "c_0_1", "c_0_2", "c_1_0", "c_1_2", "c_2_0", "c_2_1", "c_2_2"],
		"center has all 8 neighbours"
	)
	_assert_ids(map.neighbors("c_0_0"), ["c_0_1", "c_1_0", "c_1_1"], "corner has 3 neighbours")
	_assert_ids(map.neighbors("missing"), [], "unknown chunk has no neighbours")

	var single := WorldMap.load_from_dict(_make_world([_chunk("only", [5, 5])]))
	_assert_ids(single.neighbors("only"), [], "isolated chunk has no neighbours")


func test_chunks_near_uses_chebyshev_radius() -> void:
	var map := WorldMap.load_from_dict(_make_world(_grid_of_nine(), [32, 32], 1))

	_assert_ids(map.chunks_near(Vector2i(1, 1), 0), ["c_1_1"], "radius 0 is the player chunk only")
	_assert_ids(map.chunks_near(Vector2i(1, 1), 1), _all_ids_of_nine(), "radius 1 covers the 3x3 block")
	_assert_ids(map.chunks_near(Vector2i(0, 0), 1), ["c_0_0", "c_0_1", "c_1_0", "c_1_1"], "radius is clipped at the grid edge")
	_assert_ids(map.chunks_near(Vector2i(0, 0), 2), _all_ids_of_nine(), "radius 2 covers the whole 3x3")
	_assert_ids(map.chunks_near(Vector2i(9, 9), 1), [], "no chunks around an empty cell")
	_assert_ids(map.chunks_near(Vector2i(1, 1)), _all_ids_of_nine(), "negative radius falls back to load_radius")


func test_real_world_json_is_valid() -> void:
	var map := WorldMap.load_file(WORLD_PATH)
	assert_not_null(map)
	assert_true(map.is_valid(), "world.json errors: %s" % str(map.errors))
	assert_gt(map.chunk_size.x, 0, "chunk width must be positive")
	assert_gt(map.chunk_size.y, 0, "chunk height must be positive")
	assert_gte(map.load_radius, 0, "load_radius must be non-negative")
	assert_gt(map.chunk_ids().size(), 0, "world.json must place at least one chunk")

	for chunk_id: String in map.chunk_ids():
		var stem := map.zone_stem(chunk_id)
		assert_false(stem.is_empty(), "chunk '%s' must name a zone" % chunk_id)
		assert_true(FileAccess.file_exists("res://data/zones/floor1/%s.json" % stem), "zone json for chunk '%s' must exist" % chunk_id)
		assert_true(FileAccess.file_exists("res://data/zones/floor1/%s.map" % stem), "zone map for chunk '%s' must exist" % chunk_id)
		assert_false(map.chunk_kind(chunk_id).is_empty(), "chunk '%s' must have a kind" % chunk_id)


func test_missing_world_file_is_invalid() -> void:
	var map := WorldMap.load_file("res://data/zones/floor1/does_not_exist.json")
	assert_not_null(map)
	assert_false(map.is_valid())
	assert_gt(map.errors.size(), 0)
