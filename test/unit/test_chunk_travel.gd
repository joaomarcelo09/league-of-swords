extends GutTest

const CHUNK_SIZE := 32

var _calls: Array[String] = []
var _loader: ChunkLoader = null


func before_each() -> void:
	_calls.clear()
	_loader = null


func _gate(transition_id: String, from_chunk: String, from_tile: Array, to_chunk: String, to_tile: Array, extra: Dictionary = {}) -> Dictionary:
	var transition := {
		"id": transition_id,
		"kind": "gate",
		"from": {"chunk": from_chunk, "tile": from_tile},
		"to": {"chunk": to_chunk, "tile": to_tile},
	}
	transition.merge(extra, true)
	return transition


func _door_to_zone(transition_id: String, from_chunk: String, from_tile: Array, zone_name: String, to_tile: Array) -> Dictionary:
	return {
		"id": transition_id,
		"kind": "door",
		"from": {"chunk": from_chunk, "tile": from_tile},
		"to": {"zone": zone_name, "tile": to_tile},
	}


func _make_world(load_radius: int = 1) -> WorldMap:
	var chunks: Array = []
	for x in range(5):
		chunks.append({"id": "c_%d" % x, "grid": [x, 0], "zone": "test_small", "kind": "plains"})
	var transitions: Array = [
		_gate("east_0", "c_0", [31, 5], "c_1", [0, 5]),
		_gate("west_1", "c_1", [0, 5], "c_0", [31, 5]),
		_gate("east_2", "c_2", [5, 10], "c_3", [0, 10]),
		_gate("east_3", "c_3", [5, 15], "c_4", [0, 15]),
		_gate("boss_gate", "c_4", [10, 5], "c_3", [0, 5], {"requires_boss": "warden"}),
		_door_to_zone("dungeon_door", "c_2", [10, 10], "test_arena", [3, 2]),
		_gate("side_door", "c_3", [20, 20], "c_4", [15, 15], {"kind": "door"}),
	]
	var map := WorldMap.load_from_dict({
		"chunk_size": [CHUNK_SIZE, CHUNK_SIZE],
		"load_radius": load_radius,
		"chunks": chunks,
		"transitions": transitions,
	})
	assert_true(map.is_valid(), "test world must be valid: %s" % str(map.errors))
	return map


func _make_travel(map: WorldMap) -> ChunkTravel:
	_loader = ChunkLoader.new(map, Callable(self, "_load_zone"))
	return ChunkTravel.new(map, _loader)


func _load_zone(chunk_id: String) -> Zone:
	_calls.append(chunk_id)
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


func test_tile_without_transition_returns_none() -> void:
	var travel := _make_travel(_make_world())

	var result := travel.travel("c_0", Vector2i(0, 0), [])

	assert_false(result["ok"])
	assert_eq(result["reason"], "none")
	_assert_ids(_loader.loaded_ids(), [], "nothing may load")
	_assert_ids(_calls, [], "zone loader must not be called")


func test_gate_travel_loads_destination_neighbourhood() -> void:
	var travel := _make_travel(_make_world())

	var result := travel.travel("c_0", Vector2i(31, 5), [])

	assert_true(result["ok"], str(result))
	assert_eq(result["kind"], "gate")
	assert_eq(result["id"], "east_0")
	assert_eq(result["to_chunk"], "c_1")
	assert_eq(result["to_local"], Vector2i(0, 5))
	assert_eq(result["to_world"], Vector2i(CHUNK_SIZE, 5))
	_assert_ids(result["loaded"], ["c_0", "c_1", "c_2"], "destination cell (1, 0) with radius 1")
	_assert_ids(result["unloaded"], [], "nothing was loaded before")
	_assert_ids(_loader.loaded_ids(), ["c_0", "c_1", "c_2"], "loaded_ids")
	_assert_ids(_calls, ["c_0", "c_1", "c_2"], "only the destination neighbourhood is loaded")


func test_gate_travel_works_both_directions() -> void:
	var travel := _make_travel(_make_world())
	travel.travel("c_0", Vector2i(31, 5), [])

	var result := travel.travel("c_1", Vector2i(0, 5), [])

	assert_true(result["ok"], str(result))
	assert_eq(result["kind"], "gate")
	assert_eq(result["id"], "west_1")
	assert_eq(result["to_chunk"], "c_0")
	assert_eq(result["to_local"], Vector2i(31, 5))
	assert_eq(result["to_world"], Vector2i(31, 5))
	_assert_ids(result["loaded"], [], "the c_0 neighbourhood is already loaded")
	_assert_ids(result["unloaded"], ["c_2"], "c_2 left the destination radius")
	_assert_ids(_loader.loaded_ids(), ["c_0", "c_1"], "loaded_ids after returning")


