extends GutTest

const MAP_PATH: String = "res://data/zones/floor1/test_small.map"
const JSON_PATH: String = "res://data/zones/floor1/test_small.json"
const DATA_DIR: String = "res://data"


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

	var wall_count := 0
	var floor_count := 0
	var grass_count := 0

	for y: int in range(zone.height):
		for x: int in range(zone.width):
			var t := Vector2i(x, y)
			var expected_type: String = zone.tile_type(t)
			var atlas_coords: Vector2i = zv.get_cell_atlas_coords(t)

			match expected_type:
				"wall":
					assert_eq(atlas_coords, Vector2i(0, 0), "Tile %s expected wall atlas coords" % str(t))
					wall_count += 1
				"floor":
					assert_eq(atlas_coords, Vector2i(1, 0), "Tile %s expected floor atlas coords" % str(t))
					floor_count += 1
				"grass":
					assert_eq(atlas_coords, Vector2i(2, 0), "Tile %s expected grass atlas coords" % str(t))
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
