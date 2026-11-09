extends GutTest

const FIXTURE_DIR := "user://test_fixture_skills"

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


func test_real_skills_json_loads_and_passes_validate_skill() -> void:
	var registry := DataRegistry.new()
	registry.load_dir("res://data")

	var errors := registry.validate()
	assert_eq(errors.size(), 0, "res://data should validate without errors: %s" % str(errors))

	var skill_ids := registry.ids("skills")
	assert_has(skill_ids, "ember_lance")
	assert_has(skill_ids, "crescent_sweep")
	assert_has(skill_ids, "mending_gale")

	for s_id in skill_ids:
		var skill_dict := registry.get_entry("skills", s_id)
		var val_errors := SkillSystem.validate_skill(skill_dict)
		assert_eq(val_errors.size(), 0, "Skill '%s' should pass validate_skill: %s" % [s_id, str(val_errors)])

	var q_skill := registry.get_entry("skills", "ember_lance")
	assert_eq(q_skill.get("slot"), "Q")
	assert_eq(q_skill.get("shape"), "line")

	var w_skill := registry.get_entry("skills", "crescent_sweep")
	assert_eq(w_skill.get("slot"), "W")
	assert_eq(w_skill.get("shape"), "cone")

	var r_skill := registry.get_entry("skills", "mending_gale")
	assert_eq(r_skill.get("slot"), "R")
	assert_eq(r_skill.get("shape"), "circle")
	assert_eq(r_skill.get("range"), 0.0)


func test_validate_skill_detects_malformed_definitions() -> void:
	var valid_base: Dictionary = {
		"name": "Test Skill",
		"slot": "Q",
		"cooldown_s": 2.0,
		"cast_time_s": 0.1,
		"shape": "line",
		"range": 4.0,
		"width": 1.0,
		"effects": [{"type": "damage", "mult": 1.0}]
	}
	assert_eq(SkillSystem.validate_skill(valid_base).size(), 0)

	var bad_name := valid_base.duplicate()
	bad_name["name"] = ""
	assert_gt(SkillSystem.validate_skill(bad_name).size(), 0)

	var bad_slot := valid_base.duplicate()
	bad_slot["slot"] = "E"
	assert_gt(SkillSystem.validate_skill(bad_slot).size(), 0)

	var bad_cd := valid_base.duplicate()
	bad_cd["cooldown_s"] = -1.0
	assert_gt(SkillSystem.validate_skill(bad_cd).size(), 0)

	var bad_shape := valid_base.duplicate()
	bad_shape["shape"] = "triangle"
	assert_gt(SkillSystem.validate_skill(bad_shape).size(), 0)

	var bad_line := valid_base.duplicate()
	bad_line.erase("width")
	assert_gt(SkillSystem.validate_skill(bad_line).size(), 0)

	var bad_cone: Dictionary = {
		"name": "Cone", "slot": "W", "cooldown_s": 1.0, "cast_time_s": 0.0,
		"shape": "cone", "range": 3.0, "effects": [{"type": "damage", "mult": 1.0}]
	}
	assert_gt(SkillSystem.validate_skill(bad_cone).size(), 0)

	var bad_circle: Dictionary = {
		"name": "Circle", "slot": "R", "cooldown_s": 1.0, "cast_time_s": 0.0,
		"shape": "circle", "range": 0.0, "effects": [{"type": "heal", "amount": 10.0}]
	}
	assert_gt(SkillSystem.validate_skill(bad_circle).size(), 0)

	var bad_effects := valid_base.duplicate()
	bad_effects["effects"] = []
	assert_gt(SkillSystem.validate_skill(bad_effects).size(), 0)

	var bad_eff_type := valid_base.duplicate()
	bad_eff_type["effects"] = [{"type": "unknown_type"}]
	assert_gt(SkillSystem.validate_skill(bad_eff_type).size(), 0)


