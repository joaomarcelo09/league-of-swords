extends GutTest

const LAYOUT_PATH: String = "res://data/sprites/layout_lpc.json"
const PLACEHOLDER_BODY: String = "res://assets/characters/placeholder/body.png"
const PLACEHOLDER_HAIR: String = "res://assets/characters/placeholder/hair.png"
const PLACEHOLDER_CLOTHES: String = "res://assets/characters/placeholder/clothes.png"
const PLACEHOLDER_ARMOR: String = "res://assets/characters/placeholder/armor.png"
const PLACEHOLDER_WEAPON: String = "res://assets/characters/placeholder/weapon.png"


func _load_layout() -> Dictionary:
	var file := FileAccess.open(LAYOUT_PATH, FileAccess.READ)
	assert_not_null(file, "Layout file must be readable at " + LAYOUT_PATH)
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	assert_eq(err, OK, "Layout JSON must parse without error")
	return json.data as Dictionary


func test_layout_json_keys_complete() -> void:
	var layout := _load_layout()
	assert_eq(int(layout.get("frame_width", 0)), 64, "frame_width must be 64")
	assert_eq(int(layout.get("frame_height", 0)), 64, "frame_height must be 64")

	var draw_order: Array = layout.get("layer_draw_order", [])
	assert_gt(draw_order.size(), 0, "layer_draw_order must not be empty")
	for expected_layer in ["body", "clothes", "armor", "hair", "weapon"]:
		assert_true(draw_order.has(expected_layer), "layer_draw_order must include " + expected_layer)

	var anims: Dictionary = layout.get("animations", {})
	var expected_anims := ["walk", "slash", "hurt"]
	var expected_dirs := ["up", "left", "down", "right"]

	for anim_name in expected_anims:
		assert_true(anims.has(anim_name), "Layout must define animation: " + anim_name)
		var anim_data: Dictionary = anims[anim_name]
		assert_gt(int(anim_data.get("frame_count", 0)), 0, anim_name + " must have frame_count > 0")
		assert_gt(float(anim_data.get("fps", 0.0)), 0.0, anim_name + " must have fps > 0")
		assert_true(anim_data.has("rows"), anim_name + " must define rows")

		var rows: Dictionary = anim_data["rows"]
		for dir_name in expected_dirs:
			assert_true(rows.has(dir_name), "%s rows must define direction '%s'" % [anim_name, dir_name])

		# Verify LPC row order for directional anims: up < left < down < right
		var r_up: int = int(rows["up"])
		var r_left: int = int(rows["left"])
		var r_down: int = int(rows["down"])
		var r_right: int = int(rows["right"])
		if anim_name in ["walk", "slash"]:
			assert_true(r_up < r_left, "%s row up (%d) must precede left (%d)" % [anim_name, r_up, r_left])
			assert_true(r_left < r_down, "%s row left (%d) must precede down (%d)" % [anim_name, r_left, r_down])
			assert_true(r_down < r_right, "%s row down (%d) must precede right (%d)" % [anim_name, r_down, r_right])

	var hurt_rows: Dictionary = anims["hurt"]["rows"]
	assert_eq(int(hurt_rows["up"]), 20, "hurt row up must be 20")
	assert_eq(int(hurt_rows["left"]), 20, "hurt row left must be 20")
	assert_eq(int(hurt_rows["down"]), 20, "hurt row down must be 20")
	assert_eq(int(hurt_rows["right"]), 20, "hurt row right must be 20")


func test_region_for_all_anims_and_dirs() -> void:
	var layout := _load_layout()
	var anims: Dictionary = layout.get("animations", {})

	for anim_name in anims.keys():
		var anim_data: Dictionary = anims[anim_name]
		var rows: Dictionary = anim_data.get("rows", {})
		for dir_name in rows.keys():
			var expected_row: int = int(rows[dir_name])
			var rect: Rect2 = LayeredSprite.region_for(layout, anim_name, dir_name, 0)
			assert_eq(rect.position.x, 0.0, "Frame 0 x should be 0")
			assert_eq(rect.position.y, float(expected_row * 64), "Frame y should match row * 64")
			assert_eq(rect.size, Vector2(64, 64), "Frame size must be 64x64")


func test_region_for_hurt_directions_share_row() -> void:
	var layout := _load_layout()
	var hurt_up: Rect2 = LayeredSprite.region_for(layout, "hurt", "up", 0)
	var hurt_down: Rect2 = LayeredSprite.region_for(layout, "hurt", "down", 0)
	var hurt_left: Rect2 = LayeredSprite.region_for(layout, "hurt", "left", 0)
	var hurt_right: Rect2 = LayeredSprite.region_for(layout, "hurt", "right", 0)
	assert_eq(hurt_up.position.y, float(20 * 64), "Hurt up row y must be 20 * 64")
	assert_eq(hurt_up.position.y, hurt_down.position.y, "Hurt up and down must share the same row")
	assert_eq(hurt_left.position.y, hurt_right.position.y, "Hurt left and right must share the same row")
	assert_eq(hurt_up, hurt_down, "Hurt regions for different directions on frame 0 must be identical")


