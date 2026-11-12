extends GutTest

const MAP_PATH := "res://data/zones/floor1/test_arena.map"
const JSON_PATH := "res://data/zones/floor1/test_arena.json"
const DATA_DIR := "res://data"

var _registry: DataRegistry = null
var _zone: Zone = null


func before_each() -> void:
	_registry = DataRegistry.new()
	_registry.load_dir(DATA_DIR)
	_zone = Zone.load_files(MAP_PATH, JSON_PATH)


func test_zone_spawns_create_enemies_at_right_tiles() -> void:
	assert_true(_zone.is_valid(), "Zone should be valid: %s" % str(_zone.errors))
	assert_eq(_zone.spawns.size(), 3, "test_arena should define 3 spawns")

	var session := GameSession.new(_zone, _registry)
	var spawned := session.spawn_zone_enemies()
	assert_eq(spawned.size(), 3, "Should spawn 3 enemies from zone")

	# Check each expected spawn from test_arena
	for i in range(_zone.spawns.size()):
		var s: Dictionary = _zone.spawns[i]
		var tile_arr: Array = s["tile"]
		var expected_tile := Vector2i(int(tile_arr[0]), int(tile_arr[1]))
		var expected_center := WorldSim.tile_center(expected_tile)
		var expected_type: String = str(s["enemy"])

		var entity: Entity = spawned[i]
		assert_not_null(entity, "Spawned entity %d should not be null" % i)
		assert_eq(entity.kind, "enemy", "Entity %d kind should be 'enemy'" % i)
		assert_eq(entity.enemy_type_id, expected_type, "Entity %d enemy_type_id should match" % i)
		assert_eq(entity.pos, expected_center, "Entity %d position should be center of %s" % [i, str(expected_tile)])
		assert_eq(entity.spawn_pos, expected_center, "Entity %d spawn_pos should match pos" % i)
		assert_eq(entity.state, "idle", "Entity %d state should be idle" % i)
		assert_gt(entity.hp, 0.0, "Entity %d should have positive HP" % i)
		assert_gt(entity.speed, 0.0, "Entity %d should have positive speed" % i)
		assert_eq(session.world.get_entity(entity.id), entity, "Entity should exist in WorldSim")


func test_killing_enemy_with_seeded_rng_and_chance_1_produces_ground_item_and_loot_drop_event() -> void:
	var item_db := ItemDB.new(_registry)
	var inventory := Inventory.new(item_db)

	# Register a deterministic loot table with 100% chance for test
	item_db.register_loot_table("ash_stalker", {
		"roll_count": 1,
		"entries": [
			{"item_id": "healing_draught", "chance": 1.0}
		]
	})

	var rng := RandomNumberGenerator.new()
	rng.seed = 12345

	var session := GameSession.new(_zone, _registry, inventory, item_db, rng, "floor1")
	var player := session.spawn_player()
	var spawn_tile := Vector2i(4, 10)
	var enemy := session.world.spawn_enemy("ash_stalker", spawn_tile)
	assert_not_null(enemy, "Enemy should spawn successfully")

	# Kill the enemy
	session.world.apply_damage(player.id, enemy, 9999.0)
	assert_true(enemy.dead, "Enemy should be dead")

	var events := session.world.drain_events()
	var death_event: Dictionary = {}
	var loot_event: Dictionary = {}

	for ev: Dictionary in events:
		if ev.get("type") == "death" and ev.get("target") == enemy.id:
			death_event = ev
		elif ev.get("type") == "loot_drop" and ev.get("entity") == enemy.id:
			loot_event = ev

	assert_false(death_event.is_empty(), "WorldSim should emit death event for enemy")
	assert_false(loot_event.is_empty(), "WorldSim should emit loot_drop event when loot dropped")

	assert_eq(loot_event.get("type"), "loot_drop")
	assert_eq(loot_event.get("entity"), enemy.id)
	assert_eq(loot_event.get("tile"), spawn_tile)
	assert_eq(loot_event.get("tick"), death_event.get("tick"))

	var items: Array = loot_event.get("items", [])
	assert_eq(items.size(), 1, "Should have exactly 1 dropped item UID")
	var uid: int = int(items[0])
	assert_gt(uid, 0, "Item UID must be valid positive integer")

	# Verify ownership and definition in inventory
	assert_eq(inventory.owner_of(uid), "ground:floor1", "Ground item owner should be ground:floor1")
	assert_eq(inventory.def_id_of(uid), "healing_draught", "Ground item definition should match table")


