extends GutTest

## JGT-123/JGT-135: Floor 1 houses are multi-tile (8x6 and 7x5) compositions
## of roof, wall, window and door decor parts. Every footprint is blocked
## except its door cell, which faces open town floor and is reachable from the
## entry.

const ZONES_DIR := "res://data/zones/floor1"
const WORLD_PATH := ZONES_DIR + "/world.json"
const TILESET_PATH := "res://data/tilesets/floor1.json"
const ATLAS_PATH := "res://assets/tiles/world_tiles.png"
const CHUNK := 32
const TILE_PX := 32
const HOUSE_SIZES := [Vector2i(8, 6), Vector2i(7, 5)]
const MIN_HOUSES := 4

## Plaza layout from tools/gen_floor1_layout.py: houses must leave these alone.
const ENTRY_TILE := Vector2i(93, 58)
const FOUNTAIN_TILE := Vector2i(93, 60)
const PLAZA_TORCHES := [
	Vector2i(92, 56), Vector2i(99, 56), Vector2i(92, 65), Vector2i(99, 65),
]

var world: WorldMap = null
var zones: Dictionary = {}  # chunk id -> Zone


func before_all() -> void:
	world = WorldMap.load_file(WORLD_PATH)
	for chunk_id: String in world.chunk_ids():
		var stem := world.zone_stem(chunk_id)
		zones[chunk_id] = Zone.load_files(ZONES_DIR.path_join(stem + ".map"), ZONES_DIR.path_join(stem + ".json"))


func _zone_at(t: Vector2i) -> Zone:
	return zones.get(world.chunk_id_at_tile(t), null)


func _local(t: Vector2i) -> Vector2i:
	return Vector2i(posmod(t.x, CHUNK), posmod(t.y, CHUNK))


func _walkable(t: Vector2i) -> bool:
	var zone := _zone_at(t)
	return zone != null and zone.is_walkable(_local(t))


func _safe(t: Vector2i) -> bool:
	var zone := _zone_at(t)
	return zone != null and zone.is_safe(_local(t))


func _decor(t: Vector2i) -> String:
	var zone := _zone_at(t)
	return zone.decor_at(_local(t)) if zone != null else ""


func _house_cells() -> Dictionary:
	## World tile -> house decor id for every house part on the floor.
	var cells := {}
	for chunk_id: String in world.chunk_ids():
		var zone: Zone = zones[chunk_id]
		for y in range(zone.height):
			for x in range(zone.width):
				var local := Vector2i(x, y)
				var decor := zone.decor_at(local)
				if decor.begins_with("house_"):
					cells[world.chunk_to_world(chunk_id, local)] = decor
	return cells


func _components(cells: Dictionary) -> Array:
	## 4-connected groups of house cells.
	var seen := {}
	var comps := []
	for start: Vector2i in cells.keys():
		if seen.has(start):
			continue
		var comp: Array[Vector2i] = [start]
		seen[start] = true
		var head := 0
		while head < comp.size():
			var t := comp[head]
			head += 1
			for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var n := t + step
				if cells.has(n) and not seen.has(n):
					seen[n] = true
					comp.append(n)
		comps.append(comp)
	return comps


func _part_kind(decor_id: String) -> String:
	var parts := decor_id.split("_")
	return parts[2] if parts.size() > 2 else ""


func test_house_parts_exist_in_tileset_and_atlas() -> void:
	var ts := TilesetData.load_file(TILESET_PATH)
	var tex: Texture2D = load(ATLAS_PATH) as Texture2D
	assert_not_null(tex, "world_tiles.png must import as a Texture2D")
	if tex == null:
		return
	var img := tex.get_image()
	var cols := img.get_width() / TILE_PX
	var rows := img.get_height() / TILE_PX

	var cells := _house_cells()
	assert_gt(cells.size(), 0, "the city uses multi-tile house parts")
	for t: Vector2i in cells.keys():
		var decor := str(cells[t])
		assert_true(ts.has_decor(decor), "house part '%s' must be in the floor1 tileset" % decor)
		if not ts.has_decor(decor):
			continue
		var c := ts.decor_coords(decor)
		assert_between(c.x, 0, cols - 1, "house part '%s' x inside the atlas" % decor)
		assert_between(c.y, 0, rows - 1, "house part '%s' y inside the atlas" % decor)


