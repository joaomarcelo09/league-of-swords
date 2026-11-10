class_name Inventory
extends RefCounted

var item_db: ItemDB:
	get:
		return _item_db
	set(val):
		_item_db = val

var _item_db: ItemDB = null
var _next_uid: int = 1
var _items: Dictionary = {}
var _equipment: Dictionary = {}


func _init(p_item_db: ItemDB = null) -> void:
	_item_db = p_item_db


static func is_valid_owner(owner_str: String) -> bool:
	var colon_idx := owner_str.find(":")
	if colon_idx <= 0 or colon_idx >= owner_str.length() - 1:
		return false
	var prefix := owner_str.substr(0, colon_idx)
	var suffix := owner_str.substr(colon_idx + 1).strip_edges()
	if suffix.is_empty():
		return false
	return prefix in ["character", "merchant", "container", "ground"]


func create(def_id: String, owner: String) -> int:
	if _item_db == null:
		push_error("Inventory.create: item_db is required to create items")
		return -1

	if def_id.strip_edges().is_empty():
		push_error("Inventory.create: def_id is empty")
		return -1

	if not _item_db.has_item(def_id):
		push_error("Inventory.create: unknown item definition '%s'" % def_id)
		return -1

	if not is_valid_owner(owner):
		push_error("Inventory.create: invalid owner string '%s'" % owner)
		return -1

	var uid := _next_uid
	_next_uid += 1
	_items[uid] = {
		"uid": uid,
		"def_id": def_id,
		"owner": owner
	}
	return uid


func owner_of(uid: int) -> String:
	if not _items.has(uid):
		push_error("Inventory.owner_of: unknown item uid %d" % uid)
		return ""
	return str(_items[uid]["owner"])


func def_id_of(uid: int) -> String:
	if not _items.has(uid):
		push_error("Inventory.def_id_of: unknown item uid %d" % uid)
		return ""
	return str(_items[uid]["def_id"])


func is_consumed(uid: int) -> bool:
	return _items.has(uid) and _items[uid]["owner"] == "consumed"


func transfer(uid: int, new_owner: String) -> bool:
	if not _items.has(uid):
		push_error("Inventory.transfer: unknown item uid %d" % uid)
		return false

	if _items[uid]["owner"] == "consumed":
		push_error("Inventory.transfer: cannot transfer consumed item %d" % uid)
		return false

	if new_owner != "consumed" and not is_valid_owner(new_owner):
		push_error("Inventory.transfer: invalid new_owner '%s'" % new_owner)
		return false

	var old_owner: String = _items[uid]["owner"]
	if old_owner != new_owner and _equipment.has(old_owner):
		var eq: Dictionary = _equipment[old_owner]
		if eq.has("weapon") and eq["weapon"] == uid:
			eq.erase("weapon")
		if eq.has("armor") and eq["armor"] == uid:
			eq.erase("armor")

	_items[uid]["owner"] = new_owner
	return true


func items_of(owner: String) -> Array[int]:
	var result: Array[int] = []
	for uid: int in _items.keys():
		if _items[uid]["owner"] == owner:
			result.append(uid)
	result.sort()
	return result


func pickup(uid: int, character_owner: String) -> bool:
	if not character_owner.begins_with("character:"):
		push_error("Inventory.pickup: recipient must be a character owner, got '%s'" % character_owner)
		return false

	if not _items.has(uid):
		push_error("Inventory.pickup: unknown item uid %d" % uid)
		return false

	var cur_owner: String = _items[uid]["owner"]
	if not cur_owner.begins_with("ground:"):
		push_error("Inventory.pickup: item %d is not on the ground (owner is '%s')" % [uid, cur_owner])
		return false

	return transfer(uid, character_owner)


func drop(uid: int, zone: String) -> bool:
	if not _items.has(uid):
		push_error("Inventory.drop: unknown item uid %d" % uid)
		return false

	if _items[uid]["owner"] == "consumed":
		push_error("Inventory.drop: cannot drop consumed item %d" % uid)
		return false

	var ground_owner := zone if zone.begins_with("ground:") else "ground:%s" % zone
	return transfer(uid, ground_owner)


