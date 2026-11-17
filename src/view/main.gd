class_name MainView
extends Node2D

const ZONE_MAP_PATH: String = "res://data/zones/floor1/floor1.map"
const ZONE_JSON_PATH: String = "res://data/zones/floor1/floor1.json"
## Chunked Floor 1: the running game streams these chunks (the classic single
## zone above stays as the fallback when the chunked world cannot load).
const WORLD_PATH: String = "res://data/zones/floor1/world.json"
const ZONES_DIR: String = "res://data/zones/floor1"
const START_CHUNK: String = "floor1_x2_y1"
const DATA_DIR: String = "res://data"
const DEFAULT_SAVE_ROOT: String = "user://saves"
const DEFAULT_SAVE_SLOT: String = "slot_1"
const DEFAULT_PLAYER_NAME: String = "Hero"
const APPEARANCES_PATH: String = "res://data/appearances.json"
const PLAYER_APPEARANCE_ID: String = "player_default"

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
## LayeredSprite drawing the player inside player_marker (null when only the diamond
## fallback marker could be built).
var player_sprite: LayeredSprite = null
## "placeholder" or "none" (diamond marker) - which art the player uses.
var player_sprite_source: String = CharacterAppearance.SOURCE_NONE
var player_animator: CharacterAnimator = CharacterAnimator.new()
var entity_layer: EntityLayer = null
var hud: HUD = null
var vfx_layer: VfxLayer = null
## White hit flash on the player sprite (or the diamond marker), JGT-87.
var player_flash: HitFlash = null
var max_frame_dt_s: float = 0.0

