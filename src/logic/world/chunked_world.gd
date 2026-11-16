class_name ChunkedWorld
extends RefCounted

# Pure-logic owner of a chunked floor: a WorldMap, a ChunkLoader that streams
# zone chunks around the player, and the start chunk the game begins in.
# Zone files are loaded through the injected Callable (chunk id -> Zone).
# World tiles are chunk-local tiles plus the chunk's grid offset (grid * chunk_size).
# Chunk grids are expected to be non-negative; the world spans up to the highest
# occupied grid cell. No Node/SceneTree/Input/rendering dependencies.

const DEFAULT_START_CHUNK: String = "floor1_x2_y1"

var map: WorldMap = null
var loader: ChunkLoader = null
var start_chunk: String = DEFAULT_START_CHUNK
var errors: Array[String] = []
## Chunk the player last stood in ("" until the first update).
var player_chunk: String = ""
## World tile of the start chunk's zone entry, cached when the start area
## loads so it survives the start chunk streaming out. (-1, -1) until then.
var _start_entry: Vector2i = Vector2i(-1, -1)


func _init(
	p_map: WorldMap,
	p_zone_loader: Callable = Callable(),
	p_start_chunk: String = DEFAULT_START_CHUNK
) -> void:
	map = p_map
	start_chunk = p_start_chunk
	if map != null:
		loader = ChunkLoader.new(map, p_zone_loader)
		_load_start_area()
	else:
		errors.append("ChunkedWorld: no world map configured")


## Loads world_json_path and starts in start_chunk, reading zone files from
## zones_dir (<dir>/<zone stem>.map + .json, as WorldMap.zone_stem names them).
static func load_file(
	world_json_path: String,
	zones_dir: String,
	p_start_chunk: String = DEFAULT_START_CHUNK
) -> ChunkedWorld:
	var world_map := WorldMap.load_file(world_json_path)
	return ChunkedWorld.new(world_map, zone_file_loader(world_map, zones_dir), p_start_chunk)


## Callable(chunk_id) -> Zone that loads the chunk's zone files from zones_dir.
static func zone_file_loader(world_map: WorldMap, zones_dir: String) -> Callable:
	return func(chunk_id: String) -> Zone:
		if world_map == null:
			return null
		var stem := world_map.zone_stem(chunk_id)
		if stem.is_empty():
			return null
		return Zone.load_files(
			zones_dir.path_join(stem + ".map"),
			zones_dir.path_join(stem + ".json")
		)


func is_valid() -> bool:
	return errors.is_empty()


func _load_start_area() -> void:
	if not map.is_valid():
		_collect_errors()
		return
	if not map.has_chunk(start_chunk):
		_collect_errors()
		errors.append("ChunkedWorld: start chunk '%s' is not in the world map" % start_chunk)
		return
	update(map.chunk_to_world(start_chunk, Vector2i.ZERO))
	var start_zone := zone_for(start_chunk)
	if start_zone != null:
		_start_entry = map.chunk_to_world(start_chunk, start_zone.entry)


## Streams the chunks around player_world_tile and returns the ChunkLoader
## changes: {"loaded": Array[String], "unloaded": Array[String], "player_chunk": String}.
func update(player_world_tile: Vector2i) -> Dictionary:
	if map == null or loader == null:
		_collect_errors()
		errors.append("ChunkedWorld: no chunk loader configured")
		return {"loaded": [], "unloaded": [], "player_chunk": player_chunk}

	var changes := loader.update(player_world_tile)
	player_chunk = map.chunk_id_at_tile(player_world_tile) if map.is_valid() else ""
	changes["player_chunk"] = player_chunk
	_collect_errors()
	return changes


func _collect_errors() -> void:
	errors.clear()
	if map != null:
		errors.append_array(map.errors)
	if loader != null:
		errors.append_array(loader.errors)


func chunk_size() -> Vector2i:
	return map.chunk_size if map != null else Vector2i.ZERO


## World tile of the chunk's top-left corner (grid * chunk_size), or (-1, -1).
func chunk_offset(chunk_id: String) -> Vector2i:
	if map == null:
		return Vector2i(-1, -1)
	return map.chunk_to_world(chunk_id, Vector2i.ZERO)


## Chunk id covering world_tile ("" when no chunk is placed on its grid cell).
func chunk_at(world_tile: Vector2i) -> String:
	if map == null:
		return ""
	return map.chunk_id_at_tile(world_tile)


## Tile inside its chunk for a world tile (the world tile itself when unmapped).
func local_tile_at(world_tile: Vector2i) -> Vector2i:
	if map == null:
		return world_tile
	var placement := map.world_to_chunk(world_tile)
	var local_tile: Vector2i = placement.get("local_tile", world_tile)
	return local_tile


func loaded_ids() -> Array[String]:
	if loader == null:
		return []
	return loader.loaded_ids()


func is_loaded(chunk_id: String) -> bool:
	return loader != null and loader.is_loaded(chunk_id)


func zone_for(chunk_id: String) -> Zone:
	if loader == null:
		return null
	return loader.zone_for(chunk_id)


## Zone of the loaded chunk covering world_tile, or null when that chunk is not loaded.
func zone_at(world_tile: Vector2i) -> Zone:
	var chunk_id := chunk_at(world_tile)
	if chunk_id.is_empty() or not is_loaded(chunk_id):
		return null
	return zone_for(chunk_id)


func is_world_tile_loaded(world_tile: Vector2i) -> bool:
	return zone_at(world_tile) != null


func is_walkable(world_tile: Vector2i) -> bool:
	var chunk_zone := zone_at(world_tile)
	if chunk_zone == null:
		return false
	return chunk_zone.is_walkable(local_tile_at(world_tile))


## Loaded chunks with their zone and world-tile offset, sorted by chunk id.
func loaded_chunks() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if loader == null:
		return result
	for chunk_id: String in loader.loaded_ids():
		result.append({
			"id": chunk_id,
			"zone": loader.zone_for(chunk_id),
			"offset": chunk_offset(chunk_id),
			"kind": map.chunk_kind(chunk_id) if map != null else "",
		})
	return result


## World tile of the start chunk's zone entry (the player spawn), or (-1, -1)
## when the start chunk never loaded. Independent of what is currently loaded:
## the entry is cached when the start area loads, so unloading the start chunk
## does not move the spawn.
func start_entry() -> Vector2i:
	var start_zone := zone_for(start_chunk)
	if map != null and start_zone != null:
		_start_entry = map.chunk_to_world(start_chunk, start_zone.entry)
	return _start_entry


func world_width() -> int:
	if map == null or map.chunk_size.x <= 0:
		return 0
	var max_cell_x := -1
	for chunk_id: String in map.chunk_ids():
		max_cell_x = maxi(max_cell_x, map.grid_cell(chunk_id).x)
	if max_cell_x < 0:
		return 0
	return (max_cell_x + 1) * map.chunk_size.x


func world_height() -> int:
	if map == null or map.chunk_size.y <= 0:
		return 0
	var max_cell_y := -1
	for chunk_id: String in map.chunk_ids():
		max_cell_y = maxi(max_cell_y, map.grid_cell(chunk_id).y)
	if max_cell_y < 0:
		return 0
	return (max_cell_y + 1) * map.chunk_size.y
