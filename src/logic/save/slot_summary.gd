class_name SlotSummary
extends RefCounted


## Inspects a save slot and summarizes its state.
## Returns a Dictionary with:
##   has_world: bool
##   world_ok: bool
##   living_character_id: String
##   living_name: String
##   living_level: int
##   living_zone: String
##   dead_count: int
##   error: String
static func inspect(store: SaveStore, slot: String, item_db: ItemDB = null) -> Dictionary:
	var result: Dictionary = {
		"has_world": false,
		"world_ok": false,
		"living_character_id": "",
		"living_name": "",
		"living_level": 0,
		"living_zone": "",
		"dead_count": 0,
		"error": "",
	}

	if store == null:
		result["error"] = "store cannot be null"
		return result

	if not SaveStore.is_valid_name(slot):
		result["error"] = "Invalid or unsafe slot name '%s'" % slot
		return result

	if not store.slot_exists(slot):
		return result

	var world_file_path := store.get_world_file_path(slot)
	var has_world := FileAccess.file_exists(world_file_path)
	result["has_world"] = has_world

	if not has_world:
		return result

	var world_res := store.load_world(slot, item_db)
	if not world_res.get("ok", false):
		result["world_ok"] = false
		result["error"] = str(world_res.get("error", "Failed to load world"))
		return result

	result["world_ok"] = true
	var world_state: WorldState = world_res.get("value")

	var dead_ids: Dictionary = {}
	if world_state != null:
		for entry_val: Variant in world_state.cemetery:
			if entry_val is Dictionary:
				var entry: Dictionary = entry_val
				var cid := str(entry.get("character_id", ""))
				if cid.is_empty():
					cid = str(entry.get("name", ""))
				if not cid.is_empty():
					dead_ids[cid] = true
				else:
					result["dead_count"] += 1

	var list_res := store.list_characters(slot)
	if list_res.get("ok", false) and list_res.get("value") is Array:
		var char_ids: Array = list_res.get("value")
		for cid_variant: Variant in char_ids:
			var cid := str(cid_variant)
			var load_res := Lifecycle.load_playable(store, slot, cid, item_db)
			if load_res.get("ok", false) and load_res.get("value") is CharacterState:
				var char_state: CharacterState = load_res["value"]
				if result["living_character_id"].is_empty():
					result["living_character_id"] = char_state.id
					result["living_name"] = char_state.name
					result["living_level"] = char_state.level
					result["living_zone"] = char_state.zone
			else:
				var char_res := store.load_character(slot, cid, item_db)
				if char_res.get("ok", false) and char_res.get("value") is CharacterState:
					var cs: CharacterState = char_res["value"]
					if cs.status == "dead":
						dead_ids[cs.id] = true

	result["dead_count"] += dead_ids.size()
	return result
