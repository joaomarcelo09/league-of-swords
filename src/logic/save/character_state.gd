class_name CharacterState
extends RefCounted

const SAVE_VERSION: int = 1

const STATS_KEYS: Array[String] = [
	"max_hp",
	"atk",
	"defense",
	"attack_range",
	"attack_interval",
	"weapon_damage"
]

static var last_error: String = ""

var version: int = SAVE_VERSION
var id: String = ""
var status: String = "alive"
var name: String = ""
var appearance: Dictionary = {}
var level: int = 1
var xp: int = 0
var stats: Stats = null
var zone: String = ""
var position: Array = [0.0, 0.0]


func to_dict() -> Dictionary:
	var stats_dict: Dictionary = {}
	if stats != null:
		stats_dict = stats.to_dict()

	var pos_arr: Array = [0.0, 0.0]
	if position.size() >= 2:
		pos_arr = [float(position[0]), float(position[1])]

	return {
		"version": version,
		"id": id,
		"status": status,
		"name": name,
		"appearance": appearance.duplicate(true),
		"level": level,
		"xp": xp,
		"stats": stats_dict,
		"zone": zone,
		"position": pos_arr,
	}


static func from_dict(dict: Dictionary, arg1: Variant = null, arg2: Variant = null) -> CharacterState:
	last_error = ""
	var out_error: Array = []
	if arg1 is Array:
		out_error = arg1
	elif arg2 is Array:
		out_error = arg2

	if dict == null or not (dict is Dictionary):
		return _fail("Invalid input: expected Dictionary", out_error)

	if not dict.has("version"):
		return _fail("Missing 'version' field", out_error)
	var ver_val: Variant = dict["version"]
	if not (ver_val is int or (ver_val is float and is_finite(ver_val) and floor(ver_val) == ver_val)):
		return _fail("Invalid 'version' type (expected int)", out_error)
	if int(ver_val) != SAVE_VERSION:
		return _fail("Unsupported version %s (expected %d)" % [str(ver_val), SAVE_VERSION], out_error)

	if not dict.has("id"):
		return _fail("Missing 'id' field", out_error)
	if not (dict["id"] is String) or str(dict["id"]).strip_edges().is_empty():
		return _fail("Invalid 'id' field (must be non-empty String)", out_error)

	if not dict.has("status"):
		return _fail("Missing 'status' field", out_error)
	if not (dict["status"] is String) or not (str(dict["status"]) in ["alive", "dead"]):
		return _fail("Invalid 'status' field '%s' (must be 'alive' or 'dead')" % str(dict.get("status")), out_error)

	if not dict.has("name"):
		return _fail("Missing 'name' field", out_error)
	if not (dict["name"] is String):
		return _fail("Invalid 'name' field (expected String)", out_error)

	if not dict.has("appearance"):
		return _fail("Missing 'appearance' field", out_error)
	if not (dict["appearance"] is Dictionary):
		return _fail("Invalid 'appearance' field (expected Dictionary)", out_error)

	if not dict.has("level"):
		return _fail("Missing 'level' field", out_error)
	var lvl_val: Variant = dict["level"]
	if not (lvl_val is int or (lvl_val is float and is_finite(lvl_val) and floor(lvl_val) == lvl_val)):
		return _fail("Invalid 'level' type (expected int)", out_error)
	if int(lvl_val) < 1:
		return _fail("Invalid 'level' value %d (must be >= 1)" % int(lvl_val), out_error)

	if not dict.has("xp"):
		return _fail("Missing 'xp' field", out_error)
	var xp_val: Variant = dict["xp"]
	if not (xp_val is int or (xp_val is float and is_finite(xp_val) and floor(xp_val) == xp_val)):
		return _fail("Invalid 'xp' type (expected int)", out_error)
	if int(xp_val) < 0:
		return _fail("Invalid 'xp' value %d (must be >= 0)" % int(xp_val), out_error)

	if not dict.has("stats"):
		return _fail("Missing 'stats' field", out_error)
	if not (dict["stats"] is Dictionary):
		return _fail("Invalid 'stats' field (expected Dictionary)", out_error)

	var stats_dict: Dictionary = dict["stats"]
	for key in STATS_KEYS:
		if not stats_dict.has(key):
			return _fail("Stats missing required field '%s'" % key, out_error)
		var val: Variant = stats_dict[key]
		if not ((val is int or val is float) and not (val is bool)):
			return _fail("Stats field '%s' must be numeric (got %s)" % [key, typeof(val)], out_error)
		var num_val := float(val)
		if not is_finite(num_val):
			return _fail("Stats field '%s' must be a finite number" % key, out_error)
		if key == "max_hp" or key == "attack_interval":
			if num_val <= 0.0:
				return _fail("Stats field '%s' must be > 0 (got %s)" % [key, str(val)], out_error)
		else:
			if num_val < 0.0:
				return _fail("Stats field '%s' must be >= 0 (got %s)" % [key, str(val)], out_error)

	if not dict.has("zone"):
		return _fail("Missing 'zone' field", out_error)
	if not (dict["zone"] is String):
		return _fail("Invalid 'zone' field (expected String)", out_error)

	if not dict.has("position"):
		return _fail("Missing 'position' field", out_error)
	if not (dict["position"] is Array) or dict["position"].size() != 2:
		return _fail("Invalid 'position' field (expected Array of 2 coordinates)", out_error)
	var px: Variant = dict["position"][0]
	var py: Variant = dict["position"][1]
	if not (((px is int or px is float) and not (px is bool)) and is_finite(float(px)) and ((py is int or py is float) and not (py is bool)) and is_finite(float(py))):
		return _fail("Invalid 'position' coordinates (must be finite numbers)", out_error)

	var cs := CharacterState.new()
	cs.version = int(ver_val)
	cs.id = str(dict["id"])
	cs.status = str(dict["status"])
	cs.name = str(dict["name"])
	cs.appearance = (dict["appearance"] as Dictionary).duplicate(true)
	cs.level = int(lvl_val)
	cs.xp = int(xp_val)
	cs.stats = Stats.from_dict(stats_dict)
	cs.zone = str(dict["zone"])
	cs.position = [float(px), float(py)]

	return cs


func equals(other: CharacterState) -> bool:
	if other == null:
		return false
	if version != other.version or id != other.id or status != other.status or name != other.name:
		return false
	if appearance != other.appearance or level != other.level or xp != other.xp or zone != other.zone:
		return false
	if position != other.position:
		return false
	if (stats == null) != (other.stats == null):
		return false
	if stats != null and stats.to_dict() != other.stats.to_dict():
		return false
	return true


static func _fail(msg: String, out_error: Array = []) -> CharacterState:
	last_error = msg
	if out_error != null and out_error is Array:
		out_error.append(msg)
	return null
