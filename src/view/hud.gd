class_name HUD
extends CanvasLayer

const DEFAULT_HP_BAR_WIDTH: float = 240.0
const DEFAULT_HP_BAR_HEIGHT: float = 22.0
const DEFAULT_HP_BG_COLOR := Color(0.12, 0.12, 0.15, 0.85)
const DEFAULT_HP_FILL_COLOR := Color(0.18, 0.75, 0.32, 1.0)
const DEFAULT_HP_BORDER_COLOR := Color(0.05, 0.05, 0.08, 0.95)

const DEFAULT_SLOT_SIZE: float = 48.0
const DEFAULT_SLOT_GAP: float = 8.0
const DEFAULT_SLOT_BG_COLOR := Color(0.12, 0.14, 0.18, 0.9)
const DEFAULT_SLOT_BORDER_COLOR := Color(0.28, 0.35, 0.45, 0.95)
const DEFAULT_SWEEP_COLOR := Color(0.05, 0.05, 0.08, 0.75)

const DEFAULT_INVENTORY_WIDTH: float = 260.0
const DEFAULT_INVENTORY_HEIGHT: float = 320.0
const DEFAULT_PICKUP_RADIUS: float = 1.2
const DEFAULT_CLICK_RADIUS: float = 24.0

const EQUIPPED_MARKER: String = "[E]"


# --- Inner Classes for HUD Components ---

class HPBarComponent extends Control:
	var bar_width: float = DEFAULT_HP_BAR_WIDTH
	var bar_height: float = DEFAULT_HP_BAR_HEIGHT
	var bg_color: Color = DEFAULT_HP_BG_COLOR
	var fill_color: Color = DEFAULT_HP_FILL_COLOR
	var border_color: Color = DEFAULT_HP_BORDER_COLOR
	var ratio: float = 1.0
	var label: Label = null

	func _init() -> void:
		custom_minimum_size = Vector2(bar_width, bar_height)
		size = custom_minimum_size

		label = Label.new()
		label.name = "HPLabel"
		label.position = Vector2.ZERO
		label.size = custom_minimum_size
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
		label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
		add_child(label)

	func update_dimensions(p_w: float, p_h: float) -> void:
		bar_width = p_w
		bar_height = p_h
		custom_minimum_size = Vector2(bar_width, bar_height)
		size = custom_minimum_size
		if label != null:
			label.size = custom_minimum_size
		queue_redraw()

	func set_hp(current_hp: float, max_hp: float) -> void:
		ratio = HUD.hp_fraction(current_hp, max_hp)
		var text := HUD.format_hp_text(current_hp, max_hp)
		if label != null:
			label.text = text
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(0.0, 0.0, bar_width, bar_height)
		draw_rect(r, bg_color)
		var fill_w := bar_width * ratio
		if fill_w > 0.0:
			draw_rect(Rect2(0.0, 0.0, fill_w, bar_height), fill_color)
		draw_rect(r, border_color, false, 2.0)