var world_state: WorldState = null
## Chunk streaming for the chunked floor (null when running the classic single zone).
var chunked_world: ChunkedWorld = null
## One tilemap per loaded chunk, keyed by chunk id.
var chunk_views: Dictionary = {}
var chunks_root: Node2D = null
var character_state: CharacterState = null
var save_store: SaveStore = null
var death_screen: DeathScreen = null
var merchant_id: String = ""
var npc_views: Array[NpcView] = []
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

	# 2. Load the chunked floor, starting in the town chunk. The classic single
	#    zone remains the fallback when the chunked world cannot load.
	chunked_world = ChunkedWorld.load_file(WORLD_PATH, ZONES_DIR, START_CHUNK)
	if chunked_world.is_valid():
		zone = ChunkedZone.new(chunked_world)
	else:
		push_error("MainView: Failed to load chunked floor: %s" % str(chunked_world.errors))
		chunked_world = null
		var map_path := zone_map_path if not zone_map_path.is_empty() else ZONE_MAP_PATH
		var json_path := zone_json_path if not zone_json_path.is_empty() else ZONE_JSON_PATH
		zone = Zone.load_files(map_path, json_path)
		if not zone.is_valid():
			push_error("MainView: Failed to load zone: %s" % str(zone.errors))
			return

	# 3. Setup the ZoneView used for tile<->world conversions. On a chunked floor
	#    each loaded chunk gets its own ZoneView, positioned at its chunk offset.
	if zone_view == null:
		zone_view = ZoneView.new()
		zone_view.name = "ZoneView"
		add_child(zone_view)
	zone_view.setup(registry)
	if chunked_world != null:
		_ensure_chunks_root()
		_sync_chunk_views()
	else:
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

	var new_character_created := false
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
			# A new character starts in the chunked floor's start chunk (the
			# town); the classic fallback keeps its zone entry.
			var new_chunk := ""
			var new_entry: Variant = zone.entry if zone != null else null
			if chunked_world != null:
				var start := ChunkResume.start_position(chunked_world)
				if bool(start.get("ok", false)):
					new_chunk = str(start.get("chunk", ""))
					new_entry = start.get("local_tile")
			var create_res := Lifecycle.new_character(
				world_state,
				init_name,
				{},
				new_entry,
				save_store,
				save_slot,
				null,
				"floor1",
				registry,
				new_chunk
			)
			if create_res.get("ok", false):
				character_state = create_res.get("value")
				new_character_created = true

	LaunchRequest.reset()

	# 5b. Resume the character's chunk before the session is built: stream the
	#     floor around the saved chunk and spawn there. A classic save (empty
	#     chunk) keeps the start area and its saved_spawn_pos path; a chunk that
	#     cannot be resumed falls back to the start chunk entry.
	var resume_spawn: Variant = null
	if chunked_world != null and character_state != null and not character_state.chunk.is_empty():
		var resumed := ChunkResume.resume(chunked_world.map, chunked_world.loader, character_state)
		if bool(resumed.get("ok", false)) and bool(resumed.get("chunked", false)):
			var resumed_tile: Vector2i = resumed.get("world_tile", Vector2i(-1, -1))
			chunked_world.update(resumed_tile)
			resume_spawn = resumed.get("world_pos", resumed_tile)
		else:
			var start := ChunkResume.start_position(chunked_world)
			if bool(start.get("ok", false)):
				var start_tile: Vector2i = start.get("world_tile", Vector2i(-1, -1))
				var start_pos: Variant = start.get("world_pos")
				chunked_world.update(start_tile)
				# Drop the unreadable chunk/position so a later save (or death
				# record) does not carry it forward.
				ChunkResume.capture_position(chunked_world.map, character_state, start_pos)
				resume_spawn = start_pos
		zone = ChunkedZone.new(chunked_world)
		_clear_chunk_views()
		_sync_chunk_views()

	# 6. Create GameSession, spawn player and zone enemies
	session = GameSession.new(zone, registry, inventory, item_db)
	session.zone_loader = Callable(self, "_load_travel_zone")
	world = session.world
	var player_speed: float = float(registry.get_balance("player.move_speed_tiles_per_s", 4.0))
	var spawn_pos: Variant = zone.entry
	var saved_pos: Variant = null
	if character_state != null and not character_state.chunk.is_empty():
		# Chunked save: resume already streamed the floor around its chunk.
		if resume_spawn != null:
			spawn_pos = resume_spawn
	elif character_state != null:
		saved_pos = saved_spawn_pos(zone, character_state.position)
		if saved_pos != null:
			spawn_pos = saved_pos
	player = session.spawn_player(spawn_pos, player_speed)
	if saved_pos != null:
		player.pos = saved_pos
	elif character_state != null and not new_character_created and resume_spawn is Vector2:
		# Resume keeps the saved sub-tile position (spawn snapped it to the tile
		# center for the walkability check). A character created just now keeps
		# the tile-center spawn, as before.
		player.pos = resume_spawn
	if character_state != null and character_state.stats != null:
		player.stats = character_state.stats.duplicate()
	if world_state != null:
		world.set_bosses_defeated(world_state.bosses_defeated)
	session.spawn_enemies()
	_sync_items_to_entity()

	# 7. Create Player Marker
	_create_player_marker()

	# 7b. Create EntityLayer
	_create_entity_layer()

	# 7b2. Skill VFX layer (world space, fed every sim event)
	if entities_root != null and vfx_layer == null:
		vfx_layer = VfxLayer.create(entities_root, world, zone_view, registry)
		event_emitted.connect(vfx_layer.handle_event)

	# 7c. Draw zone NPCs
	_create_npc_views()

	# 8. Setup Camera
	if camera == null:
		camera = GameCamera.new()
		camera.name = "Camera"
		add_child(camera)
	camera.enabled = true
	camera.setup(registry)
	if entity_layer != null:
		entity_layer.camera = camera
	_update_camera_bounds()

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

	if not player_input.npc_interact.is_connected(_on_npc_interact):
		player_input.npc_interact.connect(_on_npc_interact)
	var m_panel := hud.get_merchant_panel() if hud != null else null
	if m_panel != null and not m_panel.item_taken.is_connected(_on_merchant_item_taken):
		m_panel.item_taken.connect(_on_merchant_item_taken)

	# 11. Setup DeathScreen
	_create_death_screen()

	if not event_emitted.is_connected(_on_event_emitted):
		event_emitted.connect(_on_event_emitted)

	TelegraphWindupPreview.setup_if_requested(self)
	LayeredSpritePreview.setup_if_requested(self)
	HudPreview.setup_if_requested(self)
	DeathScreenPreview.setup_if_requested(self)
	VfxPreview.setup_if_requested(self)
	HitSequencePreview.setup_if_requested(self)

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


