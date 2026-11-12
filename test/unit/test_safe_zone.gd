extends GutTest

# Columns 5-7 are a full-height safe band (plaza) splitting the corridor.
const MAP := "#############\n#....SSS....#\n#....SSS....#\n#....SSS....#\n#############\n"
const LEGEND := {
	"#": {"type": "wall", "walkable": false},
	".": {"type": "floor", "walkable": true},
	"S": {"type": "plaza", "walkable": true, "safe": true}
}

var _registry: DataRegistry = null
var _zone: Zone = null


func before_each() -> void:
	_registry = DataRegistry.new()
	_registry.load_dir("res://data")
	_zone = Zone.load_from_strings(MAP, {"legend": LEGEND, "entry": [1, 2]})
	assert_true(_zone.is_valid(), str(_zone.errors))


func _player(sim: WorldSim, t: Vector2i) -> Entity:
	return sim.spawn("player", t, 0.0, 100.0, Stats.new(100.0, 10.0, 2.0, 1.5, 1.0, 5.0))


func test_player_on_safe_tile_does_not_draw_aggro() -> void:
	var sim := WorldSim.new(_zone, _registry)
	var enemy := sim.spawn_enemy("ash_stalker", Vector2i(2, 2))
	_player(sim, Vector2i(5, 2)) # safe, dist 3 < aggro radius
	for _i in range(30):
		sim.step(sim.tick_length)
		assert_eq(enemy.state, "idle")
		assert_eq(enemy.target_id, 0)
	assert_eq(enemy.tile(), Vector2i(2, 2))


func test_aggro_dropped_when_target_steps_onto_safe_tile() -> void:
	var sim := WorldSim.new(_zone, _registry)
	var enemy := sim.spawn_enemy("ash_stalker", Vector2i(1, 2))
	var player := _player(sim, Vector2i(4, 2)) # dist 3: aggro but out of attack range
	sim.step(sim.tick_length)
	assert_eq(enemy.state, "chase")
	assert_eq(enemy.target_id, player.id)

	player.pos = WorldSim.tile_center(Vector2i(5, 2))
	sim.step(sim.tick_length)
	assert_eq(enemy.target_id, 0, "target on safe tile is dropped")
	assert_true(enemy.state == "reset" or enemy.state == "idle", "enemy goes home, got %s" % enemy.state)

	for _i in range(120):
		sim.step(sim.tick_length)
		assert_false(_zone.is_safe(enemy.tile()))
	assert_eq(enemy.state, "idle")
	assert_eq(enemy.pos, enemy.spawn_pos)


func test_enemy_never_enters_safe_tiles_chasing_target_beyond_them() -> void:
	var sim := WorldSim.new(_zone, _registry)
	var enemy := sim.spawn_enemy("ash_stalker", Vector2i(3, 2))
	var player := _player(sim, Vector2i(8, 2)) # just outside the band, dist 5 = aggro
	var start_hp := player.hp
	var chased := false
	for _i in range(300):
		sim.step(sim.tick_length)
		if enemy.state == "chase":
			chased = true
		assert_false(_zone.is_safe(enemy.tile()), "enemy on safe tile %s" % str(enemy.tile()))
		assert_true(enemy.pos.x < 5.0, "enemy crossed into the safe band at %s" % str(enemy.pos))
	assert_true(chased, "enemy did aggro the target")
	assert_almost_eq(player.hp, start_hp, 0.001, "target across the band never takes damage")


func test_enemy_spawned_on_safe_tile_may_leave_it() -> void:
	var sim := WorldSim.new(_zone, _registry)
	var enemy := sim.spawn_enemy("ash_stalker", Vector2i(5, 2))
	_player(sim, Vector2i(1, 2)) # dist 4, outside attack range
	sim.step(sim.tick_length)
	assert_eq(enemy.state, "chase")
	var left := false
	for _i in range(60):
		sim.step(sim.tick_length)
		if not _zone.is_safe(enemy.tile()):
			left = true
			break
	assert_true(left, "enemy walked off its safe spawn tile")


func test_zone_without_safe_tiles_keeps_chasing() -> void:
	var zone := Zone.load_from_strings(MAP.replace("S", "."), {"legend": LEGEND, "entry": [1, 2]})
	var sim := WorldSim.new(zone, _registry)
	var enemy := sim.spawn_enemy("ash_stalker", Vector2i(3, 2))
	var player := _player(sim, Vector2i(8, 2))
	sim.step(sim.tick_length)
	assert_eq(enemy.state, "chase")
	assert_eq(enemy.target_id, player.id)
	for _i in range(60):
		sim.step(sim.tick_length)
	assert_gt(enemy.pos.x, 5.0, "enemy crosses the former band")


func test_null_zone_aggro_unchanged() -> void:
	var sim := WorldSim.new(null, _registry)
	var enemy := sim.spawn_enemy("ash_stalker", Vector2i(2, 2))
	var player := _player(sim, Vector2i(5, 2))
	sim.step(sim.tick_length)
	assert_eq(enemy.target_id, player.id)
	assert_ne(enemy.state, "idle")
