extends GutTest

var _registry: DataRegistry = null
var _zone: Zone = null


func before_each() -> void:
	_registry = DataRegistry.new()
	_registry.load_dir("res://data")
	_zone = Zone.load_files("res://data/zones/floor1/test_small.map", "res://data/zones/floor1/test_small.json")


func test_enemy_config_loaded_from_real_data() -> void:
	assert_true(_registry.has_entry("enemies", "ash_stalker"), "enemies.json should contain 'ash_stalker'")
	var cfg := _registry.get_entry("enemies", "ash_stalker")
	assert_gt(float(cfg.get("aggro_radius", 0.0)), 0.0)
	assert_gt(float(cfg.get("leash_radius", 0.0)), float(cfg.get("aggro_radius", 0.0)))
	assert_gt(float(cfg.get("move_speed_tiles_per_s", 0.0)), 0.0)
	assert_gt(float(cfg.get("windup_s", 0.0)), 0.0)
	assert_gt(float(cfg.get("active_s", 0.0)), 0.0)
	assert_gt(float(cfg.get("recovery_s", 0.0)), 0.0)

	var attack: Dictionary = cfg.get("attack", {})
	assert_eq(attack.get("shape"), "cone")
	assert_gt(float(attack.get("range", 0.0)), 0.0)
	assert_gt(float(attack.get("angle_deg", 0.0)), 0.0)
	assert_gt(float(attack.get("damage_mult", 0.0)), 0.0)

	var sim := WorldSim.new(_zone, _registry)
	var enemy := sim.spawn_enemy("ash_stalker", Vector2i(2, 2))
	assert_not_null(enemy)
	assert_eq(enemy.kind, "enemy")
	assert_eq(enemy.enemy_type_id, "ash_stalker")
	assert_eq(enemy.state, "idle")
	assert_eq(enemy.spawn_pos, WorldSim.tile_center(Vector2i(2, 2)))
	assert_eq(enemy.speed, float(cfg.get("move_speed_tiles_per_s")))
	assert_eq(enemy.recovery_damage_mult, float(cfg.get("recovery_damage_mult", 1.0)))


func test_player_outside_locked_area_takes_no_damage_inside_takes_damage() -> void:
	# Criterion 1: Player outside the locked area at active takes no damage; inside takes damage.
	var sim := WorldSim.new(_zone, _registry)
	var player_stats := Stats.new(100.0, 10.0, 2.0, 1.5, 1.0, 5.0)

	var enemy := sim.spawn_enemy("ash_stalker", Vector2i(2, 2))
	# Player 1 inside attack cone (directly to the right, dist 2.0 < range 2.5)
	var player_inside := sim.spawn("player", Vector2i(4, 2), 0.0, 100.0, player_stats)
	# Player 2 outside attack cone (below enemy, outside 90-degree cone pointing right)
	var player_outside := sim.spawn("player", Vector2i(2, 4), 0.0, 100.0, player_stats)

	var p1_start_hp := player_inside.hp
	var p2_start_hp := player_outside.hp

	# Step until enemy enters windup (aims at nearest player inside)
	sim.step(sim.tick_length)
	assert_eq(enemy.state, "windup")

	# Advance sim past windup duration to reach 'active'
	var cfg := _registry.get_entry("enemies", "ash_stalker")
	var windup_ticks := int(round(float(cfg.get("windup_s")) / sim.tick_length))

	for _i in range(windup_ticks - 1):
		sim.step(sim.tick_length)

	# Next tick transitions to active and triggers the attack once
	sim.step(sim.tick_length)
	assert_eq(enemy.state, "active")

	# Base combat formula: (atk + weapon) * atk_scale - def * def_scale
	# Ash stalker kind is 'enemy' -> balance.json has atk=5, weapon=0. def=2 on player.
	# base_dmg = 5.0 - 2.0 = 3.0. mult = 1.5. Expected dmg = 4.5.
	var enemy_stats := sim.effective_stats(enemy)
	var p1_stats := sim.effective_stats(player_inside)
	var base_dmg := Combat.compute_damage(enemy_stats, p1_stats, _registry)
	var mult: float = float(cfg.get("attack", {}).get("damage_mult", 1.0))
	var expected_dmg := mult * base_dmg

	assert_almost_eq(player_inside.hp, p1_start_hp - expected_dmg, 0.001, "Player inside locked area must take damage")
	assert_almost_eq(player_outside.hp, p2_start_hp, 0.001, "Player outside locked area must take no damage")


