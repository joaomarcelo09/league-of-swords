class_name Commands
extends RefCounted

class Command extends RefCounted:
	var entity_id: int = 0
	var type: String = ""

	func is_targeting(_target_id: int) -> bool:
		return false


class MoveTo extends Command:
	var target: Vector2i = Vector2i.ZERO
	## Exact destination inside `target` (e.g. the clicked point); non-finite
	## means "the centre of `target`".
	var point: Vector2 = Vector2.INF

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


## MoveTo whose final waypoint is the exact point (its tile is the A* target).
static func move_to_point(entity_id: int, point: Vector2) -> MoveTo:
	var cmd := MoveTo.new(entity_id, Vector2i(int(floor(point.x)), int(floor(point.y))))
	cmd.point = point
	return cmd


static func attack_target(entity_id: int, target_id: int) -> AttackTarget:
	return AttackTarget.new(entity_id, target_id)


class CastSkill extends Command:
	var slot: String = ""
	var aim: Vector2 = Vector2.ZERO
	var resolve_tick: int = 0

	func _init(p_entity_id: int = 0, p_slot: String = "", p_aim: Vector2 = Vector2.ZERO) -> void:
		entity_id = p_entity_id
		slot = p_slot
		aim = p_aim
		type = "cast_skill"


static func cast_skill(entity_id: int, slot: String, aim: Vector2) -> CastSkill:
	return CastSkill.new(entity_id, slot, aim)


class Dash extends Command:
	# aim is a direction vector (not a world position), normalised;
	# zero or non-finite aim yields dash_failed with reason 'invalid_aim'.
	var aim: Vector2 = Vector2.ZERO
	var from: Vector2 = Vector2.ZERO
	var to: Vector2 = Vector2.ZERO
	var distance: float = 0.0
	var duration_s: float = 0.0

	func _init(p_entity_id: int = 0, p_aim: Vector2 = Vector2.ZERO) -> void:
		entity_id = p_entity_id
		aim = p_aim
		type = "dash"


static func dash(entity_id: int, aim: Vector2) -> Dash:
	return Dash.new(entity_id, aim)


