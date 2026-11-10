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


func _write_raw_file(rel_path: String, content: String) -> void:
	var full_path := TEST_ROOT.path_join(rel_path)
	var dir_path := full_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
	var f := FileAccess.open(full_path, FileAccess.WRITE)
	if f != null:
		f.store_string(content)
		f.close()


func test_world_round_trip_equals() -> void:
	var world := WorldState.new()
	world.seed = 4242
	world.floors_unlocked = 3
	world.bosses_defeated = ["cavern_beast", "shadow_stalker"]
	world.cemetery = [
		{
			"name": "Alden",
			"level": 12,
			"zone": "boss_chamber",
			"cause": "stone_warden",
			"date": "2026-11-10",
			"appearance": {"body": "body_1", "hair": "blue"}
		}
	]
	world.killed_enemies = 123
	world.flags = {"first_blood": true, "met_guide": true}

	var inv := Inventory.new(_item_db)
	var smith_item := inv.create("iron_sword", "merchant:floor1_smith")
	var chest_item := inv.create("leather_vest", "container:chest_1")
	assert_gt(smith_item, 0)
	assert_gt(chest_item, 0)
	world.inventory = inv

	var save_res := _store.save_world("slot_1", world)
	assert_true(save_res.get("ok", false), "save_world should succeed: %s" % str(save_res.get("error")))

	var load_res := _store.load_world("slot_1")
	assert_true(load_res.get("ok", false), "load_world should succeed: %s" % str(load_res.get("error")))

	var loaded: WorldState = load_res.get("value")
	assert_not_null(loaded, "Loaded world should not be null")
	assert_true(loaded.equals(world), "Loaded world should equal original world via equals()")
	assert_eq(loaded.to_dict(), world.to_dict(), "Loaded world to_dict() should equal original")
	assert_eq(loaded.seed, 4242)
	assert_eq(loaded.floors_unlocked, 3)
	assert_eq(loaded.bosses_defeated, ["cavern_beast", "shadow_stalker"])
	assert_eq(loaded.cemetery.size(), 1)
	assert_eq(loaded.cemetery[0]["name"], "Alden")
	assert_eq(loaded.killed_enemies, 123)
	assert_eq(loaded.flags["first_blood"], true)
	assert_eq(loaded.get_stock("floor1_smith"), [smith_item])
	assert_eq(loaded.get_container_items("chest_1"), [chest_item])


func test_character_round_trip_equals() -> void:
	var char_state := CharacterState.new()
	char_state.id = "rowan"
	char_state.status = "alive"
	char_state.name = "Rowan"
	char_state.appearance = {"body": "male_1", "hair": "black_short"}
	char_state.level = 7
	char_state.xp = 2400
	char_state.stats = Stats.new(150.0, 20.0, 5.0, 1.5, 0.8, 12.0)
	char_state.zone = "floor1_town"
	char_state.position = [14.5, 22.0]

	var save_res := _store.save_character("slot_1", char_state)
	assert_true(save_res.get("ok", false), "save_character should succeed: %s" % str(save_res.get("error")))

	var load_res := _store.load_character("slot_1", "rowan")
	assert_true(load_res.get("ok", false), "load_character should succeed: %s" % str(load_res.get("error")))

	var loaded: CharacterState = load_res.get("value")
	assert_not_null(loaded, "Loaded character should not be null")
	assert_true(loaded.equals(char_state), "Loaded character should equal original character via equals()")
	assert_eq(loaded.to_dict(), char_state.to_dict(), "Loaded character to_dict() should equal original")
	assert_eq(loaded.id, "rowan")
	assert_eq(loaded.status, "alive")
	assert_eq(loaded.name, "Rowan")
	assert_eq(loaded.appearance, {"body": "male_1", "hair": "black_short"})
	assert_eq(loaded.level, 7)
	assert_eq(loaded.xp, 2400)
	assert_eq(loaded.stats.max_hp, 150.0)
	assert_eq(loaded.stats.atk, 20.0)
	assert_eq(loaded.stats.defense, 5.0)
	assert_eq(loaded.stats.weapon_damage, 12.0)
	assert_eq(loaded.zone, "floor1_town")
	assert_eq(loaded.position, [14.5, 22.0])


