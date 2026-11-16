class_name WorldMap
extends RefCounted

# Pure-logic description of a floor laid out as a grid of chunks.
# Built from data/zones/<floor>/world.json:
#   chunk_size: [width, height] in tiles
#   load_radius: chunk radius (Chebyshev) kept loaded around the player
#   chunks: [{id, grid: [cx, cy], zone: "<zone file stem>", kind: "..."}]
#   transitions: [{id, kind: "gate"|"door", from: {chunk, tile},
#                  to: {chunk, tile} or {zone, tile} for doors,
#                  requires_boss (optional), label (optional)}]
# Tiles are local to their chunk. No Node/SceneTree/Input/rendering dependencies.

var chunk_size: Vector2i = Vector2i.ZERO
var load_radius: int = 0
var errors: Array[String] = []

var _chunks: Dictionary = {}  # chunk id (String) -> {id, grid: Vector2i, zone, kind}
var _cells: Dictionary = {}  # grid cell (Vector2i) -> chunk id (String)
var _transitions: Array[Dictionary] = []
var _transition_at: Dictionary = {}  # chunk id (String) -> {Vector2i -> transition}


func is_valid() -> bool:
	return errors.is_empty()


func has_chunk(chunk_id: String) -> bool:
	return _chunks.has(chunk_id)


func chunk_ids() -> Array[String]:
	var result: Array[String] = []
	for id_key: Variant in _chunks.keys():
		result.append(str(id_key))
	result.sort()
	return result


func zone_stem(chunk_id: String) -> String:
	if _chunks.has(chunk_id):
		return str((_chunks[chunk_id] as Dictionary).get("zone", ""))
	return ""


func chunk_kind(chunk_id: String) -> String:
	if _chunks.has(chunk_id):
		return str((_chunks[chunk_id] as Dictionary).get("kind", ""))
	return ""


func grid_cell(chunk_id: String) -> Vector2i:
	if _chunks.has(chunk_id):
		return (_chunks[chunk_id] as Dictionary).get("grid", Vector2i(-1, -1))
	return Vector2i(-1, -1)


func chunk_at_cell(cell: Vector2i) -> String:
	if _cells.has(cell):
		return str(_cells[cell])
	return ""


# Transition whose `from` tile is local_tile inside chunk_id, or an empty
# Dictionary when the tile has no transition. The returned dictionary is a
# copy with keys: id, kind, from_chunk, from_tile, to_chunk, to_zone,
# to_tile, requires_boss, label (to_chunk is empty for zone doors).
func transition_at(chunk_id: String, local_tile: Vector2i) -> Dictionary:
	var by_tile: Variant = _transition_at.get(chunk_id)
	if not (by_tile is Dictionary):
		return {}
	var entry: Variant = (by_tile as Dictionary).get(local_tile)
	if entry is Dictionary:
		return (entry as Dictionary).duplicate(true)
	return {}


# Transitions starting inside chunk_id, sorted by transition id.
func transitions_of(chunk_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for transition: Dictionary in _transitions:
		if str(transition.get("from_chunk", "")) == chunk_id:
			result.append(transition.duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("id", "")) < str(b.get("id", ""))
	)
	return result


# Maps a world tile to its chunk cell and the tile inside that chunk.
# The returned dictionary always has "chunk_id", "local_tile" and "chunk_cell";
# "chunk_id" is empty when no chunk is placed on that grid cell.
func world_to_chunk(world_tile: Vector2i) -> Dictionary:
	if chunk_size.x <= 0 or chunk_size.y <= 0:
		return {
			"chunk_id": "",
			"local_tile": world_tile,
			"chunk_cell": Vector2i.ZERO,
		}
	var cell := Vector2i(
		int(floorf(float(world_tile.x) / float(chunk_size.x))),
		int(floorf(float(world_tile.y) / float(chunk_size.y)))
	)
	var local_tile := Vector2i(
		posmod(world_tile.x, chunk_size.x),
		posmod(world_tile.y, chunk_size.y)
	)
	return {
		"chunk_id": chunk_at_cell(cell),
		"local_tile": local_tile,
		"chunk_cell": cell,
	}


func chunk_id_at_tile(world_tile: Vector2i) -> String:
	return str(world_to_chunk(world_tile).get("chunk_id", ""))


# Converts a tile local to a chunk into its world tile. Returns (-1, -1)
# when the chunk id is unknown.
func chunk_to_world(chunk_id: String, local_tile: Vector2i) -> Vector2i:
	if not _chunks.has(chunk_id):
		return Vector2i(-1, -1)
	var cell: Vector2i = (_chunks[chunk_id] as Dictionary).get("grid", Vector2i.ZERO)
	return Vector2i(cell.x * chunk_size.x + local_tile.x, cell.y * chunk_size.y + local_tile.y)


