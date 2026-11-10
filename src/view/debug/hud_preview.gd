class_name HudPreview
extends RefCounted

static var is_active: bool = false


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
	_prepare(main)


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
