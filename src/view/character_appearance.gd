class_name CharacterAppearance
extends RefCounted
## View-side helper that turns an appearance entry from data/appearances.json into one
## stacked Image per layer that LayeredSprite can draw with the rows of data/sprites/layout.json.
##
## An appearance entry is {"layers": {layer_name: "res://path/to/sheet.png"}}: one stacked
## sheet per layer (body, clothes, armor, hair, weapon), all using the same layout rows.
## Animations with a "fallback" entry in the layout (e.g. idle -> walk frame 0) get their
## rows filled from the fallback frame when they lie outside a sheet, so sheets without
## idle rows still play idle.
##
## Layers whose sheet is missing are skipped (one push_warning each, no crash). If no
## sheet loads at all, the result has source "none" and the caller keeps its non-sprite
## marker.

const DEFAULT_APPEARANCES_PATH: String = "res://data/appearances.json"

const SOURCE_PLACEHOLDER: String = "placeholder"
const SOURCE_NONE: String = "none"


## Reads a JSON object from path. Returns {} on any error (with push_warning).
static func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("CharacterAppearance: file not found " + path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("CharacterAppearance: cannot open " + path)
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not (json.data is Dictionary):
		push_warning("CharacterAppearance: invalid JSON object in " + path)
		return {}
	return json.data as Dictionary


## Returns the appearance entry with the given id, or {} if missing.
static func get_appearance(appearances: Dictionary, appearance_id: String) -> Dictionary:
	var entry: Variant = appearances.get(appearance_id, {})
	return entry as Dictionary if entry is Dictionary else {}


## Frame size [w, h] from the layout (frame_size wins over frame_width/height).
static func frame_size(layout: Dictionary) -> Vector2i:
	var w: int = int(layout.get("frame_width", 64))
	var h: int = int(layout.get("frame_height", 64))
	var size_val: Variant = layout.get("frame_size", null)
	if size_val is Array and (size_val as Array).size() >= 2:
		w = int(size_val[0])
		h = int(size_val[1])
	return Vector2i(w, h)


## Number of frame columns/rows needed for a stacked sheet holding every layout animation.
static func stacked_grid(layout: Dictionary) -> Vector2i:
	var cols: int = 1
	var rows: int = 1
	var anims: Dictionary = layout.get("animations", {})
	for anim_name: Variant in anims.keys():
		var info: Dictionary = anims[anim_name]
		cols = maxi(cols, int(info.get("frame_count", 1)))
		var anim_rows: Dictionary = info.get("rows", {})
		for dir_name: Variant in anim_rows.keys():
			rows = maxi(rows, int(anim_rows[dir_name]) + 1)
	return Vector2i(cols, rows)


## True if the file exists either as raw file or as an imported resource.
static func file_exists(path: String) -> bool:
	return FileAccess.file_exists(path) or ResourceLoader.exists(path)


## Loads an Image from a res:// path. Uses the imported texture when available (works in
## exports); falls back to reading the raw PNG (not yet imported art).
static func load_image(path: String) -> Image:
	var img: Image = null
	if ResourceLoader.exists(path):
		var tex := ResourceLoader.load(path) as Texture2D
		if tex != null:
			img = tex.get_image()
	if img == null and FileAccess.file_exists(path):
		img = Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


## Copies a stacked sheet and fills rows of animations with a "fallback" that lie
## outside the sheet (e.g. idle rows past a 21-row sheet get walk frame 0). Pure.
static func extend_stacked(sheet: Image, layout: Dictionary) -> Image:
	var fs := frame_size(layout)
	var grid := stacked_grid(layout)
	var w: int = maxi(grid.x * fs.x, sheet.get_width())
	var h: int = maxi(grid.y * fs.y, sheet.get_height())
	var out := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	out.blit_rect(sheet, Rect2i(Vector2i.ZERO, sheet.get_size()), Vector2i.ZERO)
	var sheet_rows: int = sheet.get_height() / fs.y
	var anims: Dictionary = layout.get("animations", {})
	for anim_name: Variant in anims.keys():
		var info: Dictionary = anims[anim_name]
		var fb: Variant = info.get("fallback", null)
		if not (fb is Dictionary):
			continue
		var rows: Dictionary = info.get("rows", {})
		var inside := true
		for dir_name: Variant in rows.keys():
			if int(rows[dir_name]) >= sheet_rows:
				inside = false
		if not inside:
			_fill_from_fallback(out, info, fb as Dictionary, anims, fs)
	return out


## Resolves an appearance entry into {"source": String, "layers": {layer: Texture2D}}.
## source is SOURCE_PLACEHOLDER when at least one sheet loads, else SOURCE_NONE.
static func build_textures(entry: Dictionary, layout: Dictionary) -> Dictionary:
	var images := build_images(entry, layout)
	var textures: Dictionary = {}
	var layer_images: Dictionary = images.get("layers", {})
	for layer_name: Variant in layer_images.keys():
		textures[layer_name] = ImageTexture.create_from_image(layer_images[layer_name])
	return {"source": images.get("source", SOURCE_NONE), "layers": textures}


## Like build_textures but returns Images (pure; used by tests).
static func build_images(entry: Dictionary, layout: Dictionary) -> Dictionary:
	var sheets: Variant = entry.get("layers", {})
	var out_layers: Dictionary = {}
	if sheets is Dictionary:
		for layer_name: Variant in (sheets as Dictionary).keys():
			var path := str(sheets[layer_name]).strip_edges()
			if path.is_empty() or not file_exists(path):
				push_warning("CharacterAppearance: sheet for layer '%s' missing (%s)" % [layer_name, path])
				continue
			var img := load_image(path)
			if img == null:
				push_warning("CharacterAppearance: cannot load sheet " + path)
				continue
			out_layers[str(layer_name)] = extend_stacked(img, layout)
	if out_layers.is_empty():
		push_warning("CharacterAppearance: no layer sheets could be loaded")
		return {"source": SOURCE_NONE, "layers": {}}
	return {"source": SOURCE_PLACEHOLDER, "layers": out_layers}


static func _fill_from_fallback(out: Image, info: Dictionary, fb: Dictionary, anims: Dictionary, fs: Vector2i) -> void:
	var fb_anim: Dictionary = anims.get(str(fb.get("anim", "")), {})
	var fb_rows: Dictionary = fb_anim.get("rows", {})
	var fb_frame: int = int(fb.get("frame", 0))
	var rows: Dictionary = info.get("rows", {})
	var frame_count: int = int(info.get("frame_count", 1))
	for dir_name: Variant in rows.keys():
		if not fb_rows.has(dir_name):
			continue
		var src_rect := Rect2i(fb_frame * fs.x, int(fb_rows[dir_name]) * fs.y, fs.x, fs.y)
		var frame := out.get_region(src_rect)
		var dst_row: int = int(rows[dir_name])
		for f in range(frame_count):
			out.blit_rect(frame, Rect2i(Vector2i.ZERO, fs), Vector2i(f * fs.x, dst_row * fs.y))