## Draws one tilemap per loaded chunk, each positioned at its chunk offset.
func _ensure_chunks_root() -> void:
	if chunks_root != null:
		return
	chunks_root = Node2D.new()
	chunks_root.name = "Chunks"
	add_child(chunks_root)
	# Chunks draw above the origin ZoneView but below the Entities node.
	move_child(chunks_root, 1)


func _sync_chunk_views() -> void:
	if chunked_world == null or chunks_root == null:
		return

	var loaded: Dictionary = {}
	for chunk_id: String in chunked_world.loaded_ids():
		loaded[chunk_id] = true
		if chunk_views.has(chunk_id):
			continue
		var chunk_zone := chunked_world.zone_for(chunk_id)
		if chunk_zone == null:
			continue
		var view := ZoneView.new()
		view.name = "Chunk_%s" % chunk_id
		view.setup(registry)
		view.build(chunk_zone)
		var offset := chunked_world.chunk_offset(chunk_id)
		view.position = Vector2(offset) * float(zone_view.tile_px)
		chunks_root.add_child(view)
		chunk_views[chunk_id] = view

	var stale: Array[String] = []
	for chunk_key: Variant in chunk_views.keys():
		if not loaded.has(str(chunk_key)):
			stale.append(str(chunk_key))
	for chunk_id: String in stale:
		var view: ZoneView = chunk_views[chunk_id]
		chunk_views.erase(chunk_id)
		if is_instance_valid(view):
			if view.get_parent() != null:
				view.get_parent().remove_child(view)
			view.queue_free()


## Streams chunks around the player; rebuilds chunk tilemaps and NPCs when the
## loaded set changed.
func _update_chunks() -> void:
	if session == null or player == null or chunked_world == null:
		return
	var tile := Vector2i(floori(player.pos.x), floori(player.pos.y))
	var changes := session.update_chunks(tile)
	if not bool(changes.get("changed", false)):
		return
	_sync_chunk_views()
	_create_npc_views(true)


## Reacts to a gate/door travel resolved by the session. A gate only changes the
## loaded chunks; a door switches the whole zone, so every view is rebound.
func _handle_travel(travel: Dictionary) -> void:
	if bool(travel.get("zone_changed", false)):
		_rebuild_after_zone_change()
		return
	if str(travel.get("kind", "")) == "gate":
		_sync_chunk_views()
		_create_npc_views(true)


## Rebinds the simulation world and every view after a door switched zones.
func _rebuild_after_zone_change() -> void:
	if session == null or session.player == null:
		return
	zone = session.zone
	world = session.world
	player = session.player

	if in_chunked_mode():
		zone_view.build(null)
		_sync_chunk_views()
	else:
		_clear_chunk_views()
		zone_view.build(zone)
	_update_camera_bounds()
	_create_npc_views(true)

	player_animator.reset(player.pos)
	if player_input != null:
		player_input.process_mode = Node.PROCESS_MODE_INHERIT
		player_input.setup(player.id, world, zone_view, registry)
	if entity_layer != null:
		entity_layer.reset()
		entity_layer.setup(session, zone_view, registry, player_marker)
	if vfx_layer != null:
		vfx_layer.setup(world, zone_view, registry)
	if hud != null:
		hud.clear_loot_markers()
		hud.setup(session, world, player, inventory, item_db, registry, entities_root, zone_view)
	_sync_items_to_entity()


## True when the session currently runs on the chunked floor.
func in_chunked_mode() -> bool:
	return session != null and session.in_chunked_world()


