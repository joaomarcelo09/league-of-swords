extends GutTest

var _registry: DataRegistry = null
var _zone: Zone = null


func before_each() -> void:
	_registry = DataRegistry.new()
	_registry.load_dir("res://data")
	_zone = Zone.load_files("res://data/zones/floor1/test_small.map", "res://data/zones/floor1/test_small.json")


func test_stats_creation_and_from_dict() -> void:
	var dict: Dictionary = {
		"max_hp": 120.0,
		"atk": 15.0,
		"defense": 3.0,
		"attack_range": 1.5,
		"attack_interval": 0.8,
		"weapon_damage": 7.0,
	}
	var s := Stats.from_dict(dict)
	assert_eq(s.max_hp, 120.0)
	assert_eq(s.atk, 15.0)
	assert_eq(s.defense, 3.0)
	assert_eq(s.attack_range, 1.5)
	assert_eq(s.attack_interval, 0.8)
	assert_eq(s.weapon_damage, 7.0)

	var dup := s.duplicate()
	assert_eq(dup.max_hp, 120.0)
	assert_eq(dup.weapon_damage, 7.0)


func test_target_out_of_range_approaches_and_hits_on_expected_arrival() -> void:
	# Acceptance criterion 1:
	# Target out of range: attacker approaches, then hits; first hit tick matches expected arrival.
	var sim := WorldSim.new(_zone, _registry)
	var attacker_stats := Stats.new(100.0, 10.0, 2.0, 1.0, 1.0, 5.0)
	var target_stats := Stats.new(500.0, 0.0, 0.0, 1.0, 1.0, 0.0)

	var attacker_speed := 4.0
	var attacker := sim.spawn("player", Vector2i(1, 1), attacker_speed, 100.0, attacker_stats)
	var target := sim.spawn("enemy", Vector2i(4, 1), 0.0, 500.0, target_stats)

	var tick_len := sim.tick_length
	var start_pos := attacker.pos # (1.5, 1.5)
	var target_pos := target.pos # (4.5, 1.5)
	var total_dist := start_pos.distance_to(target_pos) # 3.0
	var dist_to_travel := total_dist - attacker_stats.attack_range # 2.0
	var expected_ticks := int(ceil(dist_to_travel / (attacker_speed * tick_len))) # 15 ticks

	sim.submit(Commands.attack_target(attacker.id, target.id))

	# Advance until 1 tick before expected arrival
	for tick in range(expected_ticks - 1):
		sim.step(tick_len)
		assert_eq(sim.events.size(), 0, "No damage events before arrival at tick %d" % (tick + 1))

	# Step the arrival tick
	sim.step(tick_len)
	assert_eq(sim.tick_count, expected_ticks)
	assert_eq(sim.events.size(), 1, "Should emit first hit immediately upon arrival")

	var ev: Dictionary = sim.events[0]
	assert_eq(ev.get("type"), "damage")
	assert_eq(ev.get("tick"), expected_ticks, "First hit tick should match expected arrival tick")
	assert_eq(ev.get("source"), attacker.id)
	assert_eq(ev.get("target"), target.id)
	assert_gt(ev.get("amount"), 0.0)

	assert_almost_eq(attacker.pos.x, 3.5, 0.001)
	assert_almost_eq(attacker.pos.y, 1.5, 0.001)


