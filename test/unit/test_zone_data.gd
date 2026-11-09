extends GutTest

const FLOOR1_DIR := "res://data/zones/floor1"
const ENEMIES_PATH := "res://data/enemies.json"


func _load_json_file(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "Failed to open file: %s" % path)
	if file == null:
		return null
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	var err := json.parse(text)
	assert_eq(err, OK, "Failed to parse JSON at %s: %s" % [path, json.get_error_message()])
	if err != OK:
		return null
	return json.data


func _find_zone_pairs() -> Array[Dictionary]:
	var pairs: Array[Dictionary] = []
	var dir := DirAccess.open(FLOOR1_DIR)
	assert_not_null(dir, "Failed to open directory: %s" % FLOOR1_DIR)
	if dir == null:
		return pairs
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var base := file_name.get_basename()
			if base != "test_small":
				var json_path := FLOOR1_DIR.path_join(file_name)
				var map_path := FLOOR1_DIR.path_join(base + ".map")
				if FileAccess.file_exists(map_path):
					pairs.append({
						"name": base,
						"json_path": json_path,
						"map_path": map_path,
					})
		file_name = dir.get_next()
	dir.list_dir_end()
	return pairs


func test_floor1_zones_validity_and_enemies() -> void:
	var enemies_raw: Variant = _load_json_file(ENEMIES_PATH)
	assert_true(enemies_raw is Dictionary, "enemies.json must be a Dictionary")
	var enemies: Dictionary = enemies_raw if enemies_raw is Dictionary else {}

	var pairs := _find_zone_pairs()
	assert_gt(pairs.size(), 0, "Expected at least one non-fixture zone in floor1")

	for pair in pairs:
		var zone_name: String = pair["name"]
		var map_path: String = pair["map_path"]
		var json_path: String = pair["json_path"]

		var zone := Zone.load_files(map_path, json_path)
		assert_not_null(zone, "Zone %s should not be null" % zone_name)
		assert_true(zone.is_valid(), "Zone %s must load with no errors, got: %s" % [zone_name, str(zone.errors)])
		assert_eq(zone.errors.size(), 0, "Zone %s errors array must be empty" % zone_name)

		var seen_spawn_tiles: Dictionary = {}
		for i in range(zone.spawns.size()):
			var spawn: Dictionary = zone.spawns[i]
			var enemy_id: String = str(spawn.get("enemy", ""))
			assert_true(enemies.has(enemy_id), "Spawn enemy '%s' in %s must exist in enemies.json" % [enemy_id, zone_name])

			var tile_raw: Variant = spawn.get("tile")
			assert_true(tile_raw is Array, "Spawn tile must be an array")
			var tile_arr: Array = tile_raw if tile_raw is Array else []
			assert_eq(tile_arr.size(), 2, "Spawn tile must have 2 elements")
			var spawn_tile := Vector2i(int(tile_arr[0]), int(tile_arr[1]))

			assert_ne(spawn_tile, zone.entry, "Spawn tile %s cannot be on entry in %s" % [str(spawn_tile), zone_name])
			assert_false(seen_spawn_tiles.has(spawn_tile), "Spawn tile %s is duplicate in %s" % [str(spawn_tile), zone_name])
			seen_spawn_tiles[spawn_tile] = true

			var path := zone.find_path(zone.entry, spawn_tile)
			assert_gt(path.size(), 0, "Spawn tile %s in %s must be reachable from entry %s via find_path" % [str(spawn_tile), zone_name, str(zone.entry)])


func test_test_arena_specifics() -> void:
	var map_path := FLOOR1_DIR.path_join("test_arena.map")
	var json_path := FLOOR1_DIR.path_join("test_arena.json")
	assert_true(FileAccess.file_exists(map_path), "test_arena.map must exist")
	assert_true(FileAccess.file_exists(json_path), "test_arena.json must exist")

	var zone := Zone.load_files(map_path, json_path)
	assert_not_null(zone)
	assert_true(zone.is_valid(), "test_arena must be valid: %s" % str(zone.errors))

	# Size within 24..40 x 14..24
	assert_gte(zone.width, 24, "test_arena width (%d) must be >= 24" % zone.width)
	assert_lte(zone.width, 40, "test_arena width (%d) must be <= 40" % zone.width)
	assert_gte(zone.height, 14, "test_arena height (%d) must be >= 14" % zone.height)
	assert_lte(zone.height, 24, "test_arena height (%d) must be <= 24" % zone.height)

	# Exactly 3 spawns
	assert_eq(zone.spawns.size(), 3, "test_arena must have exactly 3 spawns")

	# Entry walkable
	assert_true(zone.is_walkable(zone.entry), "test_arena entry must be walkable")

	# Exits check
	assert_eq(zone.exits.size(), 1, "test_arena must have 1 exit")
	var exit_entry: Dictionary = zone.exits[0]
	assert_eq(exit_entry.get("to_zone"), "town")
	var exit_tile_arr: Array = exit_entry.get("tile", [])
	var exit_tile := Vector2i(int(exit_tile_arr[0]), int(exit_tile_arr[1]))
	assert_true(zone.is_walkable(exit_tile), "test_arena exit tile must be walkable")
	var exit_path := zone.find_path(zone.entry, exit_tile)
	assert_gt(exit_path.size(), 0, "test_arena exit tile must be reachable from entry")

	# All walkable areas reachable from entry
	var walkable_tiles: int = 0
	for y in range(zone.height):
		for x in range(zone.width):
			var t := Vector2i(x, y)
			if zone.is_walkable(t):
				walkable_tiles += 1
				var path := zone.find_path(zone.entry, t)
				assert_gt(path.size(), 0, "Walkable tile %s must be reachable from entry %s in test_arena" % [str(t), str(zone.entry)])
	assert_gt(walkable_tiles, 0, "test_arena must have walkable tiles")
