class_name ZoneView
extends TileMapLayer

const DEFAULT_TILE_PX: int = 32
const ATLAS_PATH: String = "res://assets/tiles/placeholder_tiles.png"
const ATLAS_SOURCE_ID: int = 0

const TILE_COORDS: Dictionary = {
	"wall": Vector2i(0, 0),
	"floor": Vector2i(1, 0),
	"grass": Vector2i(2, 0),
}
const FALLBACK_COORDS: Vector2i = Vector2i(3, 0)

var tile_px: int = DEFAULT_TILE_PX
var current_zone: Zone = null


func _init(p_registry: DataRegistry = null) -> void:
	if p_registry != null:
		setup(p_registry)


func setup(registry: DataRegistry) -> void:
	if registry == null:
		return
	var px_val: Variant = registry.get_balance("view.tile_px")
	if px_val != null and int(px_val) > 0:
		tile_px = int(px_val)


func build(zone: Zone) -> void:
	current_zone = zone
	_ensure_tileset()
	clear()
	if zone == null:
		return

	for y in range(zone.height):
		for x in range(zone.width):
			var t := Vector2i(x, y)
			var type_name := zone.tile_type(t)
			var atlas_coords: Vector2i = TILE_COORDS.get(type_name, FALLBACK_COORDS)
			set_cell(t, ATLAS_SOURCE_ID, atlas_coords)


func _ensure_tileset() -> void:
	if tile_set != null:
		return

	var ts := TileSet.new()
	ts.tile_size = Vector2i(tile_px, tile_px)

	var tex: Texture2D = null
	if ResourceLoader.exists(ATLAS_PATH):
		tex = load(ATLAS_PATH)

	if tex == null:
		var img := Image.create(128, 32, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.2, 0.2, 0.2))
		tex = ImageTexture.create_from_image(img)

	var source := TileSetAtlasSource.new()
	source.texture = tex
	source.texture_region_size = Vector2i(tile_px, tile_px)
	source.create_tile(Vector2i(0, 0))
	source.create_tile(Vector2i(1, 0))
	source.create_tile(Vector2i(2, 0))
	source.create_tile(Vector2i(3, 0))

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
