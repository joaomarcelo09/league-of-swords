class_name MainView
extends Node2D

const ZONE_MAP_PATH: String = "res://data/zones/floor1/test_arena.map"
const ZONE_JSON_PATH: String = "res://data/zones/floor1/test_arena.json"
const DATA_DIR: String = "res://data"
const DEFAULT_SAVE_ROOT: String = "user://saves"
const DEFAULT_SAVE_SLOT: String = "slot_1"
const DEFAULT_PLAYER_NAME: String = "Hero"

@export var zone_map_path: String = ZONE_MAP_PATH
@export var zone_json_path: String = ZONE_JSON_PATH
@export var save_root: String = ""
@export var save_slot: String = ""

@onready var zone_view: ZoneView = $ZoneView if has_node("ZoneView") else null
@onready var entities_root: Node2D = $Entities if has_node("Entities") else null
@onready var camera: GameCamera = $Camera if has_node("Camera") else null
@onready var player_input: PlayerInput = $PlayerInput if has_node("PlayerInput") else null

signal event_emitted(event: Dictionary)

var registry: DataRegistry = null
var zone: Zone = null
var item_db: ItemDB = null
var inventory: Inventory = null
var session: GameSession = null
var world: WorldSim = null
var player: Entity = null
var player_marker: Node2D = null
var entity_layer: EntityLayer = null
var hud: HUD = null
var max_frame_dt_s: float = 0.0

var world_state: WorldState = null
var character_state: CharacterState = null
var save_store: SaveStore = null
var death_screen: DeathScreen = null
var merchant_id: String = ""
var _pending_death_event: Dictionary = {}
var _death_persisted: bool = false

var last_events: Array[Dictionary]:
	get:
		return entity_layer.last_events if entity_layer != null else []


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_now()


func _ready() -> void:
	_init_game()


