class_name GameSession
extends RefCounted

var zone: Zone = null
var registry: DataRegistry = null
var inventory: Inventory = null
var item_db: ItemDB = null
var rng: RandomNumberGenerator = null
var zone_id: String = "floor1"
var world: WorldSim = null
var player: Entity = null


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

	if p_item_db != null:
		item_db = p_item_db
	elif registry != null:
		item_db = ItemDB.new(registry)

	if p_inventory != null:
		inventory = p_inventory
	elif item_db != null:
		inventory = Inventory.new(item_db)

	if p_rng != null:
		rng = p_rng
	else:
		rng = RandomNumberGenerator.new()
		var seed_val: Variant = null
		if registry != null:
			seed_val = registry.get_balance("sim.seed")
			if seed_val == null:
				seed_val = registry.get_balance("loot.seed")
		if seed_val != null and (seed_val is int or seed_val is float):
			rng.seed = int(seed_val)
		else:
			rng.randomize()

	if not p_zone_id.is_empty():
		zone_id = p_zone_id
	else:
		zone_id = "floor1"

	world = WorldSim.new(zone, registry, inventory, item_db, rng, zone_id)


func spawn_player(pos: Variant = null, speed: float = -1.0) -> Entity:
	if world == null:
		return null
	var spawn_pos: Variant = pos
	if spawn_pos == null and zone != null:
		spawn_pos = zone.entry

	var spawn_speed := speed
	if spawn_speed <= 0.0 and registry != null:
		var speed_val: Variant = registry.get_balance("player.move_speed_tiles_per_s")
		if speed_val != null and float(speed_val) > 0.0:
			spawn_speed = float(speed_val)
	if spawn_speed <= 0.0:
		spawn_speed = 4.0

	player = world.spawn("player", spawn_pos, spawn_speed)
	return player


func spawn_zone_enemies() -> Array[Entity]:
	if world != null:
		return world.spawn_zone_enemies()
	return []


func spawn_enemies() -> Array[Entity]:
	return spawn_zone_enemies()


func step(dt: float) -> void:
	if world != null:
		world.step(dt)


func drain_events() -> Array[Dictionary]:
	if world != null:
		return world.drain_events()
	return []
