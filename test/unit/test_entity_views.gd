extends GutTest

const MAP_PATH := "res://data/zones/floor1/test_arena.map"
const JSON_PATH := "res://data/zones/floor1/test_arena.json"
const DATA_DIR := "res://data"

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


func test_layer_creates_view_for_spawned_enemy_and_removes_it_after_death() -> void:
	var session := GameSession.new(_zone, _registry)
	var player := session.spawn_player()
	var enemy := session.world.spawn_enemy("ash_stalker", Vector2i(4, 10))
	assert_not_null(enemy)

	var layer := EntityLayer.new()
	autofree(layer)
	layer.setup(session, _zone_view, _registry)

	assert_true(layer.has_entity_view(enemy.id), "Layer must create an EntityView for spawned enemy")
	var view := layer.get_entity_view(enemy.id)
	assert_not_null(view)
	assert_eq(view.entity_id, enemy.id)
	assert_false(layer.has_entity_view(player.id), "Player should use player marker, not EntityView")

	# Kill the enemy
	session.world.apply_damage(player.id, enemy, 9999.0)
	assert_true(enemy.dead)

	layer.sync()
	assert_false(layer.has_entity_view(enemy.id), "Layer must remove EntityView after entity death")
	assert_true(view.is_queued_for_deletion(), "Removed view should be queued for deletion")


func test_hp_bar_ratio_matches_hp_over_max_hp_after_damage() -> void:
	var session := GameSession.new(_zone, _registry)
	var player := session.spawn_player()
	var enemy := session.world.spawn_enemy("ash_stalker", Vector2i(4, 10))

	var layer := EntityLayer.new()
	autofree(layer)
	layer.setup(session, _zone_view, _registry)

	var view := layer.get_entity_view(enemy.id)
	assert_not_null(view)
	assert_almost_eq(view.get_hp_ratio(), 1.0, 0.001)

	var max_hp := enemy.stats.max_hp
	var damage := max_hp * 0.4
	session.world.apply_damage(player.id, enemy, damage)

	layer.sync()
	var expected_ratio := (max_hp - damage) / max_hp
	assert_almost_eq(view.get_hp_ratio(), expected_ratio, 0.001)
	assert_almost_eq(view.hp_ratio, expected_ratio, 0.001)


func test_telegraph_start_event_creates_telegraph_view_progress_0_to_1_and_frees() -> void:
	var session := GameSession.new(_zone, _registry)
	var layer := EntityLayer.new()
	autofree(layer)
	layer.setup(session, _zone_view, _registry)

	# Record telegraph_start event
	var duration: float = 0.5
	var event: Dictionary = {
		"type": "telegraph_start",
		"tick": 1,
		"source": 2,
		"shape": "cone",
		"duration": duration,
		"duration_s": duration,
		"duration_ticks": 15,
		"origin": Vector2(4.5, 10.5),
		"dir": Vector2(0.0, -1.0),
		"range": 2.5,
		"angle_deg": 90.0
	}
	session.world.record_event(event)

	layer.sync()
	var telegraphs := layer.get_telegraph_views()
	assert_eq(telegraphs.size(), 1, "Layer must create a TelegraphView on telegraph_start event")

	var tele: TelegraphView = telegraphs[0]
	assert_almost_eq(tele.progress, 0.0, 0.001)
	assert_false(tele.is_queued_for_deletion())

	# Advance 50%
	tele.advance(duration * 0.5)
	assert_almost_eq(tele.progress, 0.5, 0.01)
	assert_false(tele.is_queued_for_deletion())

	# Advance remaining 50% -> reaches 1.0 and frees
	tele.advance(duration * 0.5)
	assert_almost_eq(tele.progress, 1.0, 0.01)
	assert_true(tele.is_queued_for_deletion(), "TelegraphView must queue_free after duration elapsed")


func test_telegraph_view_line_and_circle_shapes() -> void:
	var line_tele := TelegraphView.new()
	autofree(line_tele)
	line_tele.setup({
		"shape": "line",
		"origin": Vector2(1.0, 1.0),
		"dir": Vector2.RIGHT,
		"range": 3.0,
		"width": 1.0,
		"duration_s": 0.4
	}, 32, _registry)
	assert_eq(line_tele.shape_type, "line")
	line_tele.advance(0.2)
	assert_almost_eq(line_tele.progress, 0.5, 0.01)

	var circle_tele := TelegraphView.new()
	autofree(circle_tele)
	circle_tele.setup({
		"shape": "circle",
		"origin": Vector2(1.0, 1.0),
		"dir": Vector2.RIGHT,
		"range": 2.0,
		"radius": 1.5,
		"duration_s": 0.4
	}, 32, _registry)
	assert_eq(circle_tele.shape_type, "circle")
	circle_tele.advance(0.4)
	assert_almost_eq(circle_tele.progress, 1.0, 0.01)
	assert_true(circle_tele.is_queued_for_deletion())


