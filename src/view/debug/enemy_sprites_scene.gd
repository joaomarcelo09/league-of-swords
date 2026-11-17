extends Node2D
## Debug showcase for tools/screenshot.sh: the three Floor 1 enemies plus the boss
## Gorvak side by side on the test arena floor, one column per layout animation (idle
## fallback, walk, slash, scream, hurt, death), frozen on a representative frame. A
## fifth row repeats the boss with its phase 2 weapon layer (cleaver, targe gone) so
## both phases show in one shot; only the boss has the scream rows.
##
##   tools/screenshot.sh --scene=res://scenes/debug/enemy_sprites.tscn \
##       --frames=30 --out=.screenshots/enemy_sprites.png
##
## Art and layers come from data/appearances.json, exactly like the real enemy views.

const DATA_DIR: String = "res://data"
const APPEARANCES_PATH: String = "res://data/appearances.json"
const ARENA_MAP: String = "res://data/zones/floor1/test_arena.map"
const ARENA_JSON: String = "res://data/zones/floor1/test_arena.json"
const TILE_PX: int = 32
const CAMERA_ZOOM: float = 1.25
const CAMERA_TILE: Vector2 = Vector2(11.0, 13.0)

## Rows: the three Floor 1 regulars, Gorvak in phase 1, then the same boss with its
## phase 2 weapon layer (cleaver instead of pick and targe, see data/enemies.json).
const ENEMY_IDS: Array[String] = ["ash_stalker", "bog_slime", "cinder_bat", "thornback_warden", "thornback_warden"]
const ROW_WEAPON_LAYERS: Array[String] = ["", "", "", "", "weapon_phase2"]
const ROW_LABEL_SUFFIXES: Array[String] = ["", "", "", "", "  (phase 2)"]
const ROW_TILES: Array[float] = [5.5, 9.0, 12.5, 16.0, 19.5]
const COLUMN_TILES: Array[float] = [3.0, 6.2, 9.4, 12.6, 15.8, 19.0]
const COLUMN_ANIMS: Array[String] = ["idle", "walk", "slash", "scream", "hurt", "death"]
## Representative frame of each column (death holds its last frame).
const COLUMN_FRAMES: Array[int] = [0, 4, 3, 3, 3, 5]
## The cleaver is longer than the war pick, so strike frame 3 pushes a few tip pixels
## past the 96px cell; frame 2 is the same strike with the whole blade in frame.
const CLEAVER_SLASH_FRAME: int = 2
const PHASE2_WEAPON_LAYER: String = "weapon_phase2"

var _registry: DataRegistry = null


func _ready() -> void:
	_registry = DataRegistry.new()
	_registry.load_dir(DATA_DIR)
	_build_floor()
	_build_backdrop()
	_build_enemies()
	_build_camera()
	_add_labels()


func _build_backdrop() -> void:
	# Dim the floor so the sprites read clearly, while keeping the dungeon context.
	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color(0.04, 0.045, 0.07, 0.78)
	backdrop.position = Vector2(-256.0, -256.0)
	backdrop.size = Vector2(2048.0, 1536.0)
	add_child(backdrop)


func _build_floor() -> void:
	var zone := Zone.load_files(ARENA_MAP, ARENA_JSON)
	if zone == null:
		push_error("EnemySpritesScene: cannot load " + ARENA_MAP)
		return
	var zone_view := ZoneView.new()
	zone_view.name = "Arena"
	zone_view.setup(_registry)
	zone_view.build(zone)
	add_child(zone_view)


func _build_enemies() -> void:
	var appearances := CharacterAppearance.load_json(APPEARANCES_PATH)
	for row_idx in ENEMY_IDS.size():
		_build_row(appearances, row_idx)


func _build_row(appearances: Dictionary, row_idx: int) -> void:
	var enemy_id := ENEMY_IDS[row_idx]
	var enemy := _registry.get_entry("enemies", enemy_id)
	var appearance := CharacterAppearance.get_appearance(appearances, str(enemy.get("appearance", "")))
	var layout_path := EntityView.layout_path_for(str(enemy.get("layout", "")))
	var weapon_layer := ROW_WEAPON_LAYERS[row_idx]
	for col_idx in COLUMN_ANIMS.size():
		var anim := COLUMN_ANIMS[col_idx]
		var sprite := LayeredSprite.new(layout_path)
		if sprite.layout.is_empty():
			sprite.free()
			continue
		if not sprite.has_animation(anim):
			# Only the boss has the phase 2 scream rows; leave the other cells empty.
			sprite.free()
			continue
		var built := CharacterAppearance.build_textures(appearance, sprite.layout)
		var textures: Dictionary = built.get("layers", {})
		if not weapon_layer.is_empty() and textures.has(weapon_layer):
			# Alternate weapon sheet on the same body, like the in-game phase swap.
			textures["weapon"] = textures[weapon_layer]
		sprite.set_layer_textures(textures)
		sprite.position = _tile_centre(Vector2(COLUMN_TILES[col_idx], ROW_TILES[row_idx]))
		sprite.play(anim, AnimState.DIR_DOWN)
		var frame := COLUMN_FRAMES[col_idx]
		if anim == AnimState.ANIM_SLASH and weapon_layer == PHASE2_WEAPON_LAYER:
			frame = CLEAVER_SLASH_FRAME
		sprite.set_frame(frame)
		sprite.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(sprite)


func _build_camera() -> void:
	var camera := Camera2D.new()
	camera.name = "Camera"
	camera.position = Vector2(CAMERA_TILE.x, CAMERA_TILE.y) * float(TILE_PX)
	camera.zoom = Vector2(CAMERA_ZOOM, CAMERA_ZOOM)
	add_child(camera)
	camera.make_current()


func _add_labels() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Labels"
	add_child(layer)
	_add_label(layer, "Floor 1 enemy sprites  -  Gorvak phase 1 and phase 2  -  idle / walk / slash / scream / hurt / death", Vector2(220, 8), 20)
	for col_idx in COLUMN_ANIMS.size():
		_add_label(layer, COLUMN_ANIMS[col_idx], Vector2(_column_screen_x(col_idx) - 26, 40), 18)
	for row_idx in ENEMY_IDS.size():
		var display_name := str(_registry.get_entry("enemies", ENEMY_IDS[row_idx]).get("name", ENEMY_IDS[row_idx]))
		_add_label(layer, display_name + ROW_LABEL_SUFFIXES[row_idx], Vector2(36, _row_screen_y(ROW_TILES[row_idx]) - 16), 18)


func _add_label(layer: CanvasLayer, text: String, pos: Vector2, font_size: int) -> void:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(0.94, 0.94, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.04, 0.04, 0.07))
	label.add_theme_constant_override("outline_size", 5)
	layer.add_child(label)


func _tile_centre(tile: Vector2) -> Vector2:
	return (tile + Vector2(0.5, 0.5)) * float(TILE_PX)


func _column_screen_x(col_idx: int) -> float:
	var world_x := _tile_centre(Vector2(COLUMN_TILES[col_idx], 0.0)).x
	return 640.0 + (world_x - CAMERA_TILE.x * float(TILE_PX)) * CAMERA_ZOOM


func _row_screen_y(row_tile: float) -> float:
	var world_y := _tile_centre(Vector2(0.0, row_tile)).y
	return 360.0 + (world_y - CAMERA_TILE.y * float(TILE_PX)) * CAMERA_ZOOM

