class_name LayeredSpritePreview
extends RefCounted

static var is_active: bool = false
static var preview_sprite: LayeredSprite = null


static func check_preview_flag() -> bool:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--preview=layered_sprite" or arg.begins_with("--preview=layered_sprite"):
			return true
	return false


static func setup_if_requested(main: MainView) -> void:
	is_active = false
	preview_sprite = null
	if not check_preview_flag():
		return

	is_active = true
	_prepare(main)


static func _prepare(main: MainView) -> void:
	var sprite := LayeredSprite.new()
	sprite.name = "LayeredSpritePreview"
	sprite.set_appearance({
		"body": "res://assets/characters/placeholder/body.png",
		"clothes": "res://assets/characters/placeholder/clothes.png",
		"armor": "res://assets/characters/placeholder/armor.png",
		"hair": "res://assets/characters/placeholder/hair.png",
		"weapon": "res://assets/characters/placeholder/weapon.png",
	})
	sprite.play("walk", "down")

	var target_pos := Vector2.ZERO
	if main.zone_view != null and main.player != null:
		target_pos = main.zone_view.entity_to_world(main.player.pos)
	elif main.player_marker != null:
		target_pos = main.player_marker.position

	sprite.position = target_pos

	if main.entities_root != null:
		main.entities_root.add_child(sprite)
	else:
		main.add_child(sprite)

	# Hide diamond player marker so the layered sprite character is prominent
	if main.player_marker != null:
		main.player_marker.visible = false

	preview_sprite = sprite
