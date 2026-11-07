class_name Commands
extends RefCounted

class Command extends RefCounted:
	var entity_id: int = 0
	var type: String = ""


class MoveTo extends Command:
	var target: Vector2i = Vector2i.ZERO

	func _init(p_entity_id: int = 0, p_target: Vector2i = Vector2i.ZERO) -> void:
		entity_id = p_entity_id
		target = p_target
		type = "move_to"


static func move_to(entity_id: int, target: Vector2i) -> MoveTo:
	return MoveTo.new(entity_id, target)