func test_damage_formula_and_floor() -> void:
	# Acceptance criterion 2:
	# Damage equals the formula from balance.json (test with two different stat sets; min damage floor).
	# Formula: max(min_damage, (atk + weapon_damage) * atk_scale - defense * def_scale)
	var stats_atk1 := Stats.new(100.0, 12.0, 0.0, 1.5, 1.0, 8.0) # (12 + 8) = 20
	var stats_def1 := Stats.new(100.0, 0.0, 4.0, 1.5, 1.0, 0.0) # 4 * 1 = 4 -> dmg 16
	var dmg1 := Combat.compute_damage(stats_atk1, stats_def1, _registry)
	assert_eq(dmg1, 16.0, "Stat set 1 damage: (12 + 8) * 1 - 4 * 1 = 16")

	var stats_atk2 := Stats.new(100.0, 25.0, 0.0, 1.5, 1.0, 15.0) # (25 + 15) = 40
	var stats_def2 := Stats.new(100.0, 0.0, 15.0, 1.5, 1.0, 0.0) # 15 * 1 = 15 -> dmg 25
	var dmg2 := Combat.compute_damage(stats_atk2, stats_def2, _registry)
	assert_eq(dmg2, 25.0, "Stat set 2 damage: (25 + 15) * 1 - 15 * 1 = 25")

	# Min damage floor
	var stats_weak_atk := Stats.new(100.0, 1.0, 0.0, 1.5, 1.0, 0.0) # 1
	var stats_high_def := Stats.new(100.0, 0.0, 50.0, 1.5, 1.0, 0.0) # 50
	var dmg_floor := Combat.compute_damage(stats_weak_atk, stats_high_def, _registry)
	var min_damage: float = float(_registry.get_balance("combat.min_damage"))
	assert_eq(dmg_floor, min_damage, "Floor damage should match combat.min_damage (1.0)")

	# Verify in simulation
	var sim := WorldSim.new(_zone, _registry)
	var attacker := sim.spawn("player", Vector2i(1, 1), 4.0, 100.0, stats_atk1)
	var target := sim.spawn("enemy", Vector2i(2, 1), 0.0, 100.0, stats_def1)

	sim.submit(Commands.attack_target(attacker.id, target.id))
	sim.step(sim.tick_length)

	var events := sim.drain_events()
	assert_eq(events.size(), 1)
	assert_eq(events[0].get("amount"), 16.0)
	assert_almost_eq(target.hp, 84.0, 0.001)


func test_hits_repeat_every_attack_interval() -> void:
	# Acceptance criterion 3:
	# Hits repeat every attack_interval (ticks ±1); no cooldown/mana involved.
	var sim := WorldSim.new(_zone, _registry)
	var interval_s := 0.5
	var attacker_stats := Stats.new(100.0, 10.0, 0.0, 1.5, interval_s, 5.0)
	var target_stats := Stats.new(1000.0, 0.0, 0.0, 1.5, 1.0, 0.0)

	var attacker := sim.spawn("player", Vector2i(1, 1), 4.0, 100.0, attacker_stats)
	var target := sim.spawn("enemy", Vector2i(2, 1), 0.0, 1000.0, target_stats)

	sim.submit(Commands.attack_target(attacker.id, target.id))

	var hit_ticks: Array[int] = []
	var expected_ticks_interval := int(round(interval_s / sim.tick_length)) # 15 ticks at 30hz

	for tick in range(60):
		sim.step(sim.tick_length)
		var drained := sim.drain_events()
		for ev in drained:
			if ev.get("type") == "damage":
				hit_ticks.append(ev.get("tick"))

	assert_eq(hit_ticks.size(), 4, "Should have 4 hits in 60 ticks with 0.5s interval (30hz)")
	assert_eq(hit_ticks[0], 1, "First hit immediately on arrival (tick 1)")

	for i in range(1, hit_ticks.size()):
		var diff := hit_ticks[i] - hit_ticks[i - 1]
		assert_true(
			abs(diff - expected_ticks_interval) <= 1,
			"Hit interval should be %d ±1 ticks, got %d" % [expected_ticks_interval, diff]
		)


func test_target_death_emits_one_death_event_and_stops_attacker() -> void:
	# Acceptance criterion 4:
	# Target death emits one death event, stops the attacker's command, and no further damage events.
	var sim := WorldSim.new(_zone, _registry)
	var attacker_stats := Stats.new(100.0, 25.0, 0.0, 1.5, 1.0, 0.0) # 25 damage per hit
	var target_stats := Stats.new(20.0, 0.0, 0.0, 1.5, 1.0, 0.0) # 20 hp

	var attacker := sim.spawn("player", Vector2i(1, 1), 4.0, 100.0, attacker_stats)
	var target := sim.spawn("enemy", Vector2i(2, 1), 0.0, 20.0, target_stats)

	sim.submit(Commands.attack_target(attacker.id, target.id))

	# First tick: attack hits, deals 25 damage, target dies
	sim.step(sim.tick_length)

	assert_true(target.dead, "Target should be marked dead")
	assert_null(attacker.command, "Attacker command should end on target death")

	var events := sim.drain_events()
	assert_eq(events.size(), 2, "Expected 1 damage event and 1 death event")

	var dmg_count := 0
	var death_count := 0
	for ev in events:
		if ev.get("type") == "damage":
			dmg_count += 1
			assert_eq(ev.get("source"), attacker.id)
			assert_eq(ev.get("target"), target.id)
			assert_eq(ev.get("amount"), 25.0)
		elif ev.get("type") == "death":
			death_count += 1
			assert_eq(ev.get("id"), target.id)
			assert_eq(ev.get("tick"), 1)

	assert_eq(dmg_count, 1, "Exactly one damage event on kill")
	assert_eq(death_count, 1, "Exactly one death event on kill")

	# Step for another 40 ticks - no further events should occur
	for tick in range(40):
		sim.step(sim.tick_length)

	var subsequent_events := sim.drain_events()
	assert_eq(subsequent_events.size(), 0, "No further damage or death events after target death")
	assert_null(attacker.command)