func test_shape_line_inclusion_and_edge_cases() -> void:
	var line_skill: Dictionary = {
		"shape": "line",
		"range": 5.0,
		"width": 1.0
	}
	var origin := Vector2(10.0, 10.0)
	var dir := Vector2(1.0, 0.0)

	# Inside: straight ahead, distance 3.0
	assert_true(SkillSystem.in_shape(line_skill, origin, dir, Vector2(13.0, 10.0)))
	# Inside: near right side edge within half-width (0.5)
	assert_true(SkillSystem.in_shape(line_skill, origin, dir, Vector2(13.0, 10.45)))
	assert_true(SkillSystem.in_shape(line_skill, origin, dir, Vector2(13.0, 9.55)))
	# Inside: near max range (4.9)
	assert_true(SkillSystem.in_shape(line_skill, origin, dir, Vector2(14.9, 10.0)))

	# Edge case: behind caster
	assert_false(SkillSystem.in_shape(line_skill, origin, dir, Vector2(9.5, 10.0)))
	# Edge case: beyond range (dist 5.5 > 5.0)
	assert_false(SkillSystem.in_shape(line_skill, origin, dir, Vector2(15.5, 10.0)))
	# Edge case: outside width (perp_dist 0.6 > 0.5)
	assert_false(SkillSystem.in_shape(line_skill, origin, dir, Vector2(13.0, 10.65)))
	assert_false(SkillSystem.in_shape(line_skill, origin, dir, Vector2(13.0, 9.35)))

	# Diagonal direction test: dir (1, 1)
	var diag_dir := Vector2(1.0, 1.0).normalized()
	assert_true(SkillSystem.in_shape(line_skill, origin, diag_dir, origin + diag_dir * 3.0))
	assert_false(SkillSystem.in_shape(line_skill, origin, diag_dir, origin - diag_dir * 1.0))
	assert_false(SkillSystem.in_shape(line_skill, origin, diag_dir, origin + diag_dir * 6.0))


func test_shape_cone_inclusion_and_edge_cases() -> void:
	var cone_skill: Dictionary = {
		"shape": "cone",
		"range": 4.0,
		"angle_deg": 90.0 # half-angle is 45 deg
	}
	var origin := Vector2(0.0, 0.0)
	var dir := Vector2(1.0, 0.0)

	# Inside: straight ahead at dist 2.0
	assert_true(SkillSystem.in_shape(cone_skill, origin, dir, Vector2(2.0, 0.0)))
	# Inside: exactly at 45 degrees, dist 2.0 (cos 45 = sin 45 ~= 0.7071)
	assert_true(SkillSystem.in_shape(cone_skill, origin, dir, Vector2(1.4, 1.4)))
	assert_true(SkillSystem.in_shape(cone_skill, origin, dir, Vector2(1.4, -1.4)))

	# Edge case: behind caster (-1.0, 0.0)
	assert_false(SkillSystem.in_shape(cone_skill, origin, dir, Vector2(-1.0, 0.0)))
	# Edge case: beyond range (dist 4.5 > 4.0)
	assert_false(SkillSystem.in_shape(cone_skill, origin, dir, Vector2(4.5, 0.0)))
	# Edge case: outside angle (e.g. 60 degrees from center, vector (1.0, 2.0))
	assert_false(SkillSystem.in_shape(cone_skill, origin, dir, Vector2(1.0, 2.0)))
	assert_false(SkillSystem.in_shape(cone_skill, origin, dir, Vector2(1.0, -2.0)))


