extends GutTest

## JGT-119: walking onto a gate moves the player to the next chunk and the
## center-chunk door enters the dungeon zone, whose return link brings the
## player back. Covers locked transitions and anti-ping-pong on arrival.

const CHUNK_SIZE := 32
const ZONE_SIZE := 32
const DATA_DIR := "res://data"

const TOWN_CHUNK := "c_0"
const PLAINS_CHUNK := "c_1"
const CENTER_CHUNK := "c_2"
const DUNGEON_STEM := "test_dungeon"

const TOWN_GATE := Vector2i(31, 5)
const PLAINS_GATE := Vector2i(0, 5)
const TOWN_GATE_WORLD := Vector2i(31, 5)
const PLAINS_GATE_WORLD := Vector2i(CHUNK_SIZE, 5)
const LOCKED_GATE := Vector2i(10, 10)
const DOOR_TILE := Vector2i(10, 10)
const DOOR_WORLD := Vector2i(2 * CHUNK_SIZE + 10, 10)
const DOOR_SPAWN := Vector2i(5, 5)
const DOOR_RETURN := Vector2i(5, 6)
const DOOR_RETURN_WORLD := Vector2i(2 * CHUNK_SIZE + 9, 10)
const SAME_TILE_DOOR := Vector2i(20, 20)
const SAME_TILE_DOOR_WORLD := Vector2i(2 * CHUNK_SIZE + 20, 20)
const SAME_TILE_SPAWN := Vector2i(10, 10)

var _registry: DataRegistry = null
var _dungeon: Zone = null


func before_each() -> void:
	_registry = DataRegistry.new()
	_registry.load_dir(DATA_DIR)
	_dungeon = _floor_zone()


func _floor_zone() -> Zone:
	var rows: Array[String] = []
	for _y in range(ZONE_SIZE):
		rows.append(".".repeat(ZONE_SIZE))
	return Zone.load_from_strings("\n".join(rows), {
		"legend": {".": {"type": "floor", "walkable": true}},
		"entry": [1, 1],
	}, "chunk.map", "chunk.json")


func _chunk(chunk_id: String, cell: Array) -> Dictionary:
	return {"id": chunk_id, "grid": cell, "zone": "test_floor", "kind": "plains"}


func _gate(transition_id: String, from_chunk: String, from_tile: Vector2i, to_chunk: String, to_tile: Vector2i, extra: Dictionary = {}) -> Dictionary:
	var transition := {
		"id": transition_id,
		"kind": "gate",
		"from": {"chunk": from_chunk, "tile": [from_tile.x, from_tile.y]},
		"to": {"chunk": to_chunk, "tile": [to_tile.x, to_tile.y]},
	}
	transition.merge(extra, true)
	return transition


func _door(transition_id: String, from_chunk: String, from_tile: Vector2i, to_tile: Vector2i, return_tile: Vector2i, return_to_tile: Vector2i) -> Dictionary:
	return {
		"id": transition_id,
		"kind": "door",
		"from": {"chunk": from_chunk, "tile": [from_tile.x, from_tile.y]},
		"to": {"zone": DUNGEON_STEM, "tile": [to_tile.x, to_tile.y]},
		"return": {
			"tile": [return_tile.x, return_tile.y],
			"chunk": CENTER_CHUNK,
			"to_tile": [return_to_tile.x, return_to_tile.y],
		},
	}


func _make_map() -> WorldMap:
	var map := WorldMap.load_from_dict({
		"chunk_size": [CHUNK_SIZE, CHUNK_SIZE],
		"load_radius": 1,
		"chunks": [
			_chunk(TOWN_CHUNK, [0, 0]),
			_chunk(PLAINS_CHUNK, [1, 0]),
			_chunk(CENTER_CHUNK, [2, 0]),
		],
		"transitions": [
			_gate("town_to_plains", TOWN_CHUNK, TOWN_GATE, PLAINS_CHUNK, PLAINS_GATE),
			_gate("plains_to_town", PLAINS_CHUNK, PLAINS_GATE, TOWN_CHUNK, Vector2i(30, 5)),
			_gate("locked_gate", TOWN_CHUNK, LOCKED_GATE, PLAINS_CHUNK, Vector2i(10, 10), {"requires_boss": "warden"}),
			_gate("chunk_door", TOWN_CHUNK, Vector2i(20, 20), PLAINS_CHUNK, Vector2i(5, 20), {"kind": "door"}),
			_door("dungeon_door", CENTER_CHUNK, DOOR_TILE, DOOR_SPAWN, DOOR_RETURN, DOOR_RETURN_WORLD - Vector2i(2 * CHUNK_SIZE, 0)),
			_door("same_tile_door", CENTER_CHUNK, SAME_TILE_DOOR, SAME_TILE_SPAWN, SAME_TILE_SPAWN, Vector2i(19, 20)),
		],
	})
	assert_true(map.is_valid(), "test world must be valid: %s" % str(map.errors))
	return map


