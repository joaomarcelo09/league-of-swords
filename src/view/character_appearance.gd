class_name CharacterAppearance
extends RefCounted
## View-side helper that turns an appearance entry from data/appearances.json into one
## stacked Image per layer that LayeredSprite can draw with the rows of layout_lpc.json.
##
## Design (JGT-72): the fetched LPC art ships ONE file per animation (64x64 frames,
## rows = up/left/down/right, or a single row for "hurt"), while the procedural
## placeholders are ONE stacked sheet in the classic LPC layout. Instead of teaching
## LayeredSprite about several sheets, we compose the per-animation files into a single
## stacked Image per layer at load time (Image.blit_rect into the row positions declared
## by layout_lpc.json). LayeredSprite regions therefore stay identical for both sources.
##
## Animations with a "fallback" entry in the layout (e.g. idle -> walk frame 0) get their
## rows filled from the fallback frame when the source has no art for them, so the same
## layout works for the placeholders (no idle rows) and for LPC packs without idle.png.
##
## If any required animation file of any layer is missing, the whole appearance falls back
## to the placeholder sheets (one push_warning, no crash). If those are missing too, the
## result has source "none" and the caller keeps its non-sprite marker.

const DEFAULT_APPEARANCES_PATH: String = "res://data/appearances.json"
const DEFAULT_DIRECTION_ORDER: Array = ["up", "left", "down", "right"]

const SOURCE_LPC: String = "lpc"
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


## Row of a per-animation LPC file that holds the given direction. Files with fewer
## rows than directions (e.g. hurt: one row) use row 0 for every direction.
static func source_row_for(layout: Dictionary, dir_name: String, source_rows: int) -> int:
	var order: Array = layout.get("lpc_direction_order", DEFAULT_DIRECTION_ORDER)
	var idx: int = order.find(dir_name)
	if idx < 0 or idx >= source_rows:
		return 0
	return idx


