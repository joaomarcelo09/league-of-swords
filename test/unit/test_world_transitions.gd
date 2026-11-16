extends GutTest

const WORLD_PATH := "res://data/zones/floor1/world.json"
const ZONES_DIR := "res://data/zones/floor1"


func _make_world(chunks: Array, transitions: Variant = null) -> Dictionary:
	var world := {
		"chunk_size": [32, 32],
		"load_radius": 1,
		"chunks": chunks,
	}
	if transitions != null:
		world["transitions"] = transitions
	return world


func _chunk(chunk_id: String, cell: Array, zone_name: String = "test_small", kind: String = "plains") -> Dictionary:
	return {"id": chunk_id, "grid": cell, "zone": zone_name, "kind": kind}


func _row_of_three() -> Array:
	return [
		_chunk("a", [0, 0]),
		_chunk("b", [1, 0]),
		_chunk("c", [2, 0]),
	]


func _gate(transition_id: String, from_chunk: String, from_tile: Array, to_chunk: String, to_tile: Array, extra: Dictionary = {}) -> Dictionary:
	var transition := {
		"id": transition_id,
		"kind": "gate",
		"from": {"chunk": from_chunk, "tile": from_tile},
		"to": {"chunk": to_chunk, "tile": to_tile},
	}
	transition.merge(extra, true)
	return transition


func _door_to_zone(transition_id: String, from_chunk: String, from_tile: Array, zone_name: String, to_tile: Array, extra: Dictionary = {}) -> Dictionary:
	var transition := {
		"id": transition_id,
		"kind": "door",
		"from": {"chunk": from_chunk, "tile": from_tile},
		"to": {"zone": zone_name, "tile": to_tile},
	}
	transition.merge(extra, true)
	return transition


func _load_zone(stem: String) -> Zone:
	return Zone.load_files(ZONES_DIR.path_join(stem + ".map"), ZONES_DIR.path_join(stem + ".json"))


func _has_error(map: WorldMap, fragment: String) -> bool:
	for err in map.errors:
		if fragment in err:
			return true
	return false


func test_valid_transitions_parse_and_lookup() -> void:
	var map := WorldMap.load_from_dict(_make_world(_row_of_three(), [
		_gate("b_to_a", "b", [0, 5], "a", [31, 5]),
		_gate("a_to_b", "a", [31, 5], "b", [0, 5], {"label": "East Gate"}),
		_door_to_zone("b_to_dungeon", "b", [10, 10], "test_arena", [3, 2]),
	]))
	assert_true(map.is_valid(), "transitions should parse: %s" % str(map.errors))

	var a_transitions := map.transitions_of("a")
	assert_eq(a_transitions.size(), 1)
	assert_eq(a_transitions[0]["id"], "a_to_b")
	assert_eq(a_transitions[0]["kind"], "gate")
	assert_eq(a_transitions[0]["from_chunk"], "a")
	assert_eq(a_transitions[0]["from_tile"], Vector2i(31, 5))
	assert_eq(a_transitions[0]["to_chunk"], "b")
	assert_eq(a_transitions[0]["to_zone"], "")
	assert_eq(a_transitions[0]["to_tile"], Vector2i(0, 5))
	assert_eq(a_transitions[0]["requires_boss"], "")
	assert_eq(a_transitions[0]["label"], "East Gate")

	var b_transitions := map.transitions_of("b")
	assert_eq(b_transitions.size(), 2)
	assert_eq(b_transitions[0]["id"], "b_to_a", "transitions_of is sorted by id")
	assert_eq(b_transitions[1]["id"], "b_to_dungeon")

	var door := map.transition_at("b", Vector2i(10, 10))
	assert_eq(door["kind"], "door")
	assert_eq(door["to_zone"], "test_arena")
	assert_eq(door["to_chunk"], "")
	assert_eq(door["to_tile"], Vector2i(3, 2))

	assert_eq(map.transition_at("b", Vector2i(0, 5))["id"], "b_to_a")
	assert_eq(map.transition_at("b", Vector2i(5, 5)), {}, "tile without a transition")
	assert_eq(map.transition_at("missing", Vector2i(0, 0)), {}, "unknown chunk has no transition")
	assert_eq(map.transitions_of("missing").size(), 0)

	door["id"] = "mutated"
	assert_eq(map.transition_at("b", Vector2i(10, 10))["id"], "b_to_dungeon", "lookups return copies")


func test_missing_transitions_field_is_allowed() -> void:
	var map := WorldMap.load_from_dict(_make_world(_row_of_three()))
	assert_true(map.is_valid(), str(map.errors))
	assert_eq(map.transitions_of("a").size(), 0)
	assert_eq(map.transition_at("a", Vector2i(0, 0)), {})


