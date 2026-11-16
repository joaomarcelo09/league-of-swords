extends GutTest
## JGT-105: player outfit (long coat over clothes, hair, sword). Checks the player_default
## layers point at our own placeholder sheets, the draw order, and that every layer loads.

const LAYOUT_PATH: String = "res://data/sprites/layout.json"
const APPEARANCES_PATH: String = "res://data/appearances.json"
const SHEET_DIR: String = "res://assets/characters/placeholder/"
const OUTFIT_LAYERS: Array[String] = ["body", "clothes", "armor", "hair", "weapon"]


func _layout() -> Dictionary:
	return CharacterAppearance.load_json(LAYOUT_PATH)


func _player() -> Dictionary:
	return CharacterAppearance.get_appearance(CharacterAppearance.load_json(APPEARANCES_PATH), "player_default")


func test_player_default_has_outfit_layers() -> void:
	var layers: Dictionary = _player().get("layers", {})
	for layer_name: String in OUTFIT_LAYERS:
		assert_true(layers.has(layer_name), "player_default must have layer " + layer_name)
	for layer_name: Variant in layers.keys():
		var path := str(layers[layer_name])
		assert_true(path.begins_with(SHEET_DIR), "%s must use an own placeholder sheet: %s" % [layer_name, path])
		assert_true(CharacterAppearance.file_exists(path), "sheet exists: " + path)


func test_every_player_layer_is_in_draw_order() -> void:
	var order: Array = _layout().get("layer_draw_order", [])
	for layer_name: Variant in (_player()["layers"] as Dictionary).keys():
		assert_true(order.has(layer_name), "layer_draw_order must list " + str(layer_name))
	# Back to front: body < shirt < coat < hair < weapon.
	var last := -1
	for layer_name: String in OUTFIT_LAYERS:
		var idx := order.find(layer_name)
		assert_gt(idx, last, "%s must draw after the previous outfit layer" % layer_name)
		last = idx


func test_player_default_builds_every_layer() -> void:
	var res := CharacterAppearance.build_textures(_player(), _layout())
	assert_eq(res["source"], CharacterAppearance.SOURCE_PLACEHOLDER)
	var layers: Dictionary = res["layers"]
	for layer_name: String in OUTFIT_LAYERS:
		assert_true(layers.get(layer_name) is Texture2D, "outfit layer %s loads" % layer_name)


func test_layered_sprite_draws_outfit_in_order() -> void:
	var sprite: LayeredSprite = autofree(LayeredSprite.new(LAYOUT_PATH))
	var res := CharacterAppearance.build_textures(_player(), sprite.layout)
	sprite.set_layer_textures(res["layers"])
	var names: Array[String] = []
	for i in range(sprite.get_child_count()):
		names.append(sprite.get_child(i).name)
	assert_eq(names, OUTFIT_LAYERS, "children follow layer_draw_order")
	assert_eq(sprite.modulate, Color.WHITE, "node modulate stays free for hit flashes")
