extends GutTest

var _registry: DataRegistry = null
var _item_db: ItemDB = null
var _inventory: Inventory = null


func before_each() -> void:
	_registry = DataRegistry.new()
	_registry.load_dir("res://data")
	_item_db = ItemDB.new(_registry)
	_inventory = Inventory.new(_item_db)


func test_real_items_json_loads_and_validates() -> void:
	var registry := DataRegistry.new()
	registry.load_dir("res://data")

	var val_errors := registry.validate()
	assert_eq(val_errors.size(), 0, "res://data should validate cleanly with items.json: %s" % str(val_errors))

	var db := ItemDB.new(registry)
	var item_ids := db.get_item_ids()

	assert_has(item_ids, "iron_sword")
	assert_has(item_ids, "hunting_bow")
	assert_has(item_ids, "leather_vest")
	assert_has(item_ids, "iron_plate")
	assert_has(item_ids, "healing_draught")
	assert_gte(item_ids.size(), 5, "Should have at least 5 items")

	var sword := db.get_item("iron_sword")
	assert_eq(sword.get("type"), "weapon")
	assert_gt(float(sword.get("stats", {}).get("weapon_damage", 0.0)), 0.0)

	var bow := db.get_item("hunting_bow")
	assert_eq(bow.get("type"), "weapon")
	assert_gt(float(bow.get("stats", {}).get("weapon_damage", 0.0)), 0.0)

	var vest := db.get_item("leather_vest")
	assert_eq(vest.get("type"), "armor")
	assert_gte(float(vest.get("stats", {}).get("defense", -1.0)), 0.0)

	var potion := db.get_item("healing_draught")
	assert_eq(potion.get("type"), "consumable")
	assert_gt(float(potion.get("effects", {}).get("heal", 0.0)), 0.0)

	assert_true(db.has_loot_table("ash_stalker"))
	var lt := db.get_loot_table("ash_stalker")
	assert_true(lt.has("entries"))
	assert_gt((lt["entries"] as Array).size(), 0)


func test_loot_drop_and_pickup_and_invalid_pickup() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42

	# Drop table with 100% chance for test determinism
	var test_db := ItemDB.new()
	test_db.register_item({
		"id": "test_blade",
		"name": "Test Blade",
		"type": "weapon",
		"floor_tier": 1,
		"stats": {"weapon_damage": 7.0}
	})
	test_db.register_loot_table("test_mob", {
		"roll_count": 1,
		"entries": [{"item_id": "test_blade", "chance": 1.0}]
	})
	var inv := Inventory.new(test_db)

	var drops := Loot.roll("test_mob", "floor1", inv, rng)
	assert_eq(drops.size(), 1, "Should drop exactly one item")
	var uid := drops[0]
	assert_gt(uid, 0)
	assert_eq(inv.owner_of(uid), "ground:floor1", "Drop must be owned by ground:<zone>")

	# Pickup changes owner to character
	var pickup_ok := inv.pickup(uid, "character:1")
	assert_true(pickup_ok, "Pickup should succeed from ground")
	assert_eq(inv.owner_of(uid), "character:1", "Item owner should now be character:1")
	assert_has(inv.items_of("character:1"), uid)

	# Pickup of an item not on the ground fails
	var second_pickup := inv.pickup(uid, "character:2")
	assert_push_error_count(1, "Should push error when picking up item not on ground")
	assert_false(second_pickup, "Pickup of item not on ground should fail")
	assert_eq(inv.owner_of(uid), "character:1", "Owner remains character:1")

	# Drop returns item to ground
	var drop_ok := inv.drop(uid, "floor2")
	assert_true(drop_ok)
	assert_eq(inv.owner_of(uid), "ground:floor2")
	assert_does_not_have(inv.items_of("character:1"), uid)
	assert_has(inv.items_of("ground:floor2"), uid)


