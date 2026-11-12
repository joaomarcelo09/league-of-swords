class_name Lifecycle
extends RefCounted

const DEFAULT_MERCHANT_ID: String = "floor1_smith"
const DEFAULT_ZONE: String = "floor1"
const DEFAULT_ENTRY: Array = [4.0, 8.0]

static var _cached_config: Dictionary = {}

var _registry: DataRegistry = null
var _store: SaveStore = null
var _slot: String = ""


func _init(p_registry: DataRegistry = null, p_store: SaveStore = null, p_slot: String = "") -> void:
	_registry = p_registry
	_store = p_store
	_slot = p_slot


static func clear_cached_config() -> void:
	_cached_config.clear()


static func get_balance_config(registry: DataRegistry = null) -> Dictionary:
	if registry != null:
		var cfg: Variant = registry.get_balance("permadeath")
		if cfg is Dictionary:
			return cfg as Dictionary

	if not _cached_config.is_empty():
		return _cached_config

	if FileAccess.file_exists("res://data/balance.json"):
		var f := FileAccess.open("res://data/balance.json", FileAccess.READ)
		if f != null:
			var txt := f.get_as_text()
			f.close()
			var json := JSON.new()
			if json.parse(txt) == OK and json.data is Dictionary:
				var root: Dictionary = json.data
				if root.has("permadeath") and root["permadeath"] is Dictionary:
					_cached_config = (root["permadeath"] as Dictionary).duplicate(true)
					return _cached_config

	return {
		"merchant_id": DEFAULT_MERCHANT_ID,
		"default_zone": DEFAULT_ZONE,
		"default_entry": DEFAULT_ENTRY.duplicate(),
		"default_stats": {
			"max_hp": 100.0,
			"atk": 10.0,
			"defense": 2.0,
			"attack_range": 1.5,
			"attack_interval": 1.0,
			"weapon_damage": 5.0,
		}
	}


static func on_player_death(
	world: WorldState,
	character: CharacterState,
	cause: String,
	date_str: String,
	store: SaveStore = null,
	slot: String = "",
	merchant_id: String = "",
	registry: DataRegistry = null
) -> Dictionary:
	if world == null:
		return {
			"ok": false,
			"error": "world cannot be null",
			"value": null
		}
	if character == null:
		return {
			"ok": false,
			"error": "character cannot be null",
			"value": null
		}

	# Validate merchant_id before touching equipment or items
	var target_merchant := merchant_id.strip_edges()
	if target_merchant.is_empty():
		var cfg := get_balance_config(registry)
		target_merchant = str(cfg.get("merchant_id", DEFAULT_MERCHANT_ID)).strip_edges()

	var merchant_owner := ""
	if target_merchant.begins_with("merchant:"):
		merchant_owner = target_merchant
	elif not target_merchant.contains(":"):
		merchant_owner = "merchant:" + target_merchant
	else:
		merchant_owner = target_merchant

	if not Inventory.is_valid_owner(merchant_owner) or not merchant_owner.begins_with("merchant:") or target_merchant == "invalid":
		return {
			"ok": false,
			"error": "Invalid merchant id '%s' (resolved owner '%s')" % [target_merchant, merchant_owner],
			"value": null
		}

	# Always mark character dead (even if already dead on retry)
	character.status = "dead"

	# Exactly one cemetery entry for this character (dedupe by character_id across reloads)
	var cemetery_entry: Dictionary = {
		"character_id": character.id,
		"name": character.name,
		"level": character.level,
		"zone": character.zone,
		"cause": cause,
		"date": date_str,
		"appearance": character.appearance.duplicate(true)
	}

	var found_entry := false
	var new_cemetery: Array[Dictionary] = []
	for entry: Dictionary in world.cemetery:
		var matches := false
		if entry.has("character_id") and not str(entry["character_id"]).is_empty():
			matches = (str(entry["character_id"]) == character.id)
		elif not character.id.is_empty():
			matches = (entry.get("name") == character.name)

		if matches:
			if not found_entry:
				var keep_entry := entry.duplicate(true)
				if not keep_entry.has("character_id") or str(keep_entry["character_id"]).is_empty():
					keep_entry["character_id"] = character.id
				new_cemetery.append(keep_entry)
				found_entry = true
			# else: skip duplicate entry
		else:
			new_cemetery.append(entry)

	if not found_entry:
		new_cemetery.append(cemetery_entry)
	world.cemetery = new_cemetery

	# Unequip and transfer every item owned by character:<id> to merchant
	if world.inventory != null:
		var char_owner := character.id if character.id.begins_with("character:") else "character:" + character.id
		var equipped := world.inventory.get_all_equipped(char_owner)
		for eq_slot in equipped.keys():
			var eq_uid: int = int(equipped[eq_slot])
			var unequip_ok := world.inventory.unequip(char_owner, str(eq_slot))
			if not unequip_ok:
				return {
					"ok": false,
					"error": "Failed to unequip item %d from slot '%s'" % [eq_uid, str(eq_slot)],
					"value": null
				}

		var items := world.inventory.items_of(char_owner)
		for uid: int in items:
			var transfer_ok := world.inventory.transfer(uid, merchant_owner)
			if not transfer_ok:
				return {
					"ok": false,
					"error": "Failed to transfer item %d to '%s'" % [uid, merchant_owner],
					"value": null
				}

	# Persist CHARACTER (dead) first, then world, so a failed world save never leaves a playable character
	if store != null and not slot.is_empty():
		var save_c := store.save_character(slot, character)
		if not save_c.get("ok", false):
			return save_c
		var save_w := store.save_world(slot, world)
		if not save_w.get("ok", false):
			return save_w

	return {
		"ok": true,
		"error": "",
		"value": character
	}


