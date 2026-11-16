extends GutTest
## JGT-115: the generated city/plains atlas (assets/tiles/world_tiles.png) backs
## data/tilesets/floor1.json. Guards the data/art contract: every referenced cell is
## inside the atlas, ground cells are opaque, decor cells are transparent props.

const TILESET_PATH: String = "res://data/tilesets/floor1.json"
const ATLAS_PATH: String = "res://assets/tiles/world_tiles.png"
const TILE_PX: int = 32
const ATLAS_COLS: int = 8
const ATLAS_ROWS: int = 3


func _tileset() -> TilesetData:
	var ts := TilesetData.load_file(TILESET_PATH)
	assert_false(ts.is_default, "floor1.json must load its own tileset")
	return ts


func _atlas_image() -> Image:
	var tex: Texture2D = load(ATLAS_PATH) as Texture2D
	assert_not_null(tex, "world_tiles.png must import as a Texture2D")
	if tex == null:
		return null
	var img := tex.get_image()
	assert_not_null(img, "world_tiles.png must decode to an Image")
	return img


func _ground_coords(ts: TilesetData) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c: Vector2i in ts.tiles.values():
		if not out.has(c):
			out.append(c)
	for list: Array in ts.variants.values():
		for c: Vector2i in list:
			if not out.has(c):
				out.append(c)
	return out


func _opaque_pixel_count(img: Image, cell: Vector2i, tile_px: int) -> int:
	var count := 0
	for y: int in range(tile_px):
		for x: int in range(tile_px):
			if img.get_pixel(cell.x * tile_px + x, cell.y * tile_px + y).a > 0.0:
				count += 1
	return count


func test_atlas_file_loads_with_expected_grid() -> void:
	var ts := _tileset()
	assert_eq(ts.atlas_path, ATLAS_PATH)
	assert_eq(ts.tile_px, TILE_PX)
	assert_true(FileAccess.file_exists(ATLAS_PATH), "atlas PNG must exist")

	var img := _atlas_image()
	assert_not_null(img)
	if img == null:
		return
	assert_eq(img.get_width(), ATLAS_COLS * TILE_PX, "atlas keeps the original 8x3 grid")
	assert_eq(img.get_height(), ATLAS_ROWS * TILE_PX, "atlas keeps the original 8x3 grid")


func test_every_referenced_coord_is_inside_atlas() -> void:
	var ts := _tileset()
	var img := _atlas_image()
	assert_not_null(img)
	if img == null:
		return
	var coords: Array[Vector2i] = ts.all_coords()
	assert_gt(coords.size(), 0)
	for c: Vector2i in coords:
		assert_between(c.x, 0, ATLAS_COLS - 1, "coord %s is inside the atlas grid" % str(c))
		assert_between(c.y, 0, ATLAS_ROWS - 1, "coord %s is inside the atlas grid" % str(c))
		assert_true((c.x + 1) * ts.tile_px <= img.get_width(), "coord %s inside width" % str(c))
		assert_true((c.y + 1) * ts.tile_px <= img.get_height(), "coord %s inside height" % str(c))


func test_ground_cells_are_fully_opaque() -> void:
	var ts := _tileset()
	var img := _atlas_image()
	assert_not_null(img)
	if img == null:
		return
	for c: Vector2i in _ground_coords(ts):
		assert_eq(
			_opaque_pixel_count(img, c, ts.tile_px),
			ts.tile_px * ts.tile_px,
			"ground cell %s must have no transparent pixels" % str(c)
		)


func test_decor_cells_are_visible_with_transparent_background() -> void:
	var ts := _tileset()
	var img := _atlas_image()
	assert_not_null(img)
	if img == null:
		return
	assert_gt(ts.decor.size(), 0, "floor1 tileset defines decor cells")
	for decor_id: String in ts.decor.keys():
		var c: Vector2i = ts.decor_coords(decor_id)
		var opaque := _opaque_pixel_count(img, c, ts.tile_px)
		assert_gt(opaque, 20, "decor '%s' at %s must draw something" % [decor_id, str(c)])
		for corner: Vector2i in [Vector2i(0, 0), Vector2i(ts.tile_px - 1, 0), Vector2i(0, ts.tile_px - 1), Vector2i(ts.tile_px - 1, ts.tile_px - 1)]:
			var px := c * ts.tile_px + corner
			assert_eq(img.get_pixel(px.x, px.y).a, 0.0, "decor '%s' background must stay transparent at %s" % [decor_id, str(corner)])


func test_city_and_plains_additions_exist() -> void:
	var ts := _tileset()
	assert_true(ts.has_decor("tree"), "plains tree decor is defined")
	assert_true(ts.has_decor("rock"), "plains rock decor is defined")
	assert_eq(ts.decor_coords("tree"), Vector2i(6, 1))
	assert_eq(ts.decor_coords("rock"), Vector2i(7, 1))

	assert_true(ts.variants.has("path"), "dirt path tile variants are defined")
	var path_coords: Array = ts.variants["path"]
	assert_true(path_coords.has(Vector2i(5, 1)), "dirt path uses the new atlas cell")


func test_ground_and_decor_cells_do_not_overlap() -> void:
	var ts := _tileset()
	var ground: Dictionary = {}
	for c: Vector2i in _ground_coords(ts):
		ground[c] = true
	for decor_id: String in ts.decor.keys():
		assert_false(
			ground.has(ts.decor_coords(decor_id)),
			"decor '%s' must not reuse a ground cell" % decor_id
		)


func test_grass_has_three_distinct_variants() -> void:
	var ts := _tileset()
	assert_true(ts.variants.has("grass"))
	var distinct: Dictionary = {}
	for c: Vector2i in ts.variants["grass"]:
		distinct[c] = true
	assert_true(distinct.size() >= 3, "plains grass needs at least 3 distinct variants")
