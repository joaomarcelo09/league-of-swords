extends GutTest

const VALID_VFX_KINDS: Array[String] = ["line", "cone", "circle", "sprite", "trail"]
const REQUIRED_SLOTS: Array[String] = ["Q", "W", "R", "E"]

var _registry: DataRegistry


func before_each() -> void:
	_registry = DataRegistry.new()
	_registry.load_dir("res://data")


func test_data_loads_cleanly() -> void:
	var errors := _registry.validate()
	assert_eq(errors.size(), 0, "res://data should validate without errors: %s" % str(errors))
	assert_gt(_registry.ids("vfx").size(), 0, "vfx.json should load as the 'vfx' table")


func test_every_skill_has_icon_description_and_known_vfx() -> void:
	var skill_ids := _registry.ids("skills")
	assert_gt(skill_ids.size(), 0)
	for s_id: String in skill_ids:
		var skill := _registry.get_entry("skills", s_id)
		var icon: Variant = skill.get("icon")
		assert_true(icon is String and not str(icon).strip_edges().is_empty(), "Skill '%s' needs a non-empty icon" % s_id)
		var desc: Variant = skill.get("description")
		assert_true(desc is String and not str(desc).strip_edges().is_empty(), "Skill '%s' needs a non-empty description" % s_id)
		var vfx: Variant = skill.get("vfx")
		assert_true(vfx is String and _registry.has_entry("vfx", str(vfx)), "Skill '%s' vfx '%s' must exist in vfx.json" % [s_id, str(vfx)])
		assert_eq(SkillSystem.validate_skill(skill).size(), 0, "Skill '%s' should pass validate_skill" % s_id)


func test_vfx_entries_are_well_formed() -> void:
	for v_id: String in _registry.ids("vfx"):
		var vfx := _registry.get_entry("vfx", v_id)
		var kind := str(vfx.get("kind", ""))
		assert_has(VALID_VFX_KINDS, kind, "vfx '%s' kind '%s' must be one of %s" % [v_id, kind, str(VALID_VFX_KINDS)])

		var color: Variant = vfx.get("color")
		assert_true(color is Array and (color as Array).size() == 4, "vfx '%s' color must be 4 numbers" % v_id)
		if color is Array:
			for c: Variant in color:
				assert_true(c is float or c is int, "vfx '%s' color components must be numbers" % v_id)

		var dur: Variant = vfx.get("duration_s")
		assert_true((dur is float or dur is int) and float(dur) > 0.0, "vfx '%s' duration_s must be > 0" % v_id)

		if kind == "sprite":
			assert_true(vfx.get("sheet") is String and not str(vfx.get("sheet")).is_empty(), "sprite vfx '%s' needs 'sheet'" % v_id)
			var frames: Variant = vfx.get("frames")
			assert_true((frames is float or frames is int) and float(frames) >= 1.0, "sprite vfx '%s' needs 'frames' >= 1" % v_id)


func test_slots_q_w_r_e_each_covered_exactly_once() -> void:
	var counts: Dictionary = {}
	for s_id: String in _registry.ids("skills"):
		var slot := str(_registry.get_entry("skills", s_id).get("slot", ""))
		counts[slot] = int(counts.get(slot, 0)) + 1
	for slot: String in REQUIRED_SLOTS:
		assert_eq(int(counts.get(slot, 0)), 1, "Slot '%s' must be covered exactly once" % slot)
	assert_eq(counts.size(), REQUIRED_SLOTS.size(), "No slots beyond Q/W/R/E: %s" % str(counts))


func test_e_entry_references_dash_balance_without_copying_numbers() -> void:
	var e_skill: Dictionary = {}
	for s_id: String in _registry.ids("skills"):
		var skill := _registry.get_entry("skills", s_id)
		if str(skill.get("slot", "")) == "E":
			e_skill = skill
	assert_false(e_skill.is_empty(), "An E slot entry must exist")
	assert_eq(e_skill.get("data_ref"), "balance.dash")
	var key := str(e_skill.get("data_ref", "")).trim_prefix("balance.")
	var dash: Variant = _registry.get_balance(key)
	assert_true(dash is Dictionary, "data_ref must resolve to a balance table")
	assert_true((dash as Dictionary).has("cooldown_s"), "dash balance keeps its cooldown")
	assert_false(e_skill.has("cooldown_s"), "E entry must not duplicate dash numbers")
	assert_false(e_skill.has("shape"), "E entry has no shape")


func test_validate_skill_e_entry_rules() -> void:
	var ok: Dictionary = {"name": "Step", "slot": "E", "data_ref": "balance.dash"}
	assert_eq(SkillSystem.validate_skill(ok).size(), 0)

	var bad_ref := ok.duplicate()
	bad_ref["data_ref"] = "dash"
	assert_gt(SkillSystem.validate_skill(bad_ref).size(), 0)

	var no_name := ok.duplicate()
	no_name.erase("name")
	assert_gt(SkillSystem.validate_skill(no_name).size(), 0)

	var no_ref := ok.duplicate()
	no_ref.erase("data_ref")
	assert_gt(SkillSystem.validate_skill(no_ref).size(), 0, "E without data_ref still needs full skill shape")
