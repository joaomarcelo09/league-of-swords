class_name Entity
extends RefCounted

var id: int = 0
var kind: String = ""
var pos: Vector2 = Vector2.ZERO
var speed: float = 0.0
var hp: float = 100.0
var path: Array[Vector2i] = []
var path_index: int = 0
var command: Variant = null


func _init(p_id: int = 0, p_kind: String = "", p_pos: Vector2 = Vector2.ZERO, p_speed: float = 0.0, p_hp: float = 100.0) -> void:
	id = p_id
	kind = p_kind
	pos = p_pos
	speed = p_speed
	hp = p_hp


func tile() -> Vector2i:
	return Vector2i(int(floor(pos.x)), int(floor(pos.y)))
