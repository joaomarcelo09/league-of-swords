class_name LaunchRequest
extends RefCounted

## Mode of launch: "" (default/fallback), "new", or "continue"
static var mode: String = ""

## Target character id when mode is "continue"
static var character_id: String = ""


static func reset() -> void:
	mode = ""
	character_id = ""
