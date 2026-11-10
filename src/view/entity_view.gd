class_name EntityView
extends Node2D

const DEFAULT_ENEMY_SIZE: float = 12.0
const DEFAULT_ENEMY_COLOR := Color(0.85, 0.25, 0.2, 1.0)
const DEFAULT_ENEMY_OUTLINE_COLOR := Color(0.1, 0.05, 0.05, 1.0)
const DEFAULT_HP_BAR_WIDTH: float = 24.0
const DEFAULT_HP_BAR_HEIGHT: float = 4.0
const DEFAULT_HP_BAR_Y_OFFSET: float = -18.0
const DEFAULT_HP_BAR_BG_COLOR := Color(0.1, 0.1, 0.1, 0.8)
const DEFAULT_HP_BAR_FILL_COLOR := Color(0.2, 0.8, 0.2, 1.0)
const DEFAULT_HP_BAR_BORDER_COLOR := Color(0.0, 0.0, 0.0, 0.9)

var entity_id: int = 0
var entity: Entity = null
var registry: DataRegistry = null
var zone_view: ZoneView = null

var hp: float = 100.0
var max_hp: float = 100.0
var hp_ratio: float = 1.0

var enemy_size: float = DEFAULT_ENEMY_SIZE
var enemy_color: Color = DEFAULT_ENEMY_COLOR
var enemy_outline_color: Color = DEFAULT_ENEMY_OUTLINE_COLOR
var hp_bar_width: float = DEFAULT_HP_BAR_WIDTH
var hp_bar_height: float = DEFAULT_HP_BAR_HEIGHT
var hp_bar_y_offset: float = DEFAULT_HP_BAR_Y_OFFSET
var hp_bar_bg_color: Color = DEFAULT_HP_BAR_BG_COLOR
var hp_bar_fill_color: Color = DEFAULT_HP_BAR_FILL_COLOR
var hp_bar_border_color: Color = DEFAULT_HP_BAR_BORDER_COLOR


static func parse_color(val: Variant, default_val: Color) -> Color:
	if val is Array:
		var arr: Array = val
		if arr.size() >= 3:
			var a: float = float(arr[3]) if arr.size() >= 4 else 1.0
			return Color(float(arr[0]), float(arr[1]), float(arr[2]), a)
	elif val is String:
		return Color.from_string(str(val), default_val)
	elif val is Color:
		return val
	return default_val


func setup(p_entity: Entity, p_zone_view: ZoneView, p_registry: DataRegistry) -> void:
	entity = p_entity
	if entity != null:
		entity_id = entity.id
	zone_view = p_zone_view
	registry = p_registry

	_load_balance_config()
	sync(1.0)


func _load_balance_config() -> void:
	if registry == null:
		return

	var size_val: Variant = registry.get_balance("view.enemy_size")
	if size_val != null and float(size_val) > 0.0:
		enemy_size = float(size_val)
	else:
		push_warning("EntityView: missing balance key 'view.enemy_size'")

	var color_val: Variant = registry.get_balance("view.enemy_color")
	if color_val != null:
		enemy_color = parse_color(color_val, DEFAULT_ENEMY_COLOR)
	else:
		push_warning("EntityView: missing balance key 'view.enemy_color'")

	var outline_val: Variant = registry.get_balance("view.enemy_outline_color")
	if outline_val != null:
		enemy_outline_color = parse_color(outline_val, DEFAULT_ENEMY_OUTLINE_COLOR)
	else:
		push_warning("EntityView: missing balance key 'view.enemy_outline_color'")

	var width_val: Variant = registry.get_balance("view.hp_bar_width")
	if width_val != null and float(width_val) > 0.0:
		hp_bar_width = float(width_val)
	else:
		push_warning("EntityView: missing balance key 'view.hp_bar_width'")

	var height_val: Variant = registry.get_balance("view.hp_bar_height")
	if height_val != null and float(height_val) > 0.0:
		hp_bar_height = float(height_val)
	else:
		push_warning("EntityView: missing balance key 'view.hp_bar_height'")

	var offset_val: Variant = registry.get_balance("view.hp_bar_y_offset")
	if offset_val != null:
		hp_bar_y_offset = float(offset_val)
	else:
		push_warning("EntityView: missing balance key 'view.hp_bar_y_offset'")

	var bg_val: Variant = registry.get_balance("view.hp_bar_bg_color")
	if bg_val != null:
		hp_bar_bg_color = parse_color(bg_val, DEFAULT_HP_BAR_BG_COLOR)
	else:
		push_warning("EntityView: missing balance key 'view.hp_bar_bg_color'")

	var fill_val: Variant = registry.get_balance("view.hp_bar_fill_color")
	if fill_val != null:
		hp_bar_fill_color = parse_color(fill_val, DEFAULT_HP_BAR_FILL_COLOR)
	else:
		push_warning("EntityView: missing balance key 'view.hp_bar_fill_color'")

	var border_val: Variant = registry.get_balance("view.hp_bar_border_color")
	if border_val != null:
		hp_bar_border_color = parse_color(border_val, DEFAULT_HP_BAR_BORDER_COLOR)
	else:
		push_warning("EntityView: missing balance key 'view.hp_bar_border_color'")


