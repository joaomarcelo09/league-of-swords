extends GutTest

const TEST_ROOT := "user://test_saves/title_menu"

var _registry: DataRegistry = null
var _item_db: ItemDB = null
var _store: SaveStore = null


func before_each() -> void:
	_clean_dir(TEST_ROOT)
	LaunchRequest.reset()
	_registry = DataRegistry.new()
	_registry.load_dir("res://data")
	_item_db = ItemDB.new(_registry)
	_store = SaveStore.new(TEST_ROOT, _item_db)


func after_each() -> void:
	LaunchRequest.reset()
	_clean_dir(TEST_ROOT)


func after_all() -> void:
	LaunchRequest.reset()
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


func test_title_menu_ui_creation() -> void:
	var menu := TitleMenu.new()
	autofree(menu)

	assert_not_null(menu.title_label)
	assert_not_null(menu.subtitle_label)
	assert_not_null(menu.info_label)
	assert_not_null(menu.continue_button)
	assert_not_null(menu.new_world_button)
	assert_not_null(menu.name_container)
	assert_not_null(menu.name_input)
	assert_not_null(menu.start_button)
	assert_not_null(menu.error_label)
	assert_false(menu.name_container.visible)
	assert_false(menu.error_label.visible)


func test_title_menu_empty_slot() -> void:
	var menu := TitleMenu.new()
	autofree(menu)
	menu.setup(TEST_ROOT, "slot_empty", _registry)

	assert_true(menu.continue_button.disabled, "Continue must be disabled when slot is empty")
	assert_ne(menu.continue_button.tooltip_text, "", "Continue button should explain disabled reason")
	assert_false(menu.new_world_button.disabled, "New World button must be enabled")
	assert_true(menu.info_label.text.contains("No saved world"), "Info label should state no saved world")

	# Clicking New World on empty slot directly launches new mode without confirm
	menu.new_world_button.pressed.emit()
	assert_eq(LaunchRequest.mode, "new")
	assert_eq(LaunchRequest.character_id, "")


func test_title_menu_living_character() -> void:
	var world := WorldState.new()
	world.floors_unlocked = 1
	_store.save_world("slot_living", world)

	var cs := CharacterState.new()
	cs.id = "char_1"
	cs.name = "Brannoc"
	cs.level = 14
	cs.zone = "floor1"
	cs.status = "alive"
	cs.stats = Stats.new(120.0, 15.0, 3.0, 1.5, 1.0, 10.0)
	_store.save_character("slot_living", cs)

	var menu := TitleMenu.new()
	autofree(menu)
	menu.setup(TEST_ROOT, "slot_living", _registry)

	assert_false(menu.continue_button.disabled, "Continue must be enabled when living char exists")
	assert_false(menu.new_world_button.disabled)
	assert_true(menu.info_label.text.contains("Brannoc"))
	assert_true(menu.info_label.text.contains("14"))
	assert_true(menu.info_label.text.contains("floor1"))

	# Clicking continue sets LaunchRequest to continue this character
	menu.continue_button.pressed.emit()
	assert_eq(LaunchRequest.mode, "continue")
	assert_eq(LaunchRequest.character_id, "char_1")


func test_title_menu_no_living_character_shows_name_prompt_and_creates_character() -> void:
	var world := WorldState.new()
	world.cemetery = [
		{
			"character_id": "char_1",
			"name": "Alden",
			"level": 3,
			"zone": "floor1",
			"cause": "dire_wolf",
			"date": "2026-11-10",
			"appearance": {}
		}
	]
	_store.save_world("slot_dead", world)

	var cs := CharacterState.new()
	cs.id = "char_1"
	cs.name = "Alden"
	cs.status = "dead"
	_store.save_character("slot_dead", cs)

	var menu := TitleMenu.new()
	autofree(menu)
	menu.setup(TEST_ROOT, "slot_dead", _registry)

	assert_false(menu.continue_button.disabled, "Continue must be enabled to create character in existing world")
	assert_false(menu.name_container.visible)

	# Click continue: name prompt should open
	menu.continue_button.pressed.emit()
	assert_true(menu.name_container.visible, "Name entry should appear when continuing without living character")
	assert_eq(LaunchRequest.mode, "", "Launch mode not set until valid name submitted")

	# Test name validation: empty name
	menu.name_input.text = "   "
	menu.start_button.pressed.emit()
	assert_true(menu.error_label.visible)
	assert_true(menu.error_label.text.contains("empty"))
	assert_eq(LaunchRequest.mode, "")

	# Test name validation: too long (> 32 chars)
	menu.name_input.text = "ThisNameIsFarTooLongToBeAValidHeroNameForOurGame"
	menu.start_button.pressed.emit()
	assert_true(menu.error_label.visible)
	assert_true(menu.error_label.text.contains("32"))
	assert_eq(LaunchRequest.mode, "")

	# Valid name
	menu.name_input.text = "Lyra"
	menu.start_button.pressed.emit()
	assert_eq(LaunchRequest.mode, "continue")
	assert_ne(LaunchRequest.character_id, "")
	assert_ne(LaunchRequest.character_id, "char_1", "New character must have distinct id from dead character")

	# Verify on disk
	var summary := SlotSummary.inspect(_store, "slot_dead", _item_db)
	assert_eq(summary["living_character_id"], LaunchRequest.character_id)
	assert_eq(summary["living_name"], "Lyra")
	assert_eq(summary["dead_count"], 1)


func test_title_menu_confirm_new_world_on_existing_slot() -> void:
	var world := WorldState.new()
	_store.save_world("slot_existing", world)
	var cs := CharacterState.new()
	cs.id = "char_1"
	cs.name = "OldHero"
	_store.save_character("slot_existing", cs)

	var menu := TitleMenu.new()
	autofree(menu)
	menu.setup(TEST_ROOT, "slot_existing", _registry)

	# First click enters confirm step
	menu.new_world_button.pressed.emit()
	assert_true(menu._confirming_new_world, "Must enter confirm step on first click")
	assert_true(menu.new_world_button.text.contains("Confirm"))
	assert_true(_store.slot_exists("slot_existing"), "Slot must NOT be deleted after first click")
	assert_eq(LaunchRequest.mode, "", "Launch request not set before confirmation")

	# Second click executes wipe
	menu.new_world_button.pressed.emit()
	assert_false(_store.slot_exists("slot_existing"), "Slot must be deleted after confirmation")
	assert_eq(LaunchRequest.mode, "new")
	assert_eq(LaunchRequest.character_id, "")


func test_title_menu_corrupt_world_blocks_actions() -> void:
	_write_raw_file("corrupt_slot/world.json", "{ bad json")

	var menu := TitleMenu.new()
	autofree(menu)
	menu.setup(TEST_ROOT, "corrupt_slot", _registry)

	assert_true(menu.continue_button.disabled, "Continue must be disabled on corrupt world")
	assert_true(menu.new_world_button.disabled, "New World must be disabled to prevent overwriting corrupt world")
	assert_true(menu.error_label.visible, "Error label must display loading error")
	assert_false(menu.name_container.visible)

	menu.new_world_button.pressed.emit()
	assert_eq(LaunchRequest.mode, "", "No launch mode when world file corrupt")
	var world_path := _store.get_world_file_path("corrupt_slot")
	var file := FileAccess.open(world_path, FileAccess.READ)
	assert_not_null(file)
	assert_eq(file.get_as_text(), "{ bad json", "Corrupt world file must remain intact and not overwritten")
	file.close()
