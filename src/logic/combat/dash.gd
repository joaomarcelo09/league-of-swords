class_name DashRules
extends RefCounted


static func validate_params(params: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if params.is_empty():
		errors.append("missing or invalid 'dash' parameters (empty dictionary)")
		return errors

	if not params.has("distance_tiles") or not (params["distance_tiles"] is int or params["distance_tiles"] is float) or not is_finite(float(params["distance_tiles"])) or float(params["distance_tiles"]) <= 0.0:
		errors.append("missing or invalid 'distance_tiles' (must be number > 0.0)")

	if not params.has("duration_s") or not (params["duration_s"] is int or params["duration_s"] is float) or not is_finite(float(params["duration_s"])) or float(params["duration_s"]) <= 0.0:
		errors.append("missing or invalid 'duration_s' (must be number > 0.0)")

	if not params.has("cooldown_s") or not (params["cooldown_s"] is int or params["cooldown_s"] is float) or not is_finite(float(params["cooldown_s"])) or float(params["cooldown_s"]) < 0.0:
		errors.append("missing or invalid 'cooldown_s' (must be number >= 0.0)")

	return errors


static func compute_end_position(from: Vector2, aim: Vector2, distance: float, zone: Zone) -> Vector2:
	if zone == null or distance <= 0.0 or aim.is_zero_approx():
		return from

	var from_tile := Vector2i(int(floor(from.x)), int(floor(from.y)))
	if not zone.is_walkable(from_tile):
		return from

	var dir := aim.normalized()
	var current_pos := from
	var remaining := distance
	var max_step := 0.5

	while remaining > 1e-9:
		var step := minf(max_step, remaining)
		var next_pos := current_pos + dir * step
		var next_tile := Vector2i(int(floor(next_pos.x)), int(floor(next_pos.y)))
		if not zone.is_walkable(next_tile):
			break
		current_pos = next_pos
		remaining -= step

	return current_pos


static func compute_end_pos(from: Vector2, aim: Vector2, distance: float, zone: Zone) -> Vector2:
	return compute_end_position(from, aim, distance, zone)
