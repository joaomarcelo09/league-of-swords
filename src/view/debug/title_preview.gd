class_name TitlePreview
extends RefCounted

static var is_active: bool = false


static func check_preview_flag() -> bool:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--preview=title" or arg.begins_with("--preview=title") or arg == "--preview=title_screen" or arg.begins_with("--preview=title_screen"):
			return true
	return false


static func setup_if_requested(menu: TitleMenu) -> void:
	is_active = false
	if not check_preview_flag():
		return

	is_active = true
	_prepare(menu)


static func _prepare(menu: TitleMenu) -> void:
	if menu != null:
		menu.show_preview_state("Brannoc", 14, "floor1")
