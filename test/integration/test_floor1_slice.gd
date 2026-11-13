extends GutTest

## Milestone 2 end-to-end check (logic only, headless, no scene):
## town -> boss room via Commands -> kill the warden -> save/load -> exit -> floor_cleared.
## Every gameplay number is read from res://data (zone, balance, enemies, skills).
## The scripted "pilot" below only decides which Command to submit each tick; all
## movement, combat and AI are resolved by WorldSim.

const DATA_DIR := "res://data"
const ZONE_MAP := "res://data/zones/floor1/floor1.map"
const ZONE_JSON := "res://data/zones/floor1/floor1.json"
const TEST_ROOT := "user://test_saves/floor1_slice"
const TEST_SLOT := "slot_floor1"
const ZONE_ID := "floor1"
## Generous safety cap (in sim seconds) so a broken pilot fails instead of hanging.
const MAX_LEG_S := 600.0

var _registry: DataRegistry = null
var _item_db: ItemDB = null
var _store: SaveStore = null

# Live run state (rebuilt by _boot after every load).
var _zone: Zone = null
var _world_state: WorldState = null
var _character: CharacterState = null
var _session: GameSession = null
var _sim: WorldSim = null
var _player: Entity = null
var _events: Array[Dictionary] = []


func before_each() -> void:
	_clean_dir(TEST_ROOT)
	Lifecycle.clear_cached_config()
	_registry = DataRegistry.new()
	_registry.load_dir(DATA_DIR)
	_item_db = ItemDB.new(_registry)
	_store = SaveStore.new(TEST_ROOT, _item_db)
	_events.clear()


func after_each() -> void:
	_clean_dir(TEST_ROOT)
	Lifecycle.clear_cached_config()


func after_all() -> void:
	_clean_dir(TEST_ROOT)


func _clean_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(path)
	if dir != null:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while not file_name.is_empty():
			var full_sub := path.path_join(file_name)
			if dir.current_is_dir():
				if file_name != "." and file_name != "..":
					_clean_dir(full_sub)
			else:
				DirAccess.remove_absolute(full_sub)
			file_name = dir.get_next()
		dir.list_dir_end()
	DirAccess.remove_absolute(path)


# ---------------------------------------------------------------------------
# Session plumbing (mirrors MainView's logic-side wiring, without any Node)
# ---------------------------------------------------------------------------

func _new_world() -> void:
	_world_state = WorldState.new()
	_world_state.seed = int(_registry.get_balance("sim.seed"))
	_world_state.floors_unlocked = 1
	_world_state.inventory = Inventory.new(_item_db)
	var res := Lifecycle.new_character(
		_world_state, str(_registry.get_balance("permadeath.default_player_name", "Pilot")), {},
		_load_zone().entry, _store, TEST_SLOT, null, ZONE_ID, _registry)
	assert_true(res.get("ok", false), "new_character must succeed: %s" % str(res.get("error")))
	_character = res.get("value")


func _load_zone() -> Zone:
	var z := Zone.load_files(ZONE_MAP, ZONE_JSON)
	assert_true(z.is_valid(), "floor1 zone must load: %s" % str(z.errors))
	return z


## Builds a fresh sim from _world_state/_character: player at the saved position
## (or the zone entry), saved stats, shared defeated-boss list, zone enemies.
func _boot() -> void:
	_zone = _load_zone()
	_session = GameSession.new(_zone, _registry, _world_state.inventory, _item_db, null, ZONE_ID)
	_sim = _session.world
	_sim.set_bosses_defeated(_world_state.bosses_defeated)
	var spawn_at: Variant = _zone.entry
	var saved := Vector2(float(_character.position[0]), float(_character.position[1]))
	if _zone.is_walkable(Vector2i(floori(saved.x), floori(saved.y))):
		spawn_at = saved
	_player = _session.spawn_player(spawn_at)
	assert_not_null(_player, "player must spawn")
	if spawn_at is Vector2:
		_player.pos = spawn_at
	if _character.stats != null:
		_player.stats = _character.stats.duplicate()
	_session.spawn_zone_enemies()