func test_dead_character_round_trip() -> void:
	var char_state := CharacterState.new()
	char_state.id = "fallen_hero"
	char_state.status = "dead"
	char_state.name = "Fallen"
	char_state.appearance = {"body": "ghost"}
	char_state.level = 15
	char_state.xp = 8000
	char_state.stats = Stats.new(200.0, 30.0, 10.0, 1.0, 1.0, 15.0)
	char_state.zone = "floor2_boss"
	char_state.position = [5.0, 5.0]

	var save_res := _store.save_character("slot_1", char_state)
	assert_true(save_res.get("ok", false), "save_character dead should succeed")

	var load_res := _store.load_character("slot_1", "fallen_hero")
	assert_true(load_res.get("ok", false), "load_character dead should succeed")
	var loaded: CharacterState = load_res.get("value")
	assert_not_null(loaded)
	assert_eq(loaded.status, "dead")


func test_layout_paths_separate_files() -> void:
	var world := WorldState.new()
	var char_state := CharacterState.new()
	char_state.id = "mira"
	char_state.name = "Mira"
	char_state.appearance = {"hair": "chestnut"}
	char_state.level = 5
	char_state.stats = Stats.new(100.0, 10.0, 2.0, 1.0, 1.0, 5.0)
	char_state.zone = "floor1_forest"

	var s_w := _store.save_world("slot_layout", world)
	assert_true(s_w.get("ok", false))
	var s_c := _store.save_character("slot_layout", char_state)
	assert_true(s_c.get("ok", false))

	var world_expected := TEST_ROOT.path_join("slot_layout/world.json")
	var char_expected := TEST_ROOT.path_join("slot_layout/characters/mira.json")

	assert_true(FileAccess.file_exists(world_expected), "world.json should exist at layout path")
	assert_true(FileAccess.file_exists(char_expected), "mira.json should exist at layout path")
	assert_true(_store.slot_exists("slot_layout"), "slot_layout should exist")


func test_atomic_write_leaves_no_tmp_file() -> void:
	var world := WorldState.new()
	var char_state := CharacterState.new()
	char_state.id = "rowan"
	char_state.stats = Stats.new(100.0, 10.0, 2.0, 1.0, 1.0, 5.0)

	_store.save_world("slot_tmp", world)
	_store.save_character("slot_tmp", char_state)

	var world_tmp := TEST_ROOT.path_join("slot_tmp/world.json.tmp")
	var char_tmp := TEST_ROOT.path_join("slot_tmp/characters/rowan.json.tmp")

	assert_false(FileAccess.file_exists(world_tmp), "world.json.tmp should not exist after write")
	assert_false(FileAccess.file_exists(char_tmp), "rowan.json.tmp should not exist after write")


func test_atomic_write_rename_failure_leaves_target_intact() -> void:
	var target_dir := TEST_ROOT.path_join("slot_dir_fail/world.json")
	DirAccess.make_dir_recursive_absolute(target_dir)
	var canary_path := target_dir.path_join("canary.txt")
	var f := FileAccess.open(canary_path, FileAccess.WRITE)
	assert_not_null(f)
	f.store_string("untouched_data")
	f.close()

	var world := WorldState.new()
	var res := _store.save_world("slot_dir_fail", world)
	assert_false(res.get("ok", true), "save_world should fail when target path is a directory")
	var err: String = str(res.get("error"))
	assert_true(err.contains("world.json"), "Error message should name target file: %s" % err)

	assert_true(DirAccess.dir_exists_absolute(target_dir), "Target directory must remain intact")
	assert_true(FileAccess.file_exists(canary_path), "Target canary file must remain intact")
	var canary_read := FileAccess.open(canary_path, FileAccess.READ)
	assert_eq(canary_read.get_as_text(), "untouched_data", "Canary file contents must be preserved")
	canary_read.close()

	var tmp_path := TEST_ROOT.path_join("slot_dir_fail/world.json.tmp")
	assert_false(FileAccess.file_exists(tmp_path), "Temporary file must be deleted on rename failure")


