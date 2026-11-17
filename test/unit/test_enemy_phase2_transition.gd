extends GutTest
## JGT-130: Gorvak's one-shot phase 2 transition. The first time the boss drops
## below its phase 2 HP threshold it stops, charges a circular AoE for charge_s,
## hits once at the locked origin and then returns to its normal phase 2 chase.

const MAP_PATH := "res://data/zones/floor1/test_small.map"
const JSON_PATH := "res://data/zones/floor1/test_small.json"
const BOSS_ID := "thornback_warden"
const BOSS_TILE := Vector2i(7, 2)
const INSIDE_TILE := Vector2i(8, 2)
## 4.24 tiles from the boss tile centre: outside a 4 tile circle.
const OUTSIDE_TILE := Vector2i(10, 5)

var _registry: DataRegistry = null
var _zone: Zone = null


func before_each() -> void:
	_registry = DataRegistry.new()
	_registry.load_dir("res://data")
	_zone = Zone.load_files(MAP_PATH, JSON_PATH)


func _boss_config() -> Dictionary:
	return _registry.get_entry("enemies", BOSS_ID)


func _transition() -> Dictionary:
	return _boss_config()["phase2"]["transition"]


func _spawn_boss_with_players() -> Dictionary:
	var sim := WorldSim.new(_zone, _registry)
	var boss := sim.spawn_enemy(BOSS_ID, BOSS_TILE)
	assert_not_null(boss, "boss spawns")
	var inside := sim.spawn("player", INSIDE_TILE, 0.0, 100.0)
	var outside := sim.spawn("player", OUTSIDE_TILE, 0.0, 100.0)
	return {"sim": sim, "boss": boss, "inside": inside, "outside": outside}


## Drops the boss below the threshold and steps once into the scream. Returns the
## charge duration in ticks.
func _start_scream(sim: WorldSim, boss: Entity) -> int:
	boss.hp = boss.stats.max_hp * 0.2
	sim.step(sim.tick_length)
	assert_eq(boss.state, "scream", "the boss screams when it enters phase 2")
	var charge_ticks := int(round(float(_transition()["charge_s"]) / sim.tick_length))
	assert_eq(boss.state_end_tick, sim.tick_count + charge_ticks, "the charge lasts charge_s")
	return charge_ticks


func _first_event(events: Array[Dictionary], type: String) -> Dictionary:
	for ev: Dictionary in events:
		if ev.get("type") == type:
			return ev
	return {}


func _count_events(events: Array[Dictionary], type: String) -> int:
	var count := 0
	for ev: Dictionary in events:
		if ev.get("type") == type:
			count += 1
	return count


func _validate_with_transition(transition: Variant) -> Array[String]:
	var cfg := _boss_config().duplicate(true)
	cfg["phase2"]["transition"] = transition
	return EnemyAI.validate_config(cfg)


func test_scream_starts_when_entering_phase2_and_emits_the_events() -> void:
	var ctx := _spawn_boss_with_players()
	var sim: WorldSim = ctx["sim"]
	var boss: Entity = ctx["boss"]

	var charge_ticks := _start_scream(sim, boss)
	assert_true(boss.phase2_transition_done, "the transition is marked as done when it starts")
	var events := sim.drain_events()

	var telegraph := _first_event(events, "telegraph_start")
	assert_false(telegraph.is_empty(), "the scream emits a telegraph")
	assert_eq(telegraph.get("shape"), "circle")
	assert_eq(int(telegraph.get("phase", 0)), 2)
	assert_true(bool(telegraph.get("transition", false)), "the telegraph is flagged as a transition")
	assert_almost_eq(float(telegraph.get("radius", 0.0)), 4.0, 0.001)
	assert_almost_eq(float(telegraph.get("duration_s", 0.0)), 2.0, 0.001)
	assert_eq(int(telegraph.get("duration_ticks", 0)), charge_ticks)
	assert_eq(telegraph.get("origin"), boss.pos)
	assert_eq(telegraph.get("dir"), Vector2.ZERO)

	var start := _first_event(events, "phase_transition_start")
	assert_false(start.is_empty(), "the scream emits a phase transition start")
	assert_eq(int(start.get("source", 0)), boss.id)
	assert_almost_eq(float(start.get("duration_s", 0.0)), 2.0, 0.001)


func test_the_boss_does_not_move_while_screaming() -> void:
	var ctx := _spawn_boss_with_players()
	var sim: WorldSim = ctx["sim"]
	var boss: Entity = ctx["boss"]

	var charge_ticks := _start_scream(sim, boss)
	var start_pos := boss.pos
	for _i in range(charge_ticks - 1):
		sim.step(sim.tick_length)
	assert_eq(boss.state, "scream", "the charge keeps the boss screaming")
	assert_eq(boss.pos, start_pos, "the scream roots the boss")
	assert_eq(boss.path.size(), 0, "the scream drops any chase path")