class SkillSlotComponent extends Control:
	var slot_key: String = ""
	var slot_size: float = DEFAULT_SLOT_SIZE
	var bg_color: Color = DEFAULT_SLOT_BG_COLOR
	var border_color: Color = DEFAULT_SLOT_BORDER_COLOR
	var sweep_color: Color = DEFAULT_SWEEP_COLOR
	var cd_fraction: float = 0.0
	var remaining_s: float = 0.0
	var key_label: Label = null
	var cd_label: Label = null

	func _init(p_slot_key: String, p_size: float = DEFAULT_SLOT_SIZE) -> void:
		slot_key = p_slot_key
		slot_size = p_size
		custom_minimum_size = Vector2(slot_size, slot_size)
		size = custom_minimum_size

		key_label = Label.new()
		key_label.name = "KeyLabel"
		key_label.text = slot_key
		key_label.position = Vector2(4.0, 2.0)
		key_label.size = Vector2(slot_size - 8.0, 16.0)
		key_label.add_theme_font_size_override("font_size", 12)
		key_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.95))
		key_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
		key_label.add_theme_constant_override("shadow_offset_x", 1)
		key_label.add_theme_constant_override("shadow_offset_y", 1)
		add_child(key_label)

		cd_label = Label.new()
		cd_label.name = "CDLabel"
		cd_label.text = ""
		cd_label.position = Vector2(0.0, (slot_size - 20.0) / 2.0)
		cd_label.size = Vector2(slot_size, 20.0)
		cd_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cd_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cd_label.add_theme_font_size_override("font_size", 14)
		cd_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.3, 1.0))
		cd_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
		cd_label.add_theme_constant_override("shadow_offset_x", 1)
		cd_label.add_theme_constant_override("shadow_offset_y", 1)
		cd_label.visible = false
		add_child(cd_label)

	func update_size(p_size: float) -> void:
		slot_size = p_size
		custom_minimum_size = Vector2(slot_size, slot_size)
		size = custom_minimum_size
		if key_label != null:
			key_label.size = Vector2(slot_size - 8.0, 16.0)
		if cd_label != null:
			cd_label.position = Vector2(0.0, (slot_size - 20.0) / 2.0)
			cd_label.size = Vector2(slot_size, 20.0)
		queue_redraw()

	func set_cooldown(fraction: float, p_remaining_s: float) -> void:
		cd_fraction = clampf(fraction, 0.0, 1.0)
		remaining_s = maxf(0.0, p_remaining_s)
		var text := HUD.cooldown_remaining_text(remaining_s)
		if cd_label != null:
			cd_label.text = text
			cd_label.visible = cd_fraction > 0.0 and not text.is_empty()
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(0.0, 0.0, slot_size, slot_size)
		draw_rect(r, bg_color)
		if cd_fraction > 0.0:
			var sweep_h := slot_size * cd_fraction
			var sweep_r := Rect2(0.0, 0.0, slot_size, sweep_h)
			draw_rect(sweep_r, sweep_color)
		draw_rect(r, border_color, false, 2.0)


# --- HUD Member Variables ---

var session: GameSession = null
var world: WorldSim = null
var player: Entity = null
var inventory: Inventory = null
var item_db: ItemDB = null
var registry: DataRegistry = null
var entities_root: Node2D = null
var zone_view: ZoneView = null

var loot_pickup_radius: float = DEFAULT_PICKUP_RADIUS
var loot_click_radius: float = DEFAULT_CLICK_RADIUS
var loot_markers: Dictionary = {} # uid -> LootDropView

# UI Containers
var root_control: Control = null
var bottom_hud: VBoxContainer = null
var hp_bar_comp: HPBarComponent = null
var slots_container: HBoxContainer = null
var slot_components: Dictionary = {} # "Q", "W", "R", "E" -> SkillSlotComponent

var inventory_panel: PanelContainer = null
var inventory_items_vbox: VBoxContainer = null
var inventory_empty_label: Label = null


# --- Lifecycle & Setup ---

func _ready() -> void:
	layer = 10
	_ensure_ui_tree()


func setup(
	p_session: GameSession,
	p_world: WorldSim = null,
	p_player: Entity = null,
	p_inventory: Inventory = null,
	p_item_db: ItemDB = null,
	p_registry: DataRegistry = null,
	p_entities_root: Node2D = null,
	p_zone_view: ZoneView = null
) -> void:
	session = p_session
	world = p_world if p_world != null else (p_session.world if p_session != null else null)
	player = p_player if p_player != null else (p_session.player if p_session != null else null)
	inventory = p_inventory if p_inventory != null else (p_session.inventory if p_session != null else null)
	item_db = p_item_db if p_item_db != null else (p_session.item_db if p_session != null else null)
	registry = p_registry if p_registry != null else (p_session.registry if p_session != null else null)
	entities_root = p_entities_root
	zone_view = p_zone_view

	_apply_registry_balance()
	_ensure_ui_tree()
	update_view()


