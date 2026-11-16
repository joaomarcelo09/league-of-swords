class_name ChunkedZone
extends Zone

# World-space Zone facade over the loaded chunks of a ChunkedWorld. The sim
# (WorldSim, pathing, enemy AI) keeps working with a single Zone, while every
# tile it sees is a world tile: chunk offsets are applied and walkability is
# looked up in the chunk that covers the tile. Tiles of unloaded chunks are
# never walkable, so streaming naturally bounds movement.
# Spawns/NPCs/exits are aggregated from the loaded chunks in world tiles.
# No Node/SceneTree/Input/rendering dependencies.

var world: ChunkedWorld = null

var _chunk_astar: AStarGrid2D = null


func _init(p_world: ChunkedWorld = null) -> void:
	world = p_world
	refresh()


## Rebuilds the world-space view after chunks were loaded or unloaded.
func refresh() -> void:
	errors.clear()
	spawns.clear()
	exits.clear()
	npcs.clear()
	_chunk_astar = null
	width = 0
	height = 0
	entry = Vector2i(-1, -1)

	if world == null:
		errors.append("ChunkedZone: no chunked world configured")
		return
	if world.map == null or not world.map.is_valid():
		errors.append_array(world.errors)
		return

	width = world.world_width()
	height = world.world_height()
	entry = world.start_entry()

	for chunk_id: String in world.loaded_ids():
		var chunk_zone := world.zone_for(chunk_id)
		if chunk_zone == null:
			continue
		var offset := world.chunk_offset(chunk_id)
		_append_entries(chunk_zone.spawns, offset, spawns)
		_append_entries(chunk_zone.exits, offset, exits)
		_append_entries(chunk_zone.npcs, offset, npcs)

	_build_astar()


func is_walkable(t: Vector2i) -> bool:
	var chunk_zone := _zone_at(t)
	return chunk_zone != null and chunk_zone.is_walkable(_local_tile(t))


func tile_type(t: Vector2i) -> String:
	var chunk_zone := _zone_at(t)
	return chunk_zone.tile_type(_local_tile(t)) if chunk_zone != null else ""


func decor_at(t: Vector2i) -> String:
	var chunk_zone := _zone_at(t)
	return chunk_zone.decor_at(_local_tile(t)) if chunk_zone != null else ""


func is_safe(t: Vector2i) -> bool:
	var chunk_zone := _zone_at(t)
	return chunk_zone.is_safe(_local_tile(t)) if chunk_zone != null else false


func find_path(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var empty_result: Array[Vector2i] = []
	if _chunk_astar == null or not is_walkable(a) or not is_walkable(b):
		return empty_result
	if a == b:
		var single_result: Array[Vector2i] = [a]
		return single_result
	return _chunk_astar.get_id_path(a, b)


## Zone of the loaded chunk covering world tile t, or null.
func _zone_at(t: Vector2i) -> Zone:
	return world.zone_at(t) if world != null else null


func _local_tile(t: Vector2i) -> Vector2i:
	return world.local_tile_at(t) if world != null else t


func _build_astar() -> void:
	if width <= 0 or height <= 0:
		return
	_chunk_astar = AStarGrid2D.new()
	_chunk_astar.region = Rect2i(0, 0, width, height)
	_chunk_astar.cell_size = Vector2(1, 1)
	_chunk_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_chunk_astar.update()
	for y in range(height):
		for x in range(width):
			var t := Vector2i(x, y)
			if not is_walkable(t):
				_chunk_astar.set_point_solid(t, true)


func _append_entries(source: Array[Dictionary], offset: Vector2i, target: Array[Dictionary]) -> void:
	for item: Dictionary in source:
		var copy := item.duplicate(true)
		var tile_result: Variant = _parse_entry_tile(copy.get("tile"))
		if tile_result != null:
			var tile: Vector2i = tile_result
			copy["tile"] = [tile.x + offset.x, tile.y + offset.y]
		target.append(copy)


static func _parse_entry_tile(value: Variant) -> Variant:
	if value is Vector2i:
		return value
	if value is Vector2:
		return Vector2i(int(floor(value.x)), int(floor(value.y)))
	if value is Array and value.size() >= 2:
		var arr: Array = value
		if (arr[0] is int or arr[0] is float) and (arr[1] is int or arr[1] is float):
			return Vector2i(int(arr[0]), int(arr[1]))
	return null
