extends GutTest
## JGT-122: the Floor 1 boss gate, a 10 tile opening in the south outer wall.
## JGT-132 pinned it at its original absolute x=162 (chunk x5) while the map
## grew east, so its share of the width is no longer 87%. It stays the only
## transition out of the floor and a door to the dungeon.

const WORLD_PATH := "res://data/zones/floor1/world.json"
const ZONES_DIR := "res://data/zones/floor1"
const GATE_CHUNK := "floor1_x5_y3"
const CHUNK := 32
const GATE_X0 := 162

var _chunked: ChunkedWorld = null
var _map: WorldMap = null


func before_each() -> void:
	_chunked = ChunkedWorld.load_file(WORLD_PATH, ZONES_DIR)
	assert_true(_chunked.is_valid(), "floor must load: %s" % str(_chunked.errors))
	_map = _chunked.map
	_chunked.update(_map.chunk_to_world(GATE_CHUNK, Vector2i(6, 28)))


func _gate_transitions() -> Array[Dictionary]:
	return _map.transitions_of(GATE_CHUNK)


func test_gate_is_ten_wide_in_the_south_wall_at_its_pinned_x() -> void:
	var gates := _gate_transitions()
	assert_eq(gates.size(), 10, "gate is 10 tiles wide")
	var xs: Array[int] = []
	for t: Dictionary in gates:
		var tile: Vector2i = t["from_tile"]
		assert_eq(tile.y, CHUNK - 1, "gate sits on the bottom wall row of its chunk")
		xs.append(tile.x)
	xs.sort()
	for i in range(1, xs.size()):
		assert_eq(xs[i], xs[i - 1] + 1, "gate tiles are contiguous")
	var cell := _map.grid_cell(GATE_CHUNK)
	var first_world: int = cell.x * CHUNK + xs[0]
	var center_world: float = float(first_world) + float(xs[xs.size() - 1] - xs[0]) / 2.0 + 0.5
	assert_eq(first_world, GATE_X0, "gate keeps its original absolute x=162")
	assert_almost_eq(center_world, float(GATE_X0) + 5.0, 0.01, "gate centred on x=166.5")


func test_gate_tiles_are_open_and_flanked_by_posts() -> void:
	var zone_map := FileAccess.get_file_as_string(ZONES_DIR + "/chunk_x5_y3.map").split("\n")
	var row: String = zone_map[CHUNK - 1]
	var open := 0
	for t: Dictionary in _gate_transitions():
		var tile: Vector2i = t["from_tile"]
		assert_eq(row[tile.x], "G", "gate tile %s uses the gate glyph" % str(tile))
		assert_true(_chunked.is_walkable(_map.chunk_to_world(GATE_CHUNK, tile)))
		open += 1
	assert_eq(open, 10)
	assert_eq(row.count("P"), 2, "two gate posts frame the opening")
	assert_eq(row.count("G"), 10)


func test_gate_is_the_only_transition_of_the_floor() -> void:
	var count := 0
	for id: String in _map.chunk_ids():
		for t: Dictionary in _map.transitions_of(id):
			count += 1
			assert_eq(id, GATE_CHUNK)
			assert_eq(t["kind"], "door")
	assert_eq(count, 10)


func test_door_zone_and_return_refs_are_valid() -> void:
	var dungeon := Zone.load_files(ZONES_DIR + "/floor1.map", ZONES_DIR + "/floor1.json")
	assert_true(dungeon.is_valid(), str(dungeon.errors))
	for t: Dictionary in _gate_transitions():
		assert_eq(t["to_zone"], "floor1")
		assert_eq(t["to_tile"], Vector2i(20, 7))
		assert_true(dungeon.is_walkable(t["to_tile"]), "dungeon entry is walkable")
		assert_true(dungeon.is_walkable(t["return_tile"]), "dungeon return tile is walkable")
		assert_eq(t["return_chunk"], GATE_CHUNK)
		var back: Vector2i = t["return_to_tile"]
		var from_tile: Vector2i = t["from_tile"]
		assert_eq(back.x, from_tile.x, "return lands in the same column")
		assert_lt(back.y, from_tile.y, "return lands north of the gate")
		assert_true(_chunked.is_walkable(_map.chunk_to_world(GATE_CHUNK, back)), "return tile is walkable")
		var same := _map.transition_at(GATE_CHUNK, back)
		assert_true(same.is_empty(), "return tile is not itself a transition")


func test_resume_from_dungeon_returns_north_of_the_gate() -> void:
	var gate: Dictionary = _gate_transitions()[0]
	var character := CharacterState.new()
	var capture := ChunkResume.capture_door_return(_map, character, {
		"chunk": gate["return_chunk"],
		"to_tile": gate["return_to_tile"],
	})
	assert_true(capture.get("ok", false), str(capture))
	assert_eq(character.chunk, GATE_CHUNK)
	var result := ChunkResume.resume(_map, _chunked.loader, character)
	assert_true(result.get("ok", false), str(result))
	var gate_world := _map.chunk_to_world(GATE_CHUNK, gate["from_tile"])
	var world_tile: Vector2i = result["world_tile"]
	assert_eq(world_tile.x, gate_world.x)
	assert_lt(world_tile.y, gate_world.y, "resume lands north of the gate")
	assert_true(_chunked.is_walkable(world_tile))
