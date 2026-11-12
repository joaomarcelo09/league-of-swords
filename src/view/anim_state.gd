class_name AnimState
extends RefCounted
## Pure, static animation-state helper for view characters (player now, enemies later).
## Decides which layout animation and which of the 4 LPC directions to show from plain
## entity state. No nodes, no textures, no logic writes: fully unit-testable.

const ANIM_IDLE: String = "idle"
const ANIM_WALK: String = "walk"
const ANIM_SLASH: String = "slash"
const ANIM_HURT: String = "hurt"
const ANIM_DEATH: String = "death"

const DIR_UP: String = "up"
const DIR_DOWN: String = "down"
const DIR_LEFT: String = "left"
const DIR_RIGHT: String = "right"


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
static func anim_for(prev_pos: Vector2, pos: Vector2, is_attacking: bool, hurt_ticks: int, is_dead: bool, aim: Vector2 = Vector2.ZERO, prev_dir: String = DIR_DOWN) -> Dictionary:
	var delta := pos - prev_pos
	var moving := not delta.is_zero_approx()

	var dir := prev_dir
	if is_attacking and not aim.is_zero_approx():
		dir = facing_from_vector(aim, prev_dir)
	elif moving:
		dir = facing_from_vector(delta, prev_dir)

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
