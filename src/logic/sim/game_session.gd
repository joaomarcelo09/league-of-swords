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
## Loads a zone for a door transition: Callable(zone stem) -> Zone. The view
## wires it to the zone files; tests inject in-memory zones.
var zone_loader: Callable = Callable()
## Chunked floor kept while the session visits a door's zone, so leaving it can
## return to the same world. Null on the classic single-zone path.
var chunked_world: ChunkedWorld = null
## Zone id the chunked floor runs with, restored when leaving a door's zone.
var chunked_zone_id: String = "floor1"
## Door the session took to leave the chunked floor (empty until a door is used).
var active_door: Dictionary = {}
## Last zone tile checked for the active door's return link.
var _door_tile: Vector2i = Vector2i(-1, -1)
## Travel resolved by the last step (gate or zone switch); read with take_travel().
var last_travel: Dictionary = {}


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
	var chunked_zone := zone as ChunkedZone
	if chunked_zone != null:
		chunked_world = chunked_zone.world
		chunked_zone_id = zone_id


func spawn_player(pos: Variant = null, speed: float = -1.0) -> Entity:
	if world == null:
		return null
	var spawn_pos: Variant = pos
	if spawn_pos == null and zone != null:
		spawn_pos = zone.entry

	var spawn_speed := speed
	if spawn_speed <= 0.0:
		spawn_speed = default_player_speed()

	player = world.spawn("player", spawn_pos, spawn_speed)
	return player


## Player move speed from balance, with the same fallback spawn_player always had.
func default_player_speed() -> float:
	if registry != null:
		var speed_val: Variant = registry.get_balance("player.move_speed_tiles_per_s")
		if speed_val != null and float(speed_val) > 0.0:
			return float(speed_val)
	return 4.0


func spawn_zone_enemies() -> Array[Entity]:
	if world != null:
		return world.spawn_zone_enemies()
	return []


func spawn_enemies() -> Array[Entity]:
	return spawn_zone_enemies()


func step(dt: float) -> void:
	if world == null:
		return
	world.step(dt)
	if player != null and not player.dead:
		var travel := check_world_travel(player.id)
		if not travel.is_empty() and (bool(travel.get("ok", false)) or str(travel.get("reason", "")) == "locked"):
			last_travel = travel


## Returns and clears the travel resolved by the last step (empty when none).
func take_travel() -> Dictionary:
	var result := last_travel
	last_travel = {}
	return result


## True when the session is running on the chunked floor (not inside a door's zone).
func in_chunked_world() -> bool:
	return world != null and world.chunked_world != null


## Resolves a gate or door under the player, and handles leaving a door's zone
## through its return link. Gates are applied by WorldSim (teleport + streaming);
## a door to a zone switches this session to that zone, and its return link
## switches back to the chunked floor. Returns the resolution result
## ({"ok": false, "reason": "none"} when the player is not on a transition).
func check_world_travel(entity_id: int) -> Dictionary:
	if world == null:
		return {"ok": false, "reason": "none"}
	if world.chunked_world != null:
		var result := world.check_world_transition(entity_id)
		var is_zone_door := bool(result.get("ok", false)) and str(result.get("kind", "")) == "door" and not str(result.get("to_zone", "")).is_empty()
		if is_zone_door:
			return _enter_door_zone(result)
		return result
	return _check_door_return()


## Switches the session into the zone a door leads to, remembering its return link.
func _enter_door_zone(result: Dictionary) -> Dictionary:
	if not zone_loader.is_valid():
		return {"ok": false, "reason": "no_zone_loader", "kind": "door", "zone": str(result.get("to_zone", ""))}
	var stem := str(result.get("to_zone", ""))
	var loaded: Variant = zone_loader.call(stem)
	if not (loaded is Zone) or not (loaded as Zone).is_valid():
		return {"ok": false, "reason": "zone_failed", "kind": "door", "zone": stem}
	var new_zone: Zone = loaded
	var spawn_tile: Vector2i = result.get("to_tile", Vector2i(-1, -1))
	if not new_zone.is_walkable(spawn_tile):
		return {"ok": false, "reason": "invalid_spawn", "kind": "door", "zone": stem}

	var return_tile: Vector2i = result.get("return_tile", Vector2i(-1, -1))
	var return_chunk := str(result.get("return_chunk", ""))
	var return_to_tile: Vector2i = result.get("return_to_tile", Vector2i(-1, -1))
	var has_return := not return_chunk.is_empty() and return_tile.x >= 0 and return_tile.y >= 0 and return_to_tile.x >= 0 and return_to_tile.y >= 0
	active_door = {
		"id": str(result.get("id", "")),
		"zone": stem,
		"tile": return_tile if has_return else Vector2i(-1, -1),
		"chunk": return_chunk,
		"to_tile": return_to_tile,
	}
	_door_tile = spawn_tile
	_spawn_in_zone(new_zone, spawn_tile, stem)
	world.spawn_zone_enemies()
	result["zone_changed"] = true
	result["mode"] = "zone"
	result["player"] = player
	return result


