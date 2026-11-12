extends GutTest
## JGT-72: player drawn as a layered LPC character (appearance loading, stacked-sheet
## composition, idle/death rows, placeholder fallback, animation picking).
## Uses synthetic images under user:// so it passes with and without fetched LPC art.

const LAYOUT_PATH: String = "res://data/sprites/layout_lpc.json"
const APPEARANCES_PATH: String = "res://data/appearances.json"
const TMP_DIR: String = "user://test_character_appearance"
const FS: int = 64

# One colour per source row (up/left/down/right) so blits can be traced.
const ROW_COLORS: Array[Color] = [Color(1, 0, 0, 1), Color(0, 1, 0, 1), Color(0, 0, 1, 1), Color(1, 1, 0, 1)]
const IDLE_COLOR: Color = Color(1, 0, 1, 1)
const HURT_COLOR: Color = Color(0, 1, 1, 1)


func _layout() -> Dictionary:
	return CharacterAppearance.load_json(LAYOUT_PATH)


## Builds a per-animation LPC-style image: `cols` frames x `rows` rows, each row filled
## with ROW_COLORS[row] (or `solid` if given), frame f marked with alpha-1 pixel at x=f.
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
	assert_true((layout["layer_draw_order"] as Array).has("head"), "head layer must be drawable")


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


# --- composition --------------------------------------------------------------------

func test_source_row_for_lpc_direction_order() -> void:
	var layout := _layout()
	assert_eq(CharacterAppearance.source_row_for(layout, "up", 4), 0)
	assert_eq(CharacterAppearance.source_row_for(layout, "left", 4), 1)
	assert_eq(CharacterAppearance.source_row_for(layout, "down", 4), 2)
	assert_eq(CharacterAppearance.source_row_for(layout, "right", 4), 3)
	assert_eq(CharacterAppearance.source_row_for(layout, "right", 1), 0, "single-row files use row 0")


func test_compose_stacked_places_rows_and_fills_idle_from_walk() -> void:
	var layout := _layout()
	var anims: Dictionary = layout["animations"]
	var img := CharacterAppearance.compose_stacked({
		"walk": _anim_image(9, 4),
		"slash": _anim_image(6, 4),
		"hurt": _anim_image(6, 1, HURT_COLOR),
	}, layout)

	var grid := CharacterAppearance.stacked_grid(layout)
	assert_eq(img.get_size(), Vector2i(grid.x * FS, grid.y * FS))

	var dirs := ["up", "left", "down", "right"]
	for i in range(4):
		var walk_row: int = int(anims["walk"]["rows"][dirs[i]])
		var slash_row: int = int(anims["slash"]["rows"][dirs[i]])
		var idle_row: int = int(anims["idle"]["rows"][dirs[i]])
		assert_eq(img.get_pixel(8 * FS + 5, walk_row * FS + 5), ROW_COLORS[i], "walk %s last frame" % dirs[i])
		assert_eq(img.get_pixel(5 * FS + 5, slash_row * FS + 5), ROW_COLORS[i], "slash %s" % dirs[i])
		# No idle art: both idle frames copy walk frame 0 of the same direction.
		assert_eq(img.get_pixel(5, idle_row * FS + 5), ROW_COLORS[i], "idle %s frame 0 from walk" % dirs[i])
		assert_eq(img.get_pixel(FS + 5, idle_row * FS + 5), ROW_COLORS[i], "idle %s frame 1 from walk" % dirs[i])
	assert_eq(img.get_pixel(5 * FS + 5, 20 * FS + 5), HURT_COLOR, "hurt/death row 20")
	# Slash has 6 frames: column 6 of its rows stays empty.
	assert_eq(img.get_pixel(6 * FS + 5, int(anims["slash"]["rows"]["down"]) * FS + 5).a, 0.0)


