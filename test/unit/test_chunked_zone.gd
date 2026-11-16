extends GutTest

const CHUNK_SIZE := 4
const OPEN_MAP := "....\n....\n....\n...."
const WALL_MAP := "....\n.#..\n....\n...."
const SAFE_MAP := "SS..\n....\n....\n...."
const LEGEND := {
	".": {"type": "floor", "walkable": true},
	"#": {"type": "wall", "walkable": false},
	"S": {"type": "floor", "walkable": true, "safe": true},
}

var _zones: Dictionary = {}  # chunk id -> Zone
var _registry: DataRegistry = null


func before_each() -> void:
	_zones.clear()
	_registry = DataRegistry.new()
	_registry.load_dir("res://data")


func _make_zone(rows: String, extra: Dictionary = {}) -> Zone:
	var data := {"legend": LEGEND, "entry": [0, 0]}
	for key: Variant in extra.keys():
		data[key] = extra[key]
	return Zone.load_from_strings(rows, data, "chunk.map", "chunk.json")


func _load_zone(chunk_id: String) -> Zone:
	var zone: Zone = _zones.get(chunk_id, null)
	return zone


func _chunk(chunk_id: String, x: int) -> Dictionary:
	return {"id": chunk_id, "grid": [x, 0], "zone": chunk_id, "kind": "plains"}


func _make_world(radius: int = 1) -> ChunkedWorld:
	var map := WorldMap.load_from_dict({
		"chunk_size": [CHUNK_SIZE, CHUNK_SIZE],
		"load_radius": radius,
		"chunks": [_chunk("a", 0), _chunk("b", 1), _chunk("c", 2)],
	})
	assert_true(map.is_valid(), "test world map must be valid: %s" % str(map.errors))
	return ChunkedWorld.new(map, Callable(self, "_load_zone"), "a")


func _open_chunks() -> void:
	_zones["a"] = _make_zone(WALL_MAP)
	_zones["b"] = _make_zone(SAFE_MAP)
	_zones["c"] = _make_zone(OPEN_MAP)


func _enemy_of_type(sim: WorldSim, type_id: String) -> Entity:
	for entity: Entity in sim.entities.values():
		if entity.kind == "enemy" and entity.enemy_type_id == type_id:
			return entity
	return null


func _enemy_count(sim: WorldSim, type_id: String) -> int:
	var count := 0
	for entity: Entity in sim.entities.values():
		if entity.kind == "enemy" and entity.enemy_type_id == type_id:
			count += 1
	return count


func test_walkability_is_looked_up_in_the_covering_chunk() -> void:
	_open_chunks()
	var world := _make_world()
	var chunked := ChunkedZone.new(world)

	assert_true(chunked.is_valid(), "chunked zone must be valid: %s" % str(chunked.errors))
	assert_eq(chunked.width, CHUNK_SIZE * 3)
	assert_eq(chunked.height, CHUNK_SIZE)

	assert_true(chunked.is_walkable(Vector2i(0, 0)), "chunk a floor")
	assert_false(chunked.is_walkable(Vector2i(1, 1)), "wall inside chunk a")
	assert_true(chunked.is_walkable(Vector2i(4, 0)), "first tile of chunk b")
	assert_true(chunked.is_walkable(Vector2i(6, 1)), "chunk b floor")
	assert_false(chunked.is_walkable(Vector2i(9, 1)), "chunk c is not loaded")
	assert_false(chunked.is_walkable(Vector2i(0, 0) - Vector2i(1, 0)), "outside the world")

	assert_true(chunked.is_safe(Vector2i(4, 0)), "safe tile comes from chunk b's legend")
	assert_true(chunked.is_safe(Vector2i(5, 0)))
	assert_false(chunked.is_safe(Vector2i(6, 0)), "chunk b floor is not safe")
	assert_eq(chunked.tile_type(Vector2i(1, 1)), "wall")
	assert_eq(chunked.entry, Vector2i(0, 0), "start chunk entry in world tiles")


func test_path_crosses_the_chunk_boundary() -> void:
	_open_chunks()
	var chunked := ChunkedZone.new(_make_world())

	var path := chunked.find_path(Vector2i(1, 0), Vector2i(6, 1))

	assert_gt(path.size(), 0, "a path between two loaded chunks must exist")
	assert_eq(path[0], Vector2i(1, 0))
	assert_eq(path[path.size() - 1], Vector2i(6, 1))
	var crossed := false
	for tile: Vector2i in path:
		if tile.x >= CHUNK_SIZE:
			crossed = true
	assert_true(crossed, "the path must step into chunk b")

	var blocked := chunked.find_path(Vector2i(1, 0), Vector2i(9, 1))
	assert_eq(blocked.size(), 0, "no path into an unloaded chunk")


func test_real_floor_path_crosses_city_and_plains_chunks() -> void:
	var world := ChunkedWorld.load_file(
		"res://data/zones/floor1/world.json",
		"res://data/zones/floor1",
		"floor1_x2_y1"
	)
	assert_true(world.is_valid(), "chunked floor 1 must load: %s" % str(world.errors))
	var chunked := ChunkedZone.new(world)

	# From the city entry west across the chunk seam (x = 64) out onto the plains.
	var target := Vector2i(45, 58)
	assert_true(chunked.is_walkable(Vector2i(63, 58)), "city tile west of the seam")
	assert_true(chunked.is_walkable(Vector2i(64, 58)), "city tile east of the seam")
	assert_false(chunked.is_safe(target), "the target is on the plains")
	var path := chunked.find_path(chunked.entry, target)
	assert_gt(path.size(), 0, "the city opens seamlessly into the neighbouring plains chunk")
	if path.size() > 0:
		assert_eq(path[path.size() - 1], target)