func test_overwrite_works() -> void:
	var world := WorldState.new()
	world.killed_enemies = 10
	_store.save_world("slot_overwrite", world)

	var l1 := _store.load_world("slot_overwrite")
	assert_true(l1.get("ok", false))
	assert_eq((l1.get("value") as WorldState).killed_enemies, 10)

	world.killed_enemies = 99
	_store.save_world("slot_overwrite", world)

	var l2 := _store.load_world("slot_overwrite")
	assert_true(l2.get("ok", false))
	assert_eq((l2.get("value") as WorldState).killed_enemies, 99)

	var char_state := CharacterState.new()
	char_state.id = "rowan"
	char_state.level = 1
	char_state.stats = Stats.new(100.0, 10.0, 2.0, 1.0, 1.0, 5.0)
	_store.save_character("slot_overwrite", char_state)

	char_state.level = 5
	_store.save_character("slot_overwrite", char_state)

	var lc := _store.load_character("slot_overwrite", "rowan")
	assert_true(lc.get("ok", false))
	assert_eq((lc.get("value") as CharacterState).level, 5)


func test_corrupt_json_clear_error() -> void:
	_write_raw_file("slot_corrupt/world.json", "{not valid json syntax!")

	var res := _store.load_world("slot_corrupt")
	assert_false(res.get("ok", true), "Loading corrupt world.json should fail")
	var err: String = str(res.get("error"))
	assert_true(err.contains("world.json"), "Error should name world.json: %s" % err)
	assert_true(err.contains("JSON parse error") or err.contains("parse"), "Error should mention parse failure: %s" % err)

	_write_raw_file("slot_corrupt/characters/bad.json", "[\"array not object\"]")
	var c_res := _store.load_character("slot_corrupt", "bad")
	assert_false(c_res.get("ok", true), "Loading array JSON should fail")
	var c_err: String = str(c_res.get("error"))
	assert_true(c_err.contains("bad.json"), "Error should name bad.json: %s" % c_err)


func test_wrong_or_old_version_clear_error() -> void:
	_write_raw_file("slot_version/world.json", JSON.stringify({
		"version": 999,
		"seed": 1,
		"floors_unlocked": 1,
		"bosses_defeated": [],
		"cemetery": [],
		"killed_enemies": 0,
		"flags": {},
		"inventory": {"next_uid": 1, "items": {}, "equipment": {}}
	}))

	var res := _store.load_world("slot_version")
	assert_false(res.get("ok", true), "Loading unsupported version should fail")
	var err: String = str(res.get("error"))
	assert_true(err.contains("world.json"), "Error should name world.json: %s" % err)
	assert_true(err.contains("version") or err.contains("Version"), "Error should mention version: %s" % err)

	_write_raw_file("slot_no_version/world.json", JSON.stringify({
		"seed": 1,
		"inventory": {"next_uid": 1, "items": {}, "equipment": {}}
	}))
	var no_ver_res := _store.load_world("slot_no_version")
	assert_false(no_ver_res.get("ok", true), "Loading missing version should fail")
	assert_true(str(no_ver_res.get("error")).contains("version"))


func test_wrong_types_clear_error() -> void:
	_write_raw_file("slot_type/world.json", JSON.stringify({
		"version": 1,
		"seed": "not_an_int",
		"floors_unlocked": 1,
		"bosses_defeated": [],
		"cemetery": [],
		"killed_enemies": 0,
		"flags": {},
		"inventory": {"next_uid": 1, "items": {}, "equipment": {}}
	}))

	var res := _store.load_world("slot_type")
	assert_false(res.get("ok", true), "Wrong seed type should fail")
	var err: String = str(res.get("error"))
	assert_true(err.contains("seed"), "Error should mention seed: %s" % err)