static func new_character(
	world: WorldState,
	name: String,
	appearance: Dictionary,
	zone_entry: Variant = null,
	store: SaveStore = null,
	slot: String = "",
	base_stats: Stats = null,
	zone: String = "",
	registry: DataRegistry = null
) -> Dictionary:
	if world == null:
		return {
			"ok": false,
			"error": "world cannot be null",
			"value": null
		}
	if name.strip_edges().is_empty():
		return {
			"ok": false,
			"error": "character name cannot be empty",
			"value": null
		}

	var next_id: int = 1
	if world.flags.has("next_character_id"):
		next_id = int(world.flags["next_character_id"])
	if next_id <= 0:
		next_id = 1

	var existing_ids: Array[String] = []
	if store != null and not slot.is_empty():
		var list_res := store.list_characters(slot)
		if list_res.get("ok", false) and list_res.get("value") is Array:
			for cid in list_res["value"]:
				existing_ids.append(str(cid))

	var char_id := "char_%d" % next_id
	while char_id in existing_ids:
		next_id += 1
		char_id = "char_%d" % next_id

	var prev_next_id: Variant = world.flags.get("next_character_id", null)
	world.flags["next_character_id"] = next_id + 1

	var cs_stats: Stats = null
	if base_stats != null:
		cs_stats = base_stats.duplicate()
	else:
		var cfg := get_balance_config(registry)
		if cfg.has("default_stats") and cfg["default_stats"] is Dictionary:
			cs_stats = Stats.from_dict(cfg["default_stats"] as Dictionary)
		elif registry != null:
			var player_stats: Variant = registry.get_balance("player")
			if player_stats is Dictionary:
				cs_stats = Stats.from_dict(player_stats as Dictionary)
		if cs_stats == null:
			cs_stats = Stats.new(100.0, 10.0, 2.0, 1.5, 1.0, 5.0)

	var char_zone := zone
	if char_zone.is_empty():
		var cfg := get_balance_config(registry)
		char_zone = str(cfg.get("default_zone", DEFAULT_ZONE))

	var pos: Array = [0.0, 0.0]
	if zone_entry is Vector2i:
		pos = [float(zone_entry.x), float(zone_entry.y)]
	elif zone_entry is Vector2:
		pos = [float(zone_entry.x), float(zone_entry.y)]
	elif (zone_entry is Array or zone_entry is PackedFloat32Array or zone_entry is PackedInt32Array) and zone_entry.size() >= 2:
		pos = [float(zone_entry[0]), float(zone_entry[1])]
	elif zone_entry != null and zone_entry is Object and zone_entry.get("entry") != null:
		var e: Variant = zone_entry.get("entry")
		if e is Vector2i or e is Vector2:
			pos = [float(e.x), float(e.y)]
		elif (e is Array or e is PackedInt32Array) and e.size() >= 2:
			pos = [float(e[0]), float(e[1])]
	else:
		var cfg := get_balance_config(registry)
		var def_entry: Variant = cfg.get("default_entry", DEFAULT_ENTRY)
		if def_entry is Array and def_entry.size() >= 2:
			pos = [float(def_entry[0]), float(def_entry[1])]
		else:
			pos = [0.0, 0.0]

	var cs := CharacterState.new()
	cs.id = char_id
	cs.status = "alive"
	cs.name = name
	cs.appearance = appearance.duplicate(true)
	cs.level = 1
	cs.xp = 0
	cs.stats = cs_stats
	cs.zone = char_zone
	cs.position = pos

	if store != null and not slot.is_empty():
		var save_c := store.save_character(slot, cs)
		if not save_c.get("ok", false):
			if prev_next_id == null:
				world.flags.erase("next_character_id")
			else:
				world.flags["next_character_id"] = prev_next_id
			return save_c

		var save_w := store.save_world(slot, world)
		if not save_w.get("ok", false):
			if prev_next_id == null:
				world.flags.erase("next_character_id")
			else:
				world.flags["next_character_id"] = prev_next_id
			var char_path := store.get_character_file_path(slot, cs.id)
			if FileAccess.file_exists(char_path):
				DirAccess.remove_absolute(char_path)
			return save_w

	return {
		"ok": true,
		"error": "",
		"value": cs
	}