func test_shape_circle_inclusion_and_edge_cases() -> void:
	# Case 1: Centred on caster (range 0)
	var self_circle: Dictionary = {
		"shape": "circle",
		"range": 0.0,
		"radius": 2.5
	}
	var caster_pos := Vector2(10.0, 10.0)
	# Inside radius (dist 1.5 < 2.5 and dist 2.0 < 2.5)
	assert_true(SkillSystem.in_shape(self_circle, caster_pos, Vector2(1.0, 0.0), Vector2(11.5, 10.0)))
	assert_true(SkillSystem.in_shape(self_circle, caster_pos, Vector2(1.0, 0.0), Vector2(10.0, 12.0)))
	# Exactly on the edge (dist 2.5 == 2.5)
	assert_true(SkillSystem.in_shape(self_circle, caster_pos, Vector2(1.0, 0.0), Vector2(12.5, 10.0)))
	assert_true(SkillSystem.in_shape(self_circle, caster_pos, Vector2(1.0, 0.0), Vector2(10.0, 12.5)))
	assert_true(SkillSystem.in_shape(self_circle, caster_pos, Vector2(1.0, 0.0), Vector2(7.5, 10.0)))
	# Beyond radius (dist 3.0 > 2.5 and dist 2.55 > 2.5)
	assert_false(SkillSystem.in_shape(self_circle, caster_pos, Vector2(1.0, 0.0), Vector2(13.0, 10.0)))
	assert_false(SkillSystem.in_shape(self_circle, caster_pos, Vector2(1.0, 0.0), Vector2(12.55, 10.0)))

	# Case 2: Ground-targeted with range > 0 (aim within range)
	var aoe_circle: Dictionary = {
		"shape": "circle",
		"range": 5.0,
		"radius": 2.0
	}
	var aim_offset := Vector2(3.0, 0.0) # within range 5.0, center is at (13, 10)
	# Inside: dist 0.5 < 2.0
	assert_true(SkillSystem.in_shape(aoe_circle, caster_pos, aim_offset, Vector2(13.5, 10.0)))
	# On the edge: dist 2.0 == radius 2.0
	assert_true(SkillSystem.in_shape(aoe_circle, caster_pos, aim_offset, Vector2(15.0, 10.0)))
	assert_true(SkillSystem.in_shape(aoe_circle, caster_pos, aim_offset, Vector2(11.0, 10.0)))
	# Outside: dist 2.5 > 2.0 and dist 2.05 > 2.0
	assert_false(SkillSystem.in_shape(aoe_circle, caster_pos, aim_offset, Vector2(15.5, 10.0)))
	assert_false(SkillSystem.in_shape(aoe_circle, caster_pos, aim_offset, Vector2(15.05, 10.0)))

	# Case 3: Ground-targeted aimed beyond range -> clamped to range 5.0 (center at (15, 10))
	var far_aim_offset := Vector2(10.0, 0.0)
	# Inside: dist 0.5 < 2.0
	assert_true(SkillSystem.in_shape(aoe_circle, caster_pos, far_aim_offset, Vector2(15.5, 10.0)))
	# On the edge: dist 2.0 == radius 2.0 (center is 15.0, edge at 17.0)
	assert_true(SkillSystem.in_shape(aoe_circle, caster_pos, far_aim_offset, Vector2(17.0, 10.0)))
	# Outside: point at (12, 10) is dist 3.0 from clamped center (15, 10) -> outside radius 2.0
	assert_false(SkillSystem.in_shape(aoe_circle, caster_pos, far_aim_offset, Vector2(12.0, 10.0)))
	assert_false(SkillSystem.in_shape(aoe_circle, caster_pos, far_aim_offset, Vector2(17.05, 10.0)))


func test_cast_skill_unknown_slot_and_zero_aim_fail() -> void:
	var sim := WorldSim.new(_zone, _registry)
	var player := sim.spawn("player", Vector2i(1, 1), 4.0)

	# Unknown slot "X"
	sim.submit(Commands.cast_skill(player.id, "X", player.pos + Vector2(2.0, 0.0)))
	sim.step(sim.tick_length)
	var events := sim.drain_events()
	assert_eq(events.size(), 1)
	assert_eq(events[0]["type"], "cast_failed")
	assert_eq(events[0]["slot"], "X")
	assert_eq(events[0]["reason"], "unknown_slot")
	assert_null(player.command)

	# Zero aim (aim == player.pos)
	sim.submit(Commands.cast_skill(player.id, "Q", player.pos))
	sim.step(sim.tick_length)
	events = sim.drain_events()
	assert_eq(events.size(), 1)
	assert_eq(events[0]["type"], "cast_failed")
	assert_eq(events[0]["slot"], "Q")
	assert_eq(events[0]["reason"], "zero_direction")
	assert_null(player.command)

	# Slot mapped to unknown skill
	player.skills["Q"] = "nonexistent_skill"
	sim.submit(Commands.cast_skill(player.id, "Q", player.pos + Vector2(2.0, 0.0)))
	sim.step(sim.tick_length)
	events = sim.drain_events()
	assert_eq(events.size(), 1)
	assert_eq(events[0]["type"], "cast_failed")
	assert_eq(events[0]["reason"], "unknown_skill")


