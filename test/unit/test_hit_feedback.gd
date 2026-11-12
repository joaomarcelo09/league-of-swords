extends GutTest
## JGT-87: hit feedback (white flash, camera shake, hit spark).

var _registry: DataRegistry = null


func before_each() -> void:
	_registry = DataRegistry.new()
	_registry.load_dir("res://data")


func _hit(key: String) -> Variant:
	return _registry.get_balance("view.hit." + key)


func _world() -> WorldSim:
	var zone := Zone.load_files("res://data/zones/floor1/test_small.map", "res://data/zones/floor1/test_small.json")
	return WorldSim.new(zone, _registry)


func _layer(world: WorldSim = null) -> VfxLayer:
	var layer := VfxLayer.new()
	add_child_autofree(layer)
	layer.setup(world, null, _registry)
	return layer


# --- flash -----------------------------------------------------------------------------

func test_flash_strength_curve() -> void:
	assert_almost_eq(HitFlash.flash_strength(0.0, 0.2), 1.0, 0.0001, "full at the hit")
	assert_almost_eq(HitFlash.flash_strength(0.1, 0.2), 0.5, 0.0001, "half way")
	assert_eq(HitFlash.flash_strength(0.2, 0.2), 0.0, "zero at the end")
	assert_eq(HitFlash.flash_strength(1.0, 0.2), 0.0, "zero after the end")
	assert_eq(HitFlash.flash_strength(0.0, 0.0), 0.0, "no duration, no flash")
	assert_true(HitFlash.flash_strength(0.05, 0.2) > HitFlash.flash_strength(0.15, 0.2), "fades out")


func test_flash_modulate_brightens_and_keeps_alpha() -> void:
	var base := Color(1.0, 1.0, 1.0, 0.8)
	var tint := Color(3.0, 3.0, 3.0, 1.0)
	assert_eq(HitFlash.flash_modulate(base, tint, 0.0), base, "strength 0 = base")
	var full := HitFlash.flash_modulate(base, tint, 1.0)
	assert_almost_eq(full.r, 3.0, 0.0001)
	assert_almost_eq(full.a, 0.8, 0.0001, "alpha untouched")


func test_flash_config_from_balance() -> void:
	var target := Node2D.new()
	add_child_autofree(target)
	var flash := HitFlash.attach(target, target, _registry)
	assert_almost_eq(flash.duration_s, float(_hit("flash_duration_s")), 0.0001)
	var tint: Array = _hit("flash_tint")
	assert_almost_eq(flash.tint.r, float(tint[0]), 0.0001)


func test_flash_triggers_fades_and_restores_modulate() -> void:
	var target := Node2D.new()
	add_child_autofree(target)
	target.modulate = Color(0.9, 0.8, 0.7, 1.0)
	var flash := HitFlash.attach(target, target, _registry)
	flash.trigger()
	assert_true(flash.active)
	assert_true(target.modulate.r > 0.9, "brighter while flashing")
	flash.advance(flash.duration_s * 0.5)
	assert_almost_eq(flash.strength(), 0.5, 0.0001)
	flash.advance(flash.duration_s)
	assert_false(flash.active)
	assert_eq(target.modulate, Color(0.9, 0.8, 0.7, 1.0), "modulate restored exactly")


func test_flash_disabled_without_balance() -> void:
	var target := Node2D.new()
	add_child_autofree(target)
	var flash := HitFlash.attach(target, target, DataRegistry.new())
	flash.trigger()
	assert_false(flash.active)
	assert_eq(target.modulate, Color.WHITE)


func test_enemy_view_flashes_on_hurt() -> void:
	var world := _world()
	var enemy := world.spawn("enemy", Vector2i(3, 3), 1.0, 10.0)
	var view := EntityView.new()
	add_child_autofree(view)
	view.setup(enemy, null, _registry)
	assert_not_null(view.flash)
	view.notify_hurt(1, world.tick_length)
	assert_true(view.flash.active, "hurt starts the flash")
	view.flash.advance(view.flash.duration_s + 0.01)
	assert_false(view.flash.active)


# --- shake -----------------------------------------------------------------------------

func test_shake_offset_bounded_and_zero_at_end() -> void:
	var dur := 0.2
	var amp := 5.0
	var moved := false
	for i in range(41):
		var t := dur * float(i) / 40.0
		var off := GameCamera.shake_offset(t, dur, amp, 24.0, 3)
		assert_true(off.length() <= amp + 0.0001, "bounded at t=%f" % t)
		if off.length() > 0.01:
			moved = true
	assert_true(moved, "it actually shakes")
	assert_eq(GameCamera.shake_offset(dur, dur, amp, 24.0, 3), Vector2.ZERO, "zero at end")
	assert_eq(GameCamera.shake_offset(0.05, 0.0, amp, 24.0, 3), Vector2.ZERO, "no duration")
	assert_eq(GameCamera.shake_offset(0.05, dur, amp, 24.0, 3), GameCamera.shake_offset(0.05, dur, amp, 24.0, 3), "deterministic")


