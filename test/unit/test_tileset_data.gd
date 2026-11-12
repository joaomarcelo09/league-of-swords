extends GutTest
## JGT-75: tileset atlas/coords/fallback/variants come from data/tilesets/*.json.

const MAP_PATH: String = "res://data/zones/floor1/test_small.map"
const JSON_PATH: String = "res://data/zones/floor1/test_small.json"
const ARENA_MAP_PATH: String = "res://data/zones/floor1/test_arena.map"
const ARENA_JSON_PATH: String = "res://data/zones/floor1/test_arena.json"
const TMP_PATH: String = "user://test_tileset_data_tmp.json"


func after_each() -> void:
	if FileAccess.file_exists(TMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_PATH))


func _write_tmp(text: String) -> void:
	var f := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _base_dict() -> Dictionary:
	return {
		"atlas": "res://assets/tiles/placeholder_tiles.png",
		"tile_px": 32,
		"tiles": {"wall": [0, 0], "floor": [1, 0], "grass": [2, 0]},
		"fallback": [3, 0],
	}


func _mixed_zone() -> Zone:
	var custom_map: String = "#####\n#..?#\n#.,.#\n#####"
	var custom_json: Dictionary = {
		"legend": {
			"#": {"type": "wall", "walkable": false},
			".": {"type": "floor", "walkable": true},
			",": {"type": "grass", "walkable": true},
			"?": {"type": "mystery_biome", "walkable": true},
		},
		"entry": [1, 1],
	}
	return Zone.load_from_strings(custom_map, custom_json)


func test_default_json_matches_original_coords() -> void:
	var ts := TilesetData.load_file(TilesetData.DEFAULT_PATH)
	assert_false(ts.is_default, "floor1.json should load (not the built-in default)")
	assert_eq(ts.atlas_path, "res://assets/tiles/placeholder_tiles.png")
	assert_eq(ts.tile_px, 32)
	assert_eq(ts.coords_for("wall", Vector2i(0, 0)), Vector2i(0, 0))
	assert_eq(ts.coords_for("floor", Vector2i(4, 2)), Vector2i(1, 0))
	assert_eq(ts.coords_for("grass", Vector2i(1, 9)), Vector2i(2, 0))
	assert_eq(ts.coords_for("unknown", Vector2i(1, 1)), Vector2i(3, 0))


func test_default_tileset_renders_test_arena_as_before() -> void:
	var zone: Zone = Zone.load_files(ARENA_MAP_PATH, ARENA_JSON_PATH)
	assert_true(zone.is_valid())
	var zv: ZoneView = autofree(ZoneView.new())
	zv.build(zone)
	var expected := {"wall": Vector2i(0, 0), "floor": Vector2i(1, 0), "grass": Vector2i(2, 0)}
	for y: int in range(zone.height):
		for x: int in range(zone.width):
			var t := Vector2i(x, y)
			var want: Vector2i = expected.get(zone.tile_type(t), Vector2i(3, 0))
			assert_eq(zv.get_cell_atlas_coords(t), want, "cell %s" % str(t))
			assert_eq(zv.get_cell_source_id(t), ZoneView.ATLAS_SOURCE_ID)
	var src := zv.tile_set.get_source(ZoneView.ATLAS_SOURCE_ID) as TileSetAtlasSource
	assert_eq(src.get_tiles_count(), 4, "default tileset references 4 atlas coords")


func test_changed_coord_in_user_json_changes_cell() -> void:
	var d := _base_dict()
	d["tiles"]["wall"] = [3, 0]
	_write_tmp(JSON.stringify(d))

	var zone: Zone = Zone.load_files(MAP_PATH, JSON_PATH)
	var zv: ZoneView = autofree(ZoneView.new())
	zv.load_tileset(TMP_PATH)
	zv.build(zone)
	assert_eq(zv.get_cell_atlas_coords(Vector2i(0, 0)), Vector2i(3, 0), "wall now uses [3,0]")


func test_load_tileset_after_build_rebuilds_tiles() -> void:
	var zone: Zone = Zone.load_files(MAP_PATH, JSON_PATH)
	var zv: ZoneView = autofree(ZoneView.new())
	zv.build(zone)
	assert_eq(zv.get_cell_atlas_coords(Vector2i(0, 0)), Vector2i(0, 0))

	var d := _base_dict()
	d["tiles"]["wall"] = [2, 0]
	_write_tmp(JSON.stringify(d))
	zv.load_tileset(TMP_PATH)
	zv.build(zone)
	assert_eq(zv.get_cell_atlas_coords(Vector2i(0, 0)), Vector2i(2, 0))


func test_tiles_created_for_every_referenced_coord() -> void:
	var d := _base_dict()
	d["tiles"] = {"wall": [0, 0], "floor": [1, 0]}
	d["fallback"] = [1, 0]
	_write_tmp(JSON.stringify(d))
	var zv: ZoneView = autofree(ZoneView.new())
	zv.load_tileset(TMP_PATH)
	zv.build(_mixed_zone())
	var src := zv.tile_set.get_source(ZoneView.ATLAS_SOURCE_ID) as TileSetAtlasSource
	assert_eq(src.get_tiles_count(), 2)
	assert_true(src.has_tile(Vector2i(0, 0)))
	assert_true(src.has_tile(Vector2i(1, 0)))


func test_unknown_type_gets_json_fallback() -> void:
	var d := _base_dict()
	d["fallback"] = [2, 0]
	_write_tmp(JSON.stringify(d))
	var zv: ZoneView = autofree(ZoneView.new())
	zv.load_tileset(TMP_PATH)
	zv.build(_mixed_zone())
	assert_eq(zv.get_cell_atlas_coords(Vector2i(3, 1)), Vector2i(2, 0), "mystery_biome -> fallback")


