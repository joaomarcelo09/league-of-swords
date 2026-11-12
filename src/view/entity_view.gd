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
const ENEMIES_TABLE: String = "enemies"
const APPEARANCES_TABLE: String = "appearances"
const LAYOUT_DIR: String = "res://data/sprites/"
const DEFAULT_VIEW_SCALE: float = 1.0

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

## Layered LPC sprite built from the enemy type's "appearance" (null = hexagon fallback).
var sprite: LayeredSprite = null
var sprite_source: String = CharacterAppearance.SOURCE_NONE
## Visual-only sprite scale from the enemy type's "view_scale" (logic hitbox unchanged).
var view_scale: float = DEFAULT_VIEW_SCALE
var animator: CharacterAnimator = CharacterAnimator.new()
## Sim clock, set by EntityLayer before each sync (drives the hurt reaction).
var now_tick: int = 0
var tick_length: float = 0.0
## Attack direction from this frame's telegraph_start event (consumed by the next sync).
var _pending_attack_dir: Variant = null


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
	_build_sprite()
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

	if sprite != null:
		var attack_dir: Variant = _pending_attack_dir
		_pending_attack_dir = null
		animator.update(sprite, entity.pos, entity.dead, attack_dir, now_tick)

	queue_redraw()


## Pure: resolves an enemy "layout" value to a res:// path. "" -> the default LPC layout,
## a res:// path is used as is, a bare id "<name>" -> data/sprites/layout_<name>.json.
static func layout_path_for(layout_val: String) -> String:
	var v := layout_val.strip_edges()
	if v.is_empty():
		return LayeredSprite.DEFAULT_LAYOUT_PATH
	if v.begins_with("res://"):
		return v
	return LAYOUT_DIR + "layout_%s.json" % v


## Pure: seconds the death animation of p_layout lasts (frame_count / fps), 0 if none.
static func death_seconds_from_layout(p_layout: Dictionary) -> float:
	var anims: Dictionary = p_layout.get("animations", {})
	var death: Variant = anims.get(AnimState.ANIM_DEATH, null)
	if not (death is Dictionary):
		return 0.0
	var fps: float = float((death as Dictionary).get("fps", 0.0))
	var frames: int = int((death as Dictionary).get("frame_count", 0))
	if fps <= 0.0 or frames <= 0:
		return 0.0
	return float(frames) / fps


## Pure: an enemy entry's "view_scale" (default 1.0; non-numbers or <= 0 fall back).
static func view_scale_from_entry(enemy_entry: Dictionary) -> float:
	var val: Variant = enemy_entry.get("view_scale", null)
	if (val is float or val is int) and float(val) > 0.0:
		return float(val)
	return DEFAULT_VIEW_SCALE


## True if this view draws a layered sprite (false = hexagon fallback).
func has_sprite() -> bool:
	return sprite != null


## Seconds a dead view should stay on screen to play its death animation (0 = free at once).
func death_seconds() -> float:
	if sprite == null:
		return 0.0
	return death_seconds_from_layout(sprite.layout)


## The HP bar hides once the entity is dead (a lingering sprite plays its death).
func is_hp_bar_visible() -> bool:
	return entity == null or not entity.dead


## View-only: the entity started an attack (telegraph_start) toward dir.
func notify_attack(dir: Vector2) -> void:
	_pending_attack_dir = dir


## View-only: the entity took damage at sim tick p_tick.
func notify_hurt(p_tick: int, p_tick_length: float) -> void:
	if sprite != null:
		animator.trigger_hurt(sprite, p_tick, p_tick_length)


## Builds the LayeredSprite from the enemy type's "appearance" (data/enemies.json ->
## data/appearances.json). Leaves sprite null (hexagon fallback) when the type has no
## appearance or no art can be loaded.
func _build_sprite() -> void:
	if entity == null or registry == null:
		return
	var type_id := entity.enemy_type_id if not entity.enemy_type_id.is_empty() else entity.kind
	var enemy_entry := registry.get_entry(ENEMIES_TABLE, type_id)
	view_scale = view_scale_from_entry(enemy_entry)
	var appearance_id := str(enemy_entry.get("appearance", "")).strip_edges()
	if appearance_id.is_empty():
		return
	var appearance := registry.get_entry(APPEARANCES_TABLE, appearance_id)
	if appearance.is_empty():
		push_warning("EntityView: appearance '%s' of '%s' missing; using hexagon" % [appearance_id, type_id])
		return
	var layout_path := layout_path_for(str(enemy_entry.get("layout", "")))
	var new_sprite := LayeredSprite.new(layout_path)
	if new_sprite.layout.is_empty():
		new_sprite.free()
		return
	var built := CharacterAppearance.build_textures(appearance, new_sprite.layout)
	var textures: Dictionary = built.get("layers", {})
	if textures.is_empty():
		new_sprite.free()
		return
	sprite_source = str(built.get("source", CharacterAppearance.SOURCE_NONE))
	new_sprite.name = "EnemySprite"
	# Drawn behind this node's own _draw so the HP bar stays on top of the sprite.
	new_sprite.show_behind_parent = true
	new_sprite.set_layer_textures(textures)
	new_sprite.play(CharacterAnimator.ANIM_IDLE, AnimState.DIR_DOWN)
	new_sprite.scale = Vector2(view_scale, view_scale)
	add_child(new_sprite)
	sprite = new_sprite
	animator.reset(entity.pos)
	var hp_off: Variant = sprite.layout.get("hp_bar_y_offset", null)
	if hp_off is float or hp_off is int:
		hp_bar_y_offset = float(hp_off)
	# Keep the HP bar above a scaled-up sprite's head.
	hp_bar_y_offset *= view_scale


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
	if sprite != null:
		# Sprite enemies: only the HP bar, hidden once dead (death animation plays).
		if is_hp_bar_visible():
			_draw_hp_bar()
		return

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
	_draw_hp_bar()


func _draw_hp_bar() -> void:
	var bar_left := -hp_bar_width / 2.0
	var border_rect := Rect2(bar_left - 1.0, hp_bar_y_offset - 1.0, hp_bar_width + 2.0, hp_bar_height + 2.0)
	var bg_rect := Rect2(bar_left, hp_bar_y_offset, hp_bar_width, hp_bar_height)

	draw_rect(border_rect, hp_bar_border_color)
	draw_rect(bg_rect, hp_bar_bg_color)

	var fill_width := hp_bar_width * hp_ratio
	if fill_width > 0.0:
		var fill_rect := Rect2(bar_left, hp_bar_y_offset, fill_width, hp_bar_height)
		draw_rect(fill_rect, hp_bar_fill_color)
