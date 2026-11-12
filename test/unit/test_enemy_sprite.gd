extends GutTest
## JGT-74: enemies with an "appearance" render as a layered LPC sprite driven by
## CharacterAnimator; without appearance/art they keep the hexagon fallback.
## Animation and death-linger tests use synthetic sheets under user:// so they pass
## with and without the fetched LPC art.

const MAP_PATH := "res://data/zones/floor1/test_arena.map"
const JSON_PATH := "res://data/zones/floor1/test_arena.json"
const DATA_DIR := "res://data"
const MANIFEST_PATH := "res://data/art_manifest.json"
const TMP_DIR := "user://test_enemy_sprite"
const ENEMY_ID := "ash_stalker"
const FS: int = 64

var _registry: DataRegistry = null
var _zone: Zone = null
var _zone_view: ZoneView = null


func before_each() -> void:
	_registry = DataRegistry.new()
	_registry.load_dir(DATA_DIR)
	_zone = Zone.load_files(MAP_PATH, JSON_PATH)
	_zone_view = ZoneView.new()
	_zone_view.setup(_registry)
	_zone_view.build(_zone)
	autofree(_zone_view)


func after_all() -> void:
	var dir := DirAccess.open(TMP_DIR)
	if dir != null:
		for f in dir.get_files():
			dir.remove(f)
		DirAccess.remove_absolute(TMP_DIR)


func _layout() -> Dictionary:
	return CharacterAppearance.load_json(LayeredSprite.DEFAULT_LAYOUT_PATH)


func _write_png(cols: int, rows: int, name: String) -> String:
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	var img := Image.create_empty(cols * FS, rows * FS, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.8, 0.8, 0.7, 1.0))
	var path := TMP_DIR.path_join(name)
	assert_eq(img.save_png(path), OK, "temp png must save: " + path)
	return path


## Points the in-memory ash_stalker appearance at synthetic sheets (art-independent).
func _use_synthetic_art() -> void:
	var files := {
		"walk": _write_png(9, 4, "walk.png"),
		"slash": _write_png(6, 4, "slash.png"),
		"hurt": _write_png(6, 1, "hurt.png"),
	}
	var entry := _registry.get_entry("appearances", ENEMY_ID)
	entry["layers"] = {"body": files.duplicate(), "head": files.duplicate()}


func _real_art_present() -> bool:
	var entry := _registry.get_entry("appearances", ENEMY_ID)
	var layers: Dictionary = entry.get("layers", {})
	if layers.is_empty():
		return false
	for layer_name: Variant in layers.keys():
		if not CharacterAppearance.first_missing_file(layers[layer_name], _layout()).is_empty():
			return false
	return true


func _new_view(session: GameSession, enemy: Entity) -> EntityView:
	var view := EntityView.new()
	add_child_autofree(view)
	view.tick_length = session.world.tick_length
	view.setup(enemy, _zone_view, _registry)
	return view


# --- data ---------------------------------------------------------------------------

func test_enemy_appearance_entries_reference_manifest_rows() -> void:
	var manifest := CharacterAppearance.load_json(MANIFEST_PATH)
	var dests: Dictionary = {}
	for row_id: Variant in manifest.keys():
		var row: Variant = manifest[row_id]
		if row is Dictionary:
			dests["res://" + str((row as Dictionary).get("dest", ""))] = true

	var enemy := _registry.get_entry("enemies", ENEMY_ID)
	var appearance_id := str(enemy.get("appearance", ""))
	assert_eq(appearance_id, ENEMY_ID, "ash_stalker must name its appearance")
	assert_true(FileAccess.file_exists(EntityView.layout_path_for(str(enemy.get("layout", "")))), "enemy layout must exist")

	var appearance := _registry.get_entry("appearances", appearance_id)
	var layers: Dictionary = appearance.get("layers", {})
	assert_true(layers.has("body") and layers.has("head"), "skeleton body + head layers")
	for layer_name: Variant in layers.keys():
		var files: Dictionary = layers[layer_name]
		for anim: String in ["idle", "walk", "slash", "hurt"]:
			var path := str(files.get(anim, ""))
			assert_true(dests.has(path), "%s/%s must be a manifest dest: %s" % [layer_name, anim, path])
			assert_true(path.contains("skeleton"), "ash_stalker uses skeleton art: " + path)
	assert_false(appearance.has("fallback"), "enemy fallback is the hexagon, not placeholder sheets")


