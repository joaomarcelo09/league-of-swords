class_name ZoneView
extends TileMapLayer

const DEFAULT_TILE_PX: int = 32
const ATLAS_SOURCE_ID: int = 0

## Tileset JSON read on first build unless load_tileset() was called (tests may point
## this at a user:// file). Atlas, tile coords, fallback and variants all come from it.
var tileset_path: String = TilesetData.DEFAULT_PATH
var tileset: TilesetData = null

var tile_px: int = DEFAULT_TILE_PX
var current_zone: Zone = null

# True when balance.json view.tile_px set tile_px: it then wins over the tileset tile_px.
var _tile_px_from_balance: bool = false


func _init(p_registry: DataRegistry = null) -> void:
	if p_registry != null:
		setup(p_registry)


func setup(registry: DataRegistry) -> void:
	if registry == null:
		return
	var px_val: Variant = registry.get_balance("view.tile_px")
	if px_val != null and int(px_val) > 0:
		tile_px = int(px_val)
		_tile_px_from_balance = true


## Loads the tileset JSON at path (missing/invalid file -> built-in default, no crash).
## Drops any already built TileSet so the next build() uses the new data.
func load_tileset(path: String = tileset_path) -> TilesetData:
	tileset_path = path
	tileset = TilesetData.load_file(path)
	if not _tile_px_from_balance:
		tile_px = tileset.tile_px
	tile_set = null
	return tileset


func build(zone: Zone) -> void:
	current_zone = zone
	if tileset == null:
		load_tileset(tileset_path)
	_ensure_tileset()
	clear()
	if zone == null:
		return

	for y in range(zone.height):
		for x in range(zone.width):
			var t := Vector2i(x, y)
			var type_name := zone.tile_type(t)
			set_cell(t, ATLAS_SOURCE_ID, tileset.coords_for(type_name, t))


func _ensure_tileset() -> void:
	if tile_set != null:
		return

	var coords: Array[Vector2i] = tileset.all_coords()
	var grid := Vector2i(1, 1)
	for c: Vector2i in coords:
		grid = Vector2i(maxi(grid.x, c.x + 1), maxi(grid.y, c.y + 1))

	var ts := TileSet.new()
	ts.tile_size = Vector2i(tile_px, tile_px)

	var tex: Texture2D = null
	if ResourceLoader.exists(tileset.atlas_path):
		tex = load(tileset.atlas_path) as Texture2D

	if tex == null:
		var img := Image.create(grid.x * tile_px, grid.y * tile_px, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.2, 0.2, 0.2))
		tex = ImageTexture.create_from_image(img)

	var source := TileSetAtlasSource.new()
	source.texture = tex
	source.texture_region_size = Vector2i(tile_px, tile_px)
	var tex_size := Vector2i(tex.get_width(), tex.get_height())
	for c: Vector2i in coords:
		if (c.x + 1) * tile_px > tex_size.x or (c.y + 1) * tile_px > tex_size.y:
			push_warning("ZoneView: atlas coords %s outside atlas %s, skipped" % [str(c), tileset.atlas_path])
			continue
		source.create_tile(c)

	ts.add_source(source, ATLAS_SOURCE_ID)
	tile_set = ts


static func tile_to_world_coords(t: Vector2i, p_tile_px: int = DEFAULT_TILE_PX) -> Vector2:
	return Vector2((float(t.x) + 0.5) * float(p_tile_px), (float(t.y) + 0.5) * float(p_tile_px))


static func world_to_tile_coords(world_pos: Vector2, p_tile_px: int = DEFAULT_TILE_PX) -> Vector2i:
	return Vector2i(int(floor(world_pos.x / float(p_tile_px))), int(floor(world_pos.y / float(p_tile_px))))


func tile_to_world(t: Vector2i) -> Vector2:
	return tile_to_world_coords(t, tile_px)


func world_to_tile(world_pos: Vector2) -> Vector2i:
	return world_to_tile_coords(world_pos, tile_px)


func entity_to_world(entity_pos: Vector2) -> Vector2:
	return entity_pos * float(tile_px)


func world_to_entity(world_pos: Vector2) -> Vector2:
	return world_pos / float(tile_px)
