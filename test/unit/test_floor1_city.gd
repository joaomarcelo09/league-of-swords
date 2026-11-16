extends GutTest

## JGT-112: the floor 1 city chunk (city.json + city.map) and its world wiring.

const ZONES_DIR := "res://data/zones/floor1"
const WORLD_PATH := ZONES_DIR + "/world.json"
const CITY_MAP_PATH := ZONES_DIR + "/city.map"
const CITY_JSON_PATH := ZONES_DIR + "/city.json"
const CITY_CHUNK := "floor1_town"
const CITY_ZONE_STEM := "city"
const MERCHANT_ID := "floor1_city_merchant"
const GATE_TRANSITION_ID := "town_to_plains_gate"

var world: WorldMap = null
var zone: Zone = null


func before_each() -> void:
	world = WorldMap.load_file(WORLD_PATH)
	zone = Zone.load_files(CITY_MAP_PATH, CITY_JSON_PATH)


func _tile(value: Variant) -> Vector2i:
	var arr: Array = value
	return Vector2i(int(arr[0]), int(arr[1]))


func _load_zone(stem: String) -> Zone:
	return Zone.load_files(ZONES_DIR.path_join(stem + ".map"), ZONES_DIR.path_join(stem + ".json"))


func _transition(transition_id: String) -> Dictionary:
	for chunk_id: String in world.chunk_ids():
		for transition: Dictionary in world.transitions_of(chunk_id):
			if str(transition["id"]) == transition_id:
				return transition
	return {}


func test_city_zone_loads_without_errors() -> void:
	assert_not_null(zone)
	assert_eq(zone.errors.size(), 0, "city errors: %s" % str(zone.errors))
	assert_true(zone.is_valid(), "city must load with no errors")


func test_city_chunk_points_at_city_zone() -> void:
	assert_true(world.is_valid(), "world.json errors: %s" % str(world.errors))
	assert_eq(world.zone_stem(CITY_CHUNK), CITY_ZONE_STEM, "the town chunk must load the city zone")


func test_city_dimensions_match_chunk_size() -> void:
	assert_true(world.is_valid(), "world.json errors: %s" % str(world.errors))
	assert_eq(Vector2i(zone.width, zone.height), world.chunk_size, "the city must fill exactly one world chunk")


func test_entry_is_walkable_and_safe() -> void:
	assert_true(zone.is_walkable(zone.entry), "entry %s must be walkable" % str(zone.entry))
	assert_true(zone.is_safe(zone.entry), "entry %s must be inside the safe city" % str(zone.entry))


func test_merchant_stands_on_safe_walkable_tile_reachable_from_entry() -> void:
	assert_eq(zone.npcs.size(), 1, "the city has a single merchant NPC")
	if zone.npcs.size() != 1:
		return
	var npc: Dictionary = zone.npcs[0]
	assert_eq(str(npc.get("id", "")), MERCHANT_ID)
	assert_eq(str(npc.get("kind", "")), "merchant")
	assert_false(str(npc.get("name", "")).strip_edges().is_empty(), "the merchant needs a name")
	var npc_tile := _tile(npc.get("tile"))
	assert_true(zone.is_walkable(npc_tile), "merchant tile %s must be walkable" % str(npc_tile))
	assert_true(zone.is_safe(npc_tile), "merchant must stand inside the safe city")
	assert_gt(zone.find_path(zone.entry, npc_tile).size(), 0, "merchant must be reachable from the entry")


func test_no_enemy_spawns() -> void:
	assert_eq(zone.spawns.size(), 0, "the city is a safe zone with no enemy spawns")


func test_no_zone_exits() -> void:
	assert_eq(zone.exits.size(), 0, "travel to other chunks is handled by world.json transitions")