func test_transitions_must_be_an_array_of_objects() -> void:
	var not_array := WorldMap.load_from_dict(_make_world(_row_of_three(), {}))
	assert_false(not_array.is_valid())
	assert_true(_has_error(not_array, "'transitions' must be an array"), str(not_array.errors))

	var not_object := WorldMap.load_from_dict(_make_world(_row_of_three(), ["nope"]))
	assert_false(not_object.is_valid())
	assert_true(_has_error(not_object, "transition[0] must be an object"), str(not_object.errors))


func test_unknown_endpoint_chunks_are_errors() -> void:
	var bad_from := WorldMap.load_from_dict(_make_world(_row_of_three(), [
		_gate("bad_from", "missing", [0, 0], "a", [0, 0]),
	]))
	assert_false(bad_from.is_valid())
	assert_true(_has_error(bad_from, "references unknown chunk 'missing'"), str(bad_from.errors))
	assert_eq(bad_from.transitions_of("missing").size(), 0, "invalid transitions are not indexed")

	var bad_to := WorldMap.load_from_dict(_make_world(_row_of_three(), [
		_gate("bad_to", "a", [0, 0], "missing", [0, 0]),
	]))
	assert_false(bad_to.is_valid())
	assert_true(_has_error(bad_to, "references unknown chunk 'missing'"), str(bad_to.errors))
	assert_eq(bad_to.transition_at("a", Vector2i(0, 0)), {}, "invalid transitions are not indexed")


func test_tiles_outside_chunk_bounds_are_errors() -> void:
	var bad_tiles: Array = [
		{"from": [32, 0], "to": [0, 0]},
		{"from": [-1, 0], "to": [0, 0]},
		{"from": [0, 0], "to": [0, 32]},
		{"from": [0, 0], "to": [0, -1]},
	]
	for case: Dictionary in bad_tiles:
		var map := WorldMap.load_from_dict(_make_world(_row_of_three(), [
			_gate("bad_tile", "a", case["from"], "b", case["to"]),
		]))
		assert_false(map.is_valid(), "tiles %s must be invalid" % str(case))
		assert_true(_has_error(map, "outside chunk"), "expected bounds error for %s, got %s" % [str(case), str(map.errors)])

	var bad_zone_tile := WorldMap.load_from_dict(_make_world(_row_of_three(), [
		_door_to_zone("bad_zone_tile", "a", [0, 0], "test_arena", [-1, 2]),
	]))
	assert_false(bad_zone_tile.is_valid())
	assert_true(_has_error(bad_zone_tile, "must be non-negative for a zone target"), str(bad_zone_tile.errors))


func test_duplicate_transition_id_is_error() -> void:
	var map := WorldMap.load_from_dict(_make_world(_row_of_three(), [
		_gate("same", "a", [0, 0], "b", [0, 0]),
		_gate("same", "b", [1, 0], "c", [0, 0]),
	]))
	assert_false(map.is_valid())
	assert_true(_has_error(map, "id 'same' is duplicated"), str(map.errors))
	assert_eq(map.transitions_of("a").size(), 1, "the first transition with the duplicated id is kept")
	assert_eq(map.transitions_of("b").size(), 0, "the duplicate is dropped")


func test_bad_kind_is_error() -> void:
	var map := WorldMap.load_from_dict(_make_world(_row_of_three(), [
		_gate("portal", "a", [0, 0], "b", [0, 0], {"kind": "portal"}),
	]))
	assert_false(map.is_valid())
	assert_true(_has_error(map, "kind must be 'gate' or 'door'"), str(map.errors))
	assert_eq(map.transitions_of("a").size(), 0)


func test_duplicate_from_tile_is_error() -> void:
	var map := WorldMap.load_from_dict(_make_world(_row_of_three(), [
		_gate("first", "a", [4, 4], "b", [0, 0]),
		_gate("second", "a", [4, 4], "c", [0, 0]),
	]))
	assert_false(map.is_valid())
	assert_true(_has_error(map, "from tile [4, 4] in chunk 'a' is already used by 'first'"), str(map.errors))
	assert_eq(map.transition_at("a", Vector2i(4, 4))["id"], "first")

	var other_chunk := WorldMap.load_from_dict(_make_world(_row_of_three(), [
		_gate("first", "a", [4, 4], "b", [0, 0]),
		_gate("second", "b", [4, 4], "c", [0, 0]),
	]))
	assert_true(other_chunk.is_valid(), "the same local tile in another chunk is fine: %s" % str(other_chunk.errors))


