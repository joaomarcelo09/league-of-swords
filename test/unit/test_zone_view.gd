extends GutTest

const MAP_PATH: String = "res://data/zones/floor1/test_small.map"
const JSON_PATH: String = "res://data/zones/floor1/test_small.json"
const DATA_DIR: String = "res://data"
const FLOOR1_MAP_PATH: String = "res://data/zones/floor1/floor1.map"
const FLOOR1_JSON_PATH: String = "res://data/zones/floor1/floor1.json"


func test_tile_to_world_and_world_to_tile_round_trip() -> void:
	var zv: ZoneView = autofree(ZoneView.new())
	zv.tile_px = 32

	var test_tiles: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(1, 1),
		Vector2i(11, 7),
		Vector2i(100, 200),
		Vector2i(-1, -1),
		Vector2i(-10, 5),
	]

	for t: Vector2i in test_tiles:
		var world_center: Vector2 = zv.tile_to_world(t)
		# Centre must be (t + 0.5) * 32
		var expected_center := Vector2((float(t.x) + 0.5) * 32.0, (float(t.y) + 0.5) * 32.0)
		assert_eq(world_center, expected_center, "Tile center mismatch for tile %s" % str(t))

		var round_trip_tile: Vector2i = zv.world_to_tile(world_center)
		assert_eq(round_trip_tile, t, "Round trip failed for tile %s (got %s)" % [str(t), str(round_trip_tile)])

		# Edges of the tile should also map back to t
		var top_left := Vector2(float(t.x) * 32.0, float(t.y) * 32.0)
		assert_eq(zv.world_to_tile(top_left), t, "Top-left mapping failed for tile %s" % str(t))

		var near_bottom_right := Vector2(float(t.x + 1) * 32.0 - 0.01, float(t.y + 1) * 32.0 - 0.01)
		assert_eq(zv.world_to_tile(near_bottom_right), t, "Near bottom-right mapping failed for tile %s" % str(t))


func test_entity_and_world_coordinate_helpers() -> void:
	var zv: ZoneView = autofree(ZoneView.new())
	zv.tile_px = 32

	# Entity at tile coordinates (1.5, 2.5) -> world pixels (48.0, 80.0)
	var entity_pos := Vector2(1.5, 2.5)
	var world_px: Vector2 = zv.entity_to_world(entity_pos)
	assert_eq(world_px, Vector2(48.0, 80.0))
	assert_eq(zv.world_to_entity(world_px), entity_pos)

	# Static helper tests
	assert_eq(ZoneView.tile_to_world_coords(Vector2i(2, 3), 32), Vector2(80.0, 112.0))
	assert_eq(ZoneView.world_to_tile_coords(Vector2(80.0, 112.0), 32), Vector2i(2, 3))


func test_build_from_zone_sets_expected_cells() -> void:
	var registry := DataRegistry.new()
	registry.load_dir(DATA_DIR)

	var zone: Zone = Zone.load_files(MAP_PATH, JSON_PATH)
	assert_true(zone.is_valid(), "Zone should be valid")

	var zv: ZoneView = autofree(ZoneView.new())
	zv.setup(registry)
	zv.build(zone)

	var used_cells: Array[Vector2i] = zv.get_used_cells()
	var expected_total: int = zone.width * zone.height
	assert_eq(used_cells.size(), expected_total, "Used cell count should match total zone tiles (%d)" % expected_total)

	var ts: TilesetData = zv.tileset
	var wall_count := 0
	var floor_count := 0
	var grass_count := 0

	for y: int in range(zone.height):
		for x: int in range(zone.width):
			var t := Vector2i(x, y)
			var expected_type: String = zone.tile_type(t)
			var atlas_coords: Vector2i = zv.get_cell_atlas_coords(t)
			# Cells use the type's base coord or one of its listed variants (JGT-80).
			var allowed: Array = ts.variants.get(expected_type, [ts.tiles.get(expected_type, ts.fallback)])
			assert_true(allowed.has(atlas_coords), "Tile %s (%s) got unlisted coords %s" % [str(t), expected_type, str(atlas_coords)])
			assert_eq(atlas_coords, ts.coords_for(expected_type, t))

			match expected_type:
				"wall":
					wall_count += 1
				"floor":
					floor_count += 1
				"grass":
					grass_count += 1
				_:
					fail_test("Unexpected tile type %s at %s" % [expected_type, str(t)])

	assert_gt(wall_count, 0, "Should have walls")
	assert_gt(floor_count, 0, "Should have floors")
	assert_eq(grass_count, 1, "test_small has exactly 1 grass tile")
	assert_eq(wall_count + floor_count + grass_count, expected_total)


