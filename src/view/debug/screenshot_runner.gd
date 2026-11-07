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

	var frames_to_wait := DEFAULT_FRAMES
	if args.has("frames"):
		var parsed_frames := int(args["frames"])
		if parsed_frames > 0:
			frames_to_wait = parsed_frames

	_capture_screenshot(screenshot_path, frames_to_wait)


func _capture_screenshot(screenshot_path: String, frames_to_wait: int) -> void:
	for _i in range(frames_to_wait):
		await get_tree().process_frame

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