func test_durations_match_json_values_in_ticks_and_state_changes() -> void:
	# Criterion 2: Windup/active/recovery durations match the JSON values in ticks (assert state-change ticks).
	var sim := WorldSim.new(_zone, _registry)
	var enemy := sim.spawn_enemy("ash_stalker", Vector2i(2, 2))
	# Player at (3, 2), inside attack range 2.5 (dist 1.0)
	var _player := sim.spawn("player", Vector2i(3, 2), 0.0, 100.0)

	var cfg := _registry.get_entry("enemies", "ash_stalker")
	var windup_ticks := int(round(float(cfg.get("windup_s")) / sim.tick_length))
	var active_ticks := int(round(float(cfg.get("active_s")) / sim.tick_length))
	var recovery_ticks := int(round(float(cfg.get("recovery_s")) / sim.tick_length))

	assert_gt(windup_ticks, 0)
	assert_gt(active_ticks, 0)
	assert_gt(recovery_ticks, 0)

	# Step 1: starts windup
	sim.step(sim.tick_length)
	var windup_start_tick := sim.tick_count
	assert_eq(enemy.state, "windup")
	assert_eq(enemy.state_end_tick, windup_start_tick + windup_ticks)

	# Check each tick in windup
	for _i in range(windup_ticks - 1):
		sim.step(sim.tick_length)
		assert_eq(enemy.state, "windup", "Should remain in windup until duration completes")

	# Next tick should change state to active
	sim.step(sim.tick_length)
	var active_start_tick := sim.tick_count
	assert_eq(enemy.state, "active")
	assert_eq(active_start_tick - windup_start_tick, windup_ticks, "Windup duration in ticks must match JSON")
	assert_eq(enemy.state_end_tick, active_start_tick + active_ticks)

	# Check each tick in active
	for _i in range(active_ticks - 1):
		sim.step(sim.tick_length)
		assert_eq(enemy.state, "active", "Should remain in active until duration completes")

	# Next tick should change state to recovery
	sim.step(sim.tick_length)
	var recovery_start_tick := sim.tick_count
	assert_eq(enemy.state, "recovery")
	assert_eq(recovery_start_tick - active_start_tick, active_ticks, "Active duration in ticks must match JSON")
	assert_eq(enemy.state_end_tick, recovery_start_tick + recovery_ticks)

	# Check each tick in recovery
	for _i in range(recovery_ticks - 1):
		sim.step(sim.tick_length)
		assert_eq(enemy.state, "recovery", "Should remain in recovery until duration completes")

	# Next tick should change state to chase
	sim.step(sim.tick_length)
	var chase_start_tick := sim.tick_count
	assert_eq(enemy.state, "chase")
	assert_eq(chase_start_tick - recovery_start_tick, recovery_ticks, "Recovery duration in ticks must match JSON")


func test_area_locked_at_windup_start_player_moving_does_not_reaim_and_telegraph_event() -> void:
	# Criterion 3: Area locked at windup start (player moving during windup doesn't re-aim it); telegraph_start has shape and duration.
	var sim := WorldSim.new(_zone, _registry)
	var enemy := sim.spawn_enemy("ash_stalker", Vector2i(2, 2))
	# Player starts at (4, 2), directly right of enemy (dir = (1, 0))
	var player := sim.spawn("player", Vector2i(4, 2), 4.0, 100.0)

	sim.step(sim.tick_length)
	assert_eq(enemy.state, "windup")

	# Check telegraph_start event
	var events := sim.drain_events()
	var telegraph_found := false
	for ev in events:
		if ev.get("type") == "telegraph_start":
			telegraph_found = true
			assert_eq(ev.get("source"), enemy.id)
			assert_eq(ev.get("shape"), "cone")
			assert_almost_eq(float(ev.get("duration")), 0.5, 0.001)
			assert_eq(ev.get("origin"), enemy.pos)
			assert_true((ev.get("dir") as Vector2).is_equal_approx(Vector2.RIGHT))
			assert_almost_eq(float(ev.get("range")), 2.5, 0.001)
			assert_almost_eq(float(ev.get("angle_deg")), 90.0, 0.001)
			break
	assert_true(telegraph_found, "sim should emit 'telegraph_start' with shape and duration")

	var locked_origin: Vector2 = enemy.locked_origin
	var locked_dir: Vector2 = enemy.locked_dir
	assert_true(locked_dir.is_equal_approx(Vector2.RIGHT), "Locked dir should aim toward player at windup start")

	# Move player during windup to (2, 4) (directly below enemy)
	player.pos = WorldSim.tile_center(Vector2i(2, 4))

	# Advance remaining windup ticks
	var cfg := _registry.get_entry("enemies", "ash_stalker")
	var windup_ticks := int(round(float(cfg.get("windup_s")) / sim.tick_length))
	for _i in range(windup_ticks - 1):
		sim.step(sim.tick_length)
		# Verify locked area never changes while player moves
		assert_eq(enemy.locked_origin, locked_origin)
		assert_eq(enemy.locked_dir, locked_dir)

	# Transition to active
	sim.step(sim.tick_length)
	assert_eq(enemy.state, "active")

	# Player moved outside the locked cone pointing right, so player takes 0 damage
	assert_eq(player.hp, 100.0, "Player that moved outside locked area should take no damage")