func test_impact_hits_players_inside_and_spares_players_outside() -> void:
	var ctx := _spawn_boss_with_players()
	var sim: WorldSim = ctx["sim"]
	var boss: Entity = ctx["boss"]
	var inside: Entity = ctx["inside"]
	var outside: Entity = ctx["outside"]

	var charge_ticks := _start_scream(sim, boss)
	sim.drain_events()
	for _i in range(charge_ticks):
		sim.step(sim.tick_length)

	assert_eq(boss.state, "recovery", "the impact hands over to recovery")
	var recovery_ticks := int(round(float(_transition()["recovery_s"]) / sim.tick_length))
	assert_eq(boss.state_end_tick, sim.tick_count + recovery_ticks, "recovery lasts transition.recovery_s")
	assert_lt(inside.hp, 100.0, "a player inside the circle takes the scream damage")
	assert_eq(outside.hp, 100.0, "a player outside the circle is spared")

	var impact := _first_event(sim.drain_events(), "phase_transition_impact")
	assert_false(impact.is_empty(), "the impact emits an event")
	assert_eq(int(impact.get("source", 0)), boss.id)
	assert_almost_eq(float(impact.get("radius", 0.0)), 4.0, 0.001)


func test_a_player_who_walks_out_during_the_charge_is_not_hit() -> void:
	var sim := WorldSim.new(_zone, _registry)
	var boss := sim.spawn_enemy(BOSS_ID, BOSS_TILE)
	var player := sim.spawn("player", INSIDE_TILE, 4.0, 100.0)

	var charge_ticks := _start_scream(sim, boss)
	sim.submit(Commands.move_to_point(player.id, Vector2(OUTSIDE_TILE) + Vector2(0.5, 0.5)))
	for _i in range(charge_ticks):
		sim.step(sim.tick_length)

	assert_gt(player.pos.distance_to(boss.locked_origin), 4.0, "the player leaves the circle before the impact")
	assert_eq(player.hp, 100.0, "walking out of the circle dodges the scream")


func test_the_boss_stays_damageable_during_the_scream() -> void:
	var ctx := _spawn_boss_with_players()
	var sim: WorldSim = ctx["sim"]
	var boss: Entity = ctx["boss"]
	var inside: Entity = ctx["inside"]

	_start_scream(sim, boss)
	var hp_before := boss.hp
	sim.apply_damage(inside.id, boss, 5.0)
	assert_lt(boss.hp, hp_before, "damage lands while the boss screams")
	assert_eq(boss.state, "scream", "taking damage does not cancel the scream")


func test_the_scream_does_not_repeat_after_recovery_or_later_hp_drops() -> void:
	var ctx := _spawn_boss_with_players()
	var sim: WorldSim = ctx["sim"]
	var boss: Entity = ctx["boss"]

	var charge_ticks := _start_scream(sim, boss)
	for _i in range(charge_ticks):
		sim.step(sim.tick_length)
	var recovery_ticks := int(round(float(_transition()["recovery_s"]) / sim.tick_length))
	for _i in range(recovery_ticks):
		sim.step(sim.tick_length)
	assert_eq(boss.state, "chase", "the transition returns to the normal chase")

	sim.drain_events()
	boss.hp = boss.stats.max_hp * 0.1
	var screamed := false
	for _i in range(20):
		sim.step(sim.tick_length)
		if boss.state == "scream":
			screamed = true
	assert_false(screamed, "the one-shot transition never repeats")
	assert_eq(_count_events(sim.drain_events(), "phase_transition_start"), 0)


func test_a_new_entity_can_run_the_transition_again() -> void:
	var ctx := _spawn_boss_with_players()
	var sim: WorldSim = ctx["sim"]
	var first: Entity = ctx["boss"]

	var charge_ticks := _start_scream(sim, first)
	for _i in range(charge_ticks):
		sim.step(sim.tick_length)

	var second := sim.spawn_enemy(BOSS_ID, Vector2i(7, 4))
	assert_not_null(second, "the second boss spawns")
	assert_false(second.phase2_transition_done, "a new entity starts with a fresh one-shot")
	sim.spawn("player", Vector2i(8, 4), 0.0, 100.0)
	second.hp = second.stats.max_hp * 0.2
	sim.step(sim.tick_length)
	assert_eq(second.state, "scream", "a new entity can scream again")


func test_a_scream_does_not_interrupt_an_attack_in_progress() -> void:
	var ctx := _spawn_boss_with_players()
	var sim: WorldSim = ctx["sim"]
	var boss: Entity = ctx["boss"]
	var cfg := _boss_config()

	sim.step(sim.tick_length)
	assert_eq(boss.state, "windup", "the boss starts its phase 1 windup")
	boss.hp = boss.stats.max_hp * 0.2
	sim.drain_events()

	var windup_ticks := int(round(float(cfg["windup_s"]) / sim.tick_length))
	for _i in range(windup_ticks):
		sim.step(sim.tick_length)
	assert_eq(boss.state, "active", "the started attack finishes its windup")

	var active_ticks := int(round(float(cfg["active_s"]) / sim.tick_length))
	for _i in range(active_ticks):
		sim.step(sim.tick_length)
	assert_eq(boss.state, "recovery", "the started attack finishes its active window")

	var recovery_ticks := int(round(float(cfg["recovery_s"]) / sim.tick_length))
	for _i in range(recovery_ticks):
		sim.step(sim.tick_length)
	assert_eq(boss.state, "chase", "the attack ends before the scream")
	assert_eq(_count_events(sim.drain_events(), "phase_transition_start"), 0, "no scream during the attack")

	sim.step(sim.tick_length)
	assert_eq(boss.state, "scream", "the scream starts at the next chase tick")