func test_missing_file_error() -> void:
	var w_res := _store.load_world("non_existent_slot")
	assert_false(w_res.get("ok", true), "Missing world file should return ok=false")
	assert_true(str(w_res.get("error")).contains("File not found") or str(w_res.get("error")).contains("not found"))

	var c_res := _store.load_character("slot_1", "ghost_char")
	assert_false(c_res.get("ok", true), "Missing character file should return ok=false")
	assert_true(str(c_res.get("error")).contains("File not found") or str(c_res.get("error")).contains("not found"))


func test_unsafe_slot_and_char_id_rejected() -> void:
	var unsafe_slots: Array[String] = [
		"",
		"   ",
		"../hack",
		"slot/sub",
		"slot\\sub",
		"slot:1",
		"../../etc"
	]

	var world := WorldState.new()
	var char_state := CharacterState.new()
	char_state.id = "valid_hero"
	char_state.stats = Stats.new(10.0, 1.0, 1.0, 1.0, 1.0, 1.0)

	for bad_slot in unsafe_slots:
		assert_false(_store.slot_exists(bad_slot), "Unsafe slot '%s' should not exist" % bad_slot)
		var sw := _store.save_world(bad_slot, world)
		assert_false(sw.get("ok", true), "save_world should reject unsafe slot '%s'" % bad_slot)
		var lw := _store.load_world(bad_slot)
		assert_false(lw.get("ok", true), "load_world should reject unsafe slot '%s'" % bad_slot)
		var sc := _store.save_character(bad_slot, char_state)
		assert_false(sc.get("ok", true), "save_character should reject unsafe slot '%s'" % bad_slot)
		var lc := _store.load_character(bad_slot, "valid_hero")
		assert_false(lc.get("ok", true), "load_character should reject unsafe slot '%s'" % bad_slot)
		var list_res := _store.list_characters(bad_slot)
		assert_false(list_res.get("ok", true), "list_characters should reject unsafe slot '%s'" % bad_slot)

	var unsafe_chars: Array[String] = [
		"",
		"   ",
		"../bad_char",
		"char/1",
		"char\\1",
		"char:1"
	]

	for bad_char in unsafe_chars:
		char_state.id = bad_char
		var sc_bad := _store.save_character("valid_slot", char_state)
		assert_false(sc_bad.get("ok", true), "save_character should reject unsafe char_id '%s'" % bad_char)
		var lc_bad := _store.load_character("valid_slot", bad_char)
		assert_false(lc_bad.get("ok", true), "load_character should reject unsafe char_id '%s'" % bad_char)


func test_list_characters() -> void:
	var empty_res := _store.list_characters("slot_empty")
	assert_true(empty_res.get("ok", false), "list_characters on non-existent slot returns ok=true with empty list")
	assert_eq(empty_res.get("value"), [], "Empty slot has no characters")

	var c1 := CharacterState.new()
	c1.id = "bob"
	c1.stats = Stats.new(10.0, 1.0, 1.0, 1.0, 1.0, 1.0)
	var c2 := CharacterState.new()
	c2.id = "alice"
	c2.stats = Stats.new(10.0, 1.0, 1.0, 1.0, 1.0, 1.0)

	_store.save_character("slot_party", c1)
	_store.save_character("slot_party", c2)

	var list_res := _store.list_characters("slot_party")
	assert_true(list_res.get("ok", false))
	var ids: Array = list_res.get("value")
	assert_eq(ids, ["alice", "bob"], "list_characters should return sorted list of character IDs")

	var convenience_ids := _store.get_character_ids("slot_party")
	assert_eq(convenience_ids, ["alice", "bob"], "get_character_ids should match list_characters")


