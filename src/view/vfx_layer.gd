class_name VfxLayer
extends Node2D
## Draws short fading skill effects for sim events (skill_cast, heal, dash) using
## data/vfx.json (kind, color, duration_s) and the skill geometry in data/skills.json.
## View only: it reads events and entity state, never changes the sim.

const SKILLS_TABLE: String = "skills"
const VFX_TABLE: String = "vfx"
const KIND_LINE: String = "line"
const KIND_CONE: String = "cone"
const KIND_CIRCLE: String = "circle"
const KIND_TRAIL: String = "trail"
const SUPPORTED_KINDS: Array[String] = [KIND_LINE, KIND_CONE, KIND_CIRCLE, KIND_TRAIL]
const DASH_SLOT: String = "E"
const BALANCE_PREFIX: String = "view.vfx."
## Fallbacks used only when data/balance.json lacks view.vfx.* (keep in sync with it).
const DEFAULTS: Dictionary = {
	"z_index": 5,
	"line_width_ratio": 0.5,
	"line_extend_share": 0.35,
	"cone_segments": 16,
	"ring_start_scale": 0.35,
	"ring_width_px": 3.0,
	"fill_alpha_ratio": 0.35,
	"trail_ghost_count": 5,
	"trail_ghost_radius_px": 9.0,
	"trail_ribbon_width_px": 6.0,
	"trail_tail_alpha": 0.3,
}


## One fading effect. Positions are in layer pixels; it frees itself once expired.
class VfxEffect extends Node2D:
	var kind: String = ""
	var color: Color = Color.WHITE
	var duration_s: float = 0.0
	var elapsed: float = 0.0
	## Shape params in pixels: dir (Vector2), length/width/range/angle_deg/radius/to, plus style.
	var params: Dictionary = {}

	func _process(delta: float) -> void:
		if advance(delta):
			queue_free()
		else:
			queue_redraw()

	## Moves the effect forward by `dt` seconds; true once it has fully faded.
	func advance(dt: float) -> bool:
		elapsed += maxf(dt, 0.0)
		return is_expired()

	func is_expired() -> bool:
		return elapsed >= duration_s

	func progress() -> float:
		return VfxLayer.fade_progress(elapsed, duration_s)

	func set_direction(dir: Vector2) -> void:
		if dir.is_zero_approx() or not dir.is_finite():
			return
		params["dir"] = dir.normalized()
		queue_redraw()

	func _draw() -> void:
		var alpha := VfxLayer.fade_alpha(elapsed, duration_s)
		if alpha <= 0.0:
			return
		var c := Color(color.r, color.g, color.b, color.a * alpha)
		match kind:
			VfxLayer.KIND_LINE:
				_draw_line_fx(c)
			VfxLayer.KIND_CONE:
				_draw_cone_fx(c)
			VfxLayer.KIND_CIRCLE:
				_draw_circle_fx(c)
			VfxLayer.KIND_TRAIL:
				_draw_trail_fx(c)

	func _style(key: String) -> float:
		return float(params.get(key, VfxLayer.DEFAULTS.get(key, 0.0)))

	func _draw_line_fx(c: Color) -> void:
		var dir: Vector2 = params.get("dir", Vector2.ZERO)
		if dir.is_zero_approx():
			return
		var extend_share := _style("line_extend_share")
		var grow := 1.0 if extend_share <= 0.0 else clampf(progress() / extend_share, 0.0, 1.0)
		var length := float(params.get("length", 0.0)) * grow
		var half_w := float(params.get("width", 0.0)) * _style("line_width_ratio") * 0.5
		if length <= 0.0 or half_w <= 0.0:
			return
		var perp := Vector2(-dir.y, dir.x) * half_w
		var tip := dir * length
		var poly := PackedVector2Array([perp, tip, -perp])
		draw_colored_polygon(poly, c)
		draw_line(Vector2.ZERO, tip, Color(c.r, c.g, c.b, minf(1.0, c.a * 1.2)), maxf(1.0, half_w * 0.4))

	func _draw_cone_fx(c: Color) -> void:
		var dir: Vector2 = params.get("dir", Vector2.ZERO)
		var radius := float(params.get("range", 0.0))
		var angle := deg_to_rad(float(params.get("angle_deg", 0.0)))
		if dir.is_zero_approx() or radius <= 0.0 or angle <= 0.0:
			return
		var segments := maxi(2, int(_style("cone_segments")))
		var poly := PackedVector2Array([Vector2.ZERO])
		var start := dir.angle() - angle * 0.5
		for i in range(segments + 1):
			var a := start + angle * float(i) / float(segments)
			poly.append(Vector2.from_angle(a) * radius)
		draw_colored_polygon(poly, Color(c.r, c.g, c.b, c.a * _style("fill_alpha_ratio")))
		var edge := PackedVector2Array(poly.slice(1))
		draw_polyline(edge, c, _style("ring_width_px"), true)

	func _draw_circle_fx(c: Color) -> void:
		var radius := float(params.get("radius", 0.0))
		if radius <= 0.0:
			return
		var start_scale := clampf(_style("ring_start_scale"), 0.0, 1.0)
		var r := radius * lerpf(start_scale, 1.0, progress())
		draw_circle(Vector2.ZERO, r, Color(c.r, c.g, c.b, c.a * _style("fill_alpha_ratio")))
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, c, _style("ring_width_px"), true)

	func _draw_trail_fx(c: Color) -> void:
		var to: Vector2 = params.get("to", Vector2.ZERO)
		var count := maxi(1, int(_style("trail_ghost_count")))
		var tail := clampf(_style("trail_tail_alpha"), 0.0, 1.0)
		var ribbon_w := _style("trail_ribbon_width_px")
		if ribbon_w > 0.0 and not to.is_zero_approx():
			draw_line(Vector2.ZERO, to, Color(c.r, c.g, c.b, c.a * tail), ribbon_w, true)
		var ghost_r := _style("trail_ghost_radius_px")
		if ghost_r <= 0.0:
			return
		for i in range(count):
			var t := 1.0 if count == 1 else float(i) / float(count - 1)
			var p := to * t
			var ghost := Color(c.r, c.g, c.b, c.a * lerpf(tail, 1.0, t))
			# Afterimage silhouette: head over a taller body ellipse.
			draw_circle(p + Vector2(0.0, -ghost_r * 1.6), ghost_r * 0.6, ghost)
			draw_set_transform(p, 0.0, Vector2(0.8, 1.4))
			draw_circle(Vector2.ZERO, ghost_r, ghost)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


