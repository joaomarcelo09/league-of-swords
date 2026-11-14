class_name WorldSim
extends RefCounted

var zone: Zone = null
var registry: DataRegistry = null
var inventory: Inventory = null
var item_db: ItemDB = null
var rng: RandomNumberGenerator = null
var zone_id: String = "floor1"
var _tick_len: float = 0.0
var tick_length: float:
	get:
		return _tick_len
var tick_count: int = 0
var entities: Dictionary = {}
var _events: Array[Dictionary] = []
## Boss spawn ids already defeated. Callers may assign WorldState.bosses_defeated
## (shared by reference) so kills are recorded straight into the save state.
var bosses_defeated: Array[String] = []
## Last exit tile each entity stood on (entity id -> Vector2i); cleared when it leaves.
var _exit_tiles: Dictionary = {}

var _next_entity_id: int = 1
var _command_queue: Array[Commands.Command] = []
var _accumulator: float = 0.0

var _begin_handlers: Dictionary = {}
## Movement tuning, loaded from balance "movement" (defaults if absent).
var path_smoothing: bool = true
var arrival_epsilon: float = 0.001
var _update_handlers: Dictionary = {}


func _init(
	p_zone: Zone,
	p_registry: DataRegistry,
	p_inventory: Inventory = null,
	p_item_db: ItemDB = null,
	p_rng: RandomNumberGenerator = null,
	p_zone_id: String = ""
) -> void:
	zone = p_zone
	registry = p_registry
	inventory = p_inventory
	item_db = p_item_db
	rng = p_rng
	if not p_zone_id.is_empty():
		zone_id = p_zone_id
	var tick_hz: float = 30.0
	if registry != null:
		var hz_val: Variant = registry.get_balance("sim.tick_hz")
		if hz_val != null and float(hz_val) > 0.0:
			tick_hz = float(hz_val)
	_tick_len = 1.0 / tick_hz
	if registry != null:
		var smoothing_val: Variant = registry.get_balance("movement.path_smoothing")
		if typeof(smoothing_val) == TYPE_BOOL:
			path_smoothing = smoothing_val
		var eps_val: Variant = registry.get_balance("movement.arrival_epsilon_tiles")
		if (eps_val is float or eps_val is int) and float(eps_val) >= 0.0:
			arrival_epsilon = float(eps_val)

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


static func parse_tile_coord(tile: Variant) -> Variant:
	if tile is Vector2i:
		return tile
	elif tile is Vector2:
		return Vector2i(int(floor(tile.x)), int(floor(tile.y)))
	elif (tile is Array or tile is PackedInt32Array or tile is PackedFloat32Array) and tile.size() >= 2:
		if (tile[0] is int or tile[0] is float) and (tile[1] is int or tile[1] is float):
			return Vector2i(int(tile[0]), int(tile[1]))
	return null


func spawn(kind: String, tile: Variant, speed: float, hp: float = -1.0, stats: Stats = null) -> Entity:
	var parsed: Variant = parse_tile_coord(tile)
	if parsed == null:
		push_error("spawn: invalid tile coordinate %s" % str(tile))
		return null
	var target_tile: Vector2i = parsed

	if zone != null and not zone.is_walkable(target_tile):
		push_error("spawn: tile %s is not walkable" % str(target_tile))
		return null

	var entity_id := _next_entity_id
	_next_entity_id += 1
	var entity_pos := tile_center(target_tile)

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


func spawn_enemy(type_id: String, tile: Variant, hp: float = -1.0, stats: Stats = null) -> Entity:
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

	var final_stats := stats
	if final_stats == null:
		final_stats = _enemy_stats_for(enemy_cfg)

	var entity := spawn("enemy", tile, speed, hp, final_stats)
	if entity == null:
		return null
	entity.enemy_type_id = type_id
	entity.state = "idle"
	entity.spawn_pos = entity.pos
	if enemy_cfg.has("recovery_damage_mult"):
		entity.recovery_damage_mult = float(enemy_cfg["recovery_damage_mult"])
	return entity


## Builds enemy Stats from balance `enemy` overlaid per-field with the type's
## `max_hp`, `atk`, `defense` when present (numeric). Returns null if neither exists.
func _enemy_stats_for(enemy_cfg: Dictionary) -> Stats:
	var base: Dictionary = {}
	if registry != null:
		var balance_enemy: Variant = registry.get_balance("enemy")
		if balance_enemy is Dictionary:
			base = (balance_enemy as Dictionary).duplicate()
	var has_override := false
	for key: String in ["max_hp", "atk", "defense"]:
		if enemy_cfg.has(key) and (enemy_cfg[key] is int or enemy_cfg[key] is float):
			base[key] = float(enemy_cfg[key])
			has_override = true
	if base.is_empty() and not has_override:
		return null
	return Stats.from_dict(base)


