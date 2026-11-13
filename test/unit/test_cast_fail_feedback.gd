extends GutTest
## Cast/dash failed HUD feedback (red slot flash + reason label), view.hud_cast_fail.

const MAP_PATH := "res://data/zones/floor1/test_arena.map"
const JSON_PATH := "res://data/zones/floor1/test_arena.json"
const DATA_DIR := "res://data"

var _registry: DataRegistry = null
var _session: GameSession = null
var _player: Entity = null
var _hud: HUD = null
var _config: Dictionary = {}


func before_each() -> void:
	_registry = DataRegistry.new()
	_registry.load_dir(DATA_DIR)
	var zone := Zone.load_files(MAP_PATH, JSON_PATH)
	var item_db := ItemDB.new(_registry)
	var inventory := Inventory.new(item_db)
	_session = GameSession.new(zone, _registry, inventory, item_db)
	_player = _session.spawn_player()
	_hud = HUD.new()
	autofree(_hud)
	_hud.setup(_session, _session.world, _player, inventory, item_db, _registry)
	_config = HUD.cast_fail_config(_registry.get_balance("view.hud_cast_fail"))


func _cast_failed(slot: String, reason: String, source: int = -2) -> Dictionary:
	return {
		"type": "cast_failed", "tick": 0, "slot": slot, "reason": reason,
		"source": _player.id if source == -2 else source,
	}


func _dash_failed(reason: String) -> Dictionary:
	return {"type": "dash_failed", "tick": 0, "source": _player.id, "reason": reason}


func _slot(key: String) -> HUD.SkillSlotComponent:
	return _hud.get_skill_slot(key) as HUD.SkillSlotComponent


func _label_duration() -> float:
	return float(_config["label_duration_s"])


func _flash_duration() -> float:
	return float(_config["flash_duration_s"])


# --- Pure helpers ---

func test_flash_strength_curve() -> void:
	assert_eq(HUD.fail_flash_strength(0.0, 0.4), 1.0, "full at start")
	assert_almost_eq(HUD.fail_flash_strength(0.2, 0.4), 0.5, 0.001, "half way")
	assert_eq(HUD.fail_flash_strength(0.4, 0.4), 0.0, "zero at end")
	assert_eq(HUD.fail_flash_strength(1.0, 0.4), 0.0, "zero after end")
	assert_eq(HUD.fail_flash_strength(0.0, 0.0), 0.0, "zero duration = off")


func test_label_mapping_known_and_unknown() -> void:
	var labels: Dictionary = _config["labels"]
	assert_eq(HUD.fail_label("cooldown", labels), "cooldown")
	assert_eq(HUD.fail_label("zero_direction", labels), "no target")
	assert_eq(HUD.fail_label("invalid_aim", labels), "no target")
	assert_eq(HUD.fail_label("made_up_reason", labels), "")
	assert_eq(HUD.fail_label("cooldown", {}), "")


func test_config_present_in_balance() -> void:
	assert_gt(_flash_duration(), 0.0)
	assert_gt(_label_duration(), 0.0)
	assert_eq(HUD.cast_fail_config(null), {}, "missing config = off")
	assert_eq(HUD.cast_fail_config("bad"), {}, "non-dictionary config = off")


# --- Event handling ---

func test_cast_failed_on_q_shows_label_and_flash() -> void:
	_hud.handle_event(_cast_failed("Q", "cooldown"))
	var q := _slot("Q")
	assert_true(q.fail_active)
	assert_gt(q.fail_flash, 0.0, "Q flashes")
	assert_true(q.is_fail_label_visible(), "Q shows its reason")
	assert_eq(q.fail_label.text, "cooldown")
	assert_false(_slot("W").fail_active, "other slots untouched")
	assert_false(_slot("E").fail_active, "other slots untouched")


func test_dash_failed_targets_e() -> void:
	_hud.handle_event(_dash_failed("invalid_aim"))
	var e := _slot("E")
	assert_gt(e.fail_flash, 0.0)
	assert_eq(e.fail_label.text, "no target")
	assert_false(_slot("Q").fail_active)


func test_other_source_is_ignored() -> void:
	_hud.handle_event(_cast_failed("Q", "cooldown", _player.id + 999))
	assert_false(_slot("Q").fail_active, "enemy fails do not light player slots")


func test_unknown_slot_and_reason_no_error() -> void:
	_hud.handle_event(_cast_failed("Z", "cooldown"))
	_hud.handle_event({"type": "cast_failed", "source": _player.id})
	for key: String in ["Q", "W", "R", "E"]:
		assert_false(_slot(key).fail_active, "unknown slot does nothing (%s)" % key)
	_hud.handle_event(_cast_failed("W", "made_up_reason"))
	var w := _slot("W")
	assert_gt(w.fail_flash, 0.0, "unknown reason still flashes")
	assert_false(w.is_fail_label_visible(), "unknown reason has no label")


func test_fade_ends_at_zero_and_label_clears() -> void:
	_hud.handle_event(_cast_failed("Q", "cooldown"))
	var q := _slot("Q")
	q.advance_fail(_flash_duration() * 0.5)
	assert_almost_eq(q.fail_flash, 0.5, 0.01, "mid flash")
	q.advance_fail(_flash_duration())
	assert_eq(q.fail_flash, 0.0, "flash over")
	q.advance_fail(_label_duration())
	assert_false(q.fail_active)
	assert_eq(q.fail_flash, 0.0)
	assert_false(q.is_fail_label_visible(), "label cleared")
	assert_eq(q.fail_label.text, "")
	q._process(1.0)
	assert_false(q.is_processing(), "stops processing once done")


func test_repeat_restarts_without_stacking() -> void:
	_hud.handle_event(_cast_failed("Q", "cooldown"))
	var q := _slot("Q")
	q.advance_fail(_flash_duration() * 0.8)
	_hud.handle_event(_cast_failed("Q", "zero_direction"))
	assert_eq(q.fail_flash, 1.0, "restart from full, never above")
	assert_eq(q.fail_elapsed, 0.0)
	assert_eq(q.fail_label.text, "no target", "latest reason wins")
	q.advance_fail(maxf(_flash_duration(), _label_duration()))
	assert_eq(q.fail_flash, 0.0, "no stuck red")
	assert_false(q.is_fail_label_visible())


func test_missing_config_switches_effect_off() -> void:
	var q := _slot("Q")
	q.configure_fail(HUD.cast_fail_config(null))
	q.show_fail("cooldown")
	assert_false(q.fail_active)
	assert_eq(q.fail_flash, 0.0)
	assert_false(q.is_fail_label_visible())
