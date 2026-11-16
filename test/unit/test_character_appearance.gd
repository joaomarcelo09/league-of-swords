extends GutTest
## JGT-72: player drawn as a layered character (appearance loading, stacked sheets,
## idle/death rows, missing-sheet handling, animation picking).
## Synthetic sheets live under user://.

const LAYOUT_PATH: String = "res://data/sprites/layout.json"
const APPEARANCES_PATH: String = "res://data/appearances.json"
const TMP_DIR: String = "user://test_character_appearance"
const FS: int = 64

# One colour per source row (up/left/down/right) so blits can be traced.
const ROW_COLORS: Array[Color] = [Color(1, 0, 0, 1), Color(0, 1, 0, 1), Color(0, 0, 1, 1), Color(1, 1, 0, 1)]
const IDLE_COLOR: Color = Color(1, 0, 1, 1)


func _layout() -> Dictionary:
	return CharacterAppearance.load_json(LAYOUT_PATH)


## Builds an image of `cols` frames x `rows` rows, each row filled with ROW_COLORS[row]
## (or `solid` if given).
func _anim_image(cols: int, rows: int, solid: Variant = null) -> Image:
	var img := Image.create_empty(cols * FS, rows * FS, false, Image.FORMAT_RGBA8)
	for r in range(rows):
		var c: Color = solid if solid is Color else ROW_COLORS[r]
		img.fill_rect(Rect2i(0, r * FS, cols * FS, FS), c)
	return img


func _write_png(img: Image, name: String) -> String:
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	var path := TMP_DIR.path_join(name)
	assert_eq(img.save_png(path), OK, "temp png must save: " + path)
	return path


func after_all() -> void:
	var dir := DirAccess.open(TMP_DIR)
	if dir != null:
		for f in dir.get_files():
			dir.remove(f)
		DirAccess.remove_absolute(TMP_DIR)


# --- layout -------------------------------------------------------------------------

func test_layout_defines_idle_and_death() -> void:
	var layout := _layout()
	var anims: Dictionary = layout["animations"]
	assert_true(anims.has("idle"), "layout must define idle")
	assert_true(anims.has("death"), "layout must define death")

	var idle: Dictionary = anims["idle"]
	assert_true(bool(idle["loop"]), "idle loops")
	assert_eq(str(idle["fallback"]["anim"]), "walk", "idle falls back to walk")
	assert_eq(int(idle["fallback"]["frame"]), 0, "idle falls back to walk frame 0")

	var death: Dictionary = anims["death"]
	assert_false(bool(death["loop"]), "death must not loop")
	assert_eq(str(death["source_anim"]), "hurt", "death uses the hurt art")
	assert_eq(death["rows"], anims["hurt"]["rows"], "death uses the hurt row")
	assert_eq(int(death["frame_count"]), int(anims["hurt"]["frame_count"]))

	assert_true(layout.has("sprite_offset"), "offset must be tunable in JSON")
	assert_true(layout.has("sprite_scale"), "scale must be tunable in JSON")
	assert_true((layout["layer_draw_order"] as Array).has("armor"), "armor layer must be drawable")


func test_region_for_idle_and_death_rows() -> void:
	var layout := _layout()
	var idle_rows: Dictionary = layout["animations"]["idle"]["rows"]
	for dir_name: String in ["up", "left", "down", "right"]:
		var r := LayeredSprite.region_for(layout, "idle", dir_name, 0)
		assert_eq(r.position.y, float(int(idle_rows[dir_name]) * FS), "idle %s row" % dir_name)
	var death_last := LayeredSprite.region_for(layout, "death", "left", 5)
	assert_eq(death_last, Rect2(5 * FS, 20 * FS, FS, FS), "death last frame = hurt row 20, frame 5")


func test_offset_and_scale_helpers() -> void:
	assert_eq(LayeredSprite.offset_from_layout({"sprite_offset": [2, -30]}), Vector2(2, -30))
	assert_eq(LayeredSprite.offset_from_layout({}), Vector2.ZERO, "missing offset defaults to zero")
	assert_eq(LayeredSprite.scale_from_layout({"sprite_scale": 1.5}), 1.5)
	assert_eq(LayeredSprite.scale_from_layout({"sprite_scale": 0}), 1.0, "non-positive scale ignored")
	assert_eq(LayeredSprite.scale_from_layout({}), 1.0)


# --- sheet extension ---------------------------------------------------------------

