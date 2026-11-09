class_name GameCamera
extends Camera2D

var follow_offset: Vector2:
	get:
		return offset
	set(val):
		offset = val


func _init(registry: DataRegistry = null) -> void:
	enabled = true
	if registry != null:
		setup(registry)


func setup(registry: DataRegistry) -> void:
	if registry == null:
		return

	var zoom_val: Variant = registry.get_balance("view.zoom")
	if zoom_val != null:
		zoom = _parse_vector2(zoom_val, Vector2.ONE)

	var offset_val: Variant = registry.get_balance("view.offset")
	if offset_val != null:
		offset = _parse_vector2(offset_val, Vector2.ZERO)


func follow(world_pos: Vector2) -> void:
	global_position = world_pos
	position = world_pos


static func _parse_vector2(val: Variant, default_val: Vector2 = Vector2.ZERO) -> Vector2:
	if val is Vector2:
		return val
	if val is Array:
		var arr: Array = val
		if arr.size() >= 2:
			return Vector2(float(arr[0]), float(arr[1]))
	if val is float or val is int:
		var s := float(val)
		return Vector2(s, s)
	if val is Dictionary:
		var d: Dictionary = val
		return Vector2(float(d.get("x", default_val.x)), float(d.get("y", default_val.y)))
	return default_val
