class_name WorldSim
extends RefCounted

var zone: Zone = null
var registry: DataRegistry = null
var _tick_len: float = 0.0
var tick_length: float:
	get:
		return _tick_len
var tick_len: float:
	get:
		return _tick_len
var tick_count: int = 0
var entities: Dictionary = {}
var events: Array[Dictionary] = []

var _next_entity_id: int = 1
var _command_queue: Array[Commands.Command] = []
var _accumulator: float = 0.0

var _begin_handlers: Dictionary = {}
var _update_handlers: Dictionary = {}


func _init(p_zone: Zone, p_registry: DataRegistry) -> void:
	zone = p_zone
	registry = p_registry
	var tick_hz: float = 30.0
	if registry != null:
		var hz_val: Variant = registry.get_balance("sim.tick_hz")
		if hz_val != null and float(hz_val) > 0.0:
			tick_hz = float(hz_val)
	_tick_len = 1.0 / tick_hz

	_begin_handlers = {
		Commands.MoveTo: _begin_move_to,
		Commands.AttackTarget: _begin_attack_target,
	}
	_update_handlers = {
		Commands.MoveTo: _update_move_to,
		Commands.AttackTarget: _update_attack_target,
	}


static func tile_center(t: Vector2i) -> Vector2:
	return Vector2(t.x + 0.5, t.y + 0.5)


static func _is_on_segment(p: Vector2, a: Vector2, b: Vector2) -> bool:
	if is_equal_approx(a.x, b.x):
		if not is_equal_approx(p.x, a.x):
			return false
		var min_y := minf(a.y, b.y)
		var max_y := maxf(a.y, b.y)
		return p.y >= min_y - 0.0001 and p.y <= max_y + 0.0001
	elif is_equal_approx(a.y, b.y):
		if not is_equal_approx(p.y, a.y):
			return false
		var min_x := minf(a.x, b.x)
		var max_x := maxf(a.x, b.x)
		return p.x >= min_x - 0.0001 and p.x <= max_x + 0.0001
	return false


func spawn(kind: String, tile: Vector2i, speed: float, hp: float = -1.0, stats: Stats = null) -> Entity:
	var entity_id := _next_entity_id
	_next_entity_id += 1
	var entity_pos := tile_center(tile)
	var final_hp := hp
	if final_hp < 0.0 and stats == null and registry != null:
		var val: Variant = registry.get_balance(kind + ".max_hp")
		if val == null:
			val = registry.get_balance("player.max_hp")
		if val != null and float(val) > 0.0:
			final_hp = float(val)
	var entity := Entity.new(entity_id, kind, entity_pos, speed, final_hp, stats)
	entities[entity_id] = entity
	return entity


func spawn_with_stats(kind: String, tile: Vector2i, speed: float, stats: Stats, hp: float = -1.0) -> Entity:
	return spawn(kind, tile, speed, hp, stats)


func get_entity(id: int) -> Entity:
	return entities.get(id, null)


func submit(cmd: Commands.Command) -> void:
	if cmd != null:
		_command_queue.append(cmd)


func drain_events() -> Array[Dictionary]:
	var result: Array[Dictionary] = events.duplicate()
	events.clear()
	return result


func step(dt: float) -> void:
	if dt <= 0.0:
		return
	_accumulator += dt
	while _accumulator >= _tick_len - 1e-9:
		_accumulator -= _tick_len
		if _accumulator < 0.0:
			_accumulator = 0.0
		_tick()


func _tick() -> void:
	tick_count += 1
	var pending: Array[Commands.Command] = _command_queue.duplicate()
	_command_queue.clear()
	for cmd: Commands.Command in pending:
		if cmd == null:
			continue
		var entity: Entity = get_entity(cmd.entity_id)
		if entity == null or entity.dead:
			continue
		_apply_command(entity, cmd)
	_update_entities()


func _apply_command(entity: Entity, cmd: Commands.Command) -> void:
	entity.command = cmd
	var handler: Callable = _begin_handlers.get(cmd.get_script(), Callable())
	if handler.is_valid():
		handler.call(entity, cmd)


func _update_entities() -> void:
	var ids: Array = entities.keys()
	ids.sort()
	for id: Variant in ids:
		var entity: Entity = entities[id]
		if entity.dead:
			continue
		if entity.command != null:
			var handler: Callable = _update_handlers.get(entity.command.get_script(), Callable())
			if handler.is_valid():
				handler.call(entity, entity.command)


func _path_to_tile(entity: Entity, target_tile: Vector2i) -> void:
	if zone == null:
		entity.path.clear()
		entity.path_index = 0
		entity.command = null
		return

	var path: Array[Vector2i] = zone.find_path(entity.tile(), target_tile)
	if path.is_empty():
		var alt_tile: Vector2i = zone.nearest_reachable(entity.tile(), target_tile)
		if alt_tile != Vector2i(-1, -1):
			path = zone.find_path(entity.tile(), alt_tile)

	if path.is_empty():
		entity.path.clear()
		entity.path_index = 0
		return

	entity.path = path
	if path.size() == 1:
		var dest := tile_center(path[0])
		if entity.pos.is_equal_approx(dest):
			entity.pos = dest
			entity.path_index = 0
		else:
			entity.path_index = 0
	else:
		var p0 := tile_center(path[0])
		var p1 := tile_center(path[1])
		if _is_on_segment(entity.pos, p0, p1):
			entity.path_index = 1
		else:
			entity.path_index = 0