func test_equip_weapon_and_armor_affects_combat_damage() -> void:
	var base_stats := Stats.from_dict(_registry.get_balance("player"))
	var target_stats := Stats.from_dict(_registry.get_balance("enemy"))

	var base_damage := Combat.compute_damage(base_stats, target_stats, _registry)
	assert_gt(base_damage, 0.0)

	var sword_uid := _inventory.create("iron_sword", "character:1")
	assert_gt(sword_uid, 0)

	var equip_ok := _inventory.equip("character:1", sword_uid)
	assert_true(equip_ok, "Equipping owned weapon should succeed")
	assert_eq(_inventory.get_equipped("character:1", "weapon"), sword_uid)

	var equipped := _inventory.equipped_stats(base_stats, "character:1")
	assert_not_null(equipped)
	assert_eq(base_stats.weapon_damage, 5.0, "Base stats must not be mutated")
	assert_eq(equipped.weapon_damage, 8.0, "Equipped weapon damage should replace base")

	var equipped_damage := Combat.compute_damage(equipped, target_stats, _registry)
	assert_gt(equipped_damage, base_damage, "Equipped weapon should increase combat damage")
	assert_eq(equipped_damage - base_damage, 3.0, "Damage difference should equal (8.0 - 5.0) * atk_scale")

	# Equip armor and check defense
	var plate_uid := _inventory.create("iron_plate", "character:1")
	assert_gt(plate_uid, 0)
	assert_true(_inventory.equip("character:1", plate_uid))
	assert_eq(_inventory.get_equipped("character:1", "armor"), plate_uid)

	var equipped_with_armor := _inventory.equipped_stats(base_stats, "character:1")
	assert_eq(base_stats.defense, 2.0, "Base defense must not be mutated")
	assert_eq(equipped_with_armor.defense, 8.0, "Equipped armor defense (6.0) should be added to base (2.0)")

	# Enemy attacking player with armor should deal less damage
	var damage_against_unarmored := Combat.compute_damage(target_stats, base_stats, _registry)
	var damage_against_armored := Combat.compute_damage(target_stats, equipped_with_armor, _registry)
	assert_lt(damage_against_armored, damage_against_unarmored, "Armored player takes less damage")


func test_potion_heals_once_and_second_use_fails() -> void:
	var dummy_stats := Stats.new(100.0, 10.0, 0.0, 1.0, 1.0, 0.0)
	var dummy := Entity.new(1, "player", Vector2(0, 0), 4.0, 50.0, dummy_stats)
	assert_eq(dummy.hp, 50.0)
	assert_eq(dummy.stats.max_hp, 100.0)

	var potion_uid := _inventory.create("healing_draught", "character:1")
	assert_gt(potion_uid, 0)

	# First use heals 30 HP
	var first_use := _inventory.use(potion_uid, dummy)
	assert_true(first_use, "First use of potion should succeed")
	assert_eq(dummy.hp, 80.0, "Dummy HP should increase from 50 to 80")
	assert_true(_inventory.is_consumed(potion_uid))
	assert_eq(_inventory.owner_of(potion_uid), "consumed")

	# Second use must fail and not heal again
	var second_use := _inventory.use(potion_uid, dummy)
	assert_push_error_count(1, "Second use of consumed potion must push error")
	assert_false(second_use, "Second use of consumed potion must fail")
	assert_eq(dummy.hp, 80.0, "Dummy HP must not change on failed use")


func test_potion_healing_capped_at_max_hp() -> void:
	var dummy_stats := Stats.new(100.0, 10.0, 0.0, 1.0, 1.0, 0.0)
	var dummy := Entity.new(1, "player", Vector2(0, 0), 4.0, 90.0, dummy_stats)

	var potion_uid := _inventory.create("healing_draught", "character:1")
	var cap_use := _inventory.use(potion_uid, dummy)
	assert_true(cap_use)
	assert_eq(dummy.hp, 100.0, "Healing must not exceed max_hp (100.0)")


func test_potion_use_on_dead_entity_fails() -> void:
	var dummy_stats := Stats.new(100.0, 10.0, 0.0, 1.0, 1.0, 0.0)
	var dummy := Entity.new(1, "player", Vector2(0, 0), 4.0, 0.0, dummy_stats)
	dummy.dead = true

	var potion_uid := _inventory.create("healing_draught", "character:1")
	var dead_use := _inventory.use(potion_uid, dummy)
	assert_push_error_count(1, "Should push error when using potion on dead entity")
	assert_false(dead_use, "Cannot use potion on dead entity")
	assert_eq(dummy.hp, 0.0)


