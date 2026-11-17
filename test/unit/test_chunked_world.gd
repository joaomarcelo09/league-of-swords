extends GutTest

const CHUNK_SIZE := 4
const OPEN_MAP := "....\n....\n....\n...."
const LEGEND := {
	".": {"type": "floor", "walkable": true},
	"#": {"type": "wall", "walkable": false},
}

var _load_calls: Array[String] = []
var _zones: Dictionary = {}  # chunk id -> Zone


func before_each() -> void:
	_load_calls.clear()
	_zones.clear()


func _chunk(chunk_id: String, x: int, y: int) -> Dictionary:
	return {
		"id": chunk_id,
		"grid": [x, y],
		"zone": "open",
		"kind": "plains",
	}


func _make_map(chunks: Array, radius: int) -> WorldMap:
	var map := WorldMap.load_from_dict({
		"chunk_size": [CHUNK_SIZE, CHUNK_SIZE],
		"load_radius": radius,
		"chunks": chunks,
	})
	assert_true(map.is_valid(), "test world map must be valid: %s" % str(map.errors))
	return map


func _open_zone() -> Zone:
	return Zone.load_from_strings(
		OPEN_MAP,
		{"legend": LEGEND, "entry": [1, 1]},
		"chunk.map",
		"chunk.json"
	)


func _load_zone(chunk_id: String) -> Zone:
	_load_calls.append(chunk_id)
	var cached: Zone = _zones.get(chunk_id, null)
	if cached != null:
		return cached
	return _open_zone()


func _has_error(world: ChunkedWorld, fragment: String) -> bool:
	for err in world.errors:
		if fragment in err:
			return true
	return false


func test_start_area_loads_and_offsets_apply() -> void:
	var map := _make_map([
		_chunk("a", 0, 0),
		_chunk("b", 1, 0),
		_chunk("c", 2, 0),
	], 1)
	var world := ChunkedWorld.new(map, Callable(self, "_load_zone"), "a")

	assert_true(world.is_valid(), "world must be valid: %s" % str(world.errors))
	assert_eq(world.loaded_ids(), ["a", "b"], "start chunk plus its Chebyshev neighbour")
	assert_eq(world.player_chunk, "a")
	assert_eq(world.start_chunk, "a")
	assert_eq(world.chunk_size(), Vector2i(CHUNK_SIZE, CHUNK_SIZE))
	assert_eq(world.chunk_offset("a"), Vector2i.ZERO)
	assert_eq(world.chunk_offset("b"), Vector2i(CHUNK_SIZE, 0))
	assert_eq(world.chunk_offset("c"), Vector2i(CHUNK_SIZE * 2, 0))
	assert_eq(world.world_width(), CHUNK_SIZE * 3)
	assert_eq(world.world_height(), CHUNK_SIZE)
	assert_eq(world.start_entry(), Vector2i(1, 1), "start zone entry is exposed in world tiles")
	assert_eq(world.chunk_at(Vector2i(5, 1)), "b")
	assert_eq(world.local_tile_at(Vector2i(5, 1)), Vector2i(1, 1))
	assert_true(world.is_world_tile_loaded(Vector2i(5, 1)))
	assert_false(world.is_world_tile_loaded(Vector2i(9, 1)), "chunk c is outside the load radius")
	assert_eq(world.loaded_chunks().size(), 2)
	assert_eq(str(world.loaded_chunks()[0].get("id")), "a")
	assert_eq(str(world.loaded_chunks()[1].get("id")), "b")
	assert_eq(world.loaded_chunks()[1].get("offset"), Vector2i(CHUNK_SIZE, 0))
	assert_eq(_load_calls, ["a", "b"], "each loaded chunk's zone is read once")


func test_update_streams_chunks_around_the_player() -> void:
	var map := _make_map([
		_chunk("a", 0, 0),
		_chunk("b", 1, 0),
		_chunk("c", 2, 0),
	], 1)
	var world := ChunkedWorld.new(map, Callable(self, "_load_zone"), "a")

	var changes := world.update(Vector2i(9, 1))

	assert_eq(changes["loaded"], ["c"], "the chunk at the player's cell loads")
	assert_eq(changes["unloaded"], ["a"], "the chunk two cells behind unloads")
	assert_eq(world.player_chunk, "c")
	assert_eq(world.loaded_ids(), ["b", "c"])

	var again := world.update(Vector2i(9, 2))
	assert_eq(again["loaded"], [], "staying inside the radius loads nothing")
	assert_eq(again["unloaded"], [], "staying inside the radius unloads nothing")
	assert_eq(_load_calls, ["a", "b", "c"], "chunks are never loaded twice")


func test_update_back_into_an_unloaded_area_reloads_it() -> void:
	var map := _make_map([
		_chunk("a", 0, 0),
		_chunk("b", 1, 0),
		_chunk("c", 2, 0),
	], 1)
	var world := ChunkedWorld.new(map, Callable(self, "_load_zone"), "a")
	world.update(Vector2i(9, 1))

	var changes := world.update(Vector2i(0, 0))

	assert_eq(changes["loaded"], ["a"])
	assert_eq(changes["unloaded"], ["c"])
	assert_true(world.is_loaded("a"))
	assert_false(world.is_loaded("c"))


