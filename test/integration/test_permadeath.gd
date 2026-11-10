extends GutTest

const TEST_ROOT := "user://test_saves"
const SLOT_NAME := "perma_slot"

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


func test_permadeath_full_lifecycle() -> void:
	# 1. Create world and save to slot
	var world := WorldState.new()
	world.seed = 9999
	world.floors_unlocked = 1
	world.inventory = Inventory.new(_item_db)

	var save_w_res := _store.save_world(SLOT_NAME, world)
	assert_true(save_w_res.get("ok", false), "Initial save_world should succeed")

	# 2. Create Character A
	var entry_tile := Vector2i(3, 2)
	var res_a := Lifecycle.new_character(
		world,
		"Alden",
		{"body": "knight_body", "hair": "brown"},
		entry_tile,
		_store,
		SLOT_NAME
	)
	assert_true(res_a.get("ok", false), "new_character char_a should succeed")
	var char_a: CharacterState = res_a.get("value")
	assert_not_null(char_a, "char_a must not be null")
	assert_eq(char_a.status, "alive", "char_a must be alive")
	assert_eq(char_a.level, 1, "char_a must be level 1")
	assert_eq(char_a.position, [3.0, 2.0], "char_a position must match entry tile")

	# 3. Char A picks item from ground and equips it
	var char_a_owner := "character:" + char_a.id
	var item_uid := world.inventory.create("iron_sword", "ground:floor1")
	assert_gt(item_uid, 0, "Item iron_sword should be created")

	var pick_ok := world.inventory.pickup(item_uid, char_a_owner)
	assert_true(pick_ok, "Pickup to char_a should succeed")
	assert_eq(world.inventory.owner_of(item_uid), char_a_owner)

	var equip_ok := world.inventory.equip(char_a_owner, item_uid)
	assert_true(equip_ok, "Equip iron_sword should succeed")
	assert_eq(world.inventory.get_equipped(char_a_owner, "weapon"), item_uid)
	assert_eq(world.get_character_items(char_a.id), [item_uid])

	# Persist world and char_a state before death
	_store.save_world(SLOT_NAME, world)
	_store.save_character(SLOT_NAME, char_a)

	# 4. Char A dies from sim death event
	var sim_death_event := {
		"type": "death",
		"tick": 120,
		"target": 1,
		"source": "ash_stalker"
	}
	var death_res := Lifecycle.on_player_death_event(
		sim_death_event,
		world,
		char_a,
		"2026-11-10",
		_store,
		SLOT_NAME
	)
	assert_true(death_res.get("ok", false), "on_player_death_event should succeed")
	assert_eq(char_a.status, "dead", "char_a status must be dead")

	# 5. Cemetery has Char A
	assert_eq(world.cemetery.size(), 1, "Cemetery must contain exactly 1 entry")
	var cem_entry: Dictionary = world.cemetery[0]
	assert_eq(cem_entry["character_id"], char_a.id)
	assert_eq(cem_entry["name"], "Alden")
	assert_eq(cem_entry["level"], 1)
	assert_eq(cem_entry["zone"], "floor1")
	assert_eq(cem_entry["cause"], "ash_stalker")
	assert_eq(cem_entry["date"], "2026-11-10")
	assert_eq(cem_entry["appearance"], {"body": "knight_body", "hair": "brown"})

	# 6. Item owner is merchant (floor1_smith), not Char A
	assert_eq(world.inventory.items_of(char_a_owner), [], "Char A should own 0 items")
	assert_eq(world.inventory.get_all_equipped(char_a_owner), {}, "Char A should have no equipped items")
	assert_eq(world.inventory.owner_of(item_uid), "merchant:floor1_smith", "Item owner must be floor1_smith")
	assert_eq(world.get_stock("floor1_smith"), [item_uid], "Merchant stock must include transferred item")

	# 7. Char B starts at floor 1 entry tile in the same world file
	var res_b := Lifecycle.new_character(
		world,
		"Brand",
		{"body": "mage_body", "hair": "silver"},
		entry_tile,
		_store,
		SLOT_NAME
	)
	assert_true(res_b.get("ok", false), "new_character char_b should succeed")
	var char_b: CharacterState = res_b.get("value")
	assert_not_null(char_b, "char_b must not be null")
	assert_eq(char_b.status, "alive", "char_b must be alive")
	assert_ne(char_b.id, char_a.id, "char_b id must differ from char_a id")
	assert_eq(char_b.position, [3.0, 2.0], "char_b position must be at floor 1 entry tile")
	assert_eq(char_b.zone, "floor1", "char_b zone must be floor1")

	# 8. Char A cannot be loaded as playable; Char B can be loaded as playable
	var load_a_playable := Lifecycle.load_playable(_store, SLOT_NAME, char_a.id, _item_db)
	assert_false(load_a_playable.get("ok", true), "Dead Char A must NOT load as playable")
	assert_null(load_a_playable.get("value"))

	var load_b_playable := Lifecycle.load_playable(_store, SLOT_NAME, char_b.id, _item_db)
	assert_true(load_b_playable.get("ok", false), "Living Char B MUST load as playable")
	var loaded_b_playable: CharacterState = load_b_playable.get("value")
	assert_not_null(loaded_b_playable)
	assert_eq(loaded_b_playable.status, "alive")
	assert_eq(loaded_b_playable.name, "Brand")

	# 9. Reload from disk confirms all changes are persisted
	var fresh_store := SaveStore.new(TEST_ROOT, _item_db)

	var reload_world_res := fresh_store.load_world(SLOT_NAME)
	assert_true(reload_world_res.get("ok", false), "Reloading world from disk must succeed")
	var reloaded_world: WorldState = reload_world_res.get("value")
	assert_not_null(reloaded_world)

	assert_eq(reloaded_world.cemetery.size(), 1, "Persisted cemetery must contain Char A")
	assert_eq(reloaded_world.cemetery[0]["name"], "Alden")
	assert_eq(reloaded_world.cemetery[0]["cause"], "ash_stalker")
	assert_eq(reloaded_world.get_stock("floor1_smith"), [item_uid], "Merchant stock must be persisted on disk")
	assert_eq(reloaded_world.get_character_items(char_a.id), [], "Char A items must be empty on disk")

	# Char A is still loadable via normal load_character as read-only
	var reload_char_a := fresh_store.load_character(SLOT_NAME, char_a.id, _item_db)
	assert_true(reload_char_a.get("ok", false), "Normal load_character for Char A must succeed")
	var reloaded_char_a: CharacterState = reload_char_a.get("value")
	assert_not_null(reloaded_char_a)
	assert_eq(reloaded_char_a.status, "dead")

	# Char A refuses load_playable from disk
	var reload_a_playable := Lifecycle.load_playable(fresh_store, SLOT_NAME, char_a.id, _item_db)
	assert_false(reload_a_playable.get("ok", true), "Char A must refuse load_playable after disk reload")

	# Char B loads as playable from disk
	var reload_b_playable := Lifecycle.load_playable(fresh_store, SLOT_NAME, char_b.id, _item_db)
	assert_true(reload_b_playable.get("ok", false), "Char B must succeed load_playable after disk reload")
	var reloaded_char_b: CharacterState = reload_b_playable.get("value")
	assert_not_null(reloaded_char_b)
	assert_eq(reloaded_char_b.status, "alive")
	assert_eq(reloaded_char_b.position, [3.0, 2.0])