func spawn_zone_enemies() -> Array[Entity]:
	var spawned: Array[Entity] = []
	if zone == null:
		return spawned
	for s: Dictionary in zone.spawns:
		var enemy_type: String = str(s.get("enemy", s.get("enemy_type_id", s.get("type", ""))))
		var tile_val: Variant = s.get("tile")
		if enemy_type.is_empty() or tile_val == null:
			continue
		var spawn_id: String = str(s.get("id", ""))
		var is_boss: bool = typeof(s.get("boss", false)) == TYPE_BOOL and bool(s.get("boss", false))
		if is_boss and not spawn_id.is_empty() and bosses_defeated.has(spawn_id):
			continue
		var entity := spawn_enemy(enemy_type, tile_val)
		if entity != null:
			entity.spawn_id = spawn_id
			entity.is_boss = is_boss
			spawned.append(entity)
	return spawned


func spawn_enemies() -> Array[Entity]:
	return spawn_zone_enemies()


## Shares the caller's defeated-boss list (e.g. WorldState.bosses_defeated) by reference.
func set_bosses_defeated(list: Array[String]) -> void:
	bosses_defeated = list


func is_boss_defeated(boss_id: String) -> bool:
	return bosses_defeated.has(boss_id)


## Returns the zone exit at tile `t` or an empty Dictionary.
func exit_at(t: Vector2i) -> Dictionary:
	if zone == null:
		return {}
	for e: Dictionary in zone.exits:
		var et: Variant = parse_tile_coord(e.get("tile"))
		if et != null and et == t:
			return e
	return {}


## True when the exit's required boss (if any) has been defeated.
func is_exit_unlocked(exit: Dictionary) -> bool:
	var req: String = str(exit.get("requires_boss", ""))
	return req.is_empty() or bosses_defeated.has(req)


## Checks whether the entity stands on an exit tile. Emits `floor_cleared` or
## `exit_locked` once per entry onto the tile and returns that event; returns {}
## when off any exit, still on the same exit, or the entity is missing/dead.
func check_exit(entity_id: int) -> Dictionary:
	var entity: Entity = get_entity(entity_id)
	if entity == null or entity.dead:
		_exit_tiles.erase(entity_id)
		return {}
	var t: Vector2i = entity.tile()
	var exit: Dictionary = exit_at(t)
	if exit.is_empty():
		_exit_tiles.erase(entity_id)
		return {}
	if _exit_tiles.get(entity_id) == t:
		return {}
	_exit_tiles[entity_id] = t
	var label: String = str(exit.get("label", ""))
	var ev: Dictionary
	if is_exit_unlocked(exit):
		ev = {
			"type": "floor_cleared",
			"tick": tick_count,
			"to_zone": str(exit.get("to_zone", "")),
			"label": label,
			"tile": t,
		}
	else:
		ev = {
			"type": "exit_locked",
			"tick": tick_count,
			"boss": str(exit.get("requires_boss", "")),
			"tile": t,
			"label": label,
		}
	_events.append(ev)
	return ev


## Returns the zone NPC with id `npc_id` or an empty Dictionary.
func get_npc(npc_id: String) -> Dictionary:
	if zone == null or npc_id.is_empty():
		return {}
	for n: Dictionary in zone.npcs:
		if str(n.get("id", "")) == npc_id:
			return n
	return {}


## Centre of an NPC's tile in entity (tile) units, or Vector2.INF if the tile is invalid.
static func npc_center(npc: Dictionary) -> Vector2:
	var t: Variant = parse_tile_coord(npc.get("tile"))
	if t == null:
		return Vector2.INF
	return tile_center(t)


## Interaction range in tiles from balance key `npc_interact_range` (-1 when missing).
func npc_interact_range() -> float:
	if registry == null:
		return -1.0
	var val: Variant = registry.get_balance("npc_interact_range")
	if val == null or not (val is float or val is int):
		return -1.0
	return float(val)


## True when the live player entity is within `npc_interact_range` tiles of the NPC
## tile centre. False for an unknown NPC, a missing/dead player or a missing range key.
func npc_in_range(player_id: int, npc_id: String) -> bool:
	var entity: Entity = get_entity(player_id)
	if entity == null or entity.dead:
		return false
	var npc := get_npc(npc_id)
	if npc.is_empty():
		return false
	var center := npc_center(npc)
	if not center.is_finite():
		return false
	var max_range := npc_interact_range()
	if max_range < 0.0:
		return false
	return entity.pos.distance_to(center) <= max_range + 1e-6


