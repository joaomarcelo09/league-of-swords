class_name CharacterNaming
extends RefCounted

const MAX_NAME_LENGTH: int = 32


static func validate_name(name: String) -> Dictionary:
	var trimmed := name.strip_edges()
	if trimmed.is_empty():
		return {
			"valid": false,
			"error": "Character name cannot be empty",
			"value": ""
		}
	if trimmed.length() > MAX_NAME_LENGTH:
		return {
			"valid": false,
			"error": "Character name cannot exceed %d characters" % MAX_NAME_LENGTH,
			"value": ""
		}
	return {
		"valid": true,
		"error": "",
		"value": trimmed
	}