func test_dead_entities_and_unknown_target() -> void:
	# Acceptance criterion 5:
	# Dead entities ignore MoveTo/AttackTarget; unknown target id ends the command safely.
	var sim := WorldSim.new(_zone, _registry)
	var stats := Stats.new(100.0, 10.0, 2.0, 1.5, 1.0, 5.0)
	var live_entity := sim.spawn("player", Vector2i(1, 1), 4.0, 100.0, stats)
	var dead_entity := sim.spawn("enemy", Vector2i(2, 2), 2.0, 0.0, stats)

	assert_true(dead_entity.dead, "Spawned with hp 0.0 should be marked dead")

	# Dead entity ignores MoveTo
	sim.submit(Commands.move_to(dead_entity.id, Vector2i(4, 4)))
	sim.step(sim.tick_length)
	assert_null(dead_entity.command, "Dead entity must ignore MoveTo")
	assert_almost_eq(dead_entity.pos.x, 2.5, 0.001)
	assert_almost_eq(dead_entity.pos.y, 2.5, 0.001)

	# Dead entity ignores AttackTarget
	sim.submit(Commands.attack_target(dead_entity.id, live_entity.id))
	sim.step(sim.tick_length)
	assert_null(dead_entity.command, "Dead entity must ignore AttackTarget")
	assert_eq(sim.events.size(), 0)

	# Unknown target id ends command safely
	sim.submit(Commands.attack_target(live_entity.id, 99999))
	sim.step(sim.tick_length)
	assert_null(live_entity.command, "Unknown target id should safely clear command")
	assert_eq(sim.events.size(), 0)

	# Attacking an already dead entity ends safely
	sim.submit(Commands.attack_target(live_entity.id, dead_entity.id))
	sim.step(sim.tick_length)
	assert_null(live_entity.command, "Attacking already dead entity should safely clear command")
	assert_eq(sim.events.size(), 0)


func test_target_moves_attacker_repairs_and_chases() -> void:
	var sim := WorldSim.new(_zone, _registry)
	var attacker_stats := Stats.new(100.0, 10.0, 0.0, 1.0, 1.0, 0.0)
	var target_stats := Stats.new(500.0, 0.0, 0.0, 1.0, 1.0, 0.0)

	var attacker := sim.spawn("player", Vector2i(1, 1), 4.0, -1.0, attacker_stats)
	var target := sim.spawn("enemy", Vector2i(2, 1), 4.0, -1.0, target_stats)

	# In range initially, first hit at tick 1
	sim.submit(Commands.attack_target(attacker.id, target.id))
	sim.step(sim.tick_length)
	var initial_events := sim.drain_events()
	assert_eq(initial_events.size(), 1, "First hit on arrival")

	# Target moves east away from attacker to (4, 1)
	sim.submit(Commands.move_to(target.id, Vector2i(4, 1)))

	# Step until attacker catches up and lands another hit
	var hit_events: Array[Dictionary] = []
	for i in range(40):
		sim.step(sim.tick_length)
		var drained := sim.drain_events()
		for ev in drained:
			if ev.get("type") == "damage":
				hit_events.append(ev)

	# Attacker should have chased east towards target
	assert_true(attacker.pos.x > 2.0, "Attacker should have moved east chasing target")
	assert_almost_eq(attacker.pos.y, 1.5, 0.001)

	# Assert hit events: attacker caught up and hit the moving target again
	assert_gt(hit_events.size(), 0, "Attacker should have hit target again after chasing")
	assert_eq(hit_events[0].get("source"), attacker.id)
	assert_eq(hit_events[0].get("target"), target.id)


