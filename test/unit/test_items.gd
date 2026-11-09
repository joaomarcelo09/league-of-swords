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
	var isolated_db := ItemDB.new()
	isolated_db.register_item({
		"id": "iron_sword",
		"name": "Iron Sword",
		"type": "weapon",
		"floor_tier": 1,
		"stats": {"weapon_damage": 8.0}
	})
	var bad_table: Dictionary = {
		"roll_count": 1,
		"entries": [{"item_id": "nonexistent_item_id", "chance": 0.5}]
	}
	var reg_bad_lt := isolated_db.register_loot_table("bad_mob", bad_table)
	assert_push_error_count(1, "register_loot_table with unknown item_id should push error")
	assert_false(reg_bad_lt)
	assert_false(isolated_db.has_loot_table("bad_mob"))


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


func test_use_enforces_acting_character_ownership() -> void:
	var dummy1_stats := Stats.new(100.0, 10.0, 0.0, 1.0, 1.0, 0.0)
	var dummy1 := Entity.new(1, "player", Vector2(0, 0), 4.0, 50.0, dummy1_stats)
	var dummy2_stats := Stats.new(100.0, 10.0, 0.0, 1.0, 1.0, 0.0)
	var dummy2 := Entity.new(2, "player", Vector2(0, 0), 4.0, 50.0, dummy2_stats)

	var potion_uid := _inventory.create("healing_draught", "character:1")
	assert_gt(potion_uid, 0)
	assert_eq(_inventory.owner_of(potion_uid), "character:1")

	# Wrong character owner attempting to use character:1's potion
	var wrong_use := _inventory.use(potion_uid, dummy2)
	assert_push_error_count(1, "Using item owned by another character must push error")
	assert_false(wrong_use, "Using item owned by another character must fail")
	assert_eq(dummy2.hp, 50.0, "Wrong owner HP must not change")
	assert_false(_inventory.is_consumed(potion_uid), "Item must not be consumed on failed owner check")
	assert_eq(_inventory.owner_of(potion_uid), "character:1", "Owner must remain character:1")

	# Correct character owner uses the potion
	var ok_use := _inventory.use(potion_uid, dummy1)
	assert_true(ok_use, "Acting character owning item can use it successfully")
	assert_eq(dummy1.hp, 80.0, "Dummy1 HP should increase from 50 to 80")
	assert_true(_inventory.is_consumed(potion_uid), "Item must now be consumed")
	assert_eq(_inventory.owner_of(potion_uid), "consumed")


func test_use_with_non_character_acting_owner_fails() -> void:
	var dummy1_stats := Stats.new(100.0, 10.0, 0.0, 1.0, 1.0, 0.0)
	var dummy1 := Entity.new(1, "player", Vector2(0, 0), 4.0, 50.0, dummy1_stats)
	var potion_uid := _inventory.create("healing_draught", "character:1")

	# Wrong owner via explicit non-character string parameter
	var bad_str_owner := _inventory.use(potion_uid, dummy1, "merchant:alchemist")
	assert_push_error_count(1, "Non-character acting owner must push error")
	assert_false(bad_str_owner)
	assert_eq(dummy1.hp, 50.0)
	assert_false(_inventory.is_consumed(potion_uid))


func test_loot_tables_json_separation() -> void:
	var registry := DataRegistry.new()
	registry.load_dir("res://data")

	# loot_tables must be in its own table, not inside items.json
	assert_true(registry.has_entry("loot_tables", "ash_stalker"), "ash_stalker should exist in loot_tables table")
	assert_false(registry.has_entry("items", "loot_tables"), "items table should not contain loot_tables entry")

	var db := ItemDB.new(registry)
	assert_true(db.has_loot_table("ash_stalker"), "ItemDB should load ash_stalker from loot_tables")
	var lt := db.get_loot_table("ash_stalker")
	assert_eq(lt.get("roll_count"), 1)
	assert_false(lt.has("rolls"), "loot_tables should not carry deprecated rolls alias")
	assert_true(lt.has("entries"))


func test_loot_table_validator_rejects_rolls_alias() -> void:
	var rolls_only_table: Dictionary = {
		"rolls": 1,
		"entries": [{"item_id": "iron_sword", "chance": 0.5}]
	}
	var val_errs := ItemDB.validate_loot_table(rolls_only_table, ["iron_sword"])
	assert_gt(val_errs.size(), 0, "validate_loot_table must reject table without 'roll_count'")
	var found_roll_err := false
	for err in val_errs:
		if "roll_count" in err:
			found_roll_err = true
			break
	assert_true(found_roll_err, "Expected error mentioning missing 'roll_count'")


