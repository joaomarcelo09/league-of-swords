extends GutTest

const ScreenshotRunnerScript = preload("res://src/view/debug/screenshot_runner.gd")


func test_parse_args_empty() -> void:
	var result := ScreenshotRunnerScript.parse_args(PackedStringArray([]))
	assert_eq(result.size(), 0)


func test_parse_args_single_key_value() -> void:
	var args := PackedStringArray(["--screenshot=/path/to/shot.png"])
	var result := ScreenshotRunnerScript.parse_args(args)
	assert_eq(result.get("screenshot"), "/path/to/shot.png")


func test_parse_args_multiple_options() -> void:
	var args := PackedStringArray([
		"--screenshot=.screenshots/out.png",
		"--frames=45",
		"--scene=res://scenes/main.tscn",
	])
	var result := ScreenshotRunnerScript.parse_args(args)
	assert_eq(result.get("screenshot"), ".screenshots/out.png")
	assert_eq(result.get("frames"), "45")
	assert_eq(result.get("scene"), "res://scenes/main.tscn")


func test_parse_args_flag_without_value() -> void:
	var args := PackedStringArray(["--verbose", "--screenshot=a.png"])
	var result := ScreenshotRunnerScript.parse_args(args)
	assert_eq(result.get("verbose"), true)
	assert_eq(result.get("screenshot"), "a.png")


func test_parse_args_value_containing_equals() -> void:
	var args := PackedStringArray(["--custom=a=b=c"])
	var result := ScreenshotRunnerScript.parse_args(args)
	assert_eq(result.get("custom"), "a=b=c")


func test_parse_args_ignores_non_double_dash() -> void:
	var args := PackedStringArray(["positional", "-s", "--valid=yes"])
	var result := ScreenshotRunnerScript.parse_args(args)
	assert_false(result.has("positional"))
	assert_false(result.has("s"))
	assert_false(result.has("-s"))
	assert_eq(result.get("valid"), "yes")


func test_parse_args_bare_double_dash() -> void:
	var args := PackedStringArray(["--"])
	var result := ScreenshotRunnerScript.parse_args(args)
	assert_eq(result.size(), 0)


func test_parse_args_bare_screenshot() -> void:
	var args := PackedStringArray(["--screenshot"])
	var result := ScreenshotRunnerScript.parse_args(args)
	assert_true(result.has("screenshot"))
	assert_eq(result.get("screenshot"), true)


func test_parse_args_empty_screenshot_value() -> void:
	var args := PackedStringArray(["--screenshot="])
	var result := ScreenshotRunnerScript.parse_args(args)
	assert_true(result.has("screenshot"))
	assert_eq(result.get("screenshot"), "")


func test_is_valid_screenshot_value() -> void:
	assert_false(ScreenshotRunnerScript.is_valid_screenshot_value(true))
	assert_false(ScreenshotRunnerScript.is_valid_screenshot_value(false))
	assert_false(ScreenshotRunnerScript.is_valid_screenshot_value(123))
	assert_false(ScreenshotRunnerScript.is_valid_screenshot_value(null))
	assert_false(ScreenshotRunnerScript.is_valid_screenshot_value(""))
	assert_false(ScreenshotRunnerScript.is_valid_screenshot_value("   "))
	assert_false(ScreenshotRunnerScript.is_valid_screenshot_value("\t\n"))
	assert_true(ScreenshotRunnerScript.is_valid_screenshot_value("shot.png"))
	assert_true(ScreenshotRunnerScript.is_valid_screenshot_value("res://scenes/main.tscn"))
	assert_true(ScreenshotRunnerScript.is_valid_screenshot_value("/tmp/shot.png"))
	assert_true(ScreenshotRunnerScript.is_valid_screenshot_value(".screenshots/shot.png"))


func test_parse_tile_arg() -> void:
	assert_eq(ScreenshotRunnerScript.parse_tile_arg("27,8"), Vector2i(27, 8))
	assert_eq(ScreenshotRunnerScript.parse_tile_arg(" 3 , -4 "), Vector2i(3, -4))
	assert_null(ScreenshotRunnerScript.parse_tile_arg("27"))
	assert_null(ScreenshotRunnerScript.parse_tile_arg("a,b"))
	assert_null(ScreenshotRunnerScript.parse_tile_arg("1,2,3"))
	assert_null(ScreenshotRunnerScript.parse_tile_arg(true))


func test_camera_pin_ignores_follow() -> void:
	var cam: GameCamera = autofree(GameCamera.new())
	cam.pin_to(Vector2(100.0, 50.0))
	cam.follow(Vector2(5.0, 5.0))
	assert_true(cam.pinned)
	assert_eq(cam.position, Vector2(100.0, 50.0), "pinned camera ignores follow()")
	cam.pinned = false
	cam.follow(Vector2(5.0, 5.0))
	assert_eq(cam.position, Vector2(5.0, 5.0))
