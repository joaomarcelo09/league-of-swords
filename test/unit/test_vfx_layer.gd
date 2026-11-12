extends GutTest

var _registry: DataRegistry = null


func before_each() -> void:
	_registry = DataRegistry.new()
	_registry.load_dir("res://data")


func _layer(world: WorldSim = null) -> VfxLayer:
	var layer := VfxLayer.new()
	add_child_autofree(layer)
	layer.setup(world, null, _registry)
	return layer


func _world() -> WorldSim:
	var zone := Zone.load_files("res://data/zones/floor1/test_small.map", "res://data/zones/floor1/test_small.json")
	return WorldSim.new(zone, _registry)


func test_vfx_id_lookup_from_skill_id() -> void:
	for s_id: String in _registry.ids("skills"):
		var expected := str(_registry.get_entry("skills", s_id).get("vfx", ""))
		assert_eq(VfxLayer.vfx_id_for_skill(_registry, s_id), expected, "skill '%s'" % s_id)
	assert_eq(VfxLayer.vfx_id_for_skill(_registry, "no_such_skill"), "")
	assert_eq(VfxLayer.vfx_id_for_skill(null, "ember_lance"), "")


func test_vfx_def_reads_data() -> void:
	for v_id: String in _registry.ids("vfx"):
		var raw := _registry.get_entry("vfx", v_id)
		var def := VfxLayer.vfx_def(_registry, v_id)
		assert_false(def.is_empty(), "vfx '%s' should be drawable" % v_id)
		assert_eq(def["kind"], str(raw["kind"]))
		assert_almost_eq(float(def["duration_s"]), float(raw["duration_s"]), 0.0001)
		var c: Array = raw["color"]
		assert_almost_eq((def["color"] as Color).a, float(c[3]), 0.0001)


func test_unknown_or_bad_vfx_gives_nothing() -> void:
	assert_true(VfxLayer.vfx_def(_registry, "vfx_missing").is_empty())
	assert_true(VfxLayer.vfx_def(_registry, "").is_empty())
	var reg := DataRegistry.new()
	reg._tables["vfx"] = {
		"bad_kind": {"kind": "sparkles", "color": [1, 1, 1, 1], "duration_s": 0.2},
		"no_dur": {"kind": "line", "color": [1, 1, 1, 1], "duration_s": 0.0},
	}
	assert_true(VfxLayer.vfx_def(reg, "bad_kind").is_empty())
	assert_true(VfxLayer.vfx_def(reg, "no_dur").is_empty())


func test_shape_params_come_from_skill_data() -> void:
	var lance := _registry.get_entry("skills", "ember_lance")
	var line := VfxLayer.shape_params(_registry, "ember_lance", VfxLayer.KIND_LINE)
	assert_almost_eq(float(line["length"]), float(lance["range"]), 0.0001)
	assert_almost_eq(float(line["width"]), float(lance["width"]), 0.0001)

	var sweep := _registry.get_entry("skills", "crescent_sweep")
	var cone := VfxLayer.shape_params(_registry, "crescent_sweep", VfxLayer.KIND_CONE)
	assert_almost_eq(float(cone["range"]), float(sweep["range"]), 0.0001)
	assert_almost_eq(float(cone["angle_deg"]), float(sweep["angle_deg"]), 0.0001)

	var gale := _registry.get_entry("skills", "mending_gale")
	var circle := VfxLayer.shape_params(_registry, "mending_gale", VfxLayer.KIND_CIRCLE)
	assert_almost_eq(float(circle["radius"]), float(gale["radius"]), 0.0001)

	assert_true(VfxLayer.shape_params(_registry, "shadow_step", VfxLayer.KIND_LINE).is_empty())
	assert_true(VfxLayer.shape_params(_registry, "no_such_skill", VfxLayer.KIND_CONE).is_empty())


func test_fade_alpha_by_elapsed() -> void:
	assert_almost_eq(VfxLayer.fade_alpha(0.0, 0.5), 1.0, 0.0001)
	assert_almost_eq(VfxLayer.fade_alpha(0.25, 0.5), 0.5, 0.0001)
	assert_almost_eq(VfxLayer.fade_alpha(0.5, 0.5), 0.0, 0.0001)
	assert_almost_eq(VfxLayer.fade_alpha(2.0, 0.5), 0.0, 0.0001)
	assert_almost_eq(VfxLayer.fade_alpha(0.1, 0.0), 0.0, 0.0001)


