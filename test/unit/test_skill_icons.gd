extends GutTest

const SLOTS: Array[String] = ["Q", "W", "R", "E"]
const EXPECTED_FILES: Dictionary = {
	"Q": "fire-dash.svg",
	"W": "quick-slash.svg",
	"R": "healing-shield.svg",
	"E": "run.svg",
}

var _registry: DataRegistry


func before_each() -> void:
	_registry = DataRegistry.new()
	_registry.load_dir("res://data")


func _registry_with_icon(icon_entry: Dictionary) -> DataRegistry:
	var reg := DataRegistry.new()
	reg._tables["skills"] = {"test_skill": {"name": "Test Strike", "slot": "Q", "icon": "icon_test"}}
	reg._tables["icons"] = {"icon_test": icon_entry}
	return reg


func test_icons_table_loads_and_validates() -> void:
	assert_eq(_registry.validate().size(), 0, "res://data should validate: %s" % str(_registry.validate()))
	assert_gt(_registry.ids("icons").size(), 0, "icons.json should load as the 'icons' table")


func test_every_skill_icon_has_an_icons_entry() -> void:
	for s_id: String in _registry.ids("skills"):
		var icon_id := SkillIcons.icon_id_for_skill(_registry, s_id)
		assert_false(icon_id.is_empty(), "skill '%s' needs an icon id" % s_id)
		assert_true(_registry.has_entry("icons", icon_id), "icon '%s' (skill '%s') needs an icons.json entry" % [icon_id, s_id])
		var path := SkillIcons.icon_path(_registry, icon_id)
		assert_true(path.begins_with("res://"), "icon '%s' path must be a res:// path, got '%s'" % [icon_id, path])


func test_icon_entries_are_well_formed() -> void:
	for icon_id: String in _registry.ids("icons"):
		var entry := _registry.get_entry("icons", icon_id)
		assert_true(entry.get("path") is String, "icon '%s' needs a string path" % icon_id)
		if entry.has("color"):
			var color: Variant = entry["color"]
			assert_true(color is Array and (color as Array).size() == 4, "icon '%s' color must be [r,g,b,a]" % icon_id)


func test_each_slot_maps_to_the_chosen_icon_file() -> void:
	for slot_key: String in SLOTS:
		var skill_id := SkillIcons.skill_id_for_slot(_registry, slot_key)
		assert_false(skill_id.is_empty(), "slot %s should resolve to a skill" % slot_key)
		var path := SkillIcons.icon_path(_registry, SkillIcons.icon_id_for_skill(_registry, skill_id))
		assert_eq(path.get_file(), EXPECTED_FILES[slot_key], "slot %s icon file" % slot_key)


func test_skill_id_for_slot_prefers_equipped_skill() -> void:
	assert_eq(SkillIcons.skill_id_for_slot(_registry, "Q", {"Q": "crescent_sweep"}), "crescent_sweep")
	assert_eq(SkillIcons.skill_id_for_slot(_registry, "E", {"Q": "ember_lance"}), "shadow_step")
	assert_eq(SkillIcons.skill_id_for_slot(null, "Q"), "")


func test_icon_color_from_data_or_fallback() -> void:
	var reg := _registry_with_icon({"path": "res://nowhere.svg", "color": [0.1, 0.2, 0.3, 1.0]})
	assert_eq(SkillIcons.icon_color(reg, "icon_test", Color.WHITE), Color(0.1, 0.2, 0.3, 1.0))
	var reg_no_color := _registry_with_icon({"path": "res://nowhere.svg"})
	assert_eq(SkillIcons.icon_color(reg_no_color, "icon_test", Color.WHITE), Color.WHITE)
	assert_eq(SkillIcons.icon_color(reg, "icon_unknown", Color.RED), Color.RED)


func test_missing_icon_file_falls_back_to_letter() -> void:
	var reg := _registry_with_icon({"path": "res://assets/ui/skills/does_not_exist.svg", "color": [1.0, 0.0, 0.0, 1.0]})
	var info := SkillIcons.resolve_slot(reg, "Q", {}, Color.WHITE)
	assert_eq(info["skill_id"], "test_skill")
	assert_eq(info["icon_id"], "icon_test")
	assert_null(info["texture"], "missing art must give no texture")
	assert_eq(info["letter"], "T", "fallback letter is the skill name initial")
	assert_eq(info["color"], Color(1.0, 0.0, 0.0, 1.0))


func test_unknown_icon_id_and_empty_path_are_tolerated() -> void:
	assert_eq(SkillIcons.icon_path(_registry, "icon_unknown"), "")
	assert_null(SkillIcons.load_texture(""))
	var info := SkillIcons.resolve_slot(null, "W", {}, Color.WHITE)
	assert_null(info["texture"])
	assert_eq(info["letter"], "W", "no registry: fall back to the slot key")


func test_hud_slots_get_icon_or_fallback() -> void:
	var hud := HUD.new()
	add_child_autofree(hud)
	hud.registry = _registry
	hud.refresh_skill_icons()
	for slot_key: String in SLOTS:
		var comp: HUD.SkillSlotComponent = hud.get_skill_slot(slot_key)
		assert_not_null(comp)
		var path := SkillIcons.icon_path(_registry, SkillIcons.icon_id_for_skill(_registry, SkillIcons.skill_id_for_slot(_registry, slot_key)))
		if ResourceLoader.exists(path):
			assert_true(comp.has_icon_texture(), "slot %s should show its fetched icon" % slot_key)
		else:
			assert_false(comp.has_icon_texture(), "slot %s without art uses the letter fallback" % slot_key)
		assert_false(comp.fallback_letter.is_empty(), "slot %s always has a fallback letter" % slot_key)
		assert_eq(comp.key_label.text, slot_key, "slot %s keeps its key letter" % slot_key)