func test_missing_and_invalid_transition_fields_are_errors() -> void:
	var cases: Array = [
		{"kind": "gate", "from": {"chunk": "a", "tile": [0, 0]}, "to": {"chunk": "b", "tile": [0, 0]}},
		{"id": "x", "from": {"chunk": "a", "tile": [0, 0]}, "to": {"chunk": "b", "tile": [0, 0]}},
		{"id": "", "kind": "gate", "from": {"chunk": "a", "tile": [0, 0]}, "to": {"chunk": "b", "tile": [0, 0]}},
		{"id": "x", "kind": "gate", "to": {"chunk": "b", "tile": [0, 0]}},
		{"id": "x", "kind": "gate", "from": {"chunk": "a", "tile": [0, 0]}},
		{"id": "x", "kind": "gate", "from": "a", "to": {"chunk": "b", "tile": [0, 0]}},
		{"id": "x", "kind": "gate", "from": {"chunk": "a", "tile": [0, 0]}, "to": "b"},
		{"id": "x", "kind": "gate", "from": {"chunk": "a", "tile": "here"}, "to": {"chunk": "b", "tile": [0, 0]}},
		{"id": "x", "kind": "gate", "from": {"chunk": "", "tile": [0, 0]}, "to": {"chunk": "b", "tile": [0, 0]}},
		{"id": "x", "kind": "door", "from": {"chunk": "a", "tile": [0, 0]}, "to": {"chunk": "b", "zone": "test_arena", "tile": [0, 0]}},
		{"id": "x", "kind": "door", "from": {"chunk": "a", "tile": [0, 0]}, "to": {"tile": [0, 0]}},
		{"id": "x", "kind": "door", "from": {"chunk": "a", "tile": [0, 0]}, "to": {"zone": "", "tile": [0, 0]}},
		{"id": "x", "kind": "gate", "from": {"chunk": "a", "tile": [0, 0]}, "to": {"chunk": "b", "tile": [0, 0]}, "requires_boss": 3},
		{"id": "x", "kind": "gate", "from": {"chunk": "a", "tile": [0, 0]}, "to": {"chunk": "b", "tile": [0, 0]}, "label": 3},
	]
	for transition: Dictionary in cases:
		var map := WorldMap.load_from_dict(_make_world(_row_of_three(), [transition]))
		assert_false(map.is_valid(), "transition %s must be invalid" % str(transition))
		assert_gt(map.errors.size(), 0)

	var gate_to_zone := WorldMap.load_from_dict(_make_world(_row_of_three(), [
		_gate("gate_zone", "a", [0, 0], "b", [0, 0], {"to": {"zone": "test_arena", "tile": [1, 1]}}),
	]))
	assert_false(gate_to_zone.is_valid())
	assert_true(_has_error(gate_to_zone, "only doors may target a zone"), str(gate_to_zone.errors))


func test_zone_door_return_link_parses() -> void:
	var map := WorldMap.load_from_dict(_make_world(_row_of_three(), [
		_door_to_zone("dungeon_door", "b", [10, 10], "test_arena", [3, 2], {
			"return": {"tile": [3, 3], "chunk": "a", "to_tile": [9, 10]},
		}),
	]))
	assert_true(map.is_valid(), "return link should parse: %s" % str(map.errors))

	var door := map.transition_at("b", Vector2i(10, 10))
	assert_eq(door["return_tile"], Vector2i(3, 3))
	assert_eq(door["return_chunk"], "a")
	assert_eq(door["return_to_tile"], Vector2i(9, 10))


func test_transitions_without_a_return_link_keep_empty_return_fields() -> void:
	var map := WorldMap.load_from_dict(_make_world(_row_of_three(), [
		_gate("a_to_b", "a", [31, 5], "b", [0, 5]),
		_door_to_zone("dungeon_door", "b", [10, 10], "test_arena", [3, 2]),
	]))
	assert_true(map.is_valid(), str(map.errors))

	var gate := map.transition_at("a", Vector2i(31, 5))
	assert_eq(gate["return_tile"], Vector2i(-1, -1))
	assert_eq(gate["return_chunk"], "")
	assert_eq(gate["return_to_tile"], Vector2i(-1, -1))
	var door := map.transition_at("b", Vector2i(10, 10))
	assert_eq(door["return_tile"], Vector2i(-1, -1))


