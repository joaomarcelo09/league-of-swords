class_name FloatingText
extends Node2D

const DEFAULT_DURATION_S: float = 0.8
const DEFAULT_RISE_PX: float = 24.0
const DEFAULT_PLAYER_COLOR := Color(1.0, 0.3, 0.3, 1.0)
const DEFAULT_ENEMY_COLOR := Color(1.0, 0.9, 0.2, 1.0)

var amount: float = 0.0
var text: String = ""
var elapsed: float = 0.0
var duration_s: float = DEFAULT_DURATION_S
var rise_px: float = DEFAULT_RISE_PX
var start_pos: Vector2 = Vector2.ZERO
var is_player_damage: bool = false
var text_color: Color = DEFAULT_ENEMY_COLOR

var label: Label = null


func setup(
	p_amount: float,
	p_world_pos: Vector2,
	p_is_player_damage: bool,
	registry: DataRegistry = null
) -> void:
	amount = p_amount
	start_pos = p_world_pos
	position = start_pos
	is_player_damage = p_is_player_damage
	z_index = 100

	_load_balance_config(registry)

	if is_equal_approx(amount, roundf(amount)):
		text = str(int(roundf(amount)))
	else:
		text = "%.1f" % amount

	_setup_label()


func _load_balance_config(registry: DataRegistry) -> void:
	if registry == null:
		text_color = DEFAULT_PLAYER_COLOR if is_player_damage else DEFAULT_ENEMY_COLOR
		return

	var dur_val: Variant = registry.get_balance("view.damage_text_duration_s")
	if dur_val != null and float(dur_val) > 0.0:
		duration_s = float(dur_val)
	else:
		push_warning("FloatingText: missing balance key 'view.damage_text_duration_s'")

	var rise_val: Variant = registry.get_balance("view.damage_text_rise_px")
	if rise_val != null and float(rise_val) >= 0.0:
		rise_px = float(rise_val)
	else:
		push_warning("FloatingText: missing balance key 'view.damage_text_rise_px'")

	var player_color_val: Variant = registry.get_balance("view.damage_player_color")
	var enemy_color_val: Variant = registry.get_balance("view.damage_enemy_color")

	var player_col := DEFAULT_PLAYER_COLOR
	if player_color_val != null:
		player_col = EntityView.parse_color(player_color_val, DEFAULT_PLAYER_COLOR)
	else:
		push_warning("FloatingText: missing balance key 'view.damage_player_color'")

	var enemy_col := DEFAULT_ENEMY_COLOR
	if enemy_color_val != null:
		enemy_col = EntityView.parse_color(enemy_color_val, DEFAULT_ENEMY_COLOR)
	else:
		push_warning("FloatingText: missing balance key 'view.damage_enemy_color'")

	text_color = player_col if is_player_damage else enemy_col


func _setup_label() -> void:
	if label == null:
		label = Label.new()
		add_child(label)

	label.text = text
	label.modulate = text_color
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = Vector2(-30, -10)
	label.size = Vector2(60, 20)


func advance(dt: float) -> void:
	if is_queued_for_deletion():
		return

	elapsed += dt
	var t := clampf(elapsed / duration_s, 0.0, 1.0) if duration_s > 0.0 else 1.0
	position = start_pos + Vector2(0.0, -rise_px * t)
	modulate.a = 1.0 - t

	if elapsed >= duration_s - 1e-6:
		queue_free()


func _process(delta: float) -> void:
	advance(delta)