func test_compose_stacked_uses_idle_art_when_present() -> void:
	var layout := _layout()
	var img := CharacterAppearance.compose_stacked({
		"idle": _anim_image(2, 4, IDLE_COLOR),
		"walk": _anim_image(9, 4),
		"slash": _anim_image(6, 4),
		"hurt": _anim_image(6, 1, HURT_COLOR),
	}, layout)
	var idle_down: int = int(layout["animations"]["idle"]["rows"]["down"])
	assert_eq(img.get_pixel(FS + 5, idle_down * FS + 5), IDLE_COLOR, "idle art is used when present")


func test_extend_stacked_placeholder_gets_idle_rows() -> void:
	var layout := _layout()
	var anims: Dictionary = layout["animations"]
	# Classic stacked sheet: 13 x 21 frames, walk rows coloured per direction.
	var sheet := Image.create_empty(13 * FS, 21 * FS, false, Image.FORMAT_RGBA8)
	var dirs := ["up", "left", "down", "right"]
	for i in range(4):
		sheet.fill_rect(Rect2i(0, int(anims["walk"]["rows"][dirs[i]]) * FS, FS, FS), ROW_COLORS[i])
	var out := CharacterAppearance.extend_stacked(sheet, layout)
	assert_eq(out.get_width(), 13 * FS, "keeps placeholder width")
	assert_eq(out.get_height(), CharacterAppearance.stacked_grid(layout).y * FS, "grows to hold idle rows")
	for i in range(4):
		var idle_row: int = int(anims["idle"]["rows"][dirs[i]])
		assert_eq(out.get_pixel(FS + 5, idle_row * FS + 5), ROW_COLORS[i], "placeholder idle %s = walk frame 0" % dirs[i])


# --- appearance resolution / fallback ---------------------------------------------------

func test_appearances_json_player_default() -> void:
	var entry := CharacterAppearance.get_appearance(CharacterAppearance.load_json(APPEARANCES_PATH), "player_default")
	assert_false(entry.is_empty(), "player_default must exist")
	var layers: Dictionary = entry["layers"]
	assert_true(layers.has("body") and layers.has("head"), "body and head layers")
	for layer_name: Variant in layers.keys():
		for anim_name: String in ["walk", "slash", "hurt"]:
			assert_true(str(layers[layer_name][anim_name]).begins_with("res://assets/characters/lpc/"), "%s %s path" % [layer_name, anim_name])
	var fallback: Dictionary = entry["fallback"]
	assert_true(fallback.has("body"), "placeholder fallback must have body")
	for layer_name: Variant in fallback.keys():
		assert_true(FileAccess.file_exists(str(fallback[layer_name])) or ResourceLoader.exists(str(fallback[layer_name])), "placeholder exists: %s" % fallback[layer_name])


func test_required_anims_skip_fallback_and_alias() -> void:
	var req := CharacterAppearance.required_anims(_layout())
	assert_eq(req, ["hurt", "slash", "walk"] as Array[String], "idle (fallback) and death (alias) are optional")


func test_build_images_uses_lpc_when_all_files_exist() -> void:
	var layout := _layout()
	var files := {
		"walk": _write_png(_anim_image(9, 4), "walk.png"),
		"slash": _write_png(_anim_image(6, 4), "slash.png"),
		"hurt": _write_png(_anim_image(6, 1, HURT_COLOR), "hurt.png"),
		"idle": TMP_DIR.path_join("no_idle.png"),  # optional and missing -> walk frame 0
	}
	var res := CharacterAppearance.build_images({"layers": {"body": files, "head": files}, "fallback": {}}, layout)
	assert_eq(res["source"], CharacterAppearance.SOURCE_LPC)
	var layers: Dictionary = res["layers"]
	assert_eq(layers.size(), 2)
	var body: Image = layers["body"]
	var idle_down: int = int(layout["animations"]["idle"]["rows"]["down"])
	assert_eq(body.get_pixel(5, idle_down * FS + 5), ROW_COLORS[2], "idle falls back to walk down frame 0")


