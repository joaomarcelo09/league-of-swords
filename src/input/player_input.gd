class_name PlayerInput
extends Node

const DEFAULT_MOVE_REPEAT_S: float = 0.15
const DEFAULT_ENEMY_PICK_RADIUS: float = 0.5

var player_id: int = 0
var world: WorldSim = null
var zone_view: ZoneView = null
var registry: DataRegistry = null

var move_repeat_s: float = DEFAULT_MOVE_REPEAT_S
var enemy_pick_radius: float = DEFAULT_ENEMY_PICK_RADIUS

var is_holding_right: bool = false
var hold_timer: float = 0.0


func _init(
	p_player_id: int = 0,
	p_world: WorldSim = null,
	p_zone_view: ZoneView = null,
	p_registry: DataRegistry = null
) -> void:
	if p_player_id != 0 or p_world != null or p_zone_view != null or p_registry != null:
		setup(p_player_id, p_world, p_zone_view, p_registry)


func setup(
	p_player_id: int,
	p_world: WorldSim,
	p_zone_view: ZoneView,
	p_registry: DataRegistry = null
) -> void:
	player_id = p_player_id
	world = p_world
	zone_view = p_zone_view
	registry = p_registry

	if registry != null:
		var repeat_val: Variant = registry.get_balance("input.move_repeat_s")
		if repeat_val != null and float(repeat_val) > 0.0:
			move_repeat_s = float(repeat_val)
		else:
			push_warning("PlayerInput: missing balance key 'input.move_repeat_s'")

		var radius_val: Variant = registry.get_balance("input.enemy_pick_radius")
		if radius_val != null and float(radius_val) >= 0.0:
			enemy_pick_radius = float(radius_val)
		else:
			push_warning("PlayerInput: missing balance key 'input.enemy_pick_radius'")


func get_mouse_entity_position() -> Vector2:
	if zone_view != null and zone_view.is_inside_tree():
		var mouse_local: Vector2 = zone_view.get_local_mouse_position()
		return zone_view.world_to_entity(mouse_local)
	return Vector2.ZERO


func get_player_position() -> Vector2:
	var p: Entity = _get_player_entity()
	if p != null:
		return p.pos
	return Vector2.ZERO


func _get_player_entity() -> Entity:
	if world != null:
		return world.get_entity(player_id)
	return null


func _unhandled_input(event: InputEvent) -> void:
	handle_input(event)


func _process(delta: float) -> void:
	handle_process(delta)


func handle_input(event: InputEvent, override_mouse_pos: Vector2 = Vector2.INF) -> Commands.Command:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
		is_holding_right = false
		hold_timer = 0.0
		return null

	var player := _get_player_entity()
	if player == null or player.dead:
		return null

	var mouse_pos := override_mouse_pos if override_mouse_pos.is_finite() else get_mouse_entity_position()
	var player_pos := player.pos

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			is_holding_right = true
			hold_timer = 0.0
			var cmd := command_for_right_click(world, player_id, mouse_pos, enemy_pick_radius)
			if cmd != null and world != null:
				world.submit(cmd)
			return cmd

	if event.is_echo():
		return null

	if event.is_action_pressed("skill_q"):
		var cmd := command_for_skill(player_id, "Q", mouse_pos, player_pos)
		if cmd != null and world != null:
			world.submit(cmd)
		return cmd
	elif event.is_action_pressed("skill_w"):
		var cmd := command_for_skill(player_id, "W", mouse_pos, player_pos)
		if cmd != null and world != null:
			world.submit(cmd)
		return cmd
	elif event.is_action_pressed("skill_r"):
		var cmd := command_for_skill(player_id, "R", mouse_pos, player_pos)
		if cmd != null and world != null:
			world.submit(cmd)
		return cmd
	elif event.is_action_pressed("dash"):
		var cmd := command_for_dash(player_id, player_pos, mouse_pos)
		if cmd != null and world != null:
			world.submit(cmd)
		return cmd

	return null


func handle_process(delta: float, override_mouse_pos: Vector2 = Vector2.INF) -> Commands.Command:
	if not is_holding_right:
		return null

	var player := _get_player_entity()
	if player == null or player.dead:
		return null

	if player.command is Commands.CastSkill or player.command is Commands.Dash:
		return null

	hold_timer += delta
	if hold_timer >= move_repeat_s:
		if move_repeat_s > 0.0:
			hold_timer -= move_repeat_s
		else:
			hold_timer = 0.0

		var mouse_pos := override_mouse_pos if override_mouse_pos.is_finite() else get_mouse_entity_position()
		var cmd := command_for_right_click(world, player_id, mouse_pos, enemy_pick_radius)
		if cmd != null and world != null:
			world.submit(cmd)
		return cmd

	return null


# --- Pure helper functions ---

