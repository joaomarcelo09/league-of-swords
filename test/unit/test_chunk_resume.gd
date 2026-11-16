extends GutTest

const CHUNK_SIZE := 32

var _calls: Array[String] = []
var _loader: ChunkLoader = null


func before_each() -> void:
	_calls.clear()
	_loader = null


func _make_world(load_radius: int = 1) -> WorldMap:
	var chunks: Array = []
	for x in range(5):
		chunks.append({"id": "c_%d" % x, "grid": [x, 0], "zone": "test_small", "kind": "plains"})
	var map := WorldMap.load_from_dict({
		"chunk_size": [CHUNK_SIZE, CHUNK_SIZE],
		"load_radius": load_radius,
		"chunks": chunks,
	})
	assert_true(map.is_valid(), "test world must be valid: %s" % str(map.errors))
	return map


func _make_loader(map: WorldMap) -> ChunkLoader:
	_loader = ChunkLoader.new(map, Callable(self, "_load_zone"))
	return _loader


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


func _make_character(chunk: String = "", local_position: Array = [0.0, 0.0]) -> CharacterState:
	var character := CharacterState.new()
	character.id = "rowan"
	character.name = "Rowan"
	character.zone = "floor1"
	character.chunk = chunk
	character.position = local_position
	return character


func _assert_ids(actual: Array, expected: Array, message: String = "") -> void:
	assert_eq(actual.size(), expected.size(), "%s: expected %s, got %s" % [message, str(expected), str(actual)])
	for i in range(mini(actual.size(), expected.size())):
		assert_eq(actual[i], expected[i], "%s: expected %s, got %s" % [message, str(expected), str(actual)])


func test_classic_save_without_chunk_does_not_touch_loader() -> void:
	var map := _make_world()
	var loader := _make_loader(map)

	var result := ChunkResume.resume(map, loader, _make_character("", [4.0, 8.0]))

	assert_true(result["ok"], str(result))
	assert_false(result["chunked"], "An empty chunk means a classic single-zone save")
	assert_false(result.has("world_tile"))
	_assert_ids(loader.loaded_ids(), [], "a classic save must not load chunks")
	_assert_ids(_calls, [], "zone loader must not be called")


func test_unknown_chunk_is_reported() -> void:
	var map := _make_world()
	var loader := _make_loader(map)

	var result := ChunkResume.resume(map, loader, _make_character("missing", [1.0, 1.0]))

	assert_false(result["ok"])
	assert_eq(result["reason"], "unknown_chunk")
	_assert_ids(loader.loaded_ids(), [], "an unknown chunk must not load anything")
	_assert_ids(_calls, [], "zone loader must not be called")


func test_resume_loads_only_the_neighbourhood() -> void:
	var map := _make_world()
	var loader := _make_loader(map)

	var result := ChunkResume.resume(map, loader, _make_character("c_2", [5.0, 10.0]))

	assert_true(result["ok"], str(result))
	assert_true(result["chunked"])
	assert_eq(result["chunk"], "c_2")
	assert_eq(result["world_tile"], Vector2i(2 * CHUNK_SIZE + 5, 10), "world tile comes from chunk_to_world")
	_assert_ids(result["loaded"], ["c_1", "c_2", "c_3"], "only the neighbourhood of c_2 loads")
	_assert_ids(result["unloaded"], [], "nothing was loaded before")
	_assert_ids(loader.loaded_ids(), ["c_1", "c_2", "c_3"], "loaded_ids")
	_assert_ids(_calls, ["c_1", "c_2", "c_3"], "only the saved chunk's neighbourhood is loaded")


func test_resume_unloads_chunks_outside_the_new_neighbourhood() -> void:
	var map := _make_world()
	var loader := _make_loader(map)
	loader.update(Vector2i(5, 5))  # c_0 neighbourhood: c_0, c_1
	_calls.clear()

	var result := ChunkResume.resume(map, loader, _make_character("c_2", [5.0, 10.0]))

	assert_true(result["ok"], str(result))
	_assert_ids(result["loaded"], ["c_2", "c_3"], "only chunks that left the radius reload")
	_assert_ids(result["unloaded"], ["c_0"], "c_0 left the neighbourhood")
	_assert_ids(loader.loaded_ids(), ["c_1", "c_2", "c_3"], "loaded_ids after resume")
	_assert_ids(_calls, ["c_2", "c_3"], "each chunk is loaded once")