func test_only_destination_neighbourhood_is_loaded_and_unloaded() -> void:
	var travel := _make_travel(_make_world())
	travel.travel("c_0", Vector2i(31, 5), [])  # near c_0: c_0, c_1, c_2

	var result := travel.travel("c_2", Vector2i(5, 10), [])  # near c_3: c_2, c_3, c_4

	assert_true(result["ok"], str(result))
	assert_eq(result["to_chunk"], "c_3")
	assert_eq(result["to_world"], Vector2i(3 * CHUNK_SIZE, 10))
	_assert_ids(result["loaded"], ["c_3", "c_4"], "only the new right-side chunks load")
	_assert_ids(result["unloaded"], ["c_0", "c_1"], "only the old left-side chunks unload")
	_assert_ids(_loader.loaded_ids(), ["c_2", "c_3", "c_4"], "loaded_ids")
	_assert_ids(_calls, ["c_0", "c_1", "c_2", "c_3", "c_4"], "each chunk is loaded once")


func test_locked_boss_gate_does_not_load() -> void:
	var travel := _make_travel(_make_world())

	var result := travel.travel("c_4", Vector2i(10, 5), [])

	assert_false(result["ok"])
	assert_eq(result["reason"], "locked")
	assert_eq(result["boss"], "warden")
	_assert_ids(_loader.loaded_ids(), [], "a locked gate must not load anything")
	_assert_ids(_calls, [], "zone loader must not be called")


func test_unlocked_boss_gate_travels() -> void:
	var travel := _make_travel(_make_world())

	var result := travel.travel("c_4", Vector2i(10, 5), ["warden"])

	assert_true(result["ok"], str(result))
	assert_eq(result["to_chunk"], "c_3")
	_assert_ids(result["loaded"], ["c_2", "c_3", "c_4"], "destination neighbourhood")
	_assert_ids(_loader.loaded_ids(), ["c_2", "c_3", "c_4"], "loaded_ids")


func test_door_to_zone_leaves_loader_untouched() -> void:
	var travel := _make_travel(_make_world())
	_loader.update(Vector2i(5, 5))  # load the c_0 neighbourhood first
	_calls.clear()
	var before := _loader.loaded_ids()

	var result := travel.travel("c_2", Vector2i(10, 10), [])

	assert_true(result["ok"], str(result))
	assert_eq(result["kind"], "door")
	assert_eq(result["id"], "dungeon_door")
	assert_eq(result["to_zone"], "test_arena")
	assert_eq(result["to_tile"], Vector2i(3, 2))
	assert_false(result.has("to_chunk"), "a zone door has no chunk destination")
	assert_false(result.has("loaded"), "a zone door does not load chunks")
	assert_false(result.has("unloaded"), "a zone door does not load chunks")
	_assert_ids(_loader.loaded_ids(), before, "loader state must not change")
	_assert_ids(_calls, [], "zone loader must not be called")


func test_door_to_chunk_loads_like_a_gate() -> void:
	var travel := _make_travel(_make_world())

	var result := travel.travel("c_3", Vector2i(20, 20), [])

	assert_true(result["ok"], str(result))
	assert_eq(result["kind"], "door")
	assert_eq(result["to_chunk"], "c_4")
	assert_eq(result["to_local"], Vector2i(15, 15))
	assert_eq(result["to_world"], Vector2i(4 * CHUNK_SIZE + 15, 15))
	_assert_ids(result["loaded"], ["c_3", "c_4"], "destination cell (4, 0) with radius 1")
	_assert_ids(_loader.loaded_ids(), ["c_3", "c_4"], "loaded_ids")


func test_unknown_chunk_is_reported() -> void:
	var travel := _make_travel(_make_world())

	var result := travel.travel("missing", Vector2i(0, 0), [])

	assert_false(result["ok"])
	assert_eq(result["reason"], "unknown_chunk")
	assert_gt(travel.errors.size(), 0, "failure must be reported")
	_assert_ids(_loader.loaded_ids(), [], "nothing may load")
	_assert_ids(_calls, [], "zone loader must not be called")


func test_invalid_world_map_is_reported() -> void:
	var map := WorldMap.load_from_dict({"chunks": []})
	var travel := ChunkTravel.new(map, ChunkLoader.new(map, Callable(self, "_load_zone")))

	var result := travel.travel("any", Vector2i(0, 0), [])

	assert_false(result["ok"])
	assert_eq(result["reason"], "invalid_world")
	assert_gt(travel.errors.size(), 0, "failure must be reported")
	_assert_ids(_calls, [], "zone loader must not be called")


func test_gate_without_loader_is_reported() -> void:
	var map := _make_world()
	var travel := ChunkTravel.new(map)

	var result := travel.travel("c_0", Vector2i(31, 5), [])

	assert_false(result["ok"])
	assert_eq(result["reason"], "no_loader")
	assert_gt(travel.errors.size(), 0, "failure must be reported")
