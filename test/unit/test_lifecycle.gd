extends GutTest

const TEST_ROOT := "user://test_saves"

var _registry: DataRegistry = null
var _item_db: ItemDB = null
var _store: SaveStore = null


func before_each() -> void:
	_clean_dir(TEST_ROOT)
	_registry = DataRegistry.new()
	_registry.load_dir("res://data")
	_item_db = ItemDB.new(_registry)
	_store = SaveStore.new(TEST_ROOT, _item_db)


func after_each() -> void:
	_clean_dir(TEST_ROOT)


func after_all() -> void:
	_clean_dir(TEST_ROOT)


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


func test_cemetery_entry_fields() -> void:
	var world := WorldState.new()
	world.inventory = Inventory.new(_item_db)

	var character := CharacterState.new()
	character.id = "char_elric"
	character.name = "Elric"
	character.level = 7
	character.zone = "floor1"
	character.appearance = {"hair": "silver", "body": "knight"}
	character.status = "alive"

	var res := Lifecycle.on_player_death(world, character, "ash_stalker", "2026-11-10")
	assert_true(res.get("ok", false), "on_player_death should succeed")
	assert_eq(character.status, "dead", "Character status should be dead")
	assert_eq(world.cemetery.size(), 1, "Cemetery should have exactly 1 entry")

	var entry: Dictionary = world.cemetery[0]
	assert_eq(entry["character_id"], "char_elric", "Cemetery entry character_id must match")
	assert_eq(entry["name"], "Elric", "Cemetery entry name must match")
	assert_eq(entry["level"], 7, "Cemetery entry level must match")
	assert_eq(entry["zone"], "floor1", "Cemetery entry zone must match")
	assert_eq(entry["cause"], "ash_stalker", "Cemetery entry cause must match")
	assert_eq(entry["date"], "2026-11-10", "Cemetery entry date must match")
	assert_eq(entry["appearance"], {"hair": "silver", "body": "knight"}, "Cemetery entry appearance must match")


func test_idempotence() -> void:
	var world := WorldState.new()
	world.inventory = Inventory.new(_item_db)

	var character := CharacterState.new()
	character.id = "char_1"
	character.name = "Hero"
	character.level = 3
	character.zone = "floor1"
	character.appearance = {"body": "base"}
	character.status = "alive"

	var res1 := Lifecycle.on_player_death(world, character, "stone_warden", "2026-11-10")
	assert_true(res1.get("ok", false))
	assert_eq(character.status, "dead")
	assert_eq(world.cemetery.size(), 1)

	# Second death call for already-dead character must be idempotent
	var res2 := Lifecycle.on_player_death(world, character, "other_cause", "2026-11-11")
	assert_true(res2.get("ok", false), "Second call should return ok")
	assert_eq(character.status, "dead")
	assert_eq(world.cemetery.size(), 1, "Cemetery should still have only 1 entry")
	assert_eq(world.cemetery[0]["cause"], "stone_warden", "Original cause should be preserved")


func test_item_reowning_including_equipped() -> void:
	var world := WorldState.new()
	var inv := Inventory.new(_item_db)
	world.inventory = inv

	var char_id := "char_warrior"
	var char_owner := "character:" + char_id

	# Create bag item, weapon item, armor item
	var bag_item := inv.create("iron_sword", char_owner)
	var weapon_item := inv.create("iron_sword", char_owner)
	var armor_item := inv.create("leather_vest", char_owner)
	assert_gt(bag_item, 0)
	assert_gt(weapon_item, 0)
	assert_gt(armor_item, 0)

	# Equip weapon and armor
	assert_true(inv.equip(char_owner, weapon_item))
	assert_true(inv.equip(char_owner, armor_item))
	assert_eq(inv.get_equipped(char_owner, "weapon"), weapon_item)
	assert_eq(inv.get_equipped(char_owner, "armor"), armor_item)
	assert_eq(inv.items_of(char_owner).size(), 3)

	var character := CharacterState.new()
	character.id = char_id
	character.name = "Warrior"
	character.status = "alive"

	var res := Lifecycle.on_player_death(world, character, "cavern_beast", "2026-11-10")
	assert_true(res.get("ok", false))

	# All character equipment should be cleared
	assert_eq(inv.get_all_equipped(char_owner), {}, "Character equipment must be empty")
	# Character should own 0 items
	assert_eq(inv.items_of(char_owner), [], "Character should own 0 items")

	# Merchant floor1_smith should now own all 3 items
	var merchant_items := inv.items_of("merchant:floor1_smith")
	assert_eq(merchant_items.size(), 3, "Merchant floor1_smith should own all 3 transferred items")
	assert_true(bag_item in merchant_items, "Merchant must have bag item")
	assert_true(weapon_item in merchant_items, "Merchant must have weapon item")
	assert_true(armor_item in merchant_items, "Merchant must have armor item")

	# WorldState helper get_stock should match
	assert_eq(world.get_stock("floor1_smith"), merchant_items)