func test_attack_target_resubmitted_every_tick_throttled() -> void:
	# Regression test: submitting AttackTarget every tick does not bypass attack_interval
	var sim := WorldSim.new(_zone, _registry)
	var interval_s := 0.5 # 15 ticks at 30 Hz
	var attacker_stats := Stats.new(100.0, 10.0, 0.0, 1.5, interval_s, 5.0)
	var target_stats := Stats.new(1000.0, 0.0, 0.0, 1.5, 1.0, 0.0)

	var attacker := sim.spawn("player", Vector2i(1, 1), 4.0, -1.0, attacker_stats)
	var target := sim.spawn("enemy", Vector2i(2, 1), 0.0, -1.0, target_stats)

	var hit_ticks: Array[int] = []
	for tick in range(60):
		sim.submit(Commands.attack_target(attacker.id, target.id))
		sim.step(sim.tick_length)
		var drained := sim.drain_events()
		for ev in drained:
			if ev.get("type") == "damage":
				hit_ticks.append(ev.get("tick"))

	assert_eq(hit_ticks.size(), 4, "Right-click spam should yield only 4 hits in 60 ticks (interval 0.5s)")
	assert_eq(hit_ticks, [1, 16, 31, 46])


func test_target_leaves_and_reenters_range_no_extra_hit_before_interval() -> void:
	# Regression test: target leaving and re-entering range does not grant extra hits before interval
	var sim := WorldSim.new(_zone, _registry)
	var interval_s := 1.0 # 30 ticks at 30 Hz
	var attacker_stats := Stats.new(100.0, 10.0, 0.0, 1.0, interval_s, 5.0)
	var target_stats := Stats.new(1000.0, 0.0, 0.0, 1.0, 1.0, 0.0)

	var attacker := sim.spawn("player", Vector2i(1, 1), 0.0, -1.0, attacker_stats)
	var target := sim.spawn("enemy", Vector2i(2, 1), 4.0, -1.0, target_stats)

	# Tick 1: attacker attacks in-range target -> first hit
	sim.submit(Commands.attack_target(attacker.id, target.id))
	sim.step(sim.tick_length)
	var events := sim.drain_events()
	assert_eq(events.size(), 1, "First hit on tick 1")

	# Target moves out of range to (4, 1)
	sim.submit(Commands.move_to(target.id, Vector2i(4, 1)))
	for i in range(10):
		sim.step(sim.tick_length)
		var ev := sim.drain_events()
		assert_eq(ev.size(), 0)

	assert_true(attacker.pos.distance_to(target.pos) > attacker_stats.attack_range)

	# Target moves back to (2, 1) into range
	sim.submit(Commands.move_to(target.id, Vector2i(2, 1)))
	var reentered_damage_events: Array[Dictionary] = []
	for i in range(15):
		sim.step(sim.tick_length)
		var ev := sim.drain_events()
		for e in ev:
			if e.get("type") == "damage":
				reentered_damage_events.append(e)

	# Target is back in range, but interval (30 ticks) has not passed yet
	assert_true(attacker.pos.distance_to(target.pos) <= attacker_stats.attack_range + 0.001)
	assert_eq(reentered_damage_events.size(), 0, "No extra damage event before interval elapsed")

	# Step until tick 31 (when 30 ticks since tick 1 have passed)
	while sim.tick_count < 31:
		sim.step(sim.tick_length)
		var ev := sim.drain_events()
		for e in ev:
			if e.get("type") == "damage":
				reentered_damage_events.append(e)

	assert_eq(reentered_damage_events.size(), 1, "Second hit occurs only when interval has passed at tick 31")
	assert_eq(reentered_damage_events[0].get("tick"), 31)


func test_two_attackers_kill_target_same_tick_one_death_event() -> void:
	# Two attackers kill one low-hp target on the same tick:
	# exactly one death event, both commands become null, no subsequent damage events.
	var sim := WorldSim.new(_zone, _registry)
	var attacker_stats1 := Stats.new(100.0, 10.0, 0.0, 1.5, 1.0, 0.0) # 10 damage
	var attacker_stats2 := Stats.new(100.0, 10.0, 0.0, 1.5, 1.0, 0.0) # 10 damage
	var target_stats := Stats.new(10.0, 0.0, 0.0, 1.5, 1.0, 0.0) # 10 hp

	var attacker1 := sim.spawn("player", Vector2i(1, 1), 0.0, -1.0, attacker_stats1)
	var target := sim.spawn("enemy", Vector2i(2, 1), 0.0, -1.0, target_stats)
	var attacker2 := sim.spawn("player", Vector2i(3, 1), 0.0, -1.0, attacker_stats2)

	# Both attackers target the low-hp enemy on the same tick
	sim.submit(Commands.attack_target(attacker1.id, target.id))
	sim.submit(Commands.attack_target(attacker2.id, target.id))

	sim.step(sim.tick_length)

	assert_true(target.dead, "Target should be dead")
	assert_null(attacker1.command, "Attacker 1 command should be null after target death")
	assert_null(attacker2.command, "Attacker 2 command should be null after target death")

	var events := sim.drain_events()
	var dmg_events: Array[Dictionary] = []
	var death_events: Array[Dictionary] = []
	for ev in events:
		if ev.get("type") == "damage":
			dmg_events.append(ev)
		elif ev.get("type") == "death":
			death_events.append(ev)

	assert_eq(death_events.size(), 1, "Exactly one death event emitted")
	assert_eq(dmg_events.size(), 1, "Only the lethal hit damage event emitted; second attacker does not hit dead target")

	# Step another 20 ticks
	for i in range(20):
		sim.step(sim.tick_length)
	var later_events := sim.drain_events()
	assert_eq(later_events.size(), 0, "No subsequent damage events after target death")