var world: WorldSim = null
var zone_view: ZoneView = null
var registry: DataRegistry = null
## source entity id -> {"tick", "effect" (line/cone VfxEffect or null), "aimed" (bool),
## "vfx_id", "skill_id"} for this tick's latest cast, so later events can refine it.
var _last_cast: Dictionary = {}


## Creates a VfxLayer under `parent` (the world-space entities root) and sets it up.
static func create(parent: Node, p_world: WorldSim, p_zone_view: ZoneView, p_registry: DataRegistry) -> VfxLayer:
	var layer := VfxLayer.new()
	layer.name = "VfxLayer"
	if parent != null:
		parent.add_child(layer)
	layer.setup(p_world, p_zone_view, p_registry)
	return layer


func setup(p_world: WorldSim, p_zone_view: ZoneView, p_registry: DataRegistry) -> void:
	world = p_world
	zone_view = p_zone_view
	registry = p_registry
	z_index = int(style_value(registry, "z_index"))
	clear()


## Frees every live effect.
func clear() -> void:
	_last_cast.clear()
	for child: Node in get_children():
		child.queue_free()


func get_effects() -> Array[VfxEffect]:
	var out: Array[VfxEffect] = []
	for child: Node in get_children():
		if child is VfxEffect and not child.is_queued_for_deletion():
			out.append(child as VfxEffect)
	return out


# --- pure helpers -------------------------------------------------------------------

## The vfx id of a skill ("" if the skill or its vfx field is unknown).
static func vfx_id_for_skill(p_registry: DataRegistry, skill_id: String) -> String:
	if p_registry == null or skill_id.is_empty():
		return ""
	return str(p_registry.get_entry(SKILLS_TABLE, skill_id).get("vfx", "")).strip_edges()


## A normalised vfx.json entry {kind, color (Color), duration_s} or {} if the id is
## unknown, its kind is not drawable here, or its duration is not positive.
static func vfx_def(p_registry: DataRegistry, vfx_id: String) -> Dictionary:
	if p_registry == null or vfx_id.is_empty() or not p_registry.has_entry(VFX_TABLE, vfx_id):
		return {}
	var entry := p_registry.get_entry(VFX_TABLE, vfx_id)
	var kind := str(entry.get("kind", ""))
	if not SUPPORTED_KINDS.has(kind):
		return {}
	var dur_val: Variant = entry.get("duration_s", 0.0)
	if not (dur_val is float or dur_val is int) or float(dur_val) <= 0.0:
		return {}
	return {
		"kind": kind,
		"color": parse_color(entry.get("color", null), Color.WHITE),
		"duration_s": float(dur_val),
	}


