extends GutTest

const MAP_PATH: String = "res://data/zones/floor1/test_small.map"
const JSON_PATH: String = "res://data/zones/floor1/test_small.json"
const DATA_DIR: String = "res://data"

var _registry: DataRegistry = null
var _zone: Zone = null
var _sim: WorldSim = null
var _player: Entity = null


func before_each() -> void:
	_registry = DataRegistry.new()
	_registry.load_dir(DATA_DIR)
	_zone = Zone.load_files(MAP_PATH, JSON_PATH)
	_sim = WorldSim.new(_zone, _registry)
	_player = _sim.spawn("player", _zone.entry, 4.0)


func test_right_click_on_ground_emits_move_to() -> void:
	# Entry of test_small is at (1, 1). Tile (2, 1) is a walkable floor tile.
	var target_pos := Vector2(2.5, 1.5)
	var cmd: Commands.Command = PlayerInput.command_for_right_click(_sim, _player.id, target_pos)

	assert_not_null(cmd)
	assert_true(cmd is Commands.MoveTo)
	var move_cmd: Commands.MoveTo = cmd as Commands.MoveTo
	assert_eq(move_cmd.entity_id, _player.id)
	assert_eq(move_cmd.target, Vector2i(2, 1))

	# Test passing Vector2i tile directly
	var cmd_tile: Commands.Command = PlayerInput.command_for_right_click(_sim, _player.id, Vector2i(2, 1))
	assert_not_null(cmd_tile)
	assert_true(cmd_tile is Commands.MoveTo)
	assert_eq((cmd_tile as Commands.MoveTo).target, Vector2i(2, 1))


func test_right_click_on_enemy_emits_attack_target() -> void:
	var enemy := _sim.spawn("enemy", Vector2i(3, 1), 2.0)
	var mouse_pos := enemy.pos + Vector2(0.1, -0.1)

	var cmd: Commands.Command = PlayerInput.command_for_right_click(_sim, _player.id, mouse_pos, 0.5)
	assert_not_null(cmd)
	assert_true(cmd is Commands.AttackTarget)
	var attack_cmd: Commands.AttackTarget = cmd as Commands.AttackTarget
	assert_eq(attack_cmd.entity_id, _player.id)
	assert_eq(attack_cmd.target_id, enemy.id)


func test_dead_enemies_are_not_picked() -> void:
	var enemy := _sim.spawn("enemy", Vector2i(3, 1), 2.0)
	enemy.dead = true

	var picked := PlayerInput.pick_enemy_at(_sim, enemy.pos, 0.5)
	assert_null(picked, "Dead enemy must not be picked by pick_enemy_at")

	# Right-clicking on dead enemy tile falls back to MoveTo ground
	var cmd: Commands.Command = PlayerInput.command_for_right_click(_sim, _player.id, enemy.pos, 0.5)
	assert_not_null(cmd)
	assert_true(cmd is Commands.MoveTo)
	assert_eq((cmd as Commands.MoveTo).target, Vector2i(3, 1))


func test_nearest_enemy_wins() -> void:
	# Spawn two enemies at different distances from cursor (3.5, 1.5)
	var enemy_close := _sim.spawn("enemy", Vector2i(3, 1), 2.0)
	var enemy_far := _sim.spawn("enemy", Vector2i(6, 1), 2.0)

	var cursor := Vector2(3.6, 1.5)
	var picked := PlayerInput.pick_enemy_at(_sim, cursor, 2.0)
	assert_not_null(picked)
	assert_eq(picked.id, enemy_close.id, "Nearest enemy should be chosen")

	cursor = Vector2(6.2, 1.5)
	picked = PlayerInput.pick_enemy_at(_sim, cursor, 2.0)
	assert_not_null(picked)
	assert_eq(picked.id, enemy_far.id, "Nearest enemy should be chosen")