func test_extend_stacked_placeholder_gets_idle_rows() -> void:
	var layout := _layout()
	var anims: Dictionary = layout["animations"]
	# Stacked sheet without idle rows: 13 x 21 frames, walk rows coloured per direction.
	var sheet := Image.create_empty(13 * FS, 21 * FS, false, Image.FORMAT_RGBA8)
	var dirs := ["up", "left", "down", "right"]
	for i in range(4):
		sheet.fill_rect(Rect2i(0, int(anims["walk"]["rows"][dirs[i]]) * FS, FS, FS), ROW_COLORS[i])
	var out := CharacterAppearance.extend_stacked(sheet, layout)
	assert_eq(out.get_width(), 13 * FS, "keeps sheet width")
	assert_eq(out.get_height(), CharacterAppearance.stacked_grid(layout).y * FS, "grows to hold idle rows")
	for i in range(4):
		var idle_row: int = int(anims["idle"]["rows"][dirs[i]])
		assert_eq(out.get_pixel(5, idle_row * FS + 5), ROW_COLORS[i], "idle %s frame 0 = walk frame 0" % dirs[i])
		assert_eq(out.get_pixel(FS + 5, idle_row * FS + 5), ROW_COLORS[i], "idle %s frame 1 = walk frame 0" % dirs[i])


func test_extend_stacked_keeps_idle_rows_inside_sheet() -> void:
	var layout := _layout()
	var grid := CharacterAppearance.stacked_grid(layout)
	var sheet := Image.create_empty(13 * FS, grid.y * FS, false, Image.FORMAT_RGBA8)
	var idle_down: int = int(layout["animations"]["idle"]["rows"]["down"])
	sheet.fill_rect(Rect2i(0, idle_down * FS, 2 * FS, FS), IDLE_COLOR)
	var out := CharacterAppearance.extend_stacked(sheet, layout)
	assert_eq(out.get_pixel(FS + 5, idle_down * FS + 5), IDLE_COLOR, "idle art in the sheet is kept")


# --- appearance resolution ----------------------------------------------------------------

func test_appearances_json_player_default() -> void:
	var entry := CharacterAppearance.get_appearance(CharacterAppearance.load_json(APPEARANCES_PATH), "player_default")
	assert_false(entry.is_empty(), "player_default must exist")
	var layers: Dictionary = entry["layers"]
	assert_true(layers.has("body"), "body layer")
	for layer_name: Variant in layers.keys():
		var path := str(layers[layer_name])
		assert_true(path.begins_with("res://assets/characters/placeholder/"), "%s uses our own sheet: %s" % [layer_name, path])
		assert_true(CharacterAppearance.file_exists(path), "sheet exists: " + path)


func test_build_images_loads_every_sheet() -> void:
	var layout := _layout()
	var sheet := Image.create_empty(13 * FS, 21 * FS, false, Image.FORMAT_RGBA8)
	sheet.fill_rect(Rect2i(0, int(layout["animations"]["walk"]["rows"]["down"]) * FS, FS, FS), ROW_COLORS[2])
	var path := _write_png(sheet, "body.png")
	var res := CharacterAppearance.build_images({"layers": {"body": path, "hair": path}}, layout)
	assert_eq(res["source"], CharacterAppearance.SOURCE_PLACEHOLDER)
	var layers: Dictionary = res["layers"]
	assert_eq(layers.size(), 2)
	var body: Image = layers["body"]
	var idle_down: int = int(layout["animations"]["idle"]["rows"]["down"])
	assert_eq(body.get_pixel(5, idle_down * FS + 5), ROW_COLORS[2], "idle falls back to walk down frame 0")


func test_build_images_skips_missing_sheet() -> void:
	var layout := _layout()
	var entry := {"layers": {
		"body": "res://assets/characters/placeholder/body.png",
		"hair": TMP_DIR.path_join("missing_hair.png"),
	}}
	var res := CharacterAppearance.build_images(entry, layout)
	assert_eq(res["source"], CharacterAppearance.SOURCE_PLACEHOLDER)
	var layers: Dictionary = res["layers"]
	assert_true(layers.has("body"))
	assert_false(layers.has("hair"), "missing sheet is skipped")
	var body: Image = layers["body"]
	assert_eq(body.get_height(), CharacterAppearance.stacked_grid(layout).y * FS, "sheet extended with idle rows")


func test_build_images_none_when_nothing_loads() -> void:
	var res := CharacterAppearance.build_images({"layers": {"body": "res://does/not/exist.png"}}, _layout())
	assert_eq(res["source"], CharacterAppearance.SOURCE_NONE)
	assert_true((res["layers"] as Dictionary).is_empty())
	var empty := CharacterAppearance.build_images({}, _layout())
	assert_eq(empty["source"], CharacterAppearance.SOURCE_NONE)


