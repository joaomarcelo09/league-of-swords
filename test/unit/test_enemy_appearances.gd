extends GutTest
## JGT-124: every enemy in data/enemies.json must point at its own appearance and the
## layer sheets behind it must exist. The three Floor 1 regulars use distinct art, and
## that art covers every animation the layout plays (walk, slash, hurt, idle fallback).

const ENEMIES_PATH: String = "res://data/enemies.json"
const APPEARANCES_PATH: String = "res://data/appearances.json"
const REGULAR_IDS: Array[String] = ["ash_stalker", "bog_slime", "cinder_bat"]
const BOSS_ID: String = "thornback_warden"
const SHEET_DIR: String = "res://assets/characters/"

var _enemies: Dictionary = {}
var _appearances: Dictionary = {}


func before_each() -> void:
	_enemies = CharacterAppearance.load_json(ENEMIES_PATH)
	_appearances = CharacterAppearance.load_json(APPEARANCES_PATH)


func test_every_enemy_has_an_existing_appearance_with_existing_sheets() -> void:
	assert_gt(_enemies.size(), 0, "enemies.json must not be empty")
	for enemy_id: Variant in _enemies.keys():
		var enemy: Dictionary = _enemies[enemy_id]
		var appearance_id := str(enemy.get("appearance", "")).strip_edges()
		assert_false(appearance_id.is_empty(), "%s must name an appearance" % enemy_id)

		var appearance := CharacterAppearance.get_appearance(_appearances, appearance_id)
		assert_false(appearance.is_empty(), "%s appearance '%s' missing" % [enemy_id, appearance_id])
		var layers: Dictionary = appearance.get("layers", {})
		assert_gt(layers.size(), 0, "%s appearance needs at least one layer" % enemy_id)
		for layer_name: Variant in layers.keys():
			var path := str(layers[layer_name])
			assert_true(path.begins_with(SHEET_DIR), "%s %s sheet is own art: %s" % [enemy_id, layer_name, path])
			assert_true(CharacterAppearance.file_exists(path), "%s sheet exists: %s" % [enemy_id, path])

		var layout_path := EntityView.layout_path_for(str(enemy.get("layout", "")))
		assert_true(FileAccess.file_exists(layout_path), "%s layout exists: %s" % [enemy_id, layout_path])


func test_floor1_regulars_use_three_distinct_appearances() -> void:
	var appearance_ids: Dictionary = {}
	var sheet_sets: Dictionary = {}
	for enemy_id: String in REGULAR_IDS:
		var enemy: Dictionary = _enemies[enemy_id]
		var appearance_id := str(enemy.get("appearance", ""))
		assert_eq(appearance_id, enemy_id, "%s uses its own appearance" % enemy_id)
		appearance_ids[appearance_id] = true

		var layers: Dictionary = CharacterAppearance.get_appearance(_appearances, appearance_id).get("layers", {})
		var paths: Array[String] = []
		for layer_name: Variant in layers.keys():
			paths.append(str(layers[layer_name]))
		paths.sort()
		assert_gt(paths.size(), 0, "%s appearance has sheets" % enemy_id)
		sheet_sets[str(paths)] = true
		for path: String in paths:
			assert_true(path.begins_with(SHEET_DIR + enemy_id + "/"), "%s draws its own sheet: %s" % [enemy_id, path])

	assert_eq(appearance_ids.size(), REGULAR_IDS.size(), "the three regulars use three different appearances")
	assert_eq(sheet_sets.size(), REGULAR_IDS.size(), "the three regulars use three different sheet sets")


func test_regular_appearances_build_every_animation() -> void:
	for enemy_id: String in REGULAR_IDS:
		var enemy: Dictionary = _enemies[enemy_id]
		var appearance := CharacterAppearance.get_appearance(_appearances, str(enemy.get("appearance", "")))
		var layout := CharacterAppearance.load_json(EntityView.layout_path_for(str(enemy.get("layout", ""))))
		assert_false(layout.is_empty(), "%s layout loads" % enemy_id)

		var built := CharacterAppearance.build_images(appearance, layout)
		var images: Dictionary = built.get("layers", {})
		var sheet: Image = images.get("body", null)
		assert_not_null(sheet, "%s body sheet builds" % enemy_id)
		if sheet == null:
			continue

		var fs := CharacterAppearance.frame_size(layout)
		for anim in [AnimState.ANIM_WALK, AnimState.ANIM_SLASH, AnimState.ANIM_HURT, AnimState.ANIM_IDLE]:
			var info: Dictionary = (layout.get("animations", {}) as Dictionary).get(anim, {})
			assert_false(info.is_empty(), "%s layout defines %s" % [enemy_id, anim])
			var rows: Dictionary = info.get("rows", {})
			for dir_name: Variant in rows.keys():
				var frame := sheet.get_region(Rect2i(0, int(rows[dir_name]) * fs.y, fs.x, fs.y))
				assert_true(_has_art(frame), "%s %s %s frame has art" % [enemy_id, anim, dir_name])