func test_camera_shake_restores_offset_exactly() -> void:
	var cam := GameCamera.new(_registry)
	add_child_autofree(cam)
	cam.follow_offset = Vector2(2.0, -3.0)
	var base := cam.offset
	assert_almost_eq(cam.shake_amplitude_px, float(_hit("shake_amplitude_px")), 0.0001)
	cam.shake()
	assert_true(cam.shaking)
	var max_dev := 0.0
	var steps := 0
	while cam.shaking and steps < 1000:
		cam.advance_shake(1.0 / 120.0)
		max_dev = maxf(max_dev, (cam.offset - base).length())
		steps += 1
	assert_false(cam.shaking, "shake ends")
	assert_true(max_dev > 0.0, "offset moved during the shake")
	assert_true(max_dev <= cam.shake_amplitude_px + 0.0001, "bounded by amplitude")
	assert_eq(cam.offset, base, "no drift: offset back to base")


func test_camera_follow_still_works_while_shaking() -> void:
	var cam := GameCamera.new(_registry)
	add_child_autofree(cam)
	cam.shake()
	cam.follow(Vector2(100.0, 50.0))
	assert_eq(cam.position, Vector2(100.0, 50.0))


func test_pinned_camera_does_not_shake() -> void:
	var cam := GameCamera.new(_registry)
	add_child_autofree(cam)
	var base := cam.offset
	cam.pin_to(Vector2(10.0, 10.0))
	cam.shake()
	assert_false(cam.shaking)
	assert_eq(cam.offset, base)
	# Pinning mid-shake stops it and restores the offset.
	cam.pinned = false
	cam.shake()
	cam.advance_shake(0.01)
	cam.pin_to(Vector2(5.0, 5.0))
	assert_false(cam.shaking)
	assert_eq(cam.offset, base)


# --- spark -----------------------------------------------------------------------------

func test_spark_params_from_balance() -> void:
	var cfg := VfxLayer.spark_params(_registry)
	assert_false(cfg.is_empty())
	assert_almost_eq(float(cfg["duration_s"]), float(_hit("spark_duration_s")), 0.0001)
	assert_eq(int(cfg["count"]), int(_hit("spark_count")))
	assert_almost_eq(float(cfg["length_px"]), float(_hit("spark_length_px")), 0.0001)
	assert_almost_eq(float(cfg["width_px"]), float(_hit("spark_width_px")), 0.0001)
	var c: Array = _hit("spark_color")
	assert_almost_eq((cfg["color"] as Color).g, float(c[1]), 0.0001)
	assert_true(VfxLayer.spark_params(DataRegistry.new()).is_empty(), "missing config = no spark")


func test_damage_spawns_spark_that_frees_itself() -> void:
	var world := _world()
	var player := world.spawn("player", Vector2i(2, 2), 4.0, 100.0)
	var enemy := world.spawn("enemy", Vector2i(3, 2), 1.0, 10.0)
	var layer := _layer(world)
	layer.handle_event({"type": "damage", "source": player.id, "target": enemy.id, "amount": 3.0, "tick": 1})
	var effects := layer.get_effects()
	assert_eq(effects.size(), 1, "basic attack hit sparks (no skill vfx needed)")
	var fx := effects[0]
	assert_eq(fx.kind, VfxLayer.KIND_SPARK)
	assert_eq(fx.position, enemy.pos, "at the target (no zone view = entity units)")
	assert_false(fx.advance(fx.duration_s * 0.5))
	assert_true(fx.advance(fx.duration_s), "expires")
	fx._process(0.0)
	assert_true(fx.is_queued_for_deletion(), "frees itself")


func test_damage_without_target_draws_nothing() -> void:
	var world := _world()
	var layer := _layer(world)
	layer.handle_event({"type": "damage", "source": 99, "target": 12345, "amount": 1.0, "tick": 1})
	layer.handle_event({"type": "damage", "tick": 1})
	assert_eq(layer.get_effects().size(), 0)
	var bare := _layer(null)
	bare.handle_event({"type": "damage", "source": 1, "target": 2, "tick": 1})
	assert_eq(bare.get_effects().size(), 0)
