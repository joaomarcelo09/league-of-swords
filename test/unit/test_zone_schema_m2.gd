extends GutTest

const MAP := "#####\n#...#\n#.S.#\n#####\n"

const LEGEND := {
	"#": {"type": "wall", "walkable": false},
	".": {"type": "floor", "walkable": true},
	"S": {"type": "plaza", "walkable": true, "safe": true}
}


func _make(extra: Dictionary, legend: Dictionary = LEGEND) -> Zone:
	var data := {"legend": legend, "entry": [1, 1]}
	data.merge(extra, true)
	return Zone.load_from_strings(MAP, data)


func _has_error(zone: Zone, fragment: String) -> bool:
	for e in zone.errors:
		if e.contains(fragment):
			return true
	return false


# --- safe tiles ---

func test_is_safe_true_false_out_of_bounds() -> void:
	var zone := _make({})
	assert_true(zone.is_valid(), str(zone.errors))
	assert_true(zone.is_safe(Vector2i(2, 2)))
	assert_false(zone.is_safe(Vector2i(1, 1)))
	assert_false(zone.is_safe(Vector2i(0, 0)))
	assert_false(zone.is_safe(Vector2i(-1, 0)))
	assert_false(zone.is_safe(Vector2i(5, 1)))


func test_safe_false_is_not_safe() -> void:
	var legend := LEGEND.duplicate(true)
	legend["S"]["safe"] = false
	var zone := _make({}, legend)
	assert_true(zone.is_valid(), str(zone.errors))
	assert_false(zone.is_safe(Vector2i(2, 2)))


func test_safe_non_bool_is_error() -> void:
	var legend := LEGEND.duplicate(true)
	legend["S"]["safe"] = "yes"
	var zone := _make({}, legend)
	assert_false(zone.is_valid())
	assert_true(_has_error(zone, "legend entry 'S' safe must be a boolean"), str(zone.errors))


# --- npcs ---

func test_npcs_happy_path() -> void:
	var zone := _make({"npcs": [
		{"id": "smith", "kind": "merchant", "tile": [2.0, 1.0]},
		{"id": "guide", "kind": "any_kind", "tile": [3, 2]}
	]})
	assert_true(zone.is_valid(), str(zone.errors))
	assert_eq(zone.npcs.size(), 2)
	assert_eq(zone.npcs[0].get("id"), "smith")
	assert_eq(zone.npcs[0].get("kind"), "merchant")
	assert_eq(zone.npcs[0].get("tile"), [2, 1])
	assert_eq(zone.npcs[1].get("tile"), [3, 2])


func test_npcs_not_array_is_error() -> void:
	var zone := _make({"npcs": {"id": "x"}})
	assert_false(zone.is_valid())
	assert_true(_has_error(zone, "'npcs' must be an array"), str(zone.errors))


func test_npc_not_object_is_error() -> void:
	var zone := _make({"npcs": ["smith"]})
	assert_false(zone.is_valid())
	assert_true(_has_error(zone, "NPC entry must be an object"), str(zone.errors))


func test_npc_bad_id_and_kind() -> void:
	var zone := _make({"npcs": [
		{"id": "", "kind": "merchant", "tile": [1, 1]},
		{"id": 5, "kind": "merchant", "tile": [1, 1]},
		{"id": "a", "kind": "", "tile": [1, 1]},
		{"id": "b", "tile": [1, 1]}
	]})
	assert_false(zone.is_valid())
	assert_true(_has_error(zone, "npc[0] id must be a non-empty string"), str(zone.errors))
	assert_true(_has_error(zone, "npc[1] id must be a non-empty string"), str(zone.errors))
	assert_true(_has_error(zone, "npc[2] kind must be a non-empty string"), str(zone.errors))
	assert_true(_has_error(zone, "npc[3] kind must be a non-empty string"), str(zone.errors))


func test_npc_duplicate_id() -> void:
	var zone := _make({"npcs": [
		{"id": "smith", "kind": "merchant", "tile": [1, 1]},
		{"id": "smith", "kind": "merchant", "tile": [2, 1]}
	]})
	assert_false(zone.is_valid())
	assert_true(_has_error(zone, "npc[1] id 'smith' is duplicated"), str(zone.errors))


func test_npc_bad_tile_out_of_bounds_unwalkable() -> void:
	var bad := _make({"npcs": [{"id": "a", "kind": "k", "tile": [1.5, 1]}]})
	assert_false(bad.is_valid())
	assert_true(_has_error(bad, "npc[0] tile coordinates must be integers"), str(bad.errors))

	var oob := _make({"npcs": [{"id": "a", "kind": "k", "tile": [9, 9]}]})
	assert_false(oob.is_valid())
	assert_true(_has_error(oob, "NPC tile (9, 9) is out of bounds"), str(oob.errors))

	var wall := _make({"npcs": [{"id": "a", "kind": "k", "tile": [0, 0]}]})
	assert_false(wall.is_valid())
	assert_true(_has_error(wall, "NPC tile (0, 0) is not walkable"), str(wall.errors))


