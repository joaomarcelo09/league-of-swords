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
		errors.append_array(_validate_attack(dict["attack"], "attack"))

	if dict.has("phase2"):
		if not (dict["phase2"] is Dictionary):
			errors.append("invalid 'phase2' (must be Dictionary)")
		else:
			errors.append_array(_validate_phase2(dict["phase2"]))

	return errors


## Shared attack validation, used by the base attack and by phase2.attack.
## `label` names the block in the error messages ("attack", "phase2.attack").
static func _validate_attack(attack: Dictionary, label: String) -> Array[String]:
	var errors: Array[String] = []
	var shape: String = str(attack.get("shape", ""))
	if not shape in ["line", "cone", "circle"]:
		errors.append("%s missing or invalid 'shape' (must be 'line', 'cone', or 'circle')" % label)

	if not attack.has("range") or not (attack["range"] is int or attack["range"] is float) or float(attack["range"]) <= 0.0:
		errors.append("%s missing or invalid 'range' (must be number > 0.0)" % label)

	match shape:
		"line":
			if not attack.has("width") or not (attack["width"] is int or attack["width"] is float) or float(attack["width"]) <= 0.0:
				errors.append("%s shape 'line' requires 'width' > 0.0" % label)
		"cone":
			if not attack.has("angle_deg") or not (attack["angle_deg"] is int or attack["angle_deg"] is float) or float(attack["angle_deg"]) <= 0.0 or float(attack["angle_deg"]) > 360.0:
				errors.append("%s shape 'cone' requires 'angle_deg' > 0.0 and <= 360.0" % label)
		"circle":
			if not attack.has("radius") or not (attack["radius"] is int or attack["radius"] is float) or float(attack["radius"]) <= 0.0:
				errors.append("%s shape 'circle' requires 'radius' > 0.0" % label)

	if attack.has("damage_mult") and (not (attack["damage_mult"] is int or attack["damage_mult"] is float) or float(attack["damage_mult"]) < 0.0):
		errors.append("%s has invalid 'damage_mult' (must be number >= 0.0)" % label)

	return errors