func test_uids_are_unique_across_many_items_and_owners() -> void:
	var seen_uids: Dictionary = {}
	var owners: Array[String] = [
		"character:1",
		"character:2",
		"merchant:alchemist",
		"container:chest_1",
		"ground:floor1",
		"ground:floor2"
	]
	var item_types: Array[String] = [
		"iron_sword",
		"hunting_bow",
		"leather_vest",
		"iron_plate",
		"healing_draught"
	]

	var total_items := 60
	for i in range(total_items):
		var owner: String = owners[i % owners.size()]
		var item_type: String = item_types[i % item_types.size()]
		var uid := _inventory.create(item_type, owner)
		assert_gt(uid, 0)
		assert_false(seen_uids.has(uid), "UID %d must be unique across entire store" % uid)
		seen_uids[uid] = owner
		assert_eq(_inventory.owner_of(uid), owner)

	assert_eq(seen_uids.size(), total_items, "All 60 items should have unique UIDs")

	# Test items_of consistency
	for owner: String in owners:
		var items := _inventory.items_of(owner)
		for uid: int in items:
			assert_eq(_inventory.owner_of(uid), owner)


func test_create_unknown_item_def_pushes_error() -> void:
	var bad_create := _inventory.create("nonexistent_def", "character:1")
	assert_push_error_count(1, "Unknown item def should push error")
	assert_eq(bad_create, -1)


func test_create_invalid_owner_pushes_error() -> void:
	var bad_owner := _inventory.create("iron_sword", "not_a_valid_owner")
	assert_push_error_count(1, "Invalid owner string should push error")
	assert_eq(bad_owner, -1)


func test_owner_of_unknown_uid_pushes_error() -> void:
	var bad_owner_query := _inventory.owner_of(999999)
	assert_push_error_count(1, "Unknown UID in owner_of should push error")
	assert_eq(bad_owner_query, "")


func test_transfer_unknown_uid_pushes_error() -> void:
	var bad_transfer := _inventory.transfer(999999, "character:1")
	assert_push_error_count(1, "Unknown UID in transfer should push error")
	assert_false(bad_transfer)


func test_equip_unknown_uid_pushes_error() -> void:
	var bad_equip_uid := _inventory.equip("character:1", 999999)
	assert_push_error_count(1, "Unknown UID in equip should push error")
	assert_false(bad_equip_uid)


func test_equip_unowned_item_pushes_error() -> void:
	var sword_uid := _inventory.create("iron_sword", "character:1")
	var bad_owner_equip := _inventory.equip("character:2", sword_uid)
	assert_push_error_count(1, "Equipping unowned item should push error")
	assert_false(bad_owner_equip)


func test_equip_consumable_pushes_error() -> void:
	var potion_uid := _inventory.create("healing_draught", "character:1")
	var bad_type_equip := _inventory.equip("character:1", potion_uid)
	assert_push_error_count(1, "Equipping consumable should push error")
	assert_false(bad_type_equip)


func test_use_unknown_uid_pushes_error() -> void:
	var dummy_stats := Stats.new(100.0, 10.0, 0.0, 1.0, 1.0, 0.0)
	var dummy := Entity.new(1, "player", Vector2(0, 0), 4.0, 50.0, dummy_stats)
	var bad_use := _inventory.use(999999, dummy)
	assert_push_error_count(1, "Unknown UID in use should push error")
	assert_false(bad_use)


func test_item_db_unknown_item_pushes_error() -> void:
	var bad_item := _item_db.get_item("nonexistent_item")
	assert_push_error_count(1, "Unknown item in get_item should push error")
	assert_true(bad_item.is_empty())


func test_item_db_unknown_loot_table_pushes_error() -> void:
	var bad_lt := _item_db.get_loot_table("nonexistent_enemy")
	assert_push_error_count(1, "Unknown enemy in get_loot_table should push error")
	assert_true(bad_lt.is_empty())


func test_loot_roll_unknown_enemy_pushes_error() -> void:
	var rng := RandomNumberGenerator.new()
	var bad_roll := Loot.roll("nonexistent_enemy", "floor1", _inventory, rng)
	assert_push_error_count(1, "Loot.roll with unknown enemy should push error")
	assert_eq(bad_roll.size(), 0)