func equip(character_owner: String, uid: int) -> bool:
	if not character_owner.begins_with("character:"):
		push_error("Inventory.equip: only characters can equip items, got '%s'" % character_owner)
		return false

	if not _items.has(uid):
		push_error("Inventory.equip: unknown item uid %d" % uid)
		return false

	if _items[uid]["owner"] != character_owner:
		push_error("Inventory.equip: item %d is not owned by '%s' (owner is '%s')" % [
			uid, character_owner, _items[uid]["owner"]
		])
		return false

	if _item_db == null:
		push_error("Inventory.equip: item_db is required to equip items")
		return false

	var def_id: String = _items[uid]["def_id"]
	var item_def := _item_db.get_item(def_id)
	if item_def.is_empty():
		return false

	var item_type := str(item_def["type"]) if item_def.has("type") else ""
	if item_type != "weapon" and item_type != "armor":
		push_error("Inventory.equip: item %d is of type '%s' and cannot be equipped" % [uid, item_type])
		return false

	if not _equipment.has(character_owner):
		_equipment[character_owner] = {}

	_equipment[character_owner][item_type] = uid
	return true


func unequip(character_owner: String, slot: String) -> bool:
	if _equipment.has(character_owner) and _equipment[character_owner].has(slot):
		_equipment[character_owner].erase(slot)
		return true
	return false


func get_equipped(character_owner: String, slot: String) -> int:
	if _equipment.has(character_owner) and _equipment[character_owner].has(slot):
		return int(_equipment[character_owner][slot])
	return 0


func get_all_equipped(character_owner: String) -> Dictionary:
	if _equipment.has(character_owner):
		return _equipment[character_owner].duplicate()
	return {}


func equipped_stats(base: Stats, character_owner: String) -> Stats:
	if base == null:
		push_error("Inventory.equipped_stats: base Stats is null")
		return null

	var copy := base.duplicate()
	if not _equipment.has(character_owner):
		return copy

	var eq: Dictionary = _equipment[character_owner]

	if eq.has("weapon") and eq["weapon"] > 0:
		var w_uid: int = eq["weapon"]
		if _items.has(w_uid) and _item_db != null:
			var w_def := _item_db.get_item(_items[w_uid]["def_id"])
			if w_def.has("stats") and (w_def["stats"] is Dictionary):
				var w_stats: Dictionary = w_def["stats"]
				if w_stats.has("weapon_damage"):
					copy.weapon_damage = float(w_stats["weapon_damage"])
				if w_stats.has("atk"):
					copy.atk += float(w_stats["atk"])

	if eq.has("armor") and eq["armor"] > 0:
		var a_uid: int = eq["armor"]
		if _items.has(a_uid) and _item_db != null:
			var a_def := _item_db.get_item(_items[a_uid]["def_id"])
			if a_def.has("stats") and (a_def["stats"] is Dictionary):
				var a_stats: Dictionary = a_def["stats"]
				if a_stats.has("defense"):
					copy.defense += float(a_stats["defense"])
				if a_stats.has("max_hp"):
					copy.max_hp += float(a_stats["max_hp"])

	return copy