func test_damage_equals_mult_times_formula() -> void:
	var sim := WorldSim.new(_zone, _registry)
	var player_stats := Stats.new(100.0, 10.0, 2.0, 1.5, 1.0, 5.0)
	var enemy_stats := Stats.new(200.0, 5.0, 2.0, 1.0, 1.0, 0.0)

	var player := sim.spawn("player", Vector2i(1, 1), 4.0, 100.0, player_stats)
	var enemy := sim.spawn("enemy", Vector2i(3, 1), 0.0, 200.0, enemy_stats)

	# Base combat formula: (atk + weapon) * atk_scale - def * def_scale
	# = (10.0 + 5.0) * 1.0 - (2.0 * 1.0) = 13.0
	# Q skill "ember_lance": mult 1.5, cast_time_s 0.2 (6 ticks at 30Hz)
	# Expected damage = 1.5 * 13.0 = 19.5
	sim.submit(Commands.cast_skill(player.id, "Q", enemy.pos))

	# Advance 6 ticks for cast time
	for i in range(6):
		sim.step(sim.tick_length)

	var events := sim.drain_events()
	var damage_event: Dictionary = {}
	var cast_event: Dictionary = {}
	for ev in events:
		if ev["type"] == "damage":
			damage_event = ev
		elif ev["type"] == "skill_cast":
			cast_event = ev

	assert_false(cast_event.is_empty(), "Expected skill_cast event")
	assert_eq(cast_event.get("skill"), "ember_lance")
	assert_eq(cast_event.get("slot"), "Q")

	assert_false(damage_event.is_empty(), "Expected damage event")
	assert_eq(damage_event.get("target"), enemy.id)
	assert_eq(damage_event.get("amount"), 19.5)
	assert_eq(enemy.hp, 200.0 - 19.5)
	assert_eq(player.hp, 100.0, "Player should not damage self")


func test_cooldown_blocks_recast_and_unblocks_exactly_on_time() -> void:
	var sim := WorldSim.new(_zone, _registry)
	var player := sim.spawn("player", Vector2i(1, 1), 4.0)
	var enemy := sim.spawn("enemy", Vector2i(3, 1), 0.0, 500.0)

	# Set Q to 0 cast time, 1.0s cooldown (30 ticks)
	var skill_dict := _registry.get_entry("skills", "ember_lance").duplicate(true)
	skill_dict["cast_time_s"] = 0.0
	skill_dict["cooldown_s"] = 1.0
	_registry._tables["skills"]["ember_lance"] = skill_dict

	# Cast at tick 1 (first step)
	sim.submit(Commands.cast_skill(player.id, "Q", enemy.pos))
	sim.step(sim.tick_length)
	var resolve_tick: int = sim.tick_count
	assert_eq(resolve_tick, 1)

	var cooldown_ticks: int = int(round(float(skill_dict["cooldown_s"]) / sim.tick_length))
	var ready_tick: int = resolve_tick + cooldown_ticks
	assert_eq(player.skill_ready_ticks["Q"], float(resolve_tick + cooldown_ticks), "skill_ready_ticks must equal resolve_tick + cooldown ticks")

	var events := sim.drain_events()
	assert_eq(events[0]["type"], "skill_cast")

	# Recast on cooldown at tick 2
	sim.submit(Commands.cast_skill(player.id, "Q", enemy.pos))
	sim.step(sim.tick_length)
	events = sim.drain_events()
	assert_eq(events.size(), 1)
	assert_eq(events[0]["type"], "cast_failed")
	assert_eq(events[0]["reason"], "cooldown")

	# Step until ready_tick - 2 (tick 29, so next submit+step lands on ready_tick - 1)
	while sim.tick_count < ready_tick - 2:
		sim.step(sim.tick_length)
		sim.drain_events()

	assert_eq(sim.tick_count, ready_tick - 2)

	# Recast applied on tick ready - 1 (tick 30): must fail with "cooldown"
	sim.submit(Commands.cast_skill(player.id, "Q", enemy.pos))
	sim.step(sim.tick_length)
	assert_eq(sim.tick_count, ready_tick - 1)
	events = sim.drain_events()
	assert_eq(events.size(), 1)
	assert_eq(events[0]["type"], "cast_failed")
	assert_eq(events[0]["reason"], "cooldown")

	# Recast applied on ready tick (tick 31): must succeed with "skill_cast"
	sim.submit(Commands.cast_skill(player.id, "Q", enemy.pos))
	sim.step(sim.tick_length)
	assert_eq(sim.tick_count, ready_tick)
	events = sim.drain_events()
	assert_false(events.is_empty())
	assert_eq(events[0]["type"], "skill_cast", "Should succeed exactly on ready tick")


