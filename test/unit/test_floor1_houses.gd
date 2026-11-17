extends GutTest

## JGT-123/JGT-135/JGT-137: Floor 1 buildings are multi-tile compositions of
## roof/wall/window/door parts: 8x6 and 7x5 houses plus 8x5 and 7x5 shops. They
## fill the four quarters between the roads in mirrored rows; every footprint is
## blocked except its south door, which opens onto a two tile alley reachable
## from the hub entry.

const ZONES_DIR := "res://data/zones/floor1"
const WORLD_PATH := ZONES_DIR + "/world.json"
const TILESET_PATH := "res://data/tilesets/floor1.json"
const ATLAS_PATH := "res://assets/tiles/world_tiles.png"
const CHUNK := 32
const MAP_W := 288
const MAP_H := 128
const TILE_PX := 32
const HOUSE_SIZES := [Vector2i(8, 6), Vector2i(7, 5)]
const SHOP_SIZES := [Vector2i(8, 5), Vector2i(7, 5)]
const MIN_BUILDINGS := 8
const HOUSE_PARTS := ["ridge", "roof", "wall", "window", "door"]
const SHOP_PARTS := ["parapet", "awning", "wall", "window", "door"]

## City layout from tools/gen_floor1_layout.py.
const CITY_CENTER := Vector2(96.0, 64.0)
const HUB_RADIUS := 61.0 * 0.22
const HOUSE_MAX_CITY_DIST := 52.0
const ROAD_X_MIN := 92
const ROAD_WIDTH := 8
const ROAD_Y_MIN := 60

## Plaza layout from tools/gen_floor1_layout.py: buildings must leave these alone.
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


func _type(t: Vector2i) -> String:
	var zone := _zone_at(t)
	return zone.tile_type(_local(t)) if zone != null else ""


func _walkable(t: Vector2i) -> bool:
	var zone := _zone_at(t)
	return zone != null and zone.is_walkable(_local(t))


func _safe(t: Vector2i) -> bool:
	var zone := _zone_at(t)
	return zone != null and zone.is_safe(_local(t))


func _decor(t: Vector2i) -> String:
	var zone := _zone_at(t)
	return zone.decor_at(_local(t)) if zone != null else ""


func _city_dist(t: Vector2i) -> float:
	return (Vector2(t) + Vector2(0.5, 0.5) - CITY_CENTER).length()


func _building_cells() -> Dictionary:
	## World tile -> house/shop decor id for every building part on the floor.
	var cells := {}
	for chunk_id: String in world.chunk_ids():
		var zone: Zone = zones[chunk_id]
		for y in range(zone.height):
			for x in range(zone.width):
				var local := Vector2i(x, y)
				var decor := zone.decor_at(local)
				if decor.begins_with("house_") or decor.begins_with("shop_"):
					cells[world.chunk_to_world(chunk_id, local)] = decor
	return cells


func _building_kind(decor_id: String) -> String:
	if decor_id.begins_with("house_"):
		return "house"
	if decor_id.begins_with("shop_"):
		return "shop"
	return ""


func _part_kind(decor_id: String) -> String:
	if decor_id.begins_with("shop_"):
		return decor_id.trim_prefix("shop_").split("_")[0]
	var parts := decor_id.split("_")
	return parts[2] if parts.size() > 2 else ""


func _components(cells: Dictionary) -> Array:
	## 4-connected groups of building cells.
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


func _rect(comp: Array) -> Rect2i:
	var min_t: Vector2i = comp[0]
	var max_t: Vector2i = comp[0]
	for t: Vector2i in comp:
		min_t = Vector2i(mini(min_t.x, t.x), mini(min_t.y, t.y))
		max_t = Vector2i(maxi(max_t.x, t.x), maxi(max_t.y, t.y))
	return Rect2i(min_t, max_t - min_t + Vector2i.ONE)


func _component_kind(comp: Array, cells: Dictionary) -> String:
	return _building_kind(str(cells[comp[0]]))


func _door(comp: Array, cells: Dictionary) -> Vector2i:
	for t: Vector2i in comp:
		if _part_kind(str(cells[t])) == "door":
			return t
	return Vector2i(-1, -1)


