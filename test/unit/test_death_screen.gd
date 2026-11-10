extends GutTest


func test_death_screen_ui_creation() -> void:
	var screen := DeathScreen.new()
	autofree(screen)

	assert_not_null(screen.name_label)
	assert_not_null(screen.level_label)
	assert_not_null(screen.zone_label)
	assert_not_null(screen.cause_label)
	assert_not_null(screen.date_label)
	assert_not_null(screen.name_input)
	assert_not_null(screen.start_button)
	assert_not_null(screen.error_label)
	assert_false(screen.is_open())
	assert_false(screen.visible)


func test_death_screen_shows_cemetery_entry() -> void:
	var screen := DeathScreen.new()
	autofree(screen)

	var entry := {
		"character_id": "char_1",
		"name": "Alden",
		"level": 3,
		"zone": "floor1",
		"cause": "dire_wolf",
		"date": "2026-11-10",
		"appearance": {}
	}
	screen.show_death(entry)

	assert_true(screen.is_open())
	assert_true(screen.visible)
	assert_eq(screen.name_label.text, "Alden")
	assert_eq(screen.level_label.text, "3")
	assert_eq(screen.zone_label.text, "floor1")
	assert_eq(screen.cause_label.text, "dire_wolf")
	assert_eq(screen.date_label.text, "2026-11-10")
	assert_eq(screen.name_input.text, "")
	assert_false(screen.error_label.visible)


func test_death_screen_rejects_empty_name_without_signal() -> void:
	var screen := DeathScreen.new()
	autofree(screen)
	screen.show_death({"name": "Alden"})

	watch_signals(screen)

	screen.name_input.text = "   "
	screen.start_button.pressed.emit()

	assert_signal_not_emitted(screen, "new_character_requested")
	assert_true(screen.error_label.visible)
	assert_true(screen.error_label.text.contains("empty"))


func test_death_screen_emits_valid_name() -> void:
	var screen := DeathScreen.new()
	autofree(screen)
	screen.show_death({"name": "Alden"})

	watch_signals(screen)

	screen.name_input.text = "  Brand  "
	screen.start_button.pressed.emit()

	assert_signal_emitted(screen, "new_character_requested")
	var params: Array = get_signal_parameters(screen, "new_character_requested")
	assert_eq(params.size(), 1)
	assert_eq(params[0], "Brand")
	assert_false(screen.error_label.visible)


func test_death_screen_show_and_clear_error() -> void:
	var screen := DeathScreen.new()
	autofree(screen)

	screen.show_error("Test failure")
	assert_true(screen.error_label.visible)
	assert_eq(screen.error_label.text, "Test failure")

	screen.clear_error()
	assert_false(screen.error_label.visible)
	assert_eq(screen.error_label.text, "")


func test_death_screen_close() -> void:
	var screen := DeathScreen.new()
	autofree(screen)
	screen.show_death({"name": "Alden"})
	assert_true(screen.is_open())

	screen.close()
	assert_false(screen.is_open())
	assert_false(screen.visible)
