extends GutTest
## JGT-127: pure camera clamp to the map bounds.

const VIEW := Vector2(320.0, 180.0)
const BOUNDS := Rect2(Vector2.ZERO, Vector2(1000.0, 600.0))


func test_inside_bounds_is_unchanged() -> void:
	assert_eq(GameCamera.clamp_to_bounds(Vector2(500.0, 300.0), VIEW, BOUNDS), Vector2(500.0, 300.0))


func test_clamps_to_each_edge() -> void:
	assert_eq(GameCamera.clamp_to_bounds(Vector2(-50.0, 300.0), VIEW, BOUNDS), Vector2(160.0, 300.0), "left")
	assert_eq(GameCamera.clamp_to_bounds(Vector2(1500.0, 300.0), VIEW, BOUNDS), Vector2(840.0, 300.0), "right")
	assert_eq(GameCamera.clamp_to_bounds(Vector2(500.0, -10.0), VIEW, BOUNDS), Vector2(500.0, 90.0), "top")
	assert_eq(GameCamera.clamp_to_bounds(Vector2(500.0, 700.0), VIEW, BOUNDS), Vector2(500.0, 510.0), "bottom")


func test_clamps_corners_on_both_axes() -> void:
	assert_eq(GameCamera.clamp_to_bounds(Vector2(-100.0, -100.0), VIEW, BOUNDS), Vector2(160.0, 90.0))
	assert_eq(GameCamera.clamp_to_bounds(Vector2(2000.0, 2000.0), VIEW, BOUNDS), Vector2(840.0, 510.0))


func test_map_smaller_than_view_is_centred() -> void:
	var small := Rect2(Vector2.ZERO, Vector2(200.0, 100.0))
	assert_eq(GameCamera.clamp_to_bounds(Vector2(-500.0, 900.0), VIEW, small), Vector2(100.0, 50.0))


func test_small_map_keeps_bounds_origin() -> void:
	var offset := Rect2(Vector2(10.0, 20.0), Vector2(200.0, 100.0))
	assert_eq(GameCamera.clamp_to_bounds(Vector2(0.0, 0.0), VIEW, offset), Vector2(110.0, 70.0))


func test_zero_sized_bounds_disable_the_clamp() -> void:
	var pos := Vector2(42.0, -7.0)
	assert_eq(GameCamera.clamp_to_bounds(pos, VIEW, Rect2()), pos)
	assert_eq(GameCamera.clamp_to_bounds(pos, VIEW, Rect2(0.0, 0.0, 0.0, 50.0)), pos)


func test_axis_only_smaller_than_view_is_centred_independently() -> void:
	var wide_short := Rect2(Vector2.ZERO, Vector2(1000.0, 100.0))
	assert_eq(GameCamera.clamp_to_bounds(Vector2(500.0, 0.0), VIEW, wide_short), Vector2(500.0, 50.0))
	assert_eq(GameCamera.clamp_to_bounds(Vector2(0.0, 500.0), VIEW, wide_short), Vector2(160.0, 50.0))


func test_floor1_world_bounds_are_the_map_size_in_pixels() -> void:
	var world := ChunkedWorld.load_file(
		"res://data/zones/floor1/world.json",
		"res://data/zones/floor1",
		"floor1_x2_y1"
	)
	assert_true(world.is_valid(), "floor 1 must load: %s" % str(world.errors))
	var tiles := Vector2(float(world.world_width()), float(world.world_height()))
	assert_eq(tiles, Vector2(288.0, 128.0), "the 9x4 chunk grid is 288x128 tiles")

	var registry := DataRegistry.new()
	registry.load_dir("res://data")
	var tile_px := float(registry.get_balance("view.tile_px"))
	var bounds := GameCamera.bounds_for(tiles, tile_px)

	assert_gt(tile_px, 0.0, "the tile size comes from balance data")
	assert_eq(bounds, Rect2(Vector2.ZERO, Vector2(288.0, 128.0) * tile_px), "bounds cover the whole floor in pixels")
	assert_eq(
		GameCamera.clamp_to_bounds(Vector2(-500.0, -500.0), VIEW, bounds),
		Vector2(VIEW.x * 0.5, VIEW.y * 0.5),
		"the camera cannot show the void past the north-west corner"
	)
	assert_eq(
		GameCamera.clamp_to_bounds(Vector2(99999.0, 99999.0), VIEW, bounds),
		bounds.size - Vector2(VIEW.x * 0.5, VIEW.y * 0.5),
		"the camera cannot show the void past the south-east corner"
	)


func test_bounds_for_empty_or_invalid_input_is_empty() -> void:
	assert_eq(GameCamera.bounds_for(Vector2.ZERO, 32.0), Rect2())
	assert_eq(GameCamera.bounds_for(Vector2(10.0, 10.0), 0.0), Rect2())