## Validates the optional phase2 block. Every key is optional except the HP
## threshold; the view reads weapon_layer from the same block.
static func _validate_phase2(phase2: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var threshold: Variant = phase2.get("hp_ratio_below", null)
	if not (threshold is int or threshold is float) or float(threshold) <= 0.0 or float(threshold) >= 1.0:
		errors.append("phase2 missing or invalid 'hp_ratio_below' (must be number in (0.0, 1.0))")

	for key: String in ["windup_s", "active_s", "recovery_s"]:
		if phase2.has(key) and (not (phase2[key] is int or phase2[key] is float) or float(phase2[key]) < 0.0):
			errors.append("phase2 has invalid '%s' (must be number >= 0.0)" % key)

	if phase2.has("attack"):
		if not (phase2["attack"] is Dictionary) or (phase2["attack"] as Dictionary).is_empty():
			errors.append("phase2 has invalid 'attack' (must be non-empty Dictionary)")
		else:
			errors.append_array(_validate_attack(phase2["attack"], "phase2.attack"))

	return errors


## True while the entity is strictly below its config's phase 2 HP threshold.
## False when the enemy has no valid phase2 block.
static func is_phase2(entity: Entity, enemy_cfg: Dictionary) -> bool:
	if entity == null or entity.stats == null or entity.stats.max_hp <= 0.0:
		return false
	var block: Variant = enemy_cfg.get("phase2", null)
	if not (block is Dictionary):
		return false
	var threshold: Variant = (block as Dictionary).get("hp_ratio_below", null)
	if not (threshold is int or threshold is float):
		return false
	var ratio := float(threshold)
	if ratio <= 0.0 or ratio >= 1.0:
		return false
	return entity.hp / entity.stats.max_hp < ratio


## Effective attack pattern for this tick: the base values, overridden by the
## enemy's phase2 block while phase 2 is active.
static func _resolve_combat(entity: Entity, enemy_cfg: Dictionary) -> Dictionary:
	var combat: Dictionary = {
		"windup_s": float(enemy_cfg["windup_s"]),
		"active_s": float(enemy_cfg["active_s"]),
		"recovery_s": float(enemy_cfg["recovery_s"]),
		"attack": enemy_cfg["attack"],
		"phase": 1,
	}
	if not is_phase2(entity, enemy_cfg):
		return combat

	var phase2: Dictionary = enemy_cfg["phase2"]
	combat["phase"] = 2
	for key: String in ["windup_s", "active_s", "recovery_s"]:
		if phase2.has(key):
			combat[key] = float(phase2[key])
	var phase2_attack: Variant = phase2.get("attack", null)
	if phase2_attack is Dictionary and not (phase2_attack as Dictionary).is_empty():
		combat["attack"] = phase2_attack
	return combat


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
	var combat := _resolve_combat(entity, enemy_cfg)
	var windup_ticks := _duration_ticks(float(combat["windup_s"]), sim.tick_length)

	match entity.state:
		"idle":
			var target := _find_nearest_player(sim, entity, aggro_radius)
			if target != null:
				entity.target_id = target.id
				entity.state = "chase"
				_process_chase(sim, entity, combat, aggro_radius, leash_radius, windup_ticks)
			else:
				var spawn_tile := Vector2i(int(floor(entity.spawn_pos.x)), int(floor(entity.spawn_pos.y)))
				if entity.tile() != spawn_tile:
					_step_toward_spawn(sim, entity)

		"chase":
			_process_chase(sim, entity, combat, aggro_radius, leash_radius, windup_ticks)

		"windup":
			if sim.tick_count >= entity.state_end_tick:
				var pattern := _locked_pattern(entity, combat)
				var locked_attack: Dictionary = pattern["attack"]
				entity.state = "active"
				entity.state_end_tick = sim.tick_count + _duration_ticks(float(pattern["active_s"]), sim.tick_length)
				_perform_attack(sim, entity, enemy_cfg, locked_attack)

		"active":
			if sim.tick_count >= entity.state_end_tick:
				var pattern := _locked_pattern(entity, combat)
				entity.state = "recovery"
				entity.state_end_tick = sim.tick_count + _duration_ticks(float(pattern["recovery_s"]), sim.tick_length)

		"recovery":
			if sim.tick_count >= entity.state_end_tick:
				entity.state = "chase"
				entity.attack_pattern = {}

		"reset":
			_step_toward_spawn(sim, entity)

		_:
			entity.state = "idle"


## The attack pattern stored when the windup started, so a phase change mid-swing
## cannot alter its shape or timings. Falls back to this tick's effective values
## when no pattern was stored (e.g. a windup started directly).
static func _locked_pattern(entity: Entity, combat: Dictionary) -> Dictionary:
	var pattern: Dictionary = entity.attack_pattern
	var attack: Dictionary = pattern.get("attack", combat["attack"])
	return {
		"attack": attack,
		"active_s": float(pattern.get("active_s", combat["active_s"])),
		"recovery_s": float(pattern.get("recovery_s", combat["recovery_s"])),
		"phase": int(pattern.get("phase", combat["phase"])),
	}


static func _duration_ticks(duration_s: float, tick_length: float) -> int:
	var ticks: int = int(round(duration_s / tick_length))
	if ticks < 1 and duration_s > 0.0:
		ticks = 1
	return ticks


static func _process_chase(
	sim: WorldSim,
	entity: Entity,
	combat: Dictionary,
	aggro_radius: float,
	leash_radius: float,
	windup_ticks: int
) -> void:
	var attack: Dictionary = combat["attack"]
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
		_start_windup(sim, entity, target, attack, float(combat["windup_s"]), windup_ticks,
			float(combat["active_s"]), float(combat["recovery_s"]), int(combat["phase"]))
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
		_start_windup(sim, entity, target, attack, float(combat["windup_s"]), windup_ticks,
			float(combat["active_s"]), float(combat["recovery_s"]), int(combat["phase"]))


static func _start_windup(
	sim: WorldSim,
	entity: Entity,
	target: Entity,
	attack: Dictionary,
	windup_s: float,
	windup_ticks: int,
	active_s: float = -1.0,
	recovery_s: float = -1.0,
	phase: int = 1
) -> void:
	entity.state = "windup"
	entity.state_end_tick = sim.tick_count + windup_ticks
	entity.locked_origin = entity.pos
	var to_target := target.pos - entity.pos
	if to_target.is_zero_approx():
		entity.locked_dir = Vector2.RIGHT
	else:
		entity.locked_dir = to_target.normalized()

	entity.attack_pattern = {"attack": attack, "phase": phase}
	if active_s >= 0.0:
		entity.attack_pattern["active_s"] = active_s
	if recovery_s >= 0.0:
		entity.attack_pattern["recovery_s"] = recovery_s

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
	if phase == 2:
		event["phase"] = 2
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
