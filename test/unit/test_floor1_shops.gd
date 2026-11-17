extends GutTest

## JGT-136: Floor 1 shops are a distinct 8x5 / 7x5 decor set (flat parapet with
## a hanging sign band, striped awning, display window, warm timber wall and a
## door). Shops are not placed in the generated floor yet, so these tests drive
## the generator's place_shop() on a scratch grid and guard the tileset/legend
## contract used by the later placement task.

const TILESET_PATH := "res://data/tilesets/floor1.json"
const ATLAS_PATH := "res://assets/tiles/world_tiles.png"
const TILE_PX := 32
const ATLAS_COLS := 8
const ATLAS_ROWS := 7

const SHOP_DECORS := {
	"shop_parapet_l": Vector2i(5, 3),
	"shop_parapet_m": Vector2i(6, 3),
	"shop_parapet_r": Vector2i(7, 3),
	"shop_awning_l": Vector2i(2, 6),
	"shop_awning_m": Vector2i(3, 6),
	"shop_awning_r": Vector2i(4, 6),
	"shop_wall": Vector2i(5, 6),
	"shop_window": Vector2i(6, 6),
	"shop_door": Vector2i(7, 6),
}

const SHOP_ROWS := [
	"jkkkkkkl",
	"mnnnnnnp",
	"qqqqqqqq",
	"qqqrqqqq",
	"qqsqqqqq",
]

var _sample: Dictionary = {}


func before_all() -> void:
	_sample = _run_generator_check()


func _run_generator_check() -> Dictionary:
	var tools_path := ProjectSettings.globalize_path("res://tools").c_escape().replace("'", "\\'")
	var lines := PackedStringArray([
		"import json, sys",
		"sys.path.insert(0, '%s')" % tools_path,
		"import gen_floor1_layout as g",
		"",
		"def blank():",
		"    return [['T'] * g.WIDTH for _ in range(g.HEIGHT)]",
		"",
		"def raises(fn):",
		"    try:",
		"        fn()",
		"    except AssertionError:",
		"        return True",
		"    return False",
		"",
		"grid = blank()",
		"shop = g.place_shop(grid, 90, 55, 8, 5, 2, 'm')",
		"overlap = blank()",
		"overlap[56][92] = '#'",
		"blocked = blank()",
		"blocked[60][92] = '.'",
		"print(json.dumps({",
		"    'shop': shop,",
		"    'approach': [90 + shop['door_i'], 55 + shop['h']],",
		"    'parts': g.SHOP_PART_CHARS,",
		"    'legend': {ch: g.LEGEND[ch] for ch in 'jklmnprqs'},",
		"    'rows': [''.join(row[88:100]) for row in grid[53:62]],",
		"    'overlap_raises': raises(lambda: g.place_shop(overlap, 90, 55, 8, 5, 2, 'm')),",
		"    'blocked_raises': raises(lambda: g.place_shop(blocked, 90, 55, 8, 5, 2, 'm')),",
		"}))",
	])
	var output: Array = []
	var exit_code := OS.execute("python3", PackedStringArray(["-B", "-c", "\n".join(lines)]), output, true)
	assert_eq(exit_code, 0, "the generator shop check must run; output: %s" % str(output))
	if exit_code != 0 or output.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(str(output[0]))
	assert_true(parsed is Dictionary, "the generator check must print JSON; output: %s" % str(output))
	if not (parsed is Dictionary):
		return {}
	return parsed as Dictionary


func _cell_data(img: Image, cell: Vector2i) -> PackedByteArray:
	var region := Rect2i(cell.x * TILE_PX, cell.y * TILE_PX, TILE_PX, TILE_PX)
	return img.get_region(region).get_data()