func test_telegraph_circle_center_and_edge_points_match_skill_system() -> void:
	var tile_px: int = 32
	var origin := Vector2(10.0, 10.0)

	# 1. Circle with dir length < range
	var dir_short := Vector2(2.0, 0.0)
	var circle_event_short_dir: Dictionary = {
		"shape": "circle",
		"origin": origin,
		"dir": dir_short,
		"range": 5.0,
		"radius": 1.5,
		"duration_s": 0.5,
	}
	var tele_short := TelegraphView.new()
	autofree(tele_short)
	tele_short.setup(circle_event_short_dir, tile_px, _registry)

	var center_px_short := tele_short.get_circle_center_px()
	var expected_offset_short := Vector2(2.0, 0.0)
	assert_eq(center_px_short, expected_offset_short * float(tile_px), "Short dir: center_px should be dir * tile_px")

	var world_center_short := origin + (center_px_short / float(tile_px))
	assert_true(SkillSystem.in_shape(circle_event_short_dir, origin, dir_short, world_center_short), "World center should be inside SkillSystem.in_shape")
	# Sample inside and outside
	var inside_short := world_center_short + Vector2(1.0, 0.0)
	var outside_short := world_center_short + Vector2(2.0, 0.0)
	assert_true(SkillSystem.in_shape(circle_event_short_dir, origin, dir_short, inside_short))
	assert_false(SkillSystem.in_shape(circle_event_short_dir, origin, dir_short, outside_short))

	# 2. Circle with dir length > range (clamped)
	var dir_long := Vector2(6.0, 0.0)
	var circle_event_long_dir: Dictionary = {
		"shape": "circle",
		"origin": origin,
		"dir": dir_long,
		"range": 4.0,
		"radius": 1.0,
		"duration_s": 0.5,
	}
	var tele_long := TelegraphView.new()
	autofree(tele_long)
	tele_long.setup(circle_event_long_dir, tile_px, _registry)

	var center_px_long := tele_long.get_circle_center_px()
	var expected_offset_long := Vector2(4.0, 0.0)
	assert_eq(center_px_long, expected_offset_long * float(tile_px), "Long dir: center_px should be clamped to range * tile_px")

	var world_center_long := origin + (center_px_long / float(tile_px))
	assert_true(SkillSystem.in_shape(circle_event_long_dir, origin, dir_long, world_center_long), "Clamped world center should be inside SkillSystem.in_shape")
	# Unclamped target (origin + dir = (16, 10)) should NOT be inside circle (since center is at (14, 10) and radius is 1.0)
	var unclamped_target := origin + dir_long
	assert_false(SkillSystem.in_shape(circle_event_long_dir, origin, dir_long, unclamped_target), "Unclamped point should not be in shape when dir > range")

	# 3. Circle with zero dir
	var dir_zero := Vector2.ZERO
	var circle_event_zero_dir: Dictionary = {
		"shape": "circle",
		"origin": origin,
		"dir": dir_zero,
		"range": 3.0,
		"radius": 1.5,
		"duration_s": 0.5,
	}
	var tele_zero := TelegraphView.new()
	autofree(tele_zero)
	tele_zero.setup(circle_event_zero_dir, tile_px, _registry)

	var center_px_zero := tele_zero.get_circle_center_px()
	assert_eq(center_px_zero, Vector2.ZERO, "Zero dir: center_px should be ZERO")
	var world_center_zero := origin + (center_px_zero / float(tile_px))
	assert_true(SkillSystem.in_shape(circle_event_zero_dir, origin, dir_zero, world_center_zero), "Center at origin should be inside SkillSystem.in_shape for zero dir")

	# 4. Circle with range <= 0
	var dir_zero_range := Vector2(3.0, 2.0)
	var circle_event_zero_range: Dictionary = {
		"shape": "circle",
		"origin": origin,
		"dir": dir_zero_range,
		"range": 0.0,
		"radius": 2.0,
		"duration_s": 0.5,
	}
	var tele_zero_range := TelegraphView.new()
	autofree(tele_zero_range)
	tele_zero_range.setup(circle_event_zero_range, tile_px, _registry)
	assert_eq(tele_zero_range.get_circle_center_px(), Vector2.ZERO, "Range <= 0: center_px should be ZERO")

	# 5. Line edge sample points against SkillSystem.in_shape
	var dir_line := Vector2.RIGHT
	var line_event: Dictionary = {
		"shape": "line",
		"origin": origin,
		"dir": dir_line,
		"range": 4.0,
		"width": 2.0,
		"duration_s": 0.5,
	}
	# Along centerline inside range
	assert_true(SkillSystem.in_shape(line_event, origin, dir_line, origin + Vector2(2.0, 0.0)))
	# Near lateral edges (+- width / 2.0 = 1.0)
	assert_true(SkillSystem.in_shape(line_event, origin, dir_line, origin + Vector2(2.0, 0.95)))
	assert_true(SkillSystem.in_shape(line_event, origin, dir_line, origin + Vector2(2.0, -0.95)))
	# Outside lateral edge
	assert_false(SkillSystem.in_shape(line_event, origin, dir_line, origin + Vector2(2.0, 1.05)))
	assert_false(SkillSystem.in_shape(line_event, origin, dir_line, origin + Vector2(2.0, -1.05)))
	# Past max length and behind origin
	assert_false(SkillSystem.in_shape(line_event, origin, dir_line, origin + Vector2(4.1, 0.0)))
	assert_false(SkillSystem.in_shape(line_event, origin, dir_line, origin + Vector2(-0.5, 0.0)))

	# 6. Cone edge sample points against SkillSystem.in_shape
	var dir_cone := Vector2.RIGHT
	var cone_event: Dictionary = {
		"shape": "cone",
		"origin": origin,
		"dir": dir_cone,
		"range": 4.0,
		"angle_deg": 60.0,
		"duration_s": 0.5,
	}
	# Along center line
	assert_true(SkillSystem.in_shape(cone_event, origin, dir_cone, origin + Vector2(2.0, 0.0)))
	# Inside cone angle (half angle is 30 deg; test 25 deg at length 3.0)
	var inside_cone_pt := origin + Vector2(cos(deg_to_rad(25.0)), sin(deg_to_rad(25.0))) * 3.0
	assert_true(SkillSystem.in_shape(cone_event, origin, dir_cone, inside_cone_pt))
	# Outside cone angle (test 35 deg at length 3.0)
	var outside_cone_pt := origin + Vector2(cos(deg_to_rad(35.0)), sin(deg_to_rad(35.0))) * 3.0
	assert_false(SkillSystem.in_shape(cone_event, origin, dir_cone, outside_cone_pt))
	# Past max cone range
	assert_false(SkillSystem.in_shape(cone_event, origin, dir_cone, origin + Vector2(4.2, 0.0)))
	# Behind origin
	assert_false(SkillSystem.in_shape(cone_event, origin, dir_cone, origin + Vector2(-1.0, 0.0)))