func test_variants_pick_deterministically_from_listed_coords() -> void:
	var d := _base_dict()
	var listed: Array[Vector2i] = [Vector2i(1, 0), Vector2i(3, 0)]
	d["variants"] = {"wall": [[1, 0], [3, 0]]}
	_write_tmp(JSON.stringify(d))

	var zone: Zone = Zone.load_files(MAP_PATH, JSON_PATH)
	var zv1: ZoneView = autofree(ZoneView.new())
	zv1.load_tileset(TMP_PATH)
	zv1.build(zone)
	var zv2: ZoneView = autofree(ZoneView.new())
	zv2.load_tileset(TMP_PATH)
	zv2.build(zone)

	var seen: Dictionary = {}
	for y: int in range(zone.height):
		for x: int in range(zone.width):
			var t := Vector2i(x, y)
			var c1: Vector2i = zv1.get_cell_atlas_coords(t)
			assert_eq(c1, zv2.get_cell_atlas_coords(t), "same pick across builds at %s" % str(t))
			match zone.tile_type(t):
				"wall":
					assert_true(listed.has(c1), "wall variant %s must be listed" % str(c1))
					seen[c1] = true
				"floor":
					assert_eq(c1, Vector2i(1, 0), "types without variants keep their coord")
	assert_eq(seen.size(), 2, "walls should use both listed variants")


func test_variant_index_is_stable_and_in_range() -> void:
	for y: int in range(-5, 6):
		for x: int in range(-5, 6):
			var i := TilesetData.variant_index(Vector2i(x, y), 3)
			assert_between(i, 0, 2)
			assert_eq(i, TilesetData.variant_index(Vector2i(x, y), 3))
	assert_eq(TilesetData.variant_index(Vector2i(7, 7), 1), 0)
	assert_eq(TilesetData.variant_index(Vector2i(7, 7), 0), 0)


func test_missing_file_falls_back_to_default() -> void:
	var ts := TilesetData.load_file("user://does_not_exist_tileset.json")
	assert_true(ts.is_default)
	var zv: ZoneView = autofree(ZoneView.new())
	zv.load_tileset("user://does_not_exist_tileset.json")
	zv.build(_mixed_zone())
	assert_eq(zv.get_cell_atlas_coords(Vector2i(0, 0)), Vector2i(0, 0))
	assert_eq(zv.get_cell_atlas_coords(Vector2i(1, 1)), Vector2i(1, 0))
	assert_eq(zv.get_cell_atlas_coords(Vector2i(2, 2)), Vector2i(2, 0))
	assert_eq(zv.get_cell_atlas_coords(Vector2i(3, 1)), Vector2i(3, 0))


func test_invalid_json_falls_back_to_default() -> void:
	_write_tmp("{ not valid json")
	var ts := TilesetData.load_file(TMP_PATH)
	assert_true(ts.is_default)
	assert_eq(ts.coords_for("wall", Vector2i.ZERO), Vector2i(0, 0))
	assert_eq(ts.coords_for("nope", Vector2i.ZERO), Vector2i(3, 0))


func test_invalid_fields_fall_back_to_default() -> void:
	var bad_cases: Array = [
		{"tile_px": 32, "tiles": {}, "fallback": [3, 0]},
		{"atlas": "res://x.png", "tile_px": 0, "tiles": {}, "fallback": [3, 0]},
		{"atlas": "res://x.png", "tile_px": 32, "tiles": {"wall": "oops"}, "fallback": [3, 0]},
		{"atlas": "res://x.png", "tile_px": 32, "tiles": {}, "fallback": [3]},
		{"atlas": "res://x.png", "tile_px": 32, "tiles": {}, "fallback": [3, 0], "variants": {"wall": [[1]]}},
	]
	for d: Dictionary in bad_cases:
		_write_tmp(JSON.stringify(d))
		assert_true(TilesetData.load_file(TMP_PATH).is_default, "should reject %s" % JSON.stringify(d))


func test_missing_atlas_texture_uses_grey_image() -> void:
	var d := _base_dict()
	d["atlas"] = "res://assets/tiles/does_not_exist.png"
	_write_tmp(JSON.stringify(d))
	var zv: ZoneView = autofree(ZoneView.new())
	zv.load_tileset(TMP_PATH)
	zv.build(_mixed_zone())
	var src := zv.tile_set.get_source(ZoneView.ATLAS_SOURCE_ID) as TileSetAtlasSource
	assert_not_null(src.texture)
	assert_eq(src.texture.get_width(), 128)
	assert_eq(src.texture.get_height(), 32)
	assert_eq(src.get_tiles_count(), 4)
	assert_eq(zv.get_cell_atlas_coords(Vector2i(0, 0)), Vector2i(0, 0))


func test_tileset_tile_px_used_unless_balance_sets_it() -> void:
	var d := _base_dict()
	d["tile_px"] = 16
	d["atlas"] = "res://assets/tiles/does_not_exist.png"
	_write_tmp(JSON.stringify(d))

	var zv: ZoneView = autofree(ZoneView.new())
	zv.load_tileset(TMP_PATH)
	assert_eq(zv.tile_px, 16, "no balance: tileset tile_px applies")

	var registry := DataRegistry.new()
	registry.load_dir("res://data")
	var zv2: ZoneView = autofree(ZoneView.new())
	zv2.setup(registry)
	zv2.load_tileset(TMP_PATH)
	assert_eq(zv2.tile_px, 32, "balance view.tile_px wins")
