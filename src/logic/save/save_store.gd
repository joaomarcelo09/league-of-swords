class_name SaveStore
extends RefCounted

const SAVE_VERSION: int = 1
const DEFAULT_ROOT: String = "user://saves"
const CHARACTERS_DIR: String = "characters"
const WORLD_FILE: String = "world.json"

var root: String = DEFAULT_ROOT
var item_db: ItemDB = null


func _init(p_root: String = DEFAULT_ROOT, p_item_db: ItemDB = null) -> void:
	root = p_root
	item_db = p_item_db


static func is_valid_name(name: String) -> bool:
	if name.is_empty():
		return false
	if name.strip_edges() != name:
		return false
	if "/" in name or "\\" in name:
		return false
	if ".." in name:
		return false
	if ":" in name:
		return false
	for i in range(name.length()):
		var c := name.unicode_at(i)
		if c < 32 or c == 127:
			return false
	return true


func get_slot_dir(slot: String) -> String:
	return root.path_join(slot)


func get_world_file_path(slot: String) -> String:
	return get_slot_dir(slot).path_join(WORLD_FILE)


func get_characters_dir(slot: String) -> String:
	return get_slot_dir(slot).path_join(CHARACTERS_DIR)


func get_character_file_path(slot: String, char_id: String) -> String:
	return get_characters_dir(slot).path_join("%s.json" % char_id)


func slot_exists(slot: String) -> bool:
	if not is_valid_name(slot):
		return false
	var world_path := get_world_file_path(slot)
	return FileAccess.file_exists(world_path) or DirAccess.dir_exists_absolute(get_slot_dir(slot))


func save_world(slot: String, world_state: WorldState) -> Dictionary:
	if not is_valid_name(slot):
		return {
			"ok": false,
			"error": "Invalid or unsafe slot name '%s'" % slot,
			"value": null
		}
	if world_state == null:
		return {
			"ok": false,
			"error": "world_state cannot be null",
			"value": null
		}

	var target_path := get_world_file_path(slot)
	return _write_json_atomic(target_path, world_state.to_dict())


func load_world(slot: String, p_item_db: ItemDB = null) -> Dictionary:
	if not is_valid_name(slot):
		return {
			"ok": false,
			"error": "Invalid or unsafe slot name '%s'" % slot,
			"value": null
		}

	var target_path := get_world_file_path(slot)
	var read_res := _read_json_file(target_path)
	if not read_res["ok"]:
		return read_res

	var active_item_db := p_item_db if p_item_db != null else self.item_db
	var errs: Array = []
	var world := WorldState.from_dict(read_res["value"], active_item_db, errs)
	if world == null:
		var err_msg: String = str(errs[0]) if not errs.is_empty() else WorldState.last_error
		return {
			"ok": false,
			"error": "%s: %s" % [target_path, err_msg],
			"value": null
		}

	return {
		"ok": true,
		"error": "",
		"value": world
	}


func save_character(slot: String, character_state: CharacterState) -> Dictionary:
	if not is_valid_name(slot):
		return {
			"ok": false,
			"error": "Invalid or unsafe slot name '%s'" % slot,
			"value": null
		}
	if character_state == null:
		return {
			"ok": false,
			"error": "character_state cannot be null",
			"value": null
		}
	if not is_valid_name(character_state.id):
		return {
			"ok": false,
			"error": "Invalid or unsafe character id '%s'" % character_state.id,
			"value": null
		}

	var target_path := get_character_file_path(slot, character_state.id)
	return _write_json_atomic(target_path, character_state.to_dict())


func load_character(slot: String, char_id: String, p_item_db: ItemDB = null) -> Dictionary:
	if not is_valid_name(slot):
		return {
			"ok": false,
			"error": "Invalid or unsafe slot name '%s'" % slot,
			"value": null
		}
	if not is_valid_name(char_id):
		return {
			"ok": false,
			"error": "Invalid or unsafe char_id '%s'" % char_id,
			"value": null
		}

	var target_path := get_character_file_path(slot, char_id)
	var read_res := _read_json_file(target_path)
	if not read_res["ok"]:
		return read_res

	var errs: Array = []
	var character := CharacterState.from_dict(read_res["value"], errs)
	if character == null:
		var err_msg: String = str(errs[0]) if not errs.is_empty() else CharacterState.last_error
		return {
			"ok": false,
			"error": "%s: %s" % [target_path, err_msg],
			"value": null
		}

	return {
		"ok": true,
		"error": "",
		"value": character
	}


func list_characters(slot: String) -> Dictionary:
	if not is_valid_name(slot):
		return {
			"ok": false,
			"error": "Invalid or unsafe slot name '%s'" % slot,
			"value": []
		}

	var chars_dir := get_characters_dir(slot)
	if not DirAccess.dir_exists_absolute(chars_dir):
		return {
			"ok": true,
			"error": "",
			"value": []
		}

	var dir := DirAccess.open(chars_dir)
	if dir == null:
		var err_code := DirAccess.get_open_error()
		return {
			"ok": false,
			"error": "Failed to open characters directory '%s' (error %d)" % [chars_dir, err_code],
			"value": []
		}

	var char_ids: Array[String] = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var char_id := file_name.trim_suffix(".json")
			char_ids.append(char_id)
		file_name = dir.get_next()
	dir.list_dir_end()
	char_ids.sort()

	return {
		"ok": true,
		"error": "",
		"value": char_ids
	}


