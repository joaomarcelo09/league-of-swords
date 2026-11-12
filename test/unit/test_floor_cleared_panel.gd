extends GutTest
## JGT-82: floor-cleared panel, shown by HUD on floor_cleared, dismissed by Continue.

const EVENT := {"type": "floor_cleared", "tick": 0, "to_zone": "floor2", "label": "Stairs to Floor 2", "tile": Vector2i(3, 3)}


func test_hidden_by_default() -> void:
	var panel := FloorClearedPanel.new()
	add_child_autofree(panel)
	assert_false(panel.visible)
	assert_false(panel.is_shown())


func test_show_and_dismiss() -> void:
	var panel := FloorClearedPanel.new()
	add_child_autofree(panel)
	panel.show_for_event(EVENT, "floor1")
	assert_true(panel.visible)
	assert_eq(panel.get_message(), "Floor 1 cleared, more floors coming")
	panel.continue_button.pressed.emit()
	assert_false(panel.visible, "Continue hides the panel")


func test_floor_number_resolution() -> void:
	assert_eq(FloorClearedPanel.floor_number_for(EVENT, "floor3"), 3, "zone id wins")
	assert_eq(FloorClearedPanel.floor_number_for(EVENT, ""), 1, "to_zone floor2 -> cleared floor 1")
	assert_eq(FloorClearedPanel.floor_number_for({"to_zone": "town"}, "test"), 0)
	assert_eq(FloorClearedPanel.message_for(0), "Floor cleared, more floors coming")
	assert_eq(FloorClearedPanel.trailing_number("floor12"), 12)
	assert_eq(FloorClearedPanel.trailing_number(""), 0)


func test_hud_shows_panel_on_floor_cleared_event_only() -> void:
	var hud := HUD.new()
	add_child_autofree(hud)
	var panel := hud.get_floor_cleared_panel()
	assert_not_null(panel)
	assert_false(panel.visible, "hidden by default")
	hud.handle_event({"type": "exit_locked", "boss": "floor1_warden", "label": "x", "tile": Vector2i.ZERO})
	assert_false(panel.visible, "exit_locked does not show it")
	hud.handle_event(EVENT)
	assert_true(panel.visible, "floor_cleared shows it")
	assert_eq(panel.get_message(), "Floor 1 cleared, more floors coming")
	panel.dismiss()
	hud.update_view()
	assert_false(panel.visible, "dismissed stays dismissed")
	hud.handle_event(EVENT)
	assert_true(panel.visible, "next floor_cleared shows it again")