func _apply_registry_balance() -> void:
	if registry == null:
		return

	var radius_val: Variant = registry.get_balance("view.loot_pickup_radius")
	if radius_val != null and float(radius_val) > 0.0:
		loot_pickup_radius = float(radius_val)


func _ensure_ui_tree() -> void:
	if root_control != null:
		return

	root_control = Control.new()
	root_control.name = "HUDControl"
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root_control)

	_build_bottom_hud()
	_build_inventory_panel()


func _build_bottom_hud() -> void:
	bottom_hud = VBoxContainer.new()
	bottom_hud.name = "BottomHUD"
	bottom_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_hud.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_hud.add_theme_constant_override("separation", 6)

	var vp_width := 1280.0
	var vp_height := 720.0
	if get_viewport() != null:
		var vp_rect := get_viewport().get_visible_rect()
		if vp_rect.size.x > 0.0:
			vp_width = vp_rect.size.x
			vp_height = vp_rect.size.y

	var hp_w := DEFAULT_HP_BAR_WIDTH
	var hp_h := DEFAULT_HP_BAR_HEIGHT
	var slot_sz := DEFAULT_SLOT_SIZE
	var slot_g := DEFAULT_SLOT_GAP

	if registry != null:
		var w_val: Variant = registry.get_balance("view.hud_hp_bar_width")
		if w_val != null and float(w_val) > 0.0:
			hp_w = float(w_val)
		var h_val: Variant = registry.get_balance("view.hud_hp_bar_height")
		if h_val != null and float(h_val) > 0.0:
			hp_h = float(h_val)
		var sz_val: Variant = registry.get_balance("view.hud_slot_size")
		if sz_val != null and float(sz_val) > 0.0:
			slot_sz = float(sz_val)
		var g_val: Variant = registry.get_balance("view.hud_slot_gap")
		if g_val != null and float(g_val) >= 0.0:
			slot_g = float(g_val)

	hp_bar_comp = HPBarComponent.new()
	hp_bar_comp.name = "HPBar"
	hp_bar_comp.update_dimensions(hp_w, hp_h)
	if registry != null:
		var bg_val: Variant = registry.get_balance("view.hud_hp_bar_bg_color")
		if bg_val != null:
			hp_bar_comp.bg_color = parse_color(bg_val, DEFAULT_HP_BG_COLOR)
		var fill_val: Variant = registry.get_balance("view.hud_hp_bar_fill_color")
		if fill_val != null:
			hp_bar_comp.fill_color = parse_color(fill_val, DEFAULT_HP_FILL_COLOR)
		var border_val: Variant = registry.get_balance("view.hud_hp_bar_border_color")
		if border_val != null:
			hp_bar_comp.border_color = parse_color(border_val, DEFAULT_HP_BORDER_COLOR)

	var hp_bar_container := CenterContainer.new()
	hp_bar_container.name = "HPCenter"
	hp_bar_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_bar_container.add_child(hp_bar_comp)
	bottom_hud.add_child(hp_bar_container)

	slots_container = HBoxContainer.new()
	slots_container.name = "SkillSlots"
	slots_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slots_container.alignment = BoxContainer.ALIGNMENT_CENTER
	slots_container.add_theme_constant_override("separation", int(slot_g))

	var slot_keys := ["Q", "W", "R", "E"]
	for k: String in slot_keys:
		var slot_comp := SkillSlotComponent.new(k, slot_sz)
		slot_comp.name = "Slot_" + k
		if registry != null:
			var sbg_val: Variant = registry.get_balance("view.hud_slot_bg_color")
			if sbg_val != null:
				slot_comp.bg_color = parse_color(sbg_val, DEFAULT_SLOT_BG_COLOR)
			var sbord_val: Variant = registry.get_balance("view.hud_slot_border_color")
			if sbord_val != null:
				slot_comp.border_color = parse_color(sbord_val, DEFAULT_SLOT_BORDER_COLOR)
			var swp_val: Variant = registry.get_balance("view.hud_cooldown_sweep_color")
			if swp_val != null:
				slot_comp.sweep_color = parse_color(swp_val, DEFAULT_SWEEP_COLOR)
		slots_container.add_child(slot_comp)
		slot_components[k] = slot_comp

	bottom_hud.add_child(slots_container)

	var total_w := maxf(hp_w, float(slot_keys.size()) * slot_sz + float(slot_keys.size() - 1) * slot_g)
	var total_h := hp_h + 6.0 + slot_sz
	bottom_hud.position = Vector2((vp_width - total_w) / 2.0, vp_height - total_h - 16.0)
	bottom_hud.size = Vector2(total_w, total_h)

	root_control.add_child(bottom_hud)