func test_player_default_resolves_to_placeholder_sheets() -> void:
	var layout := _layout()
	var entry := CharacterAppearance.get_appearance(CharacterAppearance.load_json(APPEARANCES_PATH), "player_default")
	var res := CharacterAppearance.build_textures(entry, layout)
	assert_eq(res["source"], CharacterAppearance.SOURCE_PLACEHOLDER)
	assert_eq((res["layers"] as Dictionary).size(), (entry["layers"] as Dictionary).size(), "every layer loads")
	for tex: Variant in (res["layers"] as Dictionary).values():
		assert_true(tex is Texture2D)


# --- LayeredSprite with composed textures -----------------------------------------------

func test_set_layer_textures_applies_offset_and_holds_death() -> void:
	var layout := _layout()
	var sprite: LayeredSprite = autofree(LayeredSprite.new(LAYOUT_PATH))
	var tex := ImageTexture.create_from_image(CharacterAppearance.extend_stacked(_anim_image(9, 21, IDLE_COLOR), layout))
	sprite.set_layer_textures({"hair": tex, "body": tex})
	assert_eq(sprite.get_child_count(), 2)
	assert_eq(sprite.get_child(0).name, "body", "draw order body first")
	assert_eq(sprite.get_child(1).name, "hair")
	var body := sprite.get_layer_sprite("body")
	assert_eq(body.offset, LayeredSprite.offset_from_layout(layout), "offset from layout JSON")
	var scl := LayeredSprite.scale_from_layout(layout)
	assert_eq(body.scale, Vector2(scl, scl), "scale from layout JSON")

	sprite.play("death", "down")
	sprite.advance(10.0)
	assert_eq(sprite.current_frame, int(layout["animations"]["death"]["frame_count"]) - 1, "death holds last frame")
	assert_false(sprite.is_playing)
	sprite.advance(1.0)
	assert_eq(sprite.current_frame, int(layout["animations"]["death"]["frame_count"]) - 1, "still held")

	sprite.set_layer_textures({"body": tex})
	assert_false(sprite.get_layer_sprite("hair").visible, "layer without texture is hidden")


# --- animator ---------------------------------------------------------------------------

func test_facing_from_vector() -> void:
	assert_eq(CharacterAnimator.facing_from_vector(Vector2(1, 0.2)), "right")
	assert_eq(CharacterAnimator.facing_from_vector(Vector2(-1, 0.5)), "left")
	assert_eq(CharacterAnimator.facing_from_vector(Vector2(0.1, 1)), "down")
	assert_eq(CharacterAnimator.facing_from_vector(Vector2(0.1, -1)), "up")
	assert_eq(CharacterAnimator.facing_from_vector(Vector2.ZERO, "left"), "left", "zero keeps fallback")


func test_animator_drives_sprite() -> void:
	var sprite: LayeredSprite = autofree(LayeredSprite.new(LAYOUT_PATH))
	var anim := CharacterAnimator.new()
	anim.reset(Vector2(1, 1))
	anim.update(sprite, Vector2(1, 1), false)
	assert_eq(sprite.current_anim, "idle")
	anim.update(sprite, Vector2(1.2, 1), false)
	assert_eq(sprite.current_anim, "walk")
	assert_eq(sprite.current_dir, "right")
	anim.update(sprite, Vector2(1.2, 1), false, Vector2(0, -1))
	assert_eq(sprite.current_anim, "slash")
	assert_eq(sprite.current_dir, "up")
	anim.update(sprite, Vector2(1.2, 1), true)
	assert_eq(sprite.current_anim, "death")
	anim.update(sprite, Vector2(1.2, 1), true)
	assert_eq(sprite.current_anim, "death", "death is not restarted")


# --- main view ----------------------------------------------------------------------------

func test_main_view_player_is_layered_sprite() -> void:
	var view := MainView.new()
	var save_root := "user://test_saves/jgt72_%d" % int(Time.get_unix_time_from_system() * 1000.0)
	view.save_root = save_root
	view.save_slot = "jgt72_slot"
	add_child(view)
	assert_not_null(view.player_marker, "PlayerMarker exists")
	assert_not_null(view.player_sprite, "player drawn by LayeredSprite")
	assert_eq(view.player_sprite_source, CharacterAppearance.SOURCE_PLACEHOLDER)
	assert_eq(view.player_sprite.get_parent(), view.player_marker)
	assert_eq(view.player_sprite.current_anim, "idle", "player starts idle")
	assert_not_null(view.player_marker.get_node_or_null("PlayerHPBar"), "HP bar still attached")
	remove_child(view)
	view.free()
	_remove_tree(save_root)


func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for d in dir.get_directories():
		_remove_tree(path.path_join(d))
	for f in dir.get_files():
		dir.remove(f)
	DirAccess.remove_absolute(path)
