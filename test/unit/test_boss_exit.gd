extends GutTest

# Corridor: entry at (1,2), boss spawn at (6,2), exit at (10,2), open exit at (10,1).
const MAP := "############\n#..........#\n#..........#\n#..........#\n############\n"
const LEGEND := {
	"#": {"type": "wall", "walkable": false},
	".": {"type": "floor", "walkable": true},
}
const BOSS_ID := "test_warden"
const LOCKED_EXIT := Vector2i(10, 2)
const OPEN_EXIT := Vector2i(10, 1)

var _registry: DataRegistry = null
var _zone: Zone = null


func before_each() -> void:
	_registry = DataRegistry.new()
	_registry.load_dir("res://data")
	_zone = Zone.load_from_strings(MAP, {
		"legend": LEGEND,
		"entry": [1, 2],
		"spawns": [
			{"id": "grunt_a", "enemy": "ash_stalker", "tile": [3, 1]},
			{"id": BOSS_ID, "enemy": "thornback_warden", "tile": [6, 2], "boss": true},
		],
		"exits": [
			{"tile": [10, 2], "to_zone": "floor2", "label": "Stairs", "requires_boss": BOSS_ID},
			{"tile": [10, 1], "to_zone": "floor2", "label": "Side door"},
		],
	})
	assert_true(_zone.is_valid(), str(_zone.errors))


func _player(sim: WorldSim, t: Vector2i) -> Entity:
	return sim.spawn("player", t, 0.0, 100.0, Stats.new(100.0, 10.0, 2.0, 1.5, 1.0, 5.0))


