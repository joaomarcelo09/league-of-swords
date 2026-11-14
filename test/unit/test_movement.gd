extends GutTest

var _registry: DataRegistry = null
var _zone: Zone = null
var _player_speed: float = 0.0


func before_each() -> void:
	_registry = DataRegistry.new()
	_registry.load_dir("res://data")
	_zone = Zone.load_files("res://data/zones/floor1/test_small.map", "res://data/zones/floor1/test_small.json")
	var speed_val: Variant = _registry.get_balance("player.move_speed_tiles_per_s")
	_player_speed = float(speed_val) if speed_val != null else 4.0


func test_entity_init_and_tile_helper() -> void:
	var entity := Entity.new(1, "player", Vector2(1.5, 2.7), 4.0, 100.0)
	assert_eq(entity.id, 1)
	assert_eq(entity.kind, "player")
	assert_eq(entity.pos, Vector2(1.5, 2.7))
	assert_eq(entity.speed, 4.0)
	assert_eq(entity.hp, 100.0)
	assert_eq(entity.tile(), Vector2i(1, 2))
	assert_eq(entity.path.size(), 0)
	assert_eq(entity.path_index, 0)
	assert_null(entity.command)


func test_sim_spawn_and_get_entity() -> void:
	var sim := WorldSim.new(_zone, _registry)
	var e1 := sim.spawn("player", Vector2i(1, 1), _player_speed)
	var e2 := sim.spawn("enemy", Vector2i(2, 2), 2.0)

	assert_eq(e1.id, 1)
	assert_eq(e2.id, 2)
	assert_eq(e1.pos, Vector2(1.5, 1.5))
	assert_eq(e2.pos, Vector2(2.5, 2.5))
	assert_eq(e1.speed, _player_speed)
	assert_eq(sim.get_entity(1), e1)
	assert_eq(sim.get_entity(2), e2)
	assert_null(sim.get_entity(99))
	assert_eq(sim.entities.size(), 2)


func test_reaches_straight_line_target_in_expected_ticks() -> void:
	# Acceptance criterion 1:
	# Entity reaches a straight-line target in expected ticks ±1 (expected = ceil(path_len / (speed*tick_length)))
	var sim := WorldSim.new(_zone, _registry)
	var start_tile := Vector2i(1, 1)
	var target_tile := Vector2i(4, 1)
	var entity := sim.spawn("player", start_tile, _player_speed)

	var path_len := float((target_tile.x - start_tile.x)) # 3.0 tiles
	var tick_length := sim.tick_length
	var expected_ticks := int(ceil(path_len / (_player_speed * tick_length)))

	sim.submit(Commands.move_to(entity.id, target_tile))

	var ticks := 0
	while ticks < expected_ticks + 5:
		sim.step(tick_length)
		ticks += 1
		if entity.command == null:
			break

	assert_null(entity.command, "Command should be cleared upon reaching target")
	assert_almost_eq(entity.pos.x, 4.5, 0.001)
	assert_almost_eq(entity.pos.y, 1.5, 0.001)
	assert_eq(entity.tile(), target_tile)
	assert_true(
		abs(ticks - expected_ticks) <= 1,
		"Expected %d ticks ±1, actual was %d" % [expected_ticks, ticks]
	)


func test_path_avoids_walls_and_goes_through_gap() -> void:
	# Acceptance criterion 2:
	# Path avoids walls: never stands on a non-walkable tile at any tick; goes through the wall gap.
	var sim := WorldSim.new(_zone, _registry)
	var start_tile := Vector2i(1, 1)
	var target_tile := Vector2i(8, 3)
	var entity := sim.spawn("player", start_tile, _player_speed)

	sim.submit(Commands.move_to(entity.id, target_tile))

	var visited_gap := false
	var prev_pos := entity.pos
	var ticks := 0
	while ticks < 250:
		sim.step(sim.tick_length)
		ticks += 1
		var cur_tile := entity.tile()
		assert_true(
			_zone.is_walkable(cur_tile),
			"Entity must never stand on unwalkable tile. Stood on %s at tick %d (pos=%s)" % [str(cur_tile), ticks, str(entity.pos)]
		)
		# Free movement: any angle is allowed, but each tick's motion must stay on walkable tiles.
		assert_true(
			DashRules.is_segment_walkable(prev_pos, entity.pos, _zone),
			"Tick %d motion %s -> %s must not cross unwalkable tiles" % [ticks, str(prev_pos), str(entity.pos)]
		)
		prev_pos = entity.pos

		if cur_tile == Vector2i(5, 6):
			visited_gap = true
		if entity.command == null:
			break

	assert_null(entity.command, "Entity should finish MoveTo")
	assert_eq(entity.tile(), target_tile)
	assert_almost_eq(entity.pos.x, 8.5, 0.001)
	assert_almost_eq(entity.pos.y, 3.5, 0.001)
	assert_true(visited_gap, "Entity must pass through the gap at (5, 6) to cross the wall")