# Ids of the chunks in the 8 surrounding grid cells (Chebyshev neighbours).
func neighbors(chunk_id: String) -> Array[String]:
	var result: Array[String] = []
	if not _chunks.has(chunk_id):
		return result
	var cell: Vector2i = grid_cell(chunk_id)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var neighbor_id := chunk_at_cell(cell + Vector2i(dx, dy))
			if not neighbor_id.is_empty():
				result.append(neighbor_id)
	result.sort()
	return result


# Ids of the chunks whose grid cell is within `radius` (Chebyshev) of `cell`.
# A negative radius falls back to the map's load_radius.
func chunks_near(cell: Vector2i, radius: int = -1) -> Array[String]:
	var effective_radius: int = load_radius if radius < 0 else radius
	var result: Array[String] = []
	if effective_radius < 0:
		return result
	for dy in range(-effective_radius, effective_radius + 1):
		for dx in range(-effective_radius, effective_radius + 1):
			var near_id := chunk_at_cell(cell + Vector2i(dx, dy))
			if not near_id.is_empty():
				result.append(near_id)
	result.sort()
	return result


static func load_file(path: String) -> WorldMap:
	var map := WorldMap.new()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		map.errors.append("%s: Cannot open file (error %d)" % [path, FileAccess.get_open_error()])
		return map
	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var parse_err := json.parse(text)
	if parse_err != OK:
		map.errors.append("%s: JSON parse error at line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return map

	return load_from_dict(json.data, path)


static func load_from_dict(data: Variant, json_name: String = "world.json") -> WorldMap:
	var map := WorldMap.new()
	if not (data is Dictionary):
		map.errors.append("%s: Top-level JSON must be an object" % json_name)
		return map
	var world: Dictionary = data

	map._parse_chunk_size(world, json_name)
	map._parse_load_radius(world, json_name)
	map._parse_chunks(world, json_name)
	map._parse_transitions(world, json_name)
	return map


func _parse_chunk_size(world: Dictionary, json_name: String) -> void:
	if not world.has("chunk_size"):
		errors.append("%s: Missing 'chunk_size' field" % json_name)
		return
	var parsed: Variant = _parse_int_pair(world["chunk_size"], "chunk_size", json_name)
	if parsed == null:
		return
	var size: Vector2i = parsed
	if size.x <= 0 or size.y <= 0:
		errors.append("%s: 'chunk_size' must be positive, got [%d, %d]" % [json_name, size.x, size.y])
		return
	chunk_size = size


func _parse_load_radius(world: Dictionary, json_name: String) -> void:
	if not world.has("load_radius"):
		errors.append("%s: Missing 'load_radius' field" % json_name)
		return
	var value: Variant = world["load_radius"]
	if not _is_int_value(value):
		errors.append("%s: 'load_radius' must be an integer" % json_name)
		return
	var radius: int = _to_int(value)
	if radius < 0:
		errors.append("%s: 'load_radius' must be >= 0, got %d" % [json_name, radius])
		return
	load_radius = radius


func _parse_chunks(world: Dictionary, json_name: String) -> void:
	if not world.has("chunks"):
		errors.append("%s: Missing 'chunks' field" % json_name)
		return
	var chunks_value: Variant = world["chunks"]
	if not (chunks_value is Array):
		errors.append("%s: 'chunks' must be an array" % json_name)
		return

	var chunks_arr: Array = chunks_value
	var seen_ids: Dictionary = {}
	var seen_cells: Dictionary = {}
	for i in range(chunks_arr.size()):
		var item: Variant = chunks_arr[i]
		if not (item is Dictionary):
			errors.append("%s: chunk[%d] must be an object" % [json_name, i])
			continue
		_parse_chunk(item, i, json_name, seen_ids, seen_cells)


func _parse_chunk(entry: Dictionary, index: int, json_name: String, seen_ids: Dictionary, seen_cells: Dictionary) -> void:
	var chunk_id := ""
	if not entry.has("id"):
		errors.append("%s: chunk[%d] missing 'id' field" % [json_name, index])
	else:
		var id_value: Variant = entry["id"]
		if not _is_non_empty_string(id_value):
			errors.append("%s: chunk[%d] id must be a non-empty string" % [json_name, index])
		elif seen_ids.has(str(id_value)):
			errors.append("%s: chunk[%d] id '%s' is duplicated" % [json_name, index, str(id_value)])
		else:
			seen_ids[str(id_value)] = true
			chunk_id = str(id_value)

	var parsed_cell: Variant = null
	if not entry.has("grid"):
		errors.append("%s: chunk[%d] missing 'grid' field" % [json_name, index])
	else:
		parsed_cell = _parse_int_pair(entry["grid"], "chunk[%d] grid" % index, json_name)

	var zone_stem_value := ""
	if not entry.has("zone"):
		errors.append("%s: chunk[%d] missing 'zone' field" % [json_name, index])
	else:
		var zone_value: Variant = entry["zone"]
		if not _is_non_empty_string(zone_value):
			errors.append("%s: chunk[%d] zone must be a non-empty string" % [json_name, index])
		else:
			zone_stem_value = str(zone_value)

	var kind_value := ""
	if not entry.has("kind"):
		errors.append("%s: chunk[%d] missing 'kind' field" % [json_name, index])
	else:
		var kind_raw: Variant = entry["kind"]
		if not _is_non_empty_string(kind_raw):
			errors.append("%s: chunk[%d] kind must be a non-empty string" % [json_name, index])
		else:
			kind_value = str(kind_raw)

	if parsed_cell == null:
		return

	var cell: Vector2i = parsed_cell
	if seen_cells.has(cell):
		errors.append("%s: chunk[%d] grid cell [%d, %d] is already used by '%s'" % [json_name, index, cell.x, cell.y, str(seen_cells[cell])])
		return
	seen_cells[cell] = chunk_id if not chunk_id.is_empty() else "?"
	if chunk_id.is_empty():
		return

	_chunks[chunk_id] = {
		"id": chunk_id,
		"grid": cell,
		"zone": zone_stem_value,
		"kind": kind_value,
	}
	_cells[cell] = chunk_id


func _parse_transitions(world: Dictionary, json_name: String) -> void:
	if not world.has("transitions"):
		return
	var value: Variant = world["transitions"]
	if not (value is Array):
		errors.append("%s: 'transitions' must be an array" % json_name)
		return
	var arr: Array = value
	var seen_ids: Dictionary = {}
	var seen_from: Dictionary = {}  # chunk id (String) -> {Vector2i -> transition id}
	for i in range(arr.size()):
		var item: Variant = arr[i]
		if not (item is Dictionary):
			errors.append("%s: transition[%d] must be an object" % [json_name, i])
			continue
		_parse_transition(item, i, json_name, seen_ids, seen_from)


func _parse_transition(entry: Dictionary, index: int, json_name: String, seen_ids: Dictionary, seen_from: Dictionary) -> void:
	var error_count := errors.size()

	var transition_id := ""
	if not entry.has("id"):
		errors.append("%s: transition[%d] missing 'id' field" % [json_name, index])
	else:
		var id_value: Variant = entry["id"]
		if not _is_non_empty_string(id_value):
			errors.append("%s: transition[%d] id must be a non-empty string" % [json_name, index])
		elif seen_ids.has(str(id_value)):
			errors.append("%s: transition[%d] id '%s' is duplicated" % [json_name, index, str(id_value)])
		else:
			seen_ids[str(id_value)] = true
			transition_id = str(id_value)

	var kind := ""
	if not entry.has("kind"):
		errors.append("%s: transition[%d] missing 'kind' field" % [json_name, index])
	else:
		var kind_value: Variant = entry["kind"]
		if not _is_non_empty_string(kind_value):
			errors.append("%s: transition[%d] kind must be a non-empty string" % [json_name, index])
		elif str(kind_value) != "gate" and str(kind_value) != "door":
			errors.append("%s: transition[%d] kind must be 'gate' or 'door', got '%s'" % [json_name, index, str(kind_value)])
		else:
			kind = str(kind_value)

	var from_end: Variant = null
	if not entry.has("from"):
		errors.append("%s: transition[%d] missing 'from' field" % [json_name, index])
	else:
		from_end = _parse_transition_end(entry["from"], "transition[%d] from" % index, json_name, false)

	var to_end: Variant = null
	if not entry.has("to"):
		errors.append("%s: transition[%d] missing 'to' field" % [json_name, index])
	else:
		to_end = _parse_transition_end(entry["to"], "transition[%d] to" % index, json_name, kind == "door")

	var boss := ""
	if entry.has("requires_boss"):
		var boss_value: Variant = entry["requires_boss"]
		if typeof(boss_value) != TYPE_STRING:
			errors.append("%s: transition[%d] requires_boss must be a string" % [json_name, index])
		else:
			boss = str(boss_value)

	var label := ""
	if entry.has("label"):
		var label_value: Variant = entry["label"]
		if typeof(label_value) != TYPE_STRING:
			errors.append("%s: transition[%d] label must be a string" % [json_name, index])
		else:
			label = str(label_value)

	if errors.size() != error_count:
		return

	var from_chunk := str((from_end as Dictionary)["chunk"])
	var from_tile: Vector2i = (from_end as Dictionary)["tile"]
	var chunk_tiles: Dictionary = seen_from.get(from_chunk, {})
	if chunk_tiles.has(from_tile):
		errors.append("%s: transition[%d] from tile [%d, %d] in chunk '%s' is already used by '%s'" % [json_name, index, from_tile.x, from_tile.y, from_chunk, str(chunk_tiles[from_tile])])
		return
	chunk_tiles[from_tile] = transition_id
	seen_from[from_chunk] = chunk_tiles

	var transition := {
		"id": transition_id,
		"kind": kind,
		"from_chunk": from_chunk,
		"from_tile": from_tile,
		"to_chunk": "",
		"to_zone": "",
		"to_tile": (to_end as Dictionary)["tile"],
		"requires_boss": boss,
		"label": label,
	}
	if (to_end as Dictionary).has("chunk"):
		transition["to_chunk"] = str((to_end as Dictionary)["chunk"])
	else:
		transition["to_zone"] = str((to_end as Dictionary)["zone"])
	_transitions.append(transition)

	var by_tile: Dictionary = _transition_at.get(from_chunk, {})
	by_tile[from_tile] = transition
	_transition_at[from_chunk] = by_tile


# Parses a transition endpoint. Chunk targets are checked against the chunk
# grid; zone targets (doors only) are external zones with their own bounds.
# Returns {chunk, tile} / {zone, tile}, or null after recording errors.
func _parse_transition_end(value: Variant, label: String, json_name: String, allow_zone: bool) -> Variant:
	if not (value is Dictionary):
		errors.append("%s: %s must be an object" % [json_name, label])
		return null
	var end: Dictionary = value
	var has_chunk := end.has("chunk")
	var has_zone := end.has("zone")
	if has_chunk and has_zone:
		errors.append("%s: %s must target either a chunk or a zone, not both" % [json_name, label])
		return null

	var parsed_tile: Variant = _parse_int_pair(end.get("tile"), "%s tile" % label, json_name)
	if parsed_tile == null:
		return null
	var tile: Vector2i = parsed_tile

	if has_chunk:
		var chunk_value: Variant = end["chunk"]
		if not _is_non_empty_string(chunk_value):
			errors.append("%s: %s chunk must be a non-empty string" % [json_name, label])
			return null
		var chunk_id := str(chunk_value)
		if not _chunks.has(chunk_id):
			errors.append("%s: %s references unknown chunk '%s'" % [json_name, label, chunk_id])
			return null
		if chunk_size.x > 0 and chunk_size.y > 0:
			if tile.x < 0 or tile.y < 0 or tile.x >= chunk_size.x or tile.y >= chunk_size.y:
				errors.append("%s: %s tile [%d, %d] is outside chunk '%s' bounds [%d, %d]" % [json_name, label, tile.x, tile.y, chunk_id, chunk_size.x, chunk_size.y])
				return null
		return {"chunk": chunk_id, "tile": tile}

	if has_zone:
		if not allow_zone:
			errors.append("%s: %s must target a chunk; only doors may target a zone" % [json_name, label])
			return null
		var zone_value: Variant = end["zone"]
		if not _is_non_empty_string(zone_value):
			errors.append("%s: %s zone must be a non-empty string" % [json_name, label])
			return null
		if tile.x < 0 or tile.y < 0:
			errors.append("%s: %s tile [%d, %d] must be non-negative for a zone target" % [json_name, label, tile.x, tile.y])
			return null
		return {"zone": str(zone_value), "tile": tile}

	errors.append("%s: %s must target a chunk, or a zone for doors" % [json_name, label])
	return null


static func _is_non_empty_string(value: Variant) -> bool:
	return (typeof(value) == TYPE_STRING or typeof(value) == TYPE_STRING_NAME) and not str(value).is_empty()


static func _is_int_value(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) == TYPE_FLOAT:
		var number: float = value
		return is_finite(number) and is_equal_approx(number, floorf(number))
	return false


static func _to_int(value: Variant) -> int:
	if typeof(value) == TYPE_FLOAT:
		return int(roundf(value))
	return int(value)


func _parse_int_pair(value: Variant, label: String, json_name: String) -> Variant:
	if value is Array:
		var arr: Array = value
		if arr.size() == 2 and _is_int_value(arr[0]) and _is_int_value(arr[1]):
			return Vector2i(_to_int(arr[0]), _to_int(arr[1]))
	errors.append("%s: %s must be [x, y] with integer values" % [json_name, label])
	return null
