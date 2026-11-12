class_name SkillIcons
extends RefCounted

## View-side lookup of HUD skill icons. A skill's `icon` id (data/skills.json) maps to an
## entry in data/icons.json: {"path": "res://...", "color": [r, g, b, a] (optional)}.
## The art is fetched by tools/fetch_art.sh and may be missing; callers then draw a
## coloured letter fallback, so the game runs with no fetched art.

const ICONS_TABLE: String = "icons"
const SKILLS_TABLE: String = "skills"


## Skill id in `slot_key`: the player's equipped skill when known, else the first skill
## (sorted by id) whose data `slot` matches (e.g. "E" -> shadow_step).
static func skill_id_for_slot(registry: DataRegistry, slot_key: String, player_skills: Dictionary = {}) -> String:
	var equipped := str(player_skills.get(slot_key, ""))
	if not equipped.is_empty():
		return equipped
	if registry == null:
		return ""
	for s_id: String in registry.ids(SKILLS_TABLE):
		if str(registry.get_entry(SKILLS_TABLE, s_id).get("slot", "")) == slot_key:
			return s_id
	return ""


## Icon id of a skill, or "" if the skill or its icon is unknown.
static func icon_id_for_skill(registry: DataRegistry, skill_id: String) -> String:
	if registry == null or skill_id.is_empty():
		return ""
	return str(registry.get_entry(SKILLS_TABLE, skill_id).get("icon", "")).strip_edges()


## The icons.json entry of `icon_id` ({} if unknown).
static func icon_entry(registry: DataRegistry, icon_id: String) -> Dictionary:
	if registry == null or icon_id.is_empty():
		return {}
	return registry.get_entry(ICONS_TABLE, icon_id)


## Resource path of `icon_id` ("" if unknown).
static func icon_path(registry: DataRegistry, icon_id: String) -> String:
	return str(icon_entry(registry, icon_id).get("path", "")).strip_edges()


## Colour of `icon_id` (tints the icon and colours the letter fallback); `fallback` if unset.
static func icon_color(registry: DataRegistry, icon_id: String, fallback: Color) -> Color:
	var val: Variant = icon_entry(registry, icon_id).get("color", null)
	if val == null:
		return fallback
	return HUD.parse_color(val, fallback)


## Loads the icon texture at `path`, or null if the path is empty, the file is missing or
## it is not imported yet. Never logs an error for missing art.
static func load_texture(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path) as Texture2D


## Letter drawn when the icon art is missing: the skill name's initial, else the slot key.
static func fallback_letter(registry: DataRegistry, skill_id: String, slot_key: String) -> String:
	if registry != null and not skill_id.is_empty():
		var skill_name := str(registry.get_entry(SKILLS_TABLE, skill_id).get("name", "")).strip_edges()
		if not skill_name.is_empty():
			return skill_name.substr(0, 1).to_upper()
	return slot_key


## Everything a HUD slot needs: {skill_id, icon_id, texture (Texture2D or null), color, letter}.
static func resolve_slot(registry: DataRegistry, slot_key: String, player_skills: Dictionary, default_color: Color) -> Dictionary:
	var skill_id := skill_id_for_slot(registry, slot_key, player_skills)
	var icon_id := icon_id_for_skill(registry, skill_id)
	return {
		"skill_id": skill_id,
		"icon_id": icon_id,
		"texture": load_texture(icon_path(registry, icon_id)),
		"color": icon_color(registry, icon_id, default_color),
		"letter": fallback_letter(registry, skill_id, slot_key),
	}
