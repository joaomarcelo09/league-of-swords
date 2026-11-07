class_name Combat
extends RefCounted


static func compute_damage(attacker_stats: Stats, target_stats: Stats, registry: DataRegistry) -> float:
	if registry == null:
		push_error("Combat.compute_damage: DataRegistry is required")
		return 0.0

	var val_min: Variant = registry.get_balance("combat.min_damage")
	if val_min == null:
		push_error("Combat.compute_damage: missing balance entry combat.min_damage")
		return 0.0

	var val_atk: Variant = registry.get_balance("combat.atk_scale")
	if val_atk == null:
		push_error("Combat.compute_damage: missing balance entry combat.atk_scale")
		return 0.0

	var val_def: Variant = registry.get_balance("combat.def_scale")
	if val_def == null:
		push_error("Combat.compute_damage: missing balance entry combat.def_scale")
		return 0.0

	if attacker_stats == null:
		push_error("Combat.compute_damage: attacker stats missing")
		return 0.0

	var min_damage: float = float(val_min)
	var atk_scale: float = float(val_atk)
	var def_scale: float = float(val_def)

	var atk: float = attacker_stats.atk
	var weapon_damage: float = attacker_stats.weapon_damage
	var defense: float = target_stats.defense if target_stats != null else 0.0

	var raw_damage: float = (atk + weapon_damage) * atk_scale - (defense * def_scale)
	return maxf(min_damage, raw_damage)