func test_item_db_validation_rejects_malformed_definitions() -> void:
	assert_gt(ItemDB.validate_item({}).size(), 0)

	var bad_id: Dictionary = {
		"id": "Invalid-ID!", "name": "Bad", "type": "weapon", "floor_tier": 1,
		"stats": {"weapon_damage": 5.0}
	}
	assert_gt(ItemDB.validate_item(bad_id).size(), 0)

	var bad_type: Dictionary = {
		"id": "bad_type", "name": "Bad", "type": "magic_wand", "floor_tier": 1,
		"stats": {"weapon_damage": 5.0}
	}
	assert_gt(ItemDB.validate_item(bad_type).size(), 0)

	var bad_tier: Dictionary = {
		"id": "bad_tier", "name": "Bad", "type": "weapon", "floor_tier": 0,
		"stats": {"weapon_damage": 5.0}
	}
	assert_gt(ItemDB.validate_item(bad_tier).size(), 0)

	var bad_weapon_damage: Dictionary = {
		"id": "bad_wd", "name": "Bad", "type": "weapon", "floor_tier": 1,
		"stats": {"weapon_damage": -5.0}
	}
	assert_gt(ItemDB.validate_item(bad_weapon_damage).size(), 0)

	var bad_armor_defense: Dictionary = {
		"id": "bad_def", "name": "Bad", "type": "armor", "floor_tier": 1,
		"stats": {"defense": -2.0}
	}
	assert_gt(ItemDB.validate_item(bad_armor_defense).size(), 0)

	var bad_consumable: Dictionary = {
		"id": "bad_con", "name": "Bad", "type": "consumable", "floor_tier": 1,
		"effects": {"heal": -10.0}
	}
	assert_gt(ItemDB.validate_item(bad_consumable).size(), 0)

	# Loot table validation
	assert_gt(ItemDB.validate_loot_table({}).size(), 0)

	var bad_rolls: Dictionary = {
		"roll_count": 0,
		"entries": [{"item_id": "iron_sword", "chance": 0.5}]
	}
	assert_gt(ItemDB.validate_loot_table(bad_rolls).size(), 0)

	var bad_chance: Dictionary = {
		"roll_count": 1,
		"entries": [{"item_id": "iron_sword", "chance": 1.5}]
	}
	assert_gt(ItemDB.validate_loot_table(bad_chance).size(), 0)

	var bad_entries: Dictionary = {
		"roll_count": 1,
		"entries": []
	}
	assert_gt(ItemDB.validate_loot_table(bad_entries).size(), 0)

	var unknown_item_table: Dictionary = {
		"roll_count": 1,
		"entries": [{"item_id": "iron_sword", "chance": 0.5}]
	}
	assert_gt(ItemDB.validate_loot_table(unknown_item_table, []).size(), 0, "validate_loot_table with empty known_item_ids must reject entries")
	assert_eq(ItemDB.validate_loot_table(unknown_item_table, ["iron_sword"]).size(), 0, "validate_loot_table with known item_id must pass")


func test_register_invalid_item_pushes_error() -> void:
	var custom_db := ItemDB.new()
	var bad_id: Dictionary = {
		"id": "Invalid-ID!", "name": "Bad", "type": "weapon", "floor_tier": 1,
		"stats": {"weapon_damage": 5.0}
	}
	var reg_bad := custom_db.register_item(bad_id)
	assert_push_error_count(1, "register_item with invalid definition should push error")
	assert_false(reg_bad)


func test_register_invalid_loot_table_pushes_error() -> void:
	var custom_db := ItemDB.new()
	custom_db.register_item({
		"id": "iron_sword", "name": "Iron Sword", "type": "weapon", "floor_tier": 1,
		"stats": {"weapon_damage": 5.0}
	})
	var bad_rolls: Dictionary = {
		"roll_count": 0,
		"entries": [{"item_id": "iron_sword", "chance": 0.5}]
	}
	var reg_bad_lt := custom_db.register_loot_table("bad_mob", bad_rolls)
	assert_push_error_count(1, "register_loot_table with invalid definition should push error")
	assert_false(reg_bad_lt)


func test_register_loot_table_unknown_item_with_items_pushes_error() -> void:
	var bad_table: Dictionary = {
		"roll_count": 1,
		"entries": [{"item_id": "nonexistent_item_id", "chance": 0.5}]
	}
	var reg_bad_lt := _item_db.register_loot_table("bad_mob", bad_table)
	assert_push_error_count(1, "register_loot_table with unknown item_id should push error")
	assert_false(reg_bad_lt)
	assert_false(_item_db.has_loot_table("bad_mob"))