func test_flags_and_progression_persist_unchanged() -> void:
	var world := WorldState.new()
	world.inventory = Inventory.new(_item_db)
	world.killed_enemies = 88
	world.bosses_defeated = ["boss_alpha", "boss_beta"]
	world.flags = {"gate_unlocked": true, "rare_chest_found": true}

	var character := CharacterState.new()
	character.id = "char_scout"
	character.name = "Scout"
	character.status = "alive"

	var res := Lifecycle.on_player_death(world, character, "trap", "2026-11-10")
	assert_true(res.get("ok", false))

	assert_eq(world.killed_enemies, 88, "killed_enemies should remain unchanged")
	assert_eq(world.bosses_defeated, ["boss_alpha", "boss_beta"], "bosses_defeated should remain unchanged")
	assert_eq(world.flags.get("gate_unlocked"), true, "flags should remain unchanged")
	assert_eq(world.flags.get("rare_chest_found"), true, "flags should remain unchanged")


func test_dead_not_playable() -> void:
	var world := WorldState.new()
	world.inventory = Inventory.new(_item_db)
	_store.save_world("slot_test", world)

	var char_alive := CharacterState.new()
	char_alive.id = "alive_1"
	char_alive.name = "Living Hero"
	char_alive.status = "alive"
	char_alive.stats = Stats.new(100.0, 10.0, 2.0, 1.5, 1.0, 5.0)
	char_alive.position = [1.0, 2.0]
	_store.save_character("slot_test", char_alive)

	var char_dead := CharacterState.new()
	char_dead.id = "dead_1"
	char_dead.name = "Fallen Hero"
	char_dead.status = "dead"
	char_dead.stats = Stats.new(100.0, 10.0, 2.0, 1.5, 1.0, 5.0)
	char_dead.position = [1.0, 2.0]
	_store.save_character("slot_test", char_dead)

	# load_playable on living character succeeds
	var play_alive := Lifecycle.load_playable(_store, "slot_test", "alive_1", _item_db)
	assert_true(play_alive.get("ok", false), "Living character should load as playable")
	assert_not_null(play_alive.get("value"), "Living character value must not be null")

	# load_playable on dead character fails with clear error
	var play_dead := Lifecycle.load_playable(_store, "slot_test", "dead_1", _item_db)
	assert_false(play_dead.get("ok", true), "Dead character must not load as playable")
	assert_null(play_dead.get("value"), "Dead character value must be null")
	var err_msg: String = str(play_dead.get("error", ""))
	assert_true(err_msg.contains("dead") or err_msg.contains("playable"), "Error message should mention dead or playable: %s" % err_msg)

	# Regular load_character still loads dead character fine (read-only inspect)
	var load_regular := _store.load_character("slot_test", "dead_1", _item_db)
	assert_true(load_regular.get("ok", false), "Regular load_character should still load dead character file")
	var loaded_char: CharacterState = load_regular.get("value")
	assert_not_null(loaded_char)
	assert_eq(loaded_char.status, "dead")


