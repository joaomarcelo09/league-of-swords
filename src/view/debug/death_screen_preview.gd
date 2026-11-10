class_name DeathScreenPreview
extends RefCounted

static var is_active: bool = false


static func check_preview_flag() -> bool:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--preview=death" or arg.begins_with("--preview=death") or arg == "--preview=death_screen" or arg.begins_with("--preview=death_screen"):
			return true
	return false


static func setup_if_requested(main: MainView) -> void:
	is_active = false
	if not check_preview_flag():
		return

	is_active = true
	_prepare(main)


static func _prepare(main: MainView) -> void:
	var entry := {
		"character_id": "char_1",
		"name": "Kite",
		"level": 14,
		"zone": "floor1",
		"cause": "dire_wolf",
		"date": "2026-11-10",
		"appearance": {}
	}
	if main.death_screen != null:
		main.death_screen.show_death(entry)