func test_leash_and_reset_returns_to_spawn_and_idles() -> void:
	# Criterion 4: Leash/reset: enemy returns to spawn and idles when the player is far.
	var sim := WorldSim.new(_zone, _registry)
	var spawn_tile := Vector2i(2, 2)
	var enemy := sim.spawn_enemy("ash_stalker", spawn_tile)
	var cfg := _registry.get_entry("enemies", "ash_stalker")
	var leash_radius := float(cfg.get("leash_radius"))

	# Place player at (4, 5): distance sqrt(4+9) ~ 3.61 > attack range 2.5 and <= aggro 5.0
	var player := sim.spawn("player", Vector2i(4, 5), 0.0, 100.0)

	# Step sim: enemy spots player and enters chase
	sim.step(sim.tick_length)
	assert_eq(enemy.state, "chase")

	# Move player far away beyond leash_radius from spawn
	player.pos = Vector2(2.5 + leash_radius + 2.0, 2.5)

	# Step sim: enemy detects player beyond leash, drops target and walks back to spawn
	sim.step(sim.tick_length)
	assert_true(enemy.state in ["reset", "idle"])

	# Advance sim until enemy reaches spawn tile
	var max_ticks := 100
	var arrived := false
	for _i in range(max_ticks):
		sim.step(sim.tick_length)
		if enemy.state == "idle" and enemy.tile() == spawn_tile:
			arrived = true
			break

	assert_true(arrived, "Enemy should return to spawn tile and enter idle state")
	assert_eq(enemy.state, "idle")
	assert_eq(enemy.tile(), spawn_tile)
	assert_true(enemy.pos.is_equal_approx(enemy.spawn_pos))


func test_enemy_ignores_dead_player_and_chase_starts_only_inside_aggro() -> void:
	# Criterion 5: Enemy ignores a dead player; chase starts only inside the aggro radius.
	var sim := WorldSim.new(_zone, _registry)
	var enemy := sim.spawn_enemy("ash_stalker", Vector2i(2, 2))
	var cfg := _registry.get_entry("enemies", "ash_stalker")
	var aggro_radius := float(cfg.get("aggro_radius", 5.0))

	# Part A: Dead player inside aggro radius is ignored
	var dead_player := sim.spawn("player", Vector2i(3, 2), 0.0, 0.0)
	assert_true(dead_player.dead)

	sim.step(sim.tick_length)
	sim.step(sim.tick_length)
	assert_eq(enemy.state, "idle", "Enemy should ignore dead player inside aggro radius")

	# Part B: Living player outside aggro radius is ignored
	# Enemy spawn at (2.5, 2.5); place player beyond aggro_radius (e.g. dist 6.0)
	var live_player := sim.spawn("player", Vector2i(8, 2), 0.0, 100.0)
	live_player.pos = Vector2(2.5 + aggro_radius + 1.0, 2.5)

	sim.step(sim.tick_length)
	sim.step(sim.tick_length)
	assert_eq(enemy.state, "idle", "Enemy should remain idle when player is outside aggro radius")

	# Part C: Move player inside aggro radius -> chase starts
	live_player.pos = Vector2(2.5 + aggro_radius - 0.5, 2.5)

	sim.step(sim.tick_length)
	assert_eq(enemy.state, "chase", "Enemy should enter chase when player moves inside aggro radius")


