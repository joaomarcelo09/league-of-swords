class_name DeathScreen
extends CanvasLayer

signal new_character_requested(name: String)

const DEFAULT_PANEL_WIDTH: float = 340.0
const DEFAULT_PANEL_HEIGHT: float = 380.0

var root_control: Control = null
var overlay: ColorRect = null
var panel: PanelContainer = null

var name_label: Label = null
var level_label: Label = null
var zone_label: Label = null
var cause_label: Label = null
var date_label: Label = null

var name_input: LineEdit = null
var start_button: Button = null
var error_label: Label = null

var cemetery_entry: Dictionary = {}

var _ui_built: bool = false


func _init() -> void:
	layer = 20
	visible = false
	_build_ui()


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	if _ui_built:
		return
	_ui_built = true

	root_control = Control.new()
	root_control.name = "DeathScreenRoot"
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_control.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root_control)

	overlay = ColorRect.new()
	overlay.name = "Overlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.04, 0.04, 0.06, 0.82)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	root_control.add_child(overlay)

	panel = PanelContainer.new()
	panel.name = "DeathPanel"
	panel.custom_minimum_size = Vector2(DEFAULT_PANEL_WIDTH, DEFAULT_PANEL_HEIGHT)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.96)
	style.border_color = Color(0.7, 0.2, 0.22, 0.95)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 16.0
	style.content_margin_top = 16.0
	style.content_margin_right = 16.0
	style.content_margin_bottom = 16.0
	panel.add_theme_stylebox_override("panel", style)
	root_control.add_child(panel)

	var main_vbox := VBoxContainer.new()
	main_vbox.name = "MainVBox"
	main_vbox.add_theme_constant_override("separation", 8)
	panel.add_child(main_vbox)

	var title_lbl := Label.new()
	title_lbl.name = "TitleLabel"
	title_lbl.text = "FALLEN"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 20)
	title_lbl.add_theme_color_override("font_color", Color(0.95, 0.25, 0.25, 1.0))
	main_vbox.add_child(title_lbl)

	var sub_lbl := Label.new()
	sub_lbl.name = "SubtitleLabel"
	sub_lbl.text = "Cemetery Record"
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.add_theme_font_size_override("font_size", 11)
	sub_lbl.add_theme_color_override("font_color", Color(0.65, 0.7, 0.75, 0.8))
	main_vbox.add_child(sub_lbl)

	var sep1 := HSeparator.new()
	main_vbox.add_child(sep1)

	var info_vbox := VBoxContainer.new()
	info_vbox.name = "InfoVBox"
	info_vbox.add_theme_constant_override("separation", 4)
	main_vbox.add_child(info_vbox)

	name_label = _create_info_row(info_vbox, "Name:", "NameLabel")
	level_label = _create_info_row(info_vbox, "Level:", "LevelLabel")
	zone_label = _create_info_row(info_vbox, "Zone:", "ZoneLabel")
	cause_label = _create_info_row(info_vbox, "Cause:", "CauseLabel")
	date_label = _create_info_row(info_vbox, "Date:", "DateLabel")

	var sep2 := HSeparator.new()
	main_vbox.add_child(sep2)

	var prompt_lbl := Label.new()
	prompt_lbl.name = "PromptLabel"
	prompt_lbl.text = "New Character Name:"
	prompt_lbl.add_theme_font_size_override("font_size", 12)
	prompt_lbl.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95, 1.0))
	main_vbox.add_child(prompt_lbl)

	name_input = LineEdit.new()
	name_input.name = "NameInput"
	name_input.placeholder_text = "Enter character name..."
	name_input.add_theme_font_size_override("font_size", 12)
	name_input.text_submitted.connect(func(_t: String) -> void: _on_start_pressed())
	main_vbox.add_child(name_input)

	start_button = Button.new()
	start_button.name = "StartButton"
	start_button.text = "Start"
	start_button.custom_minimum_size = Vector2(0, 32)
	start_button.pressed.connect(_on_start_pressed)
	main_vbox.add_child(start_button)

	error_label = Label.new()
	error_label.name = "ErrorLabel"
	error_label.text = ""
	error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error_label.add_theme_font_size_override("font_size", 11)
	error_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35, 1.0))
	error_label.visible = false
	main_vbox.add_child(error_label)


func _create_info_row(parent: VBoxContainer, label_text: String, value_name: String) -> Label:
	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var prefix := Label.new()
	prefix.text = label_text
	prefix.custom_minimum_size = Vector2(70, 0)
	prefix.add_theme_font_size_override("font_size", 12)
	prefix.add_theme_color_override("font_color", Color(0.6, 0.65, 0.72, 1.0))
	hbox.add_child(prefix)

	var val_lbl := Label.new()
	val_lbl.name = value_name
	val_lbl.text = ""
	val_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val_lbl.add_theme_font_size_override("font_size", 12)
	val_lbl.add_theme_color_override("font_color", Color(0.92, 0.94, 0.98, 1.0))
	hbox.add_child(val_lbl)

	parent.add_child(hbox)
	return val_lbl


func show_death(entry: Dictionary) -> void:
	_build_ui()
	cemetery_entry = entry.duplicate(true)

	if name_label != null:
		name_label.text = str(entry.get("name", ""))
	if level_label != null:
		level_label.text = str(entry.get("level", 1))
	if zone_label != null:
		zone_label.text = str(entry.get("zone", ""))
	if cause_label != null:
		cause_label.text = str(entry.get("cause", ""))
	if date_label != null:
		date_label.text = str(entry.get("date", ""))

	if name_input != null:
		name_input.text = ""
		if is_inside_tree() and DisplayServer.get_name() != "headless":
			name_input.grab_focus()

	clear_error()
	visible = true


func close() -> void:
	visible = false
	clear_error()


func is_open() -> bool:
	return visible


func show_error(message: String) -> void:
	_build_ui()
	if error_label != null:
		error_label.text = message
		error_label.visible = true


func clear_error() -> void:
	if error_label != null:
		error_label.text = ""
		error_label.visible = false


func _on_start_pressed() -> void:
	clear_error()
	var raw_text := name_input.text if name_input != null else ""
	var trimmed := raw_text.strip_edges()
	if trimmed.is_empty():
		show_error("Character name cannot be empty")
		return

	new_character_requested.emit(trimmed)