func test_enemies_without_a_transition_are_unaffected() -> void:
	var sim := WorldSim.new(_zone, _registry)
	var slime := sim.spawn_enemy("bog_slime", BOSS_TILE)
	sim.spawn("player", INSIDE_TILE, 0.0, 100.0)
	slime.hp = slime.stats.max_hp * 0.1

	sim.step(sim.tick_length)
	assert_eq(slime.state, "windup", "an enemy without a transition keeps its normal attack")

	var boss := sim.spawn_enemy(BOSS_ID, Vector2i(7, 4))
	boss.hp = boss.stats.max_hp * 0.2
	var cfg := _boss_config().duplicate(true)
	cfg["phase2"].erase("transition")
	assert_false(EnemyAI._can_start_scream(boss, cfg), "phase 2 without a transition block does not scream")


func test_validate_config_rejects_bad_transitions() -> void:
	var circle := {"shape": "circle", "range": 4.0, "radius": 4.0, "damage_mult": 3.0}
	assert_gt(_validate_with_transition(null).size(), 0, "transition must be a Dictionary")
	assert_gt(_validate_with_transition({}).size(), 0, "transition must not be empty")
	assert_gt(_validate_with_transition({"recovery_s": 0.8, "attack": circle}).size(), 0, "charge_s is required")
	assert_gt(_validate_with_transition({"charge_s": 0.0, "recovery_s": 0.8, "attack": circle}).size(), 0, "charge_s must be > 0")
	assert_gt(_validate_with_transition({"charge_s": -1.0, "recovery_s": 0.8, "attack": circle}).size(), 0, "negative charge_s")
	assert_gt(_validate_with_transition({"charge_s": "slow", "recovery_s": 0.8, "attack": circle}).size(), 0, "non-numeric charge_s")
	assert_gt(_validate_with_transition({"charge_s": 2.0, "attack": circle}).size(), 0, "recovery_s is required")
	assert_gt(_validate_with_transition({"charge_s": 2.0, "recovery_s": -0.1, "attack": circle}).size(), 0, "negative recovery_s")
	assert_gt(_validate_with_transition({"charge_s": 2.0, "recovery_s": 0.8}).size(), 0, "attack is required")
	assert_gt(_validate_with_transition({"charge_s": 2.0, "recovery_s": 0.8, "attack": "boom"}).size(), 0, "attack must be a Dictionary")
	assert_gt(_validate_with_transition({"charge_s": 2.0, "recovery_s": 0.8, "attack": {"shape": "cone", "range": 3.0, "angle_deg": 90.0}}).size(), 0, "a cone is not allowed")
	assert_gt(_validate_with_transition({"charge_s": 2.0, "recovery_s": 0.8, "attack": {"shape": "circle", "range": 4.0}}).size(), 0, "circle needs a radius")
	assert_eq(_validate_with_transition({"charge_s": 2.0, "recovery_s": 0.8, "attack": circle}).size(), 0, "a valid transition passes")
	assert_eq(_validate_with_transition({"charge_s": 2.0, "recovery_s": 0, "attack": circle}).size(), 0, "recovery_s may be 0")


func test_real_boss_transition_is_valid_dodgeable_and_not_a_one_shot() -> void:
	var cfg := _boss_config()
	assert_eq(EnemyAI.validate_config(cfg).size(), 0, "the real boss config is valid")

	var transition: Dictionary = cfg["phase2"]["transition"]
	var attack: Dictionary = transition["attack"]
	assert_eq(attack.get("shape"), "circle")
	assert_gt(float(attack.get("radius", 0.0)), 0.0)
	assert_gt(float(attack.get("damage_mult", 0.0)), float(cfg["phase2"]["attack"]["damage_mult"]), "the scream hits harder than the sweep")

	var player_speed := float(_registry.get_balance("player.move_speed_tiles_per_s", 0.0))
	assert_gt(player_speed, 0.0)
	assert_lt(float(attack["radius"]), player_speed * float(transition["charge_s"]), "the player can leave the circle before the impact")

	var sim := WorldSim.new(_zone, _registry)
	var boss := sim.spawn_enemy(BOSS_ID, BOSS_TILE)
	var player := sim.spawn("player", INSIDE_TILE, 0.0, 100.0)
	var base_damage := Combat.compute_damage(sim.effective_stats(boss), sim.effective_stats(player), _registry)
	var impact_damage := base_damage * float(attack["damage_mult"])
	assert_lt(impact_damage, player.stats.max_hp, "a fresh player survives one scream impact")
	assert_gt(impact_damage, base_damage * 2.5, "the scream hits about three times as hard")