func test_failed_cast_while_walking_preserves_path_and_reaches_destination() -> void:
	var sim := WorldSim.new(_zone, _registry)
	var player := sim.spawn("player", Vector2i(1, 1), 4.0)

	# Start moving to (4, 1)
	sim.submit(Commands.move_to(player.id, Vector2i(4, 1)))
	sim.step(sim.tick_length)

	assert_not_null(player.command)
	assert_true(player.command is Commands.MoveTo)
	var initial_path := player.path.duplicate()
	assert_false(initial_path.is_empty())

	# Put Q on cooldown far in the future
	player.skill_ready_ticks["Q"] = 1000.0

	# Step a few ticks along the path
	for i in range(5):
		sim.step(sim.tick_length)
	sim.drain_events()

	var mid_path := player.path.duplicate()
	var mid_path_index := player.path_index
	var mid_pos := player.pos

	# Submit Q on cooldown while walking
	sim.submit(Commands.cast_skill(player.id, "Q", Vector2(10.0, 1.5)))
	sim.step(sim.tick_length)

	var events := sim.drain_events()
	assert_eq(events.size(), 1)
	assert_eq(events[0]["type"], "cast_failed")
	assert_eq(events[0]["reason"], "cooldown")
	assert_eq(events[0]["slot"], "Q")

	# Verify command, path, and path_index are intact and movement progressed
	assert_not_null(player.command, "MoveTo command must remain active after failed cast")
	assert_true(player.command is Commands.MoveTo)
	assert_eq(player.path, mid_path, "Path must remain unchanged after failed cast")
	assert_gte(player.path_index, mid_path_index, "Path index must not reset")
	assert_gt(player.pos.x, mid_pos.x, "Player must continue moving during the tick")

	# Continue stepping until player reaches destination
	for i in range(30):
		sim.step(sim.tick_length)

	assert_null(player.command, "Command should clear upon reaching destination")
	var expected_dest := WorldSim.tile_center(Vector2i(4, 1))
	assert_true(player.pos.is_equal_approx(expected_dest), "Player should reach (4, 1) destination")


