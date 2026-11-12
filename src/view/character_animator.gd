class_name CharacterAnimator
extends RefCounted
## View-side animation picker for a LayeredSprite character. It only reads logic state
## (position, dead flag, an optional attack direction from sim events) and decides which
## layout animation/direction to play. It never writes to logic.

const ANIM_IDLE: String = "idle"
const ANIM_WALK: String = "walk"
const ANIM_SLASH: String = "slash"
const ANIM_DEATH: String = "death"

var facing: String = "down"
var _last_pos: Vector2 = Vector2.ZERO
var _has_last_pos: bool = false


## Pure: LPC direction name for a vector (dominant axis; ties go horizontal).
## Returns p_fallback for a zero vector.
static func facing_from_vector(v: Vector2, p_fallback: String = "down") -> String:
	if v.is_zero_approx():
		return p_fallback
	if absf(v.x) >= absf(v.y):
		return "right" if v.x > 0.0 else "left"
	return "down" if v.y > 0.0 else "up"


## Pure: which animation should play given the current playback and logic state.
## Priority: death > new attack > finishing slash > walk > idle.
static func pick_anim(current_anim: String, current_playing: bool, moving: bool, dead: bool, attacking: bool) -> String:
	if dead:
		return ANIM_DEATH
	if attacking:
		return ANIM_SLASH
	if current_anim == ANIM_SLASH and current_playing:
		return ANIM_SLASH
	if moving:
		return ANIM_WALK
	return ANIM_IDLE


## Resets movement tracking (e.g. after a respawn teleport).
func reset(pos: Vector2) -> void:
	_last_pos = pos
	_has_last_pos = true
	facing = "down"


## Updates the sprite for this frame. pos is the logic position (tile units),
## attack_dir is a Vector2 toward the attack target when an attack started this frame
## (null otherwise).
func update(sprite: LayeredSprite, pos: Vector2, dead: bool, attack_dir: Variant = null) -> void:
	if sprite == null:
		return
	var delta := pos - _last_pos if _has_last_pos else Vector2.ZERO
	_last_pos = pos
	_has_last_pos = true
	var moving := not delta.is_zero_approx()
	var attacking := attack_dir is Vector2 and not dead

	var anim := pick_anim(sprite.current_anim, sprite.is_playing, moving, dead, attacking)
	if attacking:
		facing = facing_from_vector(attack_dir as Vector2, facing)
	elif anim == ANIM_WALK:
		facing = facing_from_vector(delta, facing)

	if not sprite.has_animation(anim):
		return
	if anim == ANIM_SLASH and attacking:
		sprite.play(anim, facing)  # restart on every new hit
	elif anim != sprite.current_anim or (anim != ANIM_DEATH and anim != ANIM_SLASH and facing != sprite.current_dir):
		sprite.play(anim, facing)