func test_recovery_damage_mult_amplifies_damage_only_during_recovery() -> void:
	var sim := WorldSim.new(_zone, _registry)
	var enemy := sim.spawn_enemy("ash_stalker", Vector2i(2, 2))
	var player := sim.spawn("player", Vector2i(3, 2), 0.0, 100.0)

	var cfg := _registry.get_entry("enemies", "ash_stalker")
	var rec_mult := float(cfg.get("recovery_damage_mult", 1.5))
	assert_eq(enemy.recovery_damage_mult, rec_mult)

	# Damage enemy while idle -> normal damage (1.0 mult)
	var start_hp := enemy.hp
	sim.apply_damage(player.id, enemy, 10.0)
	assert_almost_eq(enemy.hp, start_hp - 10.0, 0.001, "Normal damage outside recovery")

	# Advance enemy into recovery
	var windup_ticks := int(round(float(cfg.get("windup_s")) / sim.tick_length))
	var active_ticks := int(round(float(cfg.get("active_s")) / sim.tick_length))
	for _i in range(1 + windup_ticks + active_ticks):
		sim.step(sim.tick_length)

	assert_eq(enemy.state, "recovery")

	# Damage enemy during recovery -> damage multiplied by recovery_damage_mult
	var rec_start_hp := enemy.hp
	sim.apply_damage(player.id, enemy, 10.0)
	assert_almost_eq(enemy.hp, rec_start_hp - (10.0 * rec_mult), 0.001, "Damage in recovery must be multiplied")


func test_dead_enemy_does_not_act_or_deal_damage() -> void:
	var sim := WorldSim.new(_zone, _registry)
	var enemy := sim.spawn_enemy("ash_stalker", Vector2i(2, 2))
	var player := sim.spawn("player", Vector2i(3, 2), 0.0, 100.0)

	# Step into windup
	sim.step(sim.tick_length)
	assert_eq(enemy.state, "windup")

	# Kill the enemy during windup
	enemy.hp = 0.0
	enemy.dead = true

	# Advance past windup ticks to active
	var cfg := _registry.get_entry("enemies", "ash_stalker")
	var windup_ticks := int(round(float(cfg.get("windup_s")) / sim.tick_length))
	for _i in range(windup_ticks + 5):
		sim.step(sim.tick_length)

	# Player took no damage because dead enemy did not act
	assert_eq(player.hp, 100.0, "Dead enemy must not deal damage at active")


func test_player_death_mid_chase_triggers_leash_and_reset_to_spawn() -> void:
	var sim := WorldSim.new(_zone, _registry)
	var spawn_tile := Vector2i(2, 2)
	var enemy := sim.spawn_enemy("ash_stalker", spawn_tile)
	var player := sim.spawn("player", Vector2i(4, 5), 0.0, 100.0)

	# Enter chase
	sim.step(sim.tick_length)
	assert_eq(enemy.state, "chase")

	# Player dies mid-chase
	player.hp = 0.0
	player.dead = true

	# Next tick enemy realizes target is dead, begins reset
	sim.step(sim.tick_length)
	assert_true(enemy.state in ["reset", "idle"])

	# Step until back at spawn
	var arrived := false
	for _i in range(100):
		sim.step(sim.tick_length)
		if enemy.state == "idle" and enemy.tile() == spawn_tile:
			arrived = true
			break

	assert_true(arrived, "Enemy should return to spawn when target player dies")
	assert_eq(enemy.state, "idle")


func test_chase_paths_around_walls() -> void:
	# In test_small.map, there is a wall at x=5 from y=1 to y=6, with a gap at y=7
	var sim := WorldSim.new(_zone, _registry)
	# Enemy at (3, 5), player at (7, 5): dist = 4.0 (> attack range 2.5 and <= aggro 5.0)
	var enemy := sim.spawn_enemy("ash_stalker", Vector2i(3, 5))
	var player := sim.spawn("player", Vector2i(7, 5), 0.0, 100.0)

	# Enemy spots player
	sim.step(sim.tick_length)
	assert_eq(enemy.state, "chase")
	assert_gt(enemy.path.size(), 0, "Enemy should calculate path around the wall")
	# Path must go through gap at y=7 (tile (5, 7) has comma gap in map)
	var goes_through_gap := false
	for p in enemy.path:
		if p.y == 6 or p.y == 7: # row 7 is index 6/7
			goes_through_gap = true
			break
	assert_true(goes_through_gap, "Path should route through bottom gap")


func test_deterministic_target_selection_with_multiple_players() -> void:
	var sim := WorldSim.new(_zone, _registry)
	var enemy := sim.spawn_enemy("ash_stalker", Vector2i(2, 3))

	# Spawn two players at identical distance from enemy
	var p1 := sim.spawn("player", Vector2i(2, 1), 0.0, 100.0) # dist = 2.0
	var p2 := sim.spawn("player", Vector2i(2, 5), 0.0, 100.0) # dist = 2.0

	assert_lt(p1.id, p2.id)

	# Both are at exact same distance 2.0. Iteration order sorts by ID, so p1 is chosen.
	sim.step(sim.tick_length)
	assert_eq(enemy.target_id, p1.id, "Target selection must tie-break deterministically to lower ID")


