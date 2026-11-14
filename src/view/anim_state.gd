class_name AnimState
extends RefCounted
## Pure, static animation-state helper for view characters (player and enemies).
## Decides which layout animation and which of the 4 LPC directions to show from plain
## entity state. Facing is computed in 8 directions (Facing.octant) and mapped to one of
## the 4 LPC rows (layout "octant_dirs"). No nodes, no textures, no logic writes.

const ANIM_IDLE: String = "idle"
const ANIM_WALK: String = "walk"
const ANIM_SLASH: String = "slash"
const ANIM_HURT: String = "hurt"
const ANIM_DEATH: String = "death"

const DIR_UP: String = "up"
const DIR_DOWN: String = "down"
const DIR_LEFT: String = "left"
const DIR_RIGHT: String = "right"

## LPC row per Facing octant (EAST, SOUTH_EAST, SOUTH, ... NORTH_EAST), used when the
## layout has no "octant_dirs". Diagonals use the side-view row (LPC convention).
const DEFAULT_OCTANT_DIRS: Array = [
	DIR_RIGHT, DIR_RIGHT, DIR_DOWN, DIR_LEFT, DIR_LEFT, DIR_LEFT, DIR_UP, DIR_RIGHT,
]


## Octant -> LPC direction table from the layout ("octant_dirs", 8 entries), else default.
static func octant_dirs_from_layout(p_layout: Dictionary) -> Array:
	var val: Variant = p_layout.get("octant_dirs", null)
	if val is Array and (val as Array).size() == 8:
		return val as Array
	return DEFAULT_OCTANT_DIRS


## LPC direction for a Facing octant; p_fallback for Facing.NONE or an invalid octant.
static func dir_for_octant(p_octant: int, p_fallback: String = DIR_DOWN, p_octant_dirs: Array = DEFAULT_OCTANT_DIRS) -> String:
	if p_octant < 0 or p_octant >= p_octant_dirs.size():
		return p_fallback
	return str(p_octant_dirs[p_octant])


## LPC direction for a vector through its 8-way octant (Facing.octant).
static func dir_for_vector(v: Vector2, p_fallback: String = DIR_DOWN, p_octant_dirs: Array = DEFAULT_OCTANT_DIRS) -> String:
	return dir_for_octant(Facing.octant(v), p_fallback, p_octant_dirs)


## LPC direction name for a vector (dominant axis; ties go horizontal).
## Returns p_fallback for a zero vector.
static func facing_from_vector(v: Vector2, p_fallback: String = DIR_DOWN) -> String:
	if v.is_zero_approx():
		return p_fallback
	if absf(v.x) >= absf(v.y):
		return DIR_RIGHT if v.x > 0.0 else DIR_LEFT
	return DIR_DOWN if v.y > 0.0 else DIR_UP


## Returns {"anim": String, "dir": String}.
## Priority: death > hurt (hurt_ticks > 0) > slash (is_attacking) > walk (pos moved) > idle.
## dir comes from aim while attacking, else from movement, else prev_dir is kept.
static func anim_for(prev_pos: Vector2, pos: Vector2, is_attacking: bool, hurt_ticks: int, is_dead: bool, aim: Vector2 = Vector2.ZERO, prev_dir: String = DIR_DOWN, octant_dirs: Array = DEFAULT_OCTANT_DIRS) -> Dictionary:
	return state_for(pos - prev_pos, is_attacking, hurt_ticks, is_dead, aim, prev_dir, octant_dirs)


## Same as anim_for but from the movement vector of this step (zero = standing still).
static func state_for(move: Vector2, is_attacking: bool, hurt_ticks: int, is_dead: bool, aim: Vector2 = Vector2.ZERO, prev_dir: String = DIR_DOWN, octant_dirs: Array = DEFAULT_OCTANT_DIRS) -> Dictionary:
	var moving := not move.is_zero_approx()

	var dir := prev_dir
	if is_attacking and not aim.is_zero_approx():
		dir = dir_for_vector(aim, prev_dir, octant_dirs)
	elif moving:
		dir = dir_for_vector(move, prev_dir, octant_dirs)

	var anim := ANIM_IDLE
	if is_dead:
		anim = ANIM_DEATH
	elif hurt_ticks > 0:
		anim = ANIM_HURT
	elif is_attacking:
		anim = ANIM_SLASH
	elif moving:
		anim = ANIM_WALK
	return {"anim": anim, "dir": dir}