func test_damage_event_creates_floating_text_with_amount() -> void:
	var session := GameSession.new(_zone, _registry)
	var player := session.spawn_player()
	var enemy := session.world.spawn_enemy("ash_stalker", Vector2i(4, 10))

	var layer := EntityLayer.new()
	autofree(layer)
	layer.setup(session, _zone_view, _registry)

	# Apply damage which emits "damage" event
	var damage_amount := 23.5
	session.world.apply_damage(player.id, enemy, damage_amount)

	layer.sync()
	var texts := layer.get_floating_texts()
	assert_eq(texts.size(), 1, "Layer must create FloatingText on damage event")

	var ft: FloatingText = texts[0]
	assert_almost_eq(ft.amount, damage_amount, 0.001)
	assert_eq(ft.text, "23.5")
	assert_false(ft.is_player_damage)

	# Test rising and fading
	var start_y := ft.position.y
	ft.advance(ft.duration_s * 0.5)
	assert_lt(ft.position.y, start_y, "Floating text must rise over time")
	assert_almost_eq(ft.modulate.a, 0.5, 0.02, "Floating text alpha must fade over time")

	ft.advance(ft.duration_s * 0.5)
	assert_true(ft.is_queued_for_deletion(), "Floating text must queue_free after duration elapsed")