func test_new_character_unique_ids() -> void:
	var world := WorldState.new()
	world.inventory = Inventory.new(_item_db)

	var app1 := {"hair": "blonde"}
	var app2 := {"hair": "dark"}
	var entry_tile := Vector2i(3, 2)

	var res1 := Lifecycle.new_character(world, "First", app1, entry_tile)
	var res2 := Lifecycle.new_character(world, "Second", app2, entry_tile)
	var res3 := Lifecycle.new_character(world, "Third", app1, [4.0, 5.0])

	assert_true(res1.get("ok", false), "First character creation should succeed")
	assert_true(res2.get("ok", false), "Second character creation should succeed")
	assert_true(res3.get("ok", false), "Third character creation should succeed")

	var c1: CharacterState = res1.get("value")
	var c2: CharacterState = res2.get("value")
	var c3: CharacterState = res3.get("value")

	assert_not_null(c1)
	assert_not_null(c2)
	assert_not_null(c3)

	assert_ne(c1.id, c2.id, "Characters must have distinct IDs")
	assert_ne(c2.id, c3.id, "Characters must have distinct IDs")
	assert_ne(c1.id, c3.id, "Characters must have distinct IDs")

	assert_eq(c1.status, "alive", "New character must be alive")
	assert_eq(c1.level, 1, "New character must be level 1")
	assert_eq(c1.xp, 0, "New character must have 0 xp")
	assert_eq(c1.zone, "floor1", "New character zone must be floor1")
	assert_eq(c1.position, [3.0, 2.0], "New character position must match entry tile")
	assert_eq(c3.position, [4.0, 5.0], "Custom entry position must be respected")

	assert_not_null(c1.stats, "New character stats must not be null")
	assert_gt(c1.stats.max_hp, 0.0, "New character max_hp must be > 0")


func test_new_character_avoids_existing_ids_in_store() -> void:
	var world := WorldState.new()
	world.inventory = Inventory.new(_item_db)
	_store.save_world("slot_test", world)

	# Pre-save char_1 to disk
	var pre_char := CharacterState.new()
	pre_char.id = "char_1"
	pre_char.name = "PreExisting"
	pre_char.status = "dead"
	pre_char.stats = Stats.new(100.0, 10.0, 2.0, 1.5, 1.0, 5.0)
	pre_char.position = [0.0, 0.0]
	_store.save_character("slot_test", pre_char)

	# Reset world counter to 1
	world.flags["next_character_id"] = 1

	var res_new := Lifecycle.new_character(world, "Fresh", {}, null, _store, "slot_test")
	assert_true(res_new.get("ok", false), "new_character should succeed")
	var c_new: CharacterState = res_new.get("value")
	assert_not_null(c_new)
	assert_ne(c_new.id, "char_1", "new_character should avoid collision with existing char_1 in store")
	assert_eq(c_new.id, "char_2")


func test_sim_death_event_helper() -> void:
	var world := WorldState.new()
	world.inventory = Inventory.new(_item_db)

	var character := CharacterState.new()
	character.id = "char_sim"
	character.name = "SimHero"
	character.status = "alive"

	# Construct a death event
	var death_event := {
		"type": "death",
		"tick": 42,
		"target": 1,
		"source": "ash_stalker"
	}

	var res := Lifecycle.on_player_death_event(death_event, world, character, "2026-11-10")
	assert_true(res.get("ok", false), "on_player_death_event should succeed")
	assert_eq(character.status, "dead")
	assert_eq(world.cemetery.size(), 1)
	assert_eq(world.cemetery[0]["cause"], "ash_stalker")


func test_sim_death_event_resolves_world_sim_entity_type() -> void:
	var world := WorldState.new()
	world.inventory = Inventory.new(_item_db)

	var character := CharacterState.new()
	character.id = "char_sim2"
	character.name = "SimHero2"
	character.status = "alive"

	var sim := WorldSim.new(null, _registry)
	var enemy := Entity.new(2, "enemy", Vector2(1, 1), 2.0, 50.0)
	enemy.enemy_type_id = "stone_warden"
	sim.entities[2] = enemy

	var death_event := {
		"type": "death",
		"tick": 50,
		"target": 1,
		"source": 2
	}

	var res := Lifecycle.on_player_death_event(death_event, world, character, "2026-11-10", null, "", sim, 1)
	assert_true(res.get("ok", false))
	assert_eq(character.status, "dead")
	assert_eq(world.cemetery.size(), 1)
	assert_eq(world.cemetery[0]["cause"], "stone_warden", "Cause should be resolved from killer entity's enemy_type_id")


