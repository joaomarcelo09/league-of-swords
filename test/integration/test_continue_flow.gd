extends GutTest

const TEST_ROOT := "user://test_saves/continue_flow"
const TEST_SLOT := "slot_continue"


func before_each() -> void:
	_clean_dir(TEST_ROOT)
	LaunchRequest.reset()


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


func test_continue_flow_restores_position_inventory_and_world_flags() -> void:
	# 1. Start fresh MainView session
	LaunchRequest.mode = "new"
	var view1 := MainView.new()
	view1.save_root = TEST_ROOT
	view1.save_slot = TEST_SLOT
	view1._ready()

	assert_not_null(view1.player, "Player should be spawned")
	assert_not_null(view1.character_state, "Character state should exist")
	assert_not_null(view1.world_state, "World state should exist")

	var char_id := view1.character_state.id
	assert_false(char_id.is_empty(), "Character ID must be non-empty")

	# Move player
	view1.player.pos = Vector2(8.0, 12.0)

	# Add item to player inventory and equip it
	var player_owner := "character:%d" % view1.player.id
	var item_uid := view1.inventory.create("iron_sword", player_owner)
	assert_gt(item_uid, 0, "Created item UID must be positive")
	assert_eq(view1.inventory.owner_of(item_uid), player_owner, "Item owner should be player")
	var equip_ok := view1.inventory.equip(player_owner, item_uid)
	assert_true(equip_ok, "Equipping weapon must succeed")
	assert_eq(view1.inventory.get_equipped(player_owner, "weapon"), item_uid, "Player must have weapon equipped")

	# Set world flag
	view1.world_state.flags["tower_floor_unlocked"] = 2

	# Perform save_now()
	var save_res := view1.save_now()
	assert_true(save_res.get("ok", false), "save_now() must succeed")
	assert_eq(view1.inventory.get_equipped(player_owner, "weapon"), item_uid, "Item must still be equipped in memory right after save_now()")

	# Free view1
	view1.free()

	# 2. Launch new session in continue mode
	LaunchRequest.mode = "continue"
	LaunchRequest.character_id = char_id

	var view2 := MainView.new()
	autofree(view2)
	view2.save_root = TEST_ROOT
	view2.save_slot = TEST_SLOT
	view2._ready()

	# Assert same character restored
	assert_eq(view2.character_state.id, char_id, "Continued character ID must match")
	assert_almost_eq(view2.player.pos.x, 8.0, 0.01, "Player X position must be restored")
	assert_almost_eq(view2.player.pos.y, 12.0, 0.01, "Player Y position must be restored")

	# Assert world flags restored
	assert_eq(int(view2.world_state.flags.get("tower_floor_unlocked", 0)), 2, "World flag must be restored")

	# Assert inventory and equipped gear restored to player
	var p2_owner := "character:%d" % view2.player.id
	var p2_items := view2.inventory.items_of(p2_owner)
	assert_true(p2_items.has(item_uid), "Player inventory must contain the saved item after continue")
	assert_eq(view2.inventory.get_equipped(p2_owner, "weapon"), item_uid, "Item must be equipped in weapon slot after continue reload")


func test_continue_flow_keeps_the_floor1_chunk_tile_and_zone() -> void:
	# 1. New game on the chunked floor, standing in the east plains.
	LaunchRequest.mode = "new"
	var view1 := MainView.new()
	view1.save_root = TEST_ROOT
	view1.save_slot = TEST_SLOT
	view1._ready()

	assert_not_null(view1.chunked_world, "Floor 1 runs as a chunked world")
	assert_eq(view1.chunked_world.world_width(), 288, "the 9x4 floor is 288 tiles wide")
	assert_eq(view1.chunked_world.world_height(), 128, "the 9x4 floor is 128 tiles tall")
	var char_id := view1.character_state.id
	var east_tile := Vector2i(220, 64)
	view1.player.pos = Vector2(east_tile) + Vector2(0.5, 0.5)

	var save_res := view1.save_now()
	assert_true(save_res.get("ok", false), "save_now() must succeed: %s" % str(save_res.get("error", "")))
	assert_eq(view1.character_state.zone, "floor1", "the save keeps the floor id")
	assert_eq(view1.character_state.chunk, "floor1_x6_y2", "the save keeps the chunk of the east plains tile")
	assert_eq(view1.character_state.position, [28.5, 0.5], "the save keeps the chunk-local position")
	view1.free()

	# 2. Continue that character and check it resumes on the same world tile.
	LaunchRequest.mode = "continue"
	LaunchRequest.character_id = char_id
	var view2 := MainView.new()
	autofree(view2)
	view2.save_root = TEST_ROOT
	view2.save_slot = TEST_SLOT
	view2._ready()

	assert_eq(view2.character_state.zone, "floor1", "continue keeps the floor id")
	assert_eq(view2.character_state.chunk, "floor1_x6_y2", "continue keeps the chunk")
	assert_eq(view2.player.tile(), east_tile, "continue restores the player's world tile")
	assert_true(view2.chunked_world.is_loaded("floor1_x6_y2"), "continue streams the saved chunk back in")

	var tile_px := float(view2.registry.get_balance("view.tile_px"))
	var expected_bounds := GameCamera.bounds_for(
		Vector2(float(view2.chunked_world.world_width()), float(view2.chunked_world.world_height())),
		tile_px
	)
	assert_eq(view2.camera.map_bounds, expected_bounds, "the camera clamps to the whole 9x4 floor")
