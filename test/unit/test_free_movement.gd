extends GutTest

## JGT-104: free 360-degree movement (8-way A*, string-pulled paths, exact
## click arrival, equal diagonal speed) and the 8-way Facing helper.

const SMALL_MAP := "res://data/zones/floor1/test_small.map"
const SMALL_JSON := "res://data/zones/floor1/test_small.json"

const LEGEND := {
	"entry": [1, 1],
	"legend": {
		"#": {"walkable": false, "type": "wall"},
		".": {"walkable": true, "type": "floor"},
		"s": {"walkable": true, "type": "floor", "safe": true},
	},
}

const OPEN_MAP := """############
#..........#
#..........#
#..........#
#..........#
#..........#
#..........#
#..........#
#..........#
#..........#
#..........#
############"""

var _registry: DataRegistry = null
var _speed: float = 0.0


func before_each() -> void:
	_registry = DataRegistry.new()
	_registry.load_dir("res://data")
	_speed = float(_registry.get_balance("player.move_speed_tiles_per_s"))


func _run_until_idle(sim: WorldSim, entity: Entity, max_ticks: int = 400) -> int:
	sim.step(sim.tick_length)
	var ticks := 1
	while ticks < max_ticks and entity.command != null:
		sim.step(sim.tick_length)
		ticks += 1
	return ticks


func _waypoints(entity: Entity) -> Array[Vector2]:
	var pts: Array[Vector2] = [entity.pos]
	for i in range(entity.path_index, entity.path.size()):
		pts.append(WorldSim.waypoint_position(entity.path, i, entity.path_goal))
	return pts


func test_movement_balance_is_data_driven() -> void:
	assert_eq(typeof(_registry.get_balance("movement.path_smoothing")), TYPE_BOOL)
	assert_gte(float(_registry.get_balance("movement.arrival_epsilon_tiles")), 0.0)
	var sim := WorldSim.new(Zone.load_from_strings(OPEN_MAP, LEGEND), _registry)
	assert_eq(sim.path_smoothing, bool(_registry.get_balance("movement.path_smoothing")))
	assert_almost_eq(sim.arrival_epsilon, float(_registry.get_balance("movement.arrival_epsilon_tiles")), 1e-9)


func test_diagonal_speed_equals_straight_speed() -> void:
	var zone := Zone.load_from_strings(OPEN_MAP, LEGEND)
	var sim_straight := WorldSim.new(zone, _registry)
	var sim_diag := WorldSim.new(zone, _registry)
	var straight := sim_straight.spawn("player", Vector2i(1, 1), _speed)
	var diag := sim_diag.spawn("player", Vector2i(1, 1), _speed)
	sim_straight.submit(Commands.move_to(straight.id, Vector2i(9, 1)))
	sim_diag.submit(Commands.move_to(diag.id, Vector2i(9, 9)))

	var ticks := 10
	for _i in range(ticks):
		sim_straight.step(sim_straight.tick_length)
		sim_diag.step(sim_diag.tick_length)

	var expected := _speed * sim_straight.tick_length * float(ticks)
	var start := Vector2(1.5, 1.5)
	assert_almost_eq(straight.pos.distance_to(start), expected, 1e-4, "straight distance per time")
	assert_almost_eq(diag.pos.distance_to(start), expected, 1e-4, "diagonal distance per time equals straight")
	# The diagonal walk is a true 45-degree line, not an L of orthogonal steps.
	assert_almost_eq(diag.pos.x - start.x, diag.pos.y - start.y, 1e-4)