func use(uid: int, entity: Variant, character_owner: String = "") -> bool:
	if not _items.has(uid):
		push_error("Inventory.use: unknown item uid %d" % uid)
		return false

	if _items[uid]["owner"] == "consumed":
		push_error("Inventory.use: item %d has already been consumed" % uid)
		return false

	if entity == null:
		push_error("Inventory.use: entity is null")
		return false

	if not ("kind" in entity and entity.kind == "player"):
		var kind_str := str(entity.kind) if "kind" in entity else "<unknown>"
		push_error("Inventory.use: non-player entity (kind '%s') cannot use items" % kind_str)
		return false

	var acting_owner := character_owner
	if acting_owner.is_empty():
		if "id" in entity:
			acting_owner = "character:%s" % str(entity.id)

	if not acting_owner.begins_with("character:"):
		push_error("Inventory.use: only characters can use items, got '%s'" % acting_owner)
		return false

	if _items[uid]["owner"] != acting_owner:
		push_error("Inventory.use: item %d is not owned by '%s' (owner is '%s')" % [
			uid, acting_owner, _items[uid]["owner"]
		])
		return false

	if ("dead" in entity and entity.dead) or ("hp" in entity and entity.hp <= 0.0):
		push_error("Inventory.use: cannot use consumable on dead entity")
		return false

	if _item_db == null:
		push_error("Inventory.use: item_db is required to use consumable")
		return false

	var def_id: String = _items[uid]["def_id"]
	var item_def := _item_db.get_item(def_id)
	if item_def.is_empty():
		return false

	var item_type := str(item_def["type"]) if item_def.has("type") else ""
	if item_type != "consumable":
		push_error("Inventory.use: item %d is of type '%s', not consumable" % [uid, item_type])
		return false

	var heal_amount := 0.0
	if not item_def.has("effects") or not (item_def["effects"] is Dictionary or item_def["effects"] is Array):
		push_error("Inventory.use: consumable %d definition missing 'effects'" % uid)
		return false

	var eff_val: Variant = item_def["effects"]
	if eff_val is Dictionary:
		var eff_dict: Dictionary = eff_val
		if eff_dict.has("heal") and (eff_dict["heal"] is int or eff_dict["heal"] is float):
			heal_amount = float(eff_dict["heal"])
	elif eff_val is Array:
		var eff_arr: Array = eff_val
		for eff: Variant in eff_arr:
			if eff is Dictionary:
				var d: Dictionary = eff
				if d.has("type") and str(d["type"]) == "heal":
					if d.has("amount") and (d["amount"] is int or d["amount"] is float):
						heal_amount += float(d["amount"])
					elif d.has("heal") and (d["heal"] is int or d["heal"] is float):
						heal_amount += float(d["heal"])

	if heal_amount <= 0.0:
		push_error("Inventory.use: consumable %d has no positive heal amount" % uid)
		return false

	var max_hp := 0.0
	if "stats" in entity and entity.stats != null and entity.stats.max_hp > 0.0:
		max_hp = entity.stats.max_hp
	elif "max_hp" in entity and float(entity.max_hp) > 0.0:
		max_hp = float(entity.max_hp)

	if max_hp <= 0.0:
		push_error("Inventory.use: entity has no valid max_hp")
		return false

	entity.hp = minf(max_hp, entity.hp + heal_amount)
	_items[uid]["owner"] = "consumed"
	return true


func to_dict() -> Dictionary:
	var items_dict: Dictionary = {}
	for uid_val: Variant in _items.keys():
		var uid: int = int(uid_val)
		var item: Dictionary = _items[uid_val]
		items_dict[uid] = {
			"uid": int(item["uid"]),
			"def_id": str(item["def_id"]),
			"owner": str(item["owner"])
		}
	return {
		"next_uid": _next_uid,
		"items": items_dict,
		"equipment": _equipment.duplicate(true)
	}


