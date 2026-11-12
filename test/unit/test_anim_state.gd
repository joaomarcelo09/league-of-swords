extends GutTest
## JGT-73: AnimState picks animation + 4-way direction from entity state; CharacterAnimator
## uses it and adds a view-side hurt reaction.

const LAYOUT_PATH := "res://data/sprites/layout_lpc.json"
const P := Vector2(5, 5)


func _a(prev: Vector2, pos: Vector2, attacking: bool = false, hurt: int = 0, dead: bool = false, aim: Vector2 = Vector2.ZERO, prev_dir: String = "down") -> Dictionary:
	return AnimState.anim_for(prev, pos, attacking, hurt, dead, aim, prev_dir)


# --- animations ---------------------------------------------------------------------------

func test_idle_when_still() -> void:
	assert_eq(_a(P, P)["anim"], "idle")


func test_walk_when_moved() -> void:
	assert_eq(_a(P, P + Vector2(0.1, 0))["anim"], "walk")


func test_slash_when_attacking() -> void:
	assert_eq(_a(P, P, true, 0, false, Vector2.RIGHT)["anim"], "slash")


func test_hurt_when_hurt_ticks() -> void:
	assert_eq(_a(P, P, false, 3)["anim"], "hurt")
	assert_eq(_a(P, P, false, 0)["anim"], "idle", "hurt_ticks 0 is not hurt")


func test_death_when_dead() -> void:
	assert_eq(_a(P, P, false, 0, true)["anim"], "death")


func test_result_has_anim_and_dir() -> void:
	var r := _a(P, P)
	assert_true(r.has("anim") and r.has("dir"))


# --- priority -----------------------------------------------------------------------------

func test_priority_order() -> void:
	var moved := P + Vector2(1, 0)
	assert_eq(_a(P, moved, true, 5, true, Vector2.UP)["anim"], "death", "death beats all")
	assert_eq(_a(P, moved, true, 5, false, Vector2.UP)["anim"], "hurt", "hurt beats slash/walk")
	assert_eq(_a(P, moved, true, 0, false, Vector2.UP)["anim"], "slash", "slash beats walk")
	assert_eq(_a(P, moved, false, 0, false)["anim"], "walk", "walk beats idle")


# --- directions ---------------------------------------------------------------------------

func test_movement_directions() -> void:
	assert_eq(_a(P, P + Vector2(0, -1))["dir"], "up")
	assert_eq(_a(P, P + Vector2(0, 1), false, 0, false, Vector2.ZERO, "up")["dir"], "down")
	assert_eq(_a(P, P + Vector2(-1, 0))["dir"], "left")
	assert_eq(_a(P, P + Vector2(1, 0))["dir"], "right")
	assert_eq(_a(P, P + Vector2(1, 0.4))["dir"], "right", "dominant axis wins")
	assert_eq(_a(P, P + Vector2(0.3, -1))["dir"], "up", "dominant axis wins")


func test_aim_directions_when_attacking() -> void:
	assert_eq(_a(P, P, true, 0, false, Vector2(0, -2))["dir"], "up")
	assert_eq(_a(P, P, true, 0, false, Vector2(0, 2), "up")["dir"], "down")
	assert_eq(_a(P, P, true, 0, false, Vector2(-2, 0))["dir"], "left")
	assert_eq(_a(P, P, true, 0, false, Vector2(2, 0))["dir"], "right")


func test_aim_beats_movement_when_attacking() -> void:
	var r := _a(P, P + Vector2(1, 0), true, 0, false, Vector2(0, -1))
	assert_eq(r["dir"], "up")


func test_aim_ignored_when_not_attacking() -> void:
	var r := _a(P, P + Vector2(1, 0), false, 0, false, Vector2(0, -1))
	assert_eq(r["dir"], "right")


func test_prev_dir_kept_when_still() -> void:
	for d: String in ["up", "down", "left", "right"]:
		assert_eq(_a(P, P, false, 0, false, Vector2.ZERO, d)["dir"], d)
		assert_eq(_a(P, P, true, 0, false, Vector2.ZERO, d)["dir"], d, "zero aim keeps facing")
		assert_eq(_a(P, P, false, 2, false, Vector2.ZERO, d)["dir"], d, "hurt keeps facing")
		assert_eq(_a(P, P, false, 0, true, Vector2.ZERO, d)["dir"], d, "death keeps facing")


func test_default_prev_dir_is_down() -> void:
	assert_eq(AnimState.anim_for(P, P, false, 0, false)["dir"], "down")


