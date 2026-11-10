class_name TitleMenu
extends Control

const DATA_DIR: String = "res://data"
const DEFAULT_SAVE_ROOT: String = "user://saves"
const DEFAULT_SAVE_SLOT: String = "slot_1"
const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"

const DEFAULT_PANEL_WIDTH: float = 380.0
const DEFAULT_PANEL_HEIGHT: float = 400.0

@export var save_root: String = ""
@export var save_slot: String = ""

var registry: DataRegistry = null
var item_db: ItemDB = null
var save_store: SaveStore = null
var slot_summary: Dictionary = {}

var root_control: Control = null
var background: ColorRect = null
var panel: PanelContainer = null
var title_label: Label = null
var subtitle_label: Label = null
var info_label: Label = null
var continue_button: Button = null
var new_world_button: Button = null
var name_container: VBoxContainer = null
var prompt_label: Label = null
var name_input: LineEdit = null
var start_button: Button = null
var error_label: Label = null

var _confirming_new_world: bool = false
var _ui_built: bool = false


func _init() -> void:
	_build_ui()


func _ready() -> void:
	_build_ui()
	setup()
	TitlePreview.setup_if_requested(self)


func setup(p_root: String = "", p_slot: String = "", p_registry: DataRegistry = null) -> void:
	_build_ui()

	if p_registry != null:
		registry = p_registry
	elif registry == null:
		registry = DataRegistry.new()
		registry.load_dir(DATA_DIR)

	item_db = ItemDB.new(registry)

	var resolved_root := p_root if not p_root.is_empty() else save_root
	if resolved_root.is_empty() and registry != null:
		var root_val: Variant = registry.get_balance("save.default_root")
		if root_val != null and not str(root_val).is_empty():
			resolved_root = str(root_val)
	if resolved_root.is_empty():
		resolved_root = DEFAULT_SAVE_ROOT
	save_root = resolved_root

	var resolved_slot := p_slot if not p_slot.is_empty() else save_slot
	if resolved_slot.is_empty() and registry != null:
		var slot_val: Variant = registry.get_balance("save.default_slot")
		if slot_val != null and not str(slot_val).is_empty():
			resolved_slot = str(slot_val)
	if resolved_slot.is_empty():
		resolved_slot = DEFAULT_SAVE_SLOT
	save_slot = resolved_slot

	save_store = SaveStore.new(save_root, item_db)
	refresh()


func refresh() -> void:
	if save_store == null:
		return

	_confirming_new_world = false
	if new_world_button != null:
		new_world_button.text = "New World"

	clear_error()
	slot_summary = SlotSummary.inspect(save_store, save_slot, item_db)

	if not slot_summary.get("has_world", false):
		# Empty slot
		info_label.text = "No saved world found"
		continue_button.disabled = true
		continue_button.tooltip_text = "No save found to continue"
		new_world_button.disabled = false
		new_world_button.tooltip_text = ""
		name_container.visible = false
	elif not slot_summary.get("world_ok", false):
		# Corrupt world
		info_label.text = "Save file is corrupt or unreadable"
		continue_button.disabled = true
		continue_button.tooltip_text = "World file is corrupt"
		new_world_button.disabled = true
		new_world_button.tooltip_text = "Cannot overwrite corrupt world file"
		name_container.visible = false
		show_error(str(slot_summary.get("error", "Failed to load world file")))
	else:
		# Valid world exists
		var living_id: String = str(slot_summary.get("living_character_id", ""))
		if not living_id.is_empty():
			var c_name: String = str(slot_summary.get("living_name", "Hero"))
			var c_lvl: int = int(slot_summary.get("living_level", 1))
			var c_zone: String = str(slot_summary.get("living_zone", "floor1"))
			info_label.text = "%s - Lv.%d - %s" % [c_name, c_lvl, c_zone]
			continue_button.disabled = false
			continue_button.tooltip_text = ""
			new_world_button.disabled = false
			new_world_button.tooltip_text = ""
			name_container.visible = false
		else:
			var dead_count: int = int(slot_summary.get("dead_count", 0))
			if dead_count > 0:
				info_label.text = "No living character (%d fallen)" % dead_count
			else:
				info_label.text = "World exists (no active character)"
			continue_button.disabled = false
			continue_button.tooltip_text = "Create new character in existing world"
			new_world_button.disabled = false
			new_world_button.tooltip_text = ""
			name_container.visible = false


func show_preview_state(char_name: String, level: int, zone_name: String) -> void:
	_build_ui()
	if info_label != null:
		info_label.text = "%s - Lv.%d - %s" % [char_name, level, zone_name]
	if continue_button != null:
		continue_button.disabled = false
		continue_button.tooltip_text = ""
	if new_world_button != null:
		new_world_button.disabled = false
		new_world_button.text = "New World"
	if name_container != null:
		name_container.visible = false
	clear_error()


func show_error(message: String) -> void:
	if error_label != null:
		error_label.text = message
		error_label.visible = true


func clear_error() -> void:
	if error_label != null:
		error_label.text = ""
		error_label.visible = false