## Returns the list of animation file keys (in the per-layer dict) that must exist for
## an LPC layer to be usable: every layout animation that has no "fallback" and is not
## an alias ("source_anim") of another animation.
static func required_anims(layout: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var anims: Dictionary = layout.get("animations", {})
	for anim_name: Variant in anims.keys():
		var info: Dictionary = anims[anim_name]
		if info.has("fallback") or info.has("source_anim"):
			continue
		out.append(str(anim_name))
	out.sort()
	return out


## Returns the first missing file path of a per-animation layer spec, or "" if complete.
static func first_missing_file(layer_files: Dictionary, layout: Dictionary) -> String:
	for anim_name: String in required_anims(layout):
		var path := str(layer_files.get(anim_name, "")).strip_edges()
		if path.is_empty():
			return "<%s: no path>" % anim_name
		if not file_exists(path):
			return path
	return ""


## True if the file exists either as raw file or as an imported resource.
static func file_exists(path: String) -> bool:
	return FileAccess.file_exists(path) or ResourceLoader.exists(path)


## Loads an Image from a res:// path. Uses the imported texture when available (works in
## exports); falls back to reading the raw PNG (freshly fetched, not yet imported art).
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


## Composes per-animation images {anim_name: Image} into one stacked Image laid out by
## layout rows. Animations without an image but with a "source_anim" use that image
## (e.g. death -> hurt); with a "fallback" {anim, frame} they copy that frame into all
## their frames and rows. Pure (no scene tree).
static func compose_stacked(anim_images: Dictionary, layout: Dictionary) -> Image:
	var fs := frame_size(layout)
	var grid := stacked_grid(layout)
	var out := Image.create_empty(grid.x * fs.x, grid.y * fs.y, false, Image.FORMAT_RGBA8)
	var anims: Dictionary = layout.get("animations", {})

	# Pass 1: blit every animation that has its own (or aliased) source image.
	for anim_name: Variant in anims.keys():
		var info: Dictionary = anims[anim_name]
		var src: Image = _source_image_for(str(anim_name), info, anim_images)
		if src == null:
			continue
		_blit_anim(out, src, info, layout, fs)

	# Pass 2: fill animations without art from their fallback frame.
	for anim_name: Variant in anims.keys():
		var info: Dictionary = anims[anim_name]
		if _source_image_for(str(anim_name), info, anim_images) != null:
			continue
		var fb: Variant = info.get("fallback", null)
		if not (fb is Dictionary):
			continue
		_fill_from_fallback(out, info, fb as Dictionary, anims, fs)
	return out


## Same as compose_stacked but for a single already-stacked sheet (the placeholders):
## copies it and fills rows of animations with a "fallback" that lie outside the sheet.
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
## Tries the per-animation LPC "layers" first; if any required file is missing it uses the
## stacked "fallback" placeholder sheets; if nothing loads, source is SOURCE_NONE.
static func build_textures(entry: Dictionary, layout: Dictionary) -> Dictionary:
	var images := build_images(entry, layout)
	var textures: Dictionary = {}
	var layer_images: Dictionary = images.get("layers", {})
	for layer_name: Variant in layer_images.keys():
		textures[layer_name] = ImageTexture.create_from_image(layer_images[layer_name])
	return {"source": images.get("source", SOURCE_NONE), "layers": textures}


## Like build_textures but returns Images (pure; used by tests).
static func build_images(entry: Dictionary, layout: Dictionary) -> Dictionary:
	var lpc_layers: Dictionary = entry.get("layers", {})
	if not lpc_layers.is_empty():
		var missing := ""
		for layer_name: Variant in lpc_layers.keys():
			var files: Variant = lpc_layers[layer_name]
			if not (files is Dictionary):
				missing = "<%s: invalid spec>" % layer_name
				break
			missing = first_missing_file(files as Dictionary, layout)
			if not missing.is_empty():
				break

		if missing.is_empty():
			var out_layers: Dictionary = {}
			var ok := true
			for layer_name: Variant in lpc_layers.keys():
				var files: Dictionary = lpc_layers[layer_name]
				var anim_images: Dictionary = {}
				for anim_name: Variant in files.keys():
					var path := str(files[anim_name]).strip_edges()
					if path.is_empty() or not file_exists(path):
						continue  # optional animation (e.g. idle) not present
					var img := load_image(path)
					if img == null:
						ok = false
						missing = path
						break
					anim_images[str(anim_name)] = img
				if not ok:
					break
				out_layers[str(layer_name)] = compose_stacked(anim_images, layout)
			if ok:
				return {"source": SOURCE_LPC, "layers": out_layers}
		push_warning("CharacterAppearance: LPC art missing (%s); using placeholder sheets" % missing)

	var fallback: Dictionary = entry.get("fallback", {})
	var fb_layers: Dictionary = {}
	for layer_name: Variant in fallback.keys():
		var path := str(fallback[layer_name]).strip_edges()
		if path.is_empty() or not file_exists(path):
			continue
		var img := load_image(path)
		if img == null:
			continue
		fb_layers[str(layer_name)] = extend_stacked(img, layout)
	if fb_layers.is_empty():
		push_warning("CharacterAppearance: no placeholder sheets could be loaded")
		return {"source": SOURCE_NONE, "layers": {}}
	return {"source": SOURCE_PLACEHOLDER, "layers": fb_layers}


static func _source_image_for(anim_name: String, info: Dictionary, anim_images: Dictionary) -> Image:
	if anim_images.has(anim_name):
		return anim_images[anim_name] as Image
	var alias := str(info.get("source_anim", ""))
	if not alias.is_empty() and anim_images.has(alias):
		return anim_images[alias] as Image
	return null


static func _blit_anim(out: Image, src: Image, info: Dictionary, layout: Dictionary, fs: Vector2i) -> void:
	var rows: Dictionary = info.get("rows", {})
	var frame_count: int = int(info.get("frame_count", 1))
	var src_rows: int = maxi(1, src.get_height() / fs.y)
	var src_cols: int = src.get_width() / fs.x
	var cols: int = mini(frame_count, src_cols)
	for dir_name: Variant in rows.keys():
		var dst_row: int = int(rows[dir_name])
		var src_row: int = source_row_for(layout, str(dir_name), src_rows)
		var src_rect := Rect2i(0, src_row * fs.y, cols * fs.x, fs.y)
		out.blit_rect(src, src_rect, Vector2i(0, dst_row * fs.y))


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
