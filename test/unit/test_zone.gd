extends GutTest

const MAP_PATH := "res://data/zones/floor1/test_small.map"
const JSON_PATH := "res://data/zones/floor1/test_small.json"

const BASIC_LEGEND := {
	"#": {"type": "wall", "walkable": false},
	".": {"type": "floor", "walkable": true},
	",": {"type": "grass", "walkable": true, "decor": "grass_tuft"}
}


func test_loads_fixture_properties() -> void:
	var zone := Zone.load_files(MAP_PATH, JSON_PATH)
	assert_not_null(zone, "Zone should not be null")
	assert_true(zone.is_valid(), "Fixture zone should be valid: %s" % str(zone.errors))
	assert_eq(zone.errors.size(), 0)
	assert_eq(zone.width, 12, "Width should be 12")
	assert_eq(zone.height, 8, "Height should be 8")
	assert_eq(zone.entry, Vector2i(1, 1), "Entry should be (1, 1)")

	assert_eq(zone.spawns.size(), 1, "Should have 1 spawn")
	var spawn: Dictionary = zone.spawns[0]
	assert_eq(spawn.get("enemy"), "boar_small")
	assert_eq(spawn.get("tile"), [2, 2])
	assert_eq(spawn.get("respawn_s"), 30.0)

	assert_eq(zone.exits.size(), 1, "Should have 1 exit")
	var exit_entry: Dictionary = zone.exits[0]
	assert_eq(exit_entry.get("tile"), [10, 6])
	assert_eq(exit_entry.get("to_zone"), "town")


func test_walkability_and_types() -> void:
	var zone := Zone.load_files(MAP_PATH, JSON_PATH)
	assert_true(zone.is_valid())

	# Floor tile
	assert_true(zone.is_walkable(Vector2i(1, 1)))
	assert_eq(zone.tile_type(Vector2i(1, 1)), "floor")
	assert_eq(zone.decor_at(Vector2i(1, 1)), "")

	# Grass tile with decor
	assert_true(zone.is_walkable(Vector2i(5, 6)))
	assert_eq(zone.tile_type(Vector2i(5, 6)), "grass")
	assert_eq(zone.decor_at(Vector2i(5, 6)), "grass_tuft")

	# Wall tiles
	assert_false(zone.is_walkable(Vector2i(0, 0)))
	assert_eq(zone.tile_type(Vector2i(0, 0)), "wall")
	assert_false(zone.is_walkable(Vector2i(5, 2)))
	assert_eq(zone.tile_type(Vector2i(5, 2)), "wall")

	# Out of bounds
	assert_false(zone.is_in_bounds(Vector2i(-1, 0)))
	assert_false(zone.is_walkable(Vector2i(-1, 0)))
	assert_eq(zone.tile_type(Vector2i(-1, 0)), "")
	assert_eq(zone.decor_at(Vector2i(-1, 0)), "")

	assert_false(zone.is_in_bounds(Vector2i(12, 0)))
	assert_false(zone.is_walkable(Vector2i(12, 0)))

	assert_false(zone.is_in_bounds(Vector2i(0, 8)))
	assert_false(zone.is_walkable(Vector2i(0, 8)))

	assert_false(zone.is_in_bounds(Vector2i(0, -1)))
	assert_false(zone.is_walkable(Vector2i(0, -1)))


func test_find_path_around_wall() -> void:
	var zone := Zone.load_files(MAP_PATH, JSON_PATH)
	assert_true(zone.is_valid())

	var a := Vector2i(2, 2)
	var b := Vector2i(8, 2)
	var path := zone.find_path(a, b)

	assert_gt(path.size(), 0, "Path should not be empty")
	assert_eq(path[0], a, "Path start should be a")
	assert_eq(path[path.size() - 1], b, "Path end should be b")

	var manhattan_dist: int = abs(b.x - a.x) + abs(b.y - a.y)
	# Path length in number of steps = path.size() - 1
	var path_steps: int = path.size() - 1
	assert_gt(path_steps, manhattan_dist, "Path steps (%d) should be > Manhattan dist (%d)" % [path_steps, manhattan_dist])

	# No tile in path is a wall
	for t in path:
		assert_true(zone.is_walkable(t), "Tile %s in path must be walkable" % str(t))

	# Consecutive tiles are adjacent (8-directional, Chebyshev distance == 1);
	# a diagonal step never cuts a wall corner (both side tiles are walkable).
	for i in range(path.size() - 1):
		var d: Vector2i = path[i + 1] - path[i]
		var step_dist: int = maxi(absi(d.x), absi(d.y))
		assert_eq(step_dist, 1, "Consecutive tiles %s and %s must be adjacent" % [str(path[i]), str(path[i + 1])])
		if d.x != 0 and d.y != 0:
			assert_true(
				zone.is_walkable(path[i] + Vector2i(d.x, 0)) and zone.is_walkable(path[i] + Vector2i(0, d.y)),
				"Diagonal step %s -> %s must not cut a corner" % [str(path[i]), str(path[i + 1])]
			)


