extends GutTest

## JGT-114: the floor 1 center chunk (center.json + center.map), a stone plaza
## holding the door into the floor 1 dungeon zone, and its world.json wiring.

const ZONES_DIR := "res://data/zones/floor1"
const WORLD_PATH := ZONES_DIR + "/world.json"

const CENTER_CHUNK := "floor1_center"
const CENTER_ZONE_STEM := "center"
const PLAINS_EAST_CHUNK := "floor1_plains_east"
const DUNGEON_ZONE_STEM := "floor1"
const OLD_ARENA_CHUNK := "floor1_arena"

const PLAINS_EAST_TO_CENTER_GATE := "plains_east_to_center_gate"
const CENTER_TO_PLAINS_EAST_GATE := "center_to_plains_east_gate"
const DUNGEON_DOOR := "center_to_dungeon_door"
const DUNGEON_DOOR_LABEL := "Dungeon Entrance"

## The plaza fills the chunk with the same stone-and-grass palette as the
## floor 1 dungeon zone.
const CENTER_TILE_TYPES := ["wall", "floor", "grass"]
const CENTER_DECOR_IDS := ["", "grass_tuft", "torch", "bones", "rubble", "crate", "barrel"]

## Gate row shared with the eastern plains: the west gate gap and the door
## tunnel both sit on this row.
const GATE_ROW := 16

var world: WorldMap = null
var center: Zone = null
var plains_east: Zone = null
var dungeon: Zone = null


func before_each() -> void:
	world = WorldMap.load_file(WORLD_PATH)
	center = _load_zone(CENTER_ZONE_STEM)
	plains_east = _load_zone("plains_east")
	dungeon = _load_zone(DUNGEON_ZONE_STEM)


func _load_zone(stem: String) -> Zone:
	return Zone.load_files(ZONES_DIR.path_join(stem + ".map"), ZONES_DIR.path_join(stem + ".json"))


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


func test_center_zone_loads_without_errors() -> void:
	assert_not_null(center)
	assert_eq(center.errors.size(), 0, "center errors: %s" % str(center.errors))
	assert_true(center.is_valid(), "center must load with no errors")


func test_center_dimensions_match_chunk_size() -> void:
	assert_true(world.is_valid(), "world.json errors: %s" % str(world.errors))
	assert_eq(Vector2i(center.width, center.height), world.chunk_size, "center must fill exactly one world chunk")


func test_world_places_the_center_east_of_the_eastern_plains() -> void:
	assert_true(world.is_valid(), "world.json errors: %s" % str(world.errors))
	assert_eq(world.zone_stem(CENTER_CHUNK), CENTER_ZONE_STEM, "floor1_center must load the center zone")
	assert_eq(world.grid_cell(CENTER_CHUNK), Vector2i(3, 0), "the center chunk sits at the east end of floor 1")
	assert_eq(world.chunk_kind(CENTER_CHUNK), "dungeon_door")
	assert_eq(world.chunk_at_cell(Vector2i(3, 0)), CENTER_CHUNK)
	assert_false(world.has_chunk(OLD_ARENA_CHUNK), "the placeholder arena chunk is replaced by the center chunk")


func test_entry_is_walkable_and_not_safe() -> void:
	assert_true(center.is_walkable(center.entry), "center entry %s must be walkable" % str(center.entry))
	assert_false(center.is_safe(center.entry), "the center plaza is not a safe town zone")


func test_center_has_no_enemy_spawns() -> void:
	assert_eq(center.spawns.size(), 0, "the center plaza is a decor-only clearing")


func test_center_has_no_zone_exits() -> void:
	assert_eq(center.exits.size(), 0, "travel out of the chunk is handled by world.json transitions")


func test_center_uses_the_dungeon_palette() -> void:
	for y in range(center.height):
		for x in range(center.width):
			var t := Vector2i(x, y)
			assert_true(center.tile_type(t) in CENTER_TILE_TYPES, "center tile %s uses unexpected type '%s'" % [str(t), center.tile_type(t)])
			var decor := center.decor_at(t)
			assert_true(decor in CENTER_DECOR_IDS, "center tile %s uses unexpected decor '%s'" % [str(t), decor])