func test_missing_start_chunk_reports_error() -> void:
	var map := _make_map([_chunk("a", 0, 0)], 1)

	var world := ChunkedWorld.new(map, Callable(self, "_load_zone"), "nope")

	assert_false(world.is_valid())
	assert_true(_has_error(world, "start chunk 'nope'"), "errors: %s" % str(world.errors))
	assert_eq(world.loaded_ids(), [], "nothing may load without a valid start chunk")


func test_invalid_world_map_reports_error() -> void:
	var map := WorldMap.load_from_dict({"chunks": []})

	var world := ChunkedWorld.new(map, Callable(self, "_load_zone"), "a")

	assert_false(world.is_valid())
	assert_gt(world.errors.size(), 0, "an invalid world map must be reported")


func test_missing_zone_loader_reports_error() -> void:
	var map := _make_map([_chunk("a", 0, 0)], 0)

	var world := ChunkedWorld.new(map, Callable(), "a")

	assert_false(world.is_valid())
	assert_true(_has_error(world, "no zone loader configured"), "errors: %s" % str(world.errors))
	assert_eq(world.loaded_ids(), [])


func test_zone_file_loader_reads_the_real_floor1_chunks() -> void:
	var world := ChunkedWorld.load_file(
		"res://data/zones/floor1/world.json",
		"res://data/zones/floor1",
		"floor1_x2_y1"
	)

	assert_true(world.is_valid(), "chunked floor 1 must load: %s" % str(world.errors))
	assert_eq(world.loaded_ids().size(), 9, "the city start chunk plus its 8 neighbours")
	assert_true(world.loaded_ids().has("floor1_x1_y0"))
	assert_true(world.loaded_ids().has("floor1_x3_y2"))
	assert_true(world.zone_for("floor1_x2_y1").is_valid())
	assert_true(world.zone_for("floor1_x1_y1").is_valid())
	assert_eq(world.chunk_offset("floor1_x2_y1"), Vector2i(64, 32))
	assert_eq(world.chunk_offset("floor1_x1_y1"), Vector2i(32, 32))
	assert_eq(world.start_entry(), Vector2i(93, 58), "city entry in world tiles")
	assert_true(world.is_walkable(Vector2i(63, 58)), "city floor on the west side of the seam")
	assert_true(world.is_walkable(Vector2i(64, 58)), "city floor on the east side of the seam")
	assert_false(world.is_world_tile_loaded(Vector2i(180, 110)), "the far south-east chunk is outside the load radius")


func test_streaming_covers_the_whole_9x4_grid_without_missing_or_duplicate_chunks() -> void:
	var world := ChunkedWorld.load_file(
		"res://data/zones/floor1/world.json",
		"res://data/zones/floor1",
		"floor1_x2_y1"
	)
	assert_true(world.is_valid(), "chunked floor 1 must load: %s" % str(world.errors))
	var map := world.map
	var chunk_ids := map.chunk_ids()
	assert_eq(chunk_ids.size(), 36, "the floor is a 9x4 grid of chunks")
	assert_eq(world.world_width(), 288, "9 chunks of 32 tiles")
	assert_eq(world.world_height(), 128, "4 chunks of 32 tiles")

	var seen_ids: Dictionary = {}
	var seen_cells: Dictionary = {}
	for chunk_id: String in chunk_ids:
		assert_false(seen_ids.has(chunk_id), "chunk id %s is listed once" % chunk_id)
		seen_ids[chunk_id] = true
		var cell := map.grid_cell(chunk_id)
		assert_false(seen_cells.has(cell), "grid cell %s is listed once" % str(cell))
		seen_cells[cell] = true

	var half := Vector2i(floori(map.chunk_size.x / 2.0), floori(map.chunk_size.y / 2.0))
	for chunk_id: String in chunk_ids:
		var center := map.chunk_to_world(chunk_id, half)
		var changes := world.update(center)
		var expected := map.chunks_near(map.grid_cell(chunk_id), map.load_radius)
		var loaded := world.loaded_ids()

		assert_eq(loaded, expected, "chunk %s keeps exactly its load_radius neighbourhood loaded" % chunk_id)
		assert_eq(world.errors, [], "streaming chunk %s reports no errors" % chunk_id)
		assert_eq(map.world_to_chunk(center).get("chunk_id", ""), chunk_id, "the centre tile maps back to its chunk")

		var seen_loaded: Dictionary = {}
		for loaded_id: String in loaded:
			assert_false(seen_loaded.has(loaded_id), "chunk %s is loaded only once" % loaded_id)
			seen_loaded[loaded_id] = true
			var zone := world.zone_for(loaded_id)
			assert_not_null(zone, "loaded chunk %s has a zone" % loaded_id)
			if zone != null:
				assert_true(zone.is_valid(), "loaded chunk %s is valid: %s" % [loaded_id, str(zone.errors)])

		var loaded_changes: Array = changes["loaded"]
		var unloaded_changes: Array = changes["unloaded"]
		assert_eq(loaded_changes.size(), _unique_count(loaded_changes), "no duplicate loaded ids at %s" % chunk_id)
		assert_eq(unloaded_changes.size(), _unique_count(unloaded_changes), "no duplicate unloaded ids at %s" % chunk_id)
		for loaded_id: Variant in loaded_changes:
			assert_false(unloaded_changes.has(loaded_id), "chunk %s is not loaded and unloaded in one step" % str(loaded_id))


func _unique_count(values: Array) -> int:
	var unique: Dictionary = {}
	for value: Variant in values:
		unique[value] = true
	return unique.size()
