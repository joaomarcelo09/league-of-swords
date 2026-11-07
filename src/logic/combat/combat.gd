class_name Combat
extends RefCounted


static func compute_damage(attacker_stats: Stats, target_stats: Stats, registry: DataRegistry) -> float:
	var min_damage: float = 0.0
	var atk_scale: float = 1.0
	var def_scale: float = 1.0

	if registry != null:
		var val_min: Variant = registry.get_balance("combat.min_damage")
		if val_min != null:
			min_damage = float(val_min)
		var val_atk: Variant = registry.get_balance("combat.atk_scale")
		if val_atk != null:
			atk_scale = float(val_atk)
		var val_def: Variant = registry.get_balance("combat.def_scale")
		if val_def != null:
			def_scale = float(val_def)

	var atk: float = attacker_stats.atk if attacker_stats != null else 0.0
	var weapon_damage: float = attacker_stats.weapon_damage if attacker_stats != null else 0.0
	var defense: float = target_stats.defense if target_stats != null else 0.0

	var raw_damage: float = (atk + weapon_damage) * atk_scale - (defense * def_scale)
	return maxf(min_damage, raw_damage)