func get_character_ids(slot: String) -> Array[String]:
	var res := list_characters(slot)
	if res.get("ok", false) and res.get("value") is Array:
		var out: Array[String] = []
		for item: Variant in res["value"]:
			out.append(str(item))
		return out
	return []


func _write_json_atomic(target_path: String, data: Dictionary) -> Dictionary:
	var dir_path := target_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		var err := DirAccess.make_dir_recursive_absolute(dir_path)
		if err != OK:
			return {
				"ok": false,
				"error": "%s: Failed to create directory '%s' (error %d)" % [target_path, dir_path, err],
				"value": null
			}

	var tmp_path := target_path + ".tmp"
	if FileAccess.file_exists(tmp_path):
		DirAccess.remove_absolute(tmp_path)

	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		var err_code := FileAccess.get_open_error()
		return {
			"ok": false,
			"error": "%s: Failed to open temporary file '%s' (error %d)" % [target_path, tmp_path, err_code],
			"value": null
		}

	var json_str := JSON.stringify(data, "\t")
	var write_res: Variant = file.store_string(json_str)
	if write_res is bool and not write_res:
		file.close()
		if FileAccess.file_exists(tmp_path):
			DirAccess.remove_absolute(tmp_path)
		return {
			"ok": false,
			"error": "%s: Failed to write string to temporary file '%s'" % [target_path, tmp_path],
			"value": null
		}

	var write_err := file.get_error()
	if write_err != OK:
		file.close()
		if FileAccess.file_exists(tmp_path):
			DirAccess.remove_absolute(tmp_path)
		return {
			"ok": false,
			"error": "%s: Write error on temporary file '%s' (error %d)" % [target_path, tmp_path, write_err],
			"value": null
		}

	file.flush()
	var flush_err := file.get_error()
	if flush_err != OK:
		file.close()
		if FileAccess.file_exists(tmp_path):
			DirAccess.remove_absolute(tmp_path)
		return {
			"ok": false,
			"error": "%s: Flush error on temporary file '%s' (error %d)" % [target_path, tmp_path, flush_err],
			"value": null
		}

	file.close()
	var close_err := file.get_error()
	if close_err != OK:
		if FileAccess.file_exists(tmp_path):
			DirAccess.remove_absolute(tmp_path)
		return {
			"ok": false,
			"error": "%s: Close error on temporary file '%s' (error %d)" % [target_path, tmp_path, close_err],
			"value": null
		}

	# Re-read and parse temp file to verify integrity before rename
	var verify_file := FileAccess.open(tmp_path, FileAccess.READ)
	if verify_file == null:
		if FileAccess.file_exists(tmp_path):
			DirAccess.remove_absolute(tmp_path)
		return {
			"ok": false,
			"error": "%s: Failed to verify temporary file '%s'" % [target_path, tmp_path],
			"value": null
		}
	var written_text := verify_file.get_as_text()
	verify_file.close()

	var verify_json := JSON.new()
	var parse_err := verify_json.parse(written_text)
	if parse_err != OK:
		if FileAccess.file_exists(tmp_path):
			DirAccess.remove_absolute(tmp_path)
		return {
			"ok": false,
			"error": "%s: Verification failed, invalid JSON in '%s'" % [target_path, tmp_path],
			"value": null
		}

	var rename_err := DirAccess.rename_absolute(tmp_path, target_path)
	if rename_err != OK:
		if FileAccess.file_exists(tmp_path):
			DirAccess.remove_absolute(tmp_path)
		return {
			"ok": false,
			"error": "%s: Failed to rename '%s' to '%s' (error %d)" % [target_path, tmp_path, target_path, rename_err],
			"value": null
		}

	return {
		"ok": true,
		"error": "",
		"value": target_path
	}


func _read_json_file(file_path: String) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		return {
			"ok": false,
			"error": "%s: File not found" % file_path,
			"value": null
		}

	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		var err_code := FileAccess.get_open_error()
		return {
			"ok": false,
			"error": "%s: Failed to open file (error %d)" % [file_path, err_code],
			"value": null
		}

	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var parse_err := json.parse(text)
	if parse_err != OK:
		return {
			"ok": false,
			"error": "%s: JSON parse error at line %d: %s" % [file_path, json.get_error_line(), json.get_error_message()],
			"value": null
		}

	if not (json.data is Dictionary):
		return {
			"ok": false,
			"error": "%s: Root JSON element must be an object" % file_path,
			"value": null
		}

	var data: Dictionary = json.data
	if not data.has("version"):
		return {
			"ok": false,
			"error": "%s: Missing 'version' field" % file_path,
			"value": null
		}

	var ver: Variant = data["version"]
	if not (ver is int or (ver is float and is_finite(ver) and floor(ver) == ver)):
		return {
			"ok": false,
			"error": "%s: Invalid 'version' type (expected int)" % file_path,
			"value": null
		}

	if int(ver) != SAVE_VERSION:
		return {
			"ok": false,
			"error": "%s: Unsupported version %s (expected %d)" % [file_path, str(ver), SAVE_VERSION],
			"value": null
		}

	return {
		"ok": true,
		"error": "",
		"value": data
	}
