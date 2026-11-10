class_name EntityLayer
extends Node2D

signal event_emitted(event: Dictionary)

class PlayerHPBar extends Node2D:
	var width: float = 24.0
	var height: float = 4.0
	var y_offset: float = -18.0
	var ratio: float = 1.0
	var bg_color := Color(0.1, 0.1, 0.1, 0.8)
	var fill_color := Color(0.2, 0.8, 0.2, 1.0)
	var border_color := Color(0.0, 0.0, 0.0, 0.9)

	func update_ratio(new_ratio: float) -> void:
		ratio = clampf(new_ratio, 0.0, 1.0)
		queue_redraw()

	func _draw() -> void:
		var bar_left := -width / 2.0
		draw_rect(Rect2(bar_left - 1.0, y_offset - 1.0, width + 2.0, height + 2.0), border_color)
		draw_rect(Rect2(bar_left, y_offset, width, height), bg_color)
		var fill_w := width * ratio
		if fill_w > 0.0:
			draw_rect(Rect2(bar_left, y_offset, fill_w, height), fill_color)


var session: GameSession = null
var world: WorldSim = null
var zone_view: ZoneView = null
var registry: DataRegistry = null
var player_marker: Node2D = null
var player_hp_bar: PlayerHPBar = null

var views: Dictionary = {}
var last_events: Array[Dictionary] = []

var telegraphs_root: Node2D = null
var floating_texts_root: Node2D = null


func _ready() -> void:
	_init_containers()


func reset() -> void:
	for id_val: Variant in views.keys():
		var view: EntityView = views[id_val]
		if is_instance_valid(view):
			view.queue_free()
	views.clear()

	if telegraphs_root != null:
		for child: Node in telegraphs_root.get_children():
			if is_instance_valid(child):
				child.queue_free()

	if floating_texts_root != null:
		for child: Node in floating_texts_root.get_children():
			if is_instance_valid(child):
				child.queue_free()

	last_events.clear()


func _init_containers() -> void:
	if telegraphs_root == null:
		telegraphs_root = Node2D.new()
		telegraphs_root.name = "Telegraphs"
		telegraphs_root.z_index = 0
		add_child(telegraphs_root)

	if floating_texts_root == null:
		floating_texts_root = Node2D.new()
		floating_texts_root.name = "FloatingTexts"
		floating_texts_root.z_index = 10
		add_child(floating_texts_root)


func setup(
	p_session: GameSession,
	p_zone_view: ZoneView,
	p_registry: DataRegistry,
	p_player_marker: Node2D = null
) -> void:
	session = p_session
	world = p_session.world if p_session != null else null
	zone_view = p_zone_view
	registry = p_registry
	player_marker = p_player_marker

	_init_containers()
	_setup_player_hp_bar()
	sync()


func setup_world(
	p_world: WorldSim,
	p_zone_view: ZoneView,
	p_registry: DataRegistry,
	p_player_marker: Node2D = null
) -> void:
	session = null
	world = p_world
	zone_view = p_zone_view
	registry = p_registry
	player_marker = p_player_marker

	_init_containers()
	_setup_player_hp_bar()
	sync()


func _setup_player_hp_bar() -> void:
	if player_marker == null:
		return

	if player_marker.has_node("PlayerHPBar"):
		player_hp_bar = player_marker.get_node("PlayerHPBar") as PlayerHPBar
		return

	player_hp_bar = PlayerHPBar.new()
	player_hp_bar.name = "PlayerHPBar"

	if registry != null:
		var width_val: Variant = registry.get_balance("view.hp_bar_width")
		if width_val != null and float(width_val) > 0.0:
			player_hp_bar.width = float(width_val)
		var height_val: Variant = registry.get_balance("view.hp_bar_height")
		if height_val != null and float(height_val) > 0.0:
			player_hp_bar.height = float(height_val)
		var offset_val: Variant = registry.get_balance("view.hp_bar_y_offset")
		if offset_val != null:
			player_hp_bar.y_offset = float(offset_val)
		var bg_val: Variant = registry.get_balance("view.hp_bar_bg_color")
		if bg_val != null:
			player_hp_bar.bg_color = EntityView.parse_color(bg_val, player_hp_bar.bg_color)
		var fill_val: Variant = registry.get_balance("view.hp_bar_fill_color")
		if fill_val != null:
			player_hp_bar.fill_color = EntityView.parse_color(fill_val, player_hp_bar.fill_color)
		var border_val: Variant = registry.get_balance("view.hp_bar_border_color")
		if border_val != null:
			player_hp_bar.border_color = EntityView.parse_color(border_val, player_hp_bar.border_color)

	player_marker.add_child(player_hp_bar)


