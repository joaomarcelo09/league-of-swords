class_name HudPreview
extends RefCounted

static var is_active: bool = false

## Variants: --preview=hud (default), --preview=hud_boss (boss bar),
## --preview=hud_floor_cleared (floor-cleared panel), --preview=hud_merchant (merchant panel),
## --preview=hud_cooldowns (all four skill slots, with icons, mid-cooldown),
## --preview=hud_cast_failed (at frame CAST_FAIL_FRAME a cast_failed on Q and a dash_failed
## on E; from then on the fail feedback advances CAST_FAIL_FRAME_DT per frame, so
## tools/screenshot.sh --frames=N is repeatable: before, mid-flash, after the fade).
const VARIANT_DEFAULT: String = "hud"
const VARIANT_BOSS: String = "hud_boss"
const VARIANT_FLOOR_CLEARED: String = "hud_floor_cleared"
const VARIANT_MERCHANT: String = "hud_merchant"
const VARIANT_COOLDOWNS: String = "hud_cooldowns"
const VARIANT_CAST_FAILED: String = "hud_cast_failed"
const CAST_FAIL_FRAME: int = 20
const CAST_FAIL_FRAME_DT: float = 1.0 / 60.0
const CAST_FAIL_Q_REASON: String = "cooldown"
const CAST_FAIL_E_REASON: String = "invalid_aim"
## Share of each slot's full cooldown still remaining in the hud_cooldowns preview.
const COOLDOWN_PREVIEW_RATIOS: Dictionary = {"Q": 0.8, "W": 0.6, "R": 0.4, "E": 0.25}
const MERCHANT_NPC_ID: String = "floor1_smith"
const MERCHANT_PREVIEW_STOCK: Array[String] = ["iron_sword", "iron_plate", "healing_draught"]
const BOSS_TYPE_ID: String = "thornback_warden"
const BOSS_PREVIEW_HP_RATIO: float = 0.62


static func preview_variant() -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--preview="):
			return arg.substr("--preview=".length())
	return ""


static func check_preview_flag() -> bool:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--preview=hud" or arg.begins_with("--preview=hud"):
			return true
	return false


static func setup_if_requested(main: MainView) -> void:
	is_active = false
	if not check_preview_flag():
		return

	is_active = true
	match preview_variant():
		VARIANT_BOSS:
			_prepare_boss(main)
		VARIANT_FLOOR_CLEARED:
			_prepare_floor_cleared(main)
		VARIANT_MERCHANT:
			_prepare_merchant(main)
		VARIANT_COOLDOWNS:
			_prepare_cooldowns(main)
		VARIANT_CAST_FAILED:
			_prepare_cast_failed(main)
		_:
			_prepare(main)


## Aggroes the zone's boss (or spawns one beside the player) at partial HP.
static func _prepare_boss(main: MainView) -> void:
	var world := main.world
	var player := main.player
	if world == null or player == null:
		return
	var boss: Entity = null
	for key: Variant in world.entities.keys():
		var e: Entity = world.entities[key]
		if e != null and e.is_boss and not e.dead:
			boss = e
			break
	if boss == null:
		boss = world.spawn_enemy(BOSS_TYPE_ID, Vector2i(int(player.pos.x) + 2, int(player.pos.y)))
		if boss == null:
			return
		boss.is_boss = true
	else:
		# Bring the boss next to the player so the scaled sprite is in frame too.
		boss.pos = player.pos + Vector2(2.0, 0.0)
	boss.target_id = player.id
	if boss.stats != null:
		boss.hp = boss.stats.max_hp * BOSS_PREVIEW_HP_RATIO


static func _prepare_floor_cleared(main: MainView) -> void:
	if main.hud == null:
		return
	main.hud.handle_event({
		"type": "floor_cleared",
		"tick": main.world.tick_count if main.world != null else 0,
		"to_zone": "floor2",
		"label": "Stairs to Floor 2",
		"tile": Vector2i.ZERO,
	})


## Stocks the floor 1 merchant, stands the player beside it and opens its panel.
static func _prepare_merchant(main: MainView) -> void:
	var world := main.world
	var player := main.player
	var inventory := main.inventory
	if world == null or player == null or inventory == null or main.hud == null:
		return
	var npc := world.get_npc(MERCHANT_NPC_ID)
	if npc.is_empty():
		return
	for def_id: String in MERCHANT_PREVIEW_STOCK:
		inventory.create(def_id, MerchantPanel.merchant_owner(MERCHANT_NPC_ID))
	player.pos = WorldSim.npc_center(npc) + Vector2(-1.0, 0.0)
	main.hud.open_merchant(MERCHANT_NPC_ID)


