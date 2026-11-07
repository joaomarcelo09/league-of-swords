class_name Zone
extends RefCounted

var width: int = 0
var height: int = 0
var entry: Vector2i = Vector2i(-1, -1)
var spawns: Array[Dictionary] = []
var exits: Array[Dictionary] = []
var errors: Array[String] = []

var _rows: Array[String] = []
var _legend: Dictionary = {}
var _astar: AStarGrid2D = null


func is_valid() -> bool:
	return errors.is_empty()


func is_in_bounds(t: Vector2i) -> bool:
	return t.x >= 0 and t.x < width and t.y >= 0 and t.y < height


func is_walkable(t: Vector2i) -> bool:
	if not is_in_bounds(t):
		return false
	if t.y >= _rows.size() or t.x >= _rows[t.y].length():
		return false
	var ch: String = _rows[t.y][t.x]
	var info: Variant = _legend.get(ch)
	if info is Dictionary:
		return bool(info.get("walkable", false))
	return false


func tile_type(t: Vector2i) -> String:
	if not is_in_bounds(t):
		return ""
	if t.y >= _rows.size() or t.x >= _rows[t.y].length():
		return ""
	var ch: String = _rows[t.y][t.x]
	var info: Variant = _legend.get(ch)
	if info is Dictionary:
		return str(info.get("type", ""))
	return ""


func decor_at(t: Vector2i) -> String:
	if not is_in_bounds(t):
		return ""
	if t.y >= _rows.size() or t.x >= _rows[t.y].length():
		return ""
	var ch: String = _rows[t.y][t.x]
	var info: Variant = _legend.get(ch)
	if info is Dictionary:
		return str(info.get("decor", ""))
	return ""