func test_enemy_ties_broken_by_id() -> void:
	var e1 := _sim.spawn("enemy", Vector2i(2, 1), 2.0)
	var e2 := _sim.spawn("enemy", Vector2i(4, 1), 2.0)

	# Midpoint between (2.5, 1.5) and (4.5, 1.5) is (3.5, 1.5)
	# Distance from (3.5, 1.5) to both is exactly 1.0
	var mid := Vector2(3.5, 1.5)
	assert_almost_eq(e1.pos.distance_to(mid), e2.pos.distance_to(mid), 0.0001)

	var picked := PlayerInput.pick_enemy_at(_sim, mid, 1.5)
	assert_not_null(picked)
	var lower_id: int = mini(e1.id, e2.id)
	assert_eq(picked.id, lower_id, "Ties must be broken by lowest entity id")


func test_right_click_unwalkable_or_out_of_bounds_returns_null() -> void:
	# Tile (0, 0) is a wall tile in test_small
	assert_false(_zone.is_walkable(Vector2i(0, 0)))

	var wall_pos := Vector2(0.5, 0.5)
	var cmd_wall: Commands.Command = PlayerInput.command_for_right_click(_sim, _player.id, wall_pos)
	assert_null(cmd_wall, "Click on unwalkable wall tile should not emit a MoveTo command")

	# Out of bounds
	var oob_pos := Vector2(-5.0, -10.0)
	var cmd_oob: Commands.Command = PlayerInput.command_for_right_click(_sim, _player.id, oob_pos)
	assert_null(cmd_oob, "Click out of bounds should not emit a MoveTo command")


func test_cast_skill_q_w_r_emits_right_slot_and_correct_aim() -> void:
	var aim_target := Vector2(7.2, 4.8)

	var cmd_q: Commands.CastSkill = PlayerInput.command_for_skill(_player.id, "Q", aim_target)
	assert_not_null(cmd_q)
	assert_eq(cmd_q.entity_id, _player.id)
	assert_eq(cmd_q.slot, "Q")
	assert_eq(cmd_q.aim, aim_target)

	var cmd_w: Commands.CastSkill = PlayerInput.command_for_skill(_player.id, "W", aim_target)
	assert_not_null(cmd_w)
	assert_eq(cmd_w.entity_id, _player.id)
	assert_eq(cmd_w.slot, "W")
	assert_eq(cmd_w.aim, aim_target)

	var cmd_r: Commands.CastSkill = PlayerInput.command_for_skill(_player.id, "R", aim_target)
	assert_not_null(cmd_r)
	assert_eq(cmd_r.entity_id, _player.id)
	assert_eq(cmd_r.slot, "R")
	assert_eq(cmd_r.aim, aim_target)


func test_dash_emits_normalised_direction() -> void:
	var player_pos := Vector2(2.0, 3.0)
	var mouse_pos := Vector2(5.0, 3.0) # dx = 3, dy = 0

	var cmd: Commands.Dash = PlayerInput.command_for_dash(_player.id, player_pos, mouse_pos)
	assert_not_null(cmd)
	assert_eq(cmd.entity_id, _player.id)
	assert_almost_eq(cmd.aim.x, 1.0, 1e-6)
	assert_almost_eq(cmd.aim.y, 0.0, 1e-6)
	assert_almost_eq(cmd.aim.length(), 1.0, 1e-6)

	# Diagonal direction
	var mouse_diag := Vector2(4.0, 5.0) # dx = 2, dy = 2
	var cmd_diag: Commands.Dash = PlayerInput.command_for_dash(_player.id, player_pos, mouse_diag)
	assert_not_null(cmd_diag)
	assert_almost_eq(cmd_diag.aim.length(), 1.0, 1e-6)
	var expected_diag := (mouse_diag - player_pos).normalized()
	assert_almost_eq(cmd_diag.aim.x, expected_diag.x, 1e-6)
	assert_almost_eq(cmd_diag.aim.y, expected_diag.y, 1e-6)


