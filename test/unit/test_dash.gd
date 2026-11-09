extends GutTest

const FIXTURE_DIR := "user://test_fixture_dash"

var _registry: DataRegistry = null
var _zone: Zone = null


func before_each() -> void:
	_registry = DataRegistry.new()
	_registry.load_dir("res://data")
	_zone = Zone.load_files("res://data/zones/floor1/test_small.map", "res://data/zones/floor1/test_small.json")
	_clean_dir(FIXTURE_DIR)


func after_each() -> void:
	_clean_dir(FIXTURE_DIR)


func _clean_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(path)
	if dir != null:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while not file_name.is_empty():
			if not dir.current_is_dir():
				DirAccess.remove_absolute(path.path_join(file_name))
			file_name = dir.get_next()
		dir.list_dir_end()
	DirAccess.remove_absolute(path)


func _write_fixture_file(filename: String, content: String) -> void:
	var path := FIXTURE_DIR.path_join(filename)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(content)
		file.close()


func _create_fixture_registry(dash_params: Dictionary, sim_hz: int = 30) -> DataRegistry:
	_clean_dir(FIXTURE_DIR)
	DirAccess.make_dir_recursive_absolute(FIXTURE_DIR)
	var balance_dict: Dictionary = {
		"sim": {"tick_hz": sim_hz},
		"dash": dash_params,
		"player": {
			"move_speed_tiles_per_s": 4.0,
			"max_hp": 100.0,
			"atk": 10.0,
			"defense": 2.0,
			"attack_range": 1.5,
			"attack_interval": 1.0,
			"weapon_damage": 5.0,
			"skills": {
				"Q": "ember_lance",
				"W": "crescent_sweep",
				"R": "mending_gale"
			}
		},
		"enemy": {
			"move_speed_tiles_per_s": 2.0,
			"max_hp": 100.0,
			"atk": 5.0,
			"defense": 0.0,
			"attack_range": 1.0,
			"attack_interval": 1.0,
			"weapon_damage": 0.0
		},
		"combat": {
			"min_damage": 1.0,
			"atk_scale": 1.0,
			"def_scale": 1.0
		}
	}
	_write_fixture_file("balance.json", JSON.stringify(balance_dict))
	var reg := DataRegistry.new()
	reg.load_dir(FIXTURE_DIR)
	return reg