func test_non_enemy_death_player_rolls_no_loot() -> void:
	var item_db := ItemDB.new(_registry)
	var inventory := Inventory.new(item_db)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42

	var session := GameSession.new(_zone, _registry, inventory, item_db, rng, "floor1")
	var player := session.spawn_player()
	assert_not_null(player)

	# Initial item count in inventory
	var initial_item_count := 0
	# Damage player to death
	session.world.apply_damage(0, player, 9999.0)
	assert_true(player.dead, "Player should be dead")

	var events := session.world.drain_events()
	var death_seen := false
	var loot_drop_seen := false

	for ev: Dictionary in events:
		if ev.get("type") == "death" and ev.get("target") == player.id:
			death_seen = true
		if ev.get("type") == "loot_drop":
			loot_drop_seen = true

	assert_true(death_seen, "Player death event should be emitted")
	assert_false(loot_drop_seen, "Player death must not emit any loot_drop event")

	# Ensure no ground items exist in inventory
	var ground_items := inventory.items_of("ground:floor1")
	assert_eq(ground_items.size(), 0, "No items should be created in inventory on player death")


func test_same_seed_gives_same_drops() -> void:
	# Real data loot table: ash_stalker has healing_draught (0.5) and iron_sword (0.2)
	var run_with_seed := func(seed_val: int) -> Array[String]:
		var idb := ItemDB.new(_registry)
		var inv := Inventory.new(idb)
		var r := RandomNumberGenerator.new()
		r.seed = seed_val

		var sess := GameSession.new(_zone, _registry, inv, idb, r, "floor1")
		var p := sess.spawn_player()

		var dropped_defs: Array[String] = []
		# Spawn and kill 5 enemies in sequence
		for k in range(5):
			var en := sess.world.spawn_enemy("ash_stalker", Vector2i(4, 10))
			sess.world.apply_damage(p.id, en, 9999.0)
			var evs := sess.world.drain_events()
			for ev in evs:
				if ev.get("type") == "loot_drop":
					for uid_val in ev.get("items", []):
						dropped_defs.append(inv.def_id_of(int(uid_val)))
		return dropped_defs

	var drops_run1: Array = run_with_seed.call(777)
	var drops_run2: Array = run_with_seed.call(777)
	assert_eq(drops_run1, drops_run2, "Same seed must produce identical loot drops in same order")


func test_main_view_integration() -> void:
	var temp_root := "user://test_saves/main_view_glue_%d" % int(Time.get_unix_time_from_system() * 1000.0)
	_clean_dir(temp_root)
	var view := MainView.new()
	view.save_root = temp_root
	view.save_slot = "glue_slot"
	autofree(view)
	view._ready()

	assert_not_null(view.session, "MainView must create GameSession")
	assert_not_null(view.world, "MainView must have WorldSim")
	assert_eq(view.world, view.session.world, "MainView world should reference session.world")
	assert_not_null(view.item_db, "MainView must have ItemDB")
	assert_not_null(view.inventory, "MainView must have Inventory")
	assert_not_null(view.player, "MainView must spawn player")
	assert_not_null(view.player_input, "MainView must create PlayerInput")
	assert_true(view.player_input.attack_mode_changed.is_connected(view._on_attack_mode_changed), "MainView must connect to attack_mode_changed")

	# Check that zone enemies were spawned in world
	var enemy_count := 0
	for entity: Entity in view.world.entities.values():
		if entity.kind == "enemy":
			enemy_count += 1
	assert_eq(enemy_count, 3, "MainView should have spawned 3 zone enemies in test_arena")

	# Test stepping
	var initial_tick: int = view.world.tick_count
	view._process(0.05)
	assert_gt(view.world.tick_count, initial_tick, "MainView _process must step simulation")

	_clean_dir(temp_root)


func _clean_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(path)
	if dir != null:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while not file_name.is_empty():
			var full_sub := path.path_join(file_name)
			if dir.current_is_dir():
				if file_name != "." and file_name != "..":
					_clean_dir(full_sub)
			else:
				DirAccess.remove_absolute(full_sub)
			file_name = dir.get_next()
		dir.list_dir_end()
	DirAccess.remove_absolute(path)


func test_enemy_without_loot_table_produces_no_loot_drop() -> void:
	var item_db := ItemDB.new(_registry)
	var inventory := Inventory.new(item_db)
	var rng := RandomNumberGenerator.new()
	rng.seed = 123

	var session := GameSession.new(_zone, _registry, inventory, item_db, rng, "floor1")
	var player := session.spawn_player()

	# Create a dummy enemy with no loot table in ItemDB
	var enemy := session.world.spawn("enemy", Vector2i(4, 10), 2.0, 50.0)
	enemy.enemy_type_id = "unregistered_dummy"

	session.world.apply_damage(player.id, enemy, 100.0)
	assert_true(enemy.dead)

	var events := session.world.drain_events()
	var loot_events: Array[Dictionary] = []
	for e: Dictionary in events:
		if e.get("type") == "loot_drop":
			loot_events.append(e)
	assert_eq(loot_events.size(), 0, "No loot_drop event should be emitted for enemy without loot table")