func test_mouse_on_player_zero_aim_handled() -> void:
	var pos := Vector2(2.0, 2.0)

	# Pure helper aim_from with zero offset
	var zero_aim: Vector2 = PlayerInput.aim_from(pos, pos)
	assert_eq(zero_aim, Vector2.ZERO, "aim_from with mouse on player returns Vector2.ZERO")

	# aim_from with fallback
	var fallback_aim: Vector2 = PlayerInput.aim_from(pos, pos, Vector2(0.0, -1.0))
	assert_almost_eq(fallback_aim.y, -1.0, 1e-6)

	# Dash with mouse on player emits nothing (returns null)
	var dash_cmd: Commands.Dash = PlayerInput.command_for_dash(_player.id, pos, pos)
	assert_null(dash_cmd, "Dash when mouse on player should emit nothing (null)")

	# Dash with mouse on player and fallback
	var dash_fallback: Commands.Dash = PlayerInput.command_for_dash(_player.id, pos, pos, Vector2.RIGHT)
	assert_not_null(dash_fallback)
	assert_almost_eq(dash_fallback.aim.x, 1.0, 1e-6)

	# Skill with mouse on player emits nothing if player_pos is given
	var skill_cmd: Commands.CastSkill = PlayerInput.command_for_skill(_player.id, "Q", pos, pos)
	assert_null(skill_cmd, "Skill cast with mouse directly on player returns null")


func test_hold_repeat_throttling_honours_data_value() -> void:
	var zv: ZoneView = autofree(ZoneView.new())
	zv.setup(_registry)
	zv.build(_zone)

	var p_input: PlayerInput = autofree(PlayerInput.new())
	p_input.setup(_player.id, _sim, zv, _registry)

	# Data balance configured in balance.json
	var expected_repeat: float = float(_registry.get_balance("input.move_repeat_s", 0.15))
	assert_eq(p_input.move_repeat_s, expected_repeat)
	assert_gt(p_input.move_repeat_s, 0.0)

	# 1. Mouse down: emits initial command immediately
	var click_pos := Vector2(2.5, 1.5)
	var mouse_down := InputEventMouseButton.new()
	mouse_down.button_index = MOUSE_BUTTON_RIGHT
	mouse_down.pressed = true

	var cmd0 := p_input.handle_input(mouse_down, click_pos)
	assert_not_null(cmd0, "Initial right-click press must emit a command immediately")
	assert_true(p_input.is_holding_right)

	# 2. Frame tick with delta < move_repeat_s: throttled, returns null
	var small_dt: float = expected_repeat * 0.4
	var cmd1 := p_input.handle_process(small_dt, click_pos)
	assert_null(cmd1, "Hold-repeat before interval expires must be throttled (no spam)")

	var cmd2 := p_input.handle_process(small_dt, click_pos)
	assert_null(cmd2, "Still within interval, must be throttled")

	# 3. Accumulated delta exceeds move_repeat_s: emits repeated command
	var remaining_dt: float = expected_repeat * 0.3 # 0.4 + 0.4 + 0.3 = 1.1 * interval
	var cmd3 := p_input.handle_process(remaining_dt, click_pos)
	assert_not_null(cmd3, "Once move_repeat_s has accumulated, repeated command must emit")
	assert_true(cmd3 is Commands.MoveTo)

	# 4. Release mouse: stops repeating
	var mouse_up := InputEventMouseButton.new()
	mouse_up.button_index = MOUSE_BUTTON_RIGHT
	mouse_up.pressed = false

	var cmd_release := p_input.handle_input(mouse_up, click_pos)
	assert_null(cmd_release)
	assert_false(p_input.is_holding_right)

	# 5. Subsequent process after release does not emit anything
	var cmd_after := p_input.handle_process(expected_repeat * 2.0, click_pos)
	assert_null(cmd_after, "No commands emitted after mouse button is released")