func test_boss_has_own_appearance_with_separate_weapon_layer() -> void:
	var boss: Dictionary = _enemies.get(BOSS_ID, {})
	assert_false(boss.is_empty(), "boss entry exists")
	assert_eq(str(boss.get("name", "")), "Gorvak the Ashen Warden", "boss display name")
	assert_eq(str(boss.get("appearance", "")), BOSS_ID, "boss uses its own appearance")
	assert_eq(str(boss.get("layout", "")), BOSS_ID, "boss uses its own layout")

	var appearance := CharacterAppearance.get_appearance(_appearances, BOSS_ID)
	var layers: Dictionary = appearance.get("layers", {})
	assert_true(layers.has("body"), "boss has a body sheet")
	assert_true(layers.has("weapon"), "boss draws the phase 1 weapon as its own layer")
	assert_true(layers.has("weapon_phase2"), "boss draws the phase 2 cleaver as its own layer")
	for layer_name: Variant in layers.keys():
		var path := str(layers[layer_name])
		assert_true(path.begins_with(SHEET_DIR + BOSS_ID + "/"), "boss layer is own art: %s" % path)
		assert_true(CharacterAppearance.file_exists(path), "boss sheet exists: %s" % path)

	var layout := CharacterAppearance.load_json(EntityView.layout_path_for(str(boss.get("layout", ""))))
	assert_false(layout.is_empty(), "boss layout loads")
	assert_eq(CharacterAppearance.frame_size(layout), Vector2i(96, 96), "boss uses the bigger 96px frame")

	var built := CharacterAppearance.build_images(appearance, layout)
	var images: Dictionary = built.get("layers", {})
	var fs := CharacterAppearance.frame_size(layout)
	for layer_name: String in ["body", "weapon", "weapon_phase2"]:
		var sheet: Image = images.get(layer_name, null)
		assert_not_null(sheet, "boss %s sheet builds" % layer_name)
		if sheet == null:
			continue
		for anim in [AnimState.ANIM_WALK, AnimState.ANIM_SLASH, AnimState.ANIM_HURT, AnimState.ANIM_IDLE]:
			var info: Dictionary = (layout.get("animations", {}) as Dictionary).get(anim, {})
			assert_false(info.is_empty(), "boss layout defines %s" % anim)
			var rows: Dictionary = info.get("rows", {})
			for dir_name: Variant in rows.keys():
				var frame := sheet.get_region(Rect2i(0, int(rows[dir_name]) * fs.y, fs.x, fs.y))
				assert_true(_has_art(frame), "boss %s %s %s frame has art" % [layer_name, anim, dir_name])


func test_boss_phase2_block_names_an_existing_layer_below_a_valid_threshold() -> void:
	var boss: Dictionary = _enemies.get(BOSS_ID, {})
	var phase2_val: Variant = boss.get("phase2", null)
	assert_true(phase2_val is Dictionary, "boss has a phase2 view block")
	if not (phase2_val is Dictionary):
		return
	var phase2: Dictionary = phase2_val

	var threshold: Variant = phase2.get("hp_ratio_below", null)
	assert_true(threshold is float or threshold is int, "phase2 threshold is a number")
	if threshold is float or threshold is int:
		assert_gt(float(threshold), 0.0, "phase2 threshold is above 0")
		assert_lt(float(threshold), 1.0, "phase2 threshold is below full HP")

	var layer_name := str(phase2.get("weapon_layer", "")).strip_edges()
	assert_false(layer_name.is_empty(), "phase2 names the weapon layer to swap to")
	var layers: Dictionary = CharacterAppearance.get_appearance(_appearances, str(boss.get("appearance", ""))).get("layers", {})
	assert_true(layers.has(layer_name), "appearance holds the phase 2 layer '%s'" % layer_name)
	assert_ne(layer_name, "weapon", "phase 2 does not reuse the phase 1 sheet")
	var phase2_path := str(layers.get(layer_name, ""))
	assert_true(CharacterAppearance.file_exists(phase2_path), "phase 2 sheet exists: " + phase2_path)
	assert_ne(phase2_path, str(layers.get("weapon", "")), "phase 2 draws its own sheet")


## True when the frame holds at least one non-transparent pixel.
func _has_art(frame: Image) -> bool:
	var data := frame.get_data()
	for i in range(3, data.size(), 4):
		if data[i] > 0:
			return true
	return false