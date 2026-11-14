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
##
## JGT-105: a per-animation layer spec may also hold two reserved, non-animation keys:
## - "tint": a colour ("#rrggbb", "#rrggbbaa" or [r, g, b(, a)] in 0..1) that the view
##   multiplies into the layer (LayeredSprite layer self_modulate), e.g. to turn a grey
##   LPC recolour base black. Only applied to LPC layers, never to the placeholders.
## - "frame_sizes": {anim: [w, h]} for source files whose frames are bigger than the
##   layout frame (LPC "oversize" weapon slashes use 192px frames with the character in
##   the centre); the centred layout-sized region of each frame is used.

const DEFAULT_APPEARANCES_PATH: String = "res://data/appearances.json"
const DEFAULT_DIRECTION_ORDER: Array = ["up", "left", "down", "right"]

const SOURCE_LPC: String = "lpc"
const SOURCE_PLACEHOLDER: String = "placeholder"
const SOURCE_NONE: String = "none"

const KEY_TINT: String = "tint"
const KEY_FRAME_SIZES: String = "frame_sizes"
## Layer spec keys that are not animation files.
const RESERVED_LAYER_KEYS: Array[String] = [KEY_TINT, KEY_FRAME_SIZES]


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
## their frames and rows. src_frame_sizes {anim_name: Vector2i} names source files whose
## frames are bigger than the layout frame (centre region is used). Pure (no scene tree).
static func compose_stacked(anim_images: Dictionary, layout: Dictionary, src_frame_sizes: Dictionary = {}) -> Image:
	var fs := frame_size(layout)
	var grid := stacked_grid(layout)
	var out := Image.create_empty(grid.x * fs.x, grid.y * fs.y, false, Image.FORMAT_RGBA8)
	var anims: Dictionary = layout.get("animations", {})

	# Pass 1: blit every animation that has its own (or aliased) source image.
	for anim_name: Variant in anims.keys():
		var info: Dictionary = anims[anim_name]
		var src_name := _source_name_for(str(anim_name), info, anim_images)
		if src_name.is_empty():
			continue
		var src_fs: Vector2i = src_frame_sizes.get(src_name, fs)
		_blit_anim(out, anim_images[src_name] as Image, info, layout, fs, src_fs)

	# Pass 2: fill animations without art from their fallback frame.
	for anim_name: Variant in anims.keys():
		var info: Dictionary = anims[anim_name]
		if not _source_name_for(str(anim_name), info, anim_images).is_empty():
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


## Resolves an appearance entry into
## {"source": String, "layers": {layer: Texture2D}, "tints": {layer: Color}}.
## Tries the per-animation LPC "layers" first; if any required file is missing it uses the
## stacked "fallback" placeholder sheets; if nothing loads, source is SOURCE_NONE.
## "tints" only holds LPC layers that declare a "tint" (empty for placeholders).
static func build_textures(entry: Dictionary, layout: Dictionary) -> Dictionary:
	var images := build_images(entry, layout)
	var textures: Dictionary = {}
	var layer_images: Dictionary = images.get("layers", {})
	for layer_name: Variant in layer_images.keys():
		textures[layer_name] = ImageTexture.create_from_image(layer_images[layer_name])
	return {"source": images.get("source", SOURCE_NONE), "layers": textures, "tints": images.get("tints", {})}


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
			var out_tints: Dictionary = {}
			var ok := true
			for layer_name: Variant in lpc_layers.keys():
				var files: Dictionary = lpc_layers[layer_name]
				var anim_images: Dictionary = {}
				for anim_name: Variant in files.keys():
					if RESERVED_LAYER_KEYS.has(str(anim_name)):
						continue
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
				out_layers[str(layer_name)] = compose_stacked(anim_images, layout, parse_frame_sizes(files.get(KEY_FRAME_SIZES, null)))
				if files.has(KEY_TINT):
					out_tints[str(layer_name)] = parse_tint(files[KEY_TINT])
			if ok:
				return {"source": SOURCE_LPC, "layers": out_layers, "tints": out_tints}
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
		return {"source": SOURCE_NONE, "layers": {}, "tints": {}}
	return {"source": SOURCE_PLACEHOLDER, "layers": fb_layers, "tints": {}}


## Parses a layer "tint": "#rrggbb" / "#rrggbbaa" / [r, g, b(, a)] (0..1). Anything else
## gives Color.WHITE (no tint) with a warning.
static func parse_tint(value: Variant) -> Color:
	if value is String:
		var text := (value as String).strip_edges()
		if text.begins_with("#") and Color.html_is_valid(text):
			return Color.html(text)
	elif value is Array:
		var arr: Array = value
		if arr.size() == 3 or arr.size() == 4:
			var parts: Array[float] = []
			for v: Variant in arr:
				if not (v is float or v is int):
					break
				parts.append(clampf(float(v), 0.0, 1.0))
			if parts.size() == arr.size():
				return Color(parts[0], parts[1], parts[2], parts[3] if parts.size() == 4 else 1.0)
	push_warning("CharacterAppearance: invalid tint %s; using no tint" % str(value))
	return Color.WHITE


## Parses a layer "frame_sizes" {anim: [w, h] or n} into {anim: Vector2i}; invalid
## entries are skipped (the layout frame size is used for them).
static func parse_frame_sizes(value: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not (value is Dictionary):
		return out
	var dict: Dictionary = value
	for anim_name: Variant in dict.keys():
		var v: Variant = dict[anim_name]
		var size := Vector2i.ZERO
		if v is Array and (v as Array).size() >= 2:
			size = Vector2i(int(v[0]), int(v[1]))
		elif v is float or v is int:
			size = Vector2i(int(v), int(v))
		if size.x > 0 and size.y > 0:
			out[str(anim_name)] = size
		else:
			push_warning("CharacterAppearance: invalid frame size for %s: %s" % [anim_name, str(v)])
	return out


## Name of the anim_images entry an animation is drawn from (itself, or its
## "source_anim" alias), or "" if neither has an image.
static func _source_name_for(anim_name: String, info: Dictionary, anim_images: Dictionary) -> String:
	if anim_images.has(anim_name):
		return anim_name
	var alias := str(info.get("source_anim", ""))
	if not alias.is_empty() and anim_images.has(alias):
		return alias
	return ""


## Blits one animation into the stacked sheet. src_fs is the source frame size; when it is
## bigger than the layout frame (oversize LPC sheets) the centred fs region of each source
## frame is copied.
static func _blit_anim(out: Image, src: Image, info: Dictionary, layout: Dictionary, fs: Vector2i, src_fs: Vector2i) -> void:
	src_fs = Vector2i(maxi(src_fs.x, fs.x), maxi(src_fs.y, fs.y))
	var margin := (src_fs - fs) / 2
	var rows: Dictionary = info.get("rows", {})
	var frame_count: int = int(info.get("frame_count", 1))
	var src_rows: int = maxi(1, src.get_height() / src_fs.y)
	var src_cols: int = src.get_width() / src_fs.x
	var cols: int = mini(frame_count, src_cols)
	for dir_name: Variant in rows.keys():
		var dst_row: int = int(rows[dir_name])
		var src_row: int = source_row_for(layout, str(dir_name), src_rows)
		if src_fs == fs:
			out.blit_rect(src, Rect2i(0, src_row * fs.y, cols * fs.x, fs.y), Vector2i(0, dst_row * fs.y))
			continue
		for f in range(cols):
			var src_rect := Rect2i(f * src_fs.x + margin.x, src_row * src_fs.y + margin.y, fs.x, fs.y)
			out.blit_rect(src, src_rect, Vector2i(f * fs.x, dst_row * fs.y))


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