## Leaves the active door's zone when the player steps onto its return tile.
func _check_door_return() -> Dictionary:
	if active_door.is_empty() or player == null:
		return {"ok": false, "reason": "none"}
	var tile := player.tile()
	var was_tile := _door_tile
	_door_tile = tile
	if tile == was_tile:
		return {"ok": false, "reason": "none"}
	var trigger: Vector2i = active_door.get("tile", Vector2i(-1, -1))
	if trigger.x < 0 or trigger.y < 0 or tile != trigger:
		return {"ok": false, "reason": "none"}
	return _leave_door_zone()


## Switches back to the chunked floor at the door's return link.
func _leave_door_zone() -> Dictionary:
	if chunked_world == null:
		return {"ok": false, "reason": "no_chunked_world"}
	var return_chunk := str(active_door.get("chunk", ""))
	var return_to_tile: Vector2i = active_door.get("to_tile", Vector2i(-1, -1))
	if not chunked_world.map.has_chunk(return_chunk):
		return {"ok": false, "reason": "unknown_chunk", "chunk": return_chunk}
	var world_tile := chunked_world.map.chunk_to_world(return_chunk, return_to_tile)
	var changes := chunked_world.update(world_tile)
	var chunked_zone := ChunkedZone.new(chunked_world)
	if not chunked_zone.is_valid() or not chunked_zone.is_walkable(world_tile):
		return {"ok": false, "reason": "invalid_return", "chunk": return_chunk}

	var door_id := str(active_door.get("id", ""))
	active_door = {}
	_spawn_in_zone(chunked_zone, world_tile, chunked_zone_id)
	world.spawn_zone_enemies()
	return {
		"ok": true,
		"kind": "door",
		"id": door_id,
		"zone_changed": true,
		"mode": "chunks",
		"to_chunk": return_chunk,
		"to_world": world_tile,
		"loaded": changes.get("loaded", []),
		"unloaded": changes.get("unloaded", []),
		"player": player,
	}


## Replaces the simulation world with one in new_zone, carrying the player's
## stats, HP and skills across (transient per-world state such as cooldowns and
## buffs restarts with the new world).
func _spawn_in_zone(new_zone: Zone, spawn_tile: Vector2i, new_zone_id: String) -> Entity:
	var old_world := world
	var old_player := player
	var speed := 0.0
	var hp := -1.0
	var stats: Stats = null
	var skills: Dictionary = {}
	if old_player != null:
		speed = old_player.speed
		hp = old_player.hp
		skills = old_player.skills.duplicate(true)
		if old_player.stats != null:
			stats = old_player.stats.duplicate()
	if speed <= 0.0:
		speed = default_player_speed()
	var bosses: Array[String] = []
	if old_world != null:
		bosses = old_world.bosses_defeated

	zone = new_zone
	zone_id = new_zone_id
	world = WorldSim.new(new_zone, registry, inventory, item_db, rng, new_zone_id)
	world.set_bosses_defeated(bosses)
	player = world.spawn("player", spawn_tile, speed, hp, stats)
	if player != null:
		player.skills = skills
	return player


## Streams the chunked floor around the player's world tile; no-op for classic zones.
func update_chunks(player_world_tile: Vector2i) -> Dictionary:
	if world != null:
		return world.update_chunks(player_world_tile)
	return {"loaded": [], "unloaded": [], "player_chunk": "", "changed": false}


func drain_events() -> Array[Dictionary]:
	if world != null:
		return world.drain_events()
	return []