func test_failed_cast_during_w_cast_leaves_w_to_resolve_with_effects() -> void:
	var sim := WorldSim.new(_zone, _registry)
	var player_stats := Stats.new(100.0, 10.0, 2.0, 1.5, 1.0, 5.0)
	var enemy_stats := Stats.new(200.0, 5.0, 2.0, 1.0, 1.0, 0.0)

	var player := sim.spawn("player", Vector2i(1, 1), 4.0, 100.0, player_stats)
	var enemy := sim.spawn("enemy", Vector2i(2, 1), 0.0, 200.0, enemy_stats)

	# Crescent Sweep (W) has cast_time_s = 0.3s (9 ticks)
	# Put Q on cooldown far in the future
	player.skill_ready_ticks["Q"] = 1000.0

	# Start casting W
	sim.submit(Commands.cast_skill(player.id, "W", enemy.pos))
	sim.step(sim.tick_length) # Tick 1: cast begins, resolve_tick = 1 + 9 - 1 = 9

	assert_not_null(player.command)
	assert_true(player.command is Commands.CastSkill)
	assert_eq((player.command as Commands.CastSkill).slot, "W")

	# Step 3 ticks into the 9-tick cast
	for i in range(3):
		sim.step(sim.tick_length)
	sim.drain_events()

	# Tick 5: mid-cast, submit Q on cooldown
	sim.submit(Commands.cast_skill(player.id, "Q", enemy.pos))
	sim.step(sim.tick_length) # Tick 5

	var events := sim.drain_events()
	var failed_ev: Dictionary = {}
	for ev in events:
		if ev["type"] == "cast_failed":
			failed_ev = ev
	assert_false(failed_ev.is_empty(), "Expected cast_failed for Q")
	assert_eq(failed_ev.get("reason"), "cooldown")
	assert_eq(failed_ev.get("slot"), "Q")

	# W cast must still be active
	assert_not_null(player.command, "W cast command must remain active")
	assert_true(player.command is Commands.CastSkill)
	assert_eq((player.command as Commands.CastSkill).slot, "W")

	# Step until tick 8 (1 tick before resolve)
	while sim.tick_count < 8:
		sim.step(sim.tick_length)
		var pre_events := sim.drain_events()
		for ev in pre_events:
			assert_ne(ev["type"], "skill_cast")
			assert_ne(ev["type"], "damage")

	# Step to tick 9 (W resolves)
	sim.step(sim.tick_length)
	var resolved_events := sim.drain_events()
	var w_cast: Dictionary = {}
	var w_damage: Dictionary = {}
	for ev in resolved_events:
		if ev["type"] == "skill_cast" and ev.get("slot") == "W":
			w_cast = ev
		elif ev["type"] == "damage" and ev.get("target") == enemy.id:
			w_damage = ev

	assert_false(w_cast.is_empty(), "W skill_cast event must be emitted on resolve")
	assert_false(w_damage.is_empty(), "W damage event must be emitted on resolve")
	# Formula damage: (10 + 5) * 1.0 - 2 * 1.0 = 13.0
	# Crescent Sweep mult: 1.2 -> 13.0 * 1.2 = 15.6
	assert_eq(w_damage.get("amount"), 15.6)
	assert_eq(enemy.hp, 200.0 - 15.6)
	assert_null(player.command, "W cast command should clear after resolving")


func test_cast_time_delays_effects_and_moveto_mid_cast_cancels_it() -> void:
	var sim := WorldSim.new(_zone, _registry)
	var player := sim.spawn("player", Vector2i(1, 1), 4.0)
	var enemy := sim.spawn("enemy", Vector2i(3, 1), 0.0, 500.0)

	# 0.2s cast time = 6 ticks at 30Hz
	sim.submit(Commands.cast_skill(player.id, "Q", enemy.pos))

	# First 5 ticks: cast in progress, no damage events
	for i in range(5):
		sim.step(sim.tick_length)
		var mid_events := sim.drain_events()
		for ev in mid_events:
			assert_ne(ev["type"], "damage", "No damage should occur during cast time")

	# 6th tick: cast resolves!
	sim.step(sim.tick_length)
	var resolved_events := sim.drain_events()
	var had_damage := false
	for ev in resolved_events:
		if ev["type"] == "damage":
			had_damage = true
	assert_true(had_damage, "Damage should occur upon cast resolve")

	# Now test MoveTo mid-cast cancelling:
	# Put Q ready again
	player.skill_ready_ticks["Q"] = 0.0
	sim.submit(Commands.cast_skill(player.id, "Q", enemy.pos))
	sim.step(sim.tick_length) # Tick 1 of cast
	sim.drain_events()

	# Mid-cast: submit MoveTo
	sim.submit(Commands.move_to(player.id, Vector2i(1, 2)))
	# Step past cast duration
	for i in range(8):
		sim.step(sim.tick_length)

	var cancel_events := sim.drain_events()
	for ev in cancel_events:
		assert_ne(ev["type"], "skill_cast", "Cancelled cast must not emit skill_cast")
		assert_ne(ev["type"], "damage", "Cancelled cast must not deal damage")

	# Verify cancelled cast did NOT go on cooldown
	assert_eq(player.skill_ready_ticks.get("Q", 0.0), 0.0, "Cancelled cast must not start cooldown")