func _save() -> void:
	_character.position = [_player.pos.x, _player.pos.y]
	_character.stats = _player.stats.duplicate()
	_character.zone = ZONE_ID
	var rc := _store.save_character(TEST_SLOT, _character)
	assert_true(rc.get("ok", false), "save_character: %s" % str(rc.get("error")))
	var rw := _store.save_world(TEST_SLOT, _world_state)
	assert_true(rw.get("ok", false), "save_world: %s" % str(rw.get("error")))


## Full round trip: save, drop every live object, load from disk, rebuild the sim.
func _save_and_reload() -> void:
	_save()
	var char_id := _character.id
	_session = null
	_sim = null
	_player = null
	_world_state = null
	_character = null
	var w := _store.load_world(TEST_SLOT, _item_db)
	assert_true(w.get("ok", false), "load_world: %s" % str(w.get("error")))
	_world_state = w.get("value")
	var c := Lifecycle.load_playable(_store, TEST_SLOT, char_id, _item_db)
	assert_true(c.get("ok", false), "load_playable: %s" % str(c.get("error")))
	_character = c.get("value")
	if _world_state.inventory == null:
		_world_state.inventory = Inventory.new(_item_db)
	_boot()


func _tick() -> void:
	_sim.step(_sim.tick_length)
	_events.append_array(_sim.drain_events())