func test_smoothed_path_has_fewer_waypoints_than_raw() -> void:
	var zone := Zone.load_from_strings(OPEN_MAP, LEGEND)
	var raw := zone.find_path(Vector2i(1, 1), Vector2i(10, 4))
	assert_gt(raw.size(), 2)
	var smoothed := WorldSim.smooth_path(zone, raw, WorldSim.tile_center(raw[0]))
	assert_lt(smoothed.size(), raw.size(), "smoothing drops waypoints")
	assert_eq(smoothed.size(), 2, "open room: start tile + straight line to the goal")
	assert_eq(smoothed[0], raw[0])
	assert_eq(smoothed[smoothed.size() - 1], raw[raw.size() - 1])

	# The live path an entity follows is smoothed as well.
	var sim := WorldSim.new(zone, _registry)
	var e := sim.spawn("player", Vector2i(1, 1), _speed)
	sim.submit(Commands.move_to(e.id, Vector2i(10, 4)))
	sim.step(sim.tick_length)
	assert_lt(e.path.size(), raw.size())


func test_smoothing_can_be_disabled() -> void:
	var zone := Zone.load_from_strings(OPEN_MAP, LEGEND)
	var raw := zone.find_path(Vector2i(1, 1), Vector2i(10, 4))
	var sim := WorldSim.new(zone, _registry)
	sim.path_smoothing = false
	var e := sim.spawn("player", Vector2i(1, 1), _speed)
	sim.path_entity_to_tile(e, Vector2i(10, 4))
	assert_eq(e.path, raw)


func test_smoothed_segments_never_cross_unwalkable_tiles() -> void:
	var zone := Zone.load_files(SMALL_MAP, SMALL_JSON)
	var floor1 := Zone.load_files("res://data/zones/floor1/floor1.map", "res://data/zones/floor1/floor1.json")
	var cases: Array = [
		[zone, Vector2i(1, 1), Vector2i(10, 1)],
		[zone, Vector2i(4, 1), Vector2i(6, 1)],
		[zone, Vector2i(1, 6), Vector2i(10, 6)],
		[floor1, floor1.entry, Vector2i(52, 33)],
	]
	for c: Array in cases:
		var z: Zone = c[0]
		var raw := z.find_path(c[1], c[2])
		assert_false(raw.is_empty(), "case %s -> %s must be reachable" % [str(c[1]), str(c[2])])
		var smoothed := WorldSim.smooth_path(z, raw, WorldSim.tile_center(raw[0]))
		assert_lte(smoothed.size(), raw.size())
		for i in range(smoothed.size() - 1):
			var a := WorldSim.tile_center(smoothed[i])
			var b := WorldSim.tile_center(smoothed[i + 1])
			assert_true(DashRules.is_segment_walkable(a, b, z), "segment %s -> %s must be walkable" % [str(a), str(b)])


func test_path_around_obstacle_reaches_target_on_walkable_ground() -> void:
	var zone := Zone.load_files(SMALL_MAP, SMALL_JSON)
	var sim := WorldSim.new(zone, _registry)
	var e := sim.spawn("player", Vector2i(1, 1), _speed)
	sim.submit(Commands.move_to(e.id, Vector2i(10, 1)))
	var prev := e.pos
	var visited_gap := false
	for _i in range(400):
		sim.step(sim.tick_length)
		assert_true(DashRules.is_segment_walkable(prev, e.pos, zone), "motion %s -> %s must stay walkable" % [str(prev), str(e.pos)])
		prev = e.pos
		if e.tile() == Vector2i(5, 6):
			visited_gap = true
		if e.command == null:
			break
	assert_null(e.command)
	assert_true(visited_gap, "the only way through the wall is the gap at (5, 6)")
	assert_almost_eq(e.pos.x, 10.5, 1e-3)
	assert_almost_eq(e.pos.y, 1.5, 1e-3)