func test_entry_stays_the_town_entry_when_the_town_unloads() -> void:
	var world := ChunkedWorld.load_file(
		"res://data/zones/floor1/world.json",
		"res://data/zones/floor1",
		"floor1_x2_y1"
	)
	assert_true(world.is_valid(), "chunked floor 1 must load: %s" % str(world.errors))
	var chunked := ChunkedZone.new(world)
	var town_entry := chunked.entry
	assert_eq(town_entry, Vector2i(93, 58), "the start spawn is the city entry")

	world.update(Vector2i(180, 110))
	assert_false(world.is_loaded("floor1_x2_y1"), "moving to the far south-east plains unloads the city start chunk")
	chunked.refresh()
	assert_eq(chunked.entry, town_entry, "entry must not depend on the loaded chunks")

	world.update(Vector2i(64, 32))
	chunked.refresh()
	assert_true(world.is_loaded("floor1_x2_y1"), "the city start chunk reloads")
	assert_eq(chunked.entry, town_entry, "reloading the town keeps the same entry")
	assert_true(chunked.is_walkable(chunked.entry), "the town entry is walkable with the town loaded")


func test_sim_moves_player_across_chunks() -> void:
	_open_chunks()
	var chunked := ChunkedZone.new(_make_world())
	var sim := WorldSim.new(chunked, _registry)
	var player := sim.spawn("player", Vector2i(1, 0), 4.0, 100.0)
	assert_not_null(player, "player must spawn on chunk a")

	sim.submit(Commands.move_to(player.id, Vector2i(6, 1)))
	for _tick in range(200):
		sim.step(sim.tick_length)

	assert_eq(player.tile(), Vector2i(6, 1), "player walks from chunk a into chunk b")


func test_chunk_spawns_follow_streaming() -> void:
	_zones["a"] = _make_zone(WALL_MAP, {
		"spawns": [{"enemy": "cinder_bat", "tile": [1, 0]}],
		"npcs": [{"id": "npc_a", "kind": "merchant", "tile": [2, 0]}],
	})
	_zones["b"] = _make_zone(SAFE_MAP, {
		"spawns": [{"enemy": "ash_stalker", "tile": [1, 0]}],
		"npcs": [{"id": "npc_b", "kind": "merchant", "tile": [2, 0]}],
	})
	_zones["c"] = _make_zone(OPEN_MAP, {
		"spawns": [{"enemy": "bog_slime", "tile": [1, 0]}],
	})

	var chunked := ChunkedZone.new(_make_world())
	var sim := WorldSim.new(chunked, _registry)

	var spawned := sim.spawn_zone_enemies()
	assert_eq(spawned.size(), 2, "both loaded chunks spawn their enemies")
	assert_eq(sim.spawn_zone_enemies().size(), 0, "loaded chunks are not spawned twice")

	var bat := _enemy_of_type(sim, "cinder_bat")
	var stalker := _enemy_of_type(sim, "ash_stalker")
	assert_not_null(bat)
	assert_not_null(stalker)
	assert_eq(Vector2i(bat.pos), Vector2i(1, 0), "chunk a spawn stays at its world tile")
	assert_eq(Vector2i(stalker.pos), Vector2i(5, 0), "chunk b spawn is offset by the chunk origin")

	assert_eq(WorldSim.parse_tile_coord(sim.get_npc("npc_a").get("tile")), Vector2i(2, 0))
	assert_eq(WorldSim.parse_tile_coord(sim.get_npc("npc_b").get("tile")), Vector2i(6, 0))

	var changes := sim.update_chunks(Vector2i(9, 0))
	assert_true(bool(changes.get("changed", false)))
	assert_eq(changes["loaded"], ["c"])
	assert_eq(changes["unloaded"], ["a"])
	assert_null(sim.get_entity(bat.id), "the unloaded chunk's enemies are dropped")
	assert_not_null(sim.get_entity(stalker.id), "the still-loaded chunk keeps its enemies")
	assert_eq(_enemy_count(sim, "bog_slime"), 1, "the newly loaded chunk spawns its enemies")
	assert_eq(Vector2i(_enemy_of_type(sim, "bog_slime").pos), Vector2i(9, 0))
	assert_true(sim.get_npc("npc_a").is_empty(), "NPCs of the unloaded chunk disappear")
	assert_false(sim.get_npc("npc_b").is_empty(), "NPCs of a loaded chunk stay available")

	var repeat := sim.update_chunks(Vector2i(9, 0))
	assert_false(bool(repeat.get("changed", false)), "no change when the player stays put")
	assert_eq(_enemy_count(sim, "bog_slime"), 1, "staying put does not duplicate spawns")

	var back := sim.update_chunks(Vector2i(1, 0))
	assert_eq(back["loaded"], ["a"])
	assert_eq(back["unloaded"], ["c"])
	assert_eq(_enemy_count(sim, "cinder_bat"), 1, "a reloaded chunk spawns its enemies again")
	assert_eq(_enemy_count(sim, "bog_slime"), 0, "the unloaded chunk's enemies are gone")


func test_game_session_streams_chunks() -> void:
	_open_chunks()
	var chunked := ChunkedZone.new(_make_world())
	var session := GameSession.new(chunked, _registry)

	var changes := session.update_chunks(Vector2i(9, 0))

	assert_eq(changes["loaded"], ["c"])
	assert_eq(changes["unloaded"], ["a"])
	assert_eq(changes["player_chunk"], "c")
