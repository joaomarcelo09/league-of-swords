class_name BossBar
extends Control
## Top-centre HUD bar for the boss: name + HP fill. View-only, reads logic state.
## Visible while a living boss entity (is_boss) is aggroed (target_id != 0).

const DEFAULT_WIDTH: float = 420.0
const DEFAULT_HEIGHT: float = 18.0
const DEFAULT_TOP_MARGIN: float = 16.0
const NAME_HEIGHT: float = 20.0
const NAME_FONT_SIZE: int = 15
const HP_FONT_SIZE: int = 11
const DEFAULT_BG_COLOR := Color(0.1, 0.06, 0.06, 0.88)
const DEFAULT_FILL_COLOR := Color(0.78, 0.16, 0.14, 1.0)
const DEFAULT_BORDER_COLOR := Color(0.05, 0.03, 0.03, 0.95)
const NAME_COLOR := Color(1.0, 0.9, 0.75, 1.0)
const ENEMIES_TABLE: String = "enemies"

var bar_width: float = DEFAULT_WIDTH
var bar_height: float = DEFAULT_HEIGHT
var bg_color: Color = DEFAULT_BG_COLOR
var fill_color: Color = DEFAULT_FILL_COLOR
var border_color: Color = DEFAULT_BORDER_COLOR

var ratio: float = 1.0
var boss_entity_id: int = 0
var name_label: Label = null
var hp_label: Label = null


func _init() -> void:
	name = "BossBar"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label = _make_label("BossName", NAME_FONT_SIZE, NAME_COLOR)
	hp_label = _make_label("BossHP", HP_FONT_SIZE, Color(1.0, 1.0, 1.0, 1.0))
	add_child(name_label)
	add_child(hp_label)
	_relayout()
	visible = false


func _make_label(p_name: String, font_size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.name = p_name
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	return lbl


func _relayout() -> void:
	custom_minimum_size = Vector2(bar_width, NAME_HEIGHT + bar_height)
	size = custom_minimum_size
	name_label.position = Vector2.ZERO
	name_label.size = Vector2(bar_width, NAME_HEIGHT)
	hp_label.position = Vector2(0.0, NAME_HEIGHT)
	hp_label.size = Vector2(bar_width, bar_height)
	queue_redraw()


## Centres the bar at the top of a viewport of the given width.
func place_top_center(viewport_width: float) -> void:
	position = Vector2((viewport_width - bar_width) / 2.0, DEFAULT_TOP_MARGIN)


## Applies optional colours from balance.json "view.hud_boss_bar_*" keys.
func apply_registry(registry: DataRegistry) -> void:
	if registry == null:
		return
	var bg: Variant = registry.get_balance("view.hud_boss_bar_bg_color")
	if bg != null:
		bg_color = HUD.parse_color(bg, DEFAULT_BG_COLOR)
	var fill: Variant = registry.get_balance("view.hud_boss_bar_fill_color")
	if fill != null:
		fill_color = HUD.parse_color(fill, DEFAULT_FILL_COLOR)
	var border: Variant = registry.get_balance("view.hud_boss_bar_border_color")
	if border != null:
		border_color = HUD.parse_color(border, DEFAULT_BORDER_COLOR)
	queue_redraw()


## Shows the bar for the aggroed living boss in world (if any), hides it otherwise.
func update_from_world(world: WorldSim, registry: DataRegistry) -> void:
	var boss: Entity = null
	if world != null:
		boss = find_aggroed_boss(world.entities)
	if boss == null:
		boss_entity_id = 0
		visible = false
		return
	boss_entity_id = boss.id
	var max_hp := boss.stats.max_hp if boss.stats != null and boss.stats.max_hp > 0.0 else maxf(boss.hp, 1.0)
	set_boss(boss_display_name(boss, registry), boss.hp, max_hp)
	visible = true


func set_boss(display_name: String, hp: float, max_hp: float) -> void:
	ratio = HUD.hp_fraction(hp, max_hp)
	name_label.text = display_name
	hp_label.text = HUD.format_hp_text(hp, max_hp)
	queue_redraw()


func get_boss_name() -> String:
	return name_label.text


func get_ratio() -> float:
	return ratio


## Pure: the living, aggroed boss with the lowest id in an id -> Entity dictionary, or null.
static func find_aggroed_boss(entities: Dictionary) -> Entity:
	var best: Entity = null
	for key: Variant in entities.keys():
		var e: Entity = entities[key]
		if e == null or not e.is_boss or e.dead or e.target_id == 0:
			continue
		if best == null or e.id < best.id:
			best = e
	return best


## Pure: display name from enemies.json "name", falling back to the type id.
static func boss_display_name(boss: Entity, registry: DataRegistry) -> String:
	var type_id := boss.enemy_type_id if not boss.enemy_type_id.is_empty() else boss.kind
	if registry != null and not type_id.is_empty():
		var entry := registry.get_entry(ENEMIES_TABLE, type_id)
		var n := str(entry.get("name", "")).strip_edges()
		if not n.is_empty():
			return n
	return type_id


func _draw() -> void:
	var r := Rect2(0.0, NAME_HEIGHT, bar_width, bar_height)
	draw_rect(r, bg_color)
	var fill_w := bar_width * ratio
	if fill_w > 0.0:
		draw_rect(Rect2(0.0, NAME_HEIGHT, fill_w, bar_height), fill_color)
	draw_rect(r, border_color, false, 2.0)