func _make_session(map: WorldMap) -> GameSession:
	var chunked := ChunkedWorld.new(map, Callable(self, "_load_chunk_zone"), TOWN_CHUNK)
	assert_true(chunked.is_valid(), "chunked world must load: %s" % str(chunked.errors))
	var chunked_zone := ChunkedZone.new(chunked)
	var session := GameSession.new(chunked_zone, _registry, null, null, null, "floor1")
	session.zone_loader = Callable(self, "_load_travel_zone")
	session.spawn_player(Vector2i(1, 1))
	assert_not_null(session.player, "player must spawn in the town")
	return session


func _load_chunk_zone(_chunk_id: String) -> Zone:
	return _floor_zone()


func _load_travel_zone(stem: String) -> Zone:
	if stem == DUNGEON_STEM:
		return _dungeon
	return null


func _place(session: GameSession, tile: Vector2i) -> void:
	session.player.pos = WorldSim.tile_center(tile)


func _find_event(events: Array[Dictionary], event_type: String) -> Dictionary:
	for event: Dictionary in events:
		if str(event.get("type", "")) == event_type:
			return event
	return {}


# --- Gates ---

func test_stepping_onto_a_gate_moves_the_player_to_the_next_chunk() -> void:
	var map := _make_map()
	var session := _make_session(map)
	_place(session, TOWN_GATE_WORLD)

	var result := session.check_world_travel(session.player.id)

	assert_true(result["ok"], str(result))
	assert_eq(result["kind"], "gate")
	assert_eq(result["id"], "town_to_plains")
	assert_eq(result["to_chunk"], PLAINS_CHUNK)
	assert_eq(result["to_world"], PLAINS_GATE_WORLD)
	assert_eq(session.player.tile(), PLAINS_GATE_WORLD, "the player is teleported to the destination tile")
	assert_true(session.world.chunked_world.is_loaded(PLAINS_CHUNK), "the destination chunk is streamed in")
	assert_true(bool(result.get("changed", false)), "gate travel reports the streaming change")
	assert_eq(session.world.chunked_world.player_chunk, PLAINS_CHUNK)


func test_gate_travel_clears_the_old_move_command() -> void:
	var map := _make_map()
	var session := _make_session(map)
	_place(session, TOWN_GATE_WORLD)
	var path: Array[Vector2i] = [TOWN_GATE_WORLD, Vector2i(1, 1)]
	session.player.command = Commands.MoveTo.new(session.player.id, Vector2i(1, 1))
	session.player.path = path
	session.player.path_index = 1

	var result := session.check_world_travel(session.player.id)

	assert_true(result["ok"], str(result))
	assert_null(session.player.command, "the old-chunk move command must be cleared")
	assert_eq(session.player.path.size(), 0, "the old path must be cleared")


func test_arriving_on_the_return_gate_does_not_instantly_travel_back() -> void:
	var map := _make_map()
	var session := _make_session(map)
	_place(session, TOWN_GATE_WORLD)
	session.check_world_travel(session.player.id)
	assert_eq(session.player.tile(), PLAINS_GATE_WORLD)

	# The arrival tile is itself the gate back to town.
	var stayed := session.check_world_travel(session.player.id)

	assert_false(stayed["ok"])
	assert_eq(stayed["reason"], "none", "standing on the arrival gate must not travel")
	assert_eq(session.player.tile(), PLAINS_GATE_WORLD, "the player stays in the plains")


func test_gate_travels_again_once_the_player_steps_off_and_back() -> void:
	var map := _make_map()
	var session := _make_session(map)
	_place(session, TOWN_GATE_WORLD)
	session.check_world_travel(session.player.id)

	_place(session, PLAINS_GATE_WORLD + Vector2i(1, 0))
	var off_gate := session.check_world_travel(session.player.id)
	assert_eq(off_gate["reason"], "none", "a plain tile has no transition")

	_place(session, PLAINS_GATE_WORLD)
	var back := session.check_world_travel(session.player.id)

	assert_true(back["ok"], str(back))
	assert_eq(back["id"], "plains_to_town")
	assert_eq(session.player.tile(), Vector2i(30, 5), "the return gate lands on the town edge")


# --- Locked transitions ---

func test_door_to_a_chunk_travels_like_a_gate() -> void:
	var map := _make_map()
	var session := _make_session(map)
	_place(session, Vector2i(20, 20))

	var result := session.check_world_travel(session.player.id)

	assert_true(result["ok"], str(result))
	assert_eq(result["kind"], "door")
	assert_eq(result["to_chunk"], PLAINS_CHUNK)
	assert_true(session.in_chunked_world(), "a chunk door must not switch zones")
	assert_eq(session.player.tile(), Vector2i(CHUNK_SIZE + 5, 20))