func _events_of(events: Array[Dictionary], type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for ev: Dictionary in events:
		if ev.get("type") == type:
			out.append(ev)
	return out


func _boss(spawned: Array[Entity]) -> Entity:
	for e: Entity in spawned:
		if e.is_boss:
			return e
	return null


func test_spawned_entities_remember_spawn_id_and_boss_flag() -> void:
	var sim := WorldSim.new(_zone, _registry)
	var spawned := sim.spawn_zone_enemies()
	assert_eq(spawned.size(), 2)
	assert_eq(spawned[0].spawn_id, "grunt_a")
	assert_false(spawned[0].is_boss)
	assert_eq(spawned[1].spawn_id, BOSS_ID)
	assert_true(spawned[1].is_boss)


func test_locked_exit_emits_exit_locked_and_no_floor_cleared() -> void:
	var sim := WorldSim.new(_zone, _registry)
	var player := _player(sim, LOCKED_EXIT)
	var ev := sim.check_exit(player.id)
	assert_eq(ev.get("type"), "exit_locked")
	var events := sim.drain_events()
	var locked := _events_of(events, "exit_locked")
	assert_eq(locked.size(), 1)
	assert_eq(locked[0]["boss"], BOSS_ID)
	assert_eq(locked[0]["tile"], LOCKED_EXIT)
	assert_eq(locked[0]["label"], "Stairs")
	assert_eq(_events_of(events, "floor_cleared").size(), 0)


func test_boss_kill_emits_boss_defeated_once_and_records() -> void:
	var sim := WorldSim.new(_zone, _registry)
	var boss := _boss(sim.spawn_zone_enemies())
	assert_not_null(boss)
	sim.apply_damage(0, boss, boss.hp + 1000.0)
	sim.apply_damage(0, boss, 1000.0) # already dead: no-op
	var events := sim.drain_events()
	var defeated := _events_of(events, "boss_defeated")
	assert_eq(defeated.size(), 1)
	assert_eq(defeated[0]["boss"], BOSS_ID)
	assert_eq(defeated[0]["entity"], boss.id)
	assert_eq(defeated[0]["enemy_type"], "thornback_warden")
	assert_eq(_events_of(events, "death").size(), 1, "death event still emitted")
	assert_eq(sim.bosses_defeated, [BOSS_ID] as Array[String])
	assert_true(sim.is_boss_defeated(BOSS_ID))


func test_non_boss_kill_records_nothing() -> void:
	var sim := WorldSim.new(_zone, _registry)
	var grunt := sim.spawn_zone_enemies()[0]
	sim.apply_damage(0, grunt, grunt.hp + 1000.0)
	assert_eq(_events_of(sim.drain_events(), "boss_defeated").size(), 0)
	assert_true(sim.bosses_defeated.is_empty())


func test_unlocked_exit_after_boss_kill_emits_floor_cleared() -> void:
	var sim := WorldSim.new(_zone, _registry)
	var boss := _boss(sim.spawn_zone_enemies())
	sim.apply_damage(0, boss, boss.hp + 1000.0)
	sim.drain_events()
	var player := _player(sim, LOCKED_EXIT)
	sim.check_exit(player.id)
	var events := sim.drain_events()
	var cleared := _events_of(events, "floor_cleared")
	assert_eq(cleared.size(), 1)
	assert_eq(cleared[0]["to_zone"], "floor2")
	assert_eq(cleared[0]["label"], "Stairs")
	assert_eq(cleared[0]["tile"], LOCKED_EXIT)
	assert_eq(_events_of(events, "exit_locked").size(), 0)


func test_exit_without_requirement_is_open() -> void:
	var sim := WorldSim.new(_zone, _registry)
	var player := _player(sim, OPEN_EXIT)
	assert_eq(sim.check_exit(player.id).get("type"), "floor_cleared")


func test_staying_on_exit_tile_does_not_repeat_and_reentry_does() -> void:
	var sim := WorldSim.new(_zone, _registry)
	var player := _player(sim, LOCKED_EXIT)
	for _i in range(10):
		sim.step(sim.tick_length)
	assert_eq(_events_of(sim.drain_events(), "exit_locked").size(), 1, "per-tick check emits once")

	player.pos = WorldSim.tile_center(Vector2i(9, 2))
	sim.step(sim.tick_length)
	assert_eq(_events_of(sim.drain_events(), "exit_locked").size(), 0)

	player.pos = WorldSim.tile_center(LOCKED_EXIT)
	sim.step(sim.tick_length)
	sim.step(sim.tick_length)
	assert_eq(_events_of(sim.drain_events(), "exit_locked").size(), 1, "re-entry emits again")


func test_off_exit_returns_empty() -> void:
	var sim := WorldSim.new(_zone, _registry)
	var player := _player(sim, Vector2i(2, 2))
	assert_true(sim.check_exit(player.id).is_empty())
	assert_true(sim.drain_events().is_empty())


func test_spawn_zone_enemies_skips_defeated_boss() -> void:
	var sim := WorldSim.new(_zone, _registry)
	var defeated: Array[String] = [BOSS_ID]
	sim.set_bosses_defeated(defeated)
	var spawned := sim.spawn_zone_enemies()
	assert_eq(spawned.size(), 1)
	assert_eq(spawned[0].spawn_id, "grunt_a")
	assert_null(_boss(spawned))


func test_world_state_round_trip_keeps_boss_dead() -> void:
	var item_db := ItemDB.new(_registry)
	var ws := WorldState.new()
	ws.inventory = Inventory.new(item_db)

	var sim := WorldSim.new(_zone, _registry)
	sim.set_bosses_defeated(ws.bosses_defeated)
	var boss := _boss(sim.spawn_zone_enemies())
	sim.apply_damage(0, boss, boss.hp + 1000.0)
	assert_eq(ws.bosses_defeated, [BOSS_ID] as Array[String], "kill recorded into shared WorldState list")

	var loaded := WorldState.from_dict(ws.to_dict(), item_db)
	assert_not_null(loaded, WorldState.last_error)
	assert_eq(loaded.bosses_defeated, [BOSS_ID] as Array[String])

	var sim2 := WorldSim.new(_zone, _registry)
	sim2.set_bosses_defeated(loaded.bosses_defeated)
	assert_null(_boss(sim2.spawn_zone_enemies()), "boss stays dead after load")
	var player := _player(sim2, LOCKED_EXIT)
	assert_eq(sim2.check_exit(player.id).get("type"), "floor_cleared")


func test_floor1_exit_requires_warden() -> void:
	var floor1 := Zone.load_files("res://data/zones/floor1/floor1.map", "res://data/zones/floor1/floor1.json")
	assert_true(floor1.is_valid(), str(floor1.errors))
	var sim := WorldSim.new(floor1, _registry)
	var exit_tile: Vector2i = WorldSim.parse_tile_coord(floor1.exits[0]["tile"])
	var player := _player(sim, exit_tile)
	assert_eq(sim.check_exit(player.id).get("type"), "exit_locked")
	var warden: Entity = null
	for e: Entity in sim.spawn_zone_enemies():
		if e.spawn_id == "floor1_warden":
			warden = e
	assert_not_null(warden)
	assert_true(warden.is_boss)