func test_unknown_tile_type_gets_fallback_colour() -> void:
	var custom_map: String = "###\n#?#\n###"
	var custom_json: Dictionary = {
		"legend": {
			"#": {"type": "wall", "walkable": false},
			"?": {"type": "mystery_biome", "walkable": true}
		},
		"entry": [1, 1]
	}
	var zone: Zone = Zone.load_from_strings(custom_map, custom_json)
	assert_true(zone.is_valid())

	var zv: ZoneView = autofree(ZoneView.new())
	zv.build(zone)

	var fallback_coords: Vector2i = zv.get_cell_atlas_coords(Vector2i(1, 1))
	assert_eq(fallback_coords, Vector2i(3, 0), "Unknown tile type must receive fallback atlas coords (3, 0)")


func _floor1_zone() -> Zone:
	var zone: Zone = Zone.load_files(FLOOR1_MAP_PATH, FLOOR1_JSON_PATH)
	assert_true(zone.is_valid(), "floor1 must be valid: %s" % str(zone.errors))
	return zone


func test_variants_are_deterministic_for_same_coord() -> void:
	var zone := _floor1_zone()
	var a: ZoneView = autofree(ZoneView.new())
	var b: ZoneView = autofree(ZoneView.new())
	a.build(zone)
	b.build(zone)
	a.build(zone)  # rebuilding the same view must not change the picture either
	var seen: Dictionary = {}
	for y: int in range(zone.height):
		for x: int in range(zone.width):
			var t := Vector2i(x, y)
			assert_eq(a.get_cell_atlas_coords(t), b.get_cell_atlas_coords(t), "cell %s differs between builds" % str(t))
			seen[a.get_cell_atlas_coords(t)] = true
	# floor1 really shows variety: more ground coords than the 4 base types.
	assert_gt(seen.size(), 4, "floor1 should use tile variants")


func test_decor_layer_gets_cells_for_decor_legend_tiles() -> void:
	var zone := _floor1_zone()
	var zv: ZoneView = autofree(ZoneView.new())
	zv.build(zone)
	assert_not_null(zv.decor_layer)
	assert_eq(zv.decor_layer.get_parent(), zv, "decor layer is a child of ZoneView (drawn above ground)")
	assert_eq(zv.decor_layer.tile_set, zv.tile_set, "decor layer shares the ground TileSet")

	var decor_tiles := 0
	var ids: Dictionary = {}
	for y: int in range(zone.height):
		for x: int in range(zone.width):
			var t := Vector2i(x, y)
			var decor_id := zone.decor_at(t)
			if decor_id.is_empty():
				assert_eq(zv.decor_layer.get_cell_source_id(t), -1, "no decor expected at %s" % str(t))
				continue
			decor_tiles += 1
			ids[decor_id] = true
			assert_eq(zv.decor_layer.get_cell_source_id(t), ZoneView.ATLAS_SOURCE_ID)
			assert_eq(zv.decor_layer.get_cell_atlas_coords(t), zv.tileset.decor_coords(decor_id), "decor %s at %s" % [decor_id, str(t)])
	assert_eq(zv.decor_layer.get_used_cells().size(), decor_tiles)
	for want: String in ["grass_tuft", "house", "fountain", "torch", "bones", "crate", "barrel", "rubble"]:
		assert_true(ids.has(want), "floor1 should place decor '%s'" % want)


func test_every_floor1_decor_id_is_in_tileset() -> void:
	var zone := _floor1_zone()
	var ts := TilesetData.load_file(TilesetData.DEFAULT_PATH)
	for y: int in range(zone.height):
		for x: int in range(zone.width):
			var decor_id := zone.decor_at(Vector2i(x, y))
			if not decor_id.is_empty():
				assert_true(ts.has_decor(decor_id), "decor '%s' missing from floor1 tileset" % decor_id)


func test_missing_decor_id_is_skipped_safely() -> void:
	var custom_map: String = "####\n#.x#\n####"
	var custom_json: Dictionary = {
		"legend": {
			"#": {"type": "wall", "walkable": false},
			".": {"type": "floor", "walkable": true, "decor": "bones"},
			"x": {"type": "floor", "walkable": true, "decor": "no_such_prop"},
		},
		"entry": [1, 1],
	}
	var zone: Zone = Zone.load_from_strings(custom_map, custom_json)
	assert_true(zone.is_valid())
	var zv: ZoneView = autofree(ZoneView.new())
	zv.build(zone)
	assert_eq(zv.decor_layer.get_cell_atlas_coords(Vector2i(1, 1)), zv.tileset.decor_coords("bones"))
	assert_eq(zv.decor_layer.get_cell_source_id(Vector2i(2, 1)), -1, "unknown decor id draws nothing")
	assert_eq(zv.get_cell_source_id(Vector2i(2, 1)), ZoneView.ATLAS_SOURCE_ID, "ground still drawn under unknown decor")
	# Decor never changes logic: both tiles stay walkable as the legend says.
	assert_true(zone.is_walkable(Vector2i(1, 1)))
	assert_true(zone.is_walkable(Vector2i(2, 1)))