static func pick_enemy_at(p_world: WorldSim, entity_pos: Vector2, radius: float) -> Entity:
	if p_world == null or radius < 0.0:
		return null

	var best_enemy: Entity = null
	var best_dist: float = INF
	var sorted_ids: Array = p_world.entities.keys()
	sorted_ids.sort()
	for e_id: Variant in sorted_ids:
		var e: Entity = p_world.entities[e_id]
		if e == null or e.dead or e.kind != "enemy":
			continue
		var dist: float = e.pos.distance_to(entity_pos)
		if dist <= radius + 1e-6:
			if dist < best_dist - 1e-6:
				best_dist = dist
				best_enemy = e
			elif absf(dist - best_dist) <= 1e-6:
				if best_enemy == null or e.id < best_enemy.id:
					best_dist = dist
					best_enemy = e

	return best_enemy


static func aim_from(player_pos: Vector2, mouse_entity_pos: Vector2, fallback: Vector2 = Vector2.ZERO) -> Vector2:
	var diff: Vector2 = mouse_entity_pos - player_pos
	if diff.is_zero_approx():
		if not fallback.is_zero_approx() and fallback.is_finite():
			return fallback.normalized()
		return Vector2.ZERO
	return diff.normalized()


static func command_for_right_click(
	p_world: WorldSim,
	p_player_id: int,
	target: Variant,
	pick_radius: float = 0.5
) -> Commands.Command:
	var mouse_pos := Vector2.ZERO
	var target_tile := Vector2i.ZERO
	if target is Vector2i:
		target_tile = target
		mouse_pos = Vector2(float(target.x) + 0.5, float(target.y) + 0.5)
	elif target is Vector2:
		if not (target as Vector2).is_finite():
			return null
		mouse_pos = target
		target_tile = Vector2i(int(floor(target.x)), int(floor(target.y)))
	else:
		return null

	var enemy := pick_enemy_at(p_world, mouse_pos, pick_radius)
	if enemy != null:
		return Commands.attack_target(p_player_id, enemy.id)

	if p_world != null and p_world.zone != null:
		if not p_world.zone.is_walkable(target_tile):
			return null

	return Commands.move_to(p_player_id, target_tile)


static func command_for_skill(
	p_player_id: int,
	slot: String,
	mouse_entity_pos: Vector2,
	player_pos: Vector2 = Vector2.INF
) -> Commands.CastSkill:
	if not mouse_entity_pos.is_finite():
		return null
	if player_pos.is_finite() and mouse_entity_pos.is_equal_approx(player_pos):
		return null
	return Commands.cast_skill(p_player_id, slot, mouse_entity_pos)


static func command_for_dash(
	p_player_id: int,
	player_pos: Vector2,
	mouse_entity_pos: Vector2,
	fallback: Vector2 = Vector2.ZERO
) -> Commands.Dash:
	if not player_pos.is_finite() or not mouse_entity_pos.is_finite():
		return null
	var aim := aim_from(player_pos, mouse_entity_pos, fallback)
	if aim.is_zero_approx():
		return null
	return Commands.dash(p_player_id, aim)


static func command_for_action(
	action: String,
	p_player_id: int,
	player_pos: Vector2,
	mouse_entity_pos: Vector2
) -> Commands.Command:
	match action:
		"skill_q":
			return command_for_skill(p_player_id, "Q", mouse_entity_pos, player_pos)
		"skill_w":
			return command_for_skill(p_player_id, "W", mouse_entity_pos, player_pos)
		"skill_r":
			return command_for_skill(p_player_id, "R", mouse_entity_pos, player_pos)
		"dash":
			return command_for_dash(p_player_id, player_pos, mouse_entity_pos)
		_:
			return null


static func pickup_loot(p_inventory: Inventory, uid: int, p_player_id: int) -> bool:
	if p_inventory == null or p_player_id <= 0:
		return false
	return p_inventory.pickup(uid, "character:%d" % p_player_id)


static func equip_item(p_inventory: Inventory, p_player_id: int, uid: int) -> bool:
	if p_inventory == null or p_player_id <= 0:
		return false
	return p_inventory.equip("character:%d" % p_player_id, uid)


static func unequip_item(p_inventory: Inventory, p_player_id: int, slot: String) -> bool:
	if p_inventory == null or p_player_id <= 0:
		return false
	return p_inventory.unequip("character:%d" % p_player_id, slot)


static func use_item(p_inventory: Inventory, uid: int, player_entity: Entity) -> bool:
	if p_inventory == null or player_entity == null:
		return false
	return p_inventory.use(uid, player_entity, "character:%d" % player_entity.id)


static func activate_inventory_item(
	p_inventory: Inventory,
	p_item_db: ItemDB,
	uid: int,
	player_entity: Entity
) -> bool:
	if p_inventory == null or p_item_db == null or player_entity == null:
		return false
	var def_id := p_inventory.def_id_of(uid)
	var item := p_item_db.get_item(def_id)
	if item.is_empty():
		return false
	var item_type := str(item.get("type", ""))
	var char_owner := "character:%d" % player_entity.id
	if item_type in ["weapon", "armor"]:
		var current_equipped := p_inventory.get_equipped(char_owner, item_type)
		if current_equipped == uid:
			return p_inventory.unequip(char_owner, item_type)
		return p_inventory.equip(char_owner, uid)
	elif item_type == "consumable":
		return p_inventory.use(uid, player_entity, char_owner)
	return false
