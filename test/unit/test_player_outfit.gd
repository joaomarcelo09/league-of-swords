extends GutTest
## JGT-105: player outfit (black long coat over dark clothes, hair, sword). Checks the
## player_default layers, draw order, manifest/credits coverage of every LPC file, tint
## and oversize-frame parsing, and tinted textures on LayeredSprite. Passes with and
## without fetched LPC art (synthetic images live under user://).

const LAYOUT_PATH: String = "res://data/sprites/layout_lpc.json"
const APPEARANCES_PATH: String = "res://data/appearances.json"
const MANIFEST_PATH: String = "res://data/art_manifest.json"
const CREDITS_PATH: String = "res://assets/CREDITS.md"
const TMP_DIR: String = "user://test_player_outfit"
const FS: int = 64
const OUTFIT_LAYERS: Array[String] = ["weapon_behind", "legs", "clothes", "armor", "hair", "weapon"]


func _layout() -> Dictionary:
	return CharacterAppearance.load_json(LAYOUT_PATH)


func _player() -> Dictionary:
	return CharacterAppearance.get_appearance(CharacterAppearance.load_json(APPEARANCES_PATH), "player_default")


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


func test_player_default_has_outfit_layers() -> void:
	var layers: Dictionary = _player().get("layers", {})
	for layer_name: String in ["body", "head"] + OUTFIT_LAYERS:
		assert_true(layers.has(layer_name), "player_default must have layer " + layer_name)
	for layer_name: Variant in layers.keys():
		var spec: Dictionary = layers[layer_name]
		for anim_name: String in CharacterAppearance.required_anims(_layout()):
			assert_true(str(spec.get(anim_name, "")).begins_with("res://assets/characters/lpc/"),
				"%s needs a %s file" % [layer_name, anim_name])
	var fallback: Dictionary = _player().get("fallback", {})
	assert_true(fallback.has("clothes") and fallback.has("hair") and fallback.has("weapon"),
		"placeholder fallback must have clothes, hair and weapon")


func test_every_player_layer_is_in_draw_order() -> void:
	var order: Array = _layout().get("layer_draw_order", [])
	for layer_name: Variant in (_player()["layers"] as Dictionary).keys():
		assert_true(order.has(layer_name), "layer_draw_order must list " + str(layer_name))
	for layer_name: Variant in (_player()["fallback"] as Dictionary).keys():
		assert_true(order.has(layer_name), "layer_draw_order must list fallback " + str(layer_name))
	# Back to front: weapon behind the body, pants < shirt < coat < hair < weapon.
	var expected: Array[String] = ["weapon_behind", "body", "head", "legs", "clothes", "armor", "hair", "weapon"]
	var last := -1
	for layer_name: String in expected:
		var idx := order.find(layer_name)
		assert_gt(idx, last, "%s must draw after the previous outfit layer" % layer_name)
		last = idx


func test_player_files_are_in_manifest_and_credited() -> void:
	var manifest := CharacterAppearance.load_json(MANIFEST_PATH)
	var dests: Dictionary = {}
	for row: Variant in manifest.values():
		if row is Dictionary:
			dests[str((row as Dictionary).get("dest", ""))] = true
	var credits := FileAccess.get_file_as_string(CREDITS_PATH)
	var layers: Dictionary = _player()["layers"]
	for layer_name: Variant in layers.keys():
		var spec: Dictionary = layers[layer_name]
		for key: Variant in spec.keys():
			if CharacterAppearance.RESERVED_LAYER_KEYS.has(str(key)):
				continue
			var rel := str(spec[key]).trim_prefix("res://")
			assert_true(dests.has(rel), "art_manifest.json must pin " + rel)
			assert_true(credits.contains("`" + rel.get_base_dir() + "/`"), "CREDITS.md must credit " + rel.get_base_dir())


func test_parse_tint() -> void:
	assert_eq(CharacterAppearance.parse_tint("#ff0000"), Color(1, 0, 0, 1))
	assert_eq(CharacterAppearance.parse_tint("#00ff0080"), Color.html("#00ff0080"))
	assert_eq(CharacterAppearance.parse_tint([0.5, 0.25, 0, 1]), Color(0.5, 0.25, 0, 1))
	assert_eq(CharacterAppearance.parse_tint([2, 0, 0]), Color(1, 0, 0, 1), "components are clamped")
	assert_eq(CharacterAppearance.parse_tint("black"), Color.WHITE, "named colours are not accepted")
	assert_eq(CharacterAppearance.parse_tint("#zzzzzz"), Color.WHITE)
	assert_eq(CharacterAppearance.parse_tint([1, "x", 0]), Color.WHITE)
	assert_eq(CharacterAppearance.parse_tint(null), Color.WHITE)