func test_heal_capped_at_max_hp_and_never_revives_dead() -> void:
	var sim := WorldSim.new(_zone, _registry)
	var player_stats := Stats.new(100.0, 10.0, 2.0, 1.5, 1.0, 5.0)
	var player := sim.spawn("player", Vector2i(1, 1), 4.0, 85.0, player_stats)

	# R skill "mending_gale": heal amount 30.0, player is at 85/100 HP
	# Capped at 100.0 -> healed amount = 15.0
	sim.submit(Commands.cast_skill(player.id, "R", player.pos + Vector2(1.0, 0.0)))
	sim.step(sim.tick_length)

	var events := sim.drain_events()
	var heal_ev: Dictionary = {}
	for ev in events:
		if ev["type"] == "heal":
			heal_ev = ev

	assert_false(heal_ev.is_empty(), "Expected heal event")
	assert_eq(heal_ev.get("target"), player.id)
	assert_eq(heal_ev.get("amount"), 15.0)
	assert_eq(player.hp, 100.0, "Player HP should be capped at max_hp")

	# Dead entities are never revived
	var dead_mob := sim.spawn("enemy", Vector2i(2, 1), 0.0, 50.0)
	dead_mob.hp = 0.0
	dead_mob.dead = true

	var healed := sim.apply_heal(player.id, dead_mob, 50.0)
	assert_eq(healed, 0.0)
	assert_eq(dead_mob.hp, 0.0)
	assert_true(dead_mob.dead, "Dead entity must never revive")


func test_buff_raises_basic_attack_damage_then_expires() -> void:
	var sim := WorldSim.new(_zone, _registry)
	var player_stats := Stats.new(100.0, 10.0, 0.0, 1.5, 1.0, 5.0)
	var enemy_stats := Stats.new(500.0, 0.0, 0.0, 1.0, 1.0, 0.0)

	var player := sim.spawn("player", Vector2i(1, 1), 4.0, 100.0, player_stats)
	var enemy := sim.spawn("enemy", Vector2i(2, 1), 0.0, 500.0, enemy_stats)

	# Unbuffed basic attack: (10 + 5) * 1.0 = 15.0 damage
	sim.submit(Commands.attack_target(player.id, enemy.id))
	sim.step(sim.tick_length)
	var events := sim.drain_events()
	assert_eq(events[0]["type"], "damage")
	assert_eq(events[0]["amount"], 15.0)

	# Apply buff via R skill ("mending_gale": atk mult 1.5, duration_s 1.0 = 30 ticks)
	var r_skill := _registry.get_entry("skills", "mending_gale").duplicate(true)
	r_skill["effects"] = [{"type": "buff", "stat": "atk", "mult": 1.5, "duration_s": 1.0}]
	_registry._tables["skills"]["mending_gale"] = r_skill

	sim.submit(Commands.cast_skill(player.id, "R", player.pos + Vector2(1.0, 0.0)))
	sim.step(sim.tick_length)
	events = sim.drain_events()

	var buff_ev: Dictionary = {}
	for ev in events:
		if ev["type"] == "buff":
			buff_ev = ev
	assert_false(buff_ev.is_empty(), "Expected buff event")
	assert_eq(buff_ev.get("stat"), "atk")
	assert_eq(buff_ev.get("mult"), 1.5)

	# Effective stats during buff: atk is 15.0, damage should be (15 + 5) = 20.0
	var eff := sim.effective_stats(player)
	assert_eq(eff.atk, 15.0)

	# Make attack ready
	player.attack_ready_tick = 0.0
	sim.submit(Commands.attack_target(player.id, enemy.id))
	sim.step(sim.tick_length)
	events = sim.drain_events()
	assert_eq(events[0]["type"], "damage")
	assert_eq(events[0]["amount"], 20.0, "Buffed basic attack should deal 20.0 damage")

	# Advance 35 ticks -> buff expires
	for i in range(35):
		sim.step(sim.tick_length)
	sim.drain_events()

	var eff_after := sim.effective_stats(player)
	assert_eq(eff_after.atk, 10.0, "Effective atk should return to 10.0 after expiry")

	player.attack_ready_tick = 0.0
	sim.submit(Commands.attack_target(player.id, enemy.id))
	sim.step(sim.tick_length)
	events = sim.drain_events()
	assert_eq(events[0]["type"], "damage")
	assert_eq(events[0]["amount"], 15.0, "Damage should return to 15.0 after buff expiry")