func test_layout_path_and_death_seconds_helpers() -> void:
	assert_eq(EntityView.layout_path_for(""), LayeredSprite.DEFAULT_LAYOUT_PATH)
	assert_eq(EntityView.layout_path_for("lpc"), "res://data/sprites/layout_lpc.json")
	assert_eq(EntityView.layout_path_for("res://x/y.json"), "res://x/y.json")

	var layout := _layout()
	var death: Dictionary = layout["animations"]["death"]
	assert_almost_eq(EntityView.death_seconds_from_layout(layout), float(death["frame_count"]) / float(death["fps"]), 0.0001)
	assert_eq(EntityView.death_seconds_from_layout({}), 0.0, "no death anim -> no linger")
	assert_eq(EntityView.death_seconds_from_layout({"animations": {"death": {"fps": 0, "frame_count": 6}}}), 0.0)


# --- sprite vs hexagon --------------------------------------------------------------

func test_real_art_builds_sprite_or_falls_back_to_hexagon() -> void:
	var session := GameSession.new(_zone, _registry)
	var enemy := session.world.spawn_enemy(ENEMY_ID, Vector2i(4, 10))
	var view := _new_view(session, enemy)
	if _real_art_present():
		assert_true(view.has_sprite(), "fetched skeleton art -> layered sprite")
		assert_eq(view.sprite_source, CharacterAppearance.SOURCE_LPC)
		assert_true(view.sprite.get_parent() == view, "sprite is a child of the view")
		assert_almost_eq(view.hp_bar_y_offset, float(_layout()["hp_bar_y_offset"]), 0.001, "HP bar uses layout offset")
	else:
		assert_false(view.has_sprite(), "no art -> hexagon fallback")
		assert_eq(view.get_child_count(), 0, "hexagon draws itself, no sprite child")


func test_missing_art_falls_back_to_hexagon() -> void:
	_registry.get_entry("appearances", ENEMY_ID)["layers"] = {
		"body": {"walk": "res://nope/walk.png", "slash": "res://nope/slash.png", "hurt": "res://nope/hurt.png"},
	}
	var session := GameSession.new(_zone, _registry)
	var enemy := session.world.spawn_enemy(ENEMY_ID, Vector2i(4, 10))
	var view := _new_view(session, enemy)
	assert_false(view.has_sprite(), "missing art -> hexagon")
	assert_eq(view.death_seconds(), 0.0, "hexagon views do not linger")
	view.notify_hurt(0, session.world.tick_length)  # no crash without sprite
	view.notify_attack(Vector2.LEFT)
	view.sync()
	assert_true(view.is_hp_bar_visible())


func test_enemy_without_appearance_uses_hexagon() -> void:
	_registry.get_entry("enemies", ENEMY_ID).erase("appearance")
	var session := GameSession.new(_zone, _registry)
	var enemy := session.world.spawn_enemy(ENEMY_ID, Vector2i(4, 10))
	var view := _new_view(session, enemy)
	assert_false(view.has_sprite())

	_registry.get_entry("enemies", ENEMY_ID)["appearance"] = "no_such_appearance"
	var enemy2 := session.world.spawn_enemy(ENEMY_ID, Vector2i(6, 10))
	var view2 := _new_view(session, enemy2)
	assert_false(view2.has_sprite(), "unknown appearance id -> hexagon")


func test_synthetic_art_builds_sprite_with_layout_offsets() -> void:
	_use_synthetic_art()
	var session := GameSession.new(_zone, _registry)
	var enemy := session.world.spawn_enemy(ENEMY_ID, Vector2i(4, 10))
	var view := _new_view(session, enemy)
	assert_true(view.has_sprite())
	var layout := _layout()
	var body := view.sprite.get_layer_sprite("body")
	assert_not_null(body)
	assert_eq(body.offset, LayeredSprite.offset_from_layout(layout))
	assert_true(view.sprite.show_behind_parent, "HP bar drawn above the sprite")
	assert_almost_eq(view.hp_bar_y_offset, float(layout["hp_bar_y_offset"]), 0.001)
	assert_eq(view.sprite.current_anim, AnimState.ANIM_IDLE)


# --- animation ----------------------------------------------------------------------