func test_region_for_last_frame() -> void:
	var layout := _load_layout()

	# Walk has 9 frames: 0..8
	var walk_last: Rect2 = LayeredSprite.region_for(layout, "walk", "down", 8)
	assert_eq(walk_last.position.x, float(8 * 64), "Walk last frame x should be 8 * 64")
	assert_eq(walk_last.size, Vector2(64, 64))

	# Slash has 6 frames: 0..5
	var slash_last: Rect2 = LayeredSprite.region_for(layout, "slash", "down", 5)
	assert_eq(slash_last.position.x, float(5 * 64), "Slash last frame x should be 5 * 64")
	assert_eq(slash_last.size, Vector2(64, 64))

	# Hurt has 6 frames: 0..5
	var hurt_last: Rect2 = LayeredSprite.region_for(layout, "hurt", "down", 5)
	assert_eq(hurt_last.position.x, float(5 * 64), "Hurt last frame x should be 5 * 64")
	assert_eq(hurt_last.size, Vector2(64, 64))


func test_region_for_frame_wrap() -> void:
	var layout := _load_layout()

	# Walk frame count = 9. Frame 9 wraps to 0, frame 10 wraps to 1, frame 18 wraps to 0
	var wrap_0: Rect2 = LayeredSprite.region_for(layout, "walk", "down", 9)
	var expected_0: Rect2 = LayeredSprite.region_for(layout, "walk", "down", 0)
	assert_eq(wrap_0, expected_0, "Frame 9 should wrap to frame 0")

	var wrap_1: Rect2 = LayeredSprite.region_for(layout, "walk", "down", 10)
	var expected_1: Rect2 = LayeredSprite.region_for(layout, "walk", "down", 1)
	assert_eq(wrap_1, expected_1, "Frame 10 should wrap to frame 1")

	var wrap_18: Rect2 = LayeredSprite.region_for(layout, "walk", "down", 18)
	assert_eq(wrap_18, expected_0, "Frame 18 should wrap to frame 0")

	# Slash frame count = 6. Frame 6 wraps to 0, frame 7 wraps to 1
	var slash_wrap_0: Rect2 = LayeredSprite.region_for(layout, "slash", "right", 6)
	var slash_expected_0: Rect2 = LayeredSprite.region_for(layout, "slash", "right", 0)
	assert_eq(slash_wrap_0, slash_expected_0, "Slash frame 6 should wrap to frame 0")

	var slash_wrap_1: Rect2 = LayeredSprite.region_for(layout, "slash", "right", 7)
	var slash_expected_1: Rect2 = LayeredSprite.region_for(layout, "slash", "right", 1)
	assert_eq(slash_wrap_1, slash_expected_1, "Slash frame 7 should wrap to frame 1")


func test_set_appearance_creates_layer_per_non_empty_entry_in_draw_order() -> void:
	var sprite: LayeredSprite = autofree(LayeredSprite.new(LAYOUT_PATH))

	# Only provide body and weapon
	sprite.set_appearance({
		"body": PLACEHOLDER_BODY,
		"weapon": PLACEHOLDER_WEAPON,
	})

	assert_eq(sprite.get_child_count(), 2, "Should create exactly 2 Sprite2D nodes for 2 entries")

	var body_sprite := sprite.get_layer_sprite("body")
	var weapon_sprite := sprite.get_layer_sprite("weapon")
	assert_not_null(body_sprite, "Body sprite must exist")
	assert_not_null(weapon_sprite, "Weapon sprite must exist")

	assert_true(body_sprite.visible, "Body sprite should be visible")
	assert_true(weapon_sprite.visible, "Weapon sprite should be visible")
	assert_true(body_sprite.region_enabled, "Body sprite region_enabled must be true")
	assert_true(weapon_sprite.region_enabled, "Weapon sprite region_enabled must be true")

	# Children order must follow draw order: body comes before weapon
	assert_eq(sprite.get_child(0), body_sprite, "First child must be body")
	assert_eq(sprite.get_child(1), weapon_sprite, "Second child must be weapon")