static func from_dict(dict: Dictionary, p_item_db: ItemDB = null) -> Inventory:
	if p_item_db == null:
		push_error("Inventory.from_dict: item_db is required")
		return null

	if dict.is_empty():
		push_error("Inventory.from_dict: dict is empty")
		return null

	if not dict.has("next_uid") or not (dict["next_uid"] is int or dict["next_uid"] is float):
		push_error("Inventory.from_dict: missing or invalid 'next_uid'")
		return null
	var next_uid_val := float(dict["next_uid"])
	if not is_finite(next_uid_val) or next_uid_val < 1.0 or floor(next_uid_val) != next_uid_val:
		push_error("Inventory.from_dict: 'next_uid' must be integer >= 1")
		return null
	var next_uid := int(next_uid_val)

	if not dict.has("items") or not (dict["items"] is Dictionary):
		push_error("Inventory.from_dict: missing or invalid 'items' dictionary")
		return null

	if not dict.has("equipment") or not (dict["equipment"] is Dictionary):
		push_error("Inventory.from_dict: missing or invalid 'equipment' dictionary")
		return null

	var parsed_items: Dictionary = {}
	var raw_items: Dictionary = dict["items"]
	for k: Variant in raw_items.keys():
		var k_str := str(k)
		if not k_str.is_valid_int():
			push_error("Inventory.from_dict: invalid item key '%s'" % k_str)
			return null
		var key_uid := int(k_str)
		if key_uid < 1:
			push_error("Inventory.from_dict: item key uid must be >= 1, got %d" % key_uid)
			return null
		if key_uid >= next_uid:
			push_error("Inventory.from_dict: item uid %d >= next_uid %d" % [key_uid, next_uid])
			return null

		var item_val: Variant = raw_items[k]
		if not (item_val is Dictionary):
			push_error("Inventory.from_dict: item %s is not a dictionary" % k_str)
			return null
		var item_dict: Dictionary = item_val

		if not item_dict.has("uid") or not (item_dict["uid"] is int or item_dict["uid"] is float):
			push_error("Inventory.from_dict: item %s missing valid 'uid'" % k_str)
			return null
		var item_uid := int(item_dict["uid"])
		if item_uid != key_uid:
			push_error("Inventory.from_dict: item key %d does not match internal uid %d" % [key_uid, item_uid])
			return null

		if not item_dict.has("def_id") or not (item_dict["def_id"] is String) or str(item_dict["def_id"]).strip_edges().is_empty():
			push_error("Inventory.from_dict: item %d missing valid 'def_id'" % item_uid)
			return null
		var def_id := str(item_dict["def_id"])
		if not p_item_db.has_item(def_id):
			push_error("Inventory.from_dict: item %d references unknown def_id '%s'" % [item_uid, def_id])
			return null

		if not item_dict.has("owner") or not (item_dict["owner"] is String):
			push_error("Inventory.from_dict: item %d missing valid 'owner'" % item_uid)
			return null
		var owner := str(item_dict["owner"])
		if owner != "consumed" and not is_valid_owner(owner):
			push_error("Inventory.from_dict: item %d has invalid owner '%s'" % [item_uid, owner])
			return null

		parsed_items[item_uid] = {
			"uid": item_uid,
			"def_id": def_id,
			"owner": owner
		}

	var parsed_equipment: Dictionary = {}
	var raw_equipment: Dictionary = dict["equipment"]
	for char_key: Variant in raw_equipment.keys():
		var char_owner := str(char_key)
		if not char_owner.begins_with("character:"):
			push_error("Inventory.from_dict: equipment key must be character owner, got '%s'" % char_owner)
			return null

		var char_eq_val: Variant = raw_equipment[char_key]
		if not (char_eq_val is Dictionary):
			push_error("Inventory.from_dict: equipment for '%s' must be dictionary" % char_owner)
			return null
		var char_eq: Dictionary = char_eq_val

		var slots_eq: Dictionary = {}
		for slot_key: Variant in char_eq.keys():
			var slot := str(slot_key)
			if slot != "weapon" and slot != "armor":
				push_error("Inventory.from_dict: invalid equipment slot '%s'" % slot)
				return null

			var eq_uid_val: Variant = char_eq[slot_key]
			if not (eq_uid_val is int or eq_uid_val is float):
				push_error("Inventory.from_dict: equipped uid in slot '%s' must be numeric" % slot)
				return null
			var eq_uid := int(eq_uid_val)
			if not parsed_items.has(eq_uid):
				push_error("Inventory.from_dict: equipped uid %d in slot '%s' does not exist in items" % [eq_uid, slot])
				return null
			if parsed_items[eq_uid]["owner"] != char_owner:
				push_error("Inventory.from_dict: equipped item %d in slot '%s' not owned by '%s'" % [eq_uid, slot, char_owner])
				return null

			var item_def := p_item_db.get_item(parsed_items[eq_uid]["def_id"])
			if item_def.has("type") and str(item_def["type"]) != slot:
				push_error("Inventory.from_dict: item %d type '%s' does not match slot '%s'" % [
					eq_uid, str(item_def["type"]), slot
				])
				return null

			slots_eq[slot] = eq_uid

		parsed_equipment[char_owner] = slots_eq

	var inv := Inventory.new(p_item_db)
	inv._next_uid = next_uid
	inv._items = parsed_items
	inv._equipment = parsed_equipment
	return inv