func test_synthetic_input_map_actions() -> void:
	var zv: ZoneView = autofree(ZoneView.new())
	zv.setup(_registry)
	zv.build(_zone)

	var p_input: PlayerInput = autofree(PlayerInput.new())
	p_input.setup(_player.id, _sim, zv, _registry)

	var target_pos := Vector2(5.5, 3.5)

	# Test skill_q action event
	var ev_q := InputEventAction.new()
	ev_q.action = "skill_q"
	ev_q.pressed = true
	var cmd_q := p_input.handle_input(ev_q, target_pos)
	assert_not_null(cmd_q)
	assert_true(cmd_q is Commands.CastSkill)
	assert_eq((cmd_q as Commands.CastSkill).slot, "Q")
	assert_eq((cmd_q as Commands.CastSkill).aim, target_pos)

	# Test dash action event
	var ev_dash := InputEventAction.new()
	ev_dash.action = "dash"
	ev_dash.pressed = true
	var cmd_dash := p_input.handle_input(ev_dash, _player.pos + Vector2(3.0, 0.0))
	assert_not_null(cmd_dash)
	assert_true(cmd_dash is Commands.Dash)
	assert_almost_eq((cmd_dash as Commands.Dash).aim.x, 1.0, 1e-6)

	# Test command_for_action helper
	var cmd_act_w := PlayerInput.command_for_action("skill_w", _player.id, _player.pos, target_pos)
	assert_not_null(cmd_act_w)
	assert_true(cmd_act_w is Commands.CastSkill)
	assert_eq((cmd_act_w as Commands.CastSkill).slot, "W")

	var cmd_act_r := PlayerInput.command_for_action("skill_r", _player.id, _player.pos, target_pos)
	assert_not_null(cmd_act_r)
	assert_true(cmd_act_r is Commands.CastSkill)
	assert_eq((cmd_act_r as Commands.CastSkill).slot, "R")


func test_hold_right_click_does_not_cancel_skill_cast_and_resumes_after() -> void:
	var zv: ZoneView = autofree(ZoneView.new())
	zv.setup(_registry)
	zv.build(_zone)

	var p_input: PlayerInput = autofree(PlayerInput.new())
	p_input.setup(_player.id, _sim, zv, _registry)

	var move_pos := Vector2(2.5, 1.5)
	var aim_pos := Vector2(4.5, 1.5)

	# 1. Hold right-click
	var mouse_down := InputEventMouseButton.new()
	mouse_down.button_index = MOUSE_BUTTON_RIGHT
	mouse_down.pressed = true
	var cmd_move := p_input.handle_input(mouse_down, move_pos)
	assert_not_null(cmd_move)
	assert_true(p_input.is_holding_right)

	# Step sim 1 tick to register MoveTo
	_sim.step(_sim.tick_length)
	_sim.drain_events()

	# 2. Press Q (cast time 0.2s > move_repeat_s 0.15s)
	var ev_q := InputEventAction.new()
	ev_q.action = "skill_q"
	ev_q.pressed = true
	var cmd_q := p_input.handle_input(ev_q, aim_pos)
	assert_not_null(cmd_q)
	assert_true(cmd_q is Commands.CastSkill)

	# Step sim 1 tick to start casting Q
	_sim.step(_sim.tick_length)
	assert_true(_player.command is Commands.CastSkill, "Player should be casting Q")

	# Keep calling handle_process and stepping WorldSim until the cast resolves
	var dt: float = _sim.tick_length
	var cast_resolved: bool = false
	var repeat_resumed_cmd: Commands.Command = null

	for i in range(20):
		var p_cmd := p_input.handle_process(dt, move_pos)
		if repeat_resumed_cmd == null and p_cmd != null:
			repeat_resumed_cmd = p_cmd
		_sim.step(dt)
		for ev in _sim.drain_events():
			if ev.get("type") == "skill_cast" and ev.get("slot") == "Q":
				cast_resolved = true

	assert_true(cast_resolved, "skill_cast event for slot Q must be emitted despite holding right-click")
	assert_not_null(repeat_resumed_cmd, "Hold-repeat must resume after cast resolves")
	assert_true(repeat_resumed_cmd is Commands.MoveTo)