func test_loot_roll_rejects_missing_roll_count() -> void:
	var isolated_db := ItemDB.new()
	isolated_db.register_item({
		"id": "iron_sword", "name": "Iron Sword", "type": "weapon", "floor_tier": 1,
		"stats": {"weapon_damage": 8.0}
	})
	isolated_db._loot_tables["bad_mob_no_rolls"] = {
		"entries": [{"item_id": "iron_sword", "chance": 1.0}]
	}
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var drops := Loot.roll("bad_mob_no_rolls", "floor1", _inventory, rng, isolated_db)
	assert_push_error_count(1, "Loot.roll without roll_count must push error")
	assert_eq(drops.size(), 0)


func test_loot_roll_rejects_missing_entries() -> void:
	var isolated_db := ItemDB.new()
	isolated_db.register_item({
		"id": "iron_sword", "name": "Iron Sword", "type": "weapon", "floor_tier": 1,
		"stats": {"weapon_damage": 8.0}
	})
	isolated_db._loot_tables["bad_mob_no_entries"] = {
		"roll_count": 1
	}
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var drops := Loot.roll("bad_mob_no_entries", "floor1", _inventory, rng, isolated_db)
	assert_push_error_count(1, "Loot.roll without entries must push error")
	assert_eq(drops.size(), 0)


func test_loot_roll_rejects_entry_missing_chance() -> void:
	var isolated_db := ItemDB.new()
	isolated_db.register_item({
		"id": "iron_sword", "name": "Iron Sword", "type": "weapon", "floor_tier": 1,
		"stats": {"weapon_damage": 8.0}
	})
	isolated_db._loot_tables["bad_mob_entry_no_chance"] = {
		"roll_count": 1,
		"entries": [{"item_id": "iron_sword"}]
	}
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var drops := Loot.roll("bad_mob_entry_no_chance", "floor1", _inventory, rng, isolated_db)
	assert_push_error_count(1, "Loot.roll with entry missing chance must push error")
	assert_eq(drops.size(), 0)


func test_create_requires_non_null_item_db() -> void:
	var null_db_inv := Inventory.new(null)
	var res := null_db_inv.create("iron_sword", "character:1")
	assert_push_error_count(1, "Inventory.create with null item_db must push error")
	assert_eq(res, 0, "Inventory.create with null item_db must return 0")


func test_inventory_roundtrip_to_dict_from_dict() -> void:
	var inv := Inventory.new(_item_db)
	var sword_uid := inv.create("iron_sword", "character:1")
	var vest_uid := inv.create("leather_vest", "character:1")
	var potion_uid := inv.create("healing_draught", "character:1")
	var ground_uid := inv.create("hunting_bow", "ground:floor1")
	assert_gt(sword_uid, 0)
	assert_gt(vest_uid, 0)
	assert_gt(potion_uid, 0)
	assert_gt(ground_uid, 0)

	assert_true(inv.equip("character:1", sword_uid))
	assert_true(inv.equip("character:1", vest_uid))

	var dict := inv.to_dict()
	assert_true(dict.has("next_uid"))
	assert_true(dict.has("items"))
	assert_true(dict.has("equipment"))
	assert_gte(dict["next_uid"], 5)

	# Direct from_dict roundtrip
	var restored := Inventory.from_dict(dict, _item_db)
	assert_not_null(restored, "from_dict should successfully restore valid inventory")
	assert_eq(restored.to_dict(), dict, "Roundtrip to_dict() must match original")

	assert_eq(restored.owner_of(sword_uid), "character:1")
	assert_eq(restored.owner_of(ground_uid), "ground:floor1")
	assert_eq(restored.get_equipped("character:1", "weapon"), sword_uid)
	assert_eq(restored.get_equipped("character:1", "armor"), vest_uid)

	var base_stats := Stats.from_dict(_registry.get_balance("player"))
	var eq_stats := restored.equipped_stats(base_stats, "character:1")
	assert_eq(eq_stats.weapon_damage, 8.0)
	assert_eq(eq_stats.defense, 5.0)

	# JSON serialization roundtrip
	var json_str := JSON.stringify(dict)
	var json_parsed: Variant = JSON.parse_string(json_str)
	assert_true(json_parsed is Dictionary)
	var from_json := Inventory.from_dict(json_parsed, _item_db)
	assert_not_null(from_json, "from_dict should restore from parsed JSON with string keys")
	assert_eq(from_json.to_dict(), dict, "JSON roundtrip should match original dict")


func test_from_dict_rejects_empty_dict() -> void:
	var res := Inventory.from_dict({}, _item_db)
	assert_push_error_count(1, "Empty dict should push error")
	assert_null(res)