func test_dungeon_door_structure_has_walls_and_torches() -> void:
	var torches := 0
	var structure_walls := 0
	for y in range(center.height):
		for x in range(center.width):
			var t := Vector2i(x, y)
			if center.decor_at(t) == "torch":
				torches += 1
			if x >= center.width - 3 and center.tile_type(t) == "wall":
				structure_walls += 1
	assert_gte(torches, 2, "the dungeon-door structure needs torches")
	assert_gt(structure_walls, 0, "the dungeon-door structure needs walls on the far side of the plaza")


func test_west_gate_approach_path_is_walkable() -> void:
	var gate := _transition(PLAINS_EAST_TO_CENTER_GATE)
	assert_false(gate.is_empty(), "world.json must define '%s'" % PLAINS_EAST_TO_CENTER_GATE)
	if gate.is_empty():
		return
	var gate_tile: Vector2i = gate["to_tile"]
	assert_eq(gate_tile, Vector2i(0, GATE_ROW), "the west gate gap must sit on the center west edge")
	for x in range(0, center.width - 1):
		var t := Vector2i(x, GATE_ROW)
		assert_true(center.is_walkable(t), "the approach path tile %s must be walkable" % str(t))


func test_gate_tiles_are_walkable_and_reachable_from_entry() -> void:
	assert_true(world.is_valid(), "world.json errors: %s" % str(world.errors))
	var edge_tiles := _edge_tiles_of(CENTER_CHUNK)
	assert_gt(edge_tiles.size(), 0, "the center chunk must be wired to the world")
	for edge_tile: Vector2i in edge_tiles:
		assert_true(center.is_walkable(edge_tile), "center transition tile %s must be walkable" % str(edge_tile))
		assert_gt(center.find_path(center.entry, edge_tile).size(), 0, "center transition tile %s must be reachable from the entry" % str(edge_tile))


func test_east_plains_gate_forms_a_symmetric_passage() -> void:
	var to_center := _transition(PLAINS_EAST_TO_CENTER_GATE)
	var to_plains := _transition(CENTER_TO_PLAINS_EAST_GATE)
	assert_false(to_center.is_empty(), "world.json must define '%s'" % PLAINS_EAST_TO_CENTER_GATE)
	assert_false(to_plains.is_empty(), "world.json must define '%s'" % CENTER_TO_PLAINS_EAST_GATE)
	if to_center.is_empty() or to_plains.is_empty():
		return

	assert_eq(str(to_center["kind"]), "gate")
	assert_eq(str(to_center["from_chunk"]), PLAINS_EAST_CHUNK)
	assert_eq(str(to_center["to_chunk"]), CENTER_CHUNK)
	assert_eq(str(to_plains["kind"]), "gate")
	assert_eq(str(to_plains["from_chunk"]), CENTER_CHUNK)
	assert_eq(str(to_plains["to_chunk"]), PLAINS_EAST_CHUNK)

	var plains_edge: Vector2i = to_center["from_tile"]
	assert_eq(plains_edge.x, plains_east.width - 1, "the gate must sit on the eastern plains east edge")
	assert_true(plains_east.is_walkable(plains_edge), "eastern plains gate tile %s must be walkable" % str(plains_edge))
	assert_eq(to_center["to_tile"], to_plains["from_tile"], "both directions must use the same center edge tile")
	assert_eq(to_plains["to_tile"], plains_edge, "the return gate ends on the same eastern plains edge tile")


func test_dungeon_door_is_wired_to_the_center_chunk() -> void:
	var door := _transition(DUNGEON_DOOR)
	assert_false(door.is_empty(), "world.json must define '%s'" % DUNGEON_DOOR)
	if door.is_empty():
		return

	assert_eq(str(door["kind"]), "door")
	assert_eq(str(door["from_chunk"]), CENTER_CHUNK, "the dungeon door now sits in the center chunk")
	assert_eq(str(door["label"]), DUNGEON_DOOR_LABEL)
	assert_eq(str(door["to_zone"]), DUNGEON_ZONE_STEM, "the door must load the existing floor 1 dungeon zone")

	var door_tile: Vector2i = door["from_tile"]
	assert_true(center.is_walkable(door_tile), "dungeon door tile %s must be walkable" % str(door_tile))
	assert_gt(center.find_path(center.entry, door_tile).size(), 0, "the dungeon door must be reachable from the entry")


