extends Node

const DEFAULT_FRAMES: int = 60


## Parses command-line arguments formatted as --key=val or --flag into a Dictionary.
static func parse_args(args: PackedStringArray) -> Dictionary:
	var result: Dictionary = {}
	for arg in args:
		if arg.begins_with("--"):
			var trimmed: String = arg.substr(2)
			if trimmed.is_empty():
				continue
			var eq_idx: int = trimmed.find("=")
			if eq_idx != -1:
				var key: String = trimmed.substr(0, eq_idx)
				var val: String = trimmed.substr(eq_idx + 1)
				result[key] = val
			else:
				result[trimmed] = true
	return result


## Returns true if the given value is a non-empty string.
static func is_valid_screenshot_value(val: Variant) -> bool:
	if typeof(val) != TYPE_STRING:
		return false
	return not (val as String).strip_edges().is_empty()


## Parses "x,y" into a Vector2i tile, or null when malformed.
static func parse_tile_arg(val: Variant) -> Variant:
	if typeof(val) != TYPE_STRING:
		return null
	var parts := (val as String).strip_edges().split(",")
	if parts.size() != 2 or not parts[0].strip_edges().is_valid_int() or not parts[1].strip_edges().is_valid_int():
		return null
	return Vector2i(int(parts[0].strip_edges()), int(parts[1].strip_edges()))


func _ready() -> void:
	var args := parse_args(OS.get_cmdline_user_args())
	if not args.has("screenshot"):
		return

	var raw_val: Variant = args["screenshot"]
	if typeof(raw_val) != TYPE_STRING:
		push_error("ScreenshotRunner: --screenshot requires a String path, got %s" % type_string(typeof(raw_val)))
		get_tree().quit(1)
		return

	var screenshot_path := (raw_val as String).strip_edges()
	if screenshot_path.is_empty():
		push_error("ScreenshotRunner: --screenshot path must not be empty")
		get_tree().quit(1)
		return

	if TitlePreview.check_preview_flag():
		var cur_scene := get_tree().current_scene
		if cur_scene == null or cur_scene.scene_file_path != "res://scenes/title.tscn":
			get_tree().change_scene_to_file("res://scenes/title.tscn")

	var frames_to_wait := DEFAULT_FRAMES
	if args.has("frames"):
		var parsed_frames := int(args["frames"])
		if parsed_frames > 0:
			frames_to_wait = parsed_frames

	var focus_tile: Variant = null
	if args.has("focus_tile"):
		focus_tile = parse_tile_arg(args["focus_tile"])
		if focus_tile == null:
			push_error("ScreenshotRunner: --focus_tile must be 'x,y', got %s" % str(args["focus_tile"]))
			get_tree().quit(1)
			return

	_capture_screenshot(screenshot_path, frames_to_wait, focus_tile)


func _capture_screenshot(screenshot_path: String, frames_to_wait: int, focus_tile: Variant = null) -> void:
	for i in range(frames_to_wait):
		await get_tree().process_frame
		if i == 0 and focus_tile != null:
			_focus_camera(focus_tile as Vector2i)

	await RenderingServer.frame_post_draw

	var viewport := get_viewport()
	if viewport == null:
		push_error("ScreenshotRunner: Viewport is null")
		get_tree().quit(1)
		return

	var texture := viewport.get_texture()
	if texture == null:
		push_error("ScreenshotRunner: Viewport texture is null")
		get_tree().quit(1)
		return

	var image := texture.get_image()
	if image == null:
		push_error("ScreenshotRunner: Failed to get image from texture")
		get_tree().quit(1)
		return

	var dir_path := screenshot_path.get_base_dir()
	if not dir_path.is_empty() and not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	var err := image.save_png(screenshot_path)
	if err != OK:
		push_error("ScreenshotRunner: Failed to save PNG to %s, error code: %d" % [screenshot_path, err])
		get_tree().quit(1)
		return

	get_tree().quit(0)


## Pins the main scene camera on a tile (centre) so a screenshot can frame any room.
func _focus_camera(tile: Vector2i) -> void:
	var scene := get_tree().current_scene
	if not (scene is MainView):
		push_warning("ScreenshotRunner: --focus_tile needs the main scene, ignored")
		return
	var main := scene as MainView
	if main.camera == null or main.zone_view == null:
		push_warning("ScreenshotRunner: main scene has no camera/zone view, --focus_tile ignored")
		return
	main.camera.pin_to(main.zone_view.tile_to_world(tile))