func test_arrival_at_exact_click_point() -> void:
	var zone := Zone.load_from_strings(OPEN_MAP, LEGEND)
	var sim := WorldSim.new(zone, _registry)
	var e := sim.spawn("player", Vector2i(1, 1), _speed)
	var click := Vector2(7.83, 5.21)
	sim.submit(Commands.move_to_point(e.id, click))
	_run_until_idle(sim, e)
	assert_null(e.command)
	assert_almost_eq(e.pos.x, click.x, 1e-4)
	assert_almost_eq(e.pos.y, click.y, 1e-4)

	# Inside the same tile too.
	var near := Vector2(7.1, 5.9)
	sim.submit(Commands.move_to_point(e.id, near))
	_run_until_idle(sim, e)
	assert_almost_eq(e.pos.x, near.x, 1e-4)
	assert_almost_eq(e.pos.y, near.y, 1e-4)


func test_right_click_position_moves_to_exact_point() -> void:
	var zone := Zone.load_from_strings(OPEN_MAP, LEGEND)
	var sim := WorldSim.new(zone, _registry)
	var e := sim.spawn("player", Vector2i(1, 1), _speed)
	var click := Vector2(4.25, 8.75)
	var cmd := PlayerInput.command_for_right_click(sim, e.id, click)
	assert_true(cmd is Commands.MoveTo)
	assert_eq((cmd as Commands.MoveTo).target, Vector2i(4, 8))
	sim.submit(cmd)
	_run_until_idle(sim, e)
	assert_almost_eq(e.pos.x, click.x, 1e-4)
	assert_almost_eq(e.pos.y, click.y, 1e-4)


func test_tile_targets_still_end_on_tile_centre() -> void:
	var zone := Zone.load_from_strings(OPEN_MAP, LEGEND)
	var sim := WorldSim.new(zone, _registry)
	var e := sim.spawn("player", Vector2i(1, 1), _speed)
	sim.submit(Commands.move_to(e.id, Vector2i(6, 9)))
	_run_until_idle(sim, e)
	assert_eq(e.pos, WorldSim.tile_center(Vector2i(6, 9)))


func test_unwalkable_click_falls_back_to_nearest_tile_centre() -> void:
	var zone := Zone.load_files(SMALL_MAP, SMALL_JSON)
	var sim := WorldSim.new(zone, _registry)
	var e := sim.spawn("player", Vector2i(1, 1), _speed)
	var expected := zone.nearest_reachable(Vector2i(1, 1), Vector2i(5, 3))
	sim.submit(Commands.move_to_point(e.id, Vector2(5.4, 3.6)))
	_run_until_idle(sim, e)
	assert_almost_eq(e.pos.x, WorldSim.tile_center(expected).x, 1e-3)
	assert_almost_eq(e.pos.y, WorldSim.tile_center(expected).y, 1e-3)


func test_no_corner_cutting() -> void:
	var corner_map := """#####
#..##
#...#
##..#
#####"""
	var zone := Zone.load_from_strings(corner_map, LEGEND)
	# (1,1) -> (2,2) diagonal is fine; (2,1) -> (3,2) would cut the wall at (3,1).
	var path := zone.find_path(Vector2i(2, 1), Vector2i(3, 2))
	assert_eq(path.size(), 3, "corner must be walked around, not cut")
	for i in range(path.size() - 1):
		var d: Vector2i = path[i + 1] - path[i]
		if d.x != 0 and d.y != 0:
			assert_true(zone.is_walkable(path[i] + Vector2i(d.x, 0)) and zone.is_walkable(path[i] + Vector2i(0, d.y)))
	# Open diagonal is taken directly.
	assert_eq(zone.find_path(Vector2i(1, 1), Vector2i(2, 2)).size(), 2)

	var sim := WorldSim.new(zone, _registry)
	var e := sim.spawn("player", Vector2i(2, 1), _speed)
	sim.submit(Commands.move_to(e.id, Vector2i(3, 3)))
	var prev := e.pos
	for _i in range(200):
		sim.step(sim.tick_length)
		assert_true(DashRules.is_segment_walkable(prev, e.pos, zone), "motion %s -> %s cuts a corner" % [str(prev), str(e.pos)])
		prev = e.pos
		if e.command == null:
			break
	assert_eq(e.pos, WorldSim.tile_center(Vector2i(3, 3)))