func _init_game() -> void:
	# 1. Load data registry
	registry = DataRegistry.new()
	registry.load_dir(DATA_DIR)
	var max_dt_val: Variant = registry.get_balance("sim.max_frame_dt_s")
	if max_dt_val != null:
		max_frame_dt_s = float(max_dt_val)
	else:
		push_error("MainView: Missing sim.max_frame_dt_s in balance data")

	# 2. Load zone
	var map_path := zone_map_path if not zone_map_path.is_empty() else ZONE_MAP_PATH
	var json_path := zone_json_path if not zone_json_path.is_empty() else ZONE_JSON_PATH
	zone = Zone.load_files(map_path, json_path)
	if not zone.is_valid():
		push_error("MainView: Failed to load zone: %s" % str(zone.errors))
		return

	# 3. Setup ZoneView
	if zone_view == null:
		zone_view = ZoneView.new()
		zone_view.name = "ZoneView"
		add_child(zone_view)
	zone_view.setup(registry)
	zone_view.build(zone)

	# 4. Setup Entities Y-Sort root
	if entities_root == null:
		entities_root = Node2D.new()
		entities_root.name = "Entities"
		add_child(entities_root)
	entities_root.y_sort_enabled = true

	# 5. Create ItemDB and SaveStore / WorldState
	item_db = ItemDB.new(registry)

	var root_path := save_root
	if root_path.is_empty() and registry != null:
		var root_val: Variant = registry.get_balance("save.default_root")
		if root_val != null and not str(root_val).is_empty():
			root_path = str(root_val)
	if root_path.is_empty():
		root_path = DEFAULT_SAVE_ROOT
	save_root = root_path

	var slot_name := save_slot
	if slot_name.is_empty() and registry != null:
		var slot_val: Variant = registry.get_balance("save.default_slot")
		if slot_val != null and not str(slot_val).is_empty():
			slot_name = str(slot_val)
	if slot_name.is_empty():
		slot_name = DEFAULT_SAVE_SLOT
	save_slot = slot_name

	save_store = SaveStore.new(save_root, item_db)

	if world_state == null:
		var world_path := save_store.get_world_file_path(save_slot)
		var world_file_exists := FileAccess.file_exists(world_path)
		if world_file_exists:
			var w_res := save_store.load_world(save_slot)
			if w_res.get("ok", false) and w_res.get("value") is WorldState:
				world_state = w_res["value"]
			else:
				push_error("Failed to load existing world '%s': %s" % [world_path, str(w_res.get("error", "unknown error"))])
				# Existing world file failed to load: do not write anything, do not overwrite!
		else:
			world_state = WorldState.new()
			var seed_val: Variant = registry.get_balance("sim.seed")
			if seed_val != null:
				world_state.seed = int(seed_val)
			world_state.floors_unlocked = 1
			world_state.inventory = Inventory.new(item_db)
			save_store.save_world(save_slot, world_state)

	if world_state != null:
		if world_state.inventory == null:
			world_state.inventory = Inventory.new(item_db)
		inventory = world_state.inventory
	else:
		inventory = Inventory.new(item_db)

	if character_state == null and world_state != null:
		var target_char_id := ""
		if LaunchRequest.mode == "continue" and not LaunchRequest.character_id.is_empty():
			target_char_id = LaunchRequest.character_id

		if not target_char_id.is_empty():
			var load_res := Lifecycle.load_playable(save_store, save_slot, target_char_id, item_db)
			if load_res.get("ok", false) and load_res.get("value") is CharacterState:
				character_state = load_res["value"]

		if character_state == null and LaunchRequest.mode != "new":
			var list_res := save_store.list_characters(save_slot)
			if list_res.get("ok", false) and list_res.get("value") is Array:
				for cid in list_res["value"]:
					var load_res := Lifecycle.load_playable(save_store, save_slot, str(cid), item_db)
					if load_res.get("ok", false) and load_res.get("value") is CharacterState:
						character_state = load_res["value"]
						break

		if character_state == null:
			var init_name: String = DEFAULT_PLAYER_NAME
			if registry != null:
				var name_val: Variant = registry.get_balance("permadeath.default_player_name")
				if name_val != null and not str(name_val).is_empty():
					init_name = str(name_val)
			var create_res := Lifecycle.new_character(
				world_state,
				init_name,
				{},
				zone.entry if zone != null else null,
				save_store,
				save_slot,
				null,
				"floor1",
				registry
			)
			if create_res.get("ok", false):
				character_state = create_res.get("value")

	LaunchRequest.reset()

	# 6. Create GameSession, spawn player and zone enemies
	session = GameSession.new(zone, registry, inventory, item_db)
	world = session.world
	var player_speed: float = float(registry.get_balance("player.move_speed_tiles_per_s", 4.0))
	var spawn_pos: Variant = zone.entry
	if character_state != null and character_state.position.size() >= 2:
		spawn_pos = Vector2(character_state.position[0], character_state.position[1])
	player = session.spawn_player(spawn_pos, player_speed)
	if character_state != null and character_state.position.size() >= 2:
		player.pos = Vector2(character_state.position[0], character_state.position[1])
	if character_state != null and character_state.stats != null:
		player.stats = character_state.stats.duplicate()
	session.spawn_enemies()
	_sync_items_to_entity()

	# 7. Create Player Marker
	_create_player_marker()

	# 7b. Create EntityLayer
	_create_entity_layer()

	# 8. Setup Camera
	if camera == null:
		camera = GameCamera.new()
		camera.name = "Camera"
		add_child(camera)
	camera.enabled = true
	camera.setup(registry)

	# 9. Setup PlayerInput
	if player_input == null:
		player_input = PlayerInput.new()
		player_input.name = "PlayerInput"
		add_child(player_input)
	if not player_input.attack_mode_changed.is_connected(_on_attack_mode_changed):
		player_input.attack_mode_changed.connect(_on_attack_mode_changed)
	player_input.setup(player.id, world, zone_view, registry)

	# 10. Setup HUD
	_create_hud()

	# 11. Setup DeathScreen
	_create_death_screen()

	if not event_emitted.is_connected(_on_event_emitted):
		event_emitted.connect(_on_event_emitted)

	TelegraphWindupPreview.setup_if_requested(self)
	LayeredSpritePreview.setup_if_requested(self)
	HudPreview.setup_if_requested(self)
	DeathScreenPreview.setup_if_requested(self)

	# Initial view update
	_update_views()


func _create_hud() -> void:
	if has_node("HUD"):
		hud = get_node("HUD") as HUD
	else:
		var hud_scene := load("res://scenes/hud.tscn") as PackedScene
		if hud_scene != null:
			hud = hud_scene.instantiate() as HUD
		else:
			hud = HUD.new()
		hud.name = "HUD"
		add_child(hud)

	hud.setup(session, world, player, inventory, item_db, registry, entities_root, zone_view)
	event_emitted.connect(func(ev: Dictionary) -> void:
		if hud != null:
			hud.handle_event(ev)
	)


func _create_death_screen() -> void:
	if death_screen == null:
		if has_node("DeathScreen"):
			death_screen = get_node("DeathScreen") as DeathScreen
		else:
			death_screen = DeathScreen.new()
			death_screen.name = "DeathScreen"
			add_child(death_screen)

	if not death_screen.new_character_requested.is_connected(_on_new_character_requested):
		death_screen.new_character_requested.connect(_on_new_character_requested)


