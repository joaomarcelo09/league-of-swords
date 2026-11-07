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