func test_animation_walk_slash_hurt_death() -> void:
	_use_synthetic_art()
	var session := GameSession.new(_zone, _registry)
	var enemy := session.world.spawn_enemy(ENEMY_ID, Vector2i(4, 10))
	var view := _new_view(session, enemy)
	var spr := view.sprite

	enemy.pos += Vector2(1.0, 0.0)
	view.sync()
	assert_eq(spr.current_anim, AnimState.ANIM_WALK, "moving -> walk")
	assert_eq(spr.current_dir, AnimState.DIR_RIGHT)

	view.notify_attack(Vector2(0.0, -1.0))
	view.sync()
	assert_eq(spr.current_anim, AnimState.ANIM_SLASH, "telegraph_start -> slash")
	assert_eq(spr.current_dir, AnimState.DIR_UP, "slash faces the attack direction")

	view.now_tick = 100
	view.notify_hurt(100, session.world.tick_length)
	view.sync()
	assert_eq(spr.current_anim, AnimState.ANIM_HURT, "damage -> hurt")

	enemy.dead = true
	view.sync()
	assert_eq(spr.current_anim, AnimState.ANIM_DEATH, "dead -> death")
	assert_false(view.is_hp_bar_visible(), "HP bar hides once dead")


func test_layer_routes_sim_events_to_enemy_sprite() -> void:
	_use_synthetic_art()
	var session := GameSession.new(_zone, _registry)
	var player := session.spawn_player()
	var enemy := session.world.spawn_enemy(ENEMY_ID, Vector2i(4, 10))
	var layer := EntityLayer.new()
	add_child_autofree(layer)
	layer.setup(session, _zone_view, _registry)
	var view := layer.get_entity_view(enemy.id)
	assert_true(view.has_sprite())

	session.world.record_event({"type": "telegraph_start", "tick": session.world.tick_count, "source": enemy.id,
		"shape": "cone", "dir": Vector2.LEFT, "origin": enemy.pos, "duration_s": 0.5, "duration_ticks": 10})
	layer.sync()
	assert_eq(view.sprite.current_anim, AnimState.ANIM_SLASH)
	assert_eq(view.sprite.current_dir, AnimState.DIR_LEFT)

	session.world.apply_damage(player.id, enemy, 1.0)
	layer.sync()
	assert_eq(view.sprite.current_anim, AnimState.ANIM_HURT)


# --- death linger -------------------------------------------------------------------

func test_dead_sprite_view_lingers_for_death_animation_then_frees() -> void:
	_use_synthetic_art()
	var session := GameSession.new(_zone, _registry)
	var player := session.spawn_player()
	var enemy := session.world.spawn_enemy(ENEMY_ID, Vector2i(4, 10))
	var layer := EntityLayer.new()
	add_child_autofree(layer)
	layer.setup(session, _zone_view, _registry)
	var view := layer.get_entity_view(enemy.id)
	assert_true(view.has_sprite())

	session.world.apply_damage(player.id, enemy, 99999.0)
	layer.sync()
	assert_true(layer.has_entity_view(enemy.id), "dead sprite view lingers")
	assert_false(view.is_queued_for_deletion())
	assert_eq(view.sprite.current_anim, AnimState.ANIM_DEATH)
	assert_false(view.is_hp_bar_visible())

	var tick_len := session.world.tick_length
	var expected := CharacterAnimator.hurt_ticks_for(EntityView.death_seconds_from_layout(_layout()), tick_len)
	assert_gt(expected, 0)
	var steps := 0
	while layer.has_entity_view(enemy.id) and steps < 1000:
		session.step(tick_len)
		layer.sync()
		steps += 1
	assert_false(layer.has_entity_view(enemy.id), "view freed after the death animation")
	assert_true(view.is_queued_for_deletion())
	assert_almost_eq(steps, expected, 1, "lingers about frame_count / fps seconds")


func test_dead_hexagon_view_frees_immediately() -> void:
	_registry.get_entry("enemies", ENEMY_ID).erase("appearance")
	var session := GameSession.new(_zone, _registry)
	var player := session.spawn_player()
	var enemy := session.world.spawn_enemy(ENEMY_ID, Vector2i(4, 10))
	var layer := EntityLayer.new()
	add_child_autofree(layer)
	layer.setup(session, _zone_view, _registry)
	var view := layer.get_entity_view(enemy.id)
	session.world.apply_damage(player.id, enemy, 99999.0)
	layer.sync()
	assert_false(layer.has_entity_view(enemy.id))
	assert_true(view.is_queued_for_deletion())
