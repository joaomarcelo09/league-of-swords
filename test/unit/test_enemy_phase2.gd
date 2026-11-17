extends GutTest
## JGT-126: Gorvak's phase 2 weapon swap. The decision is a pure function
## (EntityView.weapon_layer_for) so it is testable headless, and the boss view applies
## it to the "weapon" layer texture when HP crosses the data threshold.

const MAP_PATH := "res://data/zones/floor1/test_arena.map"
const JSON_PATH := "res://data/zones/floor1/test_arena.json"
const BOSS_ID := "thornback_warden"
const PHASE2: Dictionary = {"hp_ratio_below": 0.35, "weapon_layer": "weapon_phase2"}

var _registry: DataRegistry = null
var _zone: Zone = null
var _zone_view: ZoneView = null


func before_each() -> void:
	_registry = DataRegistry.new()
	_registry.load_dir("res://data")
	_zone = Zone.load_files(MAP_PATH, JSON_PATH)
	_zone_view = ZoneView.new()
	_zone_view.setup(_registry)
	_zone_view.build(_zone)
	autofree(_zone_view)


func test_full_and_above_threshold_hp_keeps_the_phase1_weapon() -> void:
	assert_eq(EntityView.weapon_layer_for(1.0, PHASE2), "weapon", "full HP -> phase 1")
	assert_eq(EntityView.weapon_layer_for(0.36, PHASE2), "weapon", "above the threshold -> phase 1")
	assert_eq(EntityView.weapon_layer_for(0.35, PHASE2), "weapon", "the swap is strictly below the threshold")


func test_below_threshold_hp_uses_the_phase2_weapon() -> void:
	assert_eq(EntityView.weapon_layer_for(0.34, PHASE2), "weapon_phase2", "below the threshold -> phase 2")
	assert_eq(EntityView.weapon_layer_for(0.0, PHASE2), "weapon_phase2", "dead still draws the phase 2 weapon")


func test_healing_back_over_the_threshold_returns_to_the_phase1_weapon() -> void:
	var layer := EntityView.weapon_layer_for(1.0, PHASE2)
	layer = EntityView.weapon_layer_for(0.2, PHASE2)
	assert_eq(layer, "weapon_phase2", "drop below the threshold")
	layer = EntityView.weapon_layer_for(0.8, PHASE2)
	assert_eq(layer, "weapon", "healed back above the threshold")


func test_missing_or_invalid_phase2_block_keeps_the_phase1_weapon() -> void:
	assert_eq(EntityView.weapon_layer_for(0.1, {}), "weapon", "no phase 2 block")
	assert_eq(EntityView.weapon_layer_for(0.1, {"hp_ratio_below": 0.35}), "weapon", "no layer name")
	assert_eq(EntityView.weapon_layer_for(0.1, {"weapon_layer": "weapon_phase2"}), "weapon", "no threshold")
	assert_eq(EntityView.weapon_layer_for(0.1, {"hp_ratio_below": "soon", "weapon_layer": "weapon_phase2"}), "weapon", "non-numeric threshold")
	assert_eq(EntityView.weapon_layer_for(0.1, {"hp_ratio_below": 0.0, "weapon_layer": "weapon_phase2"}), "weapon", "0 is not a valid threshold")
	assert_eq(EntityView.weapon_layer_for(0.1, {"hp_ratio_below": 1.0, "weapon_layer": "weapon_phase2"}), "weapon", "1.0 is not a valid threshold")
	assert_eq(EntityView.weapon_layer_for(0.1, {"hp_ratio_below": 0.35, "weapon_layer": "   "}), "weapon", "blank layer name")
	assert_eq(EntityView.weapon_layer_for(0.9, PHASE2, "staff"), "staff", "other base layers are kept")


func test_boss_view_swaps_the_weapon_texture_and_swaps_it_back() -> void:
	var session := GameSession.new(_zone, _registry)
	var enemy := session.world.spawn_enemy(BOSS_ID, Vector2i(4, 10))
	assert_not_null(enemy, "boss spawns")
	if enemy == null:
		return
	var view := EntityView.new()
	add_child_autofree(view)
	view.tick_length = session.world.tick_length
	view.setup(enemy, _zone_view, _registry)
	assert_true(view.has_sprite(), "boss builds its layered sprite")
	var weapon := view.sprite.get_layer_sprite("weapon")
	assert_not_null(weapon, "boss weapon layer exists")
	if weapon == null:
		return

	var phase1_texture := weapon.texture
	assert_eq(view.weapon_layer, "weapon", "spawns in phase 1")

	enemy.hp = enemy.stats.max_hp * 0.2
	view.sync()
	assert_eq(view.weapon_layer, "weapon_phase2", "low HP swaps the weapon layer")
	assert_ne(weapon.texture, phase1_texture, "the weapon layer draws the phase 2 sheet")
	assert_true(weapon.visible, "the swapped layer stays visible")

	enemy.hp = enemy.stats.max_hp
	view.sync()
	assert_eq(view.weapon_layer, "weapon", "healing back restores phase 1")
	assert_eq(weapon.texture, phase1_texture, "the phase 1 sheet is restored")
