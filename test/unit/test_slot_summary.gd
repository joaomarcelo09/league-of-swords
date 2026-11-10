extends GutTest

const TEST_ROOT := "user://test_saves/slot_summary"

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


func test_empty_slot() -> void:
	var summary := SlotSummary.inspect(_store, "non_existent_slot", _item_db)
	assert_false(summary["has_world"], "Empty slot has no world")
	assert_false(summary["world_ok"], "Empty slot world_ok is false")
	assert_eq(summary["living_character_id"], "")
	assert_eq(summary["living_name"], "")
	assert_eq(summary["living_level"], 0)
	assert_eq(summary["living_zone"], "")
	assert_eq(summary["dead_count"], 0)
	assert_eq(summary["error"], "")


func test_world_only_no_characters() -> void:
	var world := WorldState.new()
	world.floors_unlocked = 1
	var save_res := _store.save_world("slot_world_only", world)
	assert_true(save_res["ok"], "World save succeeded")

	var summary := SlotSummary.inspect(_store, "slot_world_only", _item_db)
	assert_true(summary["has_world"], "Has world file")
	assert_true(summary["world_ok"], "World loaded successfully")
	assert_eq(summary["living_character_id"], "", "No living character")
	assert_eq(summary["living_name"], "")
	assert_eq(summary["living_level"], 0)
	assert_eq(summary["living_zone"], "")
	assert_eq(summary["dead_count"], 0, "No dead characters")
	assert_eq(summary["error"], "")


func test_living_character() -> void:
	var world := WorldState.new()
	_store.save_world("slot_living", world)

	var char_state := CharacterState.new()
	char_state.id = "char_1"
	char_state.name = "Brannoc"
	char_state.level = 15
	char_state.zone = "floor1"
	char_state.status = "alive"
	char_state.stats = Stats.new(120.0, 15.0, 3.0, 1.5, 1.0, 10.0)
	_store.save_character("slot_living", char_state)

	var summary := SlotSummary.inspect(_store, "slot_living", _item_db)
	assert_true(summary["has_world"])
	assert_true(summary["world_ok"])
	assert_eq(summary["living_character_id"], "char_1")
	assert_eq(summary["living_name"], "Brannoc")
	assert_eq(summary["living_level"], 15)
	assert_eq(summary["living_zone"], "floor1")
	assert_eq(summary["dead_count"], 0)
	assert_eq(summary["error"], "")


func test_dead_only_character() -> void:
	var world := WorldState.new()
	world.cemetery = [
		{
			"character_id": "char_1",
			"name": "Alden",
			"level": 5,
			"zone": "floor1",
			"cause": "dire_wolf",
			"date": "2026-11-10",
			"appearance": {}
		}
	]
	_store.save_world("slot_dead", world)

	var char_state := CharacterState.new()
	char_state.id = "char_1"
	char_state.name = "Alden"
	char_state.level = 5
	char_state.zone = "floor1"
	char_state.status = "dead"
	_store.save_character("slot_dead", char_state)

	var summary := SlotSummary.inspect(_store, "slot_dead", _item_db)
	assert_true(summary["has_world"])
	assert_true(summary["world_ok"])
	assert_eq(summary["living_character_id"], "", "Dead character must not be returned as living")
	assert_eq(summary["living_name"], "")
	assert_eq(summary["dead_count"], 1, "Dead count must be 1")
	assert_eq(summary["error"], "")


func test_corrupt_world() -> void:
	_write_raw_file("corrupt_slot/world.json", "{ invalid json content ]]]")

	var summary := SlotSummary.inspect(_store, "corrupt_slot", _item_db)
	assert_true(summary["has_world"], "World file exists")
	assert_false(summary["world_ok"], "Corrupt world must report world_ok false")
	assert_ne(summary["error"], "", "Error must explain corrupt world")
	assert_eq(summary["living_character_id"], "")


func test_delete_slot_safety() -> void:
	# 1. Reject invalid slot names
	var res_dotdot := _store.delete_slot("../other")
	assert_false(res_dotdot["ok"], "delete_slot must reject ..")
	assert_ne(res_dotdot["error"], "")

	var res_slash := _store.delete_slot("foo/bar")
	assert_false(res_slash["ok"], "delete_slot must reject /")

	var res_empty := _store.delete_slot("")
	assert_false(res_empty["ok"], "delete_slot must reject empty string")

	# 2. Deleting non-existent slot succeeds cleanly
	var res_non_exist := _store.delete_slot("does_not_exist")
	assert_true(res_non_exist["ok"])

	# 3. Create a populated slot and a neighbor slot
	var world := WorldState.new()
	_store.save_world("slot_to_delete", world)
	var cs := CharacterState.new()
	cs.id = "char_1"
	cs.name = "ToDelete"
	_store.save_character("slot_to_delete", cs)

	_store.save_world("slot_neighbor", world)

	assert_true(_store.slot_exists("slot_to_delete"))
	assert_true(_store.slot_exists("slot_neighbor"))

	# 4. Delete the slot
	var del_res := _store.delete_slot("slot_to_delete")
	assert_true(del_res["ok"], "delete_slot should succeed")
	assert_false(_store.slot_exists("slot_to_delete"), "Deleted slot directory must no longer exist")
	assert_true(_store.slot_exists("slot_neighbor"), "Neighbor slot directory must remain untouched")