func test_from_dict_rejects_missing_next_uid() -> void:
	var res := Inventory.from_dict({"items": {}, "equipment": {}}, _item_db)
	assert_push_error_count(1, "Missing next_uid should push error")
	assert_null(res)


func test_from_dict_rejects_missing_items() -> void:
	var res := Inventory.from_dict({"next_uid": 1, "equipment": {}}, _item_db)
	assert_push_error_count(1, "Missing items should push error")
	assert_null(res)


func test_from_dict_rejects_missing_equipment() -> void:
	var res := Inventory.from_dict({"next_uid": 1, "items": {}}, _item_db)
	assert_push_error_count(1, "Missing equipment should push error")
	assert_null(res)


func test_from_dict_rejects_item_uid_gte_next_uid() -> void:
	var bad_next_uid: Dictionary = {
		"next_uid": 1,
		"items": {
			1: {"uid": 1, "def_id": "iron_sword", "owner": "character:1"}
		},
		"equipment": {}
	}
	var res := Inventory.from_dict(bad_next_uid, _item_db)
	assert_push_error_count(1, "item uid >= next_uid should push error")
	assert_null(res)


func test_from_dict_rejects_unknown_def_id() -> void:
	var bad_def: Dictionary = {
		"next_uid": 2,
		"items": {
			1: {"uid": 1, "def_id": "nonexistent_item_id", "owner": "character:1"}
		},
		"equipment": {}
	}
	var res := Inventory.from_dict(bad_def, _item_db)
	assert_push_error_count(1, "Unknown item def_id should push error")
	assert_null(res)


func test_from_dict_rejects_invalid_owner() -> void:
	var bad_owner: Dictionary = {
		"next_uid": 2,
		"items": {
			1: {"uid": 1, "def_id": "iron_sword", "owner": "invalid_owner_format"}
		},
		"equipment": {}
	}
	var res := Inventory.from_dict(bad_owner, _item_db)
	assert_push_error_count(1, "Invalid item owner should push error")
	assert_null(res)


func test_from_dict_rejects_unowned_equipment() -> void:
	var unowned_eq: Dictionary = {
		"next_uid": 2,
		"items": {
			1: {"uid": 1, "def_id": "iron_sword", "owner": "character:2"}
		},
		"equipment": {
			"character:1": {"weapon": 1}
		}
	}
	var res := Inventory.from_dict(unowned_eq, _item_db)
	assert_push_error_count(1, "Equipping unowned item should push error")
	assert_null(res)


func test_from_dict_rejects_equipment_slot_mismatch() -> void:
	var mismatch_eq: Dictionary = {
		"next_uid": 2,
		"items": {
			1: {"uid": 1, "def_id": "iron_sword", "owner": "character:1"}
		},
		"equipment": {
			"character:1": {"armor": 1}
		}
	}
	var res := Inventory.from_dict(mismatch_eq, _item_db)
	assert_push_error_count(1, "Equipping weapon into armor slot should push error")
	assert_null(res)


func test_isolated_loot_table_bad_rolls_pushes_error() -> void:
	var custom_db := ItemDB.new()
	custom_db.register_item({
		"id": "test_sword",
		"name": "Test Sword",
		"type": "weapon",
		"floor_tier": 1,
		"stats": {"weapon_damage": 5.0}
	})

	var bad_rolls: Dictionary = {
		"roll_count": 0,
		"entries": [{"item_id": "test_sword", "chance": 0.5}]
	}
	var reg1 := custom_db.register_loot_table("bad_mob1", bad_rolls)
	assert_push_error_count(1, "register_loot_table with bad rolls should push error")
	assert_false(reg1)
	assert_false(custom_db.has_loot_table("bad_mob1"))
	assert_false(_item_db.has_loot_table("bad_mob1"))


func test_isolated_loot_table_bad_chance_pushes_error() -> void:
	var custom_db := ItemDB.new()
	custom_db.register_item({
		"id": "test_sword",
		"name": "Test Sword",
		"type": "weapon",
		"floor_tier": 1,
		"stats": {"weapon_damage": 5.0}
	})

	var bad_chance: Dictionary = {
		"roll_count": 1,
		"entries": [{"item_id": "test_sword", "chance": 1.5}]
	}
	var reg2 := custom_db.register_loot_table("bad_mob2", bad_chance)
	assert_push_error_count(1, "register_loot_table with bad chance should push error")
	assert_false(reg2)
	assert_false(custom_db.has_loot_table("bad_mob2"))
	assert_false(_item_db.has_loot_table("bad_mob2"))
