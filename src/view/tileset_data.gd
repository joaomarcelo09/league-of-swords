class_name TilesetData
extends RefCounted
## View-side tileset description loaded from data/tilesets/*.json (JGT-75).
##
## JSON shape:
##   "atlas":    res:// path of the atlas texture
##   "tile_px":  tile size in pixels
##   "tiles":    type -> [atlas_x, atlas_y]
##   "fallback": [atlas_x, atlas_y] used for unknown tile types
##   "variants": optional, type -> [[x, y], ...]; when present (non-empty) for a type,
##               one entry is picked deterministically from the cell coords.
##   "decor":    optional, decor id -> [atlas_x, atlas_y] (JGT-80); ids come from the
##               zone legend "decor" field and are drawn on ZoneView's decor layer.
##
## A missing or invalid file yields the built-in default (identical to the original
## hardcoded ZoneView behaviour) with a push_warning, so the game never crashes.

const DEFAULT_PATH: String = "res://data/tilesets/floor1.json"

# Built-in minimal default: used only when the tileset JSON is missing/invalid.
const DEFAULT_ATLAS: String = "res://assets/tiles/placeholder_tiles.png"
const DEFAULT_TILE_PX: int = 32
const DEFAULT_TILES: Dictionary = {
	"wall": Vector2i(0, 0),
	"floor": Vector2i(1, 0),
	"grass": Vector2i(2, 0),
}
const DEFAULT_FALLBACK: Vector2i = Vector2i(3, 0)

var atlas_path: String = DEFAULT_ATLAS
var tile_px: int = DEFAULT_TILE_PX
var tiles: Dictionary = {}          # String -> Vector2i
var fallback: Vector2i = DEFAULT_FALLBACK
var variants: Dictionary = {}       # String -> Array[Vector2i]
var decor: Dictionary = {}          # String -> Vector2i
var is_default: bool = false


static func make_default() -> TilesetData:
	var ts := TilesetData.new()
	ts.tiles = DEFAULT_TILES.duplicate()
	ts.is_default = true
	return ts


## Loads a tileset JSON. Returns the built-in default (with push_warning) on any error.
static func load_file(path: String) -> TilesetData:
	if not FileAccess.file_exists(path):
		push_warning("TilesetData: file not found " + path + ", using default tileset")
		return make_default()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("TilesetData: cannot open " + path + ", using default tileset")
		return make_default()
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not (json.data is Dictionary):
		push_warning("TilesetData: invalid JSON object in " + path + ", using default tileset")
		return make_default()
	var parsed := from_dict(json.data as Dictionary)
	if parsed == null:
		push_warning("TilesetData: invalid tileset in " + path + ", using default tileset")
		return make_default()
	return parsed


## Builds a tileset from a parsed dictionary. Returns null if required fields are invalid.
static func from_dict(d: Dictionary) -> TilesetData:
	var atlas_val: Variant = d.get("atlas", null)
	if not (atlas_val is String) or (atlas_val as String).is_empty():
		return null
	var px_val: Variant = d.get("tile_px", null)
	if not (px_val is float or px_val is int) or int(px_val) <= 0:
		return null
	var tiles_val: Variant = d.get("tiles", null)
	if not (tiles_val is Dictionary):
		return null
	var fb: Variant = _parse_coord(d.get("fallback", null))
	if fb == null:
		return null

	var ts := TilesetData.new()
	ts.atlas_path = atlas_val as String
	ts.tile_px = int(px_val)
	ts.fallback = fb as Vector2i
	for type_name: Variant in (tiles_val as Dictionary).keys():
		var c: Variant = _parse_coord((tiles_val as Dictionary)[type_name])
		if c == null:
			return null
		ts.tiles[str(type_name)] = c as Vector2i

	var variants_val: Variant = d.get("variants", {})
	if variants_val is Dictionary:
		for type_name: Variant in (variants_val as Dictionary).keys():
			var list_val: Variant = (variants_val as Dictionary)[type_name]
			if not (list_val is Array):
				return null
			var coords: Array[Vector2i] = []
			for entry: Variant in list_val as Array:
				var c: Variant = _parse_coord(entry)
				if c == null:
					return null
				coords.append(c as Vector2i)
			if not coords.is_empty():
				ts.variants[str(type_name)] = coords
	elif variants_val != null:
		return null

	var decor_val: Variant = d.get("decor", {})
	if decor_val is Dictionary:
		for decor_id: Variant in (decor_val as Dictionary).keys():
			var c: Variant = _parse_coord((decor_val as Dictionary)[decor_id])
			if c == null:
				return null
			ts.decor[str(decor_id)] = c as Vector2i
	elif decor_val != null:
		return null
	return ts


## Atlas coords for a tile type at a cell. Variants (if any) win over the single coord;
## unknown types get the fallback coords.
func coords_for(type_name: String, cell: Vector2i) -> Vector2i:
	if variants.has(type_name):
		var list: Array = variants[type_name]
		return list[variant_index(cell, list.size())]
	return tiles.get(type_name, fallback)


## True when the tileset has atlas coords for this decor id.
func has_decor(decor_id: String) -> bool:
	return decor.has(decor_id)


## Atlas coords for a decor id. Callers check has_decor() first; unknown ids return
## the fallback coords.
func decor_coords(decor_id: String) -> Vector2i:
	return decor.get(decor_id, fallback)


## Every atlas coord referenced by this tileset (tiles, fallback, variants, decor), no duplicates.
func all_coords() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c: Vector2i in tiles.values():
		if not out.has(c):
			out.append(c)
	if not out.has(fallback):
		out.append(fallback)
	for list: Array in variants.values():
		for c: Vector2i in list:
			if not out.has(c):
				out.append(c)
	for c: Vector2i in decor.values():
		if not out.has(c):
			out.append(c)
	return out


## Deterministic index in [0, count) from cell coords (stable across runs and platforms).
static func variant_index(cell: Vector2i, count: int) -> int:
	if count <= 1:
		return 0
	var h: int = (cell.x * 73856093) ^ (cell.y * 19349663)
	# Mix the bits: the raw xor keeps x+y parity in bit 0, which would checkerboard
	# variants on even counts.
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7FFFFFFF
	h ^= h >> 16
	return posmod(h, count)


static func _parse_coord(v: Variant) -> Variant:
	if not (v is Array) or (v as Array).size() < 2:
		return null
	var a: Array = v as Array
	if not ((a[0] is float or a[0] is int) and (a[1] is float or a[1] is int)):
		return null
	if int(a[0]) < 0 or int(a[1]) < 0:
		return null
	return Vector2i(int(a[0]), int(a[1]))