func _find_events(events: Array[Dictionary], type_name: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for ev in events:
		if ev.get("type") == type_name:
			result.append(ev)
	return result


func test_dash_rules_validation() -> void:
	var valid_params := {
		"distance_tiles": 3.0,
		"duration_s": 0.15,
		"cooldown_s": 6.0,
	}
	assert_eq(DashRules.validate_params(valid_params).size(), 0)

	var empty_params: Dictionary = {}
	assert_gt(DashRules.validate_params(empty_params).size(), 0)

	var missing_dist := valid_params.duplicate()
	missing_dist.erase("distance_tiles")
	assert_gt(DashRules.validate_params(missing_dist).size(), 0)

	var zero_dist := valid_params.duplicate()
	zero_dist["distance_tiles"] = 0.0
	assert_gt(DashRules.validate_params(zero_dist).size(), 0)

	var neg_dist := valid_params.duplicate()
	neg_dist["distance_tiles"] = -1.0
	assert_gt(DashRules.validate_params(neg_dist).size(), 0)

	var str_dist := valid_params.duplicate()
	str_dist["distance_tiles"] = "three"
	assert_gt(DashRules.validate_params(str_dist).size(), 0)

	var missing_dur := valid_params.duplicate()
	missing_dur.erase("duration_s")
	assert_gt(DashRules.validate_params(missing_dur).size(), 0)

	var zero_dur := valid_params.duplicate()
	zero_dur["duration_s"] = 0.0
	assert_gt(DashRules.validate_params(zero_dur).size(), 0)

	var neg_dur := valid_params.duplicate()
	neg_dur["duration_s"] = -0.5
	assert_gt(DashRules.validate_params(neg_dur).size(), 0)

	var missing_cd := valid_params.duplicate()
	missing_cd.erase("cooldown_s")
	assert_gt(DashRules.validate_params(missing_cd).size(), 0)

	var neg_cd := valid_params.duplicate()
	neg_cd["cooldown_s"] = -1.0
	assert_gt(DashRules.validate_params(neg_cd).size(), 0)

	# 0.0 cooldown is valid
	var zero_cd := valid_params.duplicate()
	zero_cd["cooldown_s"] = 0.0
	assert_eq(DashRules.validate_params(zero_cd).size(), 0)


func test_distance_and_duration_from_json() -> void:
	# Default balance: distance = 3.0, duration = 0.15 (4.5 ticks -> 5 ticks at 30Hz)
	var sim1 := WorldSim.new(_zone, _registry)
	var player1 := sim1.spawn("player", Vector2i(1, 1), 4.0)
	sim1.submit(Commands.dash(player1.id, Vector2(1.0, 0.0)))
	sim1.step(sim1.tick_length)

	var events1 := sim1.drain_events()
	var dash_events1 := _find_events(events1, "dash")
	assert_eq(dash_events1.size(), 1)
	var ev1: Dictionary = dash_events1[0]
	assert_eq(ev1.get("from"), Vector2(1.5, 1.5))
	assert_eq(ev1.get("to"), Vector2(4.5, 1.5))
	assert_eq(ev1.get("duration_ticks"), 5)

	# Changed balance in fixture registry: distance = 5.0, duration = 0.3 (9 ticks at 30Hz)
	# Use a wider zone without walls between cols 1..7
	var wide_map := """########
#......#
#......#
#......#
########"""
	var wide_json := {
		"entry": [1, 1],
		"legend": {
			"#": {"walkable": false, "type": "wall"},
			".": {"walkable": true, "type": "floor"}
		}
	}
	var wide_zone := Zone.load_from_strings(wide_map, wide_json)
	var custom_reg := _create_fixture_registry({
		"distance_tiles": 5.0,
		"duration_s": 0.3,
		"cooldown_s": 4.0,
	})

	var sim2 := WorldSim.new(wide_zone, custom_reg)
	var player2 := sim2.spawn("player", Vector2i(1, 1), 4.0)
	sim2.submit(Commands.dash(player2.id, Vector2(1.0, 0.0)))
	sim2.step(sim2.tick_length)

	var events2 := sim2.drain_events()
	var dash_events2 := _find_events(events2, "dash")
	assert_eq(dash_events2.size(), 1)
	var ev2: Dictionary = dash_events2[0]
	assert_eq(ev2.get("from"), Vector2(1.5, 1.5))
	assert_eq(ev2.get("to"), Vector2(6.5, 1.5))
	assert_eq(ev2.get("duration_ticks"), 9)
	# Assert end position changed
	assert_ne(ev1.get("to"), ev2.get("to"))
	assert_ne(ev1.get("duration_ticks"), ev2.get("duration_ticks"))


func test_end_position_after_n_ticks() -> void:
	# distance = 3.0, duration = 0.1s -> at 30Hz, exactly 3 ticks (1.0 tile/tick)
	var custom_reg := _create_fixture_registry({
		"distance_tiles": 3.0,
		"duration_s": 0.1,
		"cooldown_s": 5.0,
	}, 30)

	var sim := WorldSim.new(_zone, custom_reg)
	var player := sim.spawn("player", Vector2i(1, 1), 4.0)
	assert_eq(player.pos, Vector2(1.5, 1.5))

	sim.submit(Commands.dash(player.id, Vector2(1.0, 0.0)))

	# Tick 1: moves 1.0 tile to x = 2.5
	sim.step(sim.tick_length)
	assert_almost_eq(player.pos.x, 2.5, 0.01)
	assert_almost_eq(player.pos.y, 1.5, 0.01)
	assert_not_null(player.command)

	# Tick 2: moves 1.0 tile to x = 3.5
	sim.step(sim.tick_length)
	assert_almost_eq(player.pos.x, 3.5, 0.01)
	assert_almost_eq(player.pos.y, 1.5, 0.01)
	assert_not_null(player.command)

	# Tick 3: moves 1.0 tile to x = 4.5, arrives at computed end, command ends
	sim.step(sim.tick_length)
	assert_almost_eq(player.pos.x, 4.5, 0.01)
	assert_almost_eq(player.pos.y, 1.5, 0.01)
	assert_null(player.command, "Command should end on arrival after N ticks")

	# Subsequent step does not move player
	sim.step(sim.tick_length)
	assert_almost_eq(player.pos.x, 4.5, 0.01)


func test_wall_stops_it_and_map_edge() -> void:
	var custom_reg := _create_fixture_registry({
		"distance_tiles": 6.0,
		"duration_s": 0.2,
		"cooldown_s": 5.0,
	})

	var sim := WorldSim.new(_zone, custom_reg)
	var player := sim.spawn("player", Vector2i(1, 1), 4.0)

	# In test_small.map, col 5 is wall '#'. Cols 1..4 are floor.
	# Dash right 6.0 tiles: must stop in col 4 (x <= 4.5, never inside col 5)
	sim.submit(Commands.dash(player.id, Vector2(1.0, 0.0)))
	for i in range(10):
		sim.step(sim.tick_length)

	assert_null(player.command)
	assert_eq(player.tile().x, 4, "Must stop in last walkable tile before wall")
	assert_true(player.tile().x < 5, "Must never enter wall col 5")
	assert_true(_zone.is_walkable(player.tile()), "End tile must be walkable")

	# Test map edge: aim left towards x = 0 (wall) and out-of-bounds (x < 0)
	var player_edge := sim.spawn("player", Vector2i(1, 2), 4.0)
	sim.submit(Commands.dash(player_edge.id, Vector2(-1.0, 0.0)))
	for i in range(10):
		sim.step(sim.tick_length)

	assert_null(player_edge.command)
	assert_eq(player_edge.tile().x, 1, "Must stop at last walkable tile before map boundary")
	assert_true(player_edge.pos.x >= 1.0, "Must never cross into wall or out of bounds")
	assert_true(_zone.is_in_bounds(player_edge.tile()))
	assert_true(_zone.is_walkable(player_edge.tile()))


func test_wall_right_in_front_zero_length_dash() -> void:
	# Player at tile (4, 1), center (4.5, 1.5). Tile (5, 1) is a wall.
	var sim := WorldSim.new(_zone, _registry)
	var player := sim.spawn("player", Vector2i(4, 1), 4.0)
	assert_eq(player.pos, Vector2(4.5, 1.5))

	sim.submit(Commands.dash(player.id, Vector2(1.0, 0.0)))
	sim.step(sim.tick_length)

	var events := sim.drain_events()
	var dash_events := _find_events(events, "dash")
	assert_eq(dash_events.size(), 1, "Dash event should still be emitted")
	var ev: Dictionary = dash_events[0]
	assert_eq(ev.get("from"), Vector2(4.5, 1.5))
	assert_eq(ev.get("to"), Vector2(4.5, 1.5), "to == from when wall right in front")
	assert_eq(player.pos, Vector2(4.5, 1.5))
	assert_null(player.command, "Command ends on same tick when to == from")
	assert_gt(player.dash_ready_tick, float(sim.tick_count), "Cooldown still starts on zero-length dash")


func test_diagonal_aim() -> void:
	# In test_small.map, cols 6..10, rows 1..5 is an open room
	var sim := WorldSim.new(_zone, _registry)
	var player := sim.spawn("player", Vector2i(6, 1), 4.0)
	var from_pos := player.pos # (6.5, 1.5)

	var aim := Vector2(1.0, 1.0)
	var dir := aim.normalized()
	sim.submit(Commands.dash(player.id, aim))

	# Dash distance is 3.0. End pos should be from_pos + dir * 3.0
	var expected_end := from_pos + dir * 3.0
	var computed := DashRules.compute_end_position(from_pos, aim, 3.0, _zone)
	assert_almost_eq(computed.x, expected_end.x, 0.01)
	assert_almost_eq(computed.y, expected_end.y, 0.01)

	for i in range(10):
		sim.step(sim.tick_length)

	assert_null(player.command)
	assert_almost_eq(player.pos.x, expected_end.x, 0.05)
	assert_almost_eq(player.pos.y, expected_end.y, 0.05)
	assert_true(_zone.is_walkable(player.tile()))


func test_cooldown_blocks_second_dash_and_allows_at_exact_boundary() -> void:
	# cooldown = 1.0s, tick_hz = 30 -> exactly 30 ticks
	var custom_reg := _create_fixture_registry({
		"distance_tiles": 1.0,
		"duration_s": 0.05,
		"cooldown_s": 1.0,
	}, 30)

	var sim := WorldSim.new(_zone, custom_reg)
	var player := sim.spawn("player", Vector2i(1, 1), 4.0)

	# Tick 1: initial dash
	sim.submit(Commands.dash(player.id, Vector2(0.0, 1.0)))
	sim.step(sim.tick_length)
	var dash_tick: int = sim.tick_count
	assert_eq(dash_tick, 1)
	var ready_tick := int(round(player.dash_ready_tick))
	assert_eq(ready_tick, 31, "Ready tick should be 1 + 30 = 31")

	# Step until ready_tick - 2 (tick 29, so next submit+step lands on ready_tick - 1 = tick 30)
	while sim.tick_count < ready_tick - 2:
		sim.step(sim.tick_length)
		sim.drain_events()

	assert_eq(sim.tick_count, ready_tick - 2)

	# Recast applied on tick ready_tick - 1 (tick 30): must fail with "cooldown"
	sim.submit(Commands.dash(player.id, Vector2(0.0, 1.0)))
	sim.step(sim.tick_length)
	assert_eq(sim.tick_count, ready_tick - 1)
	var fail_events := _find_events(sim.drain_events(), "dash_failed")
	assert_eq(fail_events.size(), 1, "Dash at tick 30 must fail due to cooldown")
	assert_eq(fail_events[0].get("reason"), "cooldown")

	# Recast applied on exact boundary tick ready_tick (tick 31): must succeed
	sim.submit(Commands.dash(player.id, Vector2(0.0, 1.0)))
	sim.step(sim.tick_length)
	assert_eq(sim.tick_count, ready_tick)
	var success_events := _find_events(sim.drain_events(), "dash")
	assert_eq(success_events.size(), 1, "Dash at tick 31 must succeed at boundary tick")


func test_failed_dash_keeps_walking_moveto_and_mid_cast_running() -> void:
	var sim := WorldSim.new(_zone, _registry)
	var player := sim.spawn("player", Vector2i(1, 1), 4.0)

	# 1. Walking MoveTo
	sim.submit(Commands.move_to(player.id, Vector2i(4, 1)))
	sim.step(sim.tick_length)
	assert_true(player.command is Commands.MoveTo)
	var initial_x := player.pos.x

	# Submit failed dash with zero aim
	sim.submit(Commands.dash(player.id, Vector2.ZERO))
	sim.step(sim.tick_length)

	var fail_events := _find_events(sim.drain_events(), "dash_failed")
	assert_eq(fail_events.size(), 1)
	assert_eq(fail_events[0].get("reason"), "invalid_aim")
	assert_true(player.command is Commands.MoveTo, "MoveTo must remain active after failed dash")
	assert_gt(player.pos.x, initial_x, "Player continues walking")

	# Let player finish walking
	for i in range(30):
		sim.step(sim.tick_length)
	assert_eq(player.tile(), Vector2i(4, 1), "Player arrives at move destination")

	# 2. Mid-cast skill
	var enemy := sim.spawn("enemy", Vector2i(3, 1), 0.0)
	# Cast Q (ember_lance has cast_time_s = 0.1 -> 3 ticks at 30Hz)
	sim.submit(Commands.cast_skill(player.id, "Q", enemy.pos))
	sim.step(sim.tick_length)
	assert_true(player.command is Commands.CastSkill, "Player should be casting")

	# Put player on dash cooldown manually
	player.dash_ready_tick = float(sim.tick_count + 100)
	sim.submit(Commands.dash(player.id, Vector2(1.0, 0.0)))
	sim.step(sim.tick_length)

	var cd_fail_events := _find_events(sim.drain_events(), "dash_failed")
	assert_eq(cd_fail_events.size(), 1)
	assert_eq(cd_fail_events[0].get("reason"), "cooldown")
	assert_true(player.command is Commands.CastSkill, "CastSkill must remain active after failed dash")

	# Step until skill cast resolves
	for i in range(5):
		sim.step(sim.tick_length)

	var cast_events := _find_events(sim.drain_events(), "skill_cast")
	assert_eq(cast_events.size(), 1, "Skill should resolve and emit skill_cast")


func test_successful_dash_cancels_moveto_attacktarget_castskill() -> void:
	var sim := WorldSim.new(_zone, _registry)
	var player := sim.spawn("player", Vector2i(1, 1), 4.0)

	# 1. Cancels MoveTo
	sim.submit(Commands.move_to(player.id, Vector2i(4, 1)))
	sim.step(sim.tick_length)
	assert_true(player.command is Commands.MoveTo)

	# Dash down towards (1, 4)
	sim.submit(Commands.dash(player.id, Vector2(0.0, 1.0)))
	sim.step(sim.tick_length)
	assert_true(player.command is Commands.Dash, "Dash replaced MoveTo")
	assert_eq(player.path.size(), 0, "MoveTo path was cleared")

	for i in range(10):
		sim.step(sim.tick_length)
	assert_eq(player.tile().x, 1, "Player dashed down, not right to (4, 1)")
	assert_gt(player.tile().y, 1)

	# Reset cooldown for next test
	player.dash_ready_tick = 0.0

	# 2. Cancels AttackTarget
	var enemy := sim.spawn("enemy", Vector2i(1, 5), 0.0)
	sim.submit(Commands.attack_target(player.id, enemy.id))
	sim.step(sim.tick_length)
	assert_true(player.command is Commands.AttackTarget)

	# Dash right to escape
	sim.submit(Commands.dash(player.id, Vector2(1.0, 0.0)))
	sim.step(sim.tick_length)
	assert_true(player.command is Commands.Dash, "Dash replaced AttackTarget")

	for i in range(10):
		sim.step(sim.tick_length)

	# Reset cooldown
	player.dash_ready_tick = 0.0

	# 3. Cancels CastSkill
	sim.submit(Commands.cast_skill(player.id, "Q", enemy.pos))
	sim.step(sim.tick_length)
	assert_true(player.command is Commands.CastSkill)

	sim.drain_events()
	sim.submit(Commands.dash(player.id, Vector2(0.0, -1.0)))
	sim.step(sim.tick_length)
	assert_true(player.command is Commands.Dash, "Dash replaced CastSkill")

	for i in range(10):
		sim.step(sim.tick_length)

	var cast_events := _find_events(sim.drain_events(), "skill_cast")
	assert_eq(cast_events.size(), 0, "Canceled CastSkill should never resolve or emit skill_cast")


func test_commands_ignored_mid_dash() -> void:
	# Dash duration = 0.2s -> 6 ticks
	var custom_reg := _create_fixture_registry({
		"distance_tiles": 3.0,
		"duration_s": 0.2,
		"cooldown_s": 5.0,
	})

	var sim := WorldSim.new(_zone, custom_reg)
	var player := sim.spawn("player", Vector2i(1, 1), 4.0)

	sim.submit(Commands.dash(player.id, Vector2(1.0, 0.0)))
	sim.step(sim.tick_length)
	assert_true(player.command is Commands.Dash)
	var orig_cmd := player.command

	# Mid-dash commands submitted: all should be ignored
	var enemy := sim.spawn("enemy", Vector2i(1, 4), 0.0)
	sim.submit(Commands.move_to(player.id, Vector2i(1, 4)))
	sim.submit(Commands.attack_target(player.id, enemy.id))
	sim.submit(Commands.dash(player.id, Vector2(0.0, 1.0)))

	sim.step(sim.tick_length)
	assert_eq(player.command, orig_cmd, "Mid-dash commands must be ignored; original dash command continues")
	assert_eq(player.path.size(), 0, "MoveTo was ignored, path remains empty")

	for i in range(10):
		sim.step(sim.tick_length)

	assert_null(player.command)
	assert_almost_eq(player.pos.x, 4.5, 0.05, "Player arrived at original dash end pos")
	assert_almost_eq(player.pos.y, 1.5, 0.05, "Player did not move down to (1, 4)")


func test_enemy_attack_hits_dashing_player_no_invincibility() -> void:
	# Dashing gives NO invincibility: enemy attack deals damage
	var custom_reg := _create_fixture_registry({
		"distance_tiles": 3.0,
		"duration_s": 0.2,
		"cooldown_s": 5.0,
	})

	var sim := WorldSim.new(_zone, custom_reg)
	var player := sim.spawn("player", Vector2i(1, 1), 4.0, 100.0)
	var enemy := sim.spawn("enemy", Vector2i(2, 1), 0.0, 100.0)

	# Player dashes right past the enemy
	sim.submit(Commands.dash(player.id, Vector2(1.0, 0.0)))
	sim.step(sim.tick_length)
	assert_true(player.command is Commands.Dash)

	# Enemy attacks the player mid-dash
	sim.submit(Commands.attack_target(enemy.id, player.id))
	sim.step(sim.tick_length)

	var damage_events := _find_events(sim.drain_events(), "damage")
	var hit_on_player: Array[Dictionary] = []
	for ev in damage_events:
		if ev.get("target") == player.id:
			hit_on_player.append(ev)

	assert_gt(hit_on_player.size(), 0, "Enemy attack must hit dashing player (no invincibility)")
	assert_lt(player.hp, 100.0, "Player HP must decrease when taking damage mid-dash")


func test_death_mid_dash() -> void:
	var custom_reg := _create_fixture_registry({
		"distance_tiles": 3.0,
		"duration_s": 0.2,
		"cooldown_s": 5.0,
	})

	var sim := WorldSim.new(_zone, custom_reg)
	# Player with low HP (5.0)
	var player := sim.spawn("player", Vector2i(1, 1), 4.0, 5.0)
	var enemy := sim.spawn("enemy", Vector2i(2, 1), 0.0, 100.0)

	sim.submit(Commands.dash(player.id, Vector2(1.0, 0.0)))
	sim.step(sim.tick_length)
	assert_true(player.command is Commands.Dash)

	# Deal lethal damage to player mid-dash
	sim.apply_damage(enemy.id, player, 10.0)
	assert_true(player.dead, "Player should be dead")
	assert_null(player.command, "Dead player must have command cleared safely")

	var death_pos := player.pos
	# Step sim further; dead player should not crash or move
	for i in range(10):
		sim.step(sim.tick_length)

	assert_eq(player.pos, death_pos, "Dead player must not move")
	assert_true(player.dead)


func test_invalid_params_pushes_error_and_dash_failed() -> void:
	var bad_reg := _create_fixture_registry({
		"distance_tiles": -1.0,
		"duration_s": 0.15,
		"cooldown_s": 6.0,
	})

	var sim := WorldSim.new(_zone, bad_reg)
	var player := sim.spawn("player", Vector2i(1, 1), 4.0)

	sim.submit(Commands.dash(player.id, Vector2(1.0, 0.0)))
	sim.step(sim.tick_length)

	assert_push_error_count(1, "Invalid params must trigger push_error")
	var fail_events := _find_events(sim.drain_events(), "dash_failed")
	assert_eq(fail_events.size(), 1)
	assert_eq(fail_events[0].get("reason"), "invalid_params")
	assert_eq(player.dash_ready_tick, 0.0, "State must not change on invalid params")
	assert_null(player.command)


func test_determinism_identical_sims_yield_identical_events() -> void:
	var reg := _create_fixture_registry({
		"distance_tiles": 3.0,
		"duration_s": 0.1,
		"cooldown_s": 2.0,
	})

	var sim1 := WorldSim.new(_zone, reg)
	var sim2 := WorldSim.new(_zone, reg)

	var p1 := sim1.spawn("player", Vector2i(1, 1), 4.0)
	var e1 := sim1.spawn("enemy", Vector2i(3, 1), 2.0)

	var p2 := sim2.spawn("player", Vector2i(1, 1), 4.0)
	var e2 := sim2.spawn("enemy", Vector2i(3, 1), 2.0)

	# Submit identical sequence of actions
	sim1.submit(Commands.move_to(p1.id, Vector2i(2, 1)))
	sim2.submit(Commands.move_to(p2.id, Vector2i(2, 1)))
	for i in range(3):
		sim1.step(sim1.tick_length)
		sim2.step(sim2.tick_length)

	sim1.submit(Commands.dash(p1.id, Vector2(1.0, 0.0)))
	sim2.submit(Commands.dash(p2.id, Vector2(1.0, 0.0)))
	for i in range(5):
		sim1.step(sim1.tick_length)
		sim2.step(sim2.tick_length)

	sim1.submit(Commands.attack_target(e1.id, p1.id))
	sim2.submit(Commands.attack_target(e2.id, p2.id))
	for i in range(10):
		sim1.step(sim1.tick_length)
		sim2.step(sim2.tick_length)

	assert_eq(p1.pos, p2.pos, "Final player positions must be identical")
	assert_eq(e1.pos, e2.pos, "Final enemy positions must be identical")
	assert_eq(p1.hp, p2.hp, "Final player HP must be identical")
	assert_eq(e1.hp, e2.hp, "Final enemy HP must be identical")

	var events1 := sim1.drain_events()
	var events2 := sim2.drain_events()
	assert_eq(events1.size(), events2.size(), "Total event count must be identical")
	for i in range(events1.size()):
		assert_eq(events1[i], events2[i], "Event %d must be identical" % i)


func test_dash_aim_semantics_nan_inf_and_normalized() -> void:
	var sim := WorldSim.new(_zone, _registry)
	var player := sim.spawn("player", Vector2i(1, 1), 4.0)

	# 1. Non-finite aims must fail with invalid_aim
	var non_finite_aims: Array[Vector2] = [
		Vector2(NAN, 1.0),
		Vector2(1.0, NAN),
		Vector2(NAN, NAN),
		Vector2(INF, 0.0),
		Vector2(0.0, -INF),
		Vector2(INF, INF),
		Vector2(-INF, -INF),
	]

	for bad_aim in non_finite_aims:
		sim.submit(Commands.dash(player.id, bad_aim))
		sim.step(sim.tick_length)
		var fail_events := _find_events(sim.drain_events(), "dash_failed")
		assert_eq(fail_events.size(), 1, "Non-finite aim %s must emit dash_failed" % str(bad_aim))
		if not fail_events.is_empty():
			assert_eq(fail_events[0].get("reason"), "invalid_aim")
		assert_null(player.command, "Command must be null after invalid aim")

		# Also test compute_end_position directly returns from
		var end_computed := DashRules.compute_end_position(player.pos, bad_aim, 3.0, _zone)
		assert_eq(end_computed, player.pos, "compute_end_position must return from for non-finite aim %s" % str(bad_aim))

	# 2. Valid non-unit aim: normalized by sim, aim is a direction
	var unnormalized_aim := Vector2(10.0, 0.0)
	sim.submit(Commands.dash(player.id, unnormalized_aim))
	sim.step(sim.tick_length)

	var dash_cmd := player.command as Commands.Dash
	assert_not_null(dash_cmd, "Dash command should be active")
	assert_almost_eq(dash_cmd.aim.x, 1.0, 0.0001, "cmd.aim must be normalized direction")
	assert_almost_eq(dash_cmd.aim.y, 0.0, 0.0001)
	assert_almost_eq(dash_cmd.aim.length(), 1.0, 0.0001)


func test_dash_duration_ticks_free_and_wall_shortened() -> void:
	# 1. Free dash (nominal distance = 3.0, duration = 0.15s, 30Hz)
	# At 30Hz: 0.15s / (1/30) = 4.5 -> duration_ticks is 5.
	# Open map without obstacles between col 1 and 6.
	var open_map := """########
#......#
#......#
########"""
	var open_json := {
		"entry": [1, 1],
		"legend": {
			"#": {"walkable": false, "type": "wall"},
			".": {"walkable": true, "type": "floor"}
		}
	}
	var open_zone := Zone.load_from_strings(open_map, open_json)
	var reg := _create_fixture_registry({
		"distance_tiles": 3.0,
		"duration_s": 0.15,
		"cooldown_s": 0.0,
	}, 30)

	var sim_free := WorldSim.new(open_zone, reg)
	var player_free := sim_free.spawn("player", Vector2i(1, 1), 4.0)

	sim_free.submit(Commands.dash(player_free.id, Vector2(1.0, 0.0)))
	sim_free.step(sim_free.tick_length)

	var free_events := _find_events(sim_free.drain_events(), "dash")
	assert_eq(free_events.size(), 1)
	var free_event_ticks: int = int(free_events[0].get("duration_ticks", 0))

	# Count ticks until command clears (including tick 1 already stepped)
	var elapsed_free_ticks := 1
	while player_free.command != null and elapsed_free_ticks < 20:
		sim_free.step(sim_free.tick_length)
		elapsed_free_ticks += 1

	assert_null(player_free.command, "Free dash should have completed")
	assert_eq(free_event_ticks, elapsed_free_ticks, "Free dash event duration_ticks (%d) must equal ticks until command clears (%d)" % [free_event_ticks, elapsed_free_ticks])
	assert_eq(free_event_ticks, 5, "Free dash nominal duration_ticks should be 5")

	# 2. Wall-shortened dash:
	# Wall at col 3 (distance is 1.0 tile from col 1 center to col 2 center, wall at col 3).
	# Nominal speed = 3.0 / 0.15 = 20 tiles/s. At 30Hz, step = 20 * (1/30) = 0.6667 tiles/tick.
	# Distance = 1.0 tile -> tick 1: 0.6667, tick 2: 0.3333 -> exactly 2 ticks.
	var wall_map := """######
#..###
#..###
######"""
	var wall_json := {
		"entry": [1, 1],
		"legend": {
			"#": {"walkable": false, "type": "wall"},
			".": {"walkable": true, "type": "floor"}
		}
	}
	var wall_zone := Zone.load_from_strings(wall_map, wall_json)
	var sim_wall := WorldSim.new(wall_zone, reg)
	var player_wall := sim_wall.spawn("player", Vector2i(1, 1), 4.0)

	sim_wall.submit(Commands.dash(player_wall.id, Vector2(1.0, 0.0)))
	sim_wall.step(sim_wall.tick_length)

	var wall_events := _find_events(sim_wall.drain_events(), "dash")
	assert_eq(wall_events.size(), 1)
	var wall_event_ticks: int = int(wall_events[0].get("duration_ticks", 0))

	var elapsed_wall_ticks := 1
	while player_wall.command != null and elapsed_wall_ticks < 20:
		sim_wall.step(sim_wall.tick_length)
		elapsed_wall_ticks += 1

	assert_null(player_wall.command, "Wall dash should have completed")
	assert_eq(wall_event_ticks, elapsed_wall_ticks, "Wall-shortened dash event duration_ticks (%d) must equal ticks until command clears (%d)" % [wall_event_ticks, elapsed_wall_ticks])
	assert_eq(wall_event_ticks, 2, "Wall-shortened dash duration_ticks should be 2")
	assert_eq(player_wall.tile().x, 2, "Player should stop in col 2 before wall at col 3")

	# 3. Wall right in front (0.0 real distance)
	var player_zero := sim_wall.spawn("player", Vector2i(2, 1), 4.0)
	sim_wall.submit(Commands.dash(player_zero.id, Vector2(1.0, 0.0)))
	sim_wall.step(sim_wall.tick_length)

	var zero_events := _find_events(sim_wall.drain_events(), "dash")
	assert_eq(zero_events.size(), 1)
	var zero_event_ticks: int = int(zero_events[0].get("duration_ticks", 0))
	assert_null(player_zero.command, "Command must clear on tick 1 when wall right in front")
	assert_eq(zero_event_ticks, 1, "Zero-length dash event duration_ticks must be 1")


func test_dash_diagonal_corner_tunnelling_blocked() -> void:
	# Map layout:
	# row 0: ####
	# row 1: #.##   (1, 1) is floor, (2, 1) is WALL
	# row 2: #..#   (1, 2) is floor, (2, 2) is floor
	# row 3: ####
	# Diagonal move between (1, 1) and (2, 2): shared neighbour (2, 1) is blocked!
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

	# 1. DashRules.compute_end_position must stop before cutting the corner
	var start_pos := Vector2(1.5, 1.5) # center of (1, 1)
	var aim := Vector2(1.0, 1.0)
	var end_pos := DashRules.compute_end_position(start_pos, aim, 3.0, corner_zone)

	assert_lt(end_pos.x, 2.0, "End position x must not cross into col 2")
	assert_lt(end_pos.y, 2.0, "End position y must not cross into row 2")
	var end_tile := Vector2i(int(floor(end_pos.x)), int(floor(end_pos.y)))
	assert_eq(end_tile, Vector2i(1, 1), "End tile must remain (1, 1)")

	# 2. Simulation execution of dash must not cut through wall corner
	var reg := _create_fixture_registry({
		"distance_tiles": 3.0,
		"duration_s": 0.15,
		"cooldown_s": 0.0,
	})
	var sim := WorldSim.new(corner_zone, reg)
	var player := sim.spawn("player", Vector2i(1, 1), 4.0)

	sim.submit(Commands.dash(player.id, aim))
	for i in range(10):
		sim.step(sim.tick_length)

	assert_null(player.command, "Dash command should complete")
	assert_eq(player.tile(), Vector2i(1, 1), "Player must remain in tile (1, 1) and not cut corner into (2, 2)")
	assert_lt(player.pos.x, 2.0)
	assert_lt(player.pos.y, 2.0)

	# 3. Open ground diagonal move past walkable neighbours is unchanged
	var open_corner_map := """####
#..#
#..#
####"""
	var open_corner_zone := Zone.load_from_strings(open_corner_map, corner_json)
	var open_end := DashRules.compute_end_position(start_pos, aim, 1.0, open_corner_zone)
	# On open ground, moving 1.0 tile diagonally from (1.5, 1.5) reaches into (2, 2)
	assert_gt(open_end.x, 2.0, "On open ground, diagonal dash must cross into tile (2, 2)")
	assert_gt(open_end.y, 2.0, "On open ground, diagonal dash must cross into tile (2, 2)")