func test_attacker_killed_mid_attack() -> void:
	# Attacker killed mid-attack: command ends, no further hits
	var sim := WorldSim.new(_zone, _registry)
	var attacker_stats := Stats.new(20.0, 10.0, 0.0, 1.5, 1.0, 0.0) # 20 hp
	var target_stats := Stats.new(100.0, 0.0, 0.0, 1.5, 1.0, 0.0)
	var killer_stats := Stats.new(100.0, 50.0, 0.0, 1.5, 1.0, 0.0) # 50 damage

	var attacker := sim.spawn("player", Vector2i(1, 1), 0.0, -1.0, attacker_stats)
	var target := sim.spawn("enemy", Vector2i(2, 1), 0.0, -1.0, target_stats)
	var killer := sim.spawn("enemy", Vector2i(1, 2), 0.0, -1.0, killer_stats)

	# Attacker hits target at tick 1
	sim.submit(Commands.attack_target(attacker.id, target.id))
	sim.step(sim.tick_length)
	var initial_events := sim.drain_events()
	assert_eq(initial_events.size(), 1, "Attacker hits target on tick 1")

	# Advance 3 ticks
	for i in range(3):
		sim.step(sim.tick_length)
	sim.drain_events()

	# Killer kills attacker at tick 5
	sim.submit(Commands.attack_target(killer.id, attacker.id))
	sim.step(sim.tick_length)

	assert_true(attacker.dead, "Attacker should be killed")
	assert_null(attacker.command, "Attacker command should end upon death")

	# Step past tick 31 (when attacker's second hit would have occurred)
	for i in range(30):
		sim.step(sim.tick_length)

	var events := sim.drain_events()
	for ev in events:
		if ev.get("type") == "damage":
			assert_ne(ev.get("source"), attacker.id, "Dead attacker must not produce damage events")


func test_retarget_mid_attack_timer_not_reset() -> void:
	# Retargeting from A to B mid-attack: correct target in events, timer not reset
	var sim := WorldSim.new(_zone, _registry)
	var interval_s := 1.0 # 30 ticks at 30 Hz
	var attacker_stats := Stats.new(100.0, 10.0, 0.0, 1.5, interval_s, 0.0)
	var target_a_stats := Stats.new(100.0, 0.0, 0.0, 1.5, 1.0, 0.0)
	var target_b_stats := Stats.new(100.0, 0.0, 0.0, 1.5, 1.0, 0.0)

	var attacker := sim.spawn("player", Vector2i(2, 2), 0.0, -1.0, attacker_stats)
	var target_a := sim.spawn("enemy", Vector2i(2, 1), 0.0, -1.0, target_a_stats)
	var target_b := sim.spawn("enemy", Vector2i(2, 3), 0.0, -1.0, target_b_stats)

	# Tick 1: attack A
	sim.submit(Commands.attack_target(attacker.id, target_a.id))
	sim.step(sim.tick_length)

	var ev1 := sim.drain_events()
	assert_eq(ev1.size(), 1)
	assert_eq(ev1[0].get("target"), target_a.id)
	assert_eq(ev1[0].get("tick"), 1)

	# Tick 5: retarget to B
	for i in range(3):
		sim.step(sim.tick_length)

	sim.submit(Commands.attack_target(attacker.id, target_b.id))
	sim.step(sim.tick_length) # tick 5

	var mid_events := sim.drain_events()
	assert_eq(mid_events.size(), 0, "Retargeting must not trigger immediate attack before timer ready")

	# Step until tick 30
	for i in range(25):
		sim.step(sim.tick_length)
		var tick_ev := sim.drain_events()
		assert_eq(tick_ev.size(), 0, "No damage events prior to interval expiry")

	# Tick 31: interval expires, hits target B
	sim.step(sim.tick_length)
	assert_eq(sim.tick_count, 31)
	var hit_events := sim.drain_events()
	assert_eq(hit_events.size(), 1, "Hit occurs at tick 31")
	assert_eq(hit_events[0].get("source"), attacker.id)
	assert_eq(hit_events[0].get("target"), target_b.id, "Target should be target B")