class MockFailingStore extends SaveStore:
	var fail_world: bool = false
	var fail_character: bool = false

	func save_world(slot: String, world_state: WorldState) -> Dictionary:
		if fail_world:
			return {
				"ok": false,
				"error": "simulated world save failure",
				"value": null
			}
		return super.save_world(slot, world_state)

	func save_character(slot: String, character_state: CharacterState) -> Dictionary:
		if fail_character:
			return {
				"ok": false,
				"error": "simulated character save failure",
				"value": null
			}
		return super.save_character(slot, character_state)


func test_death_world_save_failure_and_retry_recovers() -> void:
	var mock_store := MockFailingStore.new(TEST_ROOT, _item_db)
	var world := WorldState.new()
	var inv := Inventory.new(_item_db)
	world.inventory = inv

	var char_id := "char_p1"
	var char_owner := "character:" + char_id
	var sword_uid := inv.create("iron_sword", char_owner)
	assert_gt(sword_uid, 0)
	assert_true(inv.equip(char_owner, sword_uid))

	var character := CharacterState.new()
	character.id = char_id
	character.name = "FailWorldHero"
	character.status = "alive"
	character.level = 5
	character.zone = "floor1"
	character.stats = Stats.new(100.0, 10.0, 2.0, 1.5, 1.0, 5.0)

	# Initial clean save to disk
	var sw_init := mock_store.save_world("slot_fail_w", world)
	var sc_init := mock_store.save_character("slot_fail_w", character)
	assert_true(sw_init.get("ok", false))
	assert_true(sc_init.get("ok", false))

	# First death attempt: world save fails
	mock_store.fail_world = true
	var res1 := Lifecycle.on_player_death(world, character, "boss_slam", "2026-11-10", mock_store, "slot_fail_w")
	assert_false(res1.get("ok", true), "Death should report failure when world save fails")
	assert_eq(res1.get("error"), "simulated world save failure")

	# Character was saved dead first on disk!
	var fresh_store := SaveStore.new(TEST_ROOT, _item_db)
	var char_on_disk := fresh_store.load_character("slot_fail_w", char_id, _item_db)
	assert_true(char_on_disk.get("ok", false))
	var c_disk: CharacterState = char_on_disk.get("value")
	assert_eq(c_disk.status, "dead", "Character on disk must already be dead so it cannot be loaded as playable")

	# Dead character cannot be loaded as playable even after partial failure
	var play_res := Lifecycle.load_playable(fresh_store, "slot_fail_w", char_id, _item_db)
	assert_false(play_res.get("ok", true))

	# Retry death flow with working store
	mock_store.fail_world = false
	var res2 := Lifecycle.on_player_death(world, character, "boss_slam", "2026-11-10", mock_store, "slot_fail_w")
	assert_true(res2.get("ok", false), "Retry death flow should succeed")

	# Verify final disk state: status dead, exactly one cemetery entry, all items on merchant
	var final_store := SaveStore.new(TEST_ROOT, _item_db)
	var final_char_res := final_store.load_character("slot_fail_w", char_id, _item_db)
	assert_true(final_char_res.get("ok", false))
	var final_char: CharacterState = final_char_res.get("value")
	assert_eq(final_char.status, "dead")

	var final_world_res := final_store.load_world("slot_fail_w", _item_db)
	assert_true(final_world_res.get("ok", false))
	var final_world: WorldState = final_world_res.get("value")
	assert_eq(final_world.cemetery.size(), 1, "Exactly one cemetery entry must exist on disk")
	assert_eq(final_world.cemetery[0]["character_id"], char_id)
	assert_eq(final_world.cemetery[0]["cause"], "boss_slam")

	assert_eq(final_world.inventory.items_of(char_owner), [], "Character must own 0 items on disk")
	assert_eq(final_world.inventory.get_all_equipped(char_owner), {}, "Character equipment must be empty on disk")
	var merchant_items := final_world.inventory.items_of("merchant:floor1_smith")
	assert_eq(merchant_items, [sword_uid], "Merchant must own character item on disk")