## Geometry of a skill's effect in tiles, from skills.json: line {length, width},
## cone {range, angle_deg}, circle {radius, range}; {} when the numbers are missing.
static func shape_params(p_registry: DataRegistry, skill_id: String, kind: String) -> Dictionary:
	if p_registry == null or skill_id.is_empty():
		return {}
	var skill := p_registry.get_entry(SKILLS_TABLE, skill_id)
	match kind:
		KIND_LINE:
			var length := float(skill.get("range", 0.0))
			var width := float(skill.get("width", 0.0))
			if length > 0.0 and width > 0.0:
				return {"length": length, "width": width}
		KIND_CONE:
			var range_val := float(skill.get("range", 0.0))
			var angle := float(skill.get("angle_deg", 0.0))
			if range_val > 0.0 and angle > 0.0:
				return {"range": range_val, "angle_deg": angle}
		KIND_CIRCLE:
			var radius := float(skill.get("radius", 0.0))
			if radius > 0.0:
				return {"radius": radius, "range": maxf(0.0, float(skill.get("range", 0.0)))}
	return {}


## Alpha multiplier at `elapsed` of `duration`: 1 at start, fading linearly to 0.
static func fade_alpha(elapsed: float, duration: float) -> float:
	if duration <= 0.0:
		return 0.0
	return clampf(1.0 - elapsed / duration, 0.0, 1.0)


## 0..1 share of `duration` that has elapsed.
static func fade_progress(elapsed: float, duration: float) -> float:
	if duration <= 0.0:
		return 1.0
	return clampf(elapsed / duration, 0.0, 1.0)


## view.vfx.<key> from balance.json, else the DEFAULTS fallback.
static func style_value(p_registry: DataRegistry, key: String) -> Variant:
	if p_registry != null:
		var val: Variant = p_registry.get_balance(BALANCE_PREFIX + key)
		if val is float or val is int:
			return val
	return DEFAULTS.get(key, 0.0)


static func parse_color(val: Variant, fallback: Color) -> Color:
	if val is Array and (val as Array).size() >= 3:
		var arr := val as Array
		for c: Variant in arr:
			if not (c is float or c is int):
				return fallback
		var a := float(arr[3]) if arr.size() >= 4 else 1.0
		return Color(float(arr[0]), float(arr[1]), float(arr[2]), a)
	return fallback


# --- spawning -----------------------------------------------------------------------

## Builds (and adds) an effect of `vfx_id` at `origin_px` with pixel `params`; null and
## no node when the vfx id is unknown.
func spawn_effect(vfx_id: String, origin_px: Vector2, p_params: Dictionary) -> VfxEffect:
	var def := vfx_def(registry, vfx_id)
	if def.is_empty():
		return null
	var fx := VfxEffect.new()
	fx.kind = def["kind"]
	fx.color = def["color"]
	fx.duration_s = def["duration_s"]
	fx.position = origin_px
	var style := {}
	for key: String in DEFAULTS.keys():
		style[key] = style_value(registry, key)
	style.merge(p_params, true)
	fx.params = style
	add_child(fx)
	return fx


## Entry point: called for every sim event (main.event_emitted).
func handle_event(ev: Dictionary) -> void:
	match str(ev.get("type", "")):
		"skill_cast":
			_on_skill_cast(ev)
		"damage":
			_on_damage(ev)
		"heal":
			_on_heal(ev)
		"dash":
			_on_dash(ev)


func _tile_px() -> float:
	return float(zone_view.tile_px) if zone_view != null else 1.0


func _to_px(entity_pos: Vector2) -> Vector2:
	return zone_view.entity_to_world(entity_pos) if zone_view != null else entity_pos


func _entity(id: int) -> Entity:
	if world == null:
		return null
	return world.entities.get(id, null) as Entity