static func load_playable(store: SaveStore, slot: String, char_id: String, item_db: ItemDB = null) -> Dictionary:
	if store == null:
		return {
			"ok": false,
			"error": "store cannot be null",
			"value": null
		}
	var res := store.load_character(slot, char_id, item_db)
	if not res.get("ok", false):
		return res

	var character: CharacterState = res.get("value")
	if character == null:
		return {
			"ok": false,
			"error": "Failed to load character '%s'" % char_id,
			"value": null
		}

	if character.status == "dead":
		return {
			"ok": false,
			"error": "Character '%s' is dead and cannot be loaded as playable" % char_id,
			"value": null
		}

	return {
		"ok": true,
		"error": "",
		"value": character
	}


static func cause_from_death_event(death_event: Dictionary, world_sim: WorldSim = null) -> String:
	if death_event.has("cause") and not str(death_event["cause"]).is_empty():
		return str(death_event["cause"])

	if world_sim != null and death_event.has("source"):
		var src_id: Variant = death_event["source"]
		if src_id != null and world_sim.entities.has(src_id):
			var ent: Entity = world_sim.entities[src_id]
			if ent != null:
				if not ent.enemy_type_id.is_empty():
					return ent.enemy_type_id
				elif not ent.kind.is_empty():
					return ent.kind

	if death_event.has("source") and death_event["source"] != null and not str(death_event["source"]).is_empty():
		return str(death_event["source"])

	return "unknown"


static func on_player_death_event(
	death_event: Dictionary,
	world: WorldState,
	character: CharacterState,
	date_str: String,
	store: SaveStore = null,
	slot: String = "",
	world_sim: WorldSim = null,
	player_entity_id: int = -1,
	merchant_id: String = "",
	registry: DataRegistry = null
) -> Dictionary:
	if death_event.get("type") != "death":
		return {
			"ok": false,
			"error": "Expected death event, got '%s'" % str(death_event.get("type")),
			"value": null
		}

	if player_entity_id >= 0 and death_event.has("target"):
		if int(death_event["target"]) != player_entity_id:
			return {
				"ok": false,
				"error": "Death event target %d does not match player entity %d" % [int(death_event["target"]), player_entity_id],
				"value": null
			}

	var cause := cause_from_death_event(death_event, world_sim)
	return on_player_death(world, character, cause, date_str, store, slot, merchant_id, registry)


static func on_sim_death_event(
	death_event: Dictionary,
	world: WorldState,
	character: CharacterState,
	date_str: String,
	store: SaveStore = null,
	slot: String = "",
	world_sim: WorldSim = null,
	player_entity_id: int = -1,
	merchant_id: String = "",
	registry: DataRegistry = null
) -> Dictionary:
	return on_player_death_event(death_event, world, character, date_str, store, slot, world_sim, player_entity_id, merchant_id, registry)


static func handle_player_death_event(
	death_event: Dictionary,
	world: WorldState,
	character: CharacterState,
	date_str: String,
	store: SaveStore = null,
	slot: String = "",
	world_sim: WorldSim = null,
	player_entity_id: int = -1,
	merchant_id: String = "",
	registry: DataRegistry = null
) -> Dictionary:
	return on_player_death_event(death_event, world, character, date_str, store, slot, world_sim, player_entity_id, merchant_id, registry)


# Instance methods forwarding to static methods
func death(world: WorldState, character: CharacterState, cause: String, date_str: String, slot_override: String = "") -> Dictionary:
	var use_slot := slot_override if not slot_override.is_empty() else _slot
	return on_player_death(world, character, cause, date_str, _store, use_slot, "", _registry)


func create_character(world: WorldState, name: String, appearance: Dictionary, zone_entry: Variant = null, slot_override: String = "") -> Dictionary:
	var use_slot := slot_override if not slot_override.is_empty() else _slot
	return new_character(world, name, appearance, zone_entry, _store, use_slot, null, "", _registry)


func load_playable_character(char_id: String, slot_override: String = "", item_db: ItemDB = null) -> Dictionary:
	var use_slot := slot_override if not slot_override.is_empty() else _slot
	return load_playable(_store, use_slot, char_id, item_db)