func test_enemy_shortcuts_never_enter_safe_tiles() -> void:
	var safe_map := """#######
#.....#
#.sss.#
#.....#
#######"""
	var zone := Zone.load_from_strings(safe_map, LEGEND)
	var raw := zone.find_path(Vector2i(1, 1), Vector2i(5, 3))
	assert_true(raw.any(func(t: Vector2i) -> bool: return zone.is_safe(t)), "raw path crosses the safe strip")
	var smoothed := WorldSim.smooth_path(zone, raw, WorldSim.tile_center(raw[0]), Vector2.INF, true)
	# A shortcut (skipping raw tiles) never enters a safe tile; only raw single steps may.
	for i in range(smoothed.size() - 1):
		if raw.find(smoothed[i + 1]) - raw.find(smoothed[i]) <= 1:
			continue
		var a := WorldSim.tile_center(smoothed[i])
		var b := WorldSim.tile_center(smoothed[i + 1])
		assert_false(zone.segment_crosses_safe(a, b, smoothed[i]), "enemy shortcut %s -> %s enters a safe tile" % [str(a), str(b)])
	# Without avoid_safe the same path cuts straight through the safe tiles.
	var player_path := WorldSim.smooth_path(zone, raw, WorldSim.tile_center(raw[0]))
	assert_lte(player_path.size(), smoothed.size())
	# Every safe tile on the raw path is kept, so EnemyAI can still cut the path before it.
	for t: Vector2i in raw:
		if zone.is_safe(t):
			assert_true(smoothed.has(t), "safe tile %s on the raw path must stay a waypoint" % str(t))


func test_facing_tracks_movement_direction() -> void:
	var zone := Zone.load_from_strings(OPEN_MAP, LEGEND)
	var sim := WorldSim.new(zone, _registry)
	var e := sim.spawn("player", Vector2i(5, 5), _speed)
	assert_eq(e.facing_octant(), Facing.NONE)
	sim.submit(Commands.move_to(e.id, Vector2i(9, 9)))
	sim.step(sim.tick_length)
	assert_eq(e.facing_octant(), Facing.SOUTH_EAST)
	sim.submit(Commands.move_to(e.id, Vector2i(1, e.tile().y)))
	sim.step(sim.tick_length)
	sim.step(sim.tick_length)
	assert_eq(e.facing_octant(), Facing.WEST)


func test_octant_quantization_table() -> void:
	var table: Array = [
		[Vector2(1, 0), Facing.EAST],
		[Vector2(1, 1), Facing.SOUTH_EAST],
		[Vector2(0, 1), Facing.SOUTH],
		[Vector2(-1, 1), Facing.SOUTH_WEST],
		[Vector2(-1, 0), Facing.WEST],
		[Vector2(-1, -1), Facing.NORTH_WEST],
		[Vector2(0, -1), Facing.NORTH],
		[Vector2(1, -1), Facing.NORTH_EAST],
		[Vector2.ZERO, Facing.NONE],
		[Vector2(INF, 0), Facing.NONE],
		# Off-axis vectors snap to the nearest octant.
		[Vector2(10, 3), Facing.EAST],
		[Vector2(10, -3), Facing.EAST],
		[Vector2(3, 10), Facing.SOUTH],
		[Vector2(-10, 1), Facing.WEST],
		[Vector2(5, 4), Facing.SOUTH_EAST],
		[Vector2(-4, -5), Facing.NORTH_WEST],
	]
	for row: Array in table:
		assert_eq(Facing.octant(row[0]), row[1], "octant(%s)" % str(row[0]))
	# Scale does not matter.
	assert_eq(Facing.octant(Vector2(0.001, 0.001)), Facing.SOUTH_EAST)
	assert_eq(Facing.octant(Vector2(500, -500)), Facing.NORTH_EAST)
