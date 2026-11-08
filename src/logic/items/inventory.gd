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
	if owner_str.is_empty():
		return false
	var colon_idx := owner_str.find(":")
	if colon_idx <= 0 or colon_idx >= owner_str.length() - 1:
		return false
	var prefix := owner_str.substr(0, colon_idx)
	var suffix := owner_str.substr(colon_idx + 1).strip_edges()
	if suffix.is_empty():
		return false
	return prefix in ["character", "merchant", "container", "ground"]


func create(def_id: String, owner: String) -> int:
	if def_id.strip_edges().is_empty():
		push_error("Inventory.create: def_id is empty")
		return -1

	if _item_db != null and not _item_db.has_item(def_id):
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
		if eq.get("weapon", 0) == uid:
			eq.erase("weapon")
		if eq.get("armor", 0) == uid:
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

	var item_type := str(item_def.get("type", ""))
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
	if _equipment.has(character_owner):
		return int(_equipment[character_owner].get(slot, 0))
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
			var w_stats: Dictionary = w_def.get("stats", {})
			if w_stats.has("weapon_damage"):
				copy.weapon_damage = float(w_stats["weapon_damage"])
			if w_stats.has("atk"):
				copy.atk += float(w_stats["atk"])

	if eq.has("armor") and eq["armor"] > 0:
		var a_uid: int = eq["armor"]
		if _items.has(a_uid) and _item_db != null:
			var a_def := _item_db.get_item(_items[a_uid]["def_id"])
			var a_stats: Dictionary = a_def.get("stats", {})
			if a_stats.has("defense"):
				copy.defense += float(a_stats["defense"])
			if a_stats.has("max_hp"):
				copy.max_hp += float(a_stats["max_hp"])

	return copy


func use(uid: int, entity: Variant) -> bool:
	if not _items.has(uid):
		push_error("Inventory.use: unknown item uid %d" % uid)
		return false

	if _items[uid]["owner"] == "consumed":
		push_error("Inventory.use: item %d has already been consumed" % uid)
		return false

	if entity == null:
		push_error("Inventory.use: entity is null")
		return false

	if entity.dead or ("hp" in entity and entity.hp <= 0.0):
		push_error("Inventory.use: cannot use consumable on dead entity")
		return false

	if _item_db == null:
		push_error("Inventory.use: item_db is required to use consumable")
		return false

	var def_id: String = _items[uid]["def_id"]
	var item_def := _item_db.get_item(def_id)
	if item_def.is_empty():
		return false

	var item_type := str(item_def.get("type", ""))
	if item_type != "consumable":
		push_error("Inventory.use: item %d is of type '%s', not consumable" % [uid, item_type])
		return false

	var heal_amount := 0.0
	var eff_val: Variant = item_def.get("effects", {})
	if eff_val is Dictionary:
		var eff_dict: Dictionary = eff_val
		heal_amount = float(eff_dict.get("heal", 0.0))
	elif eff_val is Array:
		var eff_arr: Array = eff_val
		for eff: Variant in eff_arr:
			if eff is Dictionary:
				var d: Dictionary = eff
				if d.get("type") == "heal":
					heal_amount += float(d.get("amount", d.get("heal", 0.0)))

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