func _events_of(type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for ev: Dictionary in _events:
		if ev.get("type") == type:
			out.append(ev)
	return out


func _max_ticks() -> int:
	return int(ceil(MAX_LEG_S / _sim.tick_length))


func _boss_spawn() -> Dictionary:
	var bosses := _zone.boss_spawns()
	assert_eq(bosses.size(), 1, "floor1 must have exactly one boss spawn")
	return bosses[0]


func _boss_exit(boss_id: String) -> Dictionary:
	for e: Dictionary in _zone.exits:
		if str(e.get("requires_boss", "")) == boss_id:
			return e
	return {}


func _boss_entity(boss_id: String) -> Entity:
	for e: Entity in _sim.entities.values():
		if e.is_boss and e.spawn_id == boss_id:
			return e
	return null


# ---------------------------------------------------------------------------
# Pilot: picks Commands like a player would (right-click move/attack, Q/W/R, E)
# ---------------------------------------------------------------------------

func _skill(slot: String) -> Dictionary:
	return _registry.get_entry("skills", str(_player.skills.get(slot, "")))


func _skill_reach(skill: Dictionary) -> float:
	var r := float(skill.get("range", 0.0))
	if r <= 0.0:
		r = float(skill.get("radius", 0.0))
	return r


func _skill_ready(slot: String) -> bool:
	return float(_sim.tick_count) >= float(_player.skill_ready_ticks.get(slot, 0.0)) - 1e-9


func _heal_amount(skill: Dictionary) -> float:
	var total := 0.0
	for eff: Dictionary in skill.get("effects", []):
		if str(eff.get("type", "")) == "heal":
			total += float(eff.get("amount", 0.0))
	return total


func _enemy_attack_range(enemy: Entity) -> float:
	var cfg := _registry.get_entry("enemies", enemy.enemy_type_id)
	return float((cfg.get("attack", {}) as Dictionary).get("range", 0.0))


## Walkable tile roughly `dist` tiles from `from` pointing away from `threat`.
func _retreat_tile(threat: Vector2, dist: float) -> Variant:
	var away := _player.pos - threat
	if away.is_zero_approx():
		away = Vector2.RIGHT
	away = away.normalized()
	for step_deg: int in [0, 30, -30, 60, -60, 90, -90, 120, -120, 150, -150, 180]:
		var dir := away.rotated(deg_to_rad(float(step_deg)))
		var t := Vector2i((threat + dir * dist).floor())
		if _zone.is_walkable(t) and not _zone.find_path(_player.tile(), t).is_empty():
			return t
	return null


## Nearest living enemy currently hunting the player (chase/windup/active/recovery).
func _nearest_threat() -> Entity:
	var best: Entity = null
	var best_d := INF
	for e: Entity in _sim.entities.values():
		if e.kind != "enemy" or e.dead or e.target_id != _player.id:
			continue
		if e.state == "idle" or e.state == "reset":
			continue
		var d := _player.pos.distance_to(e.pos)
		if d < best_d:
			best_d = d
			best = e
	return best


## One pilot decision: dodge telegraphs, else fight `foe`, else walk to `goal`.
func _pilot(goal: Vector2i, foe: Entity) -> void:
	if _player.command is Commands.Dash or _player.command is Commands.CastSkill:
		return
	var tick_len := _sim.tick_length
	var my_range := float(_player.stats.attack_range)

	# Heal with R when the heal would not be wasted.
	var r_skill := _skill("R")
	if not r_skill.is_empty() and _skill_ready("R"):
		var heal := _heal_amount(r_skill)
		if heal > 0.0 and _player.hp <= _player.stats.max_hp - heal:
			_sim.submit(Commands.cast_skill(_player.id, "R", _player.pos + Vector2.RIGHT))
			return

	# Dodge: leave a telegraphed attack before it lands.
	var threat := foe if foe != null and not foe.dead else _nearest_threat()
	if threat != null and threat.state == "windup":
		var danger := _enemy_attack_range(threat) + my_range
		var d := _player.pos.distance_to(threat.pos)
		var ticks_left := threat.state_end_tick - _sim.tick_count
		var ticks_to_escape := int(ceil((danger - d) / (_player.speed * tick_len))) + 2
		if d < danger and ticks_left <= ticks_to_escape:
			var safe_t: Variant = _retreat_tile(threat.pos, danger)
			if safe_t != null:
				var away := (_player.pos - threat.pos).normalized()
				if float(_sim.tick_count) >= _player.dash_ready_tick - 1e-9 and not away.is_zero_approx():
					_sim.submit(Commands.dash(_player.id, away))
				elif not (_player.command is Commands.MoveTo and (_player.command as Commands.MoveTo).target == safe_t):
					_sim.submit(Commands.move_to(_player.id, safe_t))
				return
	if threat != null and threat.state == "active":
		return  # keep running

	if foe != null and not foe.dead:
		var d := _player.pos.distance_to(foe.pos)
		for slot: String in ["Q", "W"]:
			var sk := _skill(slot)
			if not sk.is_empty() and _skill_ready(slot) and d <= _skill_reach(sk) and foe.state != "windup":
				_sim.submit(Commands.cast_skill(_player.id, slot, foe.pos))
				return
		var atk := _player.command as Commands.AttackTarget
		if atk == null or atk.target_id != foe.id:
			_sim.submit(Commands.attack_target(_player.id, foe.id))
		return

	var mv := _player.command as Commands.MoveTo
	if mv == null or mv.target != goal:
		_sim.submit(Commands.move_to(_player.id, goal))


## Walks to `goal` (fighting back only by dodging) until `done` returns true.
func _walk_until(goal: Vector2i, done: Callable, label: String) -> void:
	for _i in range(_max_ticks()):
		if done.call() or _player.dead:
			break
		_pilot(goal, null)
		_tick()
	assert_false(_player.dead, "%s: player must survive (hp=%.1f)" % [label, _player.hp])
	assert_true(done.call(), "%s: goal not reached within the tick cap (at %s)" % [label, str(_player.tile())])


# ---------------------------------------------------------------------------
# The slice
# ---------------------------------------------------------------------------

func test_floor1_slice_town_to_floor_cleared_with_save_load() -> void:
	_new_world()
	_boot()
	var boss_spawn := _boss_spawn()
	var boss_id := str(boss_spawn.get("id", ""))
	var boss_tile: Vector2i = WorldSim.parse_tile_coord(boss_spawn.get("tile"))
	var exit := _boss_exit(boss_id)
	assert_false(exit.is_empty(), "an exit must require the floor boss")
	var exit_tile: Vector2i = WorldSim.parse_tile_coord(exit.get("tile"))
	var aggro := float(_registry.get_entry("enemies", str(boss_spawn.get("enemy"))).get("aggro_radius", 0.0))

	# 1. Start in town: entry tile is a safe tile, the merchant stands in town.
	assert_eq(_player.tile(), _zone.entry, "player starts on the zone entry")
	assert_true(_zone.is_safe(_zone.entry), "zone entry must be inside the safe town")
	assert_false(_zone.npcs.is_empty(), "town must have an NPC")
	var npc_tile: Variant = WorldSim.parse_tile_coord(_zone.npcs[0].get("tile"))
	assert_true(_zone.is_safe(npc_tile), "merchant must stand in town")
	assert_not_null(_boss_entity(boss_id), "warden spawned with the zone")
	assert_false(_sim.is_exit_unlocked(exit), "boss exit starts locked")

	# 2. Walk out of town towards the boss room; save/load the moment we leave town.
	var path := _zone.find_path(_player.tile(), boss_tile)
	assert_false(path.is_empty(), "boss room must be reachable from town")
	_walk_until(boss_tile, func() -> bool: return not _zone.is_safe(_player.tile()), "leave town")
	var left_town_at := _player.pos
	_save_and_reload()
	assert_almost_eq(_player.pos.x, left_town_at.x, 0.001, "reload restores position x")
	assert_almost_eq(_player.pos.y, left_town_at.y, 0.001, "reload restores position y")
	assert_not_null(_boss_entity(boss_id), "warden still alive after reload")

	# 3. Continue from the loaded state into the boss room (warden aggro range).
	var warden := _boss_entity(boss_id)
	_walk_until(boss_tile,
		func() -> bool: return _player.pos.distance_to(warden.pos) <= aggro,
		"reach boss room")
	gut.p("Reached boss room at tick %d, hp %.1f" % [_sim.tick_count, _player.hp])

	# 4. Kill the warden with attacks and skills.
	for _i in range(_max_ticks()):
		if warden.dead or _player.dead:
			break
		_pilot(boss_tile, warden)
		_tick()
	gut.p("Warden fight ended at tick %d, player hp %.1f, warden hp %.1f" % [_sim.tick_count, _player.hp, warden.hp])
	assert_false(_player.dead, "player must survive the warden")
	assert_true(warden.dead, "warden must die")
	var defeated := _events_of("boss_defeated")
	assert_eq(defeated.size(), 1, "exactly one boss_defeated event")
	if defeated.size() == 1:
		assert_eq(defeated[0].get("boss"), boss_id)
	assert_true(_world_state.bosses_defeated.has(boss_id), "kill recorded in WorldState")
	var cast_slots := {}
	for ev: Dictionary in _events_of("skill_cast"):
		if int(ev.get("source", 0)) == _player.id:
			cast_slots[ev.get("slot")] = true
	assert_true(cast_slots.has("Q") or cast_slots.has("W"), "skills were used in the fight")

	# 5. Save/load again: the warden stays dead and the exit stays unlocked.
	_save_and_reload()
	assert_null(_boss_entity(boss_id), "defeated warden must not respawn after reload")
	assert_true(_sim.is_exit_unlocked(exit), "exit unlocked after reload")

	# 6. Take the exit -> floor_cleared.
	_events.clear()
	_walk_until(exit_tile, func() -> bool: return not _events_of("floor_cleared").is_empty(), "take exit")
	var cleared := _events_of("floor_cleared")
	assert_eq(cleared.size(), 1, "exactly one floor_cleared event")
	if cleared.size() == 1:
		assert_eq(cleared[0].get("to_zone"), str(exit.get("to_zone")))
		assert_eq(cleared[0].get("tile"), exit_tile)
	assert_true(_events_of("exit_locked").is_empty(), "exit must not report locked")