func _on_event_emitted(ev: Dictionary) -> void:
	if ev.get("type") == "death":
		var target_id := int(ev.get("target", -1))
		if player != null and target_id == player.id:
			_handle_player_death(ev)
		elif world_state != null:
			world_state.killed_enemies += 1


func _persist_player_death(death_event: Dictionary) -> Dictionary:
	_sync_items_to_character()

	var date_str := SaveDate.get_date_string()
	var merch := merchant_id
	if merch.is_empty() and registry != null:
		var m_val: Variant = registry.get_balance("permadeath.merchant_id")
		if m_val != null:
			merch = str(m_val)

	return Lifecycle.on_player_death_event(
		death_event,
		world_state,
		character_state,
		date_str,
		save_store,
		save_slot,
		world,
		player.id if player != null else -1,
		merch,
		registry
	)


func _handle_player_death(death_event: Dictionary) -> void:
	if death_screen != null and death_screen.is_open():
		return

	if player_input != null:
		player_input.cancel_attack_mode()
		player_input.process_mode = Node.PROCESS_MODE_DISABLED
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)

	_pending_death_event = death_event.duplicate(true)

	var res := _persist_player_death(_pending_death_event)
	_death_persisted = bool(res.get("ok", false))

	var cem_entry: Dictionary = {}
	if world_state != null:
		for entry: Dictionary in world_state.cemetery:
			if character_state != null and entry.get("character_id") == character_state.id:
				cem_entry = entry
				break

	if cem_entry.is_empty() and character_state != null:
		cem_entry = {
			"character_id": character_state.id,
			"name": character_state.name,
			"level": character_state.level,
			"zone": character_state.zone,
			"cause": Lifecycle.cause_from_death_event(death_event, world),
			"date": SaveDate.get_date_string(),
		}

	if death_screen != null:
		death_screen.show_death(cem_entry)
		if not _death_persisted:
			death_screen.show_error(str(res.get("error", "Failed to save player death")))


func _on_new_character_requested(new_name: String) -> void:
	if not _death_persisted:
		var retry_res := _persist_player_death(_pending_death_event)
		if not retry_res.get("ok", false):
			if death_screen != null:
				death_screen.show_error(str(retry_res.get("error", "Failed to save player death")))
			return
		_death_persisted = true

	var validation := CharacterNaming.validate_name(new_name)
	if not validation.get("valid", false):
		if death_screen != null:
			death_screen.show_error(str(validation.get("error", "Invalid character name")))
		return

	var valid_name: String = str(validation.get("value", new_name))
	var create_res := Lifecycle.new_character(
		world_state,
		valid_name,
		{},
		zone.entry if zone != null else null,
		save_store,
		save_slot,
		null,
		"floor1",
		registry
	)

	if not create_res.get("ok", false):
		if death_screen != null:
			death_screen.show_error(str(create_res.get("error", "Failed to create character")))
		return

	character_state = create_res.get("value") as CharacterState
	_respawn_new_character()


func _respawn_new_character() -> void:
	session = GameSession.new(zone, registry, inventory, item_db)
	world = session.world

	var player_speed: float = float(registry.get_balance("player.move_speed_tiles_per_s", 4.0))
	player = session.spawn_player(zone.entry, player_speed)
	session.spawn_enemies()
	_sync_items_to_entity()

	if player_input != null:
		player_input.process_mode = Node.PROCESS_MODE_INHERIT
		player_input.setup(player.id, world, zone_view, registry)

	if entity_layer != null:
		entity_layer.reset()
		entity_layer.setup(session, zone_view, registry, player_marker)

	if hud != null:
		hud.clear_loot_markers()
		hud.setup(session, world, player, inventory, item_db, registry, entities_root, zone_view)

	if death_screen != null:
		death_screen.close()

	_pending_death_event.clear()
	_death_persisted = false

	_update_views()


func _create_entity_layer() -> void:
	if entities_root == null:
		return
	if entities_root.has_node("EntityLayer"):
		entity_layer = entities_root.get_node("EntityLayer") as EntityLayer
		return

	var layer := EntityLayer.new()
	layer.name = "EntityLayer"
	entities_root.add_child(layer)
	entity_layer = layer
	entity_layer.setup(session, zone_view, registry, player_marker)
	entity_layer.event_emitted.connect(func(ev: Dictionary) -> void: event_emitted.emit(ev))