func _build_inventory_panel() -> void:
	var inv_w := DEFAULT_INVENTORY_WIDTH
	var inv_h := DEFAULT_INVENTORY_HEIGHT
	if registry != null:
		var w_val: Variant = registry.get_balance("view.hud_inventory_width")
		if w_val != null and float(w_val) > 0.0:
			inv_w = float(w_val)
		var h_val: Variant = registry.get_balance("view.hud_inventory_height")
		if h_val != null and float(h_val) > 0.0:
			inv_h = float(h_val)

	inventory_panel = PanelContainer.new()
	inventory_panel.name = "InventoryPanel"
	inventory_panel.custom_minimum_size = Vector2(inv_w, inv_h)
	inventory_panel.size = Vector2(inv_w, inv_h)

	var vp_width := 1280.0
	if get_viewport() != null:
		var vp_rect := get_viewport().get_visible_rect()
		if vp_rect.size.x > 0.0:
			vp_width = vp_rect.size.x
	inventory_panel.position = Vector2(vp_width - inv_w - 20.0, 80.0)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.12, 0.16, 0.92)
	style.border_color = Color(0.3, 0.38, 0.5, 0.95)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 8.0
	style.content_margin_top = 8.0
	style.content_margin_right = 8.0
	style.content_margin_bottom = 8.0
	inventory_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.name = "MainVBox"
	vbox.add_theme_constant_override("separation", 6)
	inventory_panel.add_child(vbox)

	# Header HBox
	var header := HBoxContainer.new()
	header.name = "Header"

	var title_lbl := Label.new()
	title_lbl.name = "TitleLabel"
	title_lbl.text = "INVENTORY (I)"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.add_theme_font_size_override("font_size", 13)
	title_lbl.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0, 1.0))
	header.add_child(title_lbl)

	var close_btn := Button.new()
	close_btn.name = "CloseButton"
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(24.0, 24.0)
	close_btn.pressed.connect(close_inventory)
	header.add_child(close_btn)
	vbox.add_child(header)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Scroll area for items
	var scroll := ScrollContainer.new()
	scroll.name = "ItemScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	inventory_items_vbox = VBoxContainer.new()
	inventory_items_vbox.name = "ItemList"
	inventory_items_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_items_vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(inventory_items_vbox)
	vbox.add_child(scroll)

	inventory_empty_label = Label.new()
	inventory_empty_label.name = "EmptyLabel"
	inventory_empty_label.text = "(empty)"
	inventory_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inventory_empty_label.add_theme_font_size_override("font_size", 11)
	inventory_empty_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7, 0.8))
	inventory_items_vbox.add_child(inventory_empty_label)

	inventory_panel.visible = false
	root_control.add_child(inventory_panel)


# --- Input Handling ---

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory") or (event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_I):
		toggle_inventory()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var mouse_pos: Vector2 = Vector2.ZERO
		if zone_view != null and zone_view.is_inside_tree():
			mouse_pos = zone_view.get_local_mouse_position()
		elif entities_root != null and entities_root.is_inside_tree():
			mouse_pos = entities_root.get_local_mouse_position()

		if _try_pickup_at_world_pos(mouse_pos):
			get_viewport().set_input_as_handled()
			return


