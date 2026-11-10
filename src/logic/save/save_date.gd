class_name SaveDate
extends RefCounted


static func get_date_string(datetime_dict: Dictionary = {}) -> String:
	if not datetime_dict.is_empty():
		var year: int = int(datetime_dict.get("year", 1970))
		var month: int = int(datetime_dict.get("month", 1))
		var day: int = int(datetime_dict.get("day", 1))
		return "%04d-%02d-%02d" % [year, month, day]
	return Time.get_date_string_from_system()