func test_register_loot_table_on_empty_item_db_pushes_error() -> void:
	var empty_db := ItemDB.new()
	var table: Dictionary = {
		"roll_count": 1,
		"entries": [{"item_id": "iron_sword", "chance": 0.5}]
	}
	var reg_bad_lt := empty_db.register_loot_table("bad_mob", table)
	assert_push_error_count(1, "register_loot_table on ItemDB with no items should push error")
	assert_false(reg_bad_lt)
	assert_false(empty_db.has_loot_table("bad_mob"))


func test_transfer_equipped_item_clears_slot_and_resets_stats() -> void:
	var base_stats := Stats.from_dict(_registry.get_balance("player"))
	var sword_uid := _inventory.create("iron_sword", "character:1")
	assert_gt(sword_uid, 0)

	var equip_ok := _inventory.equip("character:1", sword_uid)
	assert_true(equip_ok)
	assert_eq(_inventory.get_equipped("character:1", "weapon"), sword_uid)

	var equipped_stats := _inventory.equipped_stats(base_stats, "character:1")
	assert_gt(equipped_stats.weapon_damage, base_stats.weapon_damage)

	var transfer_ok := _inventory.transfer(sword_uid, "character:2")
	assert_true(transfer_ok)
	assert_eq(_inventory.owner_of(sword_uid), "character:2")
	assert_eq(_inventory.get_equipped("character:1", "weapon"), 0)

	var reset_stats := _inventory.equipped_stats(base_stats, "character:1")
	assert_eq(reset_stats.weapon_damage, base_stats.weapon_damage)
	assert_eq(reset_stats.defense, base_stats.defense)
	assert_eq(reset_stats.atk, base_stats.atk)
	assert_eq(reset_stats.max_hp, base_stats.max_hp)
	assert_eq(reset_stats.attack_range, base_stats.attack_range)
	assert_eq(reset_stats.attack_interval, base_stats.attack_interval)


func test_drop_equipped_item_clears_slot_and_resets_stats() -> void:
	var base_stats := Stats.from_dict(_registry.get_balance("player"))
	var sword_uid := _inventory.create("iron_sword", "character:1")
	assert_gt(sword_uid, 0)

	var equip_ok := _inventory.equip("character:1", sword_uid)
	assert_true(equip_ok)
	assert_eq(_inventory.get_equipped("character:1", "weapon"), sword_uid)

	var equipped_stats := _inventory.equipped_stats(base_stats, "character:1")
	assert_gt(equipped_stats.weapon_damage, base_stats.weapon_damage)

	var drop_ok := _inventory.drop(sword_uid, "floor1")
	assert_true(drop_ok)
	assert_eq(_inventory.owner_of(sword_uid), "ground:floor1")
	assert_eq(_inventory.get_equipped("character:1", "weapon"), 0)

	var reset_stats := _inventory.equipped_stats(base_stats, "character:1")
	assert_eq(reset_stats.weapon_damage, base_stats.weapon_damage)
	assert_eq(reset_stats.defense, base_stats.defense)
	assert_eq(reset_stats.atk, base_stats.atk)
	assert_eq(reset_stats.max_hp, base_stats.max_hp)
	assert_eq(reset_stats.attack_range, base_stats.attack_range)
	assert_eq(reset_stats.attack_interval, base_stats.attack_interval)


func test_deterministic_loot_rolls_with_seeded_rng() -> void:
	var rng1 := RandomNumberGenerator.new()
	rng1.seed = 987654321

	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 987654321

	var inv1 := Inventory.new(_item_db)
	var inv2 := Inventory.new(_item_db)

	var drops1: Array[String] = []
	for i in range(10):
		var rolled := Loot.roll("ash_stalker", "floor1", inv1, rng1)
		for uid in rolled:
			drops1.append(inv1.def_id_of(uid))

	var drops2: Array[String] = []
	for i in range(10):
		var rolled := Loot.roll("ash_stalker", "floor1", inv2, rng2)
		for uid in rolled:
			drops2.append(inv2.def_id_of(uid))

	assert_eq(drops1, drops2, "Seeded RNG must produce identical loot drops across separate instances")
	assert_gt(drops1.size(), 0, "Should have rolled some drops across 10 rolls")
