class_name Stats
extends RefCounted

var max_hp: float = 0.0
var atk: float = 0.0
var defense: float = 0.0
var attack_range: float = 0.0
var attack_interval: float = 0.0
var weapon_damage: float = 0.0


func _init(
	p_max_hp: float = 0.0,
	p_atk: float = 0.0,
	p_defense: float = 0.0,
	p_attack_range: float = 0.0,
	p_attack_interval: float = 0.0,
	p_weapon_damage: float = 0.0
) -> void:
	max_hp = p_max_hp
	atk = p_atk
	defense = p_defense
	attack_range = p_attack_range
	attack_interval = p_attack_interval
	weapon_damage = p_weapon_damage


static func from_dict(d: Dictionary) -> Stats:
	var s := Stats.new()
	s.max_hp = float(d.get("max_hp", 0.0))
	s.atk = float(d.get("atk", 0.0))
	s.defense = float(d.get("defense", 0.0))
	s.attack_range = float(d.get("attack_range", 0.0))
	s.attack_interval = float(d.get("attack_interval", 0.0))
	s.weapon_damage = float(d.get("weapon_damage", 0.0))
	return s


func to_dict() -> Dictionary:
	return {
		"max_hp": max_hp,
		"atk": atk,
		"defense": defense,
		"attack_range": attack_range,
		"attack_interval": attack_interval,
		"weapon_damage": weapon_damage,
	}


func duplicate() -> Stats:
	return Stats.new(max_hp, atk, defense, attack_range, attack_interval, weapon_damage)