func test_death_character_save_failure_and_retry_recovers() -> void:
	var mock_store := MockFailingStore.new(TEST_ROOT, _item_db)
	var world := WorldState.new()
	var inv := Inventory.new(_item_db)
	world.inventory = inv

	var char_id := "char_p2"
	var char_owner := "character:" + char_id
	var vest_uid := inv.create("leather_vest", char_owner)
	assert_gt(vest_uid, 0)
	assert_true(inv.equip(char_owner, vest_uid))

	var character := CharacterState.new()
	character.id = char_id
	character.name = "FailCharHero"
	character.status = "alive"
	character.level = 4
	character.zone = "floor1"
	character.stats = Stats.new(100.0, 10.0, 2.0, 1.5, 1.0, 5.0)

	var sw_init := mock_store.save_world("slot_fail_c", world)
	var sc_init := mock_store.save_character("slot_fail_c", character)
	assert_true(sw_init.get("ok", false))
	assert_true(sc_init.get("ok", false))

	# Character save fails
	mock_store.fail_character = true
	var res1 := Lifecycle.on_player_death(world, character, "poison_mist", "2026-11-10", mock_store, "slot_fail_c")
	assert_false(res1.get("ok", true), "Death should report failure when character save fails")
	assert_eq(res1.get("error"), "simulated character save failure")

	# Retry with working store
	mock_store.fail_character = false
	var res2 := Lifecycle.on_player_death(world, character, "poison_mist", "2026-11-10", mock_store, "slot_fail_c")
	assert_true(res2.get("ok", false), "Retry death flow should succeed")

	# Verify final disk state
	var final_store := SaveStore.new(TEST_ROOT, _item_db)
	var final_char_res := final_store.load_character("slot_fail_c", char_id, _item_db)
	assert_true(final_char_res.get("ok", false))
	var final_char: CharacterState = final_char_res.get("value")
	assert_eq(final_char.status, "dead")

	var final_world_res := final_store.load_world("slot_fail_c", _item_db)
	assert_true(final_world_res.get("ok", false))
	var final_world: WorldState = final_world_res.get("value")
	assert_eq(final_world.cemetery.size(), 1, "Exactly one cemetery entry must exist on disk")
	assert_eq(final_world.cemetery[0]["character_id"], char_id)
	assert_eq(final_world.cemetery[0]["cause"], "poison_mist")

	assert_eq(final_world.inventory.items_of(char_owner), [])
	assert_eq(final_world.inventory.get_all_equipped(char_owner), {})
	assert_eq(final_world.inventory.items_of("merchant:floor1_smith"), [vest_uid])


func test_death_invalid_merchant_id_leaves_items_untouched() -> void:
	var world := WorldState.new()
	var inv := Inventory.new(_item_db)
	world.inventory = inv

	var char_id := "char_safe"
	var char_owner := "character:" + char_id
	var bag_uid := inv.create("iron_sword", char_owner)
	var eq_uid := inv.create("leather_vest", char_owner)
	assert_true(inv.equip(char_owner, eq_uid))

	var character := CharacterState.new()
	character.id = char_id
	character.name = "UntouchedHero"
	character.status = "alive"

	# Test with empty suffix "merchant:"
	var res1 := Lifecycle.on_player_death(world, character, "trap", "2026-11-10", _store, "slot_test", "merchant:")
	assert_false(res1.get("ok", true), "Invalid merchant id 'merchant:' must return ok:false")
	assert_eq(inv.items_of(char_owner).size(), 2, "Items must remain owned by character")
	assert_eq(inv.get_equipped(char_owner, "armor"), eq_uid, "Equipped item must remain equipped")
	assert_eq(inv.items_of("merchant:floor1_smith").size(), 0)

	# Test with "invalid"
	var res2 := Lifecycle.on_player_death(world, character, "trap", "2026-11-10", _store, "slot_test", "invalid")
	assert_false(res2.get("ok", true), "Invalid merchant id 'invalid' must return ok:false")
	assert_eq(inv.items_of(char_owner).size(), 2, "Items must remain untouched")
	assert_eq(inv.get_equipped(char_owner, "armor"), eq_uid, "Equipped item must remain equipped")

	# Test with wrong owner prefix "character:someone"
	var res3 := Lifecycle.on_player_death(world, character, "trap", "2026-11-10", _store, "slot_test", "character:someone")
	assert_false(res3.get("ok", true), "Invalid merchant prefix must return ok:false")
	assert_eq(inv.items_of(char_owner).size(), 2, "Items must remain untouched")


