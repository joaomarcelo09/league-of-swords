class_name HitFlash
extends Node
## Short bright flash on a CanvasItem (its `modulate`) when the entity it draws is hit.
## Shader-free: modulate is pushed toward view.hit.flash_tint (values > 1 brighten) and
## fades back to the target's own modulate over view.hit.flash_duration_s.
## View only: triggered from damage events, never touches the sim.

const BALANCE_PREFIX: String = "view.hit."

var target: CanvasItem = null
var duration_s: float = 0.0
var tint: Color = Color.WHITE
var elapsed: float = 0.0
var active: bool = false
## The target's modulate before the flash; restored exactly when the flash ends.
var base_modulate: Color = Color.WHITE


## Creates a HitFlash under `parent` that tints `p_target`, configured from balance.json.
static func attach(parent: Node, p_target: CanvasItem, p_registry: DataRegistry) -> HitFlash:
	var flash := HitFlash.new()
	flash.name = "HitFlash"
	flash.target = p_target
	flash.duration_s = maxf(balance_number(p_registry, "flash_duration_s"), 0.0)
	flash.tint = balance_color(p_registry, "flash_tint", Color.WHITE)
	flash.set_process(false)
	if parent != null:
		# Internal child: invisible to get_children()/get_child_count() of the owner.
		parent.add_child(flash, false, Node.INTERNAL_MODE_BACK)
	return flash


## Pure: flash strength at `elapsed` seconds of a `duration` flash: 1 at the hit,
## fading linearly to exactly 0 at the end (0 for a non-positive duration).
static func flash_strength(p_elapsed: float, duration: float) -> float:
	if duration <= 0.0:
		return 0.0
	return clampf(1.0 - p_elapsed / duration, 0.0, 1.0)


## Pure: the modulate for `strength` between `base` (0) and base * `p_tint` (1).
static func flash_modulate(base: Color, p_tint: Color, strength: float) -> Color:
	var k := clampf(strength, 0.0, 1.0)
	var mul := Color(1.0, 1.0, 1.0, 1.0).lerp(Color(p_tint.r, p_tint.g, p_tint.b, 1.0), k)
	return Color(base.r * mul.r, base.g * mul.g, base.b * mul.b, base.a)


## view.hit.<key> as a float (0 when missing or not a number: the effect is off).
static func balance_number(p_registry: DataRegistry, key: String) -> float:
	if p_registry == null:
		return 0.0
	var val: Variant = p_registry.get_balance(BALANCE_PREFIX + key)
	if val is float or val is int:
		return float(val)
	return 0.0


## view.hit.<key> as a Color ([r, g, b(, a)]), else `fallback`.
static func balance_color(p_registry: DataRegistry, key: String, fallback: Color) -> Color:
	if p_registry == null:
		return fallback
	return VfxLayer.parse_color(p_registry.get_balance(BALANCE_PREFIX + key), fallback)


func strength() -> float:
	return flash_strength(elapsed, duration_s) if active else 0.0


## Starts (or restarts) the flash. No-op when the flash is disabled or has no target.
func trigger() -> void:
	if duration_s <= 0.0 or target == null or not is_instance_valid(target):
		return
	if not active:
		base_modulate = target.modulate
	elapsed = 0.0
	active = true
	set_process(true)
	_apply()


## Moves the flash forward by `dt` seconds; restores the base modulate when it ends.
func advance(dt: float) -> void:
	if not active:
		return
	elapsed += maxf(dt, 0.0)
	if elapsed >= duration_s:
		stop()
	else:
		_apply()


## Ends the flash at once and puts the target's modulate back exactly.
func stop() -> void:
	if active and target != null and is_instance_valid(target):
		target.modulate = base_modulate
	active = false
	elapsed = 0.0
	set_process(false)


func _process(delta: float) -> void:
	advance(delta)


func _apply() -> void:
	if target == null or not is_instance_valid(target):
		active = false
		set_process(false)
		return
	target.modulate = flash_modulate(base_modulate, tint, strength())
