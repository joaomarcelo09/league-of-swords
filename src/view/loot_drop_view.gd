class_name LootDropView
extends Node2D

const DEFAULT_MARKER_SIZE: float = 8.0
const DEFAULT_MARKER_COLOR := Color(1.0, 0.84, 0.0, 1.0)
const DEFAULT_BORDER_COLOR := Color(0.1, 0.1, 0.1, 0.9)
const DEFAULT_LABEL_COLOR := Color(1.0, 1.0, 1.0, 1.0)

var uid: int = 0
var tile: Vector2i = Vector2i.ZERO
var def_id: String = ""
var item_name: String = ""
var marker_size: float = DEFAULT_MARKER_SIZE
var marker_color: Color = DEFAULT_MARKER_COLOR
var marker_border_color: Color = DEFAULT_BORDER_COLOR
var label_color: Color = DEFAULT_LABEL_COLOR
var label: Label = null


func setup(
	p_uid: int,
	p_tile: Vector2i,
	p_def_id: String,
	p_item_name: String,
	p_world_pos: Vector2,
	p_registry: DataRegistry = null
) -> void:
	uid = p_uid
	tile = p_tile
	def_id = p_def_id
	item_name = p_item_name
	position = p_world_pos

	if p_registry != null:
		var size_val: Variant = p_registry.get_balance("view.loot_marker_size")
		if size_val != null and float(size_val) > 0.0:
			marker_size = float(size_val)
		var color_val: Variant = p_registry.get_balance("view.loot_marker_color")
		if color_val != null:
			marker_color = parse_color(color_val, DEFAULT_MARKER_COLOR)
		var border_val: Variant = p_registry.get_balance("view.loot_marker_border_color")
		if border_val != null:
			marker_border_color = parse_color(border_val, DEFAULT_BORDER_COLOR)
		var label_val: Variant = p_registry.get_balance("view.loot_label_color")
		if label_val != null:
			label_color = parse_color(label_val, DEFAULT_LABEL_COLOR)

	_setup_label()
	queue_redraw()


func _setup_label() -> void:
	if label != null:
		label.queue_free()

	label = Label.new()
	label.name = "ItemLabel"
	label.text = item_name
	label.position = Vector2(-60.0, -marker_size - 18.0)
	label.size = Vector2(120.0, 16.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", label_color)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(label)


func _draw() -> void:
	var s := marker_size
	# Draw diamond shape
	var diamond := PackedVector2Array([
		Vector2(0, -s),
		Vector2(s, 0),
		Vector2(0, s),
		Vector2(-s, 0)
	])
	draw_colored_polygon(diamond, marker_color)
	# Draw border
	var border := PackedVector2Array([
		Vector2(0, -s),
		Vector2(s, 0),
		Vector2(0, s),
		Vector2(-s, 0),
		Vector2(0, -s)
	])
	draw_polyline(border, marker_border_color, 1.5)


static func parse_color(val: Variant, fallback: Color) -> Color:
	if val is Color:
		return val
	if val is Array:
		var arr: Array = val
		if arr.size() >= 4:
			return Color(float(arr[0]), float(arr[1]), float(arr[2]), float(arr[3]))
		elif arr.size() == 3:
			return Color(float(arr[0]), float(arr[1]), float(arr[2]), 1.0)
	return fallback