func test_locked_gate_blocks_travel_and_reports_the_boss() -> void:
	var map := _make_map()
	var session := _make_session(map)
	_place(session, LOCKED_GATE)

	var result := session.check_world_travel(session.player.id)

	assert_false(result["ok"])
	assert_eq(result["reason"], "locked")
	assert_eq(result["boss"], "warden")
	assert_eq(result["id"], "locked_gate")
	assert_eq(session.player.tile(), LOCKED_GATE, "a locked gate must not move the player")
	var event := _find_event(session.drain_events(), "world_travel_locked")
	assert_false(event.is_empty(), "a locked gate must emit a HUD message event")
	assert_eq(event.get("boss"), "warden")


func test_locked_gate_does_not_repeat_while_the_player_stands_on_it() -> void:
	var map := _make_map()
	var session := _make_session(map)
	_place(session, LOCKED_GATE)
	session.check_world_travel(session.player.id)
	session.drain_events()

	var stayed := session.check_world_travel(session.player.id)

	assert_eq(stayed["reason"], "none")
	assert_eq(session.drain_events().size(), 0, "standing on a locked gate must not spam messages")


func test_unlocked_gate_travels() -> void:
	var map := _make_map()
	var session := _make_session(map)
	var defeated: Array[String] = ["warden"]
	session.world.set_bosses_defeated(defeated)
	_place(session, LOCKED_GATE)

	var result := session.check_world_travel(session.player.id)

	assert_true(result["ok"], str(result))
	assert_eq(session.player.tile(), Vector2i(CHUNK_SIZE + 10, 10))


# --- Door in and out ---

func test_door_enters_the_dungeon_zone_and_the_return_link_comes_back() -> void:
	var map := _make_map()
	var session := _make_session(map)
	var old_player := session.player
	old_player.hp = 77.0
	session.update_chunks(DOOR_WORLD)
	_place(session, DOOR_WORLD)

	var enter := session.check_world_travel(session.player.id)

	assert_true(enter["ok"], str(enter))
	assert_eq(enter["kind"], "door")
	assert_eq(enter["to_zone"], DUNGEON_STEM)
	assert_true(enter["zone_changed"])
	assert_eq(enter["mode"], "zone")
	assert_false(session.in_chunked_world(), "the session must leave the chunked floor")
	assert_eq(session.zone_id, DUNGEON_STEM)
	assert_eq(session.world.zone, session.zone)
	assert_eq(session.player.tile(), DOOR_SPAWN, "the player spawns at the door's target tile")
	assert_eq(session.player.hp, 77.0, "HP carries across the door")
	assert_ne(session.player, old_player, "the door builds a fresh player entity")

	_place(session, DOOR_RETURN)
	var leave := session.check_world_travel(session.player.id)

	assert_true(leave["ok"], str(leave))
	assert_true(leave["zone_changed"])
	assert_eq(leave["mode"], "chunks")
	assert_true(session.in_chunked_world(), "the session returns to the chunked floor")
	assert_eq(session.zone_id, "floor1")
	assert_eq(session.player.tile(), DOOR_RETURN_WORLD, "the player returns next to the door")
	assert_true(session.world.chunked_world.is_loaded(CENTER_CHUNK), "the center chunk is streamed back in")


func test_door_without_a_zone_loader_keeps_the_player_in_the_world() -> void:
	var map := _make_map()
	var session := _make_session(map)
	session.zone_loader = Callable()
	session.update_chunks(DOOR_WORLD)
	_place(session, DOOR_WORLD)

	var result := session.check_world_travel(session.player.id)

	assert_false(result["ok"])
	assert_eq(result["reason"], "no_zone_loader")
	assert_true(session.in_chunked_world())
	assert_eq(session.player.tile(), DOOR_WORLD)


func test_door_arrival_on_the_return_tile_does_not_leave_immediately() -> void:
	var map := _make_map()
	var session := _make_session(map)
	session.update_chunks(SAME_TILE_DOOR_WORLD)
	_place(session, SAME_TILE_DOOR_WORLD)

	var enter := session.check_world_travel(session.player.id)
	assert_true(enter["ok"], str(enter))
	assert_eq(session.player.tile(), SAME_TILE_SPAWN)

	var stayed := session.check_world_travel(session.player.id)
	assert_eq(stayed["reason"], "none", "the arrival tile must not trigger the return straight away")
	assert_false(session.in_chunked_world())

	_place(session, SAME_TILE_SPAWN + Vector2i(1, 0))
	session.check_world_travel(session.player.id)
	_place(session, SAME_TILE_SPAWN)
	var leave := session.check_world_travel(session.player.id)

	assert_true(leave["ok"], str(leave))
	assert_true(session.in_chunked_world(), "stepping off and back uses the return link")


func test_step_resolves_travel_and_reports_it_once() -> void:
	var map := _make_map()
	var session := _make_session(map)
	_place(session, TOWN_GATE_WORLD)

	session.step(1.0 / 60.0)

	assert_eq(session.player.tile(), PLAINS_GATE_WORLD, "step must resolve the gate travel")
	var travel := session.take_travel()
	assert_eq(travel.get("kind"), "gate")
	assert_eq(travel.get("id"), "town_to_plains")
	assert_true(session.take_travel().is_empty(), "travel is reported once")
