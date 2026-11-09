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

	if not table.has("roll_count") or not (table["roll_count"] is int or table["roll_count"] is float):
		push_error("Loot.roll: loot table for '%s' missing valid 'roll_count'" % enemy_type_id)
		return drops

	var roll_count_val := float(table["roll_count"])
	if not is_finite(roll_count_val) or roll_count_val < 1.0 or floor(roll_count_val) != roll_count_val:
		push_error("Loot.roll: loot table for '%s' has invalid 'roll_count' %s" % [enemy_type_id, str(table["roll_count"])])
		return drops
	var roll_count := int(roll_count_val)

	if not table.has("entries") or not (table["entries"] is Array):
		push_error("Loot.roll: loot table for '%s' missing 'entries' array" % enemy_type_id)
		return drops

	var entries: Array = table["entries"]
	var ground_owner := zone if zone.begins_with("ground:") else "ground:%s" % zone

	for i in range(roll_count):
		for entry_idx in range(entries.size()):
			var entry_val: Variant = entries[entry_idx]
			if not (entry_val is Dictionary):
				push_error("Loot.roll: loot entry %d is not an object" % entry_idx)
				continue
			var entry: Dictionary = entry_val
			if not entry.has("item_id") or not (entry["item_id"] is String) or str(entry["item_id"]).strip_edges().is_empty():
				push_error("Loot.roll: loot entry %d missing valid 'item_id'" % entry_idx)
				continue
			if not entry.has("chance") or not (entry["chance"] is int or entry["chance"] is float):
				push_error("Loot.roll: loot entry %d missing valid 'chance'" % entry_idx)
				continue
			var item_id := str(entry["item_id"]).strip_edges()
			var chance := float(entry["chance"])
			if not is_finite(chance) or chance <= 0.0 or chance > 1.0:
				push_error("Loot.roll: loot entry %d 'chance' out of range (must be > 0.0 and <= 1.0)" % entry_idx)
				continue

			var roll_val := rng.randf()
			if roll_val < chance:
				var uid := inventory.create(item_id, ground_owner)
				if uid > 0:
					drops.append(uid)

	return drops