func test_set_appearance_missing_or_empty_layer_hidden() -> void:
	var sprite: LayeredSprite = autofree(LayeredSprite.new(LAYOUT_PATH))

	# Empty path should not be visible
	sprite.set_appearance({
		"body": PLACEHOLDER_BODY,
		"hair": "",
		"clothes": "   ",
	})
	assert_eq(sprite.get_child_count(), 1, "Only non-empty entries should create child sprites")
	assert_null(sprite.get_layer_sprite("hair"), "Empty hair should not have a created sprite")

	# Now set with hair
	sprite.set_appearance({
		"body": PLACEHOLDER_BODY,
		"hair": PLACEHOLDER_HAIR,
	})
	var hair_sprite := sprite.get_layer_sprite("hair")
	assert_not_null(hair_sprite, "Hair sprite must now exist")
	assert_true(hair_sprite.visible, "Hair sprite must be visible")

	# Now remove hair in subsequent appearance update
	sprite.set_appearance({
		"body": PLACEHOLDER_BODY,
	})
	assert_false(hair_sprite.visible, "Missing layer in subsequent update must become hidden")


func test_set_appearance_swapping_sheet_needs_no_code_change() -> void:
	var sprite: LayeredSprite = autofree(LayeredSprite.new(LAYOUT_PATH))

	sprite.set_appearance({"body": PLACEHOLDER_BODY})
	var body_sprite := sprite.get_layer_sprite("body")
	assert_not_null(body_sprite)
	var original_tex := body_sprite.texture
	assert_not_null(original_tex)

	# Swap to clothes sheet for body layer
	sprite.set_appearance({"body": PLACEHOLDER_CLOTHES})
	var swapped_tex := body_sprite.texture
	assert_not_null(swapped_tex)
	assert_ne(original_tex, swapped_tex, "Texture must update when sheet path is swapped")


func test_draw_order_from_layout() -> void:
	var sprite: LayeredSprite = autofree(LayeredSprite.new(LAYOUT_PATH))

	# Pass entries in reverse order
	sprite.set_appearance({
		"weapon": PLACEHOLDER_WEAPON,
		"hair": PLACEHOLDER_HAIR,
		"armor": PLACEHOLDER_ARMOR,
		"clothes": PLACEHOLDER_CLOTHES,
		"body": PLACEHOLDER_BODY,
	})

	assert_eq(sprite.get_child_count(), 5, "All 5 layers should be created")

	# In layout_lpc.json, layer_draw_order is: body, clothes, armor, hair, weapon
	var child_names: Array[String] = []
	for i in range(sprite.get_child_count()):
		child_names.append(sprite.get_child(i).name)

	var expected_order: Array[String] = ["body", "clothes", "armor", "hair", "weapon"]
	assert_eq(child_names, expected_order, "Children must strictly follow layout layer_draw_order")


func test_play_and_advance_frame_timing_from_layout() -> void:
	var sprite: LayeredSprite = autofree(LayeredSprite.new(LAYOUT_PATH))
	sprite.set_appearance({
		"body": PLACEHOLDER_BODY,
	})

	sprite.play("walk", "down")
	assert_eq(sprite.current_anim, "walk")
	assert_eq(sprite.current_dir, "down")
	assert_eq(sprite.current_frame, 0)
	assert_true(sprite.is_playing)

	var body_sprite := sprite.get_layer_sprite("body")
	var initial_rect := body_sprite.region_rect

	# Walk has fps = 8.0, so each frame is 0.125 seconds.
	# Advancing 0.05 seconds should not change frame
	sprite.advance(0.05)
	assert_eq(sprite.current_frame, 0, "Should remain on frame 0 after 0.05s")

	# Advancing another 0.08 seconds (total 0.13s >= 0.125s) should advance to frame 1
	sprite.advance(0.08)
	assert_eq(sprite.current_frame, 1, "Should advance to frame 1 after 0.13s total")
	assert_ne(body_sprite.region_rect, initial_rect, "region_rect must update on advance")

	# Advancing past all 9 frames of walk (loop = true) should loop back
	for _i in range(8):
		sprite.advance(0.125)
	assert_eq(sprite.current_frame, 0, "Looping animation should wrap back to 0")

	# Test non-looping slash animation (frame_count = 6, loop = false, fps = 12.0 -> dt = 0.0833s)
	sprite.play("slash", "right")
	assert_eq(sprite.current_frame, 0)
	# Advance 10 seconds (way past the 6 frames)
	sprite.advance(10.0)
	assert_eq(sprite.current_frame, 5, "Non-looping animation must clamp at last frame")
	assert_false(sprite.is_playing, "Non-looping animation must stop playing when finished")


func test_layered_sprite_preview_inactive_by_default() -> void:
	assert_false(LayeredSpritePreview.is_active, "LayeredSpritePreview must not be active by default")
	var main_view := MainView.new()
	autofree(main_view)
	LayeredSpritePreview.setup_if_requested(main_view)
	assert_false(LayeredSpritePreview.is_active, "LayeredSpritePreview must remain inactive without --preview=layered_sprite")