func test_find_path_same_tile_and_unwalkable() -> void:
	var zone := Zone.load_files(MAP_PATH, JSON_PATH)
	assert_true(zone.is_valid())

	# Same tile
	var same_path := zone.find_path(Vector2i(2, 2), Vector2i(2, 2))
	assert_eq(same_path.size(), 1)
	assert_eq(same_path[0], Vector2i(2, 2))

	# Start on wall
	var wall_start := zone.find_path(Vector2i(0, 0), Vector2i(2, 2))
	assert_eq(wall_start.size(), 0)

	# End on wall
	var wall_end := zone.find_path(Vector2i(2, 2), Vector2i(0, 0))
	assert_eq(wall_end.size(), 0)

	# Out of bounds
	var oob_path := zone.find_path(Vector2i(-1, 0), Vector2i(2, 2))
	assert_eq(oob_path.size(), 0)


func test_unreachable_target_and_nearest_reachable() -> void:
	var zone := Zone.load_files(MAP_PATH, JSON_PATH)
	assert_true(zone.is_valid())

	# Target is a wall tile (unreachable)
	var wall_target := Vector2i(5, 2)
	var path_to_wall := zone.find_path(Vector2i(2, 2), wall_target)
	assert_eq(path_to_wall.size(), 0, "Path to wall should be empty")

	var nearest := zone.nearest_reachable(Vector2i(2, 2), wall_target)
	assert_ne(nearest, Vector2i(-1, -1))
	assert_true(zone.is_walkable(nearest), "Nearest reachable tile must be walkable")
	var path_to_nearest := zone.find_path(Vector2i(2, 2), nearest)
	assert_gt(path_to_nearest.size(), 0, "Nearest tile must be reachable from start")

	# Target in an enclosed unreachable room
	var enclosed_map := """
#######
#...#.#
#...###
#######
""".strip_edges()
	var enclosed_json := {
		"legend": BASIC_LEGEND,
		"entry": [1, 1]
	}
	var enclosed_zone := Zone.load_from_strings(enclosed_map, enclosed_json)
	assert_true(enclosed_zone.is_valid())

	var unreachable_floor := Vector2i(5, 1)
	var enclosed_path := enclosed_zone.find_path(Vector2i(1, 1), unreachable_floor)
	assert_eq(enclosed_path.size(), 0, "Path into walled-off room must be empty")

	var enclosed_nearest := enclosed_zone.nearest_reachable(Vector2i(1, 1), unreachable_floor)
	assert_ne(enclosed_nearest, Vector2i(-1, -1))
	assert_true(enclosed_zone.is_walkable(enclosed_nearest))
	var path_to_enclosed_nearest := enclosed_zone.find_path(Vector2i(1, 1), enclosed_nearest)
	assert_gt(path_to_enclosed_nearest.size(), 0, "Must be reachable")

	# Target reachable directly returns target
	var direct_target := Vector2i(3, 1)
	var direct_nearest := enclosed_zone.nearest_reachable(Vector2i(1, 1), direct_target)
	assert_eq(direct_nearest, direct_target, "Reachable target should return itself")

	# Start on wall returns (-1, -1)
	var invalid_nearest := enclosed_zone.nearest_reachable(Vector2i(0, 0), direct_target)
	assert_eq(invalid_nearest, Vector2i(-1, -1))


func test_malformed_ragged_rows() -> void:
	var ragged_map := """
#####
####
#####
""".strip_edges()
	var json_data := {
		"legend": BASIC_LEGEND,
		"entry": [1, 1]
	}
	var zone := Zone.load_from_strings(ragged_map, json_data, "ragged.map", "ragged.json")
	assert_false(zone.is_valid(), "Ragged map must not be valid")
	assert_gt(zone.errors.size(), 0)

	var found_ragged := false
	for err in zone.errors:
		if "row 1 has width 4, expected 5" in err or ("width" in err and "expected" in err):
			found_ragged = true
			break
	assert_true(found_ragged, "Should report ragged row error: %s" % str(zone.errors))