# --- spawns id / boss ---

func test_spawn_id_and_boss_happy_path() -> void:
	var zone := _make({"spawns": [
		{"id": "boss1", "enemy": "big", "tile": [3, 1], "boss": true},
		{"id": "mob1", "enemy": "small", "tile": [1, 2], "boss": false},
		{"enemy": "small", "tile": [2, 1]}
	]})
	assert_true(zone.is_valid(), str(zone.errors))
	assert_eq(zone.spawns.size(), 3)
	var bosses := zone.boss_spawns()
	assert_eq(bosses.size(), 1)
	assert_eq(bosses[0].get("id"), "boss1")


func test_spawn_bad_id_duplicate_and_boss_type() -> void:
	var zone := _make({"spawns": [
		{"id": "", "enemy": "e", "tile": [1, 1]},
		{"id": "a", "enemy": "e", "tile": [1, 1]},
		{"id": "a", "enemy": "e", "tile": [2, 1]},
		{"id": "b", "enemy": "e", "tile": [3, 1], "boss": "true"}
	]})
	assert_false(zone.is_valid())
	assert_true(_has_error(zone, "spawn[0] id must be a non-empty string"), str(zone.errors))
	assert_true(_has_error(zone, "spawn[2] id 'a' is duplicated"), str(zone.errors))
	assert_true(_has_error(zone, "spawn[3] boss must be a boolean"), str(zone.errors))


# --- exits requires_boss / label ---

func test_exit_requires_boss_and_label_happy_path() -> void:
	var zone := _make({
		"spawns": [{"id": "gate_boss", "enemy": "big", "tile": [3, 1], "boss": true}],
		"exits": [{"tile": [3, 2], "to_zone": "floor2", "requires_boss": "gate_boss", "label": "Stairs"}]
	})
	assert_true(zone.is_valid(), str(zone.errors))
	assert_eq(zone.exits[0].get("requires_boss"), "gate_boss")
	assert_eq(zone.exits[0].get("label"), "Stairs")
	assert_eq(zone.exits[0].get("tile"), [3, 2])


func test_exit_requires_boss_unknown_id() -> void:
	var zone := _make({
		"spawns": [{"id": "gate_boss", "enemy": "big", "tile": [3, 1], "boss": true}],
		"exits": [{"tile": [3, 2], "to_zone": "x", "requires_boss": "nobody"}]
	})
	assert_false(zone.is_valid())
	assert_true(_has_error(zone, "exit[0] requires_boss 'nobody' does not match a boss spawn id"), str(zone.errors))


func test_exit_requires_boss_non_boss_spawn() -> void:
	var zone := _make({
		"spawns": [
			{"id": "mob", "enemy": "small", "tile": [3, 1]},
			{"id": "mob2", "enemy": "small", "tile": [1, 2], "boss": false}
		],
		"exits": [
			{"tile": [3, 2], "to_zone": "x", "requires_boss": "mob"},
			{"tile": [3, 2], "to_zone": "x", "requires_boss": "mob2"}
		]
	})
	assert_false(zone.is_valid())
	assert_true(_has_error(zone, "exit[0] requires_boss 'mob'"), str(zone.errors))
	assert_true(_has_error(zone, "exit[1] requires_boss 'mob2'"), str(zone.errors))


func test_exit_bad_types() -> void:
	var zone := _make({
		"spawns": [{"id": "b", "enemy": "big", "tile": [3, 1], "boss": true}],
		"exits": [{"tile": [3, 2], "to_zone": "x", "requires_boss": 7, "label": 3}]
	})
	assert_false(zone.is_valid())
	assert_true(_has_error(zone, "exit[0] requires_boss must be a string"), str(zone.errors))
	assert_true(_has_error(zone, "exit[0] label must be a string"), str(zone.errors))


# --- backwards compatibility ---

func test_old_zone_files_still_valid() -> void:
	for zname in ["test_arena", "test_small"]:
		var zone := Zone.load_files("res://data/zones/floor1/%s.map" % zname, "res://data/zones/floor1/%s.json" % zname)
		assert_true(zone.is_valid(), "%s: %s" % [zname, str(zone.errors)])
		assert_eq(zone.npcs.size(), 0, "%s has no npcs" % zname)
		assert_false(zone.is_safe(zone.entry), "%s entry is not safe" % zname)