func test_hold_repeat_on_enemy_that_dies_falls_back_to_move_to() -> void:
	var zv: ZoneView = autofree(ZoneView.new())
	zv.setup(_registry)
	zv.build(_zone)

	var p_input: PlayerInput = autofree(PlayerInput.new())
	p_input.setup(_player.id, _sim, zv, _registry)

	var enemy := _sim.spawn("enemy", Vector2i(3, 1), 2.0)
	var enemy_pos := enemy.pos

	# 1. Right click on enemy to begin attack
	var mouse_down := InputEventMouseButton.new()
	mouse_down.button_index = MOUSE_BUTTON_RIGHT
	mouse_down.pressed = true
	var cmd0 := p_input.handle_input(mouse_down, enemy_pos)
	assert_not_null(cmd0)
	assert_true(cmd0 is Commands.AttackTarget)

	# 2. Enemy dies while right-click is still held
	enemy.dead = true

	# 3. Repeat fires after move_repeat_s
	var cmd_repeat := p_input.handle_process(p_input.move_repeat_s, enemy_pos)
	assert_not_null(cmd_repeat, "Repeat should fire after move_repeat_s")
	assert_true(cmd_repeat is Commands.MoveTo, "After enemy dies, repeat must fall back to MoveTo ground")
	assert_eq((cmd_repeat as Commands.MoveTo).target, Vector2i(3, 1))


func test_missing_or_dead_player_early_returns() -> void:
	var zv: ZoneView = autofree(ZoneView.new())
	zv.setup(_registry)
	zv.build(_zone)

	# 1. Missing player (player id not found in sim)
	var p_input_missing: PlayerInput = autofree(PlayerInput.new())
	p_input_missing.setup(99999, _sim, zv, _registry)

	var mouse_down := InputEventMouseButton.new()
	mouse_down.button_index = MOUSE_BUTTON_RIGHT
	mouse_down.pressed = true
	assert_null(p_input_missing.handle_input(mouse_down, Vector2(2.5, 1.5)))

	p_input_missing.is_holding_right = true
	assert_null(p_input_missing.handle_process(0.5, Vector2(2.5, 1.5)))

	# 2. Dead player
	var p_input_dead: PlayerInput = autofree(PlayerInput.new())
	p_input_dead.setup(_player.id, _sim, zv, _registry)
	_player.dead = true

	assert_null(p_input_dead.handle_input(mouse_down, Vector2(2.5, 1.5)))

	var ev_q := InputEventAction.new()
	ev_q.action = "skill_q"
	ev_q.pressed = true
	assert_null(p_input_dead.handle_input(ev_q, Vector2(3.0, 1.0)))

	p_input_dead.is_holding_right = true
	assert_null(p_input_dead.handle_process(0.5, Vector2(2.5, 1.5)))


func test_reject_non_finite_positions() -> void:
	# Skill command rejects non-finite aim
	assert_null(PlayerInput.command_for_skill(_player.id, "Q", Vector2.INF))
	assert_null(PlayerInput.command_for_skill(_player.id, "Q", Vector2(NAN, 0.0)))

	# Right click command rejects non-finite position
	assert_null(PlayerInput.command_for_right_click(_sim, _player.id, Vector2.INF))
	assert_null(PlayerInput.command_for_right_click(_sim, _player.id, Vector2(NAN, 0.0)))

	# Dash command rejects non-finite aim/player pos
	assert_null(PlayerInput.command_for_dash(_player.id, Vector2.INF, Vector2(1.0, 0.0)))
	assert_null(PlayerInput.command_for_dash(_player.id, Vector2(0.0, 0.0), Vector2.INF))


func test_get_mouse_entity_position_uses_local_mouse() -> void:
	var zv: ZoneView = add_child_autofree(ZoneView.new())
	zv.setup(_registry)
	zv.build(_zone)
	zv.position = Vector2(32.0, 64.0)

	var p_input: PlayerInput = autofree(PlayerInput.new())
	p_input.setup(_player.id, _sim, zv, _registry)

	var entity_pos := p_input.get_mouse_entity_position()
	var expected_local := zv.get_local_mouse_position()
	var expected_entity := zv.world_to_entity(expected_local)
	assert_almost_eq(entity_pos.x, expected_entity.x, 1e-5)
	assert_almost_eq(entity_pos.y, expected_entity.y, 1e-5)