func test_fixture_4th_skill_loads_from_json_and_works_without_code_changes() -> void:
	DirAccess.make_dir_recursive_absolute(FIXTURE_DIR)
	var balance_path := FIXTURE_DIR.path_join("balance.json")
	var skills_path := FIXTURE_DIR.path_join("skills.json")

	var balance_content := """{
		"combat": { "min_damage": 1.0, "atk_scale": 1.0, "def_scale": 1.0 },
		"sim": { "tick_hz": 30 },
		"player": {
			"move_speed_tiles_per_s": 4.0, "max_hp": 100.0, "atk": 10.0, "defense": 0.0,
			"attack_range": 1.0, "attack_interval": 1.0, "weapon_damage": 0.0,
			"skills": { "Q": "mystic_nova" }
		},
		"enemy": {
			"move_speed_tiles_per_s": 0.0, "max_hp": 300.0, "atk": 0.0, "defense": 0.0,
			"attack_range": 1.0, "attack_interval": 1.0, "weapon_damage": 0.0
		}
	}"""
	var skills_content := """{
		"mystic_nova": {
			"name": "Mystic Nova",
			"slot": "Q",
			"cooldown_s": 2.0,
			"cast_time_s": 0.0,
			"shape": "circle",
			"range": 4.0,
			"radius": 2.0,
			"effects": [
				{ "type": "damage", "mult": 2.5 }
			]
		}
	}"""

	var f_bal := FileAccess.open(balance_path, FileAccess.WRITE)
	f_bal.store_string(balance_content)
	f_bal.close()

	var f_skl := FileAccess.open(skills_path, FileAccess.WRITE)
	f_skl.store_string(skills_content)
	f_skl.close()

	var custom_reg := DataRegistry.new()
	custom_reg.load_dir(FIXTURE_DIR)
	assert_eq(custom_reg.validate().size(), 0)
	assert_true(custom_reg.has_entry("skills", "mystic_nova"))

	var sim := WorldSim.new(_zone, custom_reg)
	var p := sim.spawn("player", Vector2i(1, 1), 4.0)
	var e := sim.spawn("enemy", Vector2i(3, 1), 0.0)

	assert_eq(p.skills.get("Q"), "mystic_nova")

	# Cast 4th skill directly at enemy
	sim.submit(Commands.cast_skill(p.id, "Q", e.pos))
	sim.step(sim.tick_length)

	var events := sim.drain_events()
	var dmg_ev: Dictionary = {}
	for ev in events:
		if ev["type"] == "damage":
			dmg_ev = ev

	assert_false(dmg_ev.is_empty(), "4th fixture skill should deal damage")
	# Base: 10 * 1.0 = 10.0, mult 2.5 -> 25.0
	assert_eq(dmg_ev.get("amount"), 25.0)
	assert_eq(e.hp, 300.0 - 25.0)
