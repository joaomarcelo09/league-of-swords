class_name TelegraphWindupPreview
extends RefCounted

static var is_active: bool = false


static func check_preview_flag() -> bool:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--preview=telegraph_windup" or arg.begins_with("--preview=telegraph_windup"):
			return true
	return false


static func setup_if_requested(main: MainView) -> void:
	is_active = false
	if not check_preview_flag():
		return

	is_active = true
	_prepare(main)


static func _prepare(main: MainView) -> void:
	var world: WorldSim = main.world
	var player: Entity = main.player
	var session: GameSession = main.session
	var entity_layer: EntityLayer = main.entity_layer
	if world == null or player == null or session == null:
		return

	var enemy: Entity = null
	for ent: Entity in world.entities.values():
		if ent.kind == "enemy":
			enemy = ent
			break
	if enemy == null:
		return

	# Position player 1.5 tiles above enemy (within 2.5 attack cone range)
	player.pos = Vector2(enemy.pos.x, enemy.pos.y - 1.5)

	# Step ticks until enemy enters windup and reaches mid-windup (7-8 ticks at 30Hz)
	var tick_dt: float = world.tick_length
	for _i in range(8):
		session.step(tick_dt)
		if entity_layer != null:
			entity_layer.sync()

	if entity_layer != null:
		for tele: TelegraphView in entity_layer.get_telegraph_views():
			tele.set_process(false)
			tele.progress = 0.5
			tele.queue_redraw()