func test_build_images_falls_back_to_placeholder_when_file_missing() -> void:
	var layout := _layout()
	var present := _write_png(_anim_image(9, 4), "walk_only.png")
	var entry := {
		"layers": {"body": {"walk": present, "slash": TMP_DIR.path_join("missing_slash.png"), "hurt": present}},
		"fallback": {"body": "res://assets/characters/placeholder/body.png", "hair": "res://assets/characters/placeholder/hair.png"},
	}
	var res := CharacterAppearance.build_images(entry, layout)
	assert_eq(res["source"], CharacterAppearance.SOURCE_PLACEHOLDER, "missing LPC file -> placeholders")
	var layers: Dictionary = res["layers"]
	assert_true(layers.has("body") and layers.has("hair"))
	assert_false(layers.has("head"), "no LPC layers leak into the fallback")
	var body: Image = layers["body"]
	assert_eq(body.get_height(), CharacterAppearance.stacked_grid(layout).y * FS, "placeholder extended with idle rows")


func test_build_images_none_when_nothing_loads() -> void:
	var res := CharacterAppearance.build_images({
		"layers": {"body": {"walk": "res://does/not/exist.png"}},
		"fallback": {"body": "res://does/not/exist_either.png"},
	}, _layout())
	assert_eq(res["source"], CharacterAppearance.SOURCE_NONE)
	assert_true((res["layers"] as Dictionary).is_empty())


func test_player_default_resolves_with_or_without_fetched_art() -> void:
	var layout := _layout()
	var entry := CharacterAppearance.get_appearance(CharacterAppearance.load_json(APPEARANCES_PATH), "player_default")
	var res := CharacterAppearance.build_textures(entry, layout)
	var complete := true
	for layer_name: Variant in (entry["layers"] as Dictionary).keys():
		if not CharacterAppearance.first_missing_file(entry["layers"][layer_name], layout).is_empty():
			complete = false
	var expected := CharacterAppearance.SOURCE_LPC if complete else CharacterAppearance.SOURCE_PLACEHOLDER
	assert_eq(res["source"], expected)
	for tex: Variant in (res["layers"] as Dictionary).values():
		assert_true(tex is Texture2D)


# --- LayeredSprite with composed textures -----------------------------------------------

func test_set_layer_textures_applies_offset_and_holds_death() -> void:
	var layout := _layout()
	var sprite: LayeredSprite = autofree(LayeredSprite.new(LAYOUT_PATH))
	var tex := ImageTexture.create_from_image(CharacterAppearance.compose_stacked({"walk": _anim_image(9, 4)}, layout))
	sprite.set_layer_textures({"body": tex, "head": tex})
	assert_eq(sprite.get_child_count(), 2)
	assert_eq(sprite.get_child(0).name, "body", "draw order body first")
	assert_eq(sprite.get_child(1).name, "head")
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
	assert_false(sprite.get_layer_sprite("head").visible, "layer without texture is hidden")


# --- animator ---------------------------------------------------------------------------

func test_facing_from_vector() -> void:
	assert_eq(CharacterAnimator.facing_from_vector(Vector2(1, 0.2)), "right")
	assert_eq(CharacterAnimator.facing_from_vector(Vector2(-1, 0.5)), "left")
	assert_eq(CharacterAnimator.facing_from_vector(Vector2(0.1, 1)), "down")
	assert_eq(CharacterAnimator.facing_from_vector(Vector2(0.1, -1)), "up")
	assert_eq(CharacterAnimator.facing_from_vector(Vector2.ZERO, "left"), "left", "zero keeps fallback")


func test_pick_anim_priorities() -> void:
	assert_eq(CharacterAnimator.pick_anim("walk", true, true, true, true), "death")
	assert_eq(CharacterAnimator.pick_anim("walk", true, true, false, true), "slash")
	assert_eq(CharacterAnimator.pick_anim("slash", true, true, false, false), "slash", "slash finishes")
	assert_eq(CharacterAnimator.pick_anim("slash", false, true, false, false), "walk")
	assert_eq(CharacterAnimator.pick_anim("walk", true, false, false, false), "idle")


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
	assert_true(view.player_sprite_source in [CharacterAppearance.SOURCE_LPC, CharacterAppearance.SOURCE_PLACEHOLDER])
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