func test_every_house_is_a_solid_8x6_or_7x5_rectangle() -> void:
	var cells := _house_cells()
	var comps := _components(cells)
	assert_gte(comps.size(), MIN_HOUSES, "the city has several big houses")
	var size_counts := {}
	var variants := {}
	for decor_id: Variant in cells.values():
		variants[str(decor_id).split("_")[1]] = true
	for comp: Array in comps:
		var min_t: Vector2i = comp[0]
		var max_t: Vector2i = comp[0]
		for t: Vector2i in comp:
			min_t = Vector2i(mini(min_t.x, t.x), mini(min_t.y, t.y))
			max_t = Vector2i(maxi(max_t.x, t.x), maxi(max_t.y, t.y))
		var size := max_t - min_t + Vector2i.ONE
		assert_eq(comp.size(), size.x * size.y, "house at %s must be a solid rectangle" % str(min_t))
		assert_true(HOUSE_SIZES.has(size), "house at %s is 8x6 or 7x5, got %s" % [str(min_t), str(size)])
		assert_true(size.x >= 7 and size.y >= 5, "house at %s is at least 7x5" % str(min_t))
		size_counts[size] = int(size_counts.get(size, 0)) + 1
	assert_true(size_counts.has(Vector2i(8, 6)), "8x6 houses exist")
	assert_true(size_counts.has(Vector2i(7, 5)), "7x5 houses exist")
	assert_true(variants.has("a") and variants.has("b"), "both house palettes are used")


func test_every_house_has_all_parts_and_only_the_door_is_walkable() -> void:
	var cells := _house_cells()
	for comp: Array in _components(cells):
		var kinds := {}
		var doors: Array[Vector2i] = []
		var bottom := -1
		for t: Vector2i in comp:
			kinds[_part_kind(str(cells[t]))] = true
			if _part_kind(str(cells[t])) == "door":
				doors.append(t)
			bottom = maxi(bottom, t.y)
		for kind: String in ["ridge", "roof", "wall", "window", "door"]:
			assert_true(kinds.has(kind), "house at %s has a %s part" % [str(comp[0]), kind])
		assert_eq(doors.size(), 1, "house at %s has exactly one door" % str(comp[0]))
		if doors.size() != 1:
			continue
		var door := doors[0]
		assert_eq(door.y, bottom, "house door faces south")
		assert_true(_walkable(door), "door cell %s is walkable" % str(door))
		assert_true(_walkable(door + Vector2i.DOWN), "door %s opens onto town floor" % str(door))
		assert_eq(_decor(door + Vector2i.DOWN), "", "door approach %s stays open" % str(door + Vector2i.DOWN))
		for t: Vector2i in comp:
			if t != door:
				assert_false(_walkable(t), "house tile %s is blocked" % str(t))


func test_houses_leave_the_plaza_merchant_entry_and_fountain_open() -> void:
	assert_eq(_decor(ENTRY_TILE), "", "entry stays open town floor")
	assert_true(_walkable(ENTRY_TILE) and _safe(ENTRY_TILE), "entry is a safe walkable tile")

	for chunk_id: String in world.chunk_ids():
		var zone: Zone = zones[chunk_id]
		for npc: Dictionary in zone.npcs:
			if str(npc.get("kind", "")) != "merchant":
				continue
			var arr: Array = npc["tile"]
			var tile := world.chunk_to_world(chunk_id, Vector2i(int(arr[0]), int(arr[1])))
			assert_eq(_decor(tile), "", "merchant tile %s stays open" % str(tile))
			assert_true(_walkable(tile), "merchant tile %s is walkable" % str(tile))

	for j in range(2):
		for i in range(2):
			var tile := FOUNTAIN_TILE + Vector2i(i, j)
			assert_eq(_decor(tile), "fountain", "fountain tile %s stays a fountain" % str(tile))
			assert_false(_walkable(tile), "fountain tile %s stays blocked" % str(tile))

	for tile: Vector2i in PLAZA_TORCHES:
		assert_eq(_decor(tile), "torch", "plaza torch %s stays a torch" % str(tile))
		assert_false(_walkable(tile), "plaza torch %s stays blocked" % str(tile))


func test_entry_reaches_every_house_door() -> void:
	var chunked := ChunkedWorld.load_file(WORLD_PATH, ZONES_DIR)
	assert_true(chunked.is_valid(), "chunked world errors: %s" % str(chunked.errors))
	var start := chunked.start_entry()

	var cells := _house_cells()
	var doors: Array[Vector2i] = []
	for t: Vector2i in cells.keys():
		if _part_kind(str(cells[t])) == "door":
			doors.append(t)
	assert_gt(doors.size(), 0, "the city has house doors")

	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size():
		var t := queue[head]
		head += 1
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n := t + step
			if not seen.has(n) and _walkable(n):
				seen[n] = true
				queue.append(n)

	for door: Vector2i in doors:
		assert_true(seen.has(door), "entry reaches house door at %s" % str(door))
