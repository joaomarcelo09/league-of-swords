extends GutTest

## JGT-113: the two floor 1 plains chunks (plains_west + plains_east) east of the
## city, their enemy spawns and their world.json wiring.

const ZONES_DIR := "res://data/zones/floor1"
const WORLD_PATH := ZONES_DIR + "/world.json"
const ENEMIES_PATH := "res://data/enemies.json"

const TOWN_CHUNK := "floor1_town"
const WEST_CHUNK := "floor1_plains"
const WEST_ZONE_STEM := "plains_west"
const EAST_CHUNK := "floor1_plains_east"
const EAST_ZONE_STEM := "plains_east"
const ARENA_CHUNK := "floor1_arena"

const TOWN_TO_PLAINS_GATE := "town_to_plains_gate"
const PLAINS_TO_TOWN_GATE := "plains_to_town_gate"
const PLAINS_TO_EAST_GATE := "plains_to_plains_east_gate"
const EAST_TO_PLAINS_GATE := "plains_east_to_plains_gate"
const DUNGEON_DOOR := "plains_to_dungeon_door"

## Spawns must stay more than this many tiles (Chebyshev) from any gate or entry.
const MIN_GATE_DISTANCE := 5

const PLAINS_TILE_TYPES := ["wall", "floor", "grass"]

var world: WorldMap = null
var west: Zone = null
var east: Zone = null
var enemies: Dictionary = {}


func before_each() -> void:
	world = WorldMap.load_file(WORLD_PATH)
	west = _load_zone(WEST_ZONE_STEM)
	east = _load_zone(EAST_ZONE_STEM)
	enemies = _load_json(ENEMIES_PATH)


func _load_zone(stem: String) -> Zone:
	return Zone.load_files(ZONES_DIR.path_join(stem + ".map"), ZONES_DIR.path_join(stem + ".json"))


func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "%s must open" % path)
	if file == null:
		return {}
	var data: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if data is Dictionary:
		return data
	return {}


func _tile(value: Variant) -> Vector2i:
	var arr: Array = value
	return Vector2i(int(arr[0]), int(arr[1]))


func _zone_cases() -> Array[Dictionary]:
	return [
		{"name": WEST_ZONE_STEM, "chunk": WEST_CHUNK, "zone": west},
		{"name": EAST_ZONE_STEM, "chunk": EAST_CHUNK, "zone": east},
	]


func _transition(transition_id: String) -> Dictionary:
	for chunk_id: String in world.chunk_ids():
		for transition: Dictionary in world.transitions_of(chunk_id):
			if str(transition["id"]) == transition_id:
				return transition
	return {}