func test_east_gate_tile_is_walkable_and_reachable() -> void:
	var gate := _transition(GATE_TRANSITION_ID)
	assert_false(gate.is_empty(), "world.json must define '%s'" % GATE_TRANSITION_ID)
	if gate.is_empty():
		return
	assert_eq(str(gate["from_chunk"]), CITY_CHUNK)
	var gate_tile: Vector2i = gate["from_tile"]
	assert_eq(gate_tile.x, zone.width - 1, "gate must sit on the east chunk edge")
	assert_true(zone.is_walkable(gate_tile), "gate tile %s must be walkable" % str(gate_tile))
	assert_gt(zone.find_path(zone.entry, gate_tile).size(), 0, "gate must be reachable from the entry")


func test_outer_wall_has_only_the_east_gate_opening() -> void:
	var gate := _transition(GATE_TRANSITION_ID)
	assert_false(gate.is_empty(), "world.json must define '%s'" % GATE_TRANSITION_ID)
	if gate.is_empty():
		return
	var gate_tile: Vector2i = gate["from_tile"]

	var openings: Array[Vector2i] = []
	for x in range(zone.width):
		for t: Vector2i in [Vector2i(x, 0), Vector2i(x, zone.height - 1)]:
			if zone.is_walkable(t):
				openings.append(t)
	for y in range(zone.height):
		for t: Vector2i in [Vector2i(0, y), Vector2i(zone.width - 1, y)]:
			if zone.is_walkable(t):
				openings.append(t)

	assert_eq(openings.size(), 1, "the outer wall opens only at the east gate, got %s" % str(openings))
	if openings.size() == 1:
		assert_eq(openings[0], gate_tile)


func test_plaza_has_fountain_houses_and_torches() -> void:
	var safe_tiles := 0
	var houses := 0
	var fountains := 0
	var torches := 0
	for y in range(zone.height):
		for x in range(zone.width):
			var t := Vector2i(x, y)
			if zone.is_safe(t) and zone.is_walkable(t):
				safe_tiles += 1
			match zone.decor_at(t):
				"house":
					houses += 1
				"fountain":
					fountains += 1
				"torch":
					torches += 1
	assert_gt(safe_tiles, 0, "the city needs a safe plaza")
	assert_gte(houses, 4, "the city needs at least 4 houses")
	assert_gte(fountains, 1, "the plaza needs a fountain")
	assert_gte(torches, 2, "the city needs torches")


func test_all_walkable_tiles_reachable_from_entry() -> void:
	for y in range(zone.height):
		for x in range(zone.width):
			var t := Vector2i(x, y)
			if zone.is_walkable(t):
				assert_gt(zone.find_path(zone.entry, t).size(), 0, "walkable tile %s must be reachable from entry %s" % [str(t), str(zone.entry)])


func test_real_world_transition_tiles_are_walkable() -> void:
	assert_true(world.is_valid(), "world.json errors: %s" % str(world.errors))

	var transitions: Array[Dictionary] = []
	for chunk_id: String in world.chunk_ids():
		transitions.append_array(world.transitions_of(chunk_id))
	assert_gt(transitions.size(), 0, "world.json must define transitions")

	for transition: Dictionary in transitions:
		var transition_id := str(transition["id"])

		var from_stem := world.zone_stem(str(transition["from_chunk"]))
		var from_zone := _load_zone(from_stem)
		assert_true(from_zone.is_valid(), "zone '%s' errors: %s" % [from_stem, str(from_zone.errors)])
		var from_tile: Vector2i = transition["from_tile"]
		assert_true(from_zone.is_walkable(from_tile), "from tile %s of '%s' must be walkable in '%s'" % [str(from_tile), transition_id, from_stem])

		var to_tile: Vector2i = transition["to_tile"]
		var to_chunk := str(transition["to_chunk"])
		var to_stem := world.zone_stem(to_chunk) if not to_chunk.is_empty() else str(transition["to_zone"])
		var to_zone := _load_zone(to_stem)
		assert_true(to_zone.is_valid(), "zone '%s' errors: %s" % [to_stem, str(to_zone.errors)])
		assert_true(to_zone.is_walkable(to_tile), "to tile %s of '%s' must be walkable in '%s'" % [str(to_tile), transition_id, to_stem])
