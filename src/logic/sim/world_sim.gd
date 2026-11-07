class_name WorldSim
extends RefCounted

var zone: Zone = null
var registry: DataRegistry = null
var tick_len: float = 0.0
var tick_length: float:
	get:
		return tick_len
var tick_count: int = 0
var entities: Dictionary = {}

var _next_entity_id: int = 1
var _command_queue: Array = []
var _accumulator: float = 0.0


func _init(p_zone: Zone, p_registry: DataRegistry) -> void:
	zone = p_zone
	registry = p_registry
	var tick_hz: float = 30.0
	if registry != null:
		var hz_val: Variant = registry.get_balance("sim.tick_hz")
		if hz_val != null and float(hz_val) > 0.0:
			tick_hz = float(hz_val)
	tick_len = 1.0 / tick_hz


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


func spawn(kind: String, tile: Vector2i, speed: float, hp: float = 100.0) -> Entity:
	var entity_id := _next_entity_id
	_next_entity_id += 1
	var entity_pos := tile_center(tile)
	var entity := Entity.new(entity_id, kind, entity_pos, speed, hp)
	entities[entity_id] = entity
	return entity


func get_entity(id: int) -> Entity:
	return entities.get(id, null)


func submit(cmd: Variant) -> void:
	if cmd != null:
		_command_queue.append(cmd)


func step(dt: float) -> void:
	if dt <= 0.0:
		return
	_accumulator += dt
	while _accumulator >= tick_len - 1e-9:
		_accumulator -= tick_len
		if _accumulator < 0.0:
			_accumulator = 0.0
		_tick()


func _tick() -> void:
	tick_count += 1
	var pending: Array = _command_queue.duplicate()
	_command_queue.clear()
	for cmd: Variant in pending:
		if cmd == null:
			continue
		var entity: Entity = get_entity(cmd.entity_id)
		if entity == null:
			continue
		_apply_command(entity, cmd)
	_update_entities()


func _apply_command(entity: Entity, cmd: Variant) -> void:
	entity.command = cmd
	if cmd is Commands.MoveTo:
		_init_move_to(entity, cmd as Commands.MoveTo)


func _init_move_to(entity: Entity, cmd: Commands.MoveTo) -> void:
	if zone == null:
		entity.path.clear()
		entity.path_index = 0
		entity.command = null
		return

	var target_tile: Vector2i = cmd.target
	var path: Array[Vector2i] = zone.find_path(entity.tile(), target_tile)
	if path.is_empty():
		target_tile = zone.nearest_reachable(entity.tile(), target_tile)
		if target_tile != Vector2i(-1, -1):
			path = zone.find_path(entity.tile(), target_tile)

	if path.is_empty():
		entity.path.clear()
		entity.path_index = 0
		entity.command = null
		return

	entity.path = path
	if path.size() == 1:
		var dest := tile_center(path[0])
		if entity.pos.is_equal_approx(dest):
			entity.pos = dest
			entity.path_index = 0
			entity.command = null
		else:
			entity.path_index = 0
	else:
		var p0 := tile_center(path[0])
		var p1 := tile_center(path[1])
		if _is_on_segment(entity.pos, p0, p1):
			entity.path_index = 1
		else:
			entity.path_index = 0


func _update_entities() -> void:
	var ids: Array = entities.keys()
	ids.sort()
	for id: Variant in ids:
		var entity: Entity = entities[id]
		if entity.command != null:
			if entity.command is Commands.MoveTo:
				_update_move_to(entity)


func _update_move_to(entity: Entity) -> void:
	if entity.path.is_empty():
		entity.command = null
		return

	var remaining_dist: float = entity.speed * tick_len
	while remaining_dist > 0.0 and entity.command != null:
		if entity.path_index >= entity.path.size():
			entity.command = null
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
				entity.command = null
				break
		else:
			entity.pos += (to_target / dist) * remaining_dist
			remaining_dist = 0.0
