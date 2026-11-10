class_name LayeredSprite
extends Node2D

const DEFAULT_LAYOUT_PATH: String = "res://data/sprites/layout_lpc.json"

var layout: Dictionary = {}
var current_anim: String = "walk"
var current_dir: String = "down"
var current_frame: int = 0
var frame_timer: float = 0.0
var is_playing: bool = false
var appearance: Dictionary = {}
var layer_sprites: Dictionary = {}


func _init(p_layout_path: String = DEFAULT_LAYOUT_PATH) -> void:
	if not p_layout_path.is_empty():
		load_layout(p_layout_path)


func _process(delta: float) -> void:
	if is_playing:
		advance(delta)


## Pure static helper calculating the source Rect2 for an animation, direction, and frame.
static func region_for(p_layout: Dictionary, p_anim: String, p_dir: String, p_frame: int) -> Rect2:
	var frame_w: float = float(p_layout.get("frame_width", 64.0))
	var frame_h: float = float(p_layout.get("frame_height", 64.0))
	if p_layout.has("frame_size") and p_layout["frame_size"] is Array:
		var size_arr: Array = p_layout["frame_size"]
		if size_arr.size() >= 2:
			frame_w = float(size_arr[0])
			frame_h = float(size_arr[1])

	var anims: Dictionary = p_layout.get("animations", {})
	var anim_info: Dictionary = anims.get(p_anim, {})
	var rows: Dictionary = anim_info.get("rows", {})
	var row_idx: int = int(rows.get(p_dir, 0))
	var frame_count: int = int(anim_info.get("frame_count", 1))

	var actual_frame: int = 0
	if frame_count > 0:
		actual_frame = posmod(p_frame, frame_count)
	else:
		actual_frame = p_frame

	var x: float = float(actual_frame) * frame_w
	var y: float = float(row_idx) * frame_h
	return Rect2(x, y, frame_w, frame_h)


## Loads layout data from a JSON file path.
func load_layout(path: String = DEFAULT_LAYOUT_PATH) -> bool:
	if not FileAccess.file_exists(path):
		push_error("LayeredSprite: layout file not found at " + path)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("LayeredSprite: failed to open layout file: " + path)
		return false
	var text := file.get_as_text()
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_error("LayeredSprite: failed to parse layout JSON: " + json.get_error_message())
		return false
	if not (json.data is Dictionary):
		push_error("LayeredSprite: layout JSON root must be Dictionary")
		return false
	layout = json.data
	_update_regions()
	return true


## Directly sets the layout dictionary.
func set_layout(p_layout: Dictionary) -> void:
	layout = p_layout.duplicate(true)
	_update_regions()


## Returns the list of layer names in their designated draw order.
func get_draw_order() -> Array:
	return layout.get("layer_draw_order", layout.get("layers", []))


## Returns the Sprite2D assigned to a layer, if any.
func get_layer_sprite(layer_name: String) -> Sprite2D:
	return layer_sprites.get(layer_name, null)


## Configures appearance layers from a dictionary mapping layer name to sheet path.
## Builds/updates Sprite2D nodes in draw order. Missing or empty paths are hidden.
func set_appearance(p_appearance: Dictionary) -> void:
	appearance = p_appearance.duplicate()
	var draw_order: Array = get_draw_order()
	if draw_order.is_empty():
		draw_order = p_appearance.keys()

	# Mark any currently active layer sprites as hidden if missing or empty in p_appearance
	for layer_name_var: Variant in layer_sprites.keys():
		var s_name := str(layer_name_var)
		if not p_appearance.has(s_name) or str(p_appearance[s_name]).strip_edges().is_empty():
			layer_sprites[s_name].visible = false

	# Create or update sprites for each non-empty entry in draw order
	for layer_name_var: Variant in draw_order:
		var layer_name := str(layer_name_var)
		var sheet_path := str(p_appearance.get(layer_name, "")).strip_edges()
		if sheet_path.is_empty():
			continue

		var sprite: Sprite2D = layer_sprites.get(layer_name, null)
		if sprite == null:
			sprite = Sprite2D.new()
			sprite.name = layer_name
			sprite.region_enabled = true
			add_child(sprite)
			layer_sprites[layer_name] = sprite

		var tex: Texture2D = ResourceLoader.load(sheet_path) as Texture2D
		if tex != null:
			sprite.texture = tex
			sprite.visible = true
		else:
			push_warning("LayeredSprite: could not load texture at " + sheet_path)
			sprite.visible = false

	# Ensure child nodes in the tree strictly follow draw order
	var child_idx := 0
	for layer_name_var: Variant in draw_order:
		var layer_name := str(layer_name_var)
		if layer_sprites.has(layer_name):
			var sprite: Sprite2D = layer_sprites[layer_name]
			move_child(sprite, child_idx)
			child_idx += 1

	_update_regions()


## Starts playing an animation in a given direction from frame 0.
func play(anim: String, dir: String = "") -> void:
	current_anim = anim
	if not dir.is_empty():
		current_dir = dir
	current_frame = 0
	frame_timer = 0.0
	is_playing = true
	_update_regions()


## Manually sets the current animation frame index.
func set_frame(frame_index: int) -> void:
	current_frame = frame_index
	frame_timer = 0.0
	_update_regions()


## Advances animation playback timing by delta seconds based on the layout's FPS.
func advance(dt: float) -> void:
	if dt <= 0.0:
		return
	var anims: Dictionary = layout.get("animations", {})
	var anim_data: Dictionary = anims.get(current_anim, {})
	var fps: float = float(anim_data.get("fps", 10.0))
	var frame_count: int = int(anim_data.get("frame_count", 1))
	var loop: bool = bool(anim_data.get("loop", true))

	if fps <= 0.0 or frame_count <= 0:
		return

	var frame_duration: float = 1.0 / fps
	frame_timer += dt

	while frame_timer >= frame_duration:
		frame_timer -= frame_duration
		if current_frame + 1 < frame_count:
			current_frame += 1
		elif loop:
			current_frame = 0
		else:
			current_frame = frame_count - 1
			is_playing = false
			break

	_update_regions()


func _update_regions() -> void:
	var rect := region_for(layout, current_anim, current_dir, current_frame)
	for sprite: Sprite2D in layer_sprites.values():
		if sprite != null:
			sprite.region_rect = rect
