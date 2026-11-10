extends GutTest


func test_save_date_from_system() -> void:
	var date_str := SaveDate.get_date_string()
	assert_false(date_str.is_empty(), "Date string from system should not be empty")
	# Format should be YYYY-MM-DD
	var parts := date_str.split("-")
	assert_eq(parts.size(), 3, "Date string should have 3 hyphen-separated parts")
	assert_eq(parts[0].length(), 4, "Year part should be 4 characters")
	assert_eq(parts[1].length(), 2, "Month part should be 2 characters")
	assert_eq(parts[2].length(), 2, "Day part should be 2 characters")


func test_save_date_from_dict() -> void:
	var dt := {"year": 2026, "month": 11, "day": 10}
	assert_eq(SaveDate.get_date_string(dt), "2026-11-10")

	var dt2 := {"year": 2025, "month": 5, "day": 4}
	assert_eq(SaveDate.get_date_string(dt2), "2025-05-04")


func test_character_naming_valid() -> void:
	var res := CharacterNaming.validate_name("Alden")
	assert_true(res.get("valid", false))
	assert_eq(res.get("value", ""), "Alden")
	assert_eq(res.get("error", ""), "")


func test_character_naming_strips_edges() -> void:
	var res := CharacterNaming.validate_name("   Brand   ")
	assert_true(res.get("valid", false))
	assert_eq(res.get("value", ""), "Brand")


func test_character_naming_empty_rejected() -> void:
	var res1 := CharacterNaming.validate_name("")
	assert_false(res1.get("valid", true))
	assert_false(str(res1.get("error", "")).is_empty())

	var res2 := CharacterNaming.validate_name("   \t\n  ")
	assert_false(res2.get("valid", true))
	assert_false(str(res2.get("error", "")).is_empty())


func test_character_naming_too_long_rejected() -> void:
	var long_name := "A".repeat(CharacterNaming.MAX_NAME_LENGTH + 1)
	var res := CharacterNaming.validate_name(long_name)
	assert_false(res.get("valid", true))
	assert_true(str(res.get("error", "")).contains("exceed"))