func _try_pickup_at_world_pos(world_pos: Vector2) -> bool:
	if loot_markers.is_empty():
		return false

	var best_uid := -1
	var best_dist := loot_click_radius
	for uid_val: Variant in loot_markers.keys():
		var uid: int = int(uid_val)
		var marker: LootDropView = loot_markers[uid]
		if marker != null and is_instance_valid(marker):
			var d := marker.position.distance_to(world_pos)
			if d <= best_dist:
				best_dist = d
				best_uid = uid

	if best_uid != -1:
		return pickup_loot_item(best_uid)
	return false


# --- Process & View Updates ---

func _process(_delta: float) -> void:
	update_view()


func update_view() -> void:
	_update_hp_bar()
	_update_skill_slots()
	_check_loot_proximity()


func _update_hp_bar() -> void:
	if hp_bar_comp == null:
		return

	var current_hp: float = 0.0
	var max_hp: float = 100.0

	if player != null:
		current_hp = player.hp
		if player.stats != null and player.stats.max_hp > 0.0:
			max_hp = player.stats.max_hp
		elif registry != null:
			var val: Variant = registry.get_balance("player.max_hp")
			if val != null and float(val) > 0.0:
				max_hp = float(val)
	elif registry != null:
		var val: Variant = registry.get_balance("player.max_hp")
		if val != null and float(val) > 0.0:
			max_hp = float(val)
			current_hp = max_hp

	hp_bar_comp.set_hp(current_hp, max_hp)


func _update_skill_slots() -> void:
	if slot_components.is_empty() or world == null or player == null:
		return

	var now_tick := float(world.tick_count)
	var tick_len := world.tick_length
	var tick_hz := 30.0
	if tick_len > 0.0:
		tick_hz = 1.0 / tick_len

	# Q, W, R slots
	for slot_key: String in ["Q", "W", "R"]:
		var comp: SkillSlotComponent = slot_components.get(slot_key, null)
		if comp == null:
			continue

		var skill_id: String = player.skills.get(slot_key, "")
		var cd_s := 0.0
		if registry != null and not skill_id.is_empty():
			var entry := registry.get_entry("skills", skill_id)
			if entry.has("cooldown_s"):
				cd_s = float(entry["cooldown_s"])

		var total_ticks := cd_s * tick_hz
		var ready_tick: float = player.skill_ready_ticks.get(slot_key, 0.0)
		var fraction := cooldown_fraction(ready_tick, now_tick, total_ticks)
		var rem_s := cooldown_remaining_seconds(ready_tick, now_tick, tick_len)
		comp.set_cooldown(fraction, rem_s)

	# E slot (Dash)
	var dash_comp: SkillSlotComponent = slot_components.get("E", null)
	if dash_comp != null:
		var dash_cd_s := 6.0
		if registry != null:
			var dval: Variant = registry.get_balance("dash.cooldown_s")
			if dval != null and float(dval) >= 0.0:
				dash_cd_s = float(dval)

		var total_ticks := dash_cd_s * tick_hz
		var ready_tick := player.dash_ready_tick
		var fraction := cooldown_fraction(ready_tick, now_tick, total_ticks)
		var rem_s := cooldown_remaining_seconds(ready_tick, now_tick, tick_len)
		dash_comp.set_cooldown(fraction, rem_s)


func _check_loot_proximity() -> void:
	if player == null or player.dead or inventory == null or loot_markers.is_empty():
		return

	var player_pos := player.pos
	var to_pickup: Array[int] = []

	for uid_val: Variant in loot_markers.keys():
		var uid := int(uid_val)
		var marker: LootDropView = loot_markers[uid]
		if marker != null and is_instance_valid(marker):
			if is_in_pickup_range(player_pos, marker.tile, loot_pickup_radius):
				to_pickup.append(uid)

	for uid: int in to_pickup:
		pickup_loot_item(uid)


