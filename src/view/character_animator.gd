class_name CharacterAnimator
extends RefCounted
## View-side animation driver for a LayeredSprite character. It only reads logic state
## (position, dead flag, an optional attack direction and damage taken from sim events)
## and asks AnimState which layout animation/direction to play. It never writes to logic.

const ANIM_IDLE: String = AnimState.ANIM_IDLE
const ANIM_WALK: String = AnimState.ANIM_WALK
const ANIM_SLASH: String = AnimState.ANIM_SLASH
const ANIM_HURT: String = AnimState.ANIM_HURT
const ANIM_DEATH: String = AnimState.ANIM_DEATH

var facing: String = AnimState.DIR_DOWN
var _last_pos: Vector2 = Vector2.ZERO
var _has_last_pos: bool = false
## Sim tick at which the current hurt reaction ends (exclusive); -1 = none.
var _hurt_until_tick: int = -1
## Set by trigger_hurt; the next update restarts the hurt animation.
var _hurt_restart: bool = false


## Kept for callers/tests: delegates to AnimState.
static func facing_from_vector(v: Vector2, p_fallback: String = AnimState.DIR_DOWN) -> String:
	return AnimState.facing_from_vector(v, p_fallback)


## Pure: hurt duration in seconds from the layout's "hurt_seconds" (0 = no hurt reaction).
static func hurt_seconds_from_layout(p_layout: Dictionary) -> float:
	var val: Variant = p_layout.get("hurt_seconds", null)
	if val is float or val is int:
		return maxf(float(val), 0.0)
	return 0.0


## Pure: number of sim ticks a hurt reaction of p_seconds lasts (at least 1 when > 0).
static func hurt_ticks_for(p_seconds: float, p_tick_length: float) -> int:
	if p_seconds <= 0.0 or p_tick_length <= 0.0:
		return 0
	return maxi(ceili(p_seconds / p_tick_length - 1e-6), 1)


## Resets movement tracking (e.g. after a respawn teleport).
func reset(pos: Vector2) -> void:
	_last_pos = pos
	_has_last_pos = true
	facing = AnimState.DIR_DOWN
	_hurt_until_tick = -1
	_hurt_restart = false


## Starts (or restarts) a hurt reaction: the entity took damage at sim tick now_tick.
## Duration comes from the sprite layout ("hurt_seconds").
func trigger_hurt(sprite: LayeredSprite, now_tick: int, tick_length: float) -> void:
	if sprite == null:
		return
	var ticks := hurt_ticks_for(hurt_seconds_from_layout(sprite.layout), tick_length)
	if ticks <= 0:
		return
	_hurt_until_tick = now_tick + ticks
	_hurt_restart = true


## Remaining hurt ticks at now_tick.
func hurt_ticks_left(now_tick: int) -> int:
	return maxi(_hurt_until_tick - now_tick, 0)


## Updates the sprite for this frame. pos is the logic position (tile units),
## attack_dir is a Vector2 toward the attack target when an attack started this frame
## (null otherwise), now_tick is the sim tick count (for the hurt reaction).
func update(sprite: LayeredSprite, pos: Vector2, dead: bool, attack_dir: Variant = null, now_tick: int = 0) -> void:
	if sprite == null:
		return
	var prev_pos := _last_pos if _has_last_pos else pos
	_last_pos = pos
	_has_last_pos = true
	var new_attack := attack_dir is Vector2 and not dead
	# A slash in progress keeps playing (not interrupted by walk/idle).
	var finishing_slash := sprite.current_anim == ANIM_SLASH and sprite.is_playing
	var aim: Vector2 = attack_dir as Vector2 if new_attack else Vector2.ZERO

	var state := AnimState.anim_for(prev_pos, pos, new_attack or finishing_slash, hurt_ticks_left(now_tick), dead, aim, facing)
	var anim: String = state["anim"]
	# While a slash finishes, keep facing the swing direction.
	if not (anim == ANIM_SLASH and not new_attack):
		facing = state["dir"]
	var restart_hurt := _hurt_restart
	_hurt_restart = false

	if not sprite.has_animation(anim):
		return
	if anim == ANIM_SLASH:
		if new_attack:
			sprite.play(anim, facing)  # restart on every new hit
	elif anim == ANIM_HURT:
		if restart_hurt or sprite.current_anim != ANIM_HURT:
			sprite.play(anim, facing)
	elif anim == ANIM_DEATH:
		if sprite.current_anim != ANIM_DEATH:
			sprite.play(anim, facing)  # plays once, then holds its last frame
	elif anim != sprite.current_anim or facing != sprite.current_dir:
		sprite.play(anim, facing)