func test_facing_from_vector_tie_goes_horizontal() -> void:
	assert_eq(AnimState.facing_from_vector(Vector2(1, 1)), "right")
	assert_eq(AnimState.facing_from_vector(Vector2(-1, -1)), "left")
	assert_eq(AnimState.facing_from_vector(Vector2.ZERO, "up"), "up")


# --- hurt duration from data --------------------------------------------------------------

func test_layout_has_hurt_seconds() -> void:
	var sprite: LayeredSprite = autofree(LayeredSprite.new(LAYOUT_PATH))
	assert_gt(CharacterAnimator.hurt_seconds_from_layout(sprite.layout), 0.0, "hurt_seconds in layout JSON")


func test_hurt_ticks_for() -> void:
	assert_eq(CharacterAnimator.hurt_ticks_for(0.5, 0.1), 5)
	assert_eq(CharacterAnimator.hurt_ticks_for(0.01, 0.1), 1, "at least one tick")
	assert_eq(CharacterAnimator.hurt_ticks_for(0.0, 0.1), 0)
	assert_eq(CharacterAnimator.hurt_ticks_for(0.5, 0.0), 0)
	assert_eq(CharacterAnimator.hurt_seconds_from_layout({}), 0.0, "missing key = no hurt")


# --- animator -----------------------------------------------------------------------------

func _setup() -> Array:
	var sprite: LayeredSprite = autofree(LayeredSprite.new(LAYOUT_PATH))
	var anim := CharacterAnimator.new()
	anim.reset(P)
	anim.update(sprite, P, false, null, 0)
	return [sprite, anim]


func test_animator_hurt_reaction_then_recovers() -> void:
	var s: Array = _setup()
	var sprite: LayeredSprite = s[0]
	var anim: CharacterAnimator = s[1]
	var tick_len := 1.0 / 30.0
	var ticks := CharacterAnimator.hurt_ticks_for(CharacterAnimator.hurt_seconds_from_layout(sprite.layout), tick_len)
	anim.trigger_hurt(sprite, 10, tick_len)
	anim.update(sprite, P, false, null, 10)
	assert_eq(sprite.current_anim, "hurt")
	anim.update(sprite, P + Vector2(0.1, 0), false, null, 10 + ticks - 1)
	assert_eq(sprite.current_anim, "hurt", "walk does not interrupt hurt")
	anim.update(sprite, P + Vector2(0.2, 0), false, null, 10 + ticks)
	assert_eq(sprite.current_anim, "walk", "hurt ends after duration")


func test_animator_hurt_restarts_on_new_damage() -> void:
	var s: Array = _setup()
	var sprite: LayeredSprite = s[0]
	var anim: CharacterAnimator = s[1]
	anim.trigger_hurt(sprite, 0, 1.0 / 30.0)
	anim.update(sprite, P, false, null, 0)
	sprite.advance(0.25)
	assert_gt(sprite.current_frame, 0)
	anim.trigger_hurt(sprite, 3, 1.0 / 30.0)
	anim.update(sprite, P, false, null, 3)
	assert_eq(sprite.current_anim, "hurt")
	assert_eq(sprite.current_frame, 0, "new damage restarts hurt")


func test_animator_death_beats_hurt_and_holds() -> void:
	var s: Array = _setup()
	var sprite: LayeredSprite = s[0]
	var anim: CharacterAnimator = s[1]
	anim.trigger_hurt(sprite, 0, 1.0 / 30.0)
	anim.update(sprite, P, true, null, 0)
	assert_eq(sprite.current_anim, "death")
	sprite.advance(5.0)
	var last := sprite.current_frame
	anim.update(sprite, P, true, null, 100)
	assert_eq(sprite.current_anim, "death")
	assert_eq(sprite.current_frame, last, "death holds its last frame")
	assert_false(sprite.is_playing)


func test_animator_slash_finishes_before_walk() -> void:
	var s: Array = _setup()
	var sprite: LayeredSprite = s[0]
	var anim: CharacterAnimator = s[1]
	anim.update(sprite, P, false, Vector2(0, -1), 1)
	assert_eq(sprite.current_anim, "slash")
	assert_eq(sprite.current_dir, "up")
	anim.update(sprite, P + Vector2(0.1, 0), false, null, 2)
	assert_eq(sprite.current_anim, "slash", "slash in progress not interrupted by walk")
	assert_eq(sprite.current_dir, "up", "keeps swing direction")
	sprite.advance(2.0)
	anim.update(sprite, P + Vector2(0.2, 0), false, null, 3)
	assert_eq(sprite.current_anim, "walk")
	assert_eq(sprite.current_dir, "right")
