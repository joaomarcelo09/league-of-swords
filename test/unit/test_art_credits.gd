extends GutTest
## Checks that third-party art is pinned in data/art_manifest.json and credited in
## assets/CREDITS.md. No network: only reads the manifest, CREDITS.md and assets/.
## The manifest is an object {snake_case_id: row} so the data registry accepts it.

const MANIFEST_PATH: String = "res://data/art_manifest.json"
const CREDITS_PATH: String = "res://assets/CREDITS.md"
const ASSETS_DIR: String = "res://assets"
const REQUIRED_FIELDS: Array[String] = ["url", "sha256", "dest", "author", "license", "source_page"]
const ALLOWED_LICENSES: Array[String] = ["CC0", "CC-BY 3.0", "CC-BY-SA 3.0", "GPL"]
const SKIPPED_EXTENSIONS: Array[String] = ["import", "uid"]
const PLACEHOLDER_PREFIX: String = "placeholder"


func _load_manifest() -> Dictionary:
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	assert_not_null(file, "Manifest must be readable at " + MANIFEST_PATH)
	if file == null:
		return {}
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	assert_eq(err, OK, "Manifest JSON must parse: " + json.get_error_message())
	if err != OK or not (json.data is Dictionary):
		assert_true(json.data is Dictionary, "Manifest must be a JSON object of {id: row}")
		return {}
	return json.data as Dictionary


## Returns the CREDITS.md table rows as {paths: Array[String], license: String}.
## Paths are the backticked `assets/...` tokens in the first cell of a table row.
func _load_credit_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var file := FileAccess.open(CREDITS_PATH, FileAccess.READ)
	assert_not_null(file, "CREDITS.md must be readable at " + CREDITS_PATH)
	if file == null:
		return rows
	var token_re := RegEx.new()
	token_re.compile("`(assets/[^`]+)`")
	for raw_line: String in file.get_as_text().split("\n"):
		var line := raw_line.strip_edges()
		if not line.begins_with("|"):
			continue
		var cells := line.split("|")
		# cells[0] is empty (text before the first pipe).
		if cells.size() < 4:
			continue
		var paths: Array[String] = []
		for m: RegExMatch in token_re.search_all(cells[1]):
			paths.append(m.get_string(1))
		if paths.is_empty():
			continue
		rows.append({"paths": paths, "license": cells[3].strip_edges()})
	return rows


func _covering_row(rel_path: String, rows: Array[Dictionary]) -> Dictionary:
	for row: Dictionary in rows:
		for p: String in row["paths"]:
			if rel_path == p or (p.ends_with("/") and rel_path.begins_with(p)):
				return row
	return {}


func _is_placeholder(rel_path: String) -> bool:
	for part: String in rel_path.split("/"):
		if part.begins_with(PLACEHOLDER_PREFIX):
			return true
	return false


func _list_files(dir_path: String, rel_prefix: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for f: String in dir.get_files():
		out.append(rel_prefix + f)
	for sub: String in dir.get_directories():
		_list_files(dir_path.path_join(sub), rel_prefix + sub + "/", out)


func test_manifest_rows_are_complete() -> void:
	var manifest := _load_manifest()
	assert_gt(manifest.size(), 0, "Manifest must list at least one file")
	var hex_re := RegEx.new()
	hex_re.compile("^[0-9a-f]{64}$")
	var dests: Dictionary = {}
	for i: Variant in manifest.keys():
		var row_v: Variant = manifest[i]
		assert_true(row_v is Dictionary, "Manifest row %s must be an object" % i)
		if not (row_v is Dictionary):
			continue
		var row: Dictionary = row_v
		for field: String in REQUIRED_FIELDS:
			var value: Variant = row.get(field, "")
			assert_true(value is String and not (value as String).strip_edges().is_empty(),
				"Manifest row %s needs non-empty '%s'" % [i, field])
		assert_not_null(hex_re.search(str(row.get("sha256", ""))),
			"Manifest row %s sha256 must be 64 lowercase hex chars" % i)
		assert_true(ALLOWED_LICENSES.has(str(row.get("license", ""))),
			"Manifest row %s license '%s' must be one of %s" % [i, row.get("license", ""), ALLOWED_LICENSES])
		var dest := str(row.get("dest", ""))
		assert_true(dest.begins_with("assets/") and not dest.split("/").has(".."),
			"Manifest row %s dest must be under assets/: %s" % [i, dest])
		assert_false(dests.has(dest), "Manifest dest must be unique: " + dest)
		dests[dest] = true
		if row.has("member"):
			assert_false(str(row["member"]).is_empty(), "Manifest row %s member must not be empty" % i)
			assert_false(str(row["member"]).begins_with("__MACOSX/"),
				"Manifest row %s must not use __MACOSX entries" % i)
			assert_not_null(hex_re.search(str(row.get("member_sha256", ""))),
				"Manifest row %s with member needs a 64-hex member_sha256" % i)


func test_every_manifest_dest_is_credited() -> void:
	var manifest := _load_manifest()
	var rows := _load_credit_rows()
	assert_gt(rows.size(), 0, "CREDITS.md must have asset rows")
	for row_v: Variant in manifest.values():
		if not (row_v is Dictionary):
			continue
		var entry: Dictionary = row_v
		var dest := str(entry.get("dest", ""))
		var credit := _covering_row(dest, rows)
		assert_false(credit.is_empty(), "CREDITS.md has no row covering manifest dest " + dest)
		if credit.is_empty():
			continue
		var lic := str(entry.get("license", ""))
		assert_true(str(credit["license"]).begins_with(lic),
			"CREDITS.md license for %s must start with manifest license '%s' (got '%s')" % [dest, lic, credit["license"]])


func test_every_asset_file_is_credited() -> void:
	var rows := _load_credit_rows()
	var files: Array[String] = []
	_list_files(ASSETS_DIR, "assets/", files)
	var credits_rel := CREDITS_PATH.trim_prefix("res://")
	var checked := 0
	for rel: String in files:
		if rel == credits_rel or SKIPPED_EXTENSIONS.has(rel.get_extension()) or _is_placeholder(rel):
			continue
		checked += 1
		assert_false(_covering_row(rel, rows).is_empty(), "assets file has no CREDITS.md row: " + rel)
	# Passes with or without fetched art (fetched art is gitignored and optional).
	gut.p("checked %d non-placeholder asset file(s)" % checked)
	assert_true(true)
