extends GutTest

const MAP_PATH := "res://data/zones/floor1/test_arena.map"
const JSON_PATH := "res://data/zones/floor1/test_arena.json"
const DATA_DIR := "res://data"

var _registry: DataRegistry = null
var _zone: Zone = null
var _zone_view: ZoneView = null
var _item_db: ItemDB = null
var _inventory: Inventory = null


func before_each() -> void:
	_registry = DataRegistry.new()
	_registry.load_dir(DATA_DIR)
	_zone = Zone.load_files(MAP_PATH, JSON_PATH)
	_zone_view = ZoneView.new()
	_zone_view.setup(_registry)
	_zone_view.build(_zone)
	autofree(_zone_view)

	_item_db = ItemDB.new(_registry)
	_inventory = Inventory.new(_item_db)


# --- 1. Cooldown Pure Static Functions ---

func test_cooldown_fraction_calculations() -> void:
	# Total 60 ticks, 30 ticks remaining -> 0.5
	var frac := HUD.cooldown_fraction(60.0, 30.0, 60.0)
	assert_almost_eq(frac, 0.5, 0.001, "Remaining 30/60 should be 0.5")

	# Total 90 ticks, 90 ticks remaining -> 1.0
	assert_almost_eq(HUD.cooldown_fraction(90.0, 0.0, 90.0), 1.0, 0.001)

	# Cooldown finished (now >= ready) -> 0.0
	assert_eq(HUD.cooldown_fraction(30.0, 30.0, 60.0), 0.0, "Ready tick reached should return 0.0")
	assert_eq(HUD.cooldown_fraction(30.0, 35.0, 60.0), 0.0, "Past ready tick should return 0.0")

	# Invalid total ticks
	assert_eq(HUD.cooldown_fraction(30.0, 0.0, 0.0), 0.0, "Zero total ticks should return 0.0")
	assert_eq(HUD.cooldown_fraction(30.0, 0.0, -10.0), 0.0, "Negative total ticks should return 0.0")

	# Clamped if remaining exceeds total
	assert_eq(HUD.cooldown_fraction(100.0, 0.0, 50.0), 1.0, "Fraction must clamp to 1.0")


func test_cooldown_remaining_seconds_and_text() -> void:
	var tick_length := 1.0 / 30.0 # 30Hz

	# 45 ticks remaining at 30Hz = 1.5 seconds
	var rem_s := HUD.cooldown_remaining_seconds(45.0, 0.0, tick_length)
	assert_almost_eq(rem_s, 1.5, 0.001)

	var text := HUD.cooldown_remaining_text(rem_s)
	assert_eq(text, "1.5", "1.5s remaining should format to '1.5'")
	assert_eq(HUD.format_cooldown_text(rem_s), "1.5")

	# Cooldown finished (<= 0s) -> empty string
	assert_eq(HUD.cooldown_remaining_text(0.0), "", "0 remaining should return empty string")
	assert_eq(HUD.cooldown_remaining_text(-0.5), "", "Negative remaining should return empty string")

	# Cooldown text visibly counts down with fractional values
	assert_eq(HUD.cooldown_remaining_text(2.36), "2.4")
	assert_eq(HUD.cooldown_remaining_text(0.81), "0.8")


# --- 2. HP Pure Static Functions ---

func test_format_hp_text_and_ratio() -> void:
	assert_eq(HUD.format_hp_text(100.0, 100.0), "100/100")
	assert_eq(HUD.format_hp_text(45.2, 100.0), "45/100")
	assert_eq(HUD.format_hp_text(0.0, 100.0), "0/100")
	assert_eq(HUD.format_hp_text(-5.0, 100.0), "0/100", "Negative HP should clamp to 0")

	assert_almost_eq(HUD.hp_fraction(50.0, 100.0), 0.5, 0.001)
	assert_almost_eq(HUD.hp_fraction(100.0, 100.0), 1.0, 0.001)
	assert_almost_eq(HUD.hp_fraction(0.0, 100.0), 0.0, 0.001)
	assert_almost_eq(HUD.hp_fraction(120.0, 100.0), 1.0, 0.001, "Over max HP clamps to 1.0")
	assert_almost_eq(HUD.hp_fraction(50.0, 0.0), 0.0, 0.001, "Zero max HP returns 0.0")


# --- 3. Inventory Row Building ---

func test_inventory_row_building_and_equipped_marker() -> void:
	var unequipped_row := HUD.format_inventory_row("Iron Sword", false)
	assert_eq(unequipped_row, "Iron Sword")
	assert_false(unequipped_row.contains("[E]"), "Unequipped item should not contain [E]")

	var equipped_row := HUD.format_inventory_row("Iron Sword", true)
	assert_eq(equipped_row, "Iron Sword [E]")
	assert_true(equipped_row.contains("[E]"), "Equipped item must contain [E]")

	var row_dict := HUD.build_inventory_row(101, "Leather Vest", true)
	assert_eq(row_dict["uid"], 101)
	assert_eq(row_dict["name"], "Leather Vest")
	assert_true(row_dict["equipped"])
	assert_eq(row_dict["text"], "Leather Vest [E]")

	var unequipped_dict := HUD.build_inventory_row(102, "Healing Draught", false)
	assert_eq(unequipped_dict["text"], "Healing Draught")
	assert_false(unequipped_dict["equipped"])


