class_name SkillSystem
extends RefCounted


static func in_shape(skill: Dictionary, origin: Vector2, dir: Vector2, point: Vector2) -> bool:
	var shape: String = str(skill.get("shape", ""))
	match shape:
		"line":
			var length: float = float(skill.get("range", 0.0))
			var width: float = float(skill.get("width", 0.0))
			if length <= 0.0 or width <= 0.0:
				return false
			if dir.is_zero_approx():
				return false
			var d := dir.normalized()
			var v := point - origin
			var proj := v.dot(d)
			if proj < -1e-6 or proj > length + 1e-6:
				return false
			var perp := Vector2(-d.y, d.x)
			var perp_dist := absf(v.dot(perp))
			return perp_dist <= (width / 2.0) + 1e-6
		"cone":
			var range_val: float = float(skill.get("range", 0.0))
			var angle_deg: float = float(skill.get("angle_deg", 0.0))
			if range_val <= 0.0 or angle_deg <= 0.0:
				return false
			if dir.is_zero_approx():
				return false
			var v := point - origin
			var dist := v.length()
			if dist <= 1e-6:
				return true
			if dist > range_val + 1e-6:
				return false
			var d := dir.normalized()
			var angle_diff := rad_to_deg(absf(d.angle_to(v)))
			return angle_diff <= (angle_deg / 2.0) + 0.001
		"circle":
			var range_val: float = float(skill.get("range", 0.0))
			var radius: float = float(skill.get("radius", 0.0))
			if radius <= 0.0:
				return false
			var center := origin
			if range_val > 0.0:
				var offset := dir
				if offset.length() > range_val:
					offset = offset.normalized() * range_val
				center = origin + offset
			return point.distance_to(center) <= radius + 1e-6
		_:
			return false


static func validate_skill(dict: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not dict.has("name") or not (dict["name"] is String) or str(dict["name"]).strip_edges().is_empty():
		errors.append("missing or invalid 'name' (must be non-empty String)")

	var slot: String = str(dict.get("slot", ""))
	if not slot in ["Q", "W", "R"]:
		errors.append("missing or invalid 'slot' (must be 'Q', 'W', or 'R')")

	if not dict.has("cooldown_s") or not (dict["cooldown_s"] is int or dict["cooldown_s"] is float) or float(dict["cooldown_s"]) < 0.0:
		errors.append("missing or invalid 'cooldown_s' (must be number >= 0.0)")

	if not dict.has("cast_time_s") or not (dict["cast_time_s"] is int or dict["cast_time_s"] is float) or float(dict["cast_time_s"]) < 0.0:
		errors.append("missing or invalid 'cast_time_s' (must be number >= 0.0)")

	var shape: String = str(dict.get("shape", ""))
	if not shape in ["line", "cone", "circle"]:
		errors.append("missing or invalid 'shape' (must be 'line', 'cone', or 'circle')")

	if not dict.has("range") or not (dict["range"] is int or dict["range"] is float) or float(dict["range"]) < 0.0:
		errors.append("missing or invalid 'range' (must be number >= 0.0)")

	match shape:
		"line":
			if not dict.has("width") or not (dict["width"] is int or dict["width"] is float) or float(dict["width"]) <= 0.0:
				errors.append("shape 'line' requires 'width' > 0.0")
		"cone":
			if not dict.has("angle_deg") or not (dict["angle_deg"] is int or dict["angle_deg"] is float) or float(dict["angle_deg"]) <= 0.0 or float(dict["angle_deg"]) > 360.0:
				errors.append("shape 'cone' requires 'angle_deg' > 0.0 and <= 360.0")
		"circle":
			if not dict.has("radius") or not (dict["radius"] is int or dict["radius"] is float) or float(dict["radius"]) <= 0.0:
				errors.append("shape 'circle' requires 'radius' > 0.0")

	if not dict.has("effects") or not (dict["effects"] is Array) or (dict["effects"] as Array).is_empty():
		errors.append("missing or invalid 'effects' (must be non-empty Array)")
	else:
		var effects: Array = dict["effects"]
		for i in range(effects.size()):
			var eff: Variant = effects[i]
			if not (eff is Dictionary):
				errors.append("effect %d must be an object" % i)
				continue
			var eff_dict: Dictionary = eff
			var eff_type: String = str(eff_dict.get("type", ""))
			if not eff_type in ["damage", "heal", "buff"]:
				errors.append("effect %d has invalid 'type' '%s' (must be 'damage', 'heal', or 'buff')" % [i, eff_type])
				continue

			if eff_dict.has("target"):
				var target: String = str(eff_dict["target"])
				if not target in ["hit", "self"]:
					errors.append("effect %d has invalid 'target' '%s' (must be 'hit' or 'self')" % [i, target])

			match eff_type:
				"damage":
					if not eff_dict.has("mult") or not (eff_dict["mult"] is int or eff_dict["mult"] is float) or float(eff_dict["mult"]) < 0.0:
						errors.append("damage effect %d requires 'mult' >= 0.0" % i)
				"heal":
					if not eff_dict.has("amount") or not (eff_dict["amount"] is int or eff_dict["amount"] is float) or float(eff_dict["amount"]) < 0.0:
						errors.append("heal effect %d requires 'amount' >= 0.0" % i)
				"buff":
					if not eff_dict.has("stat") or not (eff_dict["stat"] is String) or str(eff_dict["stat"]).is_empty():
						errors.append("buff effect %d requires non-empty String 'stat'" % i)
					if not eff_dict.has("mult") or not (eff_dict["mult"] is int or eff_dict["mult"] is float) or float(eff_dict["mult"]) < 0.0:
						errors.append("buff effect %d requires 'mult' >= 0.0" % i)
					if not eff_dict.has("duration_s") or not (eff_dict["duration_s"] is int or eff_dict["duration_s"] is float) or float(eff_dict["duration_s"]) <= 0.0:
						errors.append("buff effect %d requires 'duration_s' > 0.0" % i)

	return errors
