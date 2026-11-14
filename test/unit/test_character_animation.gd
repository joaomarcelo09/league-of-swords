extends GutTest
## JGT-103: characters visibly animate. Walk keeps cycling while the sim ticks slower than
## the render rate, facing follows movement in 8 directions (mapped to the 4 LPC rows),
## and the slash length follows the attack interval / windup from data.

const LAYOUT_PATH := "res://data/sprites/layout_lpc.json"
const P := Vector2(5, 5)
const RENDER_DT := 1.0 / 60.0


func _tick_hz() -> int:
	var reg := DataRegistry.new()
	reg.load_dir("res://data")
	return int(reg.get_balance("sim.tick_hz"))


func _setup() -> Array:
	var sprite: LayeredSprite = autofree(LayeredSprite.new(LAYOUT_PATH))
	var anim := CharacterAnimator.new()
	anim.reset(P)
	anim.update(sprite, P, false, null, 0)
	return [sprite, anim]


## Drives the animator like the game: render frames at 60 fps, sim ticks at tick_hz,
## the entity moves by step on every sim tick. Returns the walk frames seen.
func _walk(sprite: LayeredSprite, anim: CharacterAnimator, step: Vector2, seconds: float, tick_hz: int) -> Dictionary:
	var frames_seen := {}
	var pos := P
	var tick := 0
	var acc := 0.0
	var tick_len := 1.0 / float(tick_hz)
	for i in range(int(seconds / RENDER_DT)):
		acc += RENDER_DT
		while acc >= tick_len - 1e-9:
			acc -= tick_len
			tick += 1
			pos += step
		anim.update(sprite, pos, false, null, tick)
		sprite.advance(RENDER_DT)
		if sprite.current_anim == "walk":
			frames_seen[sprite.current_frame] = true
	return frames_seen


# --- state -> animation mapping ----------------------------------------------------------

func test_still_maps_to_idle() -> void:
	assert_eq(AnimState.state_for(Vector2.ZERO, false, 0, false)["anim"], "idle")


func test_moving_maps_to_walk() -> void:
	assert_eq(AnimState.state_for(Vector2(0.1, 0.1), false, 0, false)["anim"], "walk")


func test_attack_maps_to_slash() -> void:
	assert_eq(AnimState.state_for(Vector2(0.1, 0), true, 0, false, Vector2.UP)["anim"], "slash")


func test_octant_to_direction_row() -> void:
	var expected := {
		Facing.EAST: "right", Facing.SOUTH_EAST: "right", Facing.SOUTH: "down",
		Facing.SOUTH_WEST: "left", Facing.WEST: "left", Facing.NORTH_WEST: "left",
		Facing.NORTH: "up", Facing.NORTH_EAST: "right",
	}
	var layout: Dictionary = autofree(LayeredSprite.new(LAYOUT_PATH)).layout
	var dirs := AnimState.octant_dirs_from_layout(layout)
	assert_eq(dirs.size(), 8, "layout has octant_dirs")
	var rows: Dictionary = layout["animations"]["walk"]["rows"]
	for octant: int in expected.keys():
		var dir := AnimState.dir_for_octant(octant, "down", dirs)
		assert_eq(dir, expected[octant], "octant %d" % octant)
		assert_true(rows.has(dir), "walk has a row for %s" % dir)
	assert_eq(AnimState.dir_for_octant(Facing.NONE, "up", dirs), "up", "NONE keeps facing")


func test_movement_vector_uses_octants() -> void:
	assert_eq(AnimState.dir_for_vector(Vector2(1, 1)), "right", "south-east")
	assert_eq(AnimState.dir_for_vector(Vector2(-1, 1)), "left", "south-west")
	assert_eq(AnimState.dir_for_vector(Vector2(-1, -1)), "left", "north-west")
	assert_eq(AnimState.dir_for_vector(Vector2(1, -1)), "right", "north-east")
	assert_eq(AnimState.dir_for_vector(Vector2(0.1, 1)), "down")
	assert_eq(AnimState.dir_for_vector(Vector2(-0.1, -1)), "up")
	assert_eq(AnimState.dir_for_vector(Vector2.ZERO, "left"), "left")


# --- animator: the reported bug ----------------------------------------------------------

func test_walk_frames_advance_when_sim_ticks_slower_than_render() -> void:
	var s: Array = _setup()
	var hz := _tick_hz()
	assert_gt(hz, 0)
	assert_lt(float(hz), 1.0 / RENDER_DT, "sim ticks slower than render (the bug's precondition)")
	var seen := _walk(s[0], s[1], Vector2(0.1, 0), 2.0, hz)
	assert_eq((s[0] as LayeredSprite).current_anim, "walk")
	var walk_frames: int = int((s[0] as LayeredSprite).layout["animations"]["walk"]["frame_count"])
	assert_eq(seen.size(), walk_frames, "the whole walk cycle plays, not only frame 0")


func test_walk_frames_advance_when_sim_matches_render() -> void:
	var s: Array = _setup()
	var seen := _walk(s[0], s[1], Vector2(0.05, 0), 1.0, 60)
	assert_gt(seen.size(), 1)