func test_inventory_single_source_of_truth_two_characters_and_merchant() -> void:
	var world := WorldState.new()
	var inv := Inventory.new(_item_db)

	var merchant_sword := inv.create("iron_sword", "merchant:floor1_smith")
	var merchant_vest := inv.create("leather_vest", "merchant:floor1_smith")

	var rowan_sword := inv.create("iron_sword", "character:rowan")
	var rowan_potion := inv.create("healing_draught", "character:rowan")
	var eq_r := inv.equip("character:rowan", rowan_sword)
	assert_true(eq_r)

	var mira_vest := inv.create("leather_vest", "character:mira")
	var mira_potion := inv.create("healing_draught", "character:mira")
	var eq_m := inv.equip("character:mira", mira_vest)
	assert_true(eq_m)

	world.inventory = inv

	var uids := [merchant_sword, merchant_vest, rowan_sword, rowan_potion, mira_vest, mira_potion]
	var unique_uids: Dictionary = {}
	for u in uids:
		assert_false(unique_uids.has(u), "UID %d must be unique world-wide" % u)
		unique_uids[u] = true

	var sw := _store.save_world("slot_multi", world)
	assert_true(sw.get("ok", false))

	var c1 := CharacterState.new()
	c1.id = "rowan"
	c1.status = "alive"
	c1.name = "Rowan"
	c1.level = 3
	c1.stats = Stats.new(120.0, 15.0, 5.0, 1.0, 1.0, 10.0)
	var sc1 := _store.save_character("slot_multi", c1)
	assert_true(sc1.get("ok", false))

	var c2 := CharacterState.new()
	c2.id = "mira"
	c2.status = "alive"
	c2.name = "Mira"
	c2.level = 4
	c2.stats = Stats.new(90.0, 12.0, 4.0, 1.2, 0.8, 8.0)
	var sc2 := _store.save_character("slot_multi", c2)
	assert_true(sc2.get("ok", false))

	var lw := _store.load_world("slot_multi")
	assert_true(lw.get("ok", false))
	var loaded_world: WorldState = lw.get("value")
	assert_not_null(loaded_world)
	assert_not_null(loaded_world.inventory)

	assert_eq(loaded_world.get_stock("floor1_smith"), [merchant_sword, merchant_vest])
	assert_eq(loaded_world.get_character_items("rowan"), [rowan_sword, rowan_potion])
	assert_eq(loaded_world.get_character_items("mira"), [mira_vest, mira_potion])
	assert_eq(loaded_world.get_character_equipment("rowan"), {"weapon": rowan_sword})
	assert_eq(loaded_world.get_character_equipment("mira"), {"armor": mira_vest})

	c1.status = "dead"
	var sc1_dead := _store.save_character("slot_multi", c1)
	assert_true(sc1_dead.get("ok", false))

	var lc1 := _store.load_character("slot_multi", "rowan")
	assert_true(lc1.get("ok", false))
	assert_eq((lc1.get("value") as CharacterState).status, "dead")

	var lw_after_death := _store.load_world("slot_multi")
	assert_true(lw_after_death.get("ok", false))
	var w_dead: WorldState = lw_after_death.get("value")
	assert_eq(w_dead.get_character_items("rowan"), [rowan_sword, rowan_potion], "Dead character's items must remain in world inventory")
	assert_eq(w_dead.get_character_equipment("rowan"), {"weapon": rowan_sword}, "Dead character's equipment must remain in world inventory")


func test_world_from_dict_requires_item_db() -> void:
	var world_dict := {
		"version": 1,
		"seed": 123,
		"floors_unlocked": 1,
		"bosses_defeated": [],
		"cemetery": [],
		"killed_enemies": 0,
		"flags": {},
		"inventory": {"next_uid": 1, "items": {}, "equipment": {}}
	}

	var errs: Array = []
	var w := WorldState.from_dict(world_dict, null, errs)
	assert_null(w, "WorldState.from_dict without item_db must return null")
	assert_gt(errs.size(), 0)
	var err_str: String = str(errs[0])
	assert_true(err_str.contains("item_db"), "Error must name item_db: %s" % err_str)

	var store_no_db := SaveStore.new(TEST_ROOT, null)
	_store.save_world("slot_no_db", WorldState.new())
	var load_res := store_no_db.load_world("slot_no_db")
	assert_false(load_res.get("ok", true), "load_world without item_db must return ok=false")
	assert_true(str(load_res.get("error")).contains("item_db"))


