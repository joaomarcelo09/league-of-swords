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
## Exact final position of the current path; used only while it lies in the
## last path tile, otherwise that tile's centre is the final waypoint.
var path_goal: Vector2 = Vector2.INF
## Last non-zero movement direction (unit vector); see facing_octant().
var facing_dir: Vector2 = Vector2.ZERO
var command: Commands.Command = null
var attack_ready_tick: float = 0.0
var skills: Dictionary = {}
var skill_ready_ticks: Dictionary = {}
var dash_ready_tick: float = 0.0
var buffs: Array[Dictionary] = []

# AI state fields
var state: String = "idle"
var state_end_tick: int = 0
var locked_origin: Vector2 = Vector2.ZERO
var locked_dir: Vector2 = Vector2.ZERO
var spawn_pos: Vector2 = Vector2.ZERO
var enemy_type_id: String = ""
var recovery_damage_mult: float = 1.0
var target_id: int = 0

# Zone spawn bookkeeping: id of the zone spawn this entity came from (empty if none)
var spawn_id: String = ""
var is_boss: bool = false


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
	spawn_pos = p_pos
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


## Facing quantized to 8 directions (Facing.EAST..Facing.NORTH_EAST, or Facing.NONE).
func facing_octant() -> int:
	return Facing.octant(facing_dir)
