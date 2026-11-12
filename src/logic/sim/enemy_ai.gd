class_name EnemyAI
extends RefCounted


static func validate_config(dict: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if dict.is_empty():
		errors.append("config dictionary is empty")
		return errors

	if not dict.has("name") or not (dict["name"] is String) or str(dict["name"]).strip_edges().is_empty():
		errors.append("missing or invalid 'name' (must be non-empty String)")

	if not dict.has("aggro_radius") or not (dict["aggro_radius"] is int or dict["aggro_radius"] is float) or float(dict["aggro_radius"]) <= 0.0:
		errors.append("missing or invalid 'aggro_radius' (must be number > 0.0)")

	if not dict.has("leash_radius") or not (dict["leash_radius"] is int or dict["leash_radius"] is float) or float(dict["leash_radius"]) <= 0.0:
		errors.append("missing or invalid 'leash_radius' (must be number > 0.0)")
	elif dict.has("aggro_radius") and (dict["aggro_radius"] is int or dict["aggro_radius"] is float) and float(dict["leash_radius"]) < float(dict["aggro_radius"]):
		errors.append("'leash_radius' must be >= 'aggro_radius'")

	if not dict.has("windup_s") or not (dict["windup_s"] is int or dict["windup_s"] is float) or float(dict["windup_s"]) < 0.0:
		errors.append("missing or invalid 'windup_s' (must be number >= 0.0)")

	if not dict.has("active_s") or not (dict["active_s"] is int or dict["active_s"] is float) or float(dict["active_s"]) < 0.0:
		errors.append("missing or invalid 'active_s' (must be number >= 0.0)")

	if not dict.has("recovery_s") or not (dict["recovery_s"] is int or dict["recovery_s"] is float) or float(dict["recovery_s"]) < 0.0:
		errors.append("missing or invalid 'recovery_s' (must be number >= 0.0)")

	if dict.has("move_speed_tiles_per_s") and (not (dict["move_speed_tiles_per_s"] is int or dict["move_speed_tiles_per_s"] is float) or float(dict["move_speed_tiles_per_s"]) <= 0.0):
		errors.append("invalid 'move_speed_tiles_per_s' (must be number > 0.0)")

	if dict.has("recovery_damage_mult") and (not (dict["recovery_damage_mult"] is int or dict["recovery_damage_mult"] is float) or float(dict["recovery_damage_mult"]) < 0.0):
		errors.append("invalid 'recovery_damage_mult' (must be number >= 0.0)")

	if not dict.has("attack") or not (dict["attack"] is Dictionary) or (dict["attack"] as Dictionary).is_empty():
		errors.append("missing or invalid 'attack' (must be non-empty Dictionary)")
	else:
		var attack: Dictionary = dict["attack"]
		var shape: String = str(attack.get("shape", ""))
		if not shape in ["line", "cone", "circle"]:
			errors.append("attack missing or invalid 'shape' (must be 'line', 'cone', or 'circle')")

		if not attack.has("range") or not (attack["range"] is int or attack["range"] is float) or float(attack["range"]) <= 0.0:
			errors.append("attack missing or invalid 'range' (must be number > 0.0)")

		match shape:
			"line":
				if not attack.has("width") or not (attack["width"] is int or attack["width"] is float) or float(attack["width"]) <= 0.0:
					errors.append("attack shape 'line' requires 'width' > 0.0")
			"cone":
				if not attack.has("angle_deg") or not (attack["angle_deg"] is int or attack["angle_deg"] is float) or float(attack["angle_deg"]) <= 0.0 or float(attack["angle_deg"]) > 360.0:
					errors.append("attack shape 'cone' requires 'angle_deg' > 0.0 and <= 360.0")
			"circle":
				if not attack.has("radius") or not (attack["radius"] is int or attack["radius"] is float) or float(attack["radius"]) <= 0.0:
					errors.append("attack shape 'circle' requires 'radius' > 0.0")

		if attack.has("damage_mult") and (not (attack["damage_mult"] is int or attack["damage_mult"] is float) or float(attack["damage_mult"]) < 0.0):
			errors.append("attack has invalid 'damage_mult' (must be number >= 0.0)")

	return errors


static func update(sim: WorldSim, entity: Entity) -> void:
	if entity == null or entity.dead:
		return

	if sim.registry == null or entity.enemy_type_id.is_empty():
		push_error("EnemyAI: missing registry or enemy_type_id")
		return

	var enemy_cfg: Dictionary = sim.registry.get_entry("enemies", entity.enemy_type_id)
	var errors := validate_config(enemy_cfg)
	if not errors.is_empty():
		push_error("EnemyAI: invalid enemy config for '%s': %s" % [entity.enemy_type_id, ", ".join(errors)])
		return

	var aggro_radius: float = float(enemy_cfg["aggro_radius"])
	var leash_radius: float = float(enemy_cfg["leash_radius"])
	var windup_s: float = float(enemy_cfg["windup_s"])
	var active_s: float = float(enemy_cfg["active_s"])
	var recovery_s: float = float(enemy_cfg["recovery_s"])
	var attack: Dictionary = enemy_cfg["attack"]

	var windup_ticks: int = int(round(windup_s / sim.tick_length))
	if windup_ticks < 1 and windup_s > 0.0:
		windup_ticks = 1

	var active_ticks: int = int(round(active_s / sim.tick_length))
	if active_ticks < 1 and active_s > 0.0:
		active_ticks = 1

	var recovery_ticks: int = int(round(recovery_s / sim.tick_length))
	if recovery_ticks < 1 and recovery_s > 0.0:
		recovery_ticks = 1

	match entity.state:
		"idle":
			var target := _find_nearest_player(sim, entity, aggro_radius)
			if target != null:
				entity.target_id = target.id
				entity.state = "chase"
				_process_chase(sim, entity, enemy_cfg, attack, aggro_radius, leash_radius, windup_s, windup_ticks)
			else:
				var spawn_tile := Vector2i(int(floor(entity.spawn_pos.x)), int(floor(entity.spawn_pos.y)))
				if entity.tile() != spawn_tile:
					_step_toward_spawn(sim, entity)

		"chase":
			_process_chase(sim, entity, enemy_cfg, attack, aggro_radius, leash_radius, windup_s, windup_ticks)

		"windup":
			if sim.tick_count >= entity.state_end_tick:
				entity.state = "active"
				entity.state_end_tick = sim.tick_count + active_ticks
				_perform_attack(sim, entity, enemy_cfg, attack)

		"active":
			if sim.tick_count >= entity.state_end_tick:
				entity.state = "recovery"
				entity.state_end_tick = sim.tick_count + recovery_ticks

		"recovery":
			if sim.tick_count >= entity.state_end_tick:
				entity.state = "chase"

		"reset":
			_step_toward_spawn(sim, entity)

		_:
			entity.state = "idle"


static func _process_chase(
	sim: WorldSim,
	entity: Entity,
	enemy_cfg: Dictionary,
	attack: Dictionary,
	aggro_radius: float,
	leash_radius: float,
	windup_s: float,
	windup_ticks: int
) -> void:
	var target: Entity = null
	if entity.target_id > 0:
		target = sim.get_entity(entity.target_id)

	var target_valid := (target != null and not target.dead and target.kind == "player")
	if target_valid:
		if target.pos.distance_to(entity.spawn_pos) > leash_radius + 1e-9:
			target_valid = false
		elif _is_safe_tile(sim, target.tile()):
			target_valid = false

	if not target_valid:
		target = _find_nearest_player(sim, entity, aggro_radius, leash_radius)
		if target != null:
			entity.target_id = target.id
			target_valid = true

	if not target_valid:
		_drop_to_reset(sim, entity)
		return

	var attack_range: float = float(attack["range"])
	var dist: float = entity.pos.distance_to(target.pos)
	if dist <= attack_range + 1e-9:
		entity.path.clear()
		entity.path_index = 0
		_start_windup(sim, entity, target, attack, windup_s, windup_ticks)
		return

	var target_tile := target.tile()
	if entity.path.is_empty() or entity.path[entity.path.size() - 1] != target_tile:
		sim.path_entity_to_tile(entity, target_tile)
	if _truncate_path_before_safe(sim, entity):
		_drop_to_reset(sim, entity)
		return
	sim.step_entity_along_path(entity, entity.speed * sim.tick_length)

	dist = entity.pos.distance_to(target.pos)
	if dist <= attack_range + 1e-9:
		entity.path.clear()
		entity.path_index = 0
		_start_windup(sim, entity, target, attack, windup_s, windup_ticks)


static func _start_windup(
	sim: WorldSim,
	entity: Entity,
	target: Entity,
	attack: Dictionary,
	windup_s: float,
	windup_ticks: int
) -> void:
	entity.state = "windup"
	entity.state_end_tick = sim.tick_count + windup_ticks
	entity.locked_origin = entity.pos
	var to_target := target.pos - entity.pos
	if to_target.is_zero_approx():
		entity.locked_dir = Vector2.RIGHT
	else:
		entity.locked_dir = to_target.normalized()

	var event: Dictionary = {
		"type": "telegraph_start",
		"tick": sim.tick_count,
		"source": entity.id,
		"shape": attack.get("shape", ""),
		"duration": windup_s,
		"duration_s": windup_s,
		"duration_ticks": windup_ticks,
		"origin": entity.locked_origin,
		"dir": entity.locked_dir,
	}
	for k in attack.keys():
		if not event.has(k) and k != "damage_mult":
			event[k] = attack[k]
	sim.record_event(event)


static func _perform_attack(
	sim: WorldSim,
	entity: Entity,
	_enemy_cfg: Dictionary,
	attack: Dictionary
) -> void:
	var mult: float = float(attack.get("damage_mult", 1.0))
	sim.apply_attack_shape_damage(entity, attack, entity.locked_origin, entity.locked_dir, mult, "player")


static func _step_toward_spawn(sim: WorldSim, entity: Entity) -> void:
	var spawn_tile := Vector2i(int(floor(entity.spawn_pos.x)), int(floor(entity.spawn_pos.y)))
	if entity.tile() == spawn_tile or entity.pos.is_equal_approx(entity.spawn_pos):
		entity.pos = entity.spawn_pos
		entity.path.clear()
		entity.path_index = 0
		entity.state = "idle"
		return

	if entity.path.is_empty() or entity.path[entity.path.size() - 1] != spawn_tile:
		sim.path_entity_to_tile(entity, spawn_tile)

	if _truncate_path_before_safe(sim, entity):
		# Way home crosses a safe tile: stop here and wait idle (can re-aggro).
		entity.state = "idle"
		return

	sim.step_entity_along_path(entity, entity.speed * sim.tick_length)

	if entity.tile() == spawn_tile or entity.pos.is_equal_approx(entity.spawn_pos):
		entity.pos = entity.spawn_pos
		entity.path.clear()
		entity.path_index = 0
		entity.state = "idle"


static func _drop_to_reset(sim: WorldSim, entity: Entity) -> void:
	entity.target_id = 0
	entity.state = "reset"
	entity.path.clear()
	entity.path_index = 0
	_step_toward_spawn(sim, entity)


static func _is_safe_tile(sim: WorldSim, t: Vector2i) -> bool:
	return sim.zone != null and sim.zone.is_safe(t)


# Cuts the entity's remaining path just before the first safe tile it would
# enter (its current tile is exempt, so an enemy spawned on a safe tile may
# leave). Returns true when the cut leaves no step to take: the path is
# cleared and the caller must not move the entity.
static func _truncate_path_before_safe(sim: WorldSim, entity: Entity) -> bool:
	if sim.zone == null or entity.path.is_empty():
		return false
	var current := entity.tile()
	for i in range(entity.path_index, entity.path.size()):
		var t: Vector2i = entity.path[i]
		if t != current and sim.zone.is_safe(t):
			entity.path.resize(i)
			break
	if entity.path_index >= entity.path.size():
		entity.path.clear()
		entity.path_index = 0
		return true
	return false


static func _find_nearest_player(
	sim: WorldSim,
	entity: Entity,
	max_range: float,
	max_leash_from_spawn: float = -1.0
) -> Entity:
	var best_dist: float = max_range + 1e-9
	var best_player: Entity = null
	var sorted_ids: Array = sim.entities.keys()
	sorted_ids.sort()
	for id: Variant in sorted_ids:
		var other: Entity = sim.entities[id]
		if other.id == entity.id or other.dead or other.kind != "player":
			continue
		if _is_safe_tile(sim, other.tile()):
			continue
		if max_leash_from_spawn > 0.0:
			if other.pos.distance_to(entity.spawn_pos) > max_leash_from_spawn + 1e-9:
				continue
		var dist := entity.pos.distance_to(other.pos)
		if dist <= best_dist:
			if best_player == null or dist < best_dist - 1e-6:
				best_dist = dist
				best_player = other
	return best_player
