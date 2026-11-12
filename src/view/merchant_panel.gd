class_name MerchantPanel
extends PanelContainer
## Centred merchant panel: lists the NPC's stock ("merchant:<id>" items) with a Take
## button per row. No currency yet: Take moves the item to the active character via
## Inventory.transfer. Close button or Esc hides it.

signal item_taken(uid: int)
signal closed

const PANEL_WIDTH: float = 360.0
const PANEL_HEIGHT: float = 300.0
const LIST_HEIGHT: float = 190.0
const TITLE_FONT_SIZE: int = 18
const BODY_FONT_SIZE: int = 12
const BG_COLOR := Color(0.08, 0.1, 0.14, 0.95)
const BORDER_COLOR := Color(0.75, 0.62, 0.3, 0.95)
const TITLE_COLOR := Color(1.0, 0.88, 0.55, 1.0)
const BODY_COLOR := Color(0.88, 0.92, 1.0, 1.0)
const EMPTY_COLOR := Color(0.6, 0.65, 0.7, 0.85)
const EMPTY_TEXT: String = "(nothing in stock)"

var inventory: Inventory = null
var item_db: ItemDB = null
var npc: Dictionary = {}
var merchant_id: String = ""
var character_owner: String = ""

var title_label: Label = null
var rows_vbox: VBoxContainer = null
var close_button: Button = null


func _init() -> void:
	name = "MerchantPanel"
	custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	size = custom_minimum_size

	var style := StyleBoxFlat.new()
	style.bg_color = BG_COLOR
	style.border_color = BORDER_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12.0)
	add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 10)
	add_child(vbox)

	title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	title_label.add_theme_color_override("font_color", TITLE_COLOR)
	title_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	title_label.add_theme_constant_override("shadow_offset_x", 1)
	title_label.add_theme_constant_override("shadow_offset_y", 1)
	vbox.add_child(title_label)

	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.custom_minimum_size = Vector2(0.0, LIST_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	rows_vbox = VBoxContainer.new()
	rows_vbox.name = "Rows"
	rows_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows_vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(rows_vbox)

	var btn_center := CenterContainer.new()
	btn_center.name = "ButtonCenter"
	vbox.add_child(btn_center)

	close_button = Button.new()
	close_button.name = "CloseButton"
	close_button.text = "Close"
	close_button.custom_minimum_size = Vector2(110.0, 28.0)
	close_button.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
	close_button.pressed.connect(close)
	btn_center.add_child(close_button)

	visible = false


## Centres the panel in a viewport of the given size.
func place_center(viewport_size: Vector2) -> void:
	position = (viewport_size - size) / 2.0


## Opens the panel for a zone NPC entry; taken items go to `p_character_owner`
## ("character:<id>").
func open_for(p_npc: Dictionary, p_inventory: Inventory, p_item_db: ItemDB, p_character_owner: String) -> void:
	npc = p_npc
	merchant_id = str(p_npc.get("id", ""))
	inventory = p_inventory
	item_db = p_item_db
	character_owner = p_character_owner
	title_label.text = title_for(p_npc)
	refresh()
	visible = true


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func is_shown() -> bool:
	return visible


func get_title() -> String:
	return title_label.text


## Rebuilds one row (name + Take button) per stock item.
func refresh() -> void:
	for child: Node in rows_vbox.get_children():
		rows_vbox.remove_child(child)
		child.queue_free()

	var rows := stock_rows(inventory, item_db, merchant_id)
	if rows.is_empty():
		var empty := Label.new()
		empty.name = "EmptyLabel"
		empty.text = EMPTY_TEXT
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
		empty.add_theme_color_override("font_color", EMPTY_COLOR)
		rows_vbox.add_child(empty)
		return

	for row: Dictionary in rows:
		var uid: int = int(row["uid"])
		var hbox := HBoxContainer.new()
		hbox.name = "Row_%d" % uid
		hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var name_label := Label.new()
		name_label.name = "NameLabel"
		name_label.text = str(row["name"])
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
		name_label.add_theme_color_override("font_color", BODY_COLOR)
		hbox.add_child(name_label)

		var take_btn := Button.new()
		take_btn.name = "TakeButton"
		take_btn.text = "Take"
		take_btn.custom_minimum_size = Vector2(64.0, 24.0)
		take_btn.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
		take_btn.pressed.connect(func() -> void: take(uid))
		hbox.add_child(take_btn)

		rows_vbox.add_child(hbox)


## Number of stock rows currently listed (0 when only the empty label shows).
func row_count() -> int:
	var count := 0
	for child: Node in rows_vbox.get_children():
		if child is HBoxContainer:
			count += 1
	return count


## Take button action: moves `uid` to the character and refreshes the list.
func take(uid: int) -> bool:
	var ok := take_item(inventory, merchant_id, uid, character_owner)
	if ok:
		refresh()
		item_taken.emit(uid)
	return ok


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and not event.echo and (event.physical_keycode == KEY_ESCAPE or event.keycode == KEY_ESCAPE)):
		close()
		if get_viewport() != null:
			get_viewport().set_input_as_handled()


## Pure: the merchant's inventory owner string ("merchant:<id>").
static func merchant_owner(p_merchant_id: String) -> String:
	if p_merchant_id.begins_with("merchant:"):
		return p_merchant_id
	return "merchant:" + p_merchant_id


## Pure: panel title from the NPC entry, e.g. "Smith Orrin - Merchant".
static func title_for(p_npc: Dictionary) -> String:
	var who := NpcView.display_name_for(p_npc)
	var kind := str(p_npc.get("kind", "")).strip_edges()
	if kind.is_empty():
		return who
	return "%s - %s" % [who, kind.capitalize()]


## Pure: [{uid, name}] for each item owned by the merchant, sorted by uid. The name comes
## from the item data, falling back to the def id.
static func stock_rows(p_inventory: Inventory, p_item_db: ItemDB, p_merchant_id: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if p_inventory == null or p_merchant_id.is_empty():
		return rows
	for uid: int in p_inventory.items_of(merchant_owner(p_merchant_id)):
		var def_id := p_inventory.def_id_of(uid)
		var item_name := def_id
		if p_item_db != null and p_item_db.has_item(def_id):
			item_name = str(p_item_db.get_item(def_id).get("name", def_id))
		rows.append({"uid": uid, "name": item_name})
	return rows


## Take logic: moves `uid` from the merchant's stock to `p_character_owner`. False when
## the item is not in that merchant's stock or the recipient is not a character.
static func take_item(p_inventory: Inventory, p_merchant_id: String, uid: int, p_character_owner: String) -> bool:
	if p_inventory == null or p_merchant_id.is_empty():
		return false
	if not p_character_owner.begins_with("character:") or not Inventory.is_valid_owner(p_character_owner):
		return false
	if not p_inventory.items_of(merchant_owner(p_merchant_id)).has(uid):
		return false
	return p_inventory.transfer(uid, p_character_owner)