func test_new_character_validations() -> void:
	var world := WorldState.new()
	world.inventory = Inventory.new(_item_db)

	# Null world
	var res_nil := Lifecycle.new_character(null, "Alden", {})
	assert_false(res_nil.get("ok", true), "Null world must fail")
	assert_true(str(res_nil.get("error")).contains("world"))
	assert_null(res_nil.get("value"))

	# Empty name
	var res_empty := Lifecycle.new_character(world, "", {})
	assert_false(res_empty.get("ok", true), "Empty name must fail")
	assert_true(str(res_empty.get("error")).contains("name"))
	assert_null(res_empty.get("value"))

	# Whitespace name
	var res_spaces := Lifecycle.new_character(world, "   ", {})
	assert_false(res_spaces.get("ok", true), "Whitespace name must fail")
	assert_true(str(res_spaces.get("error")).contains("name"))
	assert_null(res_spaces.get("value"))


func test_new_character_save_failures_and_counter_rollback() -> void:
	var mock_store := MockFailingStore.new(TEST_ROOT, _item_db)
	var world := WorldState.new()
	world.inventory = Inventory.new(_item_db)
	world.flags["next_character_id"] = 10

	var save_init := mock_store.save_world("slot_fail_new", world)
	assert_true(save_init.get("ok", false))

	# Character save failure
	mock_store.fail_character = true
	var res1 := Lifecycle.new_character(world, "FailedChar", {}, null, mock_store, "slot_fail_new")
	assert_false(res1.get("ok", true), "new_character must fail when character save fails")
	assert_eq(res1.get("error"), "simulated character save failure")
	assert_null(res1.get("value"))
	assert_eq(world.flags.get("next_character_id"), 10, "Counter must not be bumped in memory on character save failure")

	var disk_world_res := mock_store.load_world("slot_fail_new", _item_db)
	assert_true(disk_world_res.get("ok", false))
	var disk_world: WorldState = disk_world_res.get("value")
	assert_eq(disk_world.flags.get("next_character_id"), 10, "Counter must not be bumped on disk")

	# World save failure
	mock_store.fail_character = false
	mock_store.fail_world = true
	var res2 := Lifecycle.new_character(world, "FailedChar2", {}, null, mock_store, "slot_fail_new")
	assert_false(res2.get("ok", true), "new_character must fail when world save fails")
	assert_eq(res2.get("error"), "simulated world save failure")
	assert_null(res2.get("value"))
	assert_eq(world.flags.get("next_character_id"), 10, "Counter must not be bumped in memory on world save failure")

	disk_world_res = mock_store.load_world("slot_fail_new", _item_db)
	assert_true(disk_world_res.get("ok", false))
	disk_world = disk_world_res.get("value")
	assert_eq(disk_world.flags.get("next_character_id"), 10, "Counter must not be bumped on disk")

	# Successful creation
	mock_store.fail_world = false
	var res3 := Lifecycle.new_character(world, "SuccessChar", {}, null, mock_store, "slot_fail_new")
	assert_true(res3.get("ok", false), "new_character must succeed when saves succeed")
	var cs: CharacterState = res3.get("value")
	assert_not_null(cs)
	assert_eq(cs.id, "char_10")
	assert_eq(world.flags.get("next_character_id"), 11, "Counter must be bumped after successful save")

	disk_world_res = mock_store.load_world("slot_fail_new", _item_db)
	assert_true(disk_world_res.get("ok", false))
	disk_world = disk_world_res.get("value")
	assert_eq(disk_world.flags.get("next_character_id"), 11, "Counter on disk must be bumped")


func test_create_character_instance_method() -> void:
	var lc := Lifecycle.new(_registry, _store, "slot_inst")
	var world := WorldState.new()
	world.inventory = Inventory.new(_item_db)

	var res := lc.create_character(world, "InstanceHero", {})
	assert_true(res.get("ok", false), "create_character should return ok:true")
	assert_true(res.get("value") is CharacterState, "create_character value must be CharacterState")
	var cs: CharacterState = res.get("value")
	assert_eq(cs.name, "InstanceHero")

