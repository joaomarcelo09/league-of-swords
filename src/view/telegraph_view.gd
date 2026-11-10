class_name TelegraphView
extends Node2D

const DEFAULT_TELEGRAPH_COLOR := Color(1.0, 0.15, 0.15, 0.35)
const DEFAULT_TELEGRAPH_FILL_COLOR := Color(1.0, 0.1, 0.1, 0.7)
const DEFAULT_TELEGRAPH_LINE_COLOR := Color(1.0, 0.2, 0.2, 0.9)

var progress: float = 0.0
var elapsed: float = 0.0
var duration_s: float = 1.0

var shape_type: String = ""
var origin: Vector2 = Vector2.ZERO
var dir: Vector2 = Vector2.RIGHT
var range_val: float = 0.0
var width_val: float = 0.0
var angle_deg: float = 0.0
var radius_val: float = 0.0
var tile_px: int = 32

var telegraph_color: Color = DEFAULT_TELEGRAPH_COLOR
var telegraph_fill_color: Color = DEFAULT_TELEGRAPH_FILL_COLOR
var telegraph_line_color: Color = DEFAULT_TELEGRAPH_LINE_COLOR


func setup(event: Dictionary, p_tile_px: int, registry: DataRegistry = null) -> void:
	tile_px = p_tile_px
	origin = event.get("origin", Vector2.ZERO)
	dir = event.get("dir", Vector2.RIGHT)
	shape_type = str(event.get("shape", ""))
	duration_s = float(event.get("duration_s", event.get("duration", 1.0)))

	range_val = float(event.get("range", 0.0))
	width_val = float(event.get("width", 0.0))
	angle_deg = float(event.get("angle_deg", 0.0))
	radius_val = float(event.get("radius", 0.0))

	position = origin * float(tile_px)
	z_index = 0

	_load_balance_config(registry)
	queue_redraw()


func _load_balance_config(registry: DataRegistry) -> void:
	if registry == null:
		return

	var color_val: Variant = registry.get_balance("view.telegraph_color")
	if color_val != null:
		telegraph_color = EntityView.parse_color(color_val, DEFAULT_TELEGRAPH_COLOR)
	else:
		push_warning("TelegraphView: missing balance key 'view.telegraph_color'")

	var fill_val: Variant = registry.get_balance("view.telegraph_fill_color")
	if fill_val != null:
		telegraph_fill_color = EntityView.parse_color(fill_val, DEFAULT_TELEGRAPH_FILL_COLOR)
	else:
		push_warning("TelegraphView: missing balance key 'view.telegraph_fill_color'")

	var line_val: Variant = registry.get_balance("view.telegraph_line_color")
	if line_val != null:
		telegraph_line_color = EntityView.parse_color(line_val, DEFAULT_TELEGRAPH_LINE_COLOR)
	else:
		push_warning("TelegraphView: missing balance key 'view.telegraph_line_color'")


func advance(dt: float) -> void:
	if is_queued_for_deletion():
		return

	elapsed += dt
	if duration_s > 0.0:
		progress = clampf(elapsed / duration_s, 0.0, 1.0)
	else:
		progress = 1.0

	queue_redraw()

	if elapsed >= duration_s - 1e-6:
		queue_free()


func _process(delta: float) -> void:
	advance(delta)


func _draw() -> void:
	match shape_type:
		"cone":
			_draw_cone()
		"line":
			_draw_line()
		"circle":
			_draw_circle()


func _draw_cone() -> void:
	var r_px := range_val * float(tile_px)
	if r_px <= 0.0 or angle_deg <= 0.0:
		return

	var base_angle: float = dir.angle() if not dir.is_zero_approx() else 0.0
	var half_angle := deg_to_rad(angle_deg / 2.0)
	var start_angle := base_angle - half_angle
	var end_angle := base_angle + half_angle

	var segments := 24

	# Background full cone
	var bg_points := PackedVector2Array()
	bg_points.append(Vector2.ZERO)
	for i in range(segments + 1):
		var a := start_angle + (end_angle - start_angle) * (float(i) / float(segments))
		bg_points.append(Vector2(cos(a), sin(a)) * r_px)

	draw_colored_polygon(bg_points, telegraph_color)

	# Outline
	var outline_points := bg_points.duplicate()
	outline_points.append(Vector2.ZERO)
	draw_polyline(outline_points, telegraph_line_color, 2.0)

	# Filling progress cone
	if progress > 0.0:
		var fill_r := r_px * progress
		var fill_points := PackedVector2Array()
		fill_points.append(Vector2.ZERO)
		for i in range(segments + 1):
			var a := start_angle + (end_angle - start_angle) * (float(i) / float(segments))
			fill_points.append(Vector2(cos(a), sin(a)) * fill_r)
		draw_colored_polygon(fill_points, telegraph_fill_color)


func _draw_line() -> void:
	var length_px := range_val * float(tile_px)
	var width_px := width_val * float(tile_px)
	if length_px <= 0.0 or width_px <= 0.0:
		return

	var d: Vector2 = dir.normalized() if not dir.is_zero_approx() else Vector2.RIGHT
	var perp := Vector2(-d.y, d.x)
	var hw := perp * (width_px / 2.0)

	# Full background rectangle
	var p0 := -hw
	var p1 := hw
	var p2 := d * length_px + hw
	var p3 := d * length_px - hw

	var bg_rect := PackedVector2Array([p0, p1, p2, p3])
	draw_colored_polygon(bg_rect, telegraph_color)

	var outline := PackedVector2Array([p0, p1, p2, p3, p0])
	draw_polyline(outline, telegraph_line_color, 2.0)

	# Filling progress rectangle
	if progress > 0.0:
		var fill_len := length_px * progress
		var fp2 := d * fill_len + hw
		var fp3 := d * fill_len - hw
		var fill_rect := PackedVector2Array([p0, p1, fp2, fp3])
		draw_colored_polygon(fill_rect, telegraph_fill_color)


func get_circle_center_px() -> Vector2:
	if range_val <= 0.0:
		return Vector2.ZERO
	var offset: Vector2 = dir
	if offset.length() > range_val:
		offset = offset.normalized() * range_val
	return offset * float(tile_px)


func _draw_circle() -> void:
	var radius_px := radius_val * float(tile_px)
	if radius_px <= 0.0:
		return

	var center := get_circle_center_px()

	# Full background circle
	draw_circle(center, radius_px, telegraph_color)
	draw_arc(center, radius_px, 0.0, TAU, 32, telegraph_line_color, 2.0)

	# Filling progress circle
	if progress > 0.0:
		draw_circle(center, radius_px * progress, telegraph_fill_color)
