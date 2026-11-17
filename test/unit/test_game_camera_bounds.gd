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