func test_missing_balance_keys_push_warning() -> void:
	var empty_reg: DataRegistry = autofree(DataRegistry.new())
	var p_input: PlayerInput = autofree(PlayerInput.new())
	p_input.setup(_player.id, _sim, null, empty_reg)
	assert_push_warning_count(3, "Missing input.move_repeat_s, input.enemy_pick_radius, and input.attack_pick_radius should push warnings")
	assert_eq(p_input.move_repeat_s, PlayerInput.DEFAULT_MOVE_REPEAT_S)
	assert_eq(p_input.enemy_pick_radius, PlayerInput.DEFAULT_ENEMY_PICK_RADIUS)
	assert_eq(p_input.attack_pick_radius, PlayerInput.DEFAULT_ATTACK_PICK_RADIUS)


func test_attack_move_nearest_wins() -> void:
	var enemy_close := _sim.spawn("enemy", Vector2i(3, 1), 2.0)
	var enemy_far := _sim.spawn("enemy", Vector2i(4, 1), 2.0)

	var cursor := Vector2(2.8, 1.5)
	var cmd: Commands.Command = PlayerInput.command_for_attack_click(_sim, _player.id, cursor, 2.0)
	assert_not_null(cmd)
	assert_true(cmd is Commands.AttackTarget)
	assert_eq((cmd as Commands.AttackTarget).target_id, enemy_close.id, "Nearest enemy to cursor wins")

	cursor = Vector2(4.8, 1.5)
	cmd = PlayerInput.command_for_attack_click(_sim, _player.id, cursor, 2.0)
	assert_not_null(cmd)
	assert_true(cmd is Commands.AttackTarget)
	assert_eq((cmd as Commands.AttackTarget).target_id, enemy_far.id, "Nearest enemy to cursor wins when cursor moves")


func test_attack_move_dead_enemies_ignored() -> void:
	var dead_enemy := _sim.spawn("enemy", Vector2i(3, 1), 2.0)
	dead_enemy.dead = true
	var alive_enemy := _sim.spawn("enemy", Vector2i(4, 1), 2.0)

	var cursor := Vector2(3.2, 1.5)
	var cmd: Commands.Command = PlayerInput.command_for_attack_click(_sim, _player.id, cursor, 2.0)
	assert_not_null(cmd)
	assert_true(cmd is Commands.AttackTarget)
	assert_eq((cmd as Commands.AttackTarget).target_id, alive_enemy.id, "Dead enemy must be ignored in favor of living one")

	# If only dead enemy is in radius, command should be null
	var cmd_dead_only: Commands.Command = PlayerInput.command_for_attack_click(_sim, _player.id, dead_enemy.pos, 0.5)
	assert_null(cmd_dead_only, "No living enemy in radius must return null")


func test_attack_move_radius_limit() -> void:
	var enemy := _sim.spawn("enemy", Vector2i(4, 1), 2.0)
	var cursor := Vector2(1.5, 1.5)
	# Distance from (1.5, 1.5) to (4.5, 1.5) is 3.0 tiles
	var cmd: Commands.Command = PlayerInput.command_for_attack_click(_sim, _player.id, cursor, 1.5)
	assert_null(cmd, "Enemy outside radius must return null")


func test_attack_move_none_in_radius_returns_null_and_no_movement() -> void:
	var zv: ZoneView = autofree(ZoneView.new())
	zv.setup(_registry)
	zv.build(_zone)

	var p_input: PlayerInput = autofree(PlayerInput.new())
	p_input.setup(_player.id, _sim, zv, _registry)

	var ev_a := InputEventAction.new()
	ev_a.action = "attack_mode"
	ev_a.pressed = true
	p_input.handle_input(ev_a)
	assert_true(p_input.attack_target_mode)

	# Right-click empty ground (2.5, 1.5) where no enemy exists
	var empty_pos := Vector2(2.5, 1.5)
	var mouse_down := InputEventMouseButton.new()
	mouse_down.button_index = MOUSE_BUTTON_RIGHT
	mouse_down.pressed = true

	var cmd := p_input.handle_input(mouse_down, empty_pos)
	assert_null(cmd, "Attack-click with no enemy in radius must return null (no MoveTo command)")
	assert_false(p_input.attack_target_mode, "Attack mode must end after right click")
	assert_false(p_input.is_holding_right, "Hold must not start after attack click")