func test_unreachable_target_ends_on_nearest_reachable() -> void:
	# Acceptance criterion 3:
	# Unreachable/non-walkable target: entity ends on zone.nearest_reachable tile.
	var sim := WorldSim.new(_zone, _registry)
	var start_tile := Vector2i(1, 1)
	# (5, 3) is a solid wall
	var wall_target := Vector2i(5, 3)
	assert_false(_zone.is_walkable(wall_target), "(5, 3) should be unwalkable wall")

	var expected_tile := _zone.nearest_reachable(start_tile, wall_target)
	assert_true(expected_tile != Vector2i(-1, -1), "Should have reachable nearest tile")
	assert_true(_zone.is_walkable(expected_tile), "Nearest reachable tile must be walkable")

	var entity := sim.spawn("player", start_tile, _player_speed)
	sim.submit(Commands.move_to(entity.id, wall_target))

	var ticks := 0
	while ticks < 200:
		sim.step(sim.tick_length)
		ticks += 1
		if entity.command == null:
			break

	assert_null(entity.command, "Command should clear after reaching nearest reachable tile")
	assert_eq(entity.tile(), expected_tile)
	assert_almost_eq(entity.pos.x, float(expected_tile.x) + 0.5, 0.001)
	assert_almost_eq(entity.pos.y, float(expected_tile.y) + 0.5, 0.001)


func test_mid_walk_new_command_replaces_old() -> void:
	# Acceptance criterion 4:
	# A new MoveTo mid-walk replaces the old one (ends at the new target, not the old).
	var sim := WorldSim.new(_zone, _registry)
	var start_tile := Vector2i(1, 1)
	var target1 := Vector2i(1, 6) # Walking south
	var target2 := Vector2i(4, 1) # Turning to walk east
	var entity := sim.spawn("player", start_tile, _player_speed)

	sim.submit(Commands.move_to(entity.id, target1))

	# Run 5 ticks to get entity mid-walk along first path
	for i in range(5):
		sim.step(sim.tick_length)

	assert_not_null(entity.command)
	assert_true(entity.pos.y > 1.5, "Entity should have moved south")
	assert_true(entity.pos.y < 6.5, "Entity should not have reached target1")

	# Replace with new command
	sim.submit(Commands.move_to(entity.id, target2))

	var ticks := 0
	while ticks < 200:
		sim.step(sim.tick_length)
		ticks += 1
		if entity.command == null:
			break

	assert_null(entity.command, "Replaced command should complete")
	assert_eq(entity.tile(), target2, "Entity must end on target2, not target1")
	assert_almost_eq(entity.pos.x, 4.5, 0.001)
	assert_almost_eq(entity.pos.y, 1.5, 0.001)