func test_malformed_unknown_character() -> void:
	var unknown_map := """
#####
#.?X#
#####
""".strip_edges()
	var json_data := {
		"legend": BASIC_LEGEND,
		"entry": [1, 1]
	}
	var zone := Zone.load_from_strings(unknown_map, json_data, "bad_char.map", "bad_char.json")
	assert_false(zone.is_valid(), "Map with unknown chars must not be valid")
	assert_gt(zone.errors.size(), 0)

	var found_char_err := false
	for err in zone.errors:
		if "Unknown character" in err:
			found_char_err = true
			break
	assert_true(found_char_err, "Should report unknown character error: %s" % str(zone.errors))


func test_malformed_out_of_bounds_and_non_walkable_entry() -> void:
	var map_text := """
###
#.#
###
""".strip_edges()

	# Out of bounds entry
	var oob_entry_json := {
		"legend": BASIC_LEGEND,
		"entry": [10, 10]
	}
	var zone_oob := Zone.load_from_strings(map_text, oob_entry_json, "test.map", "oob.json")
	assert_false(zone_oob.is_valid())
	var found_oob := false
	for err in zone_oob.errors:
		if "out of bounds" in err:
			found_oob = true
			break
	assert_true(found_oob, "Should report out of bounds entry: %s" % str(zone_oob.errors))

	# Non-walkable wall entry
	var wall_entry_json := {
		"legend": BASIC_LEGEND,
		"entry": [0, 0]
	}
	var zone_wall := Zone.load_from_strings(map_text, wall_entry_json, "test.map", "wall.json")
	assert_false(zone_wall.is_valid())
	var found_non_walkable := false
	for err in zone_wall.errors:
		if "not walkable" in err:
			found_non_walkable = true
			break
	assert_true(found_non_walkable, "Should report non-walkable entry: %s" % str(zone_wall.errors))


func test_malformed_spawns_and_exits() -> void:
	var map_text := """
###
#.#
###
""".strip_edges()

	# Spawn out of bounds
	var bad_spawn_json := {
		"legend": BASIC_LEGEND,
		"entry": [1, 1],
		"spawns": [{"enemy": "boar", "tile": [5, 5]}]
	}
	var zone_bad_spawn := Zone.load_from_strings(map_text, bad_spawn_json)
	assert_false(zone_bad_spawn.is_valid())
	var found_spawn_err := false
	for err in zone_bad_spawn.errors:
		if "Spawn tile" in err and "out of bounds" in err:
			found_spawn_err = true
			break
	assert_true(found_spawn_err, "Should report spawn out of bounds error: %s" % str(zone_bad_spawn.errors))

	# Exit on wall
	var bad_exit_json := {
		"legend": BASIC_LEGEND,
		"entry": [1, 1],
		"exits": [{"to_zone": "next", "tile": [0, 0]}]
	}
	var zone_bad_exit := Zone.load_from_strings(map_text, bad_exit_json)
	assert_false(zone_bad_exit.is_valid())
	var found_exit_err := false
	for err in zone_bad_exit.errors:
		if "Exit tile" in err and "not walkable" in err:
			found_exit_err = true
			break
	assert_true(found_exit_err, "Should report exit non-walkable error: %s" % str(zone_bad_exit.errors))


func test_malformed_files_and_json() -> void:
	# Missing files
	var zone_missing := Zone.load_files("res://nonexistent.map", "res://nonexistent.json")
	assert_false(zone_missing.is_valid())
	assert_gt(zone_missing.errors.size(), 0)

	# Bad JSON syntax
	var zone_bad_json := Zone.load_from_strings("###\n#.#\n###", "{ invalid json")
	assert_false(zone_bad_json.is_valid())
	assert_gt(zone_bad_json.errors.size(), 0)

	# Empty map
	var zone_empty := Zone.load_from_strings("", {"legend": BASIC_LEGEND, "entry": [0, 0]})
	assert_false(zone_empty.is_valid())
	assert_gt(zone_empty.errors.size(), 0)