func test_style_values_come_from_balance() -> void:
	assert_eq(int(VfxLayer.style_value(_registry, "trail_ghost_count")), int(_registry.get_balance("view.vfx.trail_ghost_count")))
	assert_eq(int(VfxLayer.style_value(null, "z_index")), int(VfxLayer.DEFAULTS["z_index"]))


func test_unknown_vfx_spawns_no_node() -> void:
	var layer := _layer()
	assert_null(layer.spawn_effect("vfx_missing", Vector2.ZERO, {}))
	layer.handle_event({"type": "skill_cast", "source": 1, "skill": "no_such_skill", "slot": "Q", "tick": 0})
	assert_eq(layer.get_child_count(), 0)


func test_spawned_effect_expires_and_frees() -> void:
	var layer := _layer()
	var fx := layer.spawn_effect("vfx_mending_gale", Vector2.ZERO, {"radius": 10.0})
	assert_not_null(fx)
	assert_eq(fx.duration_s, float(_registry.get_entry("vfx", "vfx_mending_gale")["duration_s"]))
	assert_false(fx.advance(fx.duration_s * 0.5))
	fx._process(fx.duration_s)
	assert_true(fx.is_queued_for_deletion(), "expired effect should free itself")
	await get_tree().process_frame
	assert_false(is_instance_valid(fx))
	assert_eq(layer.get_child_count(), 0)


func test_skill_cast_events_spawn_matching_effects() -> void:
	var world := _world()
	var player := world.spawn("player", Vector2i(2, 2), 4.0, 100.0)
	var enemy := world.spawn("enemy", Vector2i(4, 2), 1.0, 10.0)
	assert_not_null(player)
	assert_not_null(enemy)
	var layer := _layer(world)
	layer.handle_event({"type": "skill_cast", "source": player.id, "skill": "ember_lance", "slot": "Q", "tick": 1})
	layer.handle_event({"type": "skill_cast", "source": player.id, "skill": "crescent_sweep", "slot": "W", "tick": 2})
	layer.handle_event({"type": "skill_cast", "source": player.id, "skill": "mending_gale", "slot": "R", "tick": 3})
	var kinds: Array[String] = []
	for fx: VfxLayer.VfxEffect in layer.get_effects():
		kinds.append(fx.kind)
	assert_eq(kinds, [VfxLayer.KIND_LINE, VfxLayer.KIND_CONE, VfxLayer.KIND_CIRCLE] as Array[String])
	var lance: VfxLayer.VfxEffect = layer.get_effects()[0]
	assert_almost_eq((lance.params["dir"] as Vector2).x, 1.0, 0.001, "lance aims at the nearest foe")


func test_damage_in_cast_tick_aims_the_effect() -> void:
	var world := _world()
	var player := world.spawn("player", Vector2i(2, 2), 4.0, 100.0)
	world.spawn("enemy", Vector2i(4, 2), 1.0, 10.0)
	var hit := world.spawn("enemy", Vector2i(2, 4), 1.0, 10.0)
	var layer := _layer(world)
	layer.handle_event({"type": "skill_cast", "source": player.id, "skill": "ember_lance", "slot": "Q", "tick": 5})
	layer.handle_event({"type": "damage", "source": player.id, "target": hit.id, "amount": 3.0, "tick": 5})
	var fx: VfxLayer.VfxEffect = layer.get_effects()[0]
	assert_almost_eq((fx.params["dir"] as Vector2).y, 1.0, 0.001)


func test_dash_event_spawns_trail() -> void:
	var world := _world()
	var player := world.spawn("player", Vector2i(2, 2), 4.0, 100.0)
	var layer := _layer(world)
	layer.handle_event({"type": "dash", "entity": player.id, "from": Vector2(2, 2), "to": Vector2(5, 2), "duration_ticks": 5, "tick": 0})
	var effects := layer.get_effects()
	assert_eq(effects.size(), 1)
	assert_eq(effects[0].kind, VfxLayer.KIND_TRAIL)
	assert_eq(effects[0].params["to"], Vector2(3, 0))
	layer.handle_event({"type": "dash", "entity": player.id, "from": "bad", "to": null})
	assert_eq(layer.get_effects().size(), 1, "malformed dash draws nothing")