func _create_player_marker() -> void:
	if entities_root.has_node("PlayerMarker"):
		player_marker = entities_root.get_node("PlayerMarker") as Node2D
		return

	var marker := Node2D.new()
	marker.name = "PlayerMarker"

	# Outer diamond outline
	var outline := Polygon2D.new()
	outline.polygon = PackedVector2Array([
		Vector2(0, -14),
		Vector2(12, 0),
		Vector2(0, 14),
		Vector2(-12, 0)
	])
	outline.color = Color(0.08, 0.1, 0.14, 1.0)
	marker.add_child(outline)

	# Inner diamond (bright hero cyan/blue)
	var inner := Polygon2D.new()
	inner.polygon = PackedVector2Array([
		Vector2(0, -11),
		Vector2(9, 0),
		Vector2(0, 11),
		Vector2(-9, 0)
	])
	inner.color = Color(0.2, 0.65, 1.0, 1.0)
	marker.add_child(inner)

	# Center white glint
	var center_dot := Polygon2D.new()
	center_dot.polygon = PackedVector2Array([
		Vector2(0, -3),
		Vector2(3, 0),
		Vector2(0, 3),
		Vector2(-3, 0)
	])
	center_dot.color = Color(1.0, 1.0, 1.0, 1.0)
	marker.add_child(center_dot)

	entities_root.add_child(marker)
	player_marker = marker


func _exit_tree() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _on_attack_mode_changed(active: bool) -> void:
	if active:
		Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	else:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _process(delta: float) -> void:
	if TelegraphWindupPreview.is_active or LayeredSpritePreview.is_active or HudPreview.is_active or DeathScreenPreview.is_active:
		_update_views()
		return

	if death_screen != null and death_screen.is_open():
		return

	if session != null:
		var clamped_dt := clamp_frame_dt(delta, max_frame_dt_s)
		session.step(clamped_dt)
	elif world != null:
		var clamped_dt := clamp_frame_dt(delta, max_frame_dt_s)
		world.step(clamped_dt)
	_update_views()


static func clamp_frame_dt(delta: float, max_dt: float) -> float:
	if is_nan(delta) or delta <= 0.0:
		return 0.0
	if is_nan(max_dt) or max_dt <= 0.0:
		return 0.0
	if delta > max_dt:
		return max_dt
	return delta


func _update_views() -> void:
	if player == null or zone_view == null:
		return

	var world_pos := zone_view.entity_to_world(player.pos)
	if player_marker != null:
		player_marker.position = world_pos

	if entity_layer != null:
		entity_layer.sync()

	if camera != null:
		camera.follow(world_pos)

	if hud != null:
		hud.update_view()


func save_now() -> Dictionary:
	if save_store == null or world_state == null:
		return {"ok": false, "error": "MainView is not initialized", "value": null}

	if character_state != null and character_state.status != "dead" and player != null:
		character_state.position = [player.pos.x, player.pos.y]
		if player.stats != null:
			character_state.stats = player.stats.duplicate()
		if character_state.zone.is_empty():
			character_state.zone = "floor1"

	_sync_items_to_character()

	var save_c: Dictionary = {"ok": true}
	if character_state != null:
		save_c = save_store.save_character(save_slot, character_state)
		if not save_c.get("ok", false):
			return save_c

	var save_w := save_store.save_world(save_slot, world_state)
	if not save_w.get("ok", false):
		return save_w

	if player != null and not player.dead:
		_sync_items_to_entity()

	return {"ok": true, "error": "", "value": null}


func _sync_items_to_entity() -> void:
	if world_state == null or world_state.inventory == null or player == null or character_state == null:
		return
	var ent_owner := "character:%d" % player.id
	var char_owner := character_state.id if character_state.id.begins_with("character:") else "character:" + character_state.id
	if ent_owner == char_owner:
		return

	var char_equipped := world_state.inventory.get_all_equipped(char_owner)
	var char_items := world_state.inventory.items_of(char_owner)
	for uid: int in char_items:
		world_state.inventory.transfer(uid, ent_owner)
	for s in char_equipped.keys():
		world_state.inventory.equip(ent_owner, int(char_equipped[s]))


func _sync_items_to_character() -> void:
	if world_state == null or world_state.inventory == null or player == null or character_state == null:
		return
	var ent_owner := "character:%d" % player.id
	var char_owner := character_state.id if character_state.id.begins_with("character:") else "character:" + character_state.id
	if ent_owner == char_owner:
		return

	var ent_equipped := world_state.inventory.get_all_equipped(ent_owner)
	var ent_items := world_state.inventory.items_of(ent_owner)
	for uid: int in ent_items:
		world_state.inventory.transfer(uid, char_owner)
	for s in ent_equipped.keys():
		world_state.inventory.equip(char_owner, int(ent_equipped[s]))