# --- Event Handling & Loot Markers ---

func handle_event(event: Dictionary) -> void:
	var event_type: String = str(event.get("type", ""))
	if event_type == "loot_drop":
		spawn_loot_drop(event)


func spawn_loot_drop(event: Dictionary) -> Array[LootDropView]:
	var items: Array = event.get("items", [])
	var tile: Vector2i = event.get("tile", Vector2i.ZERO)
	var spawned: Array[LootDropView] = []

	var base_pos := Vector2.ZERO
	if zone_view != null:
		base_pos = zone_view.tile_to_world(tile)
	else:
		base_pos = ZoneView.tile_to_world_coords(tile)

	var count := items.size()
	for i in range(count):
		var uid: int = int(items[i])
		var def_id := ""
		if inventory != null:
			def_id = inventory.def_id_of(uid)

		var item_name := def_id
		if item_db != null and not def_id.is_empty():
			var item_def := item_db.get_item(def_id)
			if item_def.has("name"):
				item_name = str(item_def["name"])
		if item_name.is_empty():
			item_name = "Item"

		var world_pos := base_pos
		if count > 1:
			world_pos.x += (float(i) - float(count - 1) * 0.5) * 16.0

		var marker := LootDropView.new()
		marker.name = "LootMarker_%d" % uid
		marker.setup(uid, tile, def_id, item_name, world_pos, registry)

		if entities_root != null:
			entities_root.add_child(marker)
		else:
			add_child(marker)

		loot_markers[uid] = marker
		spawned.append(marker)

	return spawned


func pickup_loot_item(uid: int) -> bool:
	if inventory == null or player == null:
		return false

	var success := PlayerInput.pickup_loot(inventory, uid, player.id)
	if success:
		if loot_markers.has(uid):
			var marker: LootDropView = loot_markers[uid]
			loot_markers.erase(uid)
			if marker != null and is_instance_valid(marker):
				marker.queue_free()
		refresh_inventory()
		return true

	return false


func get_loot_markers() -> Dictionary:
	return loot_markers


func get_loot_marker(uid: int) -> LootDropView:
	return loot_markers.get(uid, null)


func clear_loot_markers() -> void:
	for uid_val: Variant in loot_markers.keys():
		var marker: LootDropView = loot_markers[uid_val]
		if marker != null and is_instance_valid(marker):
			marker.queue_free()
	loot_markers.clear()


func reset_loot_markers() -> void:
	clear_loot_markers()


# --- Inventory Operations ---

func toggle_inventory() -> void:
	if inventory_panel == null:
		return
	if inventory_panel.visible:
		close_inventory()
	else:
		open_inventory()


func open_inventory() -> void:
	if inventory_panel == null:
		return
	inventory_panel.visible = true
	refresh_inventory()


func close_inventory() -> void:
	if inventory_panel == null:
		return
	inventory_panel.visible = false


func is_inventory_open() -> bool:
	return inventory_panel != null and inventory_panel.visible


func refresh_inventory() -> void:
	if inventory_items_vbox == null or inventory == null or player == null:
		return

	for child: Node in inventory_items_vbox.get_children():
		child.queue_free()

	var char_owner := "character:%d" % player.id
	var item_uids := inventory.items_of(char_owner)

	if item_uids.is_empty():
		inventory_empty_label = Label.new()
		inventory_empty_label.name = "EmptyLabel"
		inventory_empty_label.text = "(empty)"
		inventory_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		inventory_empty_label.add_theme_font_size_override("font_size", 11)
		inventory_empty_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7, 0.8))
		inventory_items_vbox.add_child(inventory_empty_label)
		return

	for uid: int in item_uids:
		var def_id := inventory.def_id_of(uid)
		var item_name := def_id
		var item_type := ""
		if item_db != null and not def_id.is_empty():
			var item_def := item_db.get_item(def_id)
			if item_def.has("name"):
				item_name = str(item_def["name"])
			if item_def.has("type"):
				item_type = str(item_def["type"])

		var is_equipped := false
		if item_type in ["weapon", "armor"]:
			is_equipped = inventory.get_equipped(char_owner, item_type) == uid

		var row_text := format_inventory_row(item_name, is_equipped)

		var btn := Button.new()
		btn.name = "ItemBtn_%d" % uid
		btn.text = row_text
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0.0, 26.0)
		btn.add_theme_font_size_override("font_size", 11)
		btn.pressed.connect(func() -> void: _on_inventory_item_activated(uid))
		inventory_items_vbox.add_child(btn)


