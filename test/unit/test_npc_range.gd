extends GutTest
## JGT-83: merchant NPC - interact range, pick, input signal, panel take + persistence.

const TEST_ROOT := "user://test_saves_npc"
const MAP := "##########\n#........#\n#........#\n#........#\n##########\n"
const LEGEND := {
	"#": {"type": "wall", "walkable": false},
	".": {"type": "floor", "walkable": true},
}
const NPC_ID := "test_smith"
const NPC_TILE := Vector2i(5, 2)

var _registry: DataRegistry = null
var _item_db: ItemDB = null
var _zone: Zone = null
var _range: float = 0.0


func before_each() -> void:
	_clean_dir(TEST_ROOT)
	_registry = DataRegistry.new()
	_registry.load_dir("res://data")
	_item_db = ItemDB.new(_registry)
	_range = float(_registry.get_balance("npc_interact_range", -1.0))
	_zone = Zone.load_from_strings(MAP, {
		"legend": LEGEND,
		"entry": [1, 2],
		"npcs": [{"id": NPC_ID, "kind": "merchant", "name": "Test Smith", "tile": [NPC_TILE.x, NPC_TILE.y]}],
	})
	assert_true(_zone.is_valid(), str(_zone.errors))


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


func _sim() -> WorldSim:
	return WorldSim.new(_zone, _registry)


func _player(sim: WorldSim, pos: Vector2) -> Entity:
	var p := sim.spawn("player", Vector2i(1, 1), 0.0, 100.0, Stats.new(100.0, 10.0, 2.0, 1.5, 1.0, 5.0))
	p.pos = pos
	return p


func _center() -> Vector2:
	return WorldSim.tile_center(NPC_TILE)


# --- npc_in_range ---

func test_range_key_is_data_driven() -> void:
	assert_gt(_range, 0.0, "balance.json defines npc_interact_range")
	assert_eq(_sim().npc_interact_range(), _range)


func test_in_range() -> void:
	var sim := _sim()
	var p := _player(sim, _center() + Vector2(_range * 0.5, 0.0))
	assert_true(sim.npc_in_range(p.id, NPC_ID))


func test_out_of_range() -> void:
	var sim := _sim()
	var p := _player(sim, _center() + Vector2(0.0, -(_range + 0.5)))
	assert_false(sim.npc_in_range(p.id, NPC_ID))


func test_boundary() -> void:
	var sim := _sim()
	var p := _player(sim, _center() + Vector2(-_range, 0.0))
	assert_true(sim.npc_in_range(p.id, NPC_ID), "exactly at range counts")
	p.pos = _center() + Vector2(-(_range + 0.01), 0.0)
	assert_false(sim.npc_in_range(p.id, NPC_ID), "just past range does not")


func test_unknown_npc_and_player() -> void:
	var sim := _sim()
	var p := _player(sim, _center())
	assert_false(sim.npc_in_range(p.id, "nobody"))
	assert_false(sim.npc_in_range(p.id, ""))
	assert_false(sim.npc_in_range(9999, NPC_ID))


func test_dead_player() -> void:
	var sim := _sim()
	var p := _player(sim, _center())
	p.dead = true
	assert_false(sim.npc_in_range(p.id, NPC_ID))


func test_missing_range_key_is_false() -> void:
	var sim := WorldSim.new(_zone, null)
	var p := _player(sim, _center())
	assert_false(sim.npc_in_range(p.id, NPC_ID))


# --- npc_at / input ---

func test_npc_at_picks_within_radius() -> void:
	var sim := _sim()
	assert_eq(str(sim.npc_at(_center() + Vector2(0.2, 0.1), 0.5).get("id", "")), NPC_ID)
	assert_true(sim.npc_at(_center() + Vector2(2.0, 0.0), 0.5).is_empty())
	assert_true(sim.npc_at(_center(), -1.0).is_empty())


func test_input_npc_to_interact() -> void:
	var sim := _sim()
	var p := _player(sim, _center() + Vector2(-_range * 0.5, 0.0))
	assert_eq(PlayerInput.npc_to_interact(sim, p.id, _center(), 0.5), NPC_ID)
	p.pos = Vector2(1.5, 1.5)
	assert_eq(PlayerInput.npc_to_interact(sim, p.id, _center(), 0.5), "", "too far: no interaction")
	assert_eq(PlayerInput.npc_to_interact(sim, p.id, Vector2(8.5, 3.5), 0.5), "", "no NPC under cursor")


func test_right_click_in_range_emits_signal_without_command() -> void:
	var sim := _sim()
	var p := _player(sim, _center() + Vector2(-_range * 0.5, 0.0))
	var input := PlayerInput.new()
	add_child_autofree(input)
	input.setup(p.id, sim, null, _registry)
	watch_signals(input)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	var cmd := input.handle_input(ev, _center())
	assert_null(cmd, "no move command when interacting")
	assert_signal_emitted_with_parameters(input, "npc_interact", [NPC_ID])
	assert_false(input.is_holding_right)