## The zone NPC whose tile centre is nearest `pos` (entity units) within `radius`, or {}.
## Ties go to the NPC listed first in the zone data.
func npc_at(pos: Vector2, radius: float) -> Dictionary:
	if zone == null or radius < 0.0 or not pos.is_finite():
		return {}
	var best: Dictionary = {}
	var best_dist: float = INF
	for n: Dictionary in zone.npcs:
		var center := npc_center(n)
		if not center.is_finite():
			continue
		var dist := center.distance_to(pos)
		if dist <= radius + 1e-6 and dist < best_dist - 1e-6:
			best = n
			best_dist = dist
	return best


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
	_check_player_exits()


func _check_player_exits() -> void:
	if zone == null or zone.exits.is_empty():
		return
	var ids: Array = entities.keys()
	ids.sort()
	for id: Variant in ids:
		var entity: Entity = entities[id]
		if entity.kind == "player":
			check_exit(entity.id)


func _apply_command(entity: Entity, cmd: Commands.Command) -> void:
	if entity.command is Commands.Dash:
		return

	var handler: Callable = _begin_handlers.get(cmd.get_script(), Callable())
	if not handler.is_valid():
		entity.command = null
		entity.path.clear()
		entity.path_index = 0
		return

	var accepted: bool = handler.call(entity, cmd)
	if accepted:
		if not entity.enemy_type_id.is_empty():
			entity.state = "idle"
			entity.target_id = 0


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
		# Active command takes priority over AI; when no command is active, EnemyAI drives the entity.
		if entity.command != null:
			var handler: Callable = _update_handlers.get(entity.command.get_script(), Callable())
			if handler.is_valid():
				handler.call(entity, entity.command)
			else:
				entity.command = null
				entity.path.clear()
				entity.path_index = 0
		elif entity.kind == "enemy" and not entity.enemy_type_id.is_empty():
			EnemyAI.update(self, entity)


## Paths the entity toward target_tile with A* (8-way, no corner cutting),
## then string-pulls the tile path so it walks straight segments. When
## goal_point is finite, walkable and inside the reached tile, it becomes the
## exact final waypoint; otherwise the last tile's centre is.
func path_entity_to_tile(entity: Entity, target_tile: Vector2i, goal_point: Vector2 = Vector2.INF) -> void:
	entity.path_goal = Vector2.INF
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

	var goal := Vector2.INF
	if goal_point.is_finite() and _tile_of(goal_point) == path[path.size() - 1] and zone.is_walkable(_tile_of(goal_point)):
		goal = goal_point
	entity.path_goal = goal

	if path.size() == 1:
		entity.path = path
		entity.path_index = 0
		var dest := waypoint_position(path, 0, goal)
		if entity.pos.is_equal_approx(dest):
			entity.pos = dest
		return

	var avoid_safe: bool = not entity.enemy_type_id.is_empty()
	# Skip the start tile's centre when the entity can head straight on.
	var start_index: int = 1 if _segment_clear(zone, entity.pos, waypoint_position(path, 1, goal), avoid_safe) else 0
	if path_smoothing:
		var anchor: Vector2 = entity.pos if start_index == 1 else tile_center(path[0])
		path = smooth_path(zone, path, anchor, goal, avoid_safe)
	entity.path = path
	entity.path_index = start_index


## Waypoint i of a tile path: the tile centre, or goal for the last tile when
## goal is finite.
static func waypoint_position(tiles: Array[Vector2i], i: int, goal: Vector2 = Vector2.INF) -> Vector2:
	if i == tiles.size() - 1 and goal.is_finite() and _tile_of(goal) == tiles[i]:
		return goal
	return tile_center(tiles[i])


## String pulling: from anchor (standing in tiles[0]), keeps only the tiles
## whose waypoints cannot be skipped by a straight walkable segment. The first
## and last tiles are always kept. With avoid_safe, shortcuts never enter a
## safe tile (so safe tiles on the raw path stay as waypoints).
static func smooth_path(
	p_zone: Zone,
	tiles: Array[Vector2i],
	anchor: Vector2,
	goal: Vector2 = Vector2.INF,
	avoid_safe: bool = false
) -> Array[Vector2i]:
	var n: int = tiles.size()
	if n <= 2 or p_zone == null:
		return tiles.duplicate()
	var out: Array[Vector2i] = [tiles[0]]
	var i: int = 0
	var from_pos: Vector2 = anchor
	while i < n - 1:
		var j: int = i + 1
		while j + 1 < n and _segment_clear(p_zone, from_pos, waypoint_position(tiles, j + 1, goal), avoid_safe):
			j += 1
		out.append(tiles[j])
		from_pos = waypoint_position(tiles, j, goal)
		i = j
	return out