func _rect_key(rect: Rect2i) -> String:
	return "%d,%d,%d,%d" % [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


func _mirror_rect(rect: Rect2i) -> Rect2i:
	return Rect2i(Vector2i(192 - (rect.position.x + rect.size.x), rect.position.y), rect.size)


func _beside_road(t: Vector2i) -> bool:
	for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if _type(t + step) == "road":
			return true
	return false


func test_building_parts_exist_in_tileset_and_atlas() -> void:
	var ts := TilesetData.load_file(TILESET_PATH)
	var tex: Texture2D = load(ATLAS_PATH) as Texture2D
	assert_not_null(tex, "world_tiles.png must import as a Texture2D")
	if tex == null:
		return
	var img := tex.get_image()
	var cols := img.get_width() / TILE_PX
	var rows := img.get_height() / TILE_PX

	var cells := _building_cells()
	assert_gt(cells.size(), 0, "the city uses multi-tile building parts")
	var kinds := {}
	for t: Vector2i in cells.keys():
		var decor := str(cells[t])
		kinds[_building_kind(decor)] = true
		assert_true(ts.has_decor(decor), "building part '%s' must be in the floor1 tileset" % decor)
		if not ts.has_decor(decor):
			continue
		var c := ts.decor_coords(decor)
		assert_between(c.x, 0, cols - 1, "building part '%s' x inside the atlas" % decor)
		assert_between(c.y, 0, rows - 1, "building part '%s' y inside the atlas" % decor)
	assert_true(kinds.has("house"), "the city has house parts")
	assert_true(kinds.has("shop"), "the city has shop parts")


func test_every_building_is_a_solid_rectangle_of_its_size() -> void:
	var cells := _building_cells()
	var comps := _components(cells)
	assert_gte(comps.size(), MIN_BUILDINGS, "the city has several big buildings")
	var size_counts := {}
	var house_variants := {}
	var shops := 0
	for comp: Array in comps:
		var rect := _rect(comp)
		var kind := _component_kind(comp, cells)
		var allowed: Array = HOUSE_SIZES if kind == "house" else SHOP_SIZES
		assert_eq(comp.size(), rect.size.x * rect.size.y, "%s at %s must be a solid rectangle" % [kind, str(rect.position)])
		assert_true(allowed.has(rect.size), "%s at %s is %s, got %s" % [kind, str(rect.position), str(allowed), str(rect.size)])
		size_counts[rect.size] = int(size_counts.get(rect.size, 0)) + 1
		if kind == "shop":
			shops += 1
	for decor_id: Variant in cells.values():
		var id := str(decor_id)
		if id.begins_with("house_"):
			house_variants[id.split("_")[1]] = true
	assert_true(size_counts.has(Vector2i(8, 6)), "8x6 houses exist")
	assert_true(size_counts.has(Vector2i(7, 5)), "7x5 buildings exist")
	assert_true(house_variants.has("a") and house_variants.has("b"), "both house palettes are used")
	assert_between(float(shops) / comps.size(), 0.2, 0.5, "roughly a third of the buildings are shops")


func test_every_building_has_all_parts_and_only_the_door_is_walkable() -> void:
	var cells := _building_cells()
	for comp: Array in _components(cells):
		var kind := _component_kind(comp, cells)
		var required: Array = HOUSE_PARTS if kind == "house" else SHOP_PARTS
		var kinds := {}
		var doors: Array[Vector2i] = []
		var bottom := -1
		for t: Vector2i in comp:
			var part := _part_kind(str(cells[t]))
			kinds[part] = true
			if part == "door":
				doors.append(t)
			bottom = maxi(bottom, t.y)
		for part: String in required:
			assert_true(kinds.has(part), "%s at %s has a %s part" % [kind, str(comp[0]), part])
		assert_eq(doors.size(), 1, "%s at %s has exactly one door" % [kind, str(comp[0])])
		if doors.size() != 1:
			continue
		var door := doors[0]
		assert_eq(door.y, bottom, "%s door faces south" % kind)
		assert_true(_walkable(door), "door cell %s is walkable" % str(door))
		assert_true(_walkable(door + Vector2i.DOWN), "door %s opens onto town floor" % str(door))
		assert_eq(_decor(door + Vector2i.DOWN), "", "door approach %s stays open" % str(door + Vector2i.DOWN))
		assert_true(_walkable(door + Vector2i.DOWN * 2), "door %s opens onto a two tile alley" % str(door))
		for t: Vector2i in comp:
			if t != door:
				assert_false(_walkable(t), "%s tile %s is blocked" % [kind, str(t)])


func test_buildings_keep_off_roads_hub_wall_and_tower() -> void:
	var cells := _building_cells()
	assert_gt(cells.size(), 0, "the city keeps its buildings")
	for t: Vector2i in cells.keys():
		assert_eq(_type(t), "town_floor", "building tile %s sits on town floor" % str(t))
		assert_true(_safe(t), "building tile %s is safe" % str(t))
		assert_lte(_city_dist(t), HOUSE_MAX_CITY_DIST, "building tile %s stays inside the city core" % str(t))
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var around := t + Vector2i(dx, dy)
				assert_ne(_type(around), "road", "building at %s keeps road tile %s clear" % [str(t), str(around)])
				assert_gt(_city_dist(around), HUB_RADIUS, "building at %s keeps the hub clear" % str(t))


func test_four_quarters_hold_the_same_number_of_buildings() -> void:
	var cells := _building_cells()
	var counts := {"NW": 0, "NE": 0, "SW": 0, "SE": 0}
	for comp: Array in _components(cells):
		var door := _door(comp, cells)
		if door.x < 0:
			continue
		var side := "N" if door.y < ROAD_Y_MIN else "S"
		var half := "W" if door.x < ROAD_X_MIN else "E"
		counts[side + half] = int(counts[side + half]) + 1
	assert_gt(int(counts["NW"]), 0, "the north-west quarter holds buildings")
	for key: String in counts.keys():
		assert_eq(int(counts[key]), int(counts["NW"]), "quarter %s holds as many buildings as NW" % key)


func test_west_and_east_quarters_mirror_each_other() -> void:
	var cells := _building_cells()
	var kinds := {}
	var rects := {}
	for comp: Array in _components(cells):
		var rect := _rect(comp)
		var key := _rect_key(rect)
		kinds[key] = _component_kind(comp, cells)
		rects[key] = rect
	for key: String in rects.keys():
		var mirrored := _rect_key(_mirror_rect(rects[key]))
		assert_true(kinds.has(mirrored), "building %s mirrors to %s" % [key, mirrored])
		if kinds.has(mirrored):
			assert_eq(str(kinds[mirrored]), str(kinds[key]), "building %s keeps its type when mirrored" % key)


func test_roads_and_gates_stay_fully_walkable() -> void:
	var roads := 0
	var gates := 0
	for y in range(MAP_H):
		for x in range(MAP_W):
			var t := Vector2i(x, y)
			var type := _type(t)
			if type == "road":
				roads += 1
				assert_true(_walkable(t), "road tile %s is walkable" % str(t))
				assert_true(_safe(t), "road tile %s is safe" % str(t))
			elif type == "gate":
				gates += 1
				assert_true(_walkable(t), "gate tile %s is walkable" % str(t))
	assert_gt(roads, 0, "the city keeps its roads")
	assert_gt(gates, 0, "the city keeps its gates")


func test_road_decorations_dress_town_floor_beside_roads() -> void:
	var counts := {"torch": 0, "barrel": 0, "crate": 0}
	var road_torches := 0
	for y in range(MAP_H):
		for x in range(MAP_W):
			var t := Vector2i(x, y)
			var decor := _decor(t)
			if not counts.has(decor):
				continue
			counts[decor] = int(counts[decor]) + 1
			assert_false(_walkable(t), "%s at %s blocks the tile" % [decor, str(t)])
			assert_ne(_type(t), "road", "%s at %s stays off the roads" % [decor, str(t)])
			if _type(t) != "town_floor":
				continue
			if decor == "torch":
				if _beside_road(t):
					road_torches += 1
			else:
				assert_true(_beside_road(t), "%s at %s stands beside a road" % [decor, str(t)])
	for decor: String in counts.keys():
		assert_gt(int(counts[decor]), 0, "the city has %s decorations" % decor)
	assert_gt(road_torches, 0, "torches dress the roads")


func test_buildings_leave_the_plaza_merchant_entry_and_fountain_open() -> void:
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


func test_entry_reaches_every_building_door() -> void:
	var chunked := ChunkedWorld.load_file(WORLD_PATH, ZONES_DIR)
	assert_true(chunked.is_valid(), "chunked world errors: %s" % str(chunked.errors))
	var start := chunked.start_entry()

	var cells := _building_cells()
	var doors: Array[Vector2i] = []
	for comp: Array in _components(cells):
		var door := _door(comp, cells)
		if door.x >= 0:
			doors.append(door)
	assert_gt(doors.size(), 0, "the city has building doors")

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
		assert_true(seen.has(door), "entry reaches building door at %s" % str(door))