func test_right_click_out_of_range_walks_closer() -> void:
	var sim := _sim()
	var p := _player(sim, Vector2(1.5, 1.5))
	var input := PlayerInput.new()
	add_child_autofree(input)
	input.setup(p.id, sim, null, _registry)
	watch_signals(input)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	var cmd := input.handle_input(ev, _center())
	assert_signal_not_emitted(input, "npc_interact")
	assert_true(cmd is Commands.MoveTo, "falls back to move_to")


# --- merchant panel take logic ---

func test_take_item_moves_uid_and_survives_save_load() -> void:
	var world := WorldState.new()
	world.inventory = Inventory.new(_item_db)
	var inv := world.inventory
	var sword := inv.create("iron_sword", MerchantPanel.merchant_owner(NPC_ID))
	var potion := inv.create("healing_draught", MerchantPanel.merchant_owner(NPC_ID))
	var other := inv.create("iron_plate", "merchant:someone_else")
	var char_owner := "character:hero"

	var rows := MerchantPanel.stock_rows(inv, _item_db, NPC_ID)
	assert_eq(rows.size(), 2)
	assert_eq(rows[0]["uid"], sword)
	assert_eq(rows[0]["name"], str(_item_db.get_item("iron_sword")["name"]))

	assert_true(MerchantPanel.take_item(inv, NPC_ID, sword, char_owner))
	assert_eq(inv.owner_of(sword), char_owner)
	assert_eq(world.get_stock(NPC_ID), [potion])
	assert_false(MerchantPanel.take_item(inv, NPC_ID, sword, char_owner), "already taken")
	assert_false(MerchantPanel.take_item(inv, NPC_ID, other, char_owner), "not this merchant's stock")
	assert_false(MerchantPanel.take_item(inv, NPC_ID, potion, "merchant:x"), "recipient must be a character")
	assert_false(MerchantPanel.take_item(null, NPC_ID, potion, char_owner))

	var store := SaveStore.new(TEST_ROOT, _item_db)
	var save_res := store.save_world("slot_1", world)
	assert_true(save_res.get("ok", false), str(save_res.get("error")))
	var load_res := store.load_world("slot_1")
	assert_true(load_res.get("ok", false), str(load_res.get("error")))
	var loaded: WorldState = load_res.get("value")
	assert_not_null(loaded)
	assert_eq(loaded.get_character_items("hero"), [sword])
	assert_eq(loaded.get_stock(NPC_ID), [potion])


func test_panel_take_button_refreshes_list() -> void:
	var inv := Inventory.new(_item_db)
	var sword := inv.create("iron_sword", MerchantPanel.merchant_owner(NPC_ID))
	var panel := MerchantPanel.new()
	add_child_autofree(panel)
	watch_signals(panel)
	panel.open_for(_zone.npcs[0], inv, _item_db, "character:7")
	assert_true(panel.is_shown())
	assert_eq(panel.get_title(), "Test Smith - Merchant")
	assert_eq(panel.row_count(), 1)
	var btn := panel.rows_vbox.get_node("Row_%d/TakeButton" % sword) as Button
	assert_not_null(btn)
	btn.pressed.emit()
	assert_eq(inv.owner_of(sword), "character:7")
	assert_eq(panel.row_count(), 0)
	assert_signal_emitted_with_parameters(panel, "item_taken", [sword])
	panel.close_button.pressed.emit()
	assert_false(panel.is_shown())
	await wait_process_frames(1)  # let the queue_free'd rows go


func test_panel_esc_closes() -> void:
	var panel := MerchantPanel.new()
	add_child_autofree(panel)
	panel.open_for(_zone.npcs[0], Inventory.new(_item_db), _item_db, "character:1")
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.physical_keycode = KEY_ESCAPE
	ev.pressed = true
	panel._unhandled_input(ev)
	assert_false(panel.is_shown())


func test_npc_view_label_and_position() -> void:
	var root := Node2D.new()
	add_child_autofree(root)
	var views := NpcView.build_all(_zone, root)
	assert_eq(views.size(), 1)
	assert_eq(views[0].label.text, "Test Smith")
	assert_eq(views[0].position, ZoneView.tile_to_world_coords(NPC_TILE))
	assert_eq(NpcView.display_name_for({"id": "bare"}), "bare")


func test_hud_opens_merchant_and_closes_out_of_range() -> void:
	var sim := _sim()
	var p := _player(sim, _center() + Vector2(-_range * 0.5, 0.0))
	var inv := Inventory.new(_item_db)
	var hud := HUD.new()
	add_child_autofree(hud)
	hud.setup(null, sim, p, inv, _item_db, _registry)
	assert_true(hud.open_merchant(NPC_ID))
	assert_true(hud.get_merchant_panel().is_shown())
	assert_false(hud.open_merchant("nobody"))
	p.pos = Vector2(1.5, 1.5)
	hud.update_view()
	assert_false(hud.get_merchant_panel().is_shown(), "walking away closes it")