## Pixels the camera may show: the loaded floor/chunked map in tiles times tile size.
func _update_camera_bounds() -> void:
	if camera == null:
		return
	var tiles := Vector2.ZERO
	var use_chunks := chunked_world != null and chunked_world.is_valid() and (session == null or in_chunked_mode())
	if use_chunks:
		tiles = Vector2(float(chunked_world.world_width()), float(chunked_world.world_height()))
	elif zone != null:
		tiles = Vector2(float(zone.width), float(zone.height))
	var tile_px := float(zone_view.tile_px) if zone_view != null else float(ZoneView.DEFAULT_TILE_PX)
	camera.set_map_bounds(GameCamera.bounds_for(tiles, tile_px))


## Frees every chunk tilemap (entering a classic door zone, or rebuilding the floor).
func _clear_chunk_views() -> void:
	var ids: Array[String] = []
	for chunk_key: Variant in chunk_views.keys():
		ids.append(str(chunk_key))
	for chunk_id: String in ids:
		var view: ZoneView = chunk_views[chunk_id]
		chunk_views.erase(chunk_id)
		if is_instance_valid(view):
			if view.get_parent() != null:
				view.get_parent().remove_child(view)
			view.queue_free()


## Zone loader the session uses for door transitions.
func _load_travel_zone(stem: String) -> Zone:
	return Zone.load_files(
		ZONES_DIR.path_join(stem + ".map"),
		ZONES_DIR.path_join(stem + ".json")
	)


func _create_npc_views(force: bool = false) -> void:
	if entities_root == null:
		return
	if not force and not npc_views.is_empty():
		return
	for view: NpcView in npc_views:
		if is_instance_valid(view):
			if view.get_parent() != null:
				view.get_parent().remove_child(view)
			view.queue_free()
	npc_views.clear()
	npc_views = NpcView.build_all(zone, entities_root, zone_view)


func _on_npc_interact(npc_id: String) -> void:
	if hud != null:
		hud.open_merchant(npc_id)


## Taking from a merchant changes the world, so it is written to the save at once.
func _on_merchant_item_taken(_uid: int) -> void:
	save_now()


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
	# Record the chunk the player died in before the character is written, so
	# the cemetery entry keeps it.
	_capture_character_position()
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
	# The new character starts in the town: stream the floor back to the start
	# chunk first, so zone.entry (used below and to spawn) is the town entry.
	_stream_chunks_to_start()
	# The new character starts in the town chunk, like a fresh character.
	var new_chunk := ""
	var new_entry: Variant = zone.entry if zone != null else null
	if chunked_world != null:
		var start := ChunkResume.start_position(chunked_world)
		if bool(start.get("ok", false)):
			new_chunk = str(start.get("chunk", ""))
			new_entry = start.get("local_tile")
	var create_res := Lifecycle.new_character(
		world_state,
		valid_name,
		{},
		new_entry,
		save_store,
		save_slot,
		null,
		"floor1",
		registry,
		new_chunk
	)

	if not create_res.get("ok", false):
		if death_screen != null:
			death_screen.show_error(str(create_res.get("error", "Failed to create character")))
		return

	character_state = create_res.get("value") as CharacterState
	_respawn_new_character()


## Streams the chunked floor back to the start chunk (the town), so a new
## character always respawns in a loaded town, whatever chunk (or door zone)
## the previous character died in. No-op on the classic single-zone fallback.
func _stream_chunks_to_start() -> void:
	if chunked_world == null:
		return
	var start_tile := chunked_world.chunk_offset(chunked_world.start_chunk)
	chunked_world.update(start_tile)
	zone = ChunkedZone.new(chunked_world)
	_clear_chunk_views()
	if zone_view != null:
		zone_view.build(null)
	_sync_chunk_views()
	_create_npc_views(true)


