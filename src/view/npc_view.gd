class_name NpcView
extends Node2D
## Placeholder drawing of one zone NPC (data from Zone.npcs): a coloured body shape on
## its tile with a name label above. View-only; it never changes logic state.

const BODY_RADIUS: float = 9.0
const HEAD_RADIUS: float = 5.0
const OUTLINE_COLOR := Color(0.08, 0.06, 0.04, 1.0)
const MERCHANT_COLOR := Color(0.85, 0.6, 0.2, 1.0)
const DEFAULT_COLOR := Color(0.55, 0.75, 0.55, 1.0)
const HEAD_COLOR := Color(0.95, 0.82, 0.68, 1.0)
const LABEL_COLOR := Color(1.0, 0.92, 0.6, 1.0)
const LABEL_FONT_SIZE: int = 10
const LABEL_WIDTH: float = 120.0
const LABEL_Y: float = -34.0

var npc_id: String = ""
var kind: String = ""
var display_name: String = ""
var tile: Vector2i = Vector2i.ZERO
var label: Label = null


func _init(npc: Dictionary = {}) -> void:
	npc_id = str(npc.get("id", ""))
	kind = str(npc.get("kind", ""))
	display_name = display_name_for(npc)
	var t: Variant = WorldSim.parse_tile_coord(npc.get("tile"))
	if t != null:
		tile = t
	name = "Npc_%s" % npc_id

	label = Label.new()
	label.name = "NameLabel"
	label.text = display_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(LABEL_WIDTH, 14.0)
	label.position = Vector2(-LABEL_WIDTH / 2.0, LABEL_Y)
	label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	label.add_theme_color_override("font_color", LABEL_COLOR)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(label)


## Places the view on its tile centre using the zone view's pixel size.
func place(p_zone_view: ZoneView) -> void:
	if p_zone_view != null:
		position = p_zone_view.tile_to_world(tile)
	else:
		position = ZoneView.tile_to_world_coords(tile)


func _draw() -> void:
	var body_color := MERCHANT_COLOR if kind == "merchant" else DEFAULT_COLOR
	draw_circle(Vector2(0.0, 2.0), BODY_RADIUS + 1.5, OUTLINE_COLOR)
	draw_circle(Vector2(0.0, 2.0), BODY_RADIUS, body_color)
	draw_circle(Vector2(0.0, -10.0), HEAD_RADIUS + 1.5, OUTLINE_COLOR)
	draw_circle(Vector2(0.0, -10.0), HEAD_RADIUS, HEAD_COLOR)


## Pure: the label text for an NPC entry: its "name", else its id.
static func display_name_for(npc: Dictionary) -> String:
	var n := str(npc.get("name", "")).strip_edges()
	if not n.is_empty():
		return n
	return str(npc.get("id", ""))


## Builds and places one NpcView per NPC of the zone under `parent`.
static func build_all(p_zone: Zone, parent: Node, p_zone_view: ZoneView = null) -> Array[NpcView]:
	var result: Array[NpcView] = []
	if p_zone == null or parent == null:
		return result
	for npc: Dictionary in p_zone.npcs:
		var view := NpcView.new(npc)
		view.place(p_zone_view)
		parent.add_child(view)
		result.append(view)
	return result