func test_player_taken_damage_floating_text_different_colour() -> void:
	var session := GameSession.new(_zone, _registry)
	var player := session.spawn_player()
	var enemy := session.world.spawn_enemy("ash_stalker", Vector2i(4, 10))

	var layer := EntityLayer.new()
	autofree(layer)
	layer.setup(session, _zone_view, _registry)

	# Damage player
	session.world.apply_damage(enemy.id, player, 15.0)
	layer.sync()

	var texts := layer.get_floating_texts()
	assert_eq(texts.size(), 1)
	var player_ft: FloatingText = texts[0]
	assert_true(player_ft.is_player_damage)

	# Damage enemy
	session.world.apply_damage(player.id, enemy, 10.0)
	layer.sync()

	texts = layer.get_floating_texts()
	assert_eq(texts.size(), 2)
	var enemy_ft: FloatingText = texts[1]
	assert_false(enemy_ft.is_player_damage)

	assert_ne(player_ft.text_color, enemy_ft.text_color, "Player-taken damage and enemy-taken damage must have different colours")


func test_event_emitted_signal_and_last_events() -> void:
	var session := GameSession.new(_zone, _registry)
	var player := session.spawn_player()
	var enemy := session.world.spawn_enemy("ash_stalker", Vector2i(4, 10))

	var layer := EntityLayer.new()
	autofree(layer)
	layer.setup(session, _zone_view, _registry)

	watch_signals(layer)

	session.world.apply_damage(player.id, enemy, 10.0)
	layer.sync()

	assert_signal_emitted(layer, "event_emitted")
	assert_gt(layer.last_events.size(), 0)
	assert_eq(layer.last_events[0].get("type"), "damage")


func test_player_marker_hp_bar_update() -> void:
	var session := GameSession.new(_zone, _registry)
	var player := session.spawn_player()
	var enemy := session.world.spawn_enemy("ash_stalker", Vector2i(4, 10))

	var marker := Node2D.new()
	autofree(marker)

	var layer := EntityLayer.new()
	autofree(layer)
	layer.setup(session, _zone_view, _registry, marker)

	assert_not_null(layer.player_hp_bar)
	assert_almost_eq(layer.player_hp_bar.ratio, 1.0, 0.001)

	session.world.apply_damage(enemy.id, player, 30.0)
	layer.sync()

	assert_almost_eq(layer.player_hp_bar.ratio, 0.7, 0.001)


func test_entity_view_missing_balance_keys_push_warnings() -> void:
	var empty_reg: DataRegistry = autofree(DataRegistry.new())
	var view: EntityView = autofree(EntityView.new())
	view.setup(null, null, empty_reg)
	# Missing 9 keys: enemy_size, enemy_color, enemy_outline_color, hp_bar_width, hp_bar_height,
	# hp_bar_y_offset, hp_bar_bg_color, hp_bar_fill_color, hp_bar_border_color
	assert_push_warning_count(9, "EntityView should push 9 warnings for missing balance keys")


func test_telegraph_view_missing_balance_keys_push_warnings() -> void:
	var empty_reg: DataRegistry = autofree(DataRegistry.new())
	var tele: TelegraphView = autofree(TelegraphView.new())
	tele.setup({}, 32, empty_reg)
	# Missing 3 keys: telegraph_color, telegraph_fill_color, telegraph_line_color
	assert_push_warning_count(3, "TelegraphView should push 3 warnings for missing balance keys")


func test_floating_text_missing_balance_keys_push_warnings() -> void:
	var empty_reg: DataRegistry = autofree(DataRegistry.new())
	var ft: FloatingText = autofree(FloatingText.new())
	ft.setup(10.0, Vector2.ZERO, false, empty_reg)
	# Missing 4 keys: damage_text_duration_s, damage_text_rise_px, damage_player_color, damage_enemy_color
	assert_push_warning_count(4, "FloatingText should push 4 warnings for missing balance keys")


func test_telegraph_windup_preview_inactive_by_default() -> void:
	assert_false(TelegraphWindupPreview.is_active, "TelegraphWindupPreview must not be active by default")
	# Even if setup_if_requested is called on a MainView, without the user flag it must not activate
	var main_view := MainView.new()
	autofree(main_view)
	TelegraphWindupPreview.setup_if_requested(main_view)
	assert_false(TelegraphWindupPreview.is_active, "TelegraphWindupPreview must remain inactive without --preview=telegraph_windup")