func sync() -> void:
	# 1. Drain events once per frame
	var events: Array[Dictionary] = []
	if session != null:
		events = session.drain_events()
	elif world != null:
		events = world.drain_events()

	last_events = events
	for ev: Dictionary in events:
		event_emitted.emit(ev)
		_handle_sim_event(ev)

	# 2. Sync entity views with world.entities
	if world == null:
		return

	var current_living_ids: Dictionary = {}
	var player_entity: Entity = session.player if session != null else null

	for entity_id_val: Variant in world.entities.keys():
		var entity_id: int = int(entity_id_val)
		var entity: Entity = world.entities[entity_id]
		if entity == null or entity.dead:
			continue

		var is_player: bool = false
		if player_entity != null and entity.id == player_entity.id:
			is_player = true
		elif entity.kind == "player":
			is_player = true

		if is_player:
			_update_player(entity)
			continue

		current_living_ids[entity_id] = true
		var view: EntityView = views.get(entity_id, null)
		if view == null:
			view = EntityView.new()
			view.name = "EntityView_%d" % entity_id
			views[entity_id] = view
			add_child(view)
			view.setup(entity, zone_view, registry)
		else:
			view.sync()

	# Remove views for dead or removed entities
	var to_remove: Array[int] = []
	for id_val: Variant in views.keys():
		var id: int = int(id_val)
		if not current_living_ids.has(id):
			to_remove.append(id)

	for id: int in to_remove:
		var view: EntityView = views[id]
		views.erase(id)
		if is_instance_valid(view):
			view.queue_free()


func _update_player(entity: Entity) -> void:
	if player_hp_bar == null and player_marker != null:
		_setup_player_hp_bar()

	if player_hp_bar != null:
		var max_hp: float = 100.0
		if entity.stats != null and entity.stats.max_hp > 0.0:
			max_hp = entity.stats.max_hp
		elif registry != null:
			var val: Variant = registry.get_balance("player.max_hp")
			if val != null and float(val) > 0.0:
				max_hp = float(val)
		var ratio := clampf(entity.hp / max_hp, 0.0, 1.0) if max_hp > 0.0 else 0.0
		player_hp_bar.update_ratio(ratio)


func _handle_sim_event(event: Dictionary) -> void:
	var event_type: String = str(event.get("type", ""))
	match event_type:
		"telegraph_start":
			_spawn_telegraph(event)
		"damage":
			_spawn_floating_text(event)


func _spawn_telegraph(event: Dictionary) -> void:
	_init_containers()
	var tile_px: int = 32
	if registry != null:
		var px_val: Variant = registry.get_balance("view.tile_px")
		if px_val != null and int(px_val) > 0:
			tile_px = int(px_val)

	var telegraph := TelegraphView.new()
	telegraphs_root.add_child(telegraph)
	telegraph.setup(event, tile_px, registry)


func _spawn_floating_text(event: Dictionary) -> void:
	_init_containers()
	var target_id: int = int(event.get("target", 0))
	var target_entity: Entity = world.get_entity(target_id) if world != null else null

	var world_pos := Vector2.ZERO
	var is_player := false

	if target_entity != null:
		if zone_view != null:
			world_pos = zone_view.entity_to_world(target_entity.pos)
		else:
			world_pos = target_entity.pos * 32.0
		is_player = target_entity.kind == "player"

	var amount: float = float(event.get("amount", 0.0))
	var ft := FloatingText.new()
	floating_texts_root.add_child(ft)
	ft.setup(amount, world_pos, is_player, registry)


func get_entity_view(id: int) -> EntityView:
	return views.get(id, null)


func has_entity_view(id: int) -> bool:
	return views.has(id)


func get_views() -> Dictionary:
	return views


func get_telegraph_views() -> Array[TelegraphView]:
	var result: Array[TelegraphView] = []
	if telegraphs_root != null:
		for child: Node in telegraphs_root.get_children():
			if child is TelegraphView:
				result.append(child)
	return result


func get_floating_texts() -> Array[FloatingText]:
	var result: Array[FloatingText] = []
	if floating_texts_root != null:
		for child: Node in floating_texts_root.get_children():
			if child is FloatingText:
				result.append(child)
	return result
