extends GutTest

const TYPES: Array[String] = ["ash_stalker", "bog_slime", "cinder_bat", "thornback_warden"]

var _registry: DataRegistry = null
var _zone: Zone = null


func before_each() -> void:
	_registry = DataRegistry.new()
	_registry.load_dir("res://data")
	_zone = Zone.load_files("res://data/zones/floor1/test_small.map", "res://data/zones/floor1/test_small.json")


func _cfg(type_id: String) -> Dictionary:
	return _registry.get_entry("enemies", type_id)


func test_all_four_types_exist_and_validate() -> void:
	for type_id: String in TYPES:
		assert_true(_registry.has_entry("enemies", type_id), "enemies.json should contain '%s'" % type_id)
		var errors := EnemyAI.validate_config(_cfg(type_id))
		assert_eq(errors.size(), 0, "'%s' config errors: %s" % [type_id, str(errors)])
		assert_false(str(_cfg(type_id).get("name", "")).is_empty(), "'%s' must have a name" % type_id)


func test_each_type_spawns_with_own_stats_from_json() -> void:
	var sim := WorldSim.new(_zone, _registry)
	for type_id: String in TYPES:
		var cfg := _cfg(type_id)
		for key: String in ["max_hp", "atk", "defense", "move_speed_tiles_per_s"]:
			assert_true(cfg.has(key), "'%s' should define '%s'" % [type_id, key])
		var enemy := sim.spawn_enemy(type_id, Vector2i(2, 2))
		assert_not_null(enemy, "'%s' should spawn" % type_id)
		if enemy == null:
			continue
		assert_eq(enemy.enemy_type_id, type_id)
		assert_almost_eq(enemy.stats.max_hp, float(cfg["max_hp"]), 1e-6, "%s max_hp" % type_id)
		assert_almost_eq(enemy.hp, float(cfg["max_hp"]), 1e-6, "%s hp" % type_id)
		assert_almost_eq(enemy.stats.atk, float(cfg["atk"]), 1e-6, "%s atk" % type_id)
		assert_almost_eq(enemy.stats.defense, float(cfg["defense"]), 1e-6, "%s defense" % type_id)
		assert_almost_eq(enemy.speed, float(cfg["move_speed_tiles_per_s"]), 1e-6, "%s speed" % type_id)
		# Non-overridden fields still come from balance.enemy.
		assert_almost_eq(enemy.stats.attack_range, float(_registry.get_balance("enemy.attack_range")), 1e-6)
		assert_almost_eq(enemy.stats.attack_interval, float(_registry.get_balance("enemy.attack_interval")), 1e-6)


func test_types_have_distinct_stats() -> void:
	var sim := WorldSim.new(_zone, _registry)
	var slime := sim.spawn_enemy("bog_slime", Vector2i(2, 2))
	var bat := sim.spawn_enemy("cinder_bat", Vector2i(2, 2))
	var stalker := sim.spawn_enemy("ash_stalker", Vector2i(2, 2))
	var warden := sim.spawn_enemy("thornback_warden", Vector2i(2, 2))
	assert_gt(bat.speed, slime.speed, "bat faster than slime")
	assert_gt(slime.stats.max_hp, bat.stats.max_hp, "slime tankier than bat")
	assert_gt(slime.stats.max_hp, stalker.stats.max_hp, "slime tankier than stalker")
	assert_lt(slime.stats.atk, stalker.stats.atk, "slime hits softer than stalker")
	assert_lt(bat.stats.max_hp, stalker.stats.max_hp, "bat more fragile than stalker")
	assert_gt(warden.stats.max_hp, slime.stats.max_hp, "warden has the most HP")


func _type_without_stats() -> Dictionary:
	var cfg := _cfg("ash_stalker").duplicate(true)
	cfg.erase("max_hp")
	cfg.erase("atk")
	cfg.erase("defense")
	cfg.erase("move_speed_tiles_per_s")
	cfg["name"] = "Test Plain"
	return cfg