func _step_along_path(entity: Entity, max_dist: float) -> void:
	var remaining_dist: float = max_dist
	while remaining_dist > 0.0 and entity.command != null:
		if entity.path_index >= entity.path.size():
			break

		var target_pos: Vector2 = tile_center(entity.path[entity.path_index])
		var to_target: Vector2 = target_pos - entity.pos
		var dist: float = to_target.length()

		if dist <= remaining_dist + 1e-9:
			entity.pos = target_pos
			remaining_dist -= dist
			if remaining_dist < 0.0:
				remaining_dist = 0.0
			entity.path_index += 1
			if entity.path_index >= entity.path.size():
				break
		else:
			entity.pos += (to_target / dist) * remaining_dist
			remaining_dist = 0.0


func _begin_move_to(entity: Entity, cmd: Commands.MoveTo) -> void:
	_path_to_tile(entity, cmd.target)
	if entity.path.is_empty():
		entity.command = null
		return
	if entity.path.size() == 1 and entity.pos.is_equal_approx(tile_center(entity.path[0])):
		entity.command = null


func _update_move_to(entity: Entity, _cmd: Commands.MoveTo) -> void:
	if entity.path.is_empty():
		entity.command = null
		return

	_step_along_path(entity, entity.speed * _tick_len)
	if entity.path_index >= entity.path.size():
		entity.command = null


func _begin_attack_target(entity: Entity, cmd: Commands.AttackTarget) -> void:
	var target: Entity = get_entity(cmd.target_id)
	if target == null or target.dead:
		entity.command = null
		entity.path.clear()
		entity.path_index = 0
		return

	var attack_range: float = _get_attack_range(entity)
	var dist: float = entity.pos.distance_to(target.pos)
	if dist > attack_range + 1e-9:
		cmd.last_target_tile = target.tile()
		_path_to_tile(entity, cmd.last_target_tile)


func _update_attack_target(entity: Entity, cmd: Commands.AttackTarget) -> void:
	var target: Entity = get_entity(cmd.target_id)
	if target == null or target.dead:
		entity.command = null
		entity.path.clear()
		entity.path_index = 0
		return

	var attack_range: float = _get_attack_range(entity)
	var dist: float = entity.pos.distance_to(target.pos)

	if dist > attack_range + 1e-9:
		var target_tile := target.tile()
		if entity.path.is_empty() or cmd.last_target_tile != target_tile:
			cmd.last_target_tile = target_tile
			_path_to_tile(entity, target_tile)

		_step_along_path(entity, entity.speed * _tick_len)
		dist = entity.pos.distance_to(target.pos)

	if dist <= attack_range + 1e-9:
		entity.path.clear()
		entity.path_index = 0
		if tick_count >= entity.attack_ready_tick - 1e-9:
			_perform_attack(entity, target)
			var interval_ticks: float = _get_attack_interval(entity) / _tick_len
			if entity.attack_ready_tick <= float(tick_count - 1) + 1e-9:
				entity.attack_ready_tick = float(tick_count) + interval_ticks
			else:
				entity.attack_ready_tick += interval_ticks


func _get_attack_range(entity: Entity) -> float:
	if entity.stats != null and entity.stats.attack_range > 0.0:
		return entity.stats.attack_range
	if registry != null:
		var val: Variant = registry.get_balance("player.attack_range")
		if val != null:
			return float(val)
	return 1.0


func _get_attack_interval(entity: Entity) -> float:
	if entity.stats != null and entity.stats.attack_interval > 0.0:
		return entity.stats.attack_interval
	if registry != null:
		var val: Variant = registry.get_balance("player.attack_interval")
		if val != null:
			return float(val)
	return 1.0


func _perform_attack(attacker: Entity, target: Entity) -> void:
	var damage: float = Combat.compute_damage(attacker.stats, target.stats, registry)
	target.hp -= damage
	events.append({
		"type": "damage",
		"tick": tick_count,
		"source": attacker.id,
		"target": target.id,
		"amount": damage,
	})
	if target.hp <= 0.0 and not target.dead:
		target.dead = true
		events.append({
			"type": "death",
			"tick": tick_count,
			"id": target.id,
		})
		_handle_entity_death(target)


func _handle_entity_death(dead_entity: Entity) -> void:
	dead_entity.command = null
	dead_entity.path.clear()
	dead_entity.path_index = 0
	for entity: Entity in entities.values():
		if entity.command != null and entity.command.is_targeting(dead_entity.id):
			entity.command = null
			entity.path.clear()
			entity.path_index = 0