func find_path(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	if not is_valid() or _astar == null:
		var empty_res: Array[Vector2i] = []
		return empty_res
	if not is_walkable(a) or not is_walkable(b):
		var empty_res: Array[Vector2i] = []
		return empty_res
	if a == b:
		var single_res: Array[Vector2i] = [a]
		return single_res
	return _astar.get_id_path(a, b)


func nearest_reachable(from: Vector2i, target: Vector2i) -> Vector2i:
	if not is_valid() or not is_walkable(from):
		return Vector2i(-1, -1)
	if from == target:
		return from

	var queue: Array[Vector2i] = [from]
	var visited: Dictionary = {from: true}
	var best_tile: Vector2i = from
	var best_dist_sq: float = (Vector2(from) - Vector2(target)).length_squared()

	var head: int = 0
	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1

		var dist_sq: float = (Vector2(current) - Vector2(target)).length_squared()
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best_tile = current
			if is_zero_approx(best_dist_sq):
				return best_tile

		for offset in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
			var next_tile: Vector2i = current + offset
			if is_walkable(next_tile) and not visited.has(next_tile):
				visited[next_tile] = true
				queue.append(next_tile)

	return best_tile


static func _is_valid_coord(v: Variant) -> bool:
	if typeof(v) == TYPE_INT:
		return true
	if typeof(v) == TYPE_FLOAT:
		var f: float = v
		return is_finite(f) and is_equal_approx(f, floorf(f))
	return false


static func _parse_tile(value: Variant, label: String, json_name: String, errors: Array[String] = []) -> Variant:
	if value is Array:
		var arr: Array = value
		if arr.size() == 2:
			var x_val: Variant = arr[0]
			var y_val: Variant = arr[1]
			if _is_valid_coord(x_val) and _is_valid_coord(y_val):
				var ix: int = int(roundf(x_val)) if typeof(x_val) == TYPE_FLOAT else int(x_val)
				var iy: int = int(roundf(y_val)) if typeof(y_val) == TYPE_FLOAT else int(y_val)
				return Vector2i(ix, iy)
	errors.append("%s: %s coordinates must be integers" % [json_name, label])
	return null


static func load_files(map_path: String, json_path: String) -> Zone:
	var zone := Zone.new()
	var map_file := FileAccess.open(map_path, FileAccess.READ)
	if map_file == null:
		var err_code := FileAccess.get_open_error()
		zone.errors.append("%s: Cannot open file (error %d)" % [map_path, err_code])

	var json_file := FileAccess.open(json_path, FileAccess.READ)
	if json_file == null:
		var err_code := FileAccess.get_open_error()
		zone.errors.append("%s: Cannot open file (error %d)" % [json_path, err_code])

	if not zone.errors.is_empty():
		return zone

	var map_text := map_file.get_as_text()
	map_file.close()

	var json_text := json_file.get_as_text()
	json_file.close()

	var json := JSON.new()
	var parse_err := json.parse(json_text)
	if parse_err != OK:
		zone.errors.append("%s: JSON parse error at line %d: %s" % [json_path, json.get_error_line(), json.get_error_message()])
		return zone

	if not (json.data is Dictionary):
		zone.errors.append("%s: Top-level JSON must be an object" % json_path)
		return zone

	return load_from_strings(map_text, json.data, map_path, json_path)


static func load_from_strings(map_text: String, json_data: Variant, map_name: String = "inline.map", json_name: String = "inline.json") -> Zone:
	var zone := Zone.new()

	var json_dict: Dictionary = {}
	if json_data is Dictionary:
		json_dict = json_data
	elif json_data is String:
		var json := JSON.new()
		var parse_err := json.parse(json_data)
		if parse_err != OK:
			zone.errors.append("%s: JSON parse error at line %d: %s" % [json_name, json.get_error_line(), json.get_error_message()])
			return zone
		if not (json.data is Dictionary):
			zone.errors.append("%s: Top-level JSON must be an object" % json_name)
			return zone
		json_dict = json.data
	else:
		zone.errors.append("%s: Top-level JSON must be an object" % json_name)
		return zone

	# 1. Validate legend
	if not json_dict.has("legend") or not (json_dict["legend"] is Dictionary):
		zone.errors.append("%s: Missing or invalid 'legend' object" % json_name)
	else:
		zone._legend = json_dict["legend"]
		for k in zone._legend.keys():
			var val: Variant = zone._legend[k]
			if not (val is Dictionary):
				zone.errors.append("%s: Legend entry '%s' must be an object" % [json_name, str(k)])

	# 2. Parse map rows
	var norm_text := map_text.replace("\r\n", "\n").replace("\r", "\n")
	var split_lines := norm_text.split("\n")
	var rows: Array[String] = []
	for line in split_lines:
		rows.append(line)
	while rows.size() > 0 and rows[rows.size() - 1].is_empty():
		rows.pop_back()

	if rows.is_empty():
		zone.errors.append("%s: Map has no rows" % map_name)
	else:
		zone.height = rows.size()
		zone.width = rows[0].length()
		if zone.width == 0:
			zone.errors.append("%s: Map row 0 is empty" % map_name)

		for r in range(rows.size()):
			var row_str: String = rows[r]
			if row_str.length() != zone.width:
				zone.errors.append("%s: row %d has width %d, expected %d" % [map_name, r, row_str.length(), zone.width])

		for r in range(rows.size()):
			var row_str: String = rows[r]
			for c in range(row_str.length()):
				var ch := row_str[c]
				if not zone._legend.has(ch):
					zone.errors.append("%s: Unknown character '%s' at row %d, col %d not in legend" % [map_name, ch, r, c])

	zone._rows = rows

	# 3. Validate entry
	if not json_dict.has("entry"):
		zone.errors.append("%s: Missing 'entry' field" % json_name)
	else:
		var entry_val: Variant = _parse_tile(json_dict["entry"], "entry", json_name, zone.errors)
		if entry_val != null:
			zone.entry = entry_val
			if zone.height > 0 and zone.width > 0:
				if not zone.is_in_bounds(zone.entry):
					zone.errors.append("%s: Entry tile %s is out of bounds" % [json_name, str(zone.entry)])
				elif not zone.is_walkable(zone.entry):
					zone.errors.append("%s: Entry tile %s is not walkable" % [json_name, str(zone.entry)])

	# 4. Validate spawns
	if json_dict.has("spawns"):
		var spawns_val: Variant = json_dict["spawns"]
		if not (spawns_val is Array):
			zone.errors.append("%s: 'spawns' must be an array" % json_name)
		else:
			var spawns_arr: Array = spawns_val
			for i in range(spawns_arr.size()):
				var spawn_item: Variant = spawns_arr[i]
				if not (spawn_item is Dictionary):
					zone.errors.append("%s: Spawn entry must be an object" % json_name)
					continue
				var s_dict: Dictionary = (spawn_item as Dictionary).duplicate(true)
				var parsed_tile: Variant = _parse_tile(s_dict.get("tile"), "spawn[%d] tile" % i, json_name, zone.errors)
				if parsed_tile == null:
					continue
				var st: Vector2i = parsed_tile
				s_dict["tile"] = [st.x, st.y]
				if zone.height > 0 and zone.width > 0:
					if not zone.is_in_bounds(st):
						zone.errors.append("%s: Spawn tile %s is out of bounds" % [json_name, str(st)])
					elif not zone.is_walkable(st):
						zone.errors.append("%s: Spawn tile %s is not walkable" % [json_name, str(st)])
				zone.spawns.append(s_dict)

	# 5. Validate exits
	if json_dict.has("exits"):
		var exits_val: Variant = json_dict["exits"]
		if not (exits_val is Array):
			zone.errors.append("%s: 'exits' must be an array" % json_name)
		else:
			var exits_arr: Array = exits_val
			for i in range(exits_arr.size()):
				var exit_item: Variant = exits_arr[i]
				if not (exit_item is Dictionary):
					zone.errors.append("%s: Exit entry must be an object" % json_name)
					continue
				var e_dict: Dictionary = (exit_item as Dictionary).duplicate(true)
				var parsed_tile: Variant = _parse_tile(e_dict.get("tile"), "exit[%d] tile" % i, json_name, zone.errors)
				if parsed_tile == null:
					continue
				var et: Vector2i = parsed_tile
				e_dict["tile"] = [et.x, et.y]
				if zone.height > 0 and zone.width > 0:
					if not zone.is_in_bounds(et):
						zone.errors.append("%s: Exit tile %s is out of bounds" % [json_name, str(et)])
					elif not zone.is_walkable(et):
						zone.errors.append("%s: Exit tile %s is not walkable" % [json_name, str(et)])
				zone.exits.append(e_dict)

	# 6. Initialize AStarGrid2D if valid
	if zone.is_valid() and zone.width > 0 and zone.height > 0:
		zone._init_astar()

	return zone


func _init_astar() -> void:
	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(0, 0, width, height)
	_astar.cell_size = Vector2(1, 1)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_astar.update()

	for y in range(height):
		for x in range(width):
			var t := Vector2i(x, y)
			if not is_walkable(t):
				_astar.set_point_solid(t, true)
