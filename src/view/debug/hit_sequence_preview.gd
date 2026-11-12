class_name HitSequencePreview
extends RefCounted
## --preview=hit_sequence: puts an enemy beside the player and, at frame HIT_FRAME,
## steps the sim (player attacks the enemy, the enemy hits back) until the player has
## been damaged. From then on the hit feedback (flash, camera shake, sparks) advances
## by a fixed FRAME_DT per frame, so tools/screenshot.sh --frames=N is repeatable:
## N < HIT_FRAME before the hit, N slightly above it mid-effect, N well above it after.

static var is_active: bool = false

const VARIANT: String = "hit_sequence"
## Process frame at which the hit happens.
const HIT_FRAME: int = 20
## Fixed effect time per frame after the hit (seconds).
const FRAME_DT: float = 1.0 / 60.0
## Player placed this far (tiles) left of the enemy, inside both attack ranges.
const ENEMY_OFFSET: Vector2 = Vector2(1.3, 0.0)
const MAX_HIT_TICKS: int = 300


## Drives the sequence frame by frame (added under MainView).
class Driver extends Node:
	var main: MainView = null
	var frame: int = 0
	var hit_done: bool = false

	func _process(_delta: float) -> void:
		frame += 1
		if frame == HitSequencePreview.HIT_FRAME:
			HitSequencePreview.play_hit(main)
			hit_done = true
		elif hit_done:
			HitSequencePreview.advance_feedback(main, HitSequencePreview.FRAME_DT)


static func check_preview_flag() -> bool:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--preview=" + VARIANT:
			return true
	return false


static func setup_if_requested(main: MainView) -> void:
	is_active = false
	if not check_preview_flag():
		return
	is_active = true
	var enemy := _first_enemy(main)
	if enemy != null and main.player != null:
		# Stand next to the enemy's own spawn (outside the safe zone) so it attacks.
		main.player.pos = enemy.pos - ENEMY_OFFSET
		main._update_views()
	var driver := Driver.new()
	driver.name = "HitSequencePreview"
	driver.main = main
	main.add_child(driver)


static func _first_enemy(main: MainView) -> Entity:
	if main.world == null:
		return null
	for ent: Entity in main.world.entities.values():
		if ent.kind == "enemy" and not ent.dead:
			return ent
	return null


## Steps the sim tick by tick (within this frame) until the player takes damage.
static func play_hit(main: MainView) -> void:
	var world := main.world
	if world == null or main.player == null or main.session == null:
		return
	var enemy := _first_enemy(main)
	if enemy != null:
		world.submit(Commands.attack_target(main.player.id, enemy.id))
	for _i in range(MAX_HIT_TICKS):
		main.session.step(world.tick_length)
		main._update_views()
		if main.player_flash != null and main.player_flash.active:
			break
	_hold_feedback(main)


## Stops the feedback nodes' own real-time processing so the preview advances them.
static func _hold_feedback(main: MainView) -> void:
	if main.camera != null:
		main.camera.set_process(false)
	for flash: HitFlash in _flashes(main):
		flash.set_process(false)
	if main.vfx_layer != null:
		for fx: VfxLayer.VfxEffect in main.vfx_layer.get_effects():
			fx.set_process(false)


static func advance_feedback(main: MainView, dt: float) -> void:
	if main.camera != null:
		main.camera.advance_shake(dt)
	for flash: HitFlash in _flashes(main):
		flash.advance(dt)
	if main.vfx_layer != null:
		for fx: VfxLayer.VfxEffect in main.vfx_layer.get_effects():
			if fx.advance(dt):
				fx.queue_free()
			else:
				fx.queue_redraw()
	_hold_feedback(main)


static func _flashes(main: MainView) -> Array[HitFlash]:
	var out: Array[HitFlash] = []
	if main.player_flash != null:
		out.append(main.player_flash)
	if main.entity_layer != null:
		for view: Variant in main.entity_layer.views.values():
			if view is EntityView and is_instance_valid(view) and (view as EntityView).flash != null:
				out.append((view as EntityView).flash)
	return out
