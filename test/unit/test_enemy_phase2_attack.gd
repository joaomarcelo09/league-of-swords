extends GutTest
## JGT-128: Gorvak's phase 2 cleaver sweep. The pattern is chosen when the windup
## starts and locked until recovery ends, so HP crossing the threshold mid-swing
## cannot change the attack already in progress.

const MAP_PATH := "res://data/zones/floor1/test_small.map"
const JSON_PATH := "res://data/zones/floor1/test_small.json"
const BOSS_ID := "thornback_warden"
const BOSS_TILE := Vector2i(7, 2)
const NEAR_TILE := Vector2i(8, 2)
## 90 degrees off the aim: outside the base 140 degree cone, inside the 220 sweep.
const WIDE_TILE := Vector2i(7, 4)

var _registry: DataRegistry = null
var _zone: Zone = null


func before_each() -> void:
	_registry = DataRegistry.new()
	_registry.load_dir("res://data")
	_zone = Zone.load_files(MAP_PATH, JSON_PATH)


func _boss_config() -> Dictionary:
	return _registry.get_entry("enemies", BOSS_ID)


## Spawns the boss with a nearby player on its aim line and a second player 90
## degrees off. Returns {"sim", "boss", "near", "wide"}.
func _spawn_boss_with_players() -> Dictionary:
	var sim := WorldSim.new(_zone, _registry)
	var boss := sim.spawn_enemy(BOSS_ID, BOSS_TILE)
	assert_not_null(boss, "boss spawns")
	# These tests cover the phase 2 cleaver; JGT-130's one-shot transition is
	# consumed here so it cannot delay the sweep they assert on.
	boss.phase2_transition_done = true
	var near := sim.spawn("player", NEAR_TILE, 0.0, 100.0)
	var wide := sim.spawn("player", WIDE_TILE, 0.0, 100.0)
	return {"sim": sim, "boss": boss, "near": near, "wide": wide}


func _last_telegraph(sim: WorldSim) -> Dictionary:
	var found: Dictionary = {}
	for ev: Dictionary in sim.drain_events():
		if ev.get("type") == "telegraph_start":
			found = ev
	return found


func _validate_with_phase2(phase2: Variant) -> Array[String]:
	var cfg := _boss_config().duplicate(true)
	cfg["phase2"] = phase2
	return EnemyAI.validate_config(cfg)


func test_is_phase2_tracks_the_hp_threshold_and_requires_a_block() -> void:
	var cfg := _boss_config()
	var sim := WorldSim.new(_zone, _registry)
	var boss := sim.spawn_enemy(BOSS_ID, BOSS_TILE)
	var max_hp: float = boss.stats.max_hp
	var threshold := float(cfg["phase2"]["hp_ratio_below"])

	boss.hp = max_hp * 0.9
	assert_false(EnemyAI.is_phase2(boss, cfg), "full HP is phase 1")
	boss.hp = max_hp * threshold
	assert_false(EnemyAI.is_phase2(boss, cfg), "exactly at the threshold is still phase 1")
	boss.hp = max_hp * threshold - 1.0
	assert_true(EnemyAI.is_phase2(boss, cfg), "below the threshold is phase 2")

	assert_false(EnemyAI.is_phase2(boss, _registry.get_entry("enemies", "ash_stalker")), "no phase2 block")
	assert_false(EnemyAI.is_phase2(boss, {"phase2": {"hp_ratio_below": 0.0}}), "0 is not a threshold")
	assert_false(EnemyAI.is_phase2(boss, {"phase2": {"hp_ratio_below": 1.0}}), "1.0 is not a threshold")
	assert_false(EnemyAI.is_phase2(boss, {"phase2": {"hp_ratio_below": "soon"}}), "non-numeric threshold")


func test_above_threshold_uses_the_base_windup_and_cone() -> void:
	var ctx := _spawn_boss_with_players()
	var sim: WorldSim = ctx["sim"]
	var boss: Entity = ctx["boss"]
	var near: Entity = ctx["near"]
	var wide: Entity = ctx["wide"]
	var cfg := _boss_config()

	sim.step(sim.tick_length)
	assert_eq(boss.state, "windup")
	var windup_ticks := int(round(float(cfg["windup_s"]) / sim.tick_length))
	assert_eq(boss.state_end_tick, sim.tick_count + windup_ticks, "base windup duration")

	var telegraph := _last_telegraph(sim)
	assert_eq(telegraph.get("shape"), "cone")
	assert_almost_eq(float(telegraph.get("angle_deg", 0.0)), 140.0, 0.001)
	assert_almost_eq(float(telegraph.get("duration", 0.0)), float(cfg["windup_s"]), 0.001)
	assert_eq(telegraph.get("phase", null), null, "phase 1 telegraphs have no phase key")

	for _i in range(windup_ticks):
		sim.step(sim.tick_length)
	assert_eq(boss.state, "active")
	assert_lt(near.hp, 100.0, "the base cone hits the aimed player")
	assert_eq(wide.hp, 100.0, "90 degrees off is outside the base 140 degree cone")