func test_attack_move_esc_or_a_cancels() -> void:
	var zv: ZoneView = autofree(ZoneView.new())
	zv.setup(_registry)
	zv.build(_zone)

	var p_input: PlayerInput = autofree(PlayerInput.new())
	p_input.setup(_player.id, _sim, zv, _registry)

	var signal_log: Array[bool] = []
	p_input.attack_mode_changed.connect(func(active: bool) -> void: signal_log.append(active))

	# 1. A toggles ON, A toggles OFF
	var ev_a := InputEventAction.new()
	ev_a.action = "attack_mode"
	ev_a.pressed = true
	p_input.handle_input(ev_a)
	assert_true(p_input.attack_target_mode)
	assert_eq(signal_log, [true])

	p_input.handle_input(ev_a)
	assert_false(p_input.attack_target_mode)
	assert_eq(signal_log, [true, false])

	# 2. Key A event directly
	var ev_key_a := InputEventKey.new()
	ev_key_a.physical_keycode = KEY_A
	ev_key_a.pressed = true
	p_input.handle_input(ev_key_a)
	assert_true(p_input.attack_target_mode)
	assert_eq(signal_log, [true, false, true])

	# 3. Esc cancels via ui_cancel action
	var ev_esc_act := InputEventAction.new()
	ev_esc_act.action = "ui_cancel"
	ev_esc_act.pressed = true
	p_input.handle_input(ev_esc_act)
	assert_false(p_input.attack_target_mode)
	assert_eq(signal_log, [true, false, true, false])

	# 4. Turn on and cancel via KEY_ESCAPE
	p_input.handle_input(ev_key_a)
	assert_true(p_input.attack_target_mode)

	var ev_esc_key := InputEventKey.new()
	ev_esc_key.physical_keycode = KEY_ESCAPE
	ev_esc_key.pressed = true
	p_input.handle_input(ev_esc_key)
	assert_false(p_input.attack_target_mode)

	# 5. Esc when mode is false does nothing and emits no signal
	signal_log.clear()
	p_input.handle_input(ev_esc_key)
	assert_false(p_input.attack_target_mode)
	assert_true(signal_log.is_empty(), "Esc while not in attack mode must not emit signal")


func test_attack_move_mode_ends_after_click() -> void:
	var zv: ZoneView = autofree(ZoneView.new())
	zv.setup(_registry)
	zv.build(_zone)

	var p_input: PlayerInput = autofree(PlayerInput.new())
	p_input.setup(_player.id, _sim, zv, _registry)

	var enemy := _sim.spawn("enemy", Vector2i(3, 1), 2.0)

	var ev_a := InputEventAction.new()
	ev_a.action = "attack_mode"
	ev_a.pressed = true
	p_input.handle_input(ev_a)
	assert_true(p_input.attack_target_mode)

	# Click on enemy within radius
	var mouse_down := InputEventMouseButton.new()
	mouse_down.button_index = MOUSE_BUTTON_RIGHT
	mouse_down.pressed = true

	var cmd := p_input.handle_input(mouse_down, enemy.pos)
	assert_not_null(cmd)
	assert_true(cmd is Commands.AttackTarget)
	assert_false(p_input.attack_target_mode, "Mode must end after attack click")


func test_attack_move_plain_right_click_unchanged() -> void:
	var zv: ZoneView = autofree(ZoneView.new())
	zv.setup(_registry)
	zv.build(_zone)

	var p_input: PlayerInput = autofree(PlayerInput.new())
	p_input.setup(_player.id, _sim, zv, _registry)

	assert_false(p_input.attack_target_mode)

	# Right-click on ground -> MoveTo, is_holding_right becomes true
	var mouse_down := InputEventMouseButton.new()
	mouse_down.button_index = MOUSE_BUTTON_RIGHT
	mouse_down.pressed = true

	var cmd_move := p_input.handle_input(mouse_down, Vector2(2.5, 1.5))
	assert_not_null(cmd_move)
	assert_true(cmd_move is Commands.MoveTo)
	assert_true(p_input.is_holding_right)

	# Release
	var mouse_up := InputEventMouseButton.new()
	mouse_up.button_index = MOUSE_BUTTON_RIGHT
	mouse_up.pressed = false
	p_input.handle_input(mouse_up)
	assert_false(p_input.is_holding_right)

	# Right-click on enemy -> AttackTarget, is_holding_right becomes true
	var enemy := _sim.spawn("enemy", Vector2i(3, 1), 2.0)
	var cmd_atk := p_input.handle_input(mouse_down, enemy.pos)
	assert_not_null(cmd_atk)
	assert_true(cmd_atk is Commands.AttackTarget)
	assert_true(p_input.is_holding_right)