func _on_skill_cast(ev: Dictionary) -> void:
	var source_id := int(ev.get("source", -1))
	var caster := _entity(source_id)
	var skill_id := str(ev.get("skill", ""))
	var vfx_id := vfx_id_for_skill(registry, skill_id)
	var def := vfx_def(registry, vfx_id)
	if caster == null or def.is_empty():
		return
	var kind: String = def["kind"]
	var shape := shape_params(registry, skill_id, kind)
	if shape.is_empty():
		return
	var tp := _tile_px()
	var dir := _guess_direction(caster)
	var fx: VfxEffect = null
	match kind:
		KIND_LINE:
			fx = spawn_effect(vfx_id, _to_px(caster.pos), {
				"dir": dir, "length": shape["length"] * tp, "width": shape["width"] * tp})
		KIND_CONE:
			fx = spawn_effect(vfx_id, _to_px(caster.pos), {
				"dir": dir, "range": shape["range"] * tp, "angle_deg": shape["angle_deg"]})
		KIND_CIRCLE:
			var center: Vector2 = caster.pos + dir * float(shape["range"])
			spawn_effect(vfx_id, _to_px(center), {"radius": shape["radius"] * tp})
	_last_cast[source_id] = {
		"tick": int(ev.get("tick", 0)),
		"effect": fx,
		"aimed": false,
		"vfx_id": vfx_id,
		"skill_id": skill_id,
		"kind": kind,
	}


## Damage from a caster in the same tick as its cast points the line/cone at the hit.
func _on_damage(ev: Dictionary) -> void:
	var cast: Dictionary = _last_cast.get(int(ev.get("source", -1)), {})
	if cast.is_empty() or bool(cast["aimed"]) or int(cast["tick"]) != int(ev.get("tick", 0)):
		return
	var fx: VfxEffect = cast["effect"]
	var caster := _entity(int(ev.get("source", -1)))
	var target := _entity(int(ev.get("target", -1)))
	if fx == null or not is_instance_valid(fx) or caster == null or target == null:
		return
	fx.set_direction(target.pos - caster.pos)
	cast["aimed"] = true


## A heal on someone other than the caster gets its own ring at the healed target.
func _on_heal(ev: Dictionary) -> void:
	var source_id := int(ev.get("source", -1))
	var target_id := int(ev.get("target", -1))
	if source_id == target_id:
		return
	var cast: Dictionary = _last_cast.get(source_id, {})
	if cast.is_empty() or str(cast["kind"]) != KIND_CIRCLE or int(cast["tick"]) != int(ev.get("tick", 0)):
		return
	var target := _entity(target_id)
	var shape := shape_params(registry, str(cast["skill_id"]), KIND_CIRCLE)
	if target == null or shape.is_empty():
		return
	spawn_effect(str(cast["vfx_id"]), _to_px(target.pos), {"radius": shape["radius"] * _tile_px()})


func _on_dash(ev: Dictionary) -> void:
	var mover := _entity(int(ev.get("entity", -1)))
	var skills: Dictionary = mover.skills if mover != null else {}
	var skill_id := SkillIcons.skill_id_for_slot(registry, DASH_SLOT, skills)
	var from_v: Variant = ev.get("from", null)
	var to_v: Variant = ev.get("to", null)
	if not (from_v is Vector2) or not (to_v is Vector2):
		return
	var vfx_id := vfx_id_for_skill(registry, skill_id)
	var def := vfx_def(registry, vfx_id)
	if def.is_empty() or str(def["kind"]) != KIND_TRAIL:
		return
	var from_px := _to_px(from_v as Vector2)
	spawn_effect(vfx_id, from_px, {"to": _to_px(to_v as Vector2) - from_px})


## Cast direction (the event carries no aim): nearest living foe of another kind, else
## the caster's locked direction, else down.
func _guess_direction(caster: Entity) -> Vector2:
	var best: Entity = null
	var best_d := INF
	if world != null:
		for e: Entity in world.entities.values():
			if e == null or e.id == caster.id or e.dead or e.kind == caster.kind:
				continue
			var d := caster.pos.distance_squared_to(e.pos)
			if d < best_d and d > 0.0:
				best_d = d
				best = e
	if best != null:
		return (best.pos - caster.pos).normalized()
	if not caster.locked_dir.is_zero_approx():
		return caster.locked_dir.normalized()
	return Vector2.DOWN


## Debug/preview: stops every effect at `ratio` of its life so a screenshot can hold it.
func freeze_at(ratio: float) -> void:
	for fx: VfxEffect in get_effects():
		fx.set_process(false)
		fx.elapsed = fx.duration_s * clampf(ratio, 0.0, 1.0)
		fx.queue_redraw()