func test_character_stats_validation() -> void:
	var base_char_dict := {
		"version": 1,
		"id": "hero_test",
		"status": "alive",
		"name": "Hero",
		"appearance": {},
		"level": 1,
		"xp": 0,
		"stats": {
			"max_hp": 100.0,
			"atk": 10.0,
			"defense": 5.0,
			"attack_range": 1.5,
			"attack_interval": 1.0,
			"weapon_damage": 8.0
		},
		"zone": "floor1_town",
		"position": [0.0, 0.0]
	}

	for key in ["max_hp", "atk", "defense", "attack_range", "attack_interval", "weapon_damage"]:
		var missing_dict: Dictionary = base_char_dict.duplicate(true)
		(missing_dict["stats"] as Dictionary).erase(key)
		var errs: Array = []
		var cs_missing := CharacterState.from_dict(missing_dict, errs)
		assert_null(cs_missing, "CharacterState.from_dict must reject missing stats key '%s'" % key)
		assert_true(str(errs).contains(key), "Error must name missing key '%s': %s" % [key, str(errs)])

		var wrong_type_dict: Dictionary = base_char_dict.duplicate(true)
		(wrong_type_dict["stats"] as Dictionary)[key] = "not_numeric"
		var errs_type: Array = []
		var cs_type := CharacterState.from_dict(wrong_type_dict, errs_type)
		assert_null(cs_type, "CharacterState.from_dict must reject non-numeric stats key '%s'" % key)
		assert_true(str(errs_type).contains(key), "Error must name wrong-type key '%s': %s" % [key, str(errs_type)])

		var neg_dict: Dictionary = base_char_dict.duplicate(true)
		(neg_dict["stats"] as Dictionary)[key] = -1.0
		var errs_neg: Array = []
		var cs_neg := CharacterState.from_dict(neg_dict, errs_neg)
		assert_null(cs_neg, "CharacterState.from_dict must reject negative value for '%s'" % key)
		assert_true(str(errs_neg).contains(key), "Error must name negative key '%s': %s" % [key, str(errs_neg)])

	var zero_hp_dict: Dictionary = base_char_dict.duplicate(true)
	(zero_hp_dict["stats"] as Dictionary)["max_hp"] = 0.0
	var errs_hp: Array = []
	var cs_hp := CharacterState.from_dict(zero_hp_dict, errs_hp)
	assert_null(cs_hp, "CharacterState.from_dict must reject max_hp == 0")
	assert_true(str(errs_hp).contains("max_hp"))

	var zero_interval_dict: Dictionary = base_char_dict.duplicate(true)
	(zero_interval_dict["stats"] as Dictionary)["attack_interval"] = 0.0
	var errs_interval: Array = []
	var cs_interval := CharacterState.from_dict(zero_interval_dict, errs_interval)
	assert_null(cs_interval, "CharacterState.from_dict must reject attack_interval == 0")
	assert_true(str(errs_interval).contains("attack_interval"))

	var inf_dict: Dictionary = base_char_dict.duplicate(true)
	(inf_dict["stats"] as Dictionary)["atk"] = INF
	var errs_inf: Array = []
	var cs_inf := CharacterState.from_dict(inf_dict, errs_inf)
	assert_null(cs_inf, "CharacterState.from_dict must reject non-finite stats")
	assert_true(str(errs_inf).contains("atk"))


func test_logic_purity() -> void:
	var save_files := [
		"res://src/logic/save/world_state.gd",
		"res://src/logic/save/character_state.gd",
		"res://src/logic/save/save_store.gd"
	]

	var forbidden := [
		"extends Node",
		"get_tree",
		"Input.",
		"res://src/view",
		"res://src/input",
		"res://scenes"
	]

	for file_path in save_files:
		var file := FileAccess.open(file_path, FileAccess.READ)
		assert_not_null(file, "Should be able to open %s" % file_path)
		var text := file.get_as_text()
		file.close()

		var lines := text.split("\n")
		for i in range(lines.size()):
			var line := lines[i].strip_edges()
			if line.begins_with("#"):
				continue
			for token in forbidden:
				assert_false(token in line, "File %s line %d contains forbidden token '%s'" % [file_path, i + 1, token])

		assert_true("extends RefCounted" in text, "File %s should extend RefCounted" % file_path)