func test_attack_move_hold_not_started_after_attack_click() -> void:
	var zv: ZoneView = autofree(ZoneView.new())
	zv.setup(_registry)
	zv.build(_zone)

	var p_input: PlayerInput = autofree(PlayerInput.new())
	p_input.setup(_player.id, _sim, zv, _registry)

	var enemy := _sim.spawn("enemy", Vector2i(3, 1), 2.0)

	# Enter attack mode
	var ev_a := InputEventAction.new()
	ev_a.action = "attack_mode"
	ev_a.pressed = true
	p_input.handle_input(ev_a)

	var mouse_down := InputEventMouseButton.new()
	mouse_down.button_index = MOUSE_BUTTON_RIGHT
	mouse_down.pressed = true

	var cmd := p_input.handle_input(mouse_down, enemy.pos)
	assert_not_null(cmd)
	assert_false(p_input.is_holding_right, "is_holding_right must remain false after attack click")

	var repeat_cmd := p_input.handle_process(p_input.move_repeat_s * 2.0, enemy.pos)
	assert_null(repeat_cmd, "No hold-repeat commands should emit after attack-move click")


func test_attack_move_skills_and_dash_leave_mode_untouched() -> void:
	var zv: ZoneView = autofree(ZoneView.new())
	zv.setup(_registry)
	zv.build(_zone)

	var p_input: PlayerInput = autofree(PlayerInput.new())
	p_input.setup(_player.id, _sim, zv, _registry)

	# Enter attack mode
	var ev_a := InputEventAction.new()
	ev_a.action = "attack_mode"
	ev_a.pressed = true
	p_input.handle_input(ev_a)
	assert_true(p_input.attack_target_mode)

	# Cast skill Q
	var ev_q := InputEventAction.new()
	ev_q.action = "skill_q"
	ev_q.pressed = true
	var cmd_q := p_input.handle_input(ev_q, Vector2(5.0, 1.5))
	assert_not_null(cmd_q)
	assert_true(cmd_q is Commands.CastSkill)
	assert_true(p_input.attack_target_mode, "Skill cast must leave attack mode untouched")

	# Dash
	var ev_dash := InputEventAction.new()
	ev_dash.action = "dash"
	ev_dash.pressed = true
	var cmd_dash := p_input.handle_input(ev_dash, Vector2(5.0, 1.5))
	assert_not_null(cmd_dash)
	assert_true(cmd_dash is Commands.Dash)
	assert_true(p_input.attack_target_mode, "Dash must leave attack mode untouched")


func test_attack_move_dead_player_ignores_a() -> void:
	var zv: ZoneView = autofree(ZoneView.new())
	zv.setup(_registry)
	zv.build(_zone)

	var p_input: PlayerInput = autofree(PlayerInput.new())
	p_input.setup(_player.id, _sim, zv, _registry)

	_player.dead = true

	var ev_a := InputEventAction.new()
	ev_a.action = "attack_mode"
	ev_a.pressed = true
	var cmd := p_input.handle_input(ev_a)
	assert_null(cmd)
	assert_false(p_input.attack_target_mode, "Dead player must ignore A key")


func test_attack_mode_view_cursor_shape() -> void:
	var view: MainView = autofree(MainView.new())
	view._on_attack_mode_changed(true)
	view._on_attack_mode_changed(false)
	pass_test("MainView._on_attack_mode_changed sets cursor shapes cleanly")