func test_line_and_circle_attack_shapes() -> void:
	var sim := WorldSim.new(_zone, _registry)
	var enemy := sim.spawn_enemy("ash_stalker", Vector2i(2, 2))

	# Test custom line attack
	var line_attack: Dictionary = {
		"shape": "line",
		"range": 4.0,
		"width": 1.0,
		"damage_mult": 2.0,
	}
	var player_in_line := sim.spawn("player", Vector2i(4, 2), 0.0, 100.0)
	var player_off_line := sim.spawn("player", Vector2i(4, 4), 0.0, 100.0)

	EnemyAI._start_windup(sim, enemy, player_in_line, line_attack, 0.2, 6)
	assert_eq(enemy.state, "windup")

	# Step to active
	for _i in range(6):
		sim.step(sim.tick_length)

	assert_eq(enemy.state, "active")
	EnemyAI._perform_attack(sim, enemy, {}, line_attack)

	assert_lt(player_in_line.hp, 100.0, "Player in line should take damage")
	assert_eq(player_off_line.hp, 100.0, "Player outside line should take no damage")


func test_spawn_enemy_unknown_type_id_pushes_error_and_refuses_spawn() -> void:
	var sim := WorldSim.new(_zone, _registry)
	var enemy := sim.spawn_enemy("nonexistent_enemy", Vector2i(2, 2))
	assert_push_error_count(1, "Should push error when enemy type is unknown")
	assert_null(enemy, "spawn_enemy with unknown type_id should return null")


func test_enemy_ai_validate_config_and_update_rejection() -> void:
	var errors := EnemyAI.validate_config({})
	assert_gt(errors.size(), 0, "Empty config should produce errors")

	var bad_config := {
		"name": "Bad Mob",
		"aggro_radius": -1.0,
		"leash_radius": 2.0,
		"windup_s": 0.5,
		"active_s": 0.2,
		"recovery_s": 0.5,
		"attack": {
			"shape": "unknown_shape",
			"range": 0.0,
		}
	}
	errors = EnemyAI.validate_config(bad_config)
	assert_gt(errors.size(), 0, "Bad config should produce errors")

	# Enemy with unknown type id skips AI update
	var sim := WorldSim.new(_zone, _registry)
	var dummy := sim.spawn("enemy", Vector2i(2, 2), 2.0, 100.0)
	dummy.enemy_type_id = "nonexistent_type"
	dummy.state = "idle"
	EnemyAI.update(sim, dummy)
	assert_push_error_count(1, "Should push error when AI updates with unknown type id")
	assert_eq(dummy.state, "idle", "AI should not run on entity with invalid/unknown type id")


func test_leash_walk_back_to_spawn_over_several_tiles() -> void:
	var sim := WorldSim.new(_zone, _registry)
	var spawn_tile := Vector2i(2, 1)
	var enemy := sim.spawn_enemy("ash_stalker", spawn_tile)
	assert_not_null(enemy)
	var player := sim.spawn("player", Vector2i(2, 5), 0.0, 100.0)

	# Place enemy several tiles away from spawn in chase state
	enemy.state = "chase"
	enemy.target_id = player.id
	enemy.pos = WorldSim.tile_center(Vector2i(2, 5)) # 4 tiles away from spawn pos (2.5, 1.5)

	# Move player far beyond leash radius (> 8.0 tiles from enemy.spawn_pos)
	var cfg := _registry.get_entry("enemies", "ash_stalker")
	var leash_radius := float(cfg.get("leash_radius"))
	player.pos = Vector2(2.5, 1.5 + leash_radius + 5.0)

	var prev_dist := enemy.pos.distance_to(enemy.spawn_pos)
	assert_almost_eq(prev_dist, 4.0, 0.01)

	var reset_tick_count := 0
	var arrived := false
	var max_ticks := 100

	for _i in range(max_ticks):
		sim.step(sim.tick_length)
		if enemy.state == "reset":
			reset_tick_count += 1
			var curr_dist := enemy.pos.distance_to(enemy.spawn_pos)
			assert_lt(curr_dist, prev_dist, "Enemy in reset state should move closer to spawn each tick")
			prev_dist = curr_dist
		elif enemy.state == "idle":
			arrived = true
			break

	assert_gt(reset_tick_count, 10, "Enemy should spend several ticks walking back in reset state")
	assert_true(arrived, "Enemy should arrive at spawn and transition to idle within bounded ticks")
	assert_eq(enemy.state, "idle")
	assert_eq(enemy.tile(), spawn_tile)
	assert_true(enemy.pos.is_equal_approx(enemy.spawn_pos))
