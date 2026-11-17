extends GutTest
## JGT-129: player, enemies, boss and NPCs must share one y-sorted parent so their
## feet Y decides the draw order (a sprite further down the screen is drawn in front).

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


## Mirrors the "Entities" node of scenes/main.tscn.
func _make_entities_root() -> Node2D:
	var root := Node2D.new()
	root.name = "Entities"
	root.y_sort_enabled = true
	add_child_autofree(root)
	return root


func test_enemy_view_is_direct_child_of_y_sorted_entities_root() -> void:
	var session := GameSession.new(_zone, _registry)
	var enemy := session.world.spawn_enemy("ash_stalker", Vector2i(4, 10))
	var root := _make_entities_root()
	var layer := EntityLayer.new()
	root.add_child(layer)
	layer.view_parent = root

	layer.setup(session, _zone_view, _registry)

	var view := layer.get_entity_view(enemy.id)
	assert_not_null(view)
	assert_true(root.y_sort_enabled, "Entities root must enable y_sort_enabled")
	assert_eq(view.get_parent(), root, "Enemy view must sort in the Entities root, never nested in EntityLayer")
	assert_eq(view.position, _zone_view.entity_to_world(enemy.pos), "View origin is the entity's feet position")


func test_player_enemy_and_npc_share_the_same_sort_space() -> void:
	var session := GameSession.new(_zone, _registry)
	var player := session.spawn_player(Vector2i(4, 9))
	var enemy := session.world.spawn_enemy("ash_stalker", Vector2i(4, 10))
	var root := _make_entities_root()

	# Same nodes MainView builds: PlayerMarker, NPC views and the enemy EntityLayer.
	var marker := Node2D.new()
	marker.name = "PlayerMarker"
	marker.position = _zone_view.entity_to_world(player.pos)
	root.add_child(marker)
	var npc := NpcView.new({"id": "smith", "kind": "merchant", "tile": [6, 6]})
	npc.place(_zone_view)
	root.add_child(npc)

	var layer := EntityLayer.new()
	root.add_child(layer)
	layer.view_parent = root
	layer.setup(session, _zone_view, _registry)

	var enemy_view := layer.get_entity_view(enemy.id)
	assert_not_null(enemy_view)
	assert_eq(marker.get_parent(), root)
	assert_eq(npc.get_parent(), root)
	assert_eq(enemy_view.get_parent(), root)


func test_sprite_with_larger_feet_y_is_drawn_in_front() -> void:
	var session := GameSession.new(_zone, _registry)
	var player := session.spawn_player(Vector2i(4, 9))
	var enemy := session.world.spawn_enemy("ash_stalker", Vector2i(4, 10))
	var root := _make_entities_root()
	var layer := EntityLayer.new()
	root.add_child(layer)
	layer.view_parent = root
	layer.setup(session, _zone_view, _registry)

	var marker := Node2D.new()
	root.add_child(marker)
	marker.position = _zone_view.entity_to_world(player.pos)
	var enemy_view := layer.get_entity_view(enemy.id)

	# Player stands north of (above) the enemy, so the enemy must be drawn in front.
	assert_true(marker.position.y < enemy_view.position.y, "player feet are north of the enemy feet")
	assert_true(EntityLayer.is_in_front(enemy_view.position.y, marker.position.y), "larger Y draws in front")
	assert_false(EntityLayer.is_in_front(marker.position.y, enemy_view.position.y), "smaller Y draws behind")


func test_view_layer_still_holds_effect_containers() -> void:
	var root := _make_entities_root()
	var layer := EntityLayer.new()
	root.add_child(layer)
	layer.view_parent = root
	var session := GameSession.new(_zone, _registry)
	layer.setup(session, _zone_view, _registry)

	assert_eq(layer.telegraphs_root.get_parent(), layer)
	assert_eq(layer.floating_texts_root.get_parent(), layer)
	assert_eq(layer.telegraphs_root.z_index, 0, "telegraphs stay under sprites")
	assert_eq(layer.floating_texts_root.z_index, 10, "floating texts stay above sprites")
