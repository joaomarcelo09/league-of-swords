class_name Commands
extends RefCounted

class Command extends RefCounted:
	var entity_id: int = 0
	var type: String = ""

	func is_targeting(_target_id: int) -> bool:
		return false


class MoveTo extends Command:
	var target: Vector2i = Vector2i.ZERO

	func _init(p_entity_id: int = 0, p_target: Vector2i = Vector2i.ZERO) -> void:
		entity_id = p_entity_id
		target = p_target
		type = "move_to"


class AttackTarget extends Command:
	var target_id: int = 0
	var last_target_tile: Vector2i = Vector2i(-1, -1)

	func _init(p_entity_id: int = 0, p_target_id: int = 0) -> void:
		entity_id = p_entity_id
		target_id = p_target_id
		type = "attack_target"

	func is_targeting(p_target_id: int) -> bool:
		return target_id == p_target_id


static func move_to(entity_id: int, target: Vector2i) -> MoveTo:
	return MoveTo.new(entity_id, target)


static func attack_target(entity_id: int, target_id: int) -> AttackTarget:
	return AttackTarget.new(entity_id, target_id)