func test_step_dt_smaller_and_larger_yields_same_result() -> void:
	# Acceptance criterion 5:
	# step with dt smaller/larger than the tick length still yields the same result per elapsed time.
	var sim_ref := WorldSim.new(_zone, _registry)
	var sim_small := WorldSim.new(_zone, _registry)
	var sim_large := WorldSim.new(_zone, _registry)

	var start := Vector2i(1, 1)
	var target := Vector2i(8, 3)

	var e_ref := sim_ref.spawn("player", start, _player_speed)
	var e_small := sim_small.spawn("player", start, _player_speed)
	var e_large := sim_large.spawn("player", start, _player_speed)

	sim_ref.submit(Commands.move_to(e_ref.id, target))
	sim_small.submit(Commands.move_to(e_small.id, target))
	sim_large.submit(Commands.move_to(e_large.id, target))

	var tick_length := sim_ref.tick_length

	# Reference: 30 ticks of tick_length (1.0 s)
	for i in range(30):
		sim_ref.step(tick_length)

	# Small dt: 120 steps of tick_length / 4.0 (1.0 s)
	for i in range(120):
		sim_small.step(tick_length * 0.25)

	# Large dt: 12 steps of tick_length * 2.5 (1.0 s)
	for i in range(12):
		sim_large.step(tick_length * 2.5)

	assert_eq(sim_ref.tick_count, 30)
	assert_eq(sim_small.tick_count, 30)
	assert_eq(sim_large.tick_count, 30)

	assert_almost_eq(e_small.pos.x, e_ref.pos.x, 0.0001)
	assert_almost_eq(e_small.pos.y, e_ref.pos.y, 0.0001)
	assert_almost_eq(e_large.pos.x, e_ref.pos.x, 0.0001)
	assert_almost_eq(e_large.pos.y, e_ref.pos.y, 0.0001)


func test_determinism_identical_sims_yield_identical_positions() -> void:
	# Acceptance criterion 6:
	# Determinism: two sims with same inputs end in identical positions.
	var sim1 := WorldSim.new(_zone, _registry)
	var sim2 := WorldSim.new(_zone, _registry)

	var e1 := sim1.spawn("player", Vector2i(1, 1), _player_speed)
	var e2 := sim2.spawn("player", Vector2i(1, 1), _player_speed)

	sim1.submit(Commands.move_to(e1.id, Vector2i(10, 6)))
	sim2.submit(Commands.move_to(e2.id, Vector2i(10, 6)))

	var dt_sequence: Array[float] = [0.016, 0.03333333, 0.05, 0.01, 0.04, 0.025]
	for round_idx in range(15):
		for dt in dt_sequence:
			sim1.step(dt)
			sim2.step(dt)
			assert_eq(sim1.tick_count, sim2.tick_count)
			assert_eq(e1.pos, e2.pos)
			assert_eq(e1.tile(), e2.tile())
			assert_eq(e1.path_index, e2.path_index)

	# Let both finish to destination
	while e1.command != null:
		sim1.step(sim1.tick_length)
		sim2.step(sim2.tick_length)

	assert_eq(e1.pos, e2.pos)
	assert_almost_eq(e1.pos.x, 10.5, 0.001)
	assert_almost_eq(e1.pos.y, 6.5, 0.001)


func test_move_to_same_tile_clears_command_immediately() -> void:
	var sim := WorldSim.new(_zone, _registry)
	var entity := sim.spawn("player", Vector2i(1, 1), _player_speed)
	sim.submit(Commands.move_to(entity.id, Vector2i(1, 1)))

	sim.step(sim.tick_length)
	assert_null(entity.command, "Command should clear immediately when target is already current tile")
	assert_almost_eq(entity.pos.x, 1.5, 0.001)
	assert_almost_eq(entity.pos.y, 1.5, 0.001)


func test_latest_queued_command_in_same_tick_replaces_earlier() -> void:
	var sim := WorldSim.new(_zone, _registry)
	var entity := sim.spawn("player", Vector2i(1, 1), _player_speed)

	# Submit two commands in the same tick interval
	sim.submit(Commands.move_to(entity.id, Vector2i(1, 6)))
	sim.submit(Commands.move_to(entity.id, Vector2i(4, 1)))

	sim.step(sim.tick_length)
	# After 1 tick, the entity should be heading towards (4, 1), not (1, 6)
	assert_not_null(entity.command)
	var move_cmd := entity.command as Commands.MoveTo
	assert_eq(move_cmd.target, Vector2i(4, 1))
	assert_true(entity.pos.x > 1.5)
	assert_almost_eq(entity.pos.y, 1.5, 0.001)