func test_shop_parts_are_defined_and_distinct_from_houses() -> void:
	var ts := TilesetData.load_file(TILESET_PATH)
	var tex: Texture2D = load(ATLAS_PATH) as Texture2D
	assert_not_null(tex, "world_tiles.png must import as a Texture2D")
	if tex == null:
		return
	var img := tex.get_image()

	var house_cells: Array[Vector2i] = []
	for decor_id: String in ts.decor.keys():
		if decor_id.begins_with("house_"):
			house_cells.append(ts.decor_coords(decor_id))

	var seen := {}
	for decor_id: String in SHOP_DECORS.keys():
		assert_true(ts.has_decor(decor_id), "%s decor is defined" % decor_id)
		if not ts.has_decor(decor_id):
			continue
		var cell: Vector2i = ts.decor_coords(decor_id)
		assert_eq(cell, SHOP_DECORS[decor_id], "%s keeps its atlas cell" % decor_id)
		assert_between(cell.x, 0, ATLAS_COLS - 1, "%s x inside the atlas" % decor_id)
		assert_between(cell.y, 0, ATLAS_ROWS - 1, "%s y inside the atlas" % decor_id)
		assert_false(seen.has(cell), "%s reuses another shop cell" % decor_id)
		seen[cell] = true
		for house_cell: Vector2i in house_cells:
			assert_ne(cell, house_cell, "%s must not reuse a house cell" % decor_id)
			assert_ne(
				_cell_data(img, cell),
				_cell_data(img, house_cell),
				"%s art must differ from every house part" % decor_id
			)


func test_shop_legend_entries_and_only_door_walkable() -> void:
	assert_false(_sample.is_empty(), "generator check returned no data")
	if _sample.is_empty():
		return
	var parts: Dictionary = _sample.get("parts", {})
	var legend: Dictionary = _sample.get("legend", {})
	assert_gt(parts.size(), 0, "shop part chars are defined")
	var walkable: Array[String] = []
	for variant: Variant in parts.keys():
		var variant_parts: Dictionary = parts[variant]
		for part: Variant in variant_parts.keys():
			var ch := str(variant_parts[part])
			assert_true(legend.has(ch), "shop part '%s' has a legend entry" % str(part))
			if not legend.has(ch):
				continue
			var entry: Dictionary = legend[ch]
			assert_eq(str(entry.get("type", "")), "town_floor", "shop part '%s' sits on town floor" % str(part))
			assert_eq(bool(entry.get("safe", false)), true, "shop part '%s' is safe" % str(part))
			assert_eq(str(entry.get("decor", "")), "shop_" + str(part), "shop part '%s' decor id" % str(part))
			assert_eq(
				bool(entry.get("walkable", false)),
				str(part) == "door",
				"only the shop door is walkable, not '%s'" % str(part)
			)
			if str(part) == "door":
				walkable.append(ch)
	assert_eq(walkable.size(), 1, "exactly one shop part is walkable")


func test_place_shop_scratch_grid_writes_parts_and_door_approach() -> void:
	assert_false(_sample.is_empty(), "generator check returned no data")
	if _sample.is_empty():
		return
	var shop: Dictionary = _sample.get("shop", {})
	assert_eq(Vector2i(int(shop.get("x", -1)), int(shop.get("y", -1))), Vector2i(90, 55))
	assert_eq(int(shop.get("w", 0)), 8, "scratch shop is 8 wide")
	assert_eq(int(shop.get("h", 0)), 5, "scratch shop is 5 tall")
	assert_eq(int(shop.get("door_i", -1)), 2, "scratch shop door column")

	var rows: Array = _sample.get("rows", [])
	assert_eq(rows.size(), 9, "scratch window rows")
	for j in SHOP_ROWS.size():
		var actual := str(rows[j + 2]).substr(2, 8)
		assert_eq(actual, SHOP_ROWS[j], "shop row %d parts" % j)

	var approach: Array = _sample.get("approach", [])
	assert_eq(approach.size(), 2, "door approach is reported")
	if approach.size() != 2:
		return
	var ax := int(approach[0]) - 88
	var ay := int(approach[1]) - 53
	assert_eq(str(rows[ay]).substr(ax, 1), "T", "door approach stays walkable town floor")
	assert_true(bool(_sample.get("overlap_raises", false)), "place_shop rejects a non-town-floor footprint tile")
	assert_true(bool(_sample.get("blocked_raises", false)), "place_shop rejects a door facing grass")

	var seen := {Vector2i(0, 0): true}
	var queue: Array[Vector2i] = [Vector2i(0, 0)]
	var head := 0
	while head < queue.size():
		var tile := queue[head]
		head += 1
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n := tile + step
			if n.x < 0 or n.y < 0 or n.x >= 12 or n.y >= 9 or seen.has(n):
				continue
			if str(rows[n.y]).substr(n.x, 1) != "T" and str(rows[n.y]).substr(n.x, 1) != "s":
				continue
			seen[n] = true
			queue.append(n)
	assert_true(seen.has(Vector2i(ax, ay)), "door approach %s is reachable" % str(Vector2i(ax, ay)))
	assert_true(seen.has(Vector2i(ax, ay - 1)), "shop door cell is reachable")