func test_malformed_spawn_tile_coordinates() -> void:
	var map_text := """
###
#.#
###
""".strip_edges()

	var bad_cases: Array = [
		[null, 1],
		["a", 1],
		[1.5, 1],
		"non_array_string",
		[null, {}],
	]

	for bad_tile in bad_cases:
		var json_data := {
			"legend": BASIC_LEGEND,
			"entry": [1, 1],
			"spawns": [{"enemy": "boar", "tile": bad_tile}]
		}
		var zone := Zone.load_from_strings(map_text, json_data)
		assert_not_null(zone, "Zone must not be null for spawn tile %s" % str(bad_tile))
		assert_false(zone.is_valid(), "Zone must be invalid for spawn tile %s" % str(bad_tile))
		var expected_err := "inline.json: spawn[0] tile coordinates must be integers"
		assert_has(zone.errors, expected_err, "Expected error for spawn tile %s in %s" % [str(bad_tile), str(zone.errors)])

	# Also verify indexed label for spawn at index 1
	var multi_spawn_json := {
		"legend": BASIC_LEGEND,
		"entry": [1, 1],
		"spawns": [
			{"enemy": "boar", "tile": [1, 1]},
			{"enemy": "wolf", "tile": [null, 1]}
		]
	}
	var multi_zone := Zone.load_from_strings(map_text, multi_spawn_json)
	assert_not_null(multi_zone, "Zone must not be null")
	assert_false(multi_zone.is_valid(), "Zone must be invalid")
	assert_has(multi_zone.errors, "inline.json: spawn[1] tile coordinates must be integers")


func test_malformed_exit_tile_coordinates() -> void:
	var map_text := """
###
#.#
###
""".strip_edges()

	var bad_cases: Array = [
		[null, 1],
		["a", 1],
		[1.5, 1],
		"non_array_string",
		[null, {}],
	]

	for bad_tile in bad_cases:
		var json_data := {
			"legend": BASIC_LEGEND,
			"entry": [1, 1],
			"exits": [{"to_zone": "town", "tile": bad_tile}]
		}
		var zone := Zone.load_from_strings(map_text, json_data)
		assert_not_null(zone, "Zone must not be null for exit tile %s" % str(bad_tile))
		assert_false(zone.is_valid(), "Zone must be invalid for exit tile %s" % str(bad_tile))
		var expected_err := "inline.json: exit[0] tile coordinates must be integers"
		assert_has(zone.errors, expected_err, "Expected error for exit tile %s in %s" % [str(bad_tile), str(zone.errors)])

	# Also verify indexed label for exit at index 1
	var multi_exit_json := {
		"legend": BASIC_LEGEND,
		"entry": [1, 1],
		"exits": [
			{"to_zone": "town", "tile": [1, 1]},
			{"to_zone": "dungeon", "tile": ["a", 1]}
		]
	}
	var multi_zone := Zone.load_from_strings(map_text, multi_exit_json)
	assert_not_null(multi_zone, "Zone must not be null")
	assert_false(multi_zone.is_valid(), "Zone must be invalid")
	assert_has(multi_zone.errors, "inline.json: exit[1] tile coordinates must be integers")


func test_malformed_entry_tile_coordinates() -> void:
	var map_text := """
###
#.#
###
""".strip_edges()

	var bad_cases: Array = [
		[null, 1],
		["a", 1],
		[1.5, 1],
		"non_array_string",
		[null, {}],
	]

	for bad_tile in bad_cases:
		var json_data := {
			"legend": BASIC_LEGEND,
			"entry": bad_tile
		}
		var zone := Zone.load_from_strings(map_text, json_data)
		assert_not_null(zone, "Zone must not be null for entry %s" % str(bad_tile))
		assert_false(zone.is_valid(), "Zone must be invalid for entry %s" % str(bad_tile))
		var expected_err := "inline.json: entry coordinates must be integers"
		assert_has(zone.errors, expected_err, "Expected error for entry %s in %s" % [str(bad_tile), str(zone.errors)])


func test_valid_whole_float_coordinates() -> void:
	var map_text := """
###
#.#
###
""".strip_edges()

	var json_data := {
		"legend": BASIC_LEGEND,
		"entry": [1.0, 1.0],
		"spawns": [{"enemy": "boar", "tile": [1.0, 1.0]}],
		"exits": [{"to_zone": "next", "tile": [1.0, 1.0]}]
	}
	var zone := Zone.load_from_strings(map_text, json_data)
	assert_not_null(zone, "Zone must not be null")
	assert_true(zone.is_valid(), "Zone with whole-value floats should be valid: %s" % str(zone.errors))
	assert_eq(zone.entry, Vector2i(1, 1))
	assert_eq(zone.spawns[0]["tile"], [1, 1])
	assert_eq(zone.exits[0]["tile"], [1, 1])