func test_missing_stat_fields_fall_back_to_balance() -> void:
	_registry._tables["enemies"]["test_plain"] = _type_without_stats()
	var sim := WorldSim.new(_zone, _registry)
	var enemy := sim.spawn_enemy("test_plain", Vector2i(2, 2))
	assert_not_null(enemy)
	assert_almost_eq(enemy.stats.max_hp, float(_registry.get_balance("enemy.max_hp")), 1e-6)
	assert_almost_eq(enemy.hp, float(_registry.get_balance("enemy.max_hp")), 1e-6)
	assert_almost_eq(enemy.stats.atk, float(_registry.get_balance("enemy.atk")), 1e-6)
	assert_almost_eq(enemy.stats.defense, float(_registry.get_balance("enemy.defense")), 1e-6)
	assert_almost_eq(enemy.speed, float(_registry.get_balance("enemy.move_speed_tiles_per_s")), 1e-6)


func test_partial_stat_fields_fall_back_per_field() -> void:
	var cfg := _type_without_stats()
	cfg["atk"] = float(_registry.get_balance("enemy.atk")) + 7.0
	_registry._tables["enemies"]["test_partial"] = cfg
	var sim := WorldSim.new(_zone, _registry)
	var enemy := sim.spawn_enemy("test_partial", Vector2i(2, 2))
	assert_not_null(enemy)
	assert_almost_eq(enemy.stats.atk, float(cfg["atk"]), 1e-6)
	assert_almost_eq(enemy.stats.max_hp, float(_registry.get_balance("enemy.max_hp")), 1e-6)
	assert_almost_eq(enemy.stats.defense, float(_registry.get_balance("enemy.defense")), 1e-6)


func test_explicit_hp_and_stats_args_still_win() -> void:
	var sim := WorldSim.new(_zone, _registry)
	var custom := Stats.new(42.0, 1.0, 1.0, 1.0, 1.0, 0.0)
	var enemy := sim.spawn_enemy("thornback_warden", Vector2i(2, 2), 7.0, custom)
	assert_not_null(enemy)
	assert_eq(enemy.stats, custom)
	assert_almost_eq(enemy.hp, 7.0, 1e-6)
	var enemy2 := sim.spawn_enemy("bog_slime", Vector2i(2, 2), 11.0)
	assert_almost_eq(enemy2.hp, 11.0, 1e-6)
	assert_almost_eq(enemy2.stats.max_hp, float(_cfg("bog_slime")["max_hp"]), 1e-6)


func test_shapes_and_timings_differ_as_designed() -> void:
	var stalker := _cfg("ash_stalker")
	var slime := _cfg("bog_slime")
	var bat := _cfg("cinder_bat")
	var warden := _cfg("thornback_warden")
	assert_eq(str(stalker["attack"]["shape"]), "cone")
	assert_eq(str(slime["attack"]["shape"]), "circle")
	assert_gt(float(slime["attack"]["radius"]), 0.0)
	assert_eq(str(bat["attack"]["shape"]), "line")
	assert_gt(float(bat["attack"]["width"]), 0.0)
	assert_eq(str(warden["attack"]["shape"]), "cone")
	assert_gt(float(warden["attack"]["angle_deg"]), float(stalker["attack"]["angle_deg"]), "warden cone wider")
	assert_gt(float(warden["windup_s"]), float(stalker["windup_s"]), "warden windup longer")
	assert_gt(float(warden["recovery_s"]), float(stalker["recovery_s"]), "warden recovery longer")
	assert_gt(float(bat["move_speed_tiles_per_s"]), float(slime["move_speed_tiles_per_s"]), "bat faster")
	for type_id: String in TYPES:
		assert_eq(str(_cfg(type_id).get("appearance", "")), "ash_stalker", "%s reuses ash_stalker art" % type_id)