func test_below_threshold_uses_the_phase2_sweep_and_timings() -> void:
	var ctx := _spawn_boss_with_players()
	var sim: WorldSim = ctx["sim"]
	var boss: Entity = ctx["boss"]
	var near: Entity = ctx["near"]
	var wide: Entity = ctx["wide"]
	var phase2: Dictionary = _boss_config()["phase2"]
	boss.hp = boss.stats.max_hp * 0.2

	sim.step(sim.tick_length)
	assert_eq(boss.state, "windup")
	var windup_ticks := int(round(float(phase2["windup_s"]) / sim.tick_length))
	var active_ticks := int(round(float(phase2["active_s"]) / sim.tick_length))
	var recovery_ticks := int(round(float(phase2["recovery_s"]) / sim.tick_length))
	assert_eq(boss.state_end_tick, sim.tick_count + windup_ticks, "phase 2 windup duration")

	var telegraph := _last_telegraph(sim)
	assert_eq(int(telegraph.get("phase", 0)), 2, "phase 2 telegraph is flagged")
	assert_almost_eq(float(telegraph.get("angle_deg", 0.0)), 220.0, 0.001, "cleaver sweep angle")
	assert_almost_eq(float(telegraph.get("duration", 0.0)), float(phase2["windup_s"]), 0.001)

	for _i in range(windup_ticks):
		sim.step(sim.tick_length)
	assert_eq(boss.state, "active")
	assert_eq(boss.state_end_tick, sim.tick_count + active_ticks)
	assert_lt(near.hp, 100.0, "the sweep hits the aimed player")
	assert_lt(wide.hp, 100.0, "the 220 degree sweep hits 90 degrees off the aim")

	for _i in range(active_ticks):
		sim.step(sim.tick_length)
	assert_eq(boss.state, "recovery")
	assert_eq(boss.state_end_tick, sim.tick_count + recovery_ticks, "phase 2 recovery duration")


func test_pattern_is_locked_when_hp_drops_during_windup() -> void:
	var ctx := _spawn_boss_with_players()
	var sim: WorldSim = ctx["sim"]
	var boss: Entity = ctx["boss"]
	var near: Entity = ctx["near"]
	var wide: Entity = ctx["wide"]
	var cfg := _boss_config()

	sim.step(sim.tick_length)
	assert_eq(boss.state, "windup")
	assert_eq(_last_telegraph(sim).get("phase", null), null, "the attack starts in phase 1")
	var base_windup_ticks := int(round(float(cfg["windup_s"]) / sim.tick_length))
	var base_active_ticks := int(round(float(cfg["active_s"]) / sim.tick_length))
	var base_recovery_ticks := int(round(float(cfg["recovery_s"]) / sim.tick_length))

	boss.hp = boss.stats.max_hp * 0.2

	for _i in range(base_windup_ticks):
		sim.step(sim.tick_length)
	assert_eq(boss.state, "active", "the started windup keeps its base duration")
	assert_eq(boss.state_end_tick, sim.tick_count + base_active_ticks, "base active duration stays locked")
	assert_lt(near.hp, 100.0)
	assert_eq(wide.hp, 100.0, "the swing keeps the base 140 degree cone after HP drops")

	for _i in range(base_active_ticks):
		sim.step(sim.tick_length)
	assert_eq(boss.state, "recovery")
	assert_eq(boss.state_end_tick, sim.tick_count + base_recovery_ticks, "base recovery duration stays locked")

	for _i in range(base_recovery_ticks):
		sim.step(sim.tick_length)
	assert_eq(boss.state, "chase", "the locked attack is over")

	sim.step(sim.tick_length)
	assert_eq(boss.state, "windup")
	assert_eq(int(_last_telegraph(sim).get("phase", 0)), 2, "the next attack uses phase 2")
	var phase2_windup_ticks := int(round(float(cfg["phase2"]["windup_s"]) / sim.tick_length))
	assert_eq(boss.state_end_tick, sim.tick_count + phase2_windup_ticks)


func test_real_boss_config_has_a_valid_phase2_attack() -> void:
	var cfg := _boss_config()
	assert_eq(EnemyAI.validate_config(cfg).size(), 0, "the real boss config is valid")
	assert_eq(EnemyAI.validate_config(_registry.get_entry("enemies", "ash_stalker")).size(), 0, "phase2 is optional")

	var phase2: Dictionary = cfg["phase2"]
	var attack: Dictionary = phase2["attack"]
	assert_eq(attack.get("shape"), "cone")
	assert_gt(float(attack["range"]), 0.0)
	assert_gt(float(attack["angle_deg"]), 140.0, "the cleaver sweep is wider than the base cone")
	assert_gt(float(attack["damage_mult"]), float(cfg["attack"]["damage_mult"]), "the sweep hits harder")


func test_validate_config_rejects_bad_phase2_values() -> void:
	assert_gt(_validate_with_phase2({"hp_ratio_below": 0.0}).size(), 0, "threshold 0")
	assert_gt(_validate_with_phase2({"hp_ratio_below": 1.0}).size(), 0, "threshold 1")
	assert_gt(_validate_with_phase2({"hp_ratio_below": "soon"}).size(), 0, "non-numeric threshold")
	assert_gt(_validate_with_phase2({"hp_ratio_below": 0.35, "windup_s": -0.1}).size(), 0, "negative windup")
	assert_gt(_validate_with_phase2({"hp_ratio_below": 0.35, "active_s": "slow"}).size(), 0, "non-numeric active")
	assert_gt(_validate_with_phase2({"hp_ratio_below": 0.35, "recovery_s": -1.0}).size(), 0, "negative recovery")
	assert_gt(_validate_with_phase2({"hp_ratio_below": 0.35, "attack": "wide"}).size(), 0, "attack must be a Dictionary")
	assert_gt(_validate_with_phase2({"hp_ratio_below": 0.35, "attack": {"shape": "spiral", "range": 1.0}}).size(), 0, "invalid attack shape")
	assert_gt(_validate_with_phase2("soon").size(), 0, "phase2 must be a Dictionary")
	assert_eq(_validate_with_phase2({"hp_ratio_below": 0.35}).size(), 0, "timings and attack are optional")