func test_player_tints_are_valid_and_dark() -> void:
	var layers: Dictionary = _player()["layers"]
	var tinted := 0
	for layer_name: Variant in layers.keys():
		var spec: Dictionary = layers[layer_name]
		if not spec.has(CharacterAppearance.KEY_TINT):
			continue
		tinted += 1
		var raw := str(spec[CharacterAppearance.KEY_TINT])
		assert_true(raw.begins_with("#") and Color.html_is_valid(raw), "%s tint must be #hex" % layer_name)
		assert_lt(CharacterAppearance.parse_tint(raw).get_luminance(), 0.5, "%s tint must darken" % layer_name)
	assert_gt(tinted, 0, "the dark outfit uses at least one tint")


func test_parse_frame_sizes() -> void:
	var sizes := CharacterAppearance.parse_frame_sizes({"slash": [192, 192], "walk": 128, "hurt": [0, 5], "x": "bad"})
	assert_eq(sizes, {"slash": Vector2i(192, 192), "walk": Vector2i(128, 128)})
	assert_eq(CharacterAppearance.parse_frame_sizes(null), {})


func test_oversize_slash_uses_centre_region_and_tints_reach_build() -> void:
	var layout := _layout()
	var walk := Image.create_empty(9 * FS, 4 * FS, false, Image.FORMAT_RGBA8)
	walk.fill(Color(0, 0, 1, 1))
	var hurt := Image.create_empty(6 * FS, FS, false, Image.FORMAT_RGBA8)
	hurt.fill(Color(0, 1, 1, 1))
	var big := 3 * FS
	# Oversize slash: red margins, green centre 64px of every frame.
	var slash := Image.create_empty(6 * big, 4 * big, false, Image.FORMAT_RGBA8)
	slash.fill(Color(1, 0, 0, 1))
	for r in range(4):
		for f in range(6):
			slash.fill_rect(Rect2i(f * big + FS, r * big + FS, FS, FS), Color(0, 1, 0, 1))
	var spec := {
		"walk": _write_png(walk, "walk.png"),
		"slash": _write_png(slash, "slash_big.png"),
		"hurt": _write_png(hurt, "hurt.png"),
		"tint": "#202020",
		"frame_sizes": {"slash": [big, big]},
	}
	var res := CharacterAppearance.build_images({"layers": {"armor": spec}}, layout)
	assert_eq(res["source"], CharacterAppearance.SOURCE_LPC)
	var img: Image = res["layers"]["armor"]
	for dir_name: String in ["up", "left", "down", "right"]:
		var row: int = int(layout["animations"]["slash"]["rows"][dir_name])
		for f in range(6):
			assert_eq(img.get_pixel(f * FS + 1, row * FS + 1), Color(0, 1, 0, 1), "slash %s frame %d corner" % [dir_name, f])
			assert_eq(img.get_pixel(f * FS + FS - 1, row * FS + FS - 1), Color(0, 1, 0, 1), "slash %s frame %d far corner" % [dir_name, f])
	assert_eq(res["tints"], {"armor": Color.html("#202020")})


func test_placeholder_fallback_has_no_tints() -> void:
	var res := CharacterAppearance.build_textures({
		"layers": {"clothes": {"walk": "res://missing.png", "tint": "#000000"}},
		"fallback": {"clothes": "res://assets/characters/placeholder/clothes.png",
			"weapon": "res://assets/characters/placeholder/weapon.png"},
	}, _layout())
	assert_eq(res["source"], CharacterAppearance.SOURCE_PLACEHOLDER)
	assert_true((res["layers"] as Dictionary).has("weapon"), "placeholder sword layer loads")
	assert_eq(res["tints"], {})


func test_layered_sprite_applies_and_resets_tints() -> void:
	var sprite: LayeredSprite = autofree(LayeredSprite.new(LAYOUT_PATH))
	var img := Image.create_empty(FS, FS, false, Image.FORMAT_RGBA8)
	var tex := ImageTexture.create_from_image(img)
	var dark := Color(0.1, 0.1, 0.1, 1)
	sprite.set_layer_textures({"body": tex, "armor": tex}, {"armor": dark})
	assert_eq(sprite.get_layer_sprite("armor").self_modulate, dark)
	assert_eq(sprite.get_layer_sprite("body").self_modulate, Color.WHITE)
	assert_eq(sprite.modulate, Color.WHITE, "node modulate stays free for hit flashes")
	sprite.set_layer_textures({"body": tex, "armor": tex})
	assert_eq(sprite.get_layer_sprite("armor").self_modulate, Color.WHITE, "no tint resets the layer")


func test_player_default_builds_with_or_without_art() -> void:
	var res := CharacterAppearance.build_textures(_player(), _layout())
	assert_ne(res["source"], CharacterAppearance.SOURCE_NONE)
	var layers: Dictionary = res["layers"]
	assert_true(layers.has("weapon"), "sword layer present (LPC saber or placeholder sword)")
	assert_true(layers.has("clothes"), "clothes layer present")
	if res["source"] == CharacterAppearance.SOURCE_LPC:
		for layer_name: String in OUTFIT_LAYERS:
			assert_true(layers.has(layer_name), "LPC outfit layer " + layer_name)
		assert_true((res["tints"] as Dictionary).has("clothes"), "LPC shirt is tinted dark")
