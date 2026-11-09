class_name WorldSim
extends RefCounted

var zone: Zone = null
var registry: DataRegistry = null
var _tick_len: float = 0.0
var tick_length: float:
	get:
		return _tick_len
var tick_count: int = 0
var entities: Dictionary = {}
var _events: Array[Dictionary] = []

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
		Commands.CastSkill: _begin_cast_skill,
		Commands.Dash: _begin_dash,
	}
	_update_handlers = {
		Commands.MoveTo: _update_move_to,
		Commands.AttackTarget: _update_attack_target,
		Commands.CastSkill: _update_cast_skill,
		Commands.Dash: _update_dash,
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

	var final_stats := stats
	if final_stats == null and registry != null and not kind.is_empty():
		var kind_data: Variant = registry.get_balance(kind)
		if kind_data is Dictionary:
			final_stats = Stats.from_dict(kind_data)

	var final_hp := hp
	if final_hp < 0.0:
		if final_stats != null and final_stats.max_hp > 0.0:
			final_hp = final_stats.max_hp
		elif registry != null and not kind.is_empty():
			var val: Variant = registry.get_balance(kind + ".max_hp")
			if val != null and float(val) > 0.0:
				final_hp = float(val)

	if final_hp < 0.0:
		push_error("Entity %d (kind '%s') cannot resolve HP source and spawned dead" % [entity_id, kind])
		final_hp = 0.0

	var entity := Entity.new(entity_id, kind, entity_pos, speed, final_hp, final_stats)
	if registry != null and not kind.is_empty():
		var kind_skills: Variant = registry.get_balance(kind + ".skills")
		if kind_skills is Dictionary:
			entity.skills = (kind_skills as Dictionary).duplicate()
	entities[entity_id] = entity
	return entity


func spawn_enemy(type_id: String, tile: Vector2i, hp: float = -1.0, stats: Stats = null) -> Entity:
	if registry == null or not registry.has_entry("enemies", type_id):
		push_error("spawn_enemy: unknown or missing enemy type '%s'" % type_id)
		return null

	var enemy_cfg: Dictionary = registry.get_entry("enemies", type_id)
	var errors := EnemyAI.validate_config(enemy_cfg)
	if not errors.is_empty():
		push_error("spawn_enemy: invalid enemy config for '%s': %s" % [type_id, ", ".join(errors)])
		return null

	var speed: float = 0.0
	if enemy_cfg.has("move_speed_tiles_per_s") and (enemy_cfg["move_speed_tiles_per_s"] is int or enemy_cfg["move_speed_tiles_per_s"] is float):
		speed = float(enemy_cfg["move_speed_tiles_per_s"])
	elif registry != null:
		var balance_speed: Variant = registry.get_balance("enemy.move_speed_tiles_per_s")
		if balance_speed != null and float(balance_speed) > 0.0:
			speed = float(balance_speed)

	if speed <= 0.0:
		push_error("spawn_enemy: enemy '%s' has no valid move speed in config or balance" % type_id)
		return null

	var entity := spawn("enemy", tile, speed, hp, stats)
	if entity == null:
		return null
	entity.enemy_type_id = type_id
	entity.state = "idle"
	entity.spawn_pos = tile_center(tile)
	if enemy_cfg.has("recovery_damage_mult"):
		entity.recovery_damage_mult = float(enemy_cfg["recovery_damage_mult"])
	return entity


func record_event(event: Dictionary) -> void:
	_events.append(event)


func get_entity(id: int) -> Entity:
	return entities.get(id, null)


func submit(cmd: Commands.Command) -> void:
	if cmd != null:
		_command_queue.append(cmd)


func drain_events() -> Array[Dictionary]:
	var result: Array[Dictionary] = _events.duplicate()
	_events.clear()
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
	if entity.command is Commands.Dash:
		return

	var handler: Callable = _begin_handlers.get(cmd.get_script(), Callable())
	if not handler.is_valid():
		entity.command = null
		entity.path.clear()
		entity.path_index = 0
		return

	if cmd is Commands.CastSkill or cmd is Commands.Dash:
		handler.call(entity, cmd)
	else:
		entity.command = cmd
		handler.call(entity, cmd)


func _update_entities() -> void:
	var ids: Array = entities.keys()
	ids.sort()
	for id: Variant in ids:
		var entity: Entity = entities[id]
		if entity.dead:
			continue
		if not entity.buffs.is_empty():
			var active_buffs: Array[Dictionary] = []
			for buff: Dictionary in entity.buffs:
				var expires: float = float(buff.get("expires_tick", 0.0))
				if float(tick_count) < expires - 1e-9:
					active_buffs.append(buff)
			entity.buffs = active_buffs
		if entity.kind == "enemy" and not entity.enemy_type_id.is_empty():
			EnemyAI.update(self, entity)
		elif entity.command != null:
			var handler: Callable = _update_handlers.get(entity.command.get_script(), Callable())
			if handler.is_valid():
				handler.call(entity, entity.command)
			else:
				entity.command = null
				entity.path.clear()
				entity.path_index = 0


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
	while remaining_dist > 0.0 and (entity.command != null or not entity.enemy_type_id.is_empty()):
		if entity.path_index >= entity.path.size():
			break

		var target_pos: Vector2 = tile_center(entity.path[entity.path_index])
		var to_target: Vector2 = target_pos - entity.pos
		var dist: float = to_target.length()

		if zone != null and not DashRules.is_segment_walkable(entity.pos, target_pos, zone):
			entity.command = null
			entity.path.clear()
			entity.path_index = 0
			break

		if dist <= remaining_dist + 1e-9:
			entity.pos = target_pos
			remaining_dist -= dist
			if remaining_dist < 0.0:
				remaining_dist = 0.0
			entity.path_index += 1
			if entity.path_index >= entity.path.size():
				break
		else:
			var step_move: Vector2 = (to_target / dist) * remaining_dist
			var next_pos: Vector2 = entity.pos + step_move
			if zone != null and not DashRules.is_segment_walkable(entity.pos, next_pos, zone):
				entity.command = null
				entity.path.clear()
				entity.path_index = 0
				break
			entity.pos = next_pos
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
	if cmd.target_id == entity.id:
		entity.command = null
		entity.path.clear()
		entity.path_index = 0
		return

	var target: Entity = get_entity(cmd.target_id)
	if target == null or target.dead:
		entity.command = null
		entity.path.clear()
		entity.path_index = 0
		return

	var attack_range: float = _get_attack_range(entity)
	var attack_interval: float = _get_attack_interval(entity)
	if attack_range <= 0.0 or attack_interval <= 0.0:
		entity.command = null
		entity.path.clear()
		entity.path_index = 0
		return

	var dist: float = entity.pos.distance_to(target.pos)
	if dist > attack_range + 1e-9:
		cmd.last_target_tile = target.tile()
		_path_to_tile(entity, cmd.last_target_tile)


func _update_attack_target(entity: Entity, cmd: Commands.AttackTarget) -> void:
	if cmd.target_id == entity.id:
		entity.command = null
		entity.path.clear()
		entity.path_index = 0
		return

	var target: Entity = get_entity(cmd.target_id)
	if target == null or target.dead:
		entity.command = null
		entity.path.clear()
		entity.path_index = 0
		return

	var attack_range: float = _get_attack_range(entity)
	var attack_interval: float = _get_attack_interval(entity)
	if attack_range <= 0.0 or attack_interval <= 0.0:
		entity.command = null
		entity.path.clear()
		entity.path_index = 0
		return

	var dist: float = entity.pos.distance_to(target.pos)

	if dist > attack_range + 1e-9:
		var target_tile := target.tile()
		if cmd.last_target_tile != target_tile:
			cmd.last_target_tile = target_tile
			_path_to_tile(entity, target_tile)

		_step_along_path(entity, entity.speed * _tick_len)
		dist = entity.pos.distance_to(target.pos)

	if dist <= attack_range + 1e-9:
		entity.path.clear()
		entity.path_index = 0
		cmd.last_target_tile = Vector2i(-1, -1)
		if tick_count >= entity.attack_ready_tick - 1e-9:
			_perform_attack(entity, target)
			var interval_ticks: float = attack_interval / _tick_len
			if entity.attack_ready_tick <= float(tick_count - 1) + 1e-9:
				entity.attack_ready_tick = float(tick_count) + interval_ticks
			else:
				entity.attack_ready_tick += interval_ticks


func _get_attack_range(entity: Entity) -> float:
	if entity.stats != null and entity.stats.attack_range > 0.0:
		return entity.stats.attack_range
	if registry != null and not entity.kind.is_empty():
		var val: Variant = registry.get_balance(entity.kind + ".attack_range")
		if val != null and float(val) > 0.0:
			return float(val)
	push_error("Entity %d (kind '%s') missing attack_range in stats or data" % [entity.id, entity.kind])
	return 0.0


func _get_attack_interval(entity: Entity) -> float:
	if entity.stats != null and entity.stats.attack_interval > 0.0:
		return entity.stats.attack_interval
	if registry != null and not entity.kind.is_empty():
		var val: Variant = registry.get_balance(entity.kind + ".attack_interval")
		if val != null and float(val) > 0.0:
			return float(val)
	push_error("Entity %d (kind '%s') missing attack_interval in stats or data" % [entity.id, entity.kind])
	return 0.0


func apply_damage(source_id: int, target: Entity, amount: float) -> void:
	if target == null or target.dead:
		return
	var final_amount := amount
	if target.state == "recovery" and target.recovery_damage_mult != 1.0:
		final_amount = amount * target.recovery_damage_mult
	target.hp -= final_amount
	_events.append({
		"type": "damage",
		"tick": tick_count,
		"source": source_id,
		"target": target.id,
		"amount": final_amount,
	})
	if target.hp <= 0.0:
		target.dead = true
		_events.append({
			"type": "death",
			"tick": tick_count,
			"target": target.id,
			"source": source_id,
		})
		_handle_entity_death(target)


func effective_stats(entity: Entity) -> Stats:
	if entity == null:
		return null
	var base := entity.stats
	if base == null and registry != null and not entity.kind.is_empty():
		var kind_data: Variant = registry.get_balance(entity.kind)
		if kind_data is Dictionary:
			base = Stats.from_dict(kind_data)
	if base == null:
		return null

	var eff := base.duplicate()
	for buff: Dictionary in entity.buffs:
		var expires: float = float(buff.get("expires_tick", 0.0))
		if float(tick_count) >= expires - 1e-9:
			continue
		var stat_name: String = str(buff.get("stat", ""))
		var mult: float = float(buff.get("mult", 1.0))
		match stat_name:
			"atk":
				eff.atk *= mult
			"defense":
				eff.defense *= mult
			"max_hp":
				eff.max_hp *= mult
			"attack_range":
				eff.attack_range *= mult
			"attack_interval":
				eff.attack_interval *= mult
			"weapon_damage":
				eff.weapon_damage *= mult
	return eff


func apply_heal(source_id: int, target: Entity, amount: float) -> float:
	if target == null or target.dead:
		return 0.0
	var max_hp: float = 0.0
	var eff := effective_stats(target)
	if eff != null and eff.max_hp > 0.0:
		max_hp = eff.max_hp
	elif target.stats != null and target.stats.max_hp > 0.0:
		max_hp = target.stats.max_hp
	elif registry != null and not target.kind.is_empty():
		var val: Variant = registry.get_balance(target.kind + ".max_hp")
		if val != null:
			max_hp = float(val)

	var old_hp := target.hp
	target.hp = minf(max_hp, target.hp + amount)
	var healed := target.hp - old_hp
	_events.append({
		"type": "heal",
		"tick": tick_count,
		"source": source_id,
		"target": target.id,
		"amount": healed,
	})
	return healed


func _perform_attack(attacker: Entity, target: Entity) -> void:
	var attacker_stats := effective_stats(attacker)
	if attacker_stats == null:
		push_error("Entity %d cannot attack without usable stats" % attacker.id)
		attacker.command = null
		return
	var target_stats := effective_stats(target)
	var damage: float = Combat.compute_damage(attacker_stats, target_stats, registry)
	apply_damage(attacker.id, target, damage)


func _begin_cast_skill(entity: Entity, cmd: Commands.CastSkill) -> void:
	if not entity.skills.has(cmd.slot):
		_events.append({
			"type": "cast_failed",
			"tick": tick_count,
			"source": entity.id,
			"slot": cmd.slot,
			"reason": "unknown_slot",
		})
		return

	var skill_id: String = entity.skills.get(cmd.slot, "")
	if skill_id.is_empty() or registry == null or not registry.has_entry("skills", skill_id):
		_events.append({
			"type": "cast_failed",
			"tick": tick_count,
			"source": entity.id,
			"slot": cmd.slot,
			"reason": "unknown_skill",
		})
		return

	var skill: Dictionary = registry.get_entry("skills", skill_id)
	var errors: Array[String] = SkillSystem.validate_skill(skill)
	if not errors.is_empty():
		for err in errors:
			push_error("Skill '%s' invalid: %s" % [skill_id, err])
		_events.append({
			"type": "cast_failed",
			"tick": tick_count,
			"source": entity.id,
			"slot": cmd.slot,
			"reason": "invalid_skill",
		})
		return

	var to_aim := cmd.aim - entity.pos
	if to_aim.is_zero_approx():
		_events.append({
			"type": "cast_failed",
			"tick": tick_count,
			"source": entity.id,
			"slot": cmd.slot,
			"reason": "zero_direction",
		})
		return

	var ready_tick: float = entity.skill_ready_ticks.get(cmd.slot, 0.0)
	if float(tick_count) < ready_tick - 1e-9:
		_events.append({
			"type": "cast_failed",
			"tick": tick_count,
			"source": entity.id,
			"slot": cmd.slot,
			"reason": "cooldown",
		})
		return

	entity.path.clear()
	entity.path_index = 0

	var cast_time_s: float = float(skill.get("cast_time_s", 0.0))
	var cast_ticks: int = int(round(cast_time_s / _tick_len))
	if cast_ticks <= 0:
		entity.command = cmd
		_resolve_cast_skill(entity, cmd, skill)
		entity.command = null
	else:
		cmd.resolve_tick = tick_count + cast_ticks - 1
		entity.command = cmd


func _update_cast_skill(entity: Entity, cmd: Commands.CastSkill) -> void:
	if tick_count >= cmd.resolve_tick:
		var skill_id: String = entity.skills.get(cmd.slot, "")
		var skill: Dictionary = registry.get_entry("skills", skill_id)
		_resolve_cast_skill(entity, cmd, skill)
		entity.command = null


func _begin_dash(entity: Entity, cmd: Commands.Dash) -> void:
	var dash_data: Variant = null
	if registry != null:
		dash_data = registry.get_balance("dash")

	var param_errors: Array[String] = []
	if not (dash_data is Dictionary):
		param_errors.append("dash balance config missing or not a Dictionary")
	else:
		param_errors = DashRules.validate_params(dash_data as Dictionary)

	if not param_errors.is_empty():
		for err in param_errors:
			push_error("Dash invalid: %s" % err)
		_events.append({
			"type": "dash_failed",
			"tick": tick_count,
			"source": entity.id,
			"reason": "invalid_params",
		})
		return

	if cmd.aim.is_zero_approx() or not cmd.aim.is_finite():
		_events.append({
			"type": "dash_failed",
			"tick": tick_count,
			"source": entity.id,
			"reason": "invalid_aim",
		})
		return

	cmd.aim = cmd.aim.normalized()

	if float(tick_count) < entity.dash_ready_tick - 1e-9:
		_events.append({
			"type": "dash_failed",
			"tick": tick_count,
			"source": entity.id,
			"reason": "cooldown",
		})
		return

	var dash_dict: Dictionary = dash_data as Dictionary
	var distance_tiles: float = float(dash_dict.get("distance_tiles", 0.0))
	var duration_s: float = float(dash_dict.get("duration_s", 0.0))
	var cooldown_s: float = float(dash_dict.get("cooldown_s", 0.0))

	var cd_ticks: float = cooldown_s / _tick_len
	entity.dash_ready_tick = float(tick_count) + cd_ticks

	entity.path.clear()
	entity.path_index = 0

	var from_pos: Vector2 = entity.pos
	var to_pos: Vector2 = DashRules.compute_end_position(from_pos, cmd.aim, distance_tiles, zone)

	var nominal_speed: float = distance_tiles / duration_s
	var real_distance: float = from_pos.distance_to(to_pos)
	var real_duration_s: float = real_distance / nominal_speed if nominal_speed > 0.0 else 0.0
	var step_dist: float = nominal_speed * _tick_len

	var duration_ticks: int = 1
	if real_distance > 1e-6 and step_dist > 0.0:
		duration_ticks = int(ceil(real_distance / step_dist - 1e-9))
		if duration_ticks < 1:
			duration_ticks = 1

	cmd.from = from_pos
	cmd.to = to_pos
	cmd.distance = real_distance
	cmd.duration_s = real_duration_s

	entity.command = cmd

	_events.append({
		"type": "dash",
		"tick": tick_count,
		"entity": entity.id,
		"from": from_pos,
		"to": to_pos,
		"duration_ticks": duration_ticks,
	})


func _update_dash(entity: Entity, cmd: Commands.Dash) -> void:
	if entity.dead:
		entity.command = null
		return

	var to_target: Vector2 = cmd.to - entity.pos
	var dist_to_target: float = to_target.length()
	if dist_to_target <= 1e-6:
		entity.pos = cmd.to
		entity.command = null
		return

	var speed: float = 0.0
	if cmd.duration_s > 1e-9:
		speed = cmd.distance / cmd.duration_s
	var max_dist_this_tick: float = speed * _tick_len
	var move_dist: float = minf(max_dist_this_tick, dist_to_target)
	var dir: Vector2 = to_target / dist_to_target

	var remaining := move_dist
	var max_step := 0.5
	while remaining > 1e-9:
		var step := minf(max_step, remaining)
		var next_pos := entity.pos + dir * step
		if zone != null and not DashRules.is_segment_walkable(entity.pos, next_pos, zone):
			entity.command = null
			return
		entity.pos = next_pos
		remaining -= step

	if entity.pos.distance_to(cmd.to) <= 1e-6:
		entity.pos = cmd.to
		entity.command = null



func _resolve_cast_skill(entity: Entity, cmd: Commands.CastSkill, skill: Dictionary) -> void:
	if entity.dead:
		return

	var cooldown_s: float = float(skill.get("cooldown_s", 0.0))
	var cd_ticks: float = cooldown_s / _tick_len
	entity.skill_ready_ticks[cmd.slot] = float(tick_count) + cd_ticks

	var skill_id: String = entity.skills.get(cmd.slot, "")
	_events.append({
		"type": "skill_cast",
		"tick": tick_count,
		"source": entity.id,
		"skill": skill_id,
		"slot": cmd.slot,
	})

	var hit_entities: Array[Entity] = []
	var aim_offset := cmd.aim - entity.pos
	var sorted_ids: Array = entities.keys()
	sorted_ids.sort()
	for other_id: Variant in sorted_ids:
		var other: Entity = entities[other_id]
		if other.id == entity.id or other.dead:
			continue
		if SkillSystem.in_shape(skill, entity.pos, aim_offset, other.pos):
			hit_entities.append(other)

	for effect: Dictionary in skill.get("effects", []):
		var eff_type: String = str(effect.get("type", ""))
		var target_mode: String = str(effect.get("target", ""))
		if target_mode.is_empty():
			if eff_type == "damage":
				target_mode = "hit"
			else:
				target_mode = "self"

		var targets: Array[Entity] = []
		if target_mode == "hit":
			targets = hit_entities
		elif target_mode == "self":
			if not entity.dead:
				targets = [entity]

		match eff_type:
			"damage":
				var mult: float = float(effect.get("mult", 1.0))
				var attacker_stats := effective_stats(entity)
				for target: Entity in targets:
					if target.dead:
						continue
					var target_stats := effective_stats(target)
					var base_dmg: float = Combat.compute_damage(attacker_stats, target_stats, registry)
					apply_damage(entity.id, target, mult * base_dmg)
			"heal":
				var amount: float = float(effect.get("amount", 0.0))
				for target: Entity in targets:
					if target.dead:
						continue
					apply_heal(entity.id, target, amount)
			"buff":
				var stat: String = str(effect.get("stat", ""))
				var mult: float = float(effect.get("mult", 1.0))
				var duration_s: float = float(effect.get("duration_s", 0.0))
				var duration_ticks: float = duration_s / _tick_len
				var expires_tick: int = tick_count + int(round(duration_ticks))
				for target: Entity in targets:
					if target.dead:
						continue
					target.buffs.append({
						"stat": stat,
						"mult": mult,
						"expires_tick": expires_tick,
					})
					_events.append({
						"type": "buff",
						"tick": tick_count,
						"source": entity.id,
						"target": target.id,
						"stat": stat,
						"mult": mult,
						"expires_tick": expires_tick,
					})


func _handle_entity_death(dead_entity: Entity) -> void:
	dead_entity.command = null
	dead_entity.path.clear()
	dead_entity.path_index = 0
	for entity: Entity in entities.values():
		if entity.command != null and entity.command.is_targeting(dead_entity.id):
			entity.command = null
			entity.path.clear()
			entity.path_index = 0