# --- 4. Loot Drop Marker Spawn ---

func test_loot_marker_spawn_from_loot_drop_event() -> void:
	var session := GameSession.new(_zone, _registry, _inventory, _item_db)
	var player := session.spawn_player()

	var entities_root := Node2D.new()
	entities_root.name = "Entities"
	autofree(entities_root)

	var hud := HUD.new()
	autofree(hud)
	hud.setup(session, session.world, player, _inventory, _item_db, _registry, entities_root, _zone_view)

	# Create a dropped item on the ground
	var uid := _inventory.create("iron_sword", "ground:floor1")
	assert_gt(uid, 0)

	var drop_event := {
		"type": "loot_drop",
		"tick": 10,
		"entity": 2,
		"items": [uid],
		"tile": Vector2i(5, 7),
	}

	var spawned := hud.spawn_loot_drop(drop_event)
	assert_eq(spawned.size(), 1, "Must spawn exactly 1 marker for 1 item")

	var marker: LootDropView = spawned[0]
	assert_not_null(marker)
	assert_eq(marker.uid, uid)
	assert_eq(marker.tile, Vector2i(5, 7))
	assert_eq(marker.item_name, "Iron Sword")
	assert_eq(marker.get_parent(), entities_root, "Marker must be parented to entities_root")

	var expected_pos := _zone_view.tile_to_world(Vector2i(5, 7))
	assert_eq(marker.position, expected_pos, "Marker world position must match tile center")

	assert_true(hud.get_loot_markers().has(uid), "HUD must track marker by uid")
	assert_eq(hud.get_loot_marker(uid), marker)


# --- 5. Loot Pickup Removes Marker and Moves Item to Owner ---

func test_loot_pickup_removes_marker_and_moves_item_to_owner() -> void:
	var session := GameSession.new(_zone, _registry, _inventory, _item_db)
	var player := session.spawn_player()
	var char_owner := "character:%d" % player.id

	var entities_root := Node2D.new()
	autofree(entities_root)

	var hud := HUD.new()
	autofree(hud)
	hud.setup(session, session.world, player, _inventory, _item_db, _registry, entities_root, _zone_view)

	var uid := _inventory.create("healing_draught", "ground:floor1")
	assert_eq(_inventory.owner_of(uid), "ground:floor1")

	hud.spawn_loot_drop({
		"type": "loot_drop",
		"tick": 1,
		"entity": 0,
		"items": [uid],
		"tile": Vector2i(4, 4),
	})

	assert_true(hud.get_loot_markers().has(uid))
	var marker := hud.get_loot_marker(uid)

	# Perform pickup via HUD
	var picked_up := hud.pickup_loot_item(uid)
	assert_true(picked_up, "pickup_loot_item must succeed")

	# Item moved to player
	assert_eq(_inventory.owner_of(uid), char_owner, "Item owner must now be player")
	assert_has(_inventory.items_of(char_owner), uid, "Player items must contain picked up uid")

	# Marker removed and queued for deletion
	assert_false(hud.get_loot_markers().has(uid), "Marker must be removed from HUD tracking")
	assert_true(marker.is_queued_for_deletion(), "Marker must be queued for deletion")


# --- 6. Proximity Pickup ---

func test_proximity_pickup_when_player_walks_within_radius() -> void:
	var session := GameSession.new(_zone, _registry, _inventory, _item_db)
	var player := session.spawn_player()
	var char_owner := "character:%d" % player.id

	var entities_root := Node2D.new()
	autofree(entities_root)

	var hud := HUD.new()
	autofree(hud)
	hud.setup(session, session.world, player, _inventory, _item_db, _registry, entities_root, _zone_view)

	# Spawn loot at player's current tile (zone entry [3, 2])
	var player_tile := player.tile()
	var uid := _inventory.create("iron_plate", "ground:floor1")
	hud.spawn_loot_drop({
		"type": "loot_drop",
		"tick": 1,
		"entity": 0,
		"items": [uid],
		"tile": player_tile,
	})

	assert_true(hud.get_loot_markers().has(uid))

	# Proximity check in update_view picks it up
	hud.update_view()

	assert_eq(_inventory.owner_of(uid), char_owner, "Item must be picked up automatically by proximity")
	assert_false(hud.get_loot_markers().has(uid), "Marker must be removed after proximity pickup")


# --- 7. Inventory UI Toggle and Equip/Use Interaction ---