func test_capture_then_resume_across_a_chunk_border() -> void:
	var map := _make_world()
	var loader := _make_loader(map)
	var character := _make_character()

	# Last column of c_1 and first column of c_2: neighbours across the border.
	var west_capture := ChunkResume.capture(map, character, Vector2i(CHUNK_SIZE * 2 - 1, 7))
	assert_true(west_capture["ok"], str(west_capture))
	assert_eq(character.chunk, "c_1")
	assert_eq(character.position, [float(CHUNK_SIZE - 1), 7.0])
	assert_eq(west_capture["local_tile"], Vector2i(CHUNK_SIZE - 1, 7))

	var east_capture := ChunkResume.capture(map, character, Vector2i(CHUNK_SIZE * 2, 7))
	assert_true(east_capture["ok"], str(east_capture))
	assert_eq(character.chunk, "c_2")
	assert_eq(character.position, [0.0, 7.0])
	assert_eq(east_capture["local_tile"], Vector2i(0, 7))

	var result := ChunkResume.resume(map, loader, character)

	assert_true(result["ok"], str(result))
	assert_eq(result["chunk"], "c_2")
	assert_eq(result["world_tile"], Vector2i(CHUNK_SIZE * 2, 7), "capture then resume must return the same world tile")
	assert_eq(character.zone, "floor1", "capture leaves the zone untouched")
	_assert_ids(result["loaded"], ["c_1", "c_2", "c_3"], "the neighbourhood across the border is loaded")
	_assert_ids(loader.loaded_ids(), ["c_1", "c_2", "c_3"], "loaded_ids")


func test_capture_position_keeps_sub_tile_precision() -> void:
	var map := _make_world()
	var character := _make_character()

	var capture_result := ChunkResume.capture_position(map, character, Vector2(CHUNK_SIZE + 4.25, 7.75))

	assert_true(capture_result["ok"], str(capture_result))
	assert_eq(character.chunk, "c_1")
	assert_eq(character.position, [4.25, 7.75], "the chunk-local position keeps its fraction")
	assert_eq(capture_result["local_tile"], Vector2i(4, 7))
	assert_eq(capture_result["world_tile"], Vector2i(CHUNK_SIZE + 4, 7))

	var result := ChunkResume.resume(map, _make_loader(map), character)

	assert_true(result["ok"], str(result))
	assert_eq(result["world_tile"], Vector2i(CHUNK_SIZE + 4, 7))
	assert_eq(result["world_pos"], Vector2(CHUNK_SIZE + 4.25, 7.75), "resume returns the saved float position")


func test_capture_position_rejects_a_non_finite_position() -> void:
	var map := _make_world()
	var character := _make_character()

	var result := ChunkResume.capture_position(map, character, Vector2(INF, 1.0))

	assert_false(result["ok"])
	assert_eq(result["reason"], "invalid_position")
	assert_eq(character.chunk, "", "a failed capture must not change the character")


func test_capture_rejects_a_world_tile_outside_every_chunk() -> void:
	var map := _make_world()
	var character := _make_character()

	var result := ChunkResume.capture(map, character, Vector2i(5, CHUNK_SIZE))

	assert_false(result["ok"])
	assert_eq(result["reason"], "no_chunk")
	assert_eq(character.chunk, "", "a failed capture must not change the character")
	assert_eq(character.position, [0.0, 0.0])


func test_resume_requires_a_valid_map_and_loader() -> void:
	var map := _make_world()
	var character := _make_character("c_1", [1.0, 1.0])

	var no_map := ChunkResume.resume(null, _make_loader(map), character)
	assert_false(no_map["ok"])
	assert_eq(no_map["reason"], "no_map")
	_assert_ids(_calls, [], "zone loader must not be called")

	var no_loader := ChunkResume.resume(map, null, character)
	assert_false(no_loader["ok"])
	assert_eq(no_loader["reason"], "no_loader")

	var invalid_map := WorldMap.load_from_dict({"chunks": []})
	var invalid := ChunkResume.resume(invalid_map, ChunkLoader.new(invalid_map, Callable(self, "_load_zone")), character)
	assert_false(invalid["ok"])
	assert_eq(invalid["reason"], "invalid_world")
	_assert_ids(_calls, [], "zone loader must not be called")


func test_resume_rejects_a_position_outside_the_chunk() -> void:
	var map := _make_world()
	var loader := _make_loader(map)

	var result := ChunkResume.resume(map, loader, _make_character("c_1", [CHUNK_SIZE, 0.0]))

	assert_false(result["ok"])
	assert_eq(result["reason"], "invalid_position")
	_assert_ids(loader.loaded_ids(), [], "an out-of-bounds position must not load anything")