func test_interval_0_45s_drift_carry_over() -> void:
	# Interval 0.45s over many hits: spacing ~13.5 ticks, hit count within +-1 of expected
	var sim := WorldSim.new(_zone, _registry)
	var interval_s := 0.45
	var attacker_stats := Stats.new(100.0, 10.0, 0.0, 1.5, interval_s, 0.0)
	var target_stats := Stats.new(5000.0, 0.0, 0.0, 1.5, 1.0, 0.0)

	var attacker := sim.spawn("player", Vector2i(1, 1), 0.0, -1.0, attacker_stats)
	var target := sim.spawn("enemy", Vector2i(2, 1), 0.0, -1.0, target_stats)

	sim.submit(Commands.attack_target(attacker.id, target.id))

	var hit_ticks: Array[int] = []
	var total_ticks := 136
	for tick in range(total_ticks):
		sim.step(sim.tick_length)
		var drained := sim.drain_events()
		for ev in drained:
			if ev.get("type") == "damage":
				hit_ticks.append(ev.get("tick"))

	var expected_hits := int(round(float(total_ticks) / (interval_s * 30.0)))
	assert_true(
		abs(hit_ticks.size() - expected_hits) <= 1,
		"Total hits (%d) should be within +-1 of expected (%d)" % [hit_ticks.size(), expected_hits]
	)

	var diff_sum := 0
	for i in range(1, hit_ticks.size()):
		var diff := hit_ticks[i] - hit_ticks[i - 1]
		assert_true(
			diff == 13 or diff == 14,
			"Spacing between hits should be 13 or 14 ticks, got %d (between %d and %d)" % [diff, hit_ticks[i - 1], hit_ticks[i]]
		)
		diff_sum += diff

	var avg_spacing := float(diff_sum) / float(hit_ticks.size() - 1)
	assert_almost_eq(avg_spacing, 13.5, 0.2, "Average spacing should be ~13.5 ticks")


func test_spawn_with_stats_and_no_hp_gives_max_hp() -> void:
	var sim := WorldSim.new(_zone, _registry)
	var stats := Stats.new(350.0, 10.0, 2.0, 1.5, 1.0, 5.0)

	var entity := sim.spawn("player", Vector2i(1, 1), 4.0, -1.0, stats)
	assert_eq(entity.hp, 350.0, "Spawn with stats and hp -1.0 should take stats.max_hp")
	assert_false(entity.dead)

	var entity2 := sim.spawn_with_stats("player", Vector2i(2, 2), 4.0, stats)
	assert_eq(entity2.hp, 350.0, "spawn_with_stats should take stats.max_hp")
	assert_false(entity2.dead)


func test_explicit_hp_overrides_max_hp() -> void:
	var sim := WorldSim.new(_zone, _registry)
	var stats := Stats.new(500.0, 10.0, 2.0, 1.5, 1.0, 5.0)

	var entity := sim.spawn("player", Vector2i(1, 1), 4.0, 100.0, stats)
	assert_eq(entity.hp, 100.0, "Explicit hp 100 with max_hp 500 should remain 100")
	assert_eq(entity.stats.max_hp, 500.0)
	assert_false(entity.dead)


func test_dispatch_refactor_and_types() -> void:
	# Acceptance criterion 6:
	# Movement tests still pass; dispatch refactor covered by existing + new tests.
	var sim := WorldSim.new(_zone, _registry)
	var entity := sim.spawn("player", Vector2i(1, 1), 4.0)

	var move_cmd := Commands.move_to(entity.id, Vector2i(3, 1))
	assert_true(move_cmd is Commands.Command)
	sim.submit(move_cmd)

	sim.step(sim.tick_length)
	assert_not_null(entity.command)
	assert_true(entity.command is Commands.MoveTo)

	# Read-only tick_length and backward-compatible tick_len
	assert_gt(sim.tick_length, 0.0)
	assert_eq(sim.tick_length, sim.tick_len)
