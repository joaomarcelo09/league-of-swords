class_name DataRegistry
extends RefCounted

var _tables: Dictionary = {}
var _raw_data: Dictionary = {}
var _table_files: Dictionary = {}
var _balance: Dictionary = {}
var _schemas: Dictionary = {}
var _load_errors: Array[String] = []
var _id_regex: RegEx = null


func _init() -> void:
	_id_regex = RegEx.new()
	_id_regex.compile("^[a-z0-9_]+$")


func clear() -> void:
	_tables.clear()
	_raw_data.clear()
	_table_files.clear()
	_balance.clear()
	_load_errors.clear()


func load_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		var err_code := DirAccess.get_open_error()
		_load_errors.append("%s: Cannot open directory (error %d)" % [path, err_code])
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	var json_files: Array[String] = []
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			json_files.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	json_files.sort()

	for f_name: String in json_files:
		var file_path := path.path_join(f_name)
		var file := FileAccess.open(file_path, FileAccess.READ)
		if file == null:
			var err_code := FileAccess.get_open_error()
			_load_errors.append("%s: Cannot open file (error %d)" % [f_name, err_code])
			continue

		var text := file.get_as_text()
		file.close()

		var json := JSON.new()
		var parse_err := json.parse(text)
		if parse_err != OK:
			_load_errors.append("%s: JSON parse error at line %d: %s" % [f_name, json.get_error_line(), json.get_error_message()])
			continue

		if not (json.data is Dictionary):
			_load_errors.append("%s: Top-level JSON must be an object" % f_name)
			continue

		var data: Dictionary = json.data
		var table_name := f_name.get_basename()
		_table_files[table_name] = f_name

		if f_name == "balance.json":
			_balance = data
		else:
			_raw_data[table_name] = data
			var valid_entries: Dictionary = {}
			for entry_id: Variant in data.keys():
				var id_str := str(entry_id)
				var entry_val: Variant = data[entry_id]
				if entry_val is Dictionary:
					valid_entries[id_str] = entry_val
			_tables[table_name] = valid_entries


func get_balance(key_path: String, default_value: Variant = null) -> Variant:
	if key_path.is_empty():
		return default_value
	var parts: PackedStringArray = key_path.split(".")
	var current: Variant = _balance
	for part: String in parts:
		if not (current is Dictionary) or not (current as Dictionary).has(part):
			return default_value
		current = (current as Dictionary)[part]
	return current


func get_entry(table: String, id: String) -> Dictionary:
	if _tables.has(table) and _tables[table].has(id):
		var val: Variant = _tables[table][id]
		if val is Dictionary:
			return val
	return {}


func has_entry(table: String, id: String) -> bool:
	return _tables.has(table) and _tables[table].has(id)


func ids(table: String) -> Array[String]:
	var result: Array[String] = []
	if _tables.has(table):
		for id_key: Variant in _tables[table].keys():
			result.append(str(id_key))
	result.sort()
	return result


func set_schema(table: String, required_fields: Dictionary) -> void:
	_schemas[table] = required_fields.duplicate()


func validate() -> Array[String]:
	var errors: Array[String] = []
	errors.append_array(_load_errors)

	var table_names: Array = _raw_data.keys()
	table_names.sort()

	for table: String in table_names:
		var file_name: String = _table_files.get(table, "%s.json" % table)
		var entries: Dictionary = _raw_data[table]
		var id_keys: Array = entries.keys()
		id_keys.sort()

		for id_val: Variant in id_keys:
			var id_str := str(id_val)

			if id_str.is_empty():
				errors.append('%s: id is empty (must be snake_case [a-z0-9_]+)' % file_name)
			elif _id_regex.search(id_str) == null:
				errors.append('%s: "%s" id is not valid snake_case [a-z0-9_]+' % [file_name, id_str])

			var entry_val: Variant = entries[id_val]
			if not (entry_val is Dictionary):
				errors.append('%s: "%s" entry must be an object' % [file_name, id_str])
				continue

			var entry_dict: Dictionary = entry_val
			if _schemas.has(table):
				var schema: Dictionary = _schemas[table]
				var field_names: Array = schema.keys()
				field_names.sort()

				for field_name: String in field_names:
					if not entry_dict.has(field_name):
						errors.append('%s: "%s" missing field "%s"' % [file_name, id_str, field_name])
					else:
						var expected_type: int = schema[field_name]
						var val: Variant = entry_dict[field_name]
						if not _is_type_compatible(val, expected_type):
							errors.append('%s: "%s" field "%s" wrong type (expected %s, got %s)' % [
								file_name, id_str, field_name, type_string(expected_type), type_string(typeof(val))
							])

	return errors


func _is_type_compatible(val: Variant, expected_type: int) -> bool:
	var actual_type: int = typeof(val)
	if actual_type == expected_type:
		return true
	if expected_type == TYPE_INT and actual_type == TYPE_FLOAT:
		return is_finite(val) and floor(val) == val
	if expected_type == TYPE_FLOAT and actual_type == TYPE_INT:
		return true
	return false
