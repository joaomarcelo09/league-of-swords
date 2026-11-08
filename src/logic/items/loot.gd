class_name Loot
extends RefCounted


static func roll(
	enemy_type_id: String,
	zone: String,
	inventory: Inventory,
	rng: RandomNumberGenerator,
	p_item_db: ItemDB = null
) -> Array[int]:
	var drops: Array[int] = []

	if inventory == null:
		push_error("Loot.roll: inventory is null")
		return drops

	if rng == null:
		push_error("Loot.roll: rng is null")
		return drops

	if enemy_type_id.strip_edges().is_empty():
		push_error("Loot.roll: enemy_type_id is empty")
		return drops

	if zone.strip_edges().is_empty():
		push_error("Loot.roll: zone is empty")
		return drops

	var db: ItemDB = p_item_db if p_item_db != null else inventory.item_db
	if db == null:
		push_error("Loot.roll: item_db is null")
		return drops

	if not db.has_loot_table(enemy_type_id):
		push_error("Loot.roll: unknown enemy type '%s' in loot tables" % enemy_type_id)
		return drops

	var table := db.get_loot_table(enemy_type_id)
	if table.is_empty():
		return drops

	var roll_count := int(table.get("roll_count", table.get("rolls", 1)))
	var entries: Array = table.get("entries", [])
	var ground_owner := zone if zone.begins_with("ground:") else "ground:%s" % zone

	for i in range(roll_count):
		for entry_val: Variant in entries:
			if not (entry_val is Dictionary):
				continue
			var entry: Dictionary = entry_val
			var item_id := str(entry.get("item_id", ""))
			var chance := float(entry.get("chance", 0.0))
			if item_id.is_empty() or chance <= 0.0:
				continue
			var roll_val := rng.randf()
			if roll_val < chance:
				var uid := inventory.create(item_id, ground_owner)
				if uid > 0:
					drops.append(uid)

	return drops
