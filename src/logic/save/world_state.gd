class_name WorldState
extends RefCounted

const SAVE_VERSION: int = 1

static var last_error: String = ""

var version: int = SAVE_VERSION
var seed: int = 0
var floors_unlocked: int = 1
var bosses_defeated: Array[String] = []
var cemetery: Array[Dictionary] = []
var killed_enemies: int = 0
var flags: Dictionary = {}
var inventory: Inventory = null


func to_dict() -> Dictionary:
	var cemetery_copy: Array[Dictionary] = []
	for entry: Dictionary in cemetery:
		cemetery_copy.append(entry.duplicate(true))

	var inv_dict: Dictionary = {}
	if inventory != null:
		inv_dict = inventory.to_dict()
	else:
		inv_dict = {
			"next_uid": 1,
			"items": {},
			"equipment": {}
		}

	return {
		"version": version,
		"seed": seed,
		"floors_unlocked": floors_unlocked,
		"bosses_defeated": bosses_defeated.duplicate(),
		"cemetery": cemetery_copy,
		"killed_enemies": killed_enemies,
		"flags": flags.duplicate(true),
		"inventory": inv_dict,
	}


static func from_dict(dict: Dictionary, item_db: ItemDB = null, out_error: Array = []) -> WorldState:
	last_error = ""
	if dict == null or not (dict is Dictionary):
		return _fail("Invalid input: expected Dictionary", out_error)

	if item_db == null:
		return _fail("WorldState.from_dict requires a valid item_db", out_error)

	if not dict.has("version"):
		return _fail("Missing 'version' field", out_error)
	var ver_val: Variant = dict["version"]
	if not (ver_val is int or (ver_val is float and is_finite(ver_val) and floor(ver_val) == ver_val)):
		return _fail("Invalid 'version' type (expected int)", out_error)
	if int(ver_val) != SAVE_VERSION:
		return _fail("Unsupported version %s (expected %d)" % [str(ver_val), SAVE_VERSION], out_error)

	if not dict.has("seed"):
		return _fail("Missing 'seed' field", out_error)
	var seed_val: Variant = dict["seed"]
	if not (seed_val is int or (seed_val is float and is_finite(seed_val) and floor(seed_val) == seed_val)):
		return _fail("Invalid 'seed' type (expected int)", out_error)

	if not dict.has("floors_unlocked"):
		return _fail("Missing 'floors_unlocked' field", out_error)
	var floors_val: Variant = dict["floors_unlocked"]
	if not (floors_val is int or (floors_val is float and is_finite(floors_val) and floor(floors_val) == floors_val)):
		return _fail("Invalid 'floors_unlocked' type (expected int)", out_error)
	if int(floors_val) < 0:
		return _fail("Invalid 'floors_unlocked' value %d (must be >= 0)" % int(floors_val), out_error)

	if not dict.has("bosses_defeated"):
		return _fail("Missing 'bosses_defeated' field", out_error)
	if not (dict["bosses_defeated"] is Array):
		return _fail("Invalid 'bosses_defeated' type (expected Array)", out_error)

	if not dict.has("cemetery"):
		return _fail("Missing 'cemetery' field", out_error)
	if not (dict["cemetery"] is Array):
		return _fail("Invalid 'cemetery' type (expected Array)", out_error)

	for i in range(dict["cemetery"].size()):
		var entry: Variant = dict["cemetery"][i]
		if not (entry is Dictionary):
			return _fail("Invalid cemetery entry at index %d (expected Dictionary)" % i, out_error)
		var c_dict: Dictionary = entry
		if not c_dict.has("name") or not (c_dict["name"] is String):
			return _fail("Cemetery entry %d missing or invalid 'name'" % i, out_error)
		if not c_dict.has("level") or not (c_dict["level"] is int or (c_dict["level"] is float and is_finite(c_dict["level"]) and floor(c_dict["level"]) == c_dict["level"])):
			return _fail("Cemetery entry %d missing or invalid 'level'" % i, out_error)
		if not c_dict.has("zone") or not (c_dict["zone"] is String):
			return _fail("Cemetery entry %d missing or invalid 'zone'" % i, out_error)
		if not c_dict.has("cause") or not (c_dict["cause"] is String):
			return _fail("Cemetery entry %d missing or invalid 'cause'" % i, out_error)
		if not c_dict.has("date") or not (c_dict["date"] is String):
			return _fail("Cemetery entry %d missing or invalid 'date'" % i, out_error)
		if not c_dict.has("appearance") or not (c_dict["appearance"] is Dictionary):
			return _fail("Cemetery entry %d missing or invalid 'appearance'" % i, out_error)
		if c_dict.has("character_id") and not (c_dict["character_id"] is String):
			return _fail("Cemetery entry %d invalid 'character_id' (expected String)" % i, out_error)

	if not dict.has("killed_enemies"):
		return _fail("Missing 'killed_enemies' field", out_error)
	var killed_val: Variant = dict["killed_enemies"]
	if not (killed_val is int or (killed_val is float and is_finite(killed_val) and floor(killed_val) == killed_val)):
		return _fail("Invalid 'killed_enemies' type (expected int)", out_error)
	if int(killed_val) < 0:
		return _fail("Invalid 'killed_enemies' value %d (must be >= 0)" % int(killed_val), out_error)

	if not dict.has("flags"):
		return _fail("Missing 'flags' field", out_error)
	if not (dict["flags"] is Dictionary):
		return _fail("Invalid 'flags' type (expected Dictionary)", out_error)

	if not dict.has("inventory"):
		return _fail("Missing 'inventory' field", out_error)
	if not (dict["inventory"] is Dictionary):
		return _fail("Invalid 'inventory' type (expected Dictionary)", out_error)

	var inv := Inventory.from_dict(dict["inventory"] as Dictionary, item_db)
	if inv == null:
		return _fail("Failed to parse world inventory", out_error)

	var ws := WorldState.new()
	ws.version = int(ver_val)
	ws.seed = int(seed_val)
	ws.floors_unlocked = int(floors_val)

	var bosses: Array[String] = []
	for b: Variant in dict["bosses_defeated"]:
		bosses.append(str(b))
	ws.bosses_defeated = bosses

	var cem: Array[Dictionary] = []
	for c: Variant in dict["cemetery"]:
		var c_dict: Dictionary = (c as Dictionary).duplicate(true)
		c_dict["level"] = int(c_dict["level"])
		cem.append(c_dict)
	ws.cemetery = cem

	ws.killed_enemies = int(killed_val)
	ws.flags = (dict["flags"] as Dictionary).duplicate(true)
	ws.inventory = inv

	return ws


func get_character_items(char_id: String) -> Array[int]:
	if inventory == null:
		return []
	var owner := char_id if char_id.begins_with("character:") else "character:" + char_id
	return inventory.items_of(owner)


func get_character_equipment(char_id: String) -> Dictionary:
	if inventory == null:
		return {}
	var owner := char_id if char_id.begins_with("character:") else "character:" + char_id
	return inventory.get_all_equipped(owner)


func get_stock(merchant_id: String) -> Array[int]:
	if inventory == null:
		return []
	var owner := merchant_id if merchant_id.begins_with("merchant:") else "merchant:" + merchant_id
	return inventory.items_of(owner)


func get_container_items(container_id: String) -> Array[int]:
	if inventory == null:
		return []
	var owner := container_id if container_id.begins_with("container:") else "container:" + container_id
	return inventory.items_of(owner)


func get_items_of(owner: String) -> Array[int]:
	if inventory == null:
		return []
	return inventory.items_of(owner)


func equals(other: WorldState) -> bool:
	if other == null:
		return false
	return to_dict() == other.to_dict()


static func _fail(msg: String, out_error: Array = []) -> WorldState:
	last_error = msg
	if out_error != null and out_error is Array:
		out_error.append(msg)
	return null