static func _segment_clear(p_zone: Zone, p0: Vector2, p1: Vector2, avoid_safe: bool) -> bool:
	if not DashRules.is_segment_walkable(p0, p1, p_zone):
		return false
	if avoid_safe and p_zone.segment_crosses_safe(p0, p1, _tile_of(p0)):
		return false
	return true


static func _tile_of(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x)), int(floor(p.y)))


func step_entity_along_path(entity: Entity, max_dist: float) -> void:
	var remaining_dist: float = max_dist
	while remaining_dist > 0.0 and (entity.command != null or not entity.enemy_type_id.is_empty()):
		if entity.path_index >= entity.path.size():
			break

		var target_pos: Vector2 = waypoint_position(entity.path, entity.path_index, entity.path_goal)
		var to_target: Vector2 = target_pos - entity.pos
		var dist: float = to_target.length()

		if zone != null and not DashRules.is_segment_walkable(entity.pos, target_pos, zone):
			entity.command = null
			entity.path.clear()
			entity.path_index = 0
			break

		if dist > 0.0:
			entity.facing_dir = to_target / dist

		if dist <= remaining_dist + arrival_epsilon:
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


func _begin_move_to(entity: Entity, cmd: Commands.MoveTo) -> bool:
	path_entity_to_tile(entity, cmd.target, cmd.point)
	if entity.path.is_empty():
		entity.command = null
		return false
	if entity.path.size() == 1 and entity.pos.is_equal_approx(waypoint_position(entity.path, 0, entity.path_goal)):
		entity.command = null
		return false
	entity.command = cmd
	return true


func _update_move_to(entity: Entity, _cmd: Commands.MoveTo) -> void:
	if entity.path.is_empty():
		entity.command = null
		return

	step_entity_along_path(entity, entity.speed * _tick_len)
	if entity.path_index >= entity.path.size():
		entity.command = null


func _begin_attack_target(entity: Entity, cmd: Commands.AttackTarget) -> bool:
	if cmd.target_id == entity.id:
		entity.command = null
		entity.path.clear()
		entity.path_index = 0
		return false

	var target: Entity = get_entity(cmd.target_id)
	if target == null or target.dead:
		entity.command = null
		entity.path.clear()
		entity.path_index = 0
		return false

	var attack_range: float = _get_attack_range(entity)
	var attack_interval: float = _get_attack_interval(entity)
	if attack_range <= 0.0 or attack_interval <= 0.0:
		entity.command = null
		entity.path.clear()
		entity.path_index = 0
		return false

	entity.command = cmd
	var dist: float = entity.pos.distance_to(target.pos)
	if dist > attack_range + 1e-9:
		cmd.last_target_tile = target.tile()
		path_entity_to_tile(entity, cmd.last_target_tile)
	else:
		entity.path.clear()
		entity.path_index = 0
		cmd.last_target_tile = Vector2i(-1, -1)
	return true


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
			path_entity_to_tile(entity, target_tile)

		step_entity_along_path(entity, entity.speed * _tick_len)
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


func _begin_cast_skill(entity: Entity, cmd: Commands.CastSkill) -> bool:
	if not entity.skills.has(cmd.slot):
		_events.append({
			"type": "cast_failed",
			"tick": tick_count,
			"source": entity.id,
			"slot": cmd.slot,
			"reason": "unknown_slot",
		})
		return false

	var skill_id: String = entity.skills.get(cmd.slot, "")
	if skill_id.is_empty() or registry == null or not registry.has_entry("skills", skill_id):
		_events.append({
			"type": "cast_failed",
			"tick": tick_count,
			"source": entity.id,
			"slot": cmd.slot,
			"reason": "unknown_skill",
		})
		return false

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
		return false

	var to_aim := cmd.aim - entity.pos
	if to_aim.is_zero_approx():
		_events.append({
			"type": "cast_failed",
			"tick": tick_count,
			"source": entity.id,
			"slot": cmd.slot,
			"reason": "zero_direction",
		})
		return false

	var ready_tick: float = entity.skill_ready_ticks.get(cmd.slot, 0.0)
	if float(tick_count) < ready_tick - 1e-9:
		_events.append({
			"type": "cast_failed",
			"tick": tick_count,
			"source": entity.id,
			"slot": cmd.slot,
			"reason": "cooldown",
		})
		return false

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
	return true