func _respawn_new_character() -> void:
	_stream_chunks_to_start()
	session = GameSession.new(zone, registry, inventory, item_db)
	session.zone_loader = Callable(self, "_load_travel_zone")
	world = session.world

	var player_speed: float = float(registry.get_balance("player.move_speed_tiles_per_s", 4.0))
	player = session.spawn_player(zone.entry, player_speed)
	session.spawn_enemies()
	_sync_items_to_entity()
	player_animator.reset(player.pos)

	if player_input != null:
		player_input.process_mode = Node.PROCESS_MODE_INHERIT
		player_input.setup(player.id, world, zone_view, registry)

	if entity_layer != null:
		entity_layer.reset()
		entity_layer.setup(session, zone_view, registry, player_marker)

	if vfx_layer != null:
		vfx_layer.setup(world, zone_view, registry)

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
		entity_layer.view_parent = entities_root
		return

	var layer := EntityLayer.new()
	layer.name = "EntityLayer"
	entities_root.add_child(layer)
	layer.view_parent = entities_root
	entity_layer = layer
	entity_layer.setup(session, zone_view, registry, player_marker)
	entity_layer.event_emitted.connect(func(ev: Dictionary) -> void: event_emitted.emit(ev))


## Builds the "PlayerMarker" node (EntityLayer hangs the HP bar on it). The player is
## drawn by a LayeredSprite from data/appearances.json (one stacked sheet per layer); the
## diamond marker is only used if no sheet loads at all.
func _create_player_marker() -> void:
	if entities_root.has_node("PlayerMarker"):
		player_marker = entities_root.get_node("PlayerMarker") as Node2D
		player_sprite = player_marker.get_node_or_null("PlayerSprite") as LayeredSprite
		return

	var marker := Node2D.new()
	marker.name = "PlayerMarker"

	var sprite := _build_player_sprite()
	if sprite != null:
		marker.add_child(sprite)
		player_sprite = sprite
		var layout_hp_offset: Variant = sprite.layout.get("hp_bar_y_offset", null)
		if layout_hp_offset != null:
			marker.set_meta("hp_bar_y_offset", float(layout_hp_offset))
	else:
		_add_diamond_marker(marker)

	entities_root.add_child(marker)
	player_marker = marker
	if player != null:
		player_animator.reset(player.pos)


## Returns a LayeredSprite for the player appearance, or null if no art could be loaded.
func _build_player_sprite() -> LayeredSprite:
	var appearances := CharacterAppearance.load_json(APPEARANCES_PATH)
	var entry := CharacterAppearance.get_appearance(appearances, PLAYER_APPEARANCE_ID)
	if entry.is_empty():
		push_warning("MainView: appearance '%s' missing; using marker" % PLAYER_APPEARANCE_ID)
		return null
	var sprite := LayeredSprite.new()
	if sprite.layout.is_empty():
		sprite.free()
		return null
	var built := CharacterAppearance.build_textures(entry, sprite.layout)
	player_sprite_source = str(built.get("source", CharacterAppearance.SOURCE_NONE))
	var textures: Dictionary = built.get("layers", {})
	if textures.is_empty():
		player_sprite_source = CharacterAppearance.SOURCE_NONE
		sprite.free()
		return null
	sprite.name = "PlayerSprite"
	sprite.set_layer_textures(textures)
	sprite.play(CharacterAnimator.ANIM_IDLE, "down")
	return sprite


## Fallback player marker (no sprite art available at all).
func _add_diamond_marker(marker: Node2D) -> void:
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


## Reads this frame's sim events and returns a Vector2 toward the player's attack target
## if the player attacked (damage dealt or skill cast), else null. View-only read.
func _player_attack_dir(events: Array[Dictionary]) -> Variant:
	if player == null:
		return null
	for ev: Dictionary in events:
		var ev_type := str(ev.get("type", ""))
		if int(ev.get("source", -1)) != player.id:
			continue
		if ev_type == "damage":
			var target: Entity = world.entities.get(int(ev.get("target", -1)), null) if world != null else null
			return (target.pos - player.pos) if target != null else Vector2.ZERO
		if ev_type == "skill_cast":
			return Vector2.ZERO
	return null


## The player's current basic attack interval in seconds (effective stats, else the
## balance value), 0 if unknown. View-only read; times the slash animation.
func _player_attack_interval_s() -> float:
	if player == null:
		return 0.0
	var stats: Stats = world.effective_stats(player) if world != null else player.stats
	if stats != null and stats.attack_interval > 0.0:
		return stats.attack_interval
	if registry != null and not player.kind.is_empty():
		var val: Variant = registry.get_balance(player.kind + ".attack_interval")
		if val is float or val is int:
			return maxf(float(val), 0.0)
	return 0.0


