class_name MainView
extends Node2D

const ZONE_MAP_PATH: String = "res://data/zones/floor1/test_small.map"
const ZONE_JSON_PATH: String = "res://data/zones/floor1/test_small.json"
const DATA_DIR: String = "res://data"

@onready var zone_view: ZoneView = $ZoneView if has_node("ZoneView") else null
@onready var entities_root: Node2D = $Entities if has_node("Entities") else null
@onready var camera: GameCamera = $Camera if has_node("Camera") else null

var registry: DataRegistry = null
var zone: Zone = null
var world: WorldSim = null
var player: Entity = null
var player_marker: Node2D = null
var max_frame_dt_s: float = 0.0


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
	zone = Zone.load_files(ZONE_MAP_PATH, ZONE_JSON_PATH)
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

	# 5. Create WorldSim and spawn player
	world = WorldSim.new(zone, registry)
	var player_speed: float = float(registry.get_balance("player.move_speed_tiles_per_s", 4.0))
	player = world.spawn("player", zone.entry, player_speed)

	# 6. Create Player Marker
	_create_player_marker()

	# 7. Setup Camera
	if camera == null:
		camera = GameCamera.new()
		camera.name = "Camera"
		add_child(camera)
	camera.enabled = true
	camera.setup(registry)

	# Initial view update
	_update_views()


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


func _process(delta: float) -> void:
	if world != null:
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

	if camera != null:
		camera.follow(world_pos)