func test_inventory_toggle_and_item_equip() -> void:
	var session := GameSession.new(_zone, _registry, _inventory, _item_db)
	var player := session.spawn_player()
	var char_owner := "character:%d" % player.id

	var hud := HUD.new()
	autofree(hud)
	hud.setup(session, session.world, player, _inventory, _item_db, _registry)

	assert_false(hud.is_inventory_open(), "Inventory should start closed")

	hud.toggle_inventory()
	assert_true(hud.is_inventory_open(), "Inventory should open after toggle")

	# Add sword to player inventory and refresh
	var sword_uid := _inventory.create("iron_sword", char_owner)
	hud.refresh_inventory()

	# Equip via thin input function
	var equip_ok := PlayerInput.equip_item(_inventory, player.id, sword_uid)
	assert_true(equip_ok)
	assert_eq(_inventory.get_equipped(char_owner, "weapon"), sword_uid)

	hud.refresh_inventory()

	hud.toggle_inventory()
	assert_false(hud.is_inventory_open(), "Inventory should close after second toggle")


func test_consumable_use_heals_player_and_consumes_item() -> void:
	var session := GameSession.new(_zone, _registry, _inventory, _item_db)
	var player := session.spawn_player()
	var char_owner := "character:%d" % player.id

	# Damage player
	player.hp = 50.0

	var hud := HUD.new()
	autofree(hud)
	hud.setup(session, session.world, player, _inventory, _item_db, _registry)

	var potion_uid := _inventory.create("healing_draught", char_owner)
	assert_has(_inventory.items_of(char_owner), potion_uid)

	# Activate item (healing draught heals 30 HP)
	var activated := PlayerInput.activate_inventory_item(_inventory, _item_db, potion_uid, player)
	assert_true(activated, "Consumable activation should succeed")

	assert_almost_eq(player.hp, 80.0, 0.001, "Player HP should increase from 50 to 80")
	assert_eq(_inventory.owner_of(potion_uid), "consumed", "Item should be marked consumed")
	assert_does_not_have(_inventory.items_of(char_owner), potion_uid, "Consumed item should no longer be in inventory")

	hud.refresh_inventory()
	hud.update_view()

	# HP bar should now show 80/100
	var hp_bar := hud.get_hp_bar() as HUD.HPBarComponent
	assert_eq(hp_bar.label.text, "80/100")


func test_click_pickup_at_world_pos() -> void:
	var session := GameSession.new(_zone, _registry, _inventory, _item_db)
	var player := session.spawn_player()
	var char_owner := "character:%d" % player.id

	var entities_root := Node2D.new()
	autofree(entities_root)

	var hud := HUD.new()
	autofree(hud)
	hud.setup(session, session.world, player, _inventory, _item_db, _registry, entities_root, _zone_view)

	var tile := Vector2i(4, 3)
	var uid := _inventory.create("iron_sword", "ground:floor1")
	hud.spawn_loot_drop({
		"type": "loot_drop",
		"tick": 1,
		"entity": 0,
		"items": [uid],
		"tile": tile,
	})

	var world_pos := _zone_view.tile_to_world(tile)
	# Click directly on marker world position
	var handled := hud._try_pickup_at_world_pos(world_pos)
	assert_true(handled, "Click on loot marker position should pick up item")

	assert_eq(_inventory.owner_of(uid), char_owner)
	assert_false(hud.get_loot_markers().has(uid))


func test_unequip_item_when_already_equipped() -> void:
	var session := GameSession.new(_zone, _registry, _inventory, _item_db)
	var player := session.spawn_player()
	var char_owner := "character:%d" % player.id

	var sword_uid := _inventory.create("iron_sword", char_owner)
	# Equip
	var ok1 := PlayerInput.activate_inventory_item(_inventory, _item_db, sword_uid, player)
	assert_true(ok1)
	assert_eq(_inventory.get_equipped(char_owner, "weapon"), sword_uid)

	# Activate again -> unequips
	var ok2 := PlayerInput.activate_inventory_item(_inventory, _item_db, sword_uid, player)
	assert_true(ok2)
	assert_eq(_inventory.get_equipped(char_owner, "weapon"), 0, "Activating equipped weapon should unequip it")


func test_skill_slots_cooldown_updates() -> void:
	var session := GameSession.new(_zone, _registry, _inventory, _item_db)
	var player := session.spawn_player()

	var hud := HUD.new()
	autofree(hud)
	hud.setup(session, session.world, player, _inventory, _item_db, _registry)

	var slots := hud.get_skill_slots()
	assert_eq(slots.size(), 4, "HUD must have 4 skill slots (Q, W, R, E)")
	assert_has(slots, "Q")
	assert_has(slots, "W")
	assert_has(slots, "R")
	assert_has(slots, "E")

	# Put Q on cooldown: 30 ticks remaining (1.0s at 30Hz)
	player.skill_ready_ticks["Q"] = float(session.world.tick_count) + 30.0
	hud.update_view()

	var q_slot: HUD.SkillSlotComponent = slots["Q"]
	assert_gt(q_slot.cd_fraction, 0.0, "Q slot cooldown fraction should be > 0")
	assert_eq(q_slot.cd_label.text, "1.0", "Q slot remaining text should display 1.0")
	assert_true(q_slot.cd_label.visible, "Q slot CD label must be visible on cooldown")

	# Step world past cooldown
	for _i in range(35):
		session.step(session.world.tick_length)
	hud.update_view()

	assert_eq(q_slot.cd_fraction, 0.0, "Cooldown fraction should return to 0 after ready")
	assert_false(q_slot.cd_label.visible, "CD label should be hidden when ready")
