class_name GameCamera
extends Camera2D

## When true, follow() is ignored and the camera stays where pin_to() put it
## (debug screenshots framing a spot away from the player, JGT-80).
var pinned: bool = false

## Offset from view.offset; a hit shake adds to it and always returns exactly to it.
var base_offset: Vector2 = Vector2.ZERO
## Hit shake config from view.hit.shake_* (0 duration/amplitude = shake off), JGT-87.
var shake_duration_s: float = 0.0
var shake_amplitude_px: float = 0.0
var shake_frequency_hz: float = 0.0
var shake_elapsed: float = 0.0
var shaking: bool = false
## Phase of the current shake; bumped per shake so successive shakes differ.
var shake_seed: int = 0

var follow_offset: Vector2:
	get:
		return offset
	set(val):
		base_offset = val
		offset = val if not shaking else val + current_shake_offset()


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
		base_offset = _parse_vector2(offset_val, Vector2.ZERO)
	elif not shaking:
		base_offset = offset
	stop_shake()
	offset = base_offset

	shake_duration_s = maxf(HitFlash.balance_number(registry, "shake_duration_s"), 0.0)
	shake_amplitude_px = maxf(HitFlash.balance_number(registry, "shake_amplitude_px"), 0.0)
	shake_frequency_hz = maxf(HitFlash.balance_number(registry, "shake_frequency_hz"), 0.0)
	set_process(false)


func follow(world_pos: Vector2) -> void:
	if pinned:
		return
	global_position = world_pos
	position = world_pos


func pin_to(world_pos: Vector2) -> void:
	pinned = false
	follow(world_pos)
	pinned = true
	stop_shake()


## Starts (or restarts) a short decaying hit shake. Ignored while pinned or when the
## shake is disabled in balance.json.
func shake() -> void:
	if pinned or shake_duration_s <= 0.0 or shake_amplitude_px <= 0.0:
		return
	shake_seed += 1
	shake_elapsed = 0.0
	shaking = true
	set_process(true)
	offset = base_offset + current_shake_offset()


## Moves the shake forward by `dt` seconds; offset snaps back to base_offset at the end.
func advance_shake(dt: float) -> void:
	if not shaking:
		return
	if pinned:
		stop_shake()
		return
	shake_elapsed += maxf(dt, 0.0)
	if shake_elapsed >= shake_duration_s:
		stop_shake()
	else:
		offset = base_offset + current_shake_offset()


func stop_shake() -> void:
	shaking = false
	shake_elapsed = 0.0
	offset = base_offset
	set_process(false)


func current_shake_offset() -> Vector2:
	if not shaking:
		return Vector2.ZERO
	return shake_offset(shake_elapsed, shake_duration_s, shake_amplitude_px, shake_frequency_hz, shake_seed)


func _process(delta: float) -> void:
	advance_shake(delta)


## Pure: shake offset at `elapsed` of a `duration` shake. Deterministic for a given seed;
## its length never exceeds `amplitude` and it decays (quadratically) to exactly zero.
static func shake_offset(elapsed: float, duration: float, amplitude: float, frequency_hz: float, seed: int) -> Vector2:
	if duration <= 0.0 or amplitude <= 0.0 or elapsed >= duration or elapsed < 0.0:
		return Vector2.ZERO
	var decay := 1.0 - elapsed / duration
	decay *= decay
	# Two incommensurate sines per axis give an irregular but repeatable wobble.
	var phase := float(seed) * 1.618034
	var w := TAU * frequency_hz * elapsed
	var x := sin(w + phase) * 0.6 + sin(w * 2.17 + phase * 3.1) * 0.4
	var y := cos(w * 1.31 + phase * 1.7) * 0.6 + sin(w * 2.71 + phase * 0.7) * 0.4
	return Vector2(x, y).limit_length(1.0) * amplitude * decay


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
