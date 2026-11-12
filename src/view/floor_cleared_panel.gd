class_name FloorClearedPanel
extends PanelContainer
## Centred "Floor N cleared" panel shown on a floor_cleared event. View-only:
## the Continue button only hides it; no gameplay happens here.

const PANEL_WIDTH: float = 380.0
const PANEL_HEIGHT: float = 140.0
const TITLE_FONT_SIZE: int = 20
const BODY_FONT_SIZE: int = 13
const BG_COLOR := Color(0.08, 0.1, 0.14, 0.94)
const BORDER_COLOR := Color(0.75, 0.62, 0.3, 0.95)
const TITLE_COLOR := Color(1.0, 0.88, 0.55, 1.0)
const BODY_COLOR := Color(0.88, 0.92, 1.0, 1.0)

var message_label: Label = null
var continue_button: Button = null


func _init() -> void:
	name = "FloorClearedPanel"
	custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	size = custom_minimum_size

	var style := StyleBoxFlat.new()
	style.bg_color = BG_COLOR
	style.border_color = BORDER_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(14.0)
	add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)
	add_child(vbox)

	message_label = Label.new()
	message_label.name = "MessageLabel"
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	message_label.add_theme_color_override("font_color", TITLE_COLOR)
	message_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	message_label.add_theme_constant_override("shadow_offset_x", 1)
	message_label.add_theme_constant_override("shadow_offset_y", 1)
	vbox.add_child(message_label)

	var btn_center := CenterContainer.new()
	btn_center.name = "ButtonCenter"
	vbox.add_child(btn_center)

	continue_button = Button.new()
	continue_button.name = "ContinueButton"
	continue_button.text = "Continue"
	continue_button.custom_minimum_size = Vector2(120.0, 30.0)
	continue_button.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
	continue_button.add_theme_color_override("font_color", BODY_COLOR)
	continue_button.pressed.connect(dismiss)
	btn_center.add_child(continue_button)

	visible = false


## Centres the panel in a viewport of the given size.
func place_center(viewport_size: Vector2) -> void:
	position = (viewport_size - size) / 2.0


## Shows the panel for a floor_cleared event ({to_zone, label, tile}) on zone p_zone_id.
func show_for_event(event: Dictionary, p_zone_id: String = "") -> void:
	message_label.text = message_for(floor_number_for(event, p_zone_id))
	visible = true


func dismiss() -> void:
	visible = false


func is_shown() -> bool:
	return visible


func get_message() -> String:
	return message_label.text


## Pure: panel text for a cleared floor number (<= 0 = unknown floor).
static func message_for(floor_number: int) -> String:
	if floor_number <= 0:
		return "Floor cleared, more floors coming"
	return "Floor %d cleared, more floors coming" % floor_number


## Pure: the cleared floor number. Uses the current zone id ("floor1" -> 1); falls back to
## the event's "to_zone" minus one ("floor2" -> 1). 0 when neither holds a number.
static func floor_number_for(event: Dictionary, p_zone_id: String = "") -> int:
	var from_zone := trailing_number(p_zone_id)
	if from_zone > 0:
		return from_zone
	var to_zone := trailing_number(str(event.get("to_zone", "")))
	if to_zone > 1:
		return to_zone - 1
	return 0


## Pure: the trailing integer of an id ("floor12" -> 12), 0 if none.
static func trailing_number(id: String) -> int:
	var digits := ""
	var i := id.length() - 1
	while i >= 0 and id[i] >= "0" and id[i] <= "9":
		digits = id[i] + digits
		i -= 1
	return int(digits) if not digits.is_empty() else 0