func test_default_tileset_without_decor_draws_no_decor() -> void:
	var zone := _floor1_zone()
	var zv: ZoneView = autofree(ZoneView.new())
	zv.load_tileset("user://does_not_exist_tileset.json")
	zv.build(zone)
	assert_eq(zv.decor_layer.get_used_cells().size(), 0)
	assert_eq(zv.get_used_cells().size(), zone.width * zone.height, "ground fully drawn")


func test_rebuild_clears_old_decor() -> void:
	var zv: ZoneView = autofree(ZoneView.new())
	zv.build(_floor1_zone())
	assert_gt(zv.decor_layer.get_used_cells().size(), 0)
	var small: Zone = Zone.load_files(MAP_PATH, JSON_PATH)
	zv.build(small)
	var expected := 0
	for y: int in range(small.height):
		for x: int in range(small.width):
			if not small.decor_at(Vector2i(x, y)).is_empty():
				expected += 1
	assert_eq(zv.decor_layer.get_used_cells().size(), expected)
	assert_eq(zv.get_child_count(), 1, "decor layer is reused, not duplicated")


func test_camera_follow_centres_on_target() -> void:
	var registry := DataRegistry.new()
	registry.load_dir(DATA_DIR)

	var cam: GameCamera = autofree(GameCamera.new())
	cam.setup(registry)

	var target := Vector2(250.0, 180.0)
	cam.follow(target)

	assert_eq(cam.global_position, target, "Camera global_position should equal target")
	assert_eq(cam.position, target, "Camera position should equal target")

	# Follow a different point
	var target2 := Vector2(48.0, 48.0)
	cam.follow(target2)
	assert_eq(cam.global_position, target2)
	assert_eq(cam.position, target2)


func test_camera_loads_balance_configuration() -> void:
	var registry := DataRegistry.new()
	registry.load_dir(DATA_DIR)

	var cam: GameCamera = autofree(GameCamera.new())
	cam.setup(registry)

	# Balance has zoom: [1.0, 1.0] and offset: [0.0, 0.0]
	assert_eq(cam.zoom, Vector2(1.0, 1.0), "Camera zoom should match balance.json")
	assert_eq(cam.offset, Vector2(0.0, 0.0), "Camera offset should match balance.json")
	assert_eq(cam.follow_offset, Vector2(0.0, 0.0))


func test_main_view_clamp_frame_dt() -> void:
	# Large delta is capped to max_dt
	assert_eq(MainView.clamp_frame_dt(1.0, 0.1), 0.1)
	assert_eq(MainView.clamp_frame_dt(10.0, 0.1), 0.1)
	assert_eq(MainView.clamp_frame_dt(INF, 0.1), 0.1)

	# Small delta unchanged
	assert_eq(MainView.clamp_frame_dt(0.016, 0.1), 0.016)
	assert_eq(MainView.clamp_frame_dt(0.05, 0.1), 0.05)
	assert_eq(MainView.clamp_frame_dt(0.1, 0.1), 0.1)
	assert_eq(MainView.clamp_frame_dt(0.0, 0.1), 0.0)

	# Negative and NaN delta gives 0
	assert_eq(MainView.clamp_frame_dt(-0.016, 0.1), 0.0)
	assert_eq(MainView.clamp_frame_dt(-10.0, 0.1), 0.0)
	assert_eq(MainView.clamp_frame_dt(-INF, 0.1), 0.0)
	assert_eq(MainView.clamp_frame_dt(NAN, 0.1), 0.0)

	# Edge cases with invalid or non-positive max_dt
	assert_eq(MainView.clamp_frame_dt(0.016, 0.0), 0.0)
	assert_eq(MainView.clamp_frame_dt(0.016, -0.1), 0.0)
	assert_eq(MainView.clamp_frame_dt(0.016, NAN), 0.0)


func test_main_view_balance_configuration() -> void:
	var registry := DataRegistry.new()
	registry.load_dir(DATA_DIR)
	var max_dt: Variant = registry.get_balance("sim.max_frame_dt_s")
	assert_not_null(max_dt, "sim.max_frame_dt_s must be defined in balance.json")
	assert_gt(float(max_dt), 0.0, "sim.max_frame_dt_s must be positive")
