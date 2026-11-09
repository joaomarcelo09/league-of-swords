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


static func is_segment_walkable(p0: Vector2, p1: Vector2, zone: Zone) -> bool:
	if zone == null:
		return false

	var tile0 := Vector2i(int(floor(p0.x)), int(floor(p0.y)))
	if not zone.is_walkable(tile0):
		return false

	var tile1 := Vector2i(int(floor(p1.x)), int(floor(p1.y)))
	if tile0 == tile1:
		return true

	if not zone.is_walkable(tile1):
		return false

	var delta := p1 - p0
	var step_x := 0
	var t_max_x := INF
	var t_delta_x := INF

	if delta.x > 0.0:
		step_x = 1
		t_max_x = (float(tile0.x + 1) - p0.x) / delta.x
		t_delta_x = 1.0 / delta.x
	elif delta.x < 0.0:
		step_x = -1
		t_max_x = (float(tile0.x) - p0.x) / delta.x
		t_delta_x = -1.0 / delta.x

	var step_y := 0
	var t_max_y := INF
	var t_delta_y := INF

	if delta.y > 0.0:
		step_y = 1
		t_max_y = (float(tile0.y + 1) - p0.y) / delta.y
		t_delta_y = 1.0 / delta.y
	elif delta.y < 0.0:
		step_y = -1
		t_max_y = (float(tile0.y) - p0.y) / delta.y
		t_delta_y = -1.0 / delta.y

	var current := tile0
	var max_iterations: int = (absi(tile1.x - tile0.x) + absi(tile1.y - tile0.y) + 2) * 2

	for _iter in range(max_iterations):
		if current == tile1:
			return true

		var diff := t_max_x - t_max_y
		if absf(diff) <= 1e-7:
			var next_tile := Vector2i(current.x + step_x, current.y + step_y)
			var n1 := Vector2i(current.x + step_x, current.y)
			var n2 := Vector2i(current.x, current.y + step_y)
			if not zone.is_walkable(n1) or not zone.is_walkable(n2):
				return false
			if not zone.is_walkable(next_tile):
				return false
			current = next_tile
			t_max_x += t_delta_x
			t_max_y += t_delta_y
		elif t_max_x < t_max_y:
			var next_tile := Vector2i(current.x + step_x, current.y)
			if not zone.is_walkable(next_tile):
				return false
			current = next_tile
			t_max_x += t_delta_x
		else:
			var next_tile := Vector2i(current.x, current.y + step_y)
			if not zone.is_walkable(next_tile):
				return false
			current = next_tile
			t_max_y += t_delta_y

	return zone.is_walkable(tile1)


static func compute_end_position(from: Vector2, aim: Vector2, distance: float, zone: Zone) -> Vector2:
	if zone == null or distance <= 0.0 or aim.is_zero_approx() or not aim.is_finite():
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
		if not is_segment_walkable(current_pos, next_pos, zone):
			break
		current_pos = next_pos
		remaining -= step

	return current_pos


static func compute_end_pos(from: Vector2, aim: Vector2, distance: float, zone: Zone) -> Vector2:
	return compute_end_position(from, aim, distance, zone)
