extends GutTest
## JGT-82: top-centre boss bar shows while a living boss is aggroed; view_scale read.

const MAP_PATH := "res://data/zones/floor1/test_arena.map"
const JSON_PATH := "res://data/zones/floor1/test_arena.json"
const DATA_DIR := "res://data"
const BOSS_TYPE := "thornback_warden"

var _registry: DataRegistry = null
var _world: WorldSim = null


func before_each() -> void:
	_registry = DataRegistry.new()
	_registry.load_dir(DATA_DIR)
	var zone := Zone.load_files(MAP_PATH, JSON_PATH)
	_world = WorldSim.new(zone, _registry)


func _spawn_boss() -> Entity:
	var boss := _world.spawn_enemy(BOSS_TYPE, Vector2i(2, 2))
	boss.is_boss = true
	return boss


func _new_bar() -> BossBar:
	var bar := BossBar.new()
	add_child_autofree(bar)
	return bar


func test_hidden_by_default_and_when_boss_not_aggroed() -> void:
	var bar := _new_bar()
	assert_false(bar.visible, "hidden by default")
	_spawn_boss()
	bar.update_from_world(_world, _registry)
	assert_false(bar.visible, "idle boss (target_id 0) shows no bar")


func test_non_boss_aggroed_enemy_shows_no_bar() -> void:
	var bar := _new_bar()
	var e := _world.spawn_enemy("ash_stalker", Vector2i(2, 2))
	e.target_id = 99
	bar.update_from_world(_world, _registry)
	assert_false(bar.visible)


func test_visible_with_name_and_hp_ratio_when_aggroed() -> void:
	var bar := _new_bar()
	var boss := _spawn_boss()
	boss.target_id = 99
	boss.hp = boss.stats.max_hp * 0.25
	bar.update_from_world(_world, _registry)
	assert_true(bar.visible, "aggroed boss shows the bar")
	assert_eq(bar.get_boss_name(), "Thornback Warden", "name comes from enemies.json")
	assert_almost_eq(bar.get_ratio(), 0.25, 1e-4)
	assert_eq(bar.boss_entity_id, boss.id)


func test_hides_on_death_and_leash_reset() -> void:
	var bar := _new_bar()
	var boss := _spawn_boss()
	boss.target_id = 99
	bar.update_from_world(_world, _registry)
	assert_true(bar.visible)
	boss.target_id = 0
	bar.update_from_world(_world, _registry)
	assert_false(bar.visible, "leash reset hides the bar")
	boss.target_id = 99
	boss.hp = 0.0
	boss.dead = true
	bar.update_from_world(_world, _registry)
	assert_false(bar.visible, "dead boss hides the bar")


func test_null_world_hides() -> void:
	var bar := _new_bar()
	bar.visible = true
	bar.update_from_world(null, _registry)
	assert_false(bar.visible)


func test_display_name_falls_back_to_type_id() -> void:
	var e := Entity.new(1, "enemy")
	e.enemy_type_id = "no_such_type"
	assert_eq(BossBar.boss_display_name(e, _registry), "no_such_type")
	assert_eq(BossBar.boss_display_name(e, null), "no_such_type")


func test_hud_owns_boss_bar_and_updates_it() -> void:
	var hud := HUD.new()
	add_child_autofree(hud)
	hud.setup(null, _world, null, null, null, _registry)
	var bar := hud.get_boss_bar()
	assert_not_null(bar)
	assert_false(bar.visible)
	var boss := _spawn_boss()
	boss.target_id = 99
	hud.update_view()
	assert_true(bar.visible, "HUD.update_view shows the boss bar")
	boss.dead = true
	hud.update_view()
	assert_false(bar.visible)


func test_view_scale_from_entry() -> void:
	assert_almost_eq(EntityView.view_scale_from_entry({}), 1.0, 1e-6, "default 1.0")
	assert_almost_eq(EntityView.view_scale_from_entry({"view_scale": 2}), 2.0, 1e-6)
	assert_almost_eq(EntityView.view_scale_from_entry({"view_scale": -1.0}), 1.0, 1e-6)
	assert_almost_eq(EntityView.view_scale_from_entry({"view_scale": "big"}), 1.0, 1e-6)
	var warden := _registry.get_entry("enemies", BOSS_TYPE)
	assert_almost_eq(EntityView.view_scale_from_entry(warden), 1.5, 1e-6, "warden is drawn 1.5x")
	var stalker := _registry.get_entry("enemies", "ash_stalker")
	assert_almost_eq(EntityView.view_scale_from_entry(stalker), 1.0, 1e-6)


func test_entity_view_applies_view_scale_to_sprite_only() -> void:
	var boss := _spawn_boss()
	var view := EntityView.new()
	add_child_autofree(view)
	view.setup(boss, null, _registry)
	assert_almost_eq(view.view_scale, 1.5, 1e-6)
	assert_eq(view.scale, Vector2.ONE, "node (and logic) scale untouched")
	if view.has_sprite():
		assert_eq(view.sprite.scale, Vector2(1.5, 1.5), "sprite drawn at view_scale")
	else:
		pass_test("no LPC art fetched; hexagon fallback")