func test_diagonal_corner_tunnelling_blocked_in_path_stepping() -> void:
	# Map where (1, 1) is floor, (2, 1) is wall, (1, 2) is floor, (2, 2) is floor
	var corner_map := """####
#.##
#..#
####"""
	var corner_json := {
		"entry": [1, 1],
		"legend": {
			"#": {"walkable": false, "type": "wall"},
			".": {"walkable": true, "type": "floor"}
		}
	}
	var corner_zone := Zone.load_from_strings(corner_map, corner_json)
	var sim := WorldSim.new(corner_zone, _registry)
	var entity := sim.spawn("player", Vector2i(1, 1), _player_speed)
	assert_eq(entity.pos, Vector2(1.5, 1.5))

	# Assign a diagonal path waypoint to (2, 2) whose shared neighbour (2, 1) is blocked
	var move_cmd := Commands.move_to(entity.id, Vector2i(2, 2))
	entity.command = move_cmd
	entity.path = [Vector2i(2, 2)]
	entity.path_index = 0

	# Step sim: path stepping must detect the wall corner and abort the move
	sim.step(sim.tick_length)

	assert_null(entity.command, "Command must be cleared when diagonal path waypoint cuts wall corner")
	assert_eq(entity.path.size(), 0, "Path must be cleared")
	assert_eq(entity.tile(), Vector2i(1, 1), "Entity must remain in tile (1, 1)")
	assert_lt(entity.pos.x, 2.0, "Entity pos.x must not enter col 2")
	assert_lt(entity.pos.y, 2.0, "Entity pos.y must not enter row 2")

	# On open ground, diagonal stepping succeeds
	var open_map := """####
#..#
#..#
####"""
	var open_zone := Zone.load_from_strings(open_map, corner_json)
	var sim_open := WorldSim.new(open_zone, _registry)
	var entity_open := sim_open.spawn("player", Vector2i(1, 1), _player_speed)

	var move_cmd_open := Commands.move_to(entity_open.id, Vector2i(2, 2))
	entity_open.command = move_cmd_open
	entity_open.path = [Vector2i(2, 2)]
	entity_open.path_index = 0

	for i in range(20):
		sim_open.step(sim_open.tick_length)
		if entity_open.command == null:
			break

	assert_null(entity_open.command)
	assert_eq(entity_open.tile(), Vector2i(2, 2), "On open ground, entity reaches target tile (2, 2)")
	assert_almost_eq(entity_open.pos.x, 2.5, 0.01)
	assert_almost_eq(entity_open.pos.y, 2.5, 0.01)


func test_spawn_rejects_wall_and_out_of_bounds_tiles() -> void:
	var sim := WorldSim.new(_zone, _registry)

	# 1. Border wall tile (0, 0)
	var wall_player := sim.spawn("player", Vector2i(0, 0), _player_speed)
	assert_null(wall_player, "spawn on border wall tile must return null")
	assert_push_error_count(1, "spawn on border wall must push error")

	# 2. Interior wall tile (5, 2)
	var interior_wall_player := sim.spawn("player", Vector2i(5, 2), _player_speed)
	assert_null(interior_wall_player, "spawn on interior wall tile must return null")
	assert_push_error_count(2, "spawn on interior wall must push error")

	# 3. Interior wall float coordinate Vector2(5.2, 2.8)
	var interior_float_player := sim.spawn("player", Vector2(5.2, 2.8), _player_speed)
	assert_null(interior_float_player, "spawn on interior wall float must return null")
	assert_push_error_count(3, "spawn on interior wall float must push error")

	# 4. Negative out of bounds (-1, 0)
	var oob_player := sim.spawn("player", Vector2i(-1, 0), _player_speed)
	assert_null(oob_player, "spawn out of bounds must return null")
	assert_push_error_count(4, "spawn out of bounds must push error")

	# 5. Positive out of bounds (99, 99)
	var oob_player2 := sim.spawn("player", Vector2i(99, 99), _player_speed)
	assert_null(oob_player2, "spawn out of bounds must return null")
	assert_push_error_count(5, "spawn out of bounds must push error")

	# 6. Invalid coordinate type (String)
	var invalid_coord := sim.spawn("player", "not_a_vector", _player_speed)
	assert_null(invalid_coord, "spawn with invalid coord type must return null")
	assert_push_error_count(6, "spawn with invalid coord must push error")

	# 7. Walkable tile succeeds
	var ok_player := sim.spawn("player", Vector2i(1, 1), _player_speed)
	assert_not_null(ok_player, "spawn on walkable tile must succeed")
	assert_eq(ok_player.tile(), Vector2i(1, 1))
	assert_eq(ok_player.pos, Vector2(1.5, 1.5))

