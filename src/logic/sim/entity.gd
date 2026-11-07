class_name Entity
extends RefCounted

var id: int = 0
var kind: String = ""
var pos: Vector2 = Vector2.ZERO
var speed: float = 0.0
var hp: float = 0.0
var stats: Stats = null
var dead: bool = false
var path: Array[Vector2i] = []
var path_index: int = 0
var command: Commands.Command = null
var attack_ready_tick: float = 0.0


func _init(
	p_id: int = 0,
	p_kind: String = "",
	p_pos: Vector2 = Vector2.ZERO,
	p_speed: float = 0.0,
	p_hp: float = -1.0,
	p_stats: Stats = null
) -> void:
	id = p_id
	kind = p_kind
	pos = p_pos
	speed = p_speed
	stats = p_stats
	if p_hp >= 0.0:
		hp = p_hp
	elif p_stats != null and p_stats.max_hp > 0.0:
		hp = p_stats.max_hp
	else:
		hp = 0.0
	dead = hp <= 0.0


func tile() -> Vector2i:
	return Vector2i(int(floor(pos.x)), int(floor(pos.y)))