func _update_cast_skill(entity: Entity, cmd: Commands.CastSkill) -> void:
	if tick_count >= cmd.resolve_tick:
		var skill_id: String = entity.skills.get(cmd.slot, "")
		var skill: Dictionary = registry.get_entry("skills", skill_id)
		_resolve_cast_skill(entity, cmd, skill)
		entity.command = null


func _begin_dash(entity: Entity, cmd: Commands.Dash) -> bool:
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
		return false

	if cmd.aim.is_zero_approx() or not cmd.aim.is_finite():
		_events.append({
			"type": "dash_failed",
			"tick": tick_count,
			"source": entity.id,
			"reason": "invalid_aim",
		})
		return false

	cmd.aim = cmd.aim.normalized()

	if float(tick_count) < entity.dash_ready_tick - 1e-9:
		_events.append({
			"type": "dash_failed",
			"tick": tick_count,
			"source": entity.id,
			"reason": "cooldown",
		})
		return false

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
	return true


func _update_dash(entity: Entity, cmd: Commands.Dash) -> void:
	if entity.dead:
		entity.command = null
		return

	var to_target: Vector2 = cmd.to - entity.pos
	var dist_to_target: float = to_target.length()

	var speed: float = 0.0
	if cmd.duration_s > 1e-9:
		speed = cmd.distance / cmd.duration_s
	var max_dist_this_tick: float = speed * _tick_len

	if dist_to_target <= max_dist_this_tick + 0.001:
		if zone != null and not DashRules.is_segment_walkable(entity.pos, cmd.to, zone):
			entity.command = null
			return
		entity.pos = cmd.to
		entity.command = null
		return

	var dir: Vector2 = to_target / dist_to_target
	var remaining := max_dist_this_tick
	var max_step := 0.5
	while remaining > 1e-9:
		var step := minf(max_step, remaining)
		var next_pos := entity.pos + dir * step
		if zone != null and not DashRules.is_segment_walkable(entity.pos, next_pos, zone):
			entity.command = null
			return
		entity.pos = next_pos
		remaining -= step



func get_entities_in_shape(
	shape_def: Dictionary,
	origin: Vector2,
	dir: Vector2,
	ignore_id: int = -1,
	target_kind: String = ""
) -> Array[Entity]:
	var result: Array[Entity] = []
	var sorted_ids: Array = entities.keys()
	sorted_ids.sort()
	for other_id: Variant in sorted_ids:
		var other: Entity = entities[other_id]
		if other.id == ignore_id or other.dead:
			continue
		if not target_kind.is_empty() and other.kind != target_kind:
			continue
		if SkillSystem.in_shape(shape_def, origin, dir, other.pos):
			result.append(other)
	return result


func apply_attack_shape_damage(
	attacker: Entity,
	shape_def: Dictionary,
	origin: Vector2,
	dir: Vector2,
	mult: float = 1.0,
	target_kind: String = ""
) -> Array[Entity]:
	var hit_targets := get_entities_in_shape(shape_def, origin, dir, attacker.id, target_kind)
	var attacker_stats := effective_stats(attacker)
	for target: Entity in hit_targets:
		if target.dead:
			continue
		var target_stats := effective_stats(target)
		var base_dmg: float = Combat.compute_damage(attacker_stats, target_stats, registry)
		apply_damage(attacker.id, target, mult * base_dmg)
	return hit_targets


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

	var aim_offset := cmd.aim - entity.pos
	var hit_entities := get_entities_in_shape(skill, entity.pos, aim_offset, entity.id)

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

	if dead_entity.is_boss and not dead_entity.spawn_id.is_empty() and not bosses_defeated.has(dead_entity.spawn_id):
		bosses_defeated.append(dead_entity.spawn_id)
		_events.append({
			"type": "boss_defeated",
			"tick": tick_count,
			"boss": dead_entity.spawn_id,
			"entity": dead_entity.id,
			"enemy_type": dead_entity.enemy_type_id,
		})

	# Roll loot for enemy death
	if dead_entity.kind == "enemy" and inventory != null and rng != null and item_db != null:
		if not dead_entity.enemy_type_id.is_empty() and item_db.has_loot_table(dead_entity.enemy_type_id):
			var tile := Vector2i(int(floor(dead_entity.pos.x)), int(floor(dead_entity.pos.y)))
			var eff_zone := zone_id if not zone_id.is_empty() else "floor1"
			var drops: Array[int] = Loot.roll(dead_entity.enemy_type_id, eff_zone, inventory, rng, item_db)
			if not drops.is_empty():
				_events.append({
					"type": "loot_drop",
					"tick": tick_count,
					"entity": dead_entity.id,
					"items": drops,
					"tile": tile,
				})