static func _prepare(main: MainView) -> void:
	var world := main.world
	var player := main.player
	var inventory := main.inventory
	var item_db := main.item_db
	var hud := main.hud
	if player == null or world == null or inventory == null or item_db == null:
		return

	# Put Q skill on cooldown so it shows cooldown sweep and remaining text (2.0s = 60 ticks)
	player.skill_ready_ticks["Q"] = float(world.tick_count) + 60.0

	# Give player an equipped sword and a potion
	var player_owner := "character:%d" % player.id
	var sword_uid := inventory.create("iron_sword", player_owner)
	if sword_uid > 0:
		inventory.equip(player_owner, sword_uid)
	inventory.create("healing_draught", player_owner)

	# Open inventory window to showcase it in the preview
	if hud != null:
		hud.open_inventory()

	# Spawn a sample loot drop near the player
	var loot_uid := inventory.create("iron_plate", "ground:floor1")
	if loot_uid > 0 and hud != null:
		var drop_event := {
			"type": "loot_drop",
			"tick": world.tick_count,
			"entity": 0,
			"items": [loot_uid],
			"tile": Vector2i(int(player.pos.x) + 1, int(player.pos.y)),
		}
		hud.spawn_loot_drop(drop_event)


## Puts Q/W/R (data cooldown_s) and E (balance dash.cooldown_s) part-way through their
## cooldowns so every slot shows its icon under the sweep and the seconds text.
static func _prepare_cooldowns(main: MainView) -> void:
	var world := main.world
	var player := main.player
	var registry := main.registry
	if world == null or player == null or registry == null or world.tick_length <= 0.0:
		return
	var tick_hz := 1.0 / world.tick_length
	var now := float(world.tick_count)
	for slot_key: String in ["Q", "W", "R"]:
		var skill_id := SkillIcons.skill_id_for_slot(registry, slot_key, player.skills)
		var cd_s := float(registry.get_entry("skills", skill_id).get("cooldown_s", 0.0))
		player.skill_ready_ticks[slot_key] = now + cd_s * tick_hz * float(COOLDOWN_PREVIEW_RATIOS[slot_key])
	var dash_cd_s := float(registry.get_balance("dash.cooldown_s", 0.0))
	player.dash_ready_tick = now + dash_cd_s * tick_hz * float(COOLDOWN_PREVIEW_RATIOS["E"])
	if main.hud != null:
		main.hud.update_view()


## Fires the preview's fail events at CAST_FAIL_FRAME, then steps the slots' feedback.
class CastFailDriver extends Node:
	var main: MainView = null
	var frame: int = 0

	func _process(_delta: float) -> void:
		frame += 1
		if main == null or main.hud == null:
			return
		if frame == HudPreview.CAST_FAIL_FRAME:
			HudPreview.fire_cast_failed(main)
		elif frame > HudPreview.CAST_FAIL_FRAME:
			for comp: HUD.SkillSlotComponent in main.hud.get_skill_slots().values():
				comp.advance_fail(HudPreview.CAST_FAIL_FRAME_DT)
		# The preview owns the clock: keep the slots' real-time fade off.
		for comp: HUD.SkillSlotComponent in main.hud.get_skill_slots().values():
			comp.set_process(false)


static func _prepare_cast_failed(main: MainView) -> void:
	var driver := CastFailDriver.new()
	driver.name = "HudCastFailedPreview"
	driver.main = main
	main.add_child(driver)


## A player cast_failed on Q (Q put on cooldown to match) and a dash_failed on E.
static func fire_cast_failed(main: MainView) -> void:
	var world := main.world
	var player := main.player
	if world == null or player == null or main.hud == null:
		return
	if world.tick_length > 0.0 and main.registry != null:
		var skill_id := SkillIcons.skill_id_for_slot(main.registry, "Q", player.skills)
		var cd_s := float(main.registry.get_entry("skills", skill_id).get("cooldown_s", 0.0))
		player.skill_ready_ticks["Q"] = float(world.tick_count) + cd_s / world.tick_length * float(COOLDOWN_PREVIEW_RATIOS["Q"])
	main.hud.handle_event({"type": "cast_failed", "tick": world.tick_count, "source": player.id, "slot": "Q", "reason": CAST_FAIL_Q_REASON})
	main.hud.handle_event({"type": "dash_failed", "tick": world.tick_count, "source": player.id, "reason": CAST_FAIL_E_REASON})
	main.hud.update_view()