func _build_ui() -> void:
	if _ui_built:
		return
	_ui_built = true

	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	background = ColorRect.new()
	background.name = "Background"
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.05, 0.06, 0.09, 1.0)
	add_child(background)

	panel = PanelContainer.new()
	panel.name = "MenuPanel"
	panel.custom_minimum_size = Vector2(DEFAULT_PANEL_WIDTH, DEFAULT_PANEL_HEIGHT)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.11, 0.16, 0.96)
	style.border_color = Color(0.2, 0.5, 0.8, 0.85)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 24.0
	style.content_margin_top = 24.0
	style.content_margin_right = 24.0
	style.content_margin_bottom = 24.0
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.name = "MainVBox"
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.text = "LEAGUE OF SWORDS"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 22)
	title_label.add_theme_color_override("font_color", Color(0.3, 0.75, 1.0, 1.0))
	vbox.add_child(title_label)

	subtitle_label = Label.new()
	subtitle_label.name = "SubtitleLabel"
	subtitle_label.text = "Floor by Floor · Iron & Resolve"
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.add_theme_font_size_override("font_size", 11)
	subtitle_label.add_theme_color_override("font_color", Color(0.65, 0.72, 0.82, 0.85))
	vbox.add_child(subtitle_label)

	var sep1 := HSeparator.new()
	vbox.add_child(sep1)

	info_label = Label.new()
	info_label.name = "InfoLabel"
	info_label.text = "Checking save slot..."
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.add_theme_font_size_override("font_size", 12)
	info_label.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95, 1.0))
	vbox.add_child(info_label)

	var sep2 := HSeparator.new()
	vbox.add_child(sep2)

	continue_button = Button.new()
	continue_button.name = "ContinueButton"
	continue_button.text = "Continue"
	continue_button.custom_minimum_size = Vector2(0, 36)
	continue_button.pressed.connect(_on_continue_pressed)
	vbox.add_child(continue_button)

	new_world_button = Button.new()
	new_world_button.name = "NewWorldButton"
	new_world_button.text = "New World"
	new_world_button.custom_minimum_size = Vector2(0, 36)
	new_world_button.pressed.connect(_on_new_world_pressed)
	vbox.add_child(new_world_button)

	name_container = VBoxContainer.new()
	name_container.name = "NameContainer"
	name_container.add_theme_constant_override("separation", 6)
	name_container.visible = false
	vbox.add_child(name_container)

	var name_sep := HSeparator.new()
	name_container.add_child(name_sep)

	prompt_label = Label.new()
	prompt_label.name = "PromptLabel"
	prompt_label.text = "Enter Character Name:"
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.add_theme_font_size_override("font_size", 12)
	prompt_label.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95, 1.0))
	name_container.add_child(prompt_label)

	name_input = LineEdit.new()
	name_input.name = "NameInput"
	name_input.placeholder_text = "Hero name..."
	name_input.add_theme_font_size_override("font_size", 12)
	name_input.text_submitted.connect(func(_t: String) -> void: _on_start_name_pressed())
	name_container.add_child(name_input)

	start_button = Button.new()
	start_button.name = "StartButton"
	start_button.text = "Start Character"
	start_button.custom_minimum_size = Vector2(0, 32)
	start_button.pressed.connect(_on_start_name_pressed)
	name_container.add_child(start_button)

	error_label = Label.new()
	error_label.name = "ErrorLabel"
	error_label.text = ""
	error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error_label.add_theme_font_size_override("font_size", 11)
	error_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35, 1.0))
	error_label.visible = false
	vbox.add_child(error_label)


func _on_continue_pressed() -> void:
	clear_error()
	_confirming_new_world = false
	if new_world_button != null:
		new_world_button.text = "New World"

	if not slot_summary.get("world_ok", false):
		show_error("Cannot continue: world file is invalid")
		return

	var living_id: String = str(slot_summary.get("living_character_id", ""))
	if not living_id.is_empty():
		LaunchRequest.mode = "continue"
		LaunchRequest.character_id = living_id
		_transition_to_main()
	else:
		# World exists but no living character: show name entry
		name_container.visible = true
		if name_input != null:
			name_input.text = ""
			if is_inside_tree() and DisplayServer.get_name() != "headless":
				name_input.grab_focus()


func _on_start_name_pressed() -> void:
	clear_error()
	var raw_text := name_input.text if name_input != null else ""
	var validation := CharacterNaming.validate_name(raw_text)
	if not validation.get("valid", false):
		show_error(str(validation.get("error", "Invalid character name")))
		return

	var valid_name: String = str(validation.get("value", raw_text))
	var w_res := save_store.load_world(save_slot, item_db)
	if not w_res.get("ok", false):
		show_error(str(w_res.get("error", "Failed to load world state")))
		return

	var world_obj: WorldState = w_res.get("value")
	var create_res := Lifecycle.new_character(
		world_obj,
		valid_name,
		{},
		null,
		save_store,
		save_slot,
		null,
		"floor1",
		registry
	)

	if not create_res.get("ok", false):
		show_error(str(create_res.get("error", "Failed to create character")))
		return

	var char_state: CharacterState = create_res.get("value")
	LaunchRequest.mode = "continue"
	LaunchRequest.character_id = char_state.id
	_transition_to_main()


func _on_new_world_pressed() -> void:
	clear_error()
	if name_container != null:
		name_container.visible = false

	if slot_summary.get("has_world", false) and not slot_summary.get("world_ok", false):
		show_error("Corrupt world file cannot be overwritten")
		return

	var slot_has_data: bool = bool(slot_summary.get("has_world", false)) or save_store.slot_exists(save_slot)

	if slot_has_data:
		if not _confirming_new_world:
			_confirming_new_world = true
			new_world_button.text = "Confirm Overwrite?"
			show_error("Existing world will be wiped. Click 'Confirm Overwrite?' to proceed.")
			return

		# Second click confirms wipe
		_confirming_new_world = false
		var del_res := save_store.delete_slot(save_slot)
		if not del_res.get("ok", false):
			show_error(str(del_res.get("error", "Failed to wipe slot")))
			return

	LaunchRequest.mode = "new"
	LaunchRequest.character_id = ""
	_transition_to_main()


func _transition_to_main() -> void:
	if is_inside_tree() and get_tree() != null:
		get_tree().change_scene_to_file(MAIN_SCENE_PATH)