func test_idle_after_stopping() -> void:
	var s: Array = _setup()
	var sprite: LayeredSprite = s[0]
	var anim: CharacterAnimator = s[1]
	anim.update(sprite, P + Vector2(0.1, 0), false, null, 1)
	anim.update(sprite, P + Vector2(0.1, 0), false, null, 1)
	assert_eq(sprite.current_anim, "walk", "same tick: still walking")
	anim.update(sprite, P + Vector2(0.1, 0), false, null, 2)
	assert_eq(sprite.current_anim, "idle", "a tick without movement: idle")
	assert_true(sprite.is_playing)


func test_turning_keeps_walk_cycle() -> void:
	var s: Array = _setup()
	var sprite: LayeredSprite = s[0]
	var anim: CharacterAnimator = s[1]
	anim.update(sprite, P + Vector2(0.1, 0), false, null, 1)
	sprite.advance(0.3)
	var frame := sprite.current_frame
	assert_gt(frame, 0)
	anim.update(sprite, P + Vector2(0.1, 0.2), false, null, 2)
	assert_eq(sprite.current_dir, "down")
	assert_eq(sprite.current_anim, "walk")
	assert_eq(sprite.current_frame, frame, "turning does not restart the cycle")


func test_facing_follows_eight_directions() -> void:
	var cases := [
		[Vector2(1, 0), "right"], [Vector2(1, 1), "right"], [Vector2(0, 1), "down"],
		[Vector2(-1, 1), "left"], [Vector2(-1, 0), "left"], [Vector2(-1, -1), "left"],
		[Vector2(0, -1), "up"], [Vector2(1, -1), "right"],
	]
	for c: Array in cases:
		var s: Array = _setup()
		var anim: CharacterAnimator = s[1]
		anim.update(s[0], P + (c[0] as Vector2) * 0.1, false, null, 1)
		assert_eq(anim.facing, c[1], "move %s" % c[0])
		assert_eq((s[0] as LayeredSprite).current_dir, c[1])


# --- slash timing from data --------------------------------------------------------------

func test_slash_seconds_within_attack_interval() -> void:
	var layout: Dictionary = autofree(LayeredSprite.new(LAYOUT_PATH)).layout
	var base := LayeredSprite.anim_seconds(layout, "slash")
	assert_gt(base, 0.0)
	assert_eq(CharacterAnimator.slash_seconds_within(layout, base * 4.0), base, "slow attacks keep layout length")
	assert_almost_eq(CharacterAnimator.slash_seconds_within(layout, base * 0.5), base * 0.5, 1e-6, "fast attacks shorten it")
	assert_eq(CharacterAnimator.slash_seconds_within(layout, 0.0), base)


func test_slash_speed_for() -> void:
	var layout: Dictionary = autofree(LayeredSprite.new(LAYOUT_PATH)).layout
	var base := LayeredSprite.anim_seconds(layout, "slash")
	assert_eq(CharacterAnimator.slash_speed_for(layout, 0.0), 1.0)
	assert_almost_eq(CharacterAnimator.slash_speed_for(layout, base * 0.5), 2.0, 1e-6)
	var rng: Array = layout["slash_speed_scale_range"]
	assert_eq(CharacterAnimator.slash_speed_for(layout, base * 1000.0), float(rng[0]), "clamped to min")
	assert_eq(CharacterAnimator.slash_speed_for(layout, base / 1000.0), float(rng[1]), "clamped to max")


func test_slash_lasts_requested_seconds() -> void:
	var s: Array = _setup()
	var sprite: LayeredSprite = s[0]
	var anim: CharacterAnimator = s[1]
	var base := LayeredSprite.anim_seconds(sprite.layout, "slash")
	var want := base * 0.5
	anim.update(sprite, P, false, Vector2.LEFT, 1, want)
	assert_eq(sprite.current_anim, "slash")
	assert_eq(sprite.current_dir, "left")
	sprite.advance(want * 0.9)
	assert_true(sprite.is_playing, "still swinging before the requested length")
	sprite.advance(want * 0.2)
	assert_false(sprite.is_playing, "done after the requested length")


func test_new_slash_resets_speed_and_play_resets_scale() -> void:
	var s: Array = _setup()
	var sprite: LayeredSprite = s[0]
	var anim: CharacterAnimator = s[1]
	anim.update(sprite, P, false, Vector2.UP, 1, 0.1)
	assert_gt(sprite.speed_scale, 1.0)
	sprite.play("walk", "down")
	assert_eq(sprite.speed_scale, 1.0)


func test_entity_view_notify_attack_accepts_windup() -> void:
	var view: EntityView = autofree(EntityView.new())
	view.notify_attack(Vector2.RIGHT, 0.8)
	assert_eq(view._pending_attack_seconds, 0.8)
	view.notify_attack(Vector2.RIGHT, -1.0)
	assert_eq(view._pending_attack_seconds, 0.0)
