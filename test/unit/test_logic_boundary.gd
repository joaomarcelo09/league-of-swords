extends GutTest

const FORBIDDEN_TOKENS: Array[String] = [
	"extends Node",
	"Input.",
	"get_tree",
	'load("res://scenes',
	"load('res://scenes",
	'preload("res://scenes',
	"preload('res://scenes",
	"res://src/view",
	"res://src/input",
]


static func scan_source(source_text: String) -> Array[String]:
	var hits: Array[String] = []
	var lines := source_text.split("\n")
	for i in range(lines.size()):
		var line := lines[i]
		var trimmed := line.strip_edges()
		if trimmed.begins_with("#"):
			continue
		for token in FORBIDDEN_TOKENS:
			if token in line:
				hits.append("Line %d: contains forbidden token '%s'" % [i + 1, token])
	return hits


static func find_gd_files(dir_path: String) -> Array[String]:
	var results: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return results

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if dir.current_is_dir():
			if file_name != "." and file_name != "..":
				var sub_dir := dir_path.path_join(file_name)
				results.append_array(find_gd_files(sub_dir))
		elif file_name.ends_with(".gd"):
			results.append(dir_path.path_join(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()
	results.sort()
	return results


func test_scan_source_clean_string() -> void:
	var clean_code := """class_name SafeLogic
extends RefCounted

# Comment with extends Node or Input. or get_tree should be ignored
# load("res://scenes/test.tscn")
# res://src/view
# res://src/input

var _health: float = 100.0

func calculate_damage(base: float) -> float:
	return base * 1.5
"""
	var hits := scan_source(clean_code)
	assert_eq(hits.size(), 0, "Clean code should have no hits: %s" % str(hits))


func test_scan_source_forbidden_tokens() -> void:
	var cases: Dictionary = {
		"extends Node": "class_name BadClass extends Node",
		"Input.": "var pressed := Input.is_action_pressed('dash')",
		"get_tree": "var tree = get_tree()",
		'load("res://scenes': 'var s = load("res://scenes/main.tscn")',
		"load('res://scenes": "var s = load('res://scenes/main.tscn')",
		'preload("res://scenes': 'const S = preload("res://scenes/main.tscn")',
		"preload('res://scenes": "const S = preload('res://scenes/main.tscn')",
		"res://src/view": 'const V = preload("res://src/view/hud.gd")',
		"res://src/input": 'const I = preload("res://src/input/controls.gd")',
	}

	for token in cases:
		var snippet: String = cases[token]
		var hits := scan_source(snippet)
		assert_gt(hits.size(), 0, "Should detect forbidden token '%s' in: %s" % [token, snippet])
		var found := false
		for hit in hits:
			if token in hit:
				found = true
				break
		assert_true(found, "Reported hit should reference '%s'" % token)


func test_logic_boundary_real_folder() -> void:
	var files := find_gd_files("res://src/logic")
	assert_gt(files.size(), 0, "res://src/logic should contain at least one .gd file to validate")

	var all_violations: Array[String] = []
	for file_path in files:
		var file := FileAccess.open(file_path, FileAccess.READ)
		assert_not_null(file, "File should open: %s" % file_path)
		if file != null:
			var content := file.get_as_text()
			file.close()
			var hits := scan_source(content)
			for hit in hits:
				all_violations.append("%s: %s" % [file_path, hit])

	assert_eq(all_violations.size(), 0, "No forbidden boundary tokens allowed in src/logic: %s" % str(all_violations))