func test_return_link_is_only_allowed_on_zone_doors() -> void:
	var on_gate := WorldMap.load_from_dict(_make_world(_row_of_three(), [
		_gate("a_to_b", "a", [31, 5], "b", [0, 5], {
			"return": {"tile": [3, 3], "chunk": "a", "to_tile": [1, 1]},
		}),
	]))
	assert_false(on_gate.is_valid())
	assert_true(_has_error(on_gate, "return is only allowed on doors to a zone"), str(on_gate.errors))

	var on_chunk_door := WorldMap.load_from_dict(_make_world(_row_of_three(), [
		_gate("door_to_chunk", "a", [5, 5], "b", [5, 5], {
			"kind": "door",
			"return": {"tile": [3, 3], "chunk": "a", "to_tile": [1, 1]},
		}),
	]))
	assert_false(on_chunk_door.is_valid())
	assert_true(_has_error(on_chunk_door, "return is only allowed on doors to a zone"), str(on_chunk_door.errors))


func test_invalid_return_links_are_errors() -> void:
	var cases: Array = [
		{"tile": [3, 3], "chunk": "a"},
		{"chunk": "a", "to_tile": [1, 1]},
		{"tile": [-1, 3], "chunk": "a", "to_tile": [1, 1]},
		{"tile": [3, 3], "chunk": "missing", "to_tile": [1, 1]},
		{"tile": [3, 3], "chunk": "a"},
		{"tile": [3, 3], "chunk": "a", "to_tile": [32, 1]},
	]
	for link: Dictionary in cases:
		var map := WorldMap.load_from_dict(_make_world(_row_of_three(), [
			_door_to_zone("dungeon_door", "b", [10, 10], "test_arena", [3, 2], {"return": link}),
		]))
		assert_false(map.is_valid(), "return link %s must be invalid" % str(link))
		assert_eq(map.transition_at("b", Vector2i(10, 10)), {}, "an invalid transition is not indexed")


func test_real_world_json_transitions_are_valid_and_walkable() -> void:
	var map := WorldMap.load_file(WORLD_PATH)
	assert_true(map.is_valid(), "world.json errors: %s" % str(map.errors))

	var transitions: Array[Dictionary] = []
	for chunk_id: String in map.chunk_ids():
		transitions.append_array(map.transitions_of(chunk_id))
	# Floor 1 chunks join seamlessly (open shared edges), so the list may be
	# empty; every transition it does hold must be valid and walkable.
	var seen_ids: Dictionary = {}
	var gate_count := 0
	var door_count := 0
	for transition: Dictionary in transitions:
		var transition_id := str(transition["id"])
		assert_false(seen_ids.has(transition_id), "transition id '%s' must be unique" % transition_id)
		seen_ids[transition_id] = true

		var kind := str(transition["kind"])
		if kind == "gate":
			gate_count += 1
		elif kind == "door":
			door_count += 1
		else:
			fail_test("unexpected transition kind '%s'" % kind)

		var from_chunk := str(transition["from_chunk"])
		assert_true(map.has_chunk(from_chunk), "from chunk '%s' must exist" % from_chunk)
		var from_stem: String = map.zone_stem(from_chunk)
		var from_zone := _load_zone(from_stem)
		assert_true(from_zone.is_valid(), "zone '%s' errors: %s" % [from_stem, str(from_zone.errors)])
		var from_tile: Vector2i = transition["from_tile"]
		assert_true(from_zone.is_walkable(from_tile), "from tile %s of '%s' must be walkable in '%s'" % [str(from_tile), transition_id, from_stem])

		var to_tile: Vector2i = transition["to_tile"]
		var to_chunk := str(transition["to_chunk"])
		if not to_chunk.is_empty():
			assert_true(map.has_chunk(to_chunk), "to chunk '%s' must exist" % to_chunk)
			var to_stem: String = map.zone_stem(to_chunk)
			var to_zone := _load_zone(to_stem)
			assert_true(to_zone.is_valid(), "zone '%s' errors: %s" % [to_stem, str(to_zone.errors)])
			assert_true(to_zone.is_walkable(to_tile), "to tile %s of '%s' must be walkable in '%s'" % [str(to_tile), transition_id, to_stem])
		else:
			var zone_stem := str(transition["to_zone"])
			assert_false(zone_stem.is_empty(), "transition '%s' must have a destination" % transition_id)
			assert_true(FileAccess.file_exists(ZONES_DIR.path_join(zone_stem + ".json")), "zone '%s' json must exist" % zone_stem)
			assert_true(FileAccess.file_exists(ZONES_DIR.path_join(zone_stem + ".map")), "zone '%s' map must exist" % zone_stem)
			var door_zone := _load_zone(zone_stem)
			assert_true(door_zone.is_valid(), "zone '%s' errors: %s" % [zone_stem, str(door_zone.errors)])
			assert_true(door_zone.is_walkable(to_tile), "to tile %s of '%s' must be walkable in '%s'" % [str(to_tile), transition_id, zone_stem])

	assert_eq(gate_count + door_count, transitions.size(), "every transition is a gate or a door")