## Every transition that starts in or leads into chunk_id.
func _transitions_touching(chunk_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for other_id: String in world.chunk_ids():
		for transition: Dictionary in world.transitions_of(other_id):
			if str(transition["from_chunk"]) == chunk_id:
				result.append(transition)
			elif str(transition["to_chunk"]) == chunk_id:
				result.append(transition)
	return result


## Local tiles of chunk_id used as transition endpoints (gates and doors alike).
func _edge_tiles_of(chunk_id: String) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for transition: Dictionary in _transitions_touching(chunk_id):
		if str(transition["from_chunk"]) == chunk_id:
			tiles.append(transition["from_tile"])
		if str(transition["to_chunk"]) == chunk_id:
			tiles.append(transition["to_tile"])
	return tiles


func _chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func test_plains_zones_load_without_errors() -> void:
	assert_not_null(west)
	assert_not_null(east)
	assert_eq(west.errors.size(), 0, "plains_west errors: %s" % str(west.errors))
	assert_eq(east.errors.size(), 0, "plains_east errors: %s" % str(east.errors))
	assert_true(west.is_valid(), "plains_west must load with no errors")
	assert_true(east.is_valid(), "plains_east must load with no errors")


func test_plains_dimensions_match_chunk_size() -> void:
	assert_true(world.is_valid(), "world.json errors: %s" % str(world.errors))
	assert_eq(Vector2i(west.width, west.height), world.chunk_size, "plains_west must fill exactly one world chunk")
	assert_eq(Vector2i(east.width, east.height), world.chunk_size, "plains_east must fill exactly one world chunk")


func test_world_places_the_plains_east_of_the_city() -> void:
	assert_true(world.is_valid(), "world.json errors: %s" % str(world.errors))
	assert_eq(world.zone_stem(TOWN_CHUNK), "city")
	assert_eq(world.zone_stem(WEST_CHUNK), WEST_ZONE_STEM, "floor1_plains must load plains_west")
	assert_eq(world.zone_stem(EAST_CHUNK), EAST_ZONE_STEM, "floor1_plains_east must load plains_east")
	assert_eq(world.grid_cell(WEST_CHUNK), Vector2i(1, 0), "the western plains sit right after the city")
	assert_eq(world.grid_cell(EAST_CHUNK), Vector2i(2, 0), "the eastern plains sit between the west plains and the arena")
	assert_eq(world.grid_cell(ARENA_CHUNK), Vector2i(3, 0), "the arena moved one cell east")
	assert_eq(world.chunk_kind(WEST_CHUNK), "plains")
	assert_eq(world.chunk_kind(EAST_CHUNK), "plains")
	assert_eq(world.chunk_at_cell(Vector2i(1, 0)), WEST_CHUNK)
	assert_eq(world.chunk_at_cell(Vector2i(2, 0)), EAST_CHUNK)
	assert_eq(world.chunk_at_cell(Vector2i(3, 0)), ARENA_CHUNK)


func test_entries_are_walkable() -> void:
	assert_true(west.is_walkable(west.entry), "plains_west entry %s must be walkable" % str(west.entry))
	assert_true(east.is_walkable(east.entry), "plains_east entry %s must be walkable" % str(east.entry))


func test_plains_use_the_existing_plains_legend() -> void:
	for zone_case: Dictionary in _zone_cases():
		var zone: Zone = zone_case["zone"]
		var zone_name := str(zone_case["name"])
		for y in range(zone.height):
			for x in range(zone.width):
				var t := Vector2i(x, y)
				assert_true(zone.tile_type(t) in PLAINS_TILE_TYPES, "%s tile %s uses unexpected type '%s'" % [zone_name, str(t), zone.tile_type(t)])
				var decor := zone.decor_at(t)
				assert_true(decor.is_empty() or decor == "grass_tuft", "%s tile %s uses unexpected decor '%s'" % [zone_name, str(t), decor])


func test_plains_have_no_zone_exits() -> void:
	assert_eq(west.exits.size(), 0, "travel out of the chunk is handled by world.json transitions")
	assert_eq(east.exits.size(), 0, "travel out of the chunk is handled by world.json transitions")


func test_spawn_counts_and_enemy_ids() -> void:
	assert_gte(west.spawns.size(), 4, "the western plains need at least 4 spawns")
	assert_gte(east.spawns.size(), 5, "the eastern plains need at least 5 spawns")
	for zone_case: Dictionary in _zone_cases():
		var zone: Zone = zone_case["zone"]
		var zone_name := str(zone_case["name"])
		for spawn: Dictionary in zone.spawns:
			var enemy_id := str(spawn.get("enemy", ""))
			assert_false(enemy_id.is_empty(), "%s spawns need an enemy id" % zone_name)
			assert_true(enemies.has(enemy_id), "%s spawn enemy '%s' must exist in enemies.json" % [zone_name, enemy_id])
			assert_eq(int(spawn.get("respawn_s", 0)), 30, "%s spawn '%s' must respawn like the other plains data" % [zone_name, enemy_id])


func test_west_is_weak_and_east_is_tougher() -> void:
	var west_types: Dictionary = {}
	for spawn: Dictionary in west.spawns:
		west_types[str(spawn["enemy"])] = true
	var east_types: Dictionary = {}
	for spawn: Dictionary in east.spawns:
		east_types[str(spawn["enemy"])] = true
	assert_true(west_types.has("cinder_bat"), "the western plains should field the weak cinder bats")
	assert_true(east_types.has("bog_slime"), "the eastern plains should field the tougher bog slimes")


func test_spawn_tiles_are_walkable() -> void:
	for zone_case: Dictionary in _zone_cases():
		var zone: Zone = zone_case["zone"]
		var zone_name := str(zone_case["name"])
		for spawn: Dictionary in zone.spawns:
			var spawn_tile := _tile(spawn.get("tile"))
			assert_true(zone.is_in_bounds(spawn_tile), "%s spawn tile %s must be in bounds" % [zone_name, str(spawn_tile)])
			assert_true(zone.is_walkable(spawn_tile), "%s spawn tile %s must be walkable" % [zone_name, str(spawn_tile)])
			assert_gt(zone.find_path(zone.entry, spawn_tile).size(), 0, "%s spawn tile %s must be reachable from the entry" % [zone_name, str(spawn_tile)])


func test_spawn_tiles_stay_clear_of_gates_and_entry() -> void:
	for zone_case: Dictionary in _zone_cases():
		var zone: Zone = zone_case["zone"]
		var zone_name := str(zone_case["name"])
		var chunk_id := str(zone_case["chunk"])
		var edge_tiles := _edge_tiles_of(chunk_id)
		assert_gt(edge_tiles.size(), 0, "%s must be wired to the world" % zone_name)
		for spawn: Dictionary in zone.spawns:
			var spawn_tile := _tile(spawn.get("tile"))
			for edge_tile: Vector2i in edge_tiles:
				assert_gt(_chebyshev(spawn_tile, edge_tile), MIN_GATE_DISTANCE, "%s spawn %s must stay clear of gate tile %s" % [zone_name, str(spawn_tile), str(edge_tile)])
			assert_gt(_chebyshev(spawn_tile, zone.entry), MIN_GATE_DISTANCE, "%s spawn %s must stay clear of the entry" % [zone_name, str(spawn_tile)])


func test_gate_tiles_are_walkable_and_reachable_from_entry() -> void:
	assert_true(world.is_valid(), "world.json errors: %s" % str(world.errors))
	for zone_case: Dictionary in _zone_cases():
		var zone: Zone = zone_case["zone"]
		var zone_name := str(zone_case["name"])
		var chunk_id := str(zone_case["chunk"])
		for edge_tile: Vector2i in _edge_tiles_of(chunk_id):
			assert_true(zone.is_walkable(edge_tile), "%s gate tile %s must be walkable" % [zone_name, str(edge_tile)])
			assert_gt(zone.find_path(zone.entry, edge_tile).size(), 0, "%s gate tile %s must be reachable from the entry" % [zone_name, str(edge_tile)])


func test_town_gate_uses_the_real_edge_tiles() -> void:
	var city := _load_zone("city")
	assert_true(city.is_valid(), "city errors: %s" % str(city.errors))

	var to_plains := _transition(TOWN_TO_PLAINS_GATE)
	var to_town := _transition(PLAINS_TO_TOWN_GATE)
	assert_false(to_plains.is_empty(), "world.json must define '%s'" % TOWN_TO_PLAINS_GATE)
	assert_false(to_town.is_empty(), "world.json must define '%s'" % PLAINS_TO_TOWN_GATE)
	if to_plains.is_empty() or to_town.is_empty():
		return

	assert_eq(str(to_plains["kind"]), "gate")
	assert_eq(str(to_plains["from_chunk"]), TOWN_CHUNK)
	var town_edge: Vector2i = to_plains["from_tile"]
	assert_eq(town_edge.x, city.width - 1, "the town gate must sit on the city east edge")
	assert_true(city.is_walkable(town_edge), "town gate tile %s must be walkable in the city" % str(town_edge))

	assert_eq(str(to_plains["to_chunk"]), WEST_CHUNK)
	var plains_edge: Vector2i = to_plains["to_tile"]
	assert_eq(plains_edge.x, 0, "the plains gate must sit on the plains_west west edge")
	assert_true(west.is_walkable(plains_edge), "plains gate tile %s must be walkable" % str(plains_edge))

	assert_eq(str(to_town["kind"]), "gate")
	assert_eq(str(to_town["from_chunk"]), WEST_CHUNK)
	assert_eq(to_town["from_tile"], plains_edge, "the return gate starts on the same plains edge tile")
	assert_eq(str(to_town["to_chunk"]), TOWN_CHUNK)
	var back_tile: Vector2i = to_town["to_tile"]
	assert_true(city.is_walkable(back_tile), "town return tile %s must be walkable in the city" % str(back_tile))


func test_plains_gates_form_a_symmetric_passage() -> void:
	var to_east := _transition(PLAINS_TO_EAST_GATE)
	var to_west := _transition(EAST_TO_PLAINS_GATE)
	assert_false(to_east.is_empty(), "world.json must define '%s'" % PLAINS_TO_EAST_GATE)
	assert_false(to_west.is_empty(), "world.json must define '%s'" % EAST_TO_PLAINS_GATE)
	if to_east.is_empty() or to_west.is_empty():
		return

	assert_eq(str(to_east["kind"]), "gate")
	assert_eq(str(to_east["from_chunk"]), WEST_CHUNK)
	var west_edge: Vector2i = to_east["from_tile"]
	assert_eq(west_edge.x, west.width - 1, "the eastern gate must sit on the plains_west east edge")
	assert_true(west.is_walkable(west_edge), "plains_west gate tile %s must be walkable" % str(west_edge))

	assert_eq(str(to_east["to_chunk"]), EAST_CHUNK)
	var east_edge: Vector2i = to_east["to_tile"]
	assert_eq(east_edge.x, 0, "the western gate must sit on the plains_east west edge")
	assert_true(east.is_walkable(east_edge), "plains_east gate tile %s must be walkable" % str(east_edge))

	assert_eq(str(to_west["kind"]), "gate")
	assert_eq(str(to_west["from_chunk"]), EAST_CHUNK)
	assert_eq(to_west["from_tile"], east_edge, "the return gate starts on the same plains_east edge tile")
	assert_eq(str(to_west["to_chunk"]), WEST_CHUNK)
	assert_eq(to_west["to_tile"], west_edge, "the return gate ends on the same plains_west edge tile")


func test_dungeon_door_starts_on_the_east_plains_edge() -> void:
	var door := _transition(DUNGEON_DOOR)
	assert_false(door.is_empty(), "world.json must define '%s'" % DUNGEON_DOOR)
	if door.is_empty():
		return
	assert_eq(str(door["kind"]), "door")
	assert_eq(str(door["from_chunk"]), EAST_CHUNK, "the dungeon door now sits in the eastern plains")
	var door_tile: Vector2i = door["from_tile"]
	assert_eq(door_tile.x, east.width - 1, "the dungeon door must sit on the plains_east east edge")
	assert_true(east.is_walkable(door_tile), "dungeon door tile %s must be walkable" % str(door_tile))
	assert_gt(east.find_path(east.entry, door_tile).size(), 0, "the dungeon door must be reachable from the entry")
	assert_eq(str(door["to_zone"]), "test_arena", "the door target stays unchanged until B3 replaces it")
	assert_eq(door["to_tile"], Vector2i(3, 2), "the door target tile stays unchanged until B3 replaces it")


func test_all_world_transition_tiles_are_walkable() -> void:
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


func test_world_chunks_are_contiguous() -> void:
	assert_true(world.is_valid(), "world.json errors: %s" % str(world.errors))

	var cells: Dictionary = {}
	for chunk_id: String in world.chunk_ids():
		var cell := world.grid_cell(chunk_id)
		assert_false(cells.has(cell), "grid cell %s is used by more than one chunk" % str(cell))
		cells[cell] = chunk_id
	assert_eq(cells.size(), world.chunk_ids().size(), "every chunk must have a unique grid cell")

	var chunk_ids := world.chunk_ids()
	if chunk_ids.is_empty():
		fail_test("world.json must place at least one chunk")
		return

	var visited: Dictionary = {}
	var queue: Array[Vector2i] = [world.grid_cell(chunk_ids[0])]
	visited[queue[0]] = true
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next := cell + offset
			if cells.has(next) and not visited.has(next):
				visited[next] = true
				queue.append(next)
	assert_eq(visited.size(), cells.size(), "every chunk must be reachable from the town by walking chunk to chunk")
