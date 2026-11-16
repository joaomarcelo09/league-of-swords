class_name ChunkLoader
extends RefCounted

# Pure-logic streaming of zone chunks around the player.
# The zone loader is injected as a Callable taking a chunk id and returning a
# Zone (or null). Tests use in-memory zones; the game can pass a Callable that
# loads zone files. No Node/SceneTree/Input/rendering dependencies.

var errors: Array[String] = []

var _map: WorldMap = null
var _zone_loader: Callable = Callable()
var _loaded: Dictionary = {}  # chunk id (String) -> Zone


func _init(world_map: WorldMap, zone_loader: Callable = Callable()) -> void:
	_map = world_map
	_zone_loader = zone_loader


# Loads every chunk within the map's load_radius of the player's chunk and
# unloads the chunks that left that radius. Returns only what changed:
# {"loaded": Array[String], "unloaded": Array[String]} (both sorted).
# Chunks already loaded are never reloaded.
func update(player_world_tile: Vector2i) -> Dictionary:
	var loaded_now: Array[String] = []
	var unloaded_now: Array[String] = []
	var changes := {
		"loaded": loaded_now,
		"unloaded": unloaded_now,
	}

	if _map == null:
		errors.append("ChunkLoader: no world map configured")
		return changes
	if not _map.is_valid():
		errors.append("ChunkLoader: world map is invalid: %s" % str(_map.errors))
		return changes

	var player_cell: Vector2i = _map.world_to_chunk(player_world_tile).get("chunk_cell", Vector2i.ZERO)
	var desired_ids: Array[String] = _map.chunks_near(player_cell, _map.load_radius)
	var desired: Dictionary = {}
	for chunk_id: String in desired_ids:
		desired[chunk_id] = true

	for loaded_key: Variant in _loaded.keys():
		var loaded_id := str(loaded_key)
		if not desired.has(loaded_id):
			_loaded.erase(loaded_id)
			unloaded_now.append(loaded_id)

	for chunk_id: String in desired_ids:
		if _loaded.has(chunk_id):
			continue
		var zone := _load_zone(chunk_id)
		if zone == null:
			continue
		_loaded[chunk_id] = zone
		loaded_now.append(chunk_id)

	loaded_now.sort()
	unloaded_now.sort()
	return changes


func loaded_ids() -> Array[String]:
	var result: Array[String] = []
	for chunk_key: Variant in _loaded.keys():
		result.append(str(chunk_key))
	result.sort()
	return result


func is_loaded(chunk_id: String) -> bool:
	return _loaded.has(chunk_id)


func zone_for(chunk_id: String) -> Zone:
	var zone_value: Variant = _loaded.get(chunk_id)
	if zone_value is Zone:
		return zone_value
	return null


func _load_zone(chunk_id: String) -> Zone:
	if not _zone_loader.is_valid():
		errors.append("chunk '%s': no zone loader configured" % chunk_id)
		return null

	var result: Variant = _zone_loader.call(chunk_id)
	if result == null:
		errors.append("chunk '%s' (zone '%s'): zone loader returned null" % [chunk_id, _map.zone_stem(chunk_id)])
		return null
	if not (result is Zone):
		errors.append("chunk '%s': zone loader returned %s, expected Zone" % [chunk_id, type_string(typeof(result))])
		return null

	var zone: Zone = result
	if not zone.is_valid():
		errors.append("chunk '%s' (zone '%s'): zone failed to load: %s" % [chunk_id, _map.zone_stem(chunk_id), str(zone.errors)])
		return null
	return zone