func sync(lerp_weight: float = 1.0) -> void:
	if entity == null:
		return

	if zone_view != null:
		var target_pos: Vector2 = zone_view.entity_to_world(entity.pos)
		if lerp_weight >= 1.0:
			position = target_pos
		else:
			position = position.lerp(target_pos, lerp_weight)

	hp = entity.hp
	max_hp = _resolve_max_hp()
	hp_ratio = clampf(hp / max_hp, 0.0, 1.0) if max_hp > 0.0 else 0.0

	queue_redraw()


func get_hp_ratio() -> float:
	return hp_ratio


func _resolve_max_hp() -> float:
	if entity != null:
		if entity.stats != null and entity.stats.max_hp > 0.0:
			return entity.stats.max_hp
		if registry != null and not entity.kind.is_empty():
			var val: Variant = registry.get_balance(entity.kind + ".max_hp")
			if val != null and float(val) > 0.0:
				return float(val)
	return 100.0


func _draw() -> void:
	# 1. Distinct enemy placeholder shape (hexagon)
	var hex_points := PackedVector2Array()
	var outline_points := PackedVector2Array()
	var sides := 6
	for i in range(sides):
		var angle := i * (TAU / float(sides)) - PI / 6.0
		var dir := Vector2(cos(angle), sin(angle))
		hex_points.append(dir * enemy_size)
		outline_points.append(dir * (enemy_size + 2.0))
	outline_points.append(outline_points[0])

	draw_polyline(outline_points, enemy_outline_color, 2.5)
	draw_colored_polygon(hex_points, enemy_color)

	# Enemy hostile center mark
	var center_pts := PackedVector2Array([
		Vector2(0, -enemy_size * 0.4),
		Vector2(enemy_size * 0.35, 0),
		Vector2(0, enemy_size * 0.4),
		Vector2(-enemy_size * 0.35, 0)
	])
	draw_colored_polygon(center_pts, enemy_outline_color)

	# 2. HP Bar
	var bar_left := -hp_bar_width / 2.0
	var border_rect := Rect2(bar_left - 1.0, hp_bar_y_offset - 1.0, hp_bar_width + 2.0, hp_bar_height + 2.0)
	var bg_rect := Rect2(bar_left, hp_bar_y_offset, hp_bar_width, hp_bar_height)

	draw_rect(border_rect, hp_bar_border_color)
	draw_rect(bg_rect, hp_bar_bg_color)

	var fill_width := hp_bar_width * hp_ratio
	if fill_width > 0.0:
		var fill_rect := Rect2(bar_left, hp_bar_y_offset, fill_width, hp_bar_height)
		draw_rect(fill_rect, hp_bar_fill_color)