func test_dungeon_door_target_is_a_walkable_dungeon_start() -> void:
	assert_true(dungeon.is_valid(), "floor1 zone errors: %s" % str(dungeon.errors))
	var door := _transition(DUNGEON_DOOR)
	assert_false(door.is_empty(), "world.json must define '%s'" % DUNGEON_DOOR)
	if door.is_empty():
		return

	var target: Vector2i = door["to_tile"]
	assert_true(dungeon.is_walkable(target), "dungeon door target %s must be walkable in floor1" % str(target))
	assert_false(dungeon.is_safe(target), "the door must not drop the player inside the old town")
	assert_ne(dungeon.tile_type(target), "town_floor", "the door target must be outside the old town")
	assert_gt(dungeon.find_path(dungeon.entry, target).size(), 0, "the dungeon start must be reachable from the floor 1 town")


func test_dungeon_door_walk_enters_the_dungeon_and_returns_to_the_center() -> void:
	var chunked := ChunkedWorld.load_file(WORLD_PATH, ZONES_DIR, CENTER_CHUNK)
	assert_true(chunked.is_valid(), "chunked floor errors: %s" % str(chunked.errors))
	var registry := DataRegistry.new()
	registry.load_dir("res://data")
	var chunked_zone := ChunkedZone.new(chunked)
	var session := GameSession.new(chunked_zone, registry, null, null, null, "floor1")
	session.zone_loader = func(stem: String) -> Zone: return _load_zone(stem)
	assert_not_null(session.spawn_player(), "the player must spawn at the center entry")

	var door := _transition(DUNGEON_DOOR)
	assert_false(door.is_empty(), "world.json must define '%s'" % DUNGEON_DOOR)
	if door.is_empty():
		return
	var door_world: Vector2i = chunked.map.chunk_to_world(CENTER_CHUNK, door["from_tile"])
	session.player.pos = WorldSim.tile_center(door_world)

	var enter := session.check_world_travel(session.player.id)

	assert_true(enter["ok"], str(enter))
	assert_true(enter["zone_changed"])
	assert_eq(session.player.tile(), door["to_tile"], "the player enters the dungeon at the door target")

	session.player.pos = WorldSim.tile_center(door["return_tile"])
	var leave := session.check_world_travel(session.player.id)

	assert_true(leave["ok"], str(leave))
	assert_true(session.in_chunked_world(), "the return link brings the session back to the chunks")
	assert_eq(session.player.tile(), chunked.map.chunk_to_world(CENTER_CHUNK, door["return_to_tile"]))


func test_dungeon_door_has_a_walkable_return_link_to_the_center_chunk() -> void:
	var door := _transition(DUNGEON_DOOR)
	assert_false(door.is_empty(), "world.json must define '%s'" % DUNGEON_DOOR)
	if door.is_empty():
		return

	assert_eq(str(door["return_chunk"]), CENTER_CHUNK, "the dungeon door must return to the center chunk")
	var return_tile: Vector2i = door["return_tile"]
	assert_true(dungeon.is_walkable(return_tile), "dungeon return tile %s must be walkable" % str(return_tile))
	assert_ne(return_tile, door["to_tile"], "the return tile must not be the entry tile")

	var return_to_tile: Vector2i = door["return_to_tile"]
	assert_true(center.is_walkable(return_to_tile), "center return tile %s must be walkable" % str(return_to_tile))
	assert_gt(center.find_path(center.entry, return_to_tile).size(), 0, "the return tile must be reachable from the entry")


func test_the_dungeon_door_is_the_only_door_in_the_world() -> void:
	assert_true(world.is_valid(), "world.json errors: %s" % str(world.errors))
	var doors := 0
	for chunk_id: String in world.chunk_ids():
		for transition: Dictionary in world.transitions_of(chunk_id):
			if str(transition["kind"]) != "door":
				continue
			doors += 1
			assert_eq(str(transition["from_chunk"]), CENTER_CHUNK, "only the center chunk may hold a zone door")
	assert_eq(doors, 1, "world.json must hold exactly one zone door")


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
	assert_eq(visited.size(), cells.size(), "every chunk must be walkable from the town by chunk to chunk")


func test_all_walkable_tiles_reachable_from_entry() -> void:
	for y in range(center.height):
		for x in range(center.width):
			var t := Vector2i(x, y)
			if center.is_walkable(t):
				assert_gt(center.find_path(center.entry, t).size(), 0, "walkable tile %s must be reachable from entry %s" % [str(t), str(center.entry)])