## True if this frame's sim events contain damage dealt to the player. View-only read.
func _player_was_damaged(events: Array[Dictionary]) -> bool:
	if player == null:
		return false
	for ev: Dictionary in events:
		if str(ev.get("type", "")) == "damage" and int(ev.get("target", -1)) == player.id:
			return true
	return false


func _exit_tree() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _on_attack_mode_changed(active: bool) -> void:
	if active:
		Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	else:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _process(delta: float) -> void:
	if TelegraphWindupPreview.is_active or LayeredSpritePreview.is_active or HudPreview.is_active or DeathScreenPreview.is_active or VfxPreview.is_active or HitSequencePreview.is_active:
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


## Saved character position as a Vector2, or null when it is missing or its tile is not
## walkable in this zone (e.g. a save made on an older map), so the caller uses zone.entry.
static func saved_spawn_pos(p_zone: Zone, position: Array) -> Variant:
	if p_zone == null or position.size() < 2:
		return null
	var pos := Vector2(float(position[0]), float(position[1]))
	if not pos.is_finite():
		return null
	if not p_zone.is_walkable(Vector2i(floori(pos.x), floori(pos.y))):
		return null
	return pos


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

	if session != null:
		var travel := session.take_travel()
		if not travel.is_empty():
			_handle_travel(travel)

	_update_chunks()

	var world_pos := zone_view.entity_to_world(player.pos)
	if player_marker != null:
		player_marker.position = world_pos

	if entity_layer != null:
		entity_layer.sync()

	var events: Array[Dictionary] = entity_layer.last_events if entity_layer != null else []
	var player_hit := _player_was_damaged(events)
	if player_hit:
		_play_player_hit_feedback()
	if player_sprite != null:
		var now_tick: int = world.tick_count if world != null else 0
		if player_hit:
			player_animator.trigger_hurt(player_sprite, now_tick, world.tick_length if world != null else 0.0)
		var attack_dir: Variant = _player_attack_dir(events)
		var slash_s := 0.0
		if attack_dir != null:
			slash_s = CharacterAnimator.slash_seconds_within(player_sprite.layout, _player_attack_interval_s())
		player_animator.update(player_sprite, player.pos, player.dead, attack_dir, now_tick, slash_s)

	if camera != null:
		camera.follow(world_pos)

	if hud != null:
		hud.update_view()


## View-only: the player was hit this frame -> flash the player and shake the camera.
func _play_player_hit_feedback() -> void:
	if player_flash == null and player_marker != null:
		player_flash = HitFlash.attach(player_marker, player_sprite if player_sprite != null else player_marker, registry)
	if player_flash != null:
		player_flash.trigger()
	if camera != null:
		camera.shake()


## Records where the player stands in the save: chunk + chunk-local position on
## the chunked floor; inside a door's zone (the dungeon) the door's return chunk
## and tile, so a load resumes on the chunked floor; the raw world position on
## the classic single-zone path. Leaves the character untouched when the
## position cannot be recorded safely.
func _capture_character_position() -> void:
	if character_state == null or player == null:
		return
	if in_chunked_mode() and chunked_world != null:
		ChunkResume.capture_position(chunked_world.map, character_state, player.pos)
		return
	if chunked_world != null:
		# Inside a door's zone: keep the chunk the door returns to (never write
		# zone coordinates as a chunk-local position).
		if session != null and not session.active_door.is_empty():
			ChunkResume.capture_door_return(chunked_world.map, character_state, session.active_door)
		return
	# Classic single-zone path: keep the old raw world position.
	if character_state.chunk.is_empty():
		character_state.position = [player.pos.x, player.pos.y]


func save_now() -> Dictionary:
	if save_store == null or world_state == null:
		return {"ok": false, "error": "MainView is not initialized", "value": null}

	if character_state != null and character_state.status != "dead" and player != null:
		_capture_character_position()
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
