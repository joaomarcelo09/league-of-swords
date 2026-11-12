extends GutTest

const MAP_PATH := "res://data/zones/floor1/floor1.map"
const JSON_PATH := "res://data/zones/floor1/floor1.json"
const ENEMIES_PATH := "res://data/enemies.json"
const BALANCE_PATH := "res://data/balance.json"

var zone: Zone = null


func before_each() -> void:
	zone = Zone.load_files(MAP_PATH, JSON_PATH)


func _tile(v: Variant) -> Vector2i:
	var arr: Array = v
	return Vector2i(int(arr[0]), int(arr[1]))


func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	assert_not_null(f, "%s must open" % path)
	if f == null:
		return {}
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if data is Dictionary:
		return data
	return {}


func test_floor1_is_valid() -> void:
	assert_true(zone.is_valid(), "floor1 must be valid: %s" % str(zone.errors))


func test_floor1_size() -> void:
	assert_gte(zone.width, 50, "floor1 width")
	assert_gte(zone.height, 30, "floor1 height")


func test_entry_is_safe_and_walkable() -> void:
	assert_true(zone.is_walkable(zone.entry), "entry must be walkable")
	assert_true(zone.is_safe(zone.entry), "entry must be safe (inside town)")


func test_entry_matches_balance_default_entry() -> void:
	var balance := _load_json(BALANCE_PATH)
	var pd: Dictionary = balance.get("permadeath", {})
	assert_eq(str(pd.get("default_zone", "")), "floor1")
	assert_eq(_tile(pd.get("default_entry", [-1, -1])), zone.entry, "balance default_entry must equal floor1 entry")
	assert_eq(_tile(Lifecycle.DEFAULT_ENTRY), zone.entry, "Lifecycle.DEFAULT_ENTRY must equal floor1 entry")


func test_every_spawn_reachable_from_entry() -> void:
	assert_gt(zone.spawns.size(), 0)
	for s in zone.spawns:
		var t := _tile(s["tile"])
		assert_false(zone.find_path(zone.entry, t).is_empty(), "spawn %s must be reachable" % str(t))


func test_boss_and_exit_reachable() -> void:
	var bosses := zone.boss_spawns()
	assert_eq(bosses.size(), 1, "exactly one boss spawn")
	if bosses.size() == 1:
		var bt := _tile(bosses[0]["tile"])
		assert_false(zone.find_path(zone.entry, bt).is_empty(), "boss must be reachable")
	assert_gt(zone.exits.size(), 0, "floor1 needs an exit")
	for e in zone.exits:
		var et := _tile(e["tile"])
		assert_false(zone.find_path(zone.entry, et).is_empty(), "exit %s must be reachable" % str(et))


func test_exit_requires_the_boss() -> void:
	var bosses := zone.boss_spawns()
	assert_eq(bosses.size(), 1)
	if bosses.size() != 1:
		return
	var boss_id := str(bosses[0].get("id", ""))
	assert_false(boss_id.is_empty(), "boss spawn needs an id")
	var found := false
	for e in zone.exits:
		if str(e.get("requires_boss", "")) == boss_id and str(e.get("to_zone", "")) == "floor2":
			found = true
	assert_true(found, "an exit to floor2 must require boss '%s'" % boss_id)


func test_no_spawn_on_safe_tile() -> void:
	for s in zone.spawns:
		var t := _tile(s["tile"])
		assert_false(zone.is_safe(t), "spawn %s must not be on a safe tile" % str(t))


func test_at_least_three_enemy_types() -> void:
	var types: Dictionary = {}
	for s in zone.spawns:
		if not bool(s.get("boss", false)):
			types[str(s["enemy"])] = true
	assert_gte(types.size(), 3, "need >= 3 distinct enemy types, got %s" % str(types.keys()))


func test_merchant_npc_on_safe_tile() -> void:
	var found := false
	for n in zone.npcs:
		if str(n.get("kind", "")) == "merchant":
			found = true
			assert_true(zone.is_safe(_tile(n["tile"])), "merchant %s must stand on a safe tile" % str(n.get("id")))
	assert_true(found, "floor1 needs a merchant NPC")


func test_spawn_enemies_exist_in_data() -> void:
	var enemies := _load_json(ENEMIES_PATH)
	for s in zone.spawns:
		var eid := str(s["enemy"])
		assert_true(enemies.has(eid), "enemy '%s' must exist in enemies.json" % eid)


func test_saved_spawn_pos_falls_back_when_tile_not_walkable() -> void:
	# (9, 7) sits inside the town fountain (non-walkable): an old save there must use entry.
	assert_false(zone.is_walkable(Vector2i(9, 7)))
	assert_null(MainView.saved_spawn_pos(zone, [9.5, 7.5]))
	assert_null(MainView.saved_spawn_pos(zone, []))
	assert_null(MainView.saved_spawn_pos(zone, [-5.0, 2.0]))
	var e := Vector2(zone.entry) + Vector2(0.5, 0.5)
	assert_eq(MainView.saved_spawn_pos(zone, [e.x, e.y]), e)
