class_name HudPreview
extends RefCounted

static var is_active: bool = false

## Variants: --preview=hud (default), --preview=hud_boss (boss bar),
## --preview=hud_floor_cleared (floor-cleared panel).
const VARIANT_DEFAULT: String = "hud"
const VARIANT_BOSS: String = "hud_boss"
const VARIANT_FLOOR_CLEARED: String = "hud_floor_cleared"
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
