class_name ItemDB
extends RefCounted

var _items: Dictionary = {}
var _loot_tables: Dictionary = {}
var _id_regex: RegEx = null


func _init(registry: DataRegistry = null) -> void:
	_id_regex = RegEx.new()
	_id_regex.compile("^[a-z0-9_]+$")
	if registry != null:
		load_from_registry(registry)


static func _get_static_regex() -> RegEx:
	var r := RegEx.new()
	r.compile("^[a-z0-9_]+$")
	return r


static func validate_item(dict: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if dict.is_empty():
		errors.append("item dictionary is empty")
		return errors

	if not dict.has("id") or not (dict["id"] is String) or str(dict["id"]).strip_edges().is_empty():
		errors.append("missing or invalid 'id'")
	else:
		var id_str := str(dict["id"])
		if _get_static_regex().search(id_str) == null:
			errors.append("item id '%s' is not valid snake_case" % id_str)

	if not dict.has("name") or not (dict["name"] is String) or str(dict["name"]).strip_edges().is_empty():
		errors.append("missing or invalid 'name'")

	var item_type := ""
	if not dict.has("type") or not (dict["type"] is String):
		errors.append("missing or invalid 'type'")
	else:
		item_type = str(dict["type"])
		if not item_type in ["weapon", "armor", "consumable"]:
			errors.append("invalid 'type' '%s' (must be weapon, armor, or consumable)" % item_type)

	if not dict.has("floor_tier") or not (dict["floor_tier"] is int or dict["floor_tier"] is float):
		errors.append("missing or invalid 'floor_tier'")
	else:
		var tier_val := float(dict["floor_tier"])
		if not is_finite(tier_val) or tier_val < 1.0 or floor(tier_val) != tier_val:
			errors.append("invalid 'floor_tier' (must be integer >= 1)")

	match item_type:
		"weapon":
			if not dict.has("stats") or not (dict["stats"] is Dictionary):
				errors.append("weapon requires 'stats' dictionary")
			else:
				var stats_dict: Dictionary = dict["stats"]
				if not stats_dict.has("weapon_damage") or not (stats_dict["weapon_damage"] is int or stats_dict["weapon_damage"] is float):
					errors.append("weapon stats missing 'weapon_damage'")
				else:
					var wd := float(stats_dict["weapon_damage"])
					if not is_finite(wd) or wd <= 0.0:
						errors.append("weapon 'weapon_damage' must be > 0.0")
		"armor":
			if not dict.has("stats") or not (dict["stats"] is Dictionary):
				errors.append("armor requires 'stats' dictionary")
			else:
				var stats_dict: Dictionary = dict["stats"]
				if not stats_dict.has("defense") or not (stats_dict["defense"] is int or stats_dict["defense"] is float):
					errors.append("armor stats missing 'defense'")
				else:
					var def := float(stats_dict["defense"])
					if not is_finite(def) or def < 0.0:
						errors.append("armor 'defense' must be >= 0.0")
		"consumable":
			if not dict.has("effects") or not (dict["effects"] is Dictionary or dict["effects"] is Array):
				errors.append("consumable requires 'effects' (dictionary or array)")
			else:
				var eff_val: Variant = dict["effects"]
				var heal_found := false
				if eff_val is Dictionary:
					var eff_dict: Dictionary = eff_val
					if eff_dict.has("heal") and (eff_dict["heal"] is int or eff_dict["heal"] is float):
						var h := float(eff_dict["heal"])
						if is_finite(h) and h > 0.0:
							heal_found = true
				elif eff_val is Array:
					var eff_arr: Array = eff_val
					for eff: Variant in eff_arr:
						if eff is Dictionary:
							var d: Dictionary = eff
							if d.get("type") == "heal":
								var amt: Variant = d.get("amount", d.get("heal", 0.0))
								if (amt is int or amt is float) and is_finite(float(amt)) and float(amt) > 0.0:
									heal_found = true
									break
				if not heal_found:
					errors.append("consumable requires positive 'heal' amount in effects")

	return errors


static func validate_loot_table(dict: Dictionary, known_item_ids: Array = []) -> Array[String]:
	var errors: Array[String] = []
	if dict.is_empty():
		errors.append("loot table dictionary is empty")
		return errors

	var has_rolls := dict.has("roll_count") or dict.has("rolls")
	if not has_rolls:
		errors.append("loot table missing 'roll_count' or 'rolls'")
	else:
		var rolls_val: Variant = dict.get("roll_count", dict.get("rolls"))
		if not (rolls_val is int or rolls_val is float):
			errors.append("loot table 'roll_count' must be a number")
		else:
			var r := float(rolls_val)
			if not is_finite(r) or r < 1.0 or floor(r) != r:
				errors.append("loot table 'roll_count' must be integer >= 1")

	if not dict.has("entries") or not (dict["entries"] is Array) or (dict["entries"] as Array).is_empty():
		errors.append("loot table missing or empty 'entries' array")
	else:
		var entries: Array = dict["entries"]
		for i in range(entries.size()):
			var entry_val: Variant = entries[i]
			if not (entry_val is Dictionary):
				errors.append("loot entry %d must be an object" % i)
				continue
			var entry: Dictionary = entry_val
			if not entry.has("item_id") or not (entry["item_id"] is String) or str(entry["item_id"]).strip_edges().is_empty():
				errors.append("loot entry %d missing or invalid 'item_id'" % i)
			elif not known_item_ids.has(str(entry["item_id"])):
				errors.append("loot entry %d references unknown item_id '%s'" % [i, str(entry["item_id"])])

			if not entry.has("chance") or not (entry["chance"] is int or entry["chance"] is float):
				errors.append("loot entry %d missing or invalid 'chance'" % i)
			else:
				var c := float(entry["chance"])
				if not is_finite(c) or c <= 0.0 or c > 1.0:
					errors.append("loot entry %d 'chance' must be > 0.0 and <= 1.0" % i)

	return errors


func load_from_registry(registry: DataRegistry) -> bool:
	if registry == null:
		push_error("ItemDB.load_from_registry: registry is null")
		return false

	var all_ids := registry.ids("items")
	if all_ids.is_empty():
		push_error("ItemDB.load_from_registry: no 'items' data found in registry")
		return false

	var all_ok := true

	# 1. Load item definitions
	var raw_items: Dictionary = {}
	if registry.has_entry("items", "items"):
		var nested: Dictionary = registry.get_entry("items", "items")
		for k: Variant in nested.keys():
			var item_val: Variant = nested[k]
			if item_val is Dictionary:
				raw_items[str(k)] = item_val
	else:
		for item_id in all_ids:
			if item_id == "loot_tables":
				continue
			var item_dict := registry.get_entry("items", item_id)
			if not item_dict.is_empty():
				raw_items[item_id] = item_dict

	for item_id: String in raw_items.keys():
		var item_dict: Dictionary = raw_items[item_id]
		if not register_item(item_dict):
			all_ok = false

	# 2. Load loot tables
	if registry.has_entry("items", "loot_tables"):
		var raw_tables: Dictionary = registry.get_entry("items", "loot_tables")
		for enemy_type_id: Variant in raw_tables.keys():
			var table_val: Variant = raw_tables[enemy_type_id]
			if not (table_val is Dictionary):
				push_error("ItemDB: loot table for '%s' must be an object" % enemy_type_id)
				all_ok = false
				continue
			var table_dict: Dictionary = table_val
			if not register_loot_table(str(enemy_type_id), table_dict):
				all_ok = false

	return all_ok


func register_item(item_dict: Dictionary) -> bool:
	var errs := validate_item(item_dict)
	if not errs.is_empty():
		for err: String in errs:
			push_error("ItemDB.register_item: %s" % err)
		return false

	var item_id := str(item_dict["id"])
	_items[item_id] = item_dict.duplicate(true)
	return true


func register_loot_table(enemy_type_id: String, table_dict: Dictionary) -> bool:
	if enemy_type_id.strip_edges().is_empty():
		push_error("ItemDB.register_loot_table: enemy_type_id is empty")
		return false

	var errs := validate_loot_table(table_dict, get_item_ids())
	if not errs.is_empty():
		for err: String in errs:
			push_error("ItemDB.register_loot_table: %s" % err)
		return false

	_loot_tables[enemy_type_id] = table_dict.duplicate(true)
	return true


func get_item(id: String) -> Dictionary:
	if _items.has(id):
		return _items[id]
	push_error("ItemDB.get_item: unknown item id '%s'" % id)
	return {}


func has_item(id: String) -> bool:
	return _items.has(id)


func get_item_ids() -> Array[String]:
	var result: Array[String] = []
	for k: Variant in _items.keys():
		result.append(str(k))
	result.sort()
	return result


func get_loot_table(enemy_type_id: String) -> Dictionary:
	if _loot_tables.has(enemy_type_id):
		return _loot_tables[enemy_type_id]
	push_error("ItemDB.get_loot_table: unknown enemy type '%s'" % enemy_type_id)
	return {}


func has_loot_table(enemy_type_id: String) -> bool:
	return _loot_tables.has(enemy_type_id)


func get_loot_enemy_ids() -> Array[String]:
	var result: Array[String] = []
	for k: Variant in _loot_tables.keys():
		result.append(str(k))
	result.sort()
	return result