func _on_inventory_item_activated(uid: int) -> void:
	if inventory == null or item_db == null or player == null:
		return
	PlayerInput.activate_inventory_item(inventory, item_db, uid, player)
	refresh_inventory()
	update_view()


# --- Getters for Testing ---

func get_hp_bar() -> Control:
	return hp_bar_comp


func get_skill_slots() -> Dictionary:
	return slot_components


func get_skill_slot(slot: String) -> Control:
	return slot_components.get(slot, null)


func get_inventory_panel() -> Control:
	return inventory_panel


# --- Pure Static Helper Functions ---

static func cooldown_fraction(ready_tick: float, now_tick: float, total_ticks: float) -> float:
	if total_ticks <= 0.0:
		return 0.0
	var remaining := ready_tick - now_tick
	if remaining <= 0.0:
		return 0.0
	return clampf(remaining / total_ticks, 0.0, 1.0)


static func cooldown_remaining_seconds(ready_tick: float, now_tick: float, tick_length: float) -> float:
	if tick_length <= 0.0:
		return 0.0
	var rem_ticks := ready_tick - now_tick
	if rem_ticks <= 0.0:
		return 0.0
	return rem_ticks * tick_length


static func cooldown_remaining_text(remaining_s: float) -> String:
	if remaining_s <= 0.001:
		return ""
	return "%.1f" % remaining_s


static func format_cooldown_text(remaining_s: float) -> String:
	return cooldown_remaining_text(remaining_s)


static func format_hp_text(hp: float, max_hp: float) -> String:
	var cur_val := int(round(maxf(0.0, hp)))
	var max_val := int(round(maxf(1.0, max_hp)))
	return "%d/%d" % [cur_val, max_val]


static func hp_fraction(hp: float, max_hp: float) -> float:
	if max_hp <= 0.0:
		return 0.0
	return clampf(hp / max_hp, 0.0, 1.0)


static func format_inventory_row(item_name: String, is_equipped: bool) -> String:
	if is_equipped:
		return "%s %s" % [item_name, EQUIPPED_MARKER]
	return item_name


static func build_inventory_row(uid: int, item_name: String, is_equipped: bool) -> Dictionary:
	return {
		"uid": uid,
		"name": item_name,
		"equipped": is_equipped,
		"text": format_inventory_row(item_name, is_equipped),
	}


static func build_inventory_row_text(item_name: String, is_equipped: bool) -> String:
	return format_inventory_row(item_name, is_equipped)


static func is_in_pickup_range(player_pos: Vector2, loot_tile: Vector2i, radius: float) -> bool:
	var loot_center := Vector2(float(loot_tile.x) + 0.5, float(loot_tile.y) + 0.5)
	return player_pos.distance_to(loot_center) <= radius


static func can_pickup_loot(player_pos: Vector2, loot_tile: Vector2i, radius: float) -> bool:
	return is_in_pickup_range(player_pos, loot_tile, radius)


static func parse_color(val: Variant, fallback: Color) -> Color:
	if val is Color:
		return val
	if val is Array:
		var arr: Array = val
		if arr.size() >= 4:
			return Color(float(arr[0]), float(arr[1]), float(arr[2]), float(arr[3]))
		elif arr.size() == 3:
			return Color(float(arr[0]), float(arr[1]), float(arr[2]), 1.0)
	return fallback
