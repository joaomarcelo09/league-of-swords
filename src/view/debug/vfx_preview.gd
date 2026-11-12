class_name VfxPreview
extends RefCounted
## --preview=vfx_q|vfx_w|vfx_r|vfx_e: casts that slot through the sim beside an enemy and
## freezes the resulting skill effect mid-fade so tools/screenshot.sh can capture it.

static var is_active: bool = false

const PREFIX: String = "vfx_"
const VARIANT_SLOTS: Dictionary = {"vfx_q": "Q", "vfx_w": "W", "vfx_r": "R", "vfx_e": "E"}
## Share of the effect's life shown in the screenshot.
const FREEZE_RATIO: float = 0.4
## Enemy placed this far (tiles) right of the player so Q/W have something to aim at.
const ENEMY_OFFSET: Vector2 = Vector2(2.0, 0.5)
const MAX_PREP_TICKS: int = 60


static func preview_variant() -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--preview=" + PREFIX):
			return arg.substr("--preview=".length())
	return ""


static func check_preview_flag() -> bool:
	return VARIANT_SLOTS.has(preview_variant())


static func setup_if_requested(main: MainView) -> void:
	is_active = false
	if not check_preview_flag():
		return
	is_active = true
	_prepare(main, str(VARIANT_SLOTS[preview_variant()]))


static func _prepare(main: MainView, slot: String) -> void:
	var world := main.world
	var player := main.player
	var session := main.session
	if world == null or player == null or session == null or main.vfx_layer == null:
		return

	var enemy: Entity = null
	for ent: Entity in world.entities.values():
		if ent.kind == "enemy" and not ent.dead:
			enemy = ent
			break
	if enemy != null:
		enemy.pos = player.pos + ENEMY_OFFSET

	if slot == VfxLayer.DASH_SLOT:
		world.submit(Commands.dash(player.id, Vector2.LEFT))
	else:
		var aim := enemy.pos if enemy != null else player.pos + Vector2.RIGHT
		world.submit(Commands.cast_skill(player.id, slot, aim))

	var tick_dt := world.tick_length
	var seen := false
	for _i in range(MAX_PREP_TICKS):
		session.step(tick_dt)
		if main.entity_layer != null:
			main.entity_layer.sync()
		if not main.vfx_layer.get_effects().is_empty():
			seen = true
		# Let the dash finish so the player stands at the end of its trail.
		if seen and (player.command == null):
			break
	main.vfx_layer.freeze_at(FREEZE_RATIO)
