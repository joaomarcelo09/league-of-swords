class_name ChunkResume
extends RefCounted

# Pure-logic restore of a saved character into the chunked world.
# A character with an empty `chunk` comes from a classic single-zone save and
# is resumed without touching the loader. Otherwise `position` holds chunk-local
# tile coordinates: resume converts them to a world tile, updates the loader so
# only the neighbourhood of that chunk stays loaded, and reports the changes.
# `capture` does the inverse, recording a world tile as chunk + local position.
# No Node/SceneTree/Input/rendering dependencies.

# Restores character_state into the chunk streaming world.
# Returns:
#   {ok: true, chunked: false}                                   (classic save)
#   {ok: true, chunked: true, chunk, world_tile, loaded, unloaded}
#   {ok: false, reason: "no_character"|"no_map"|"invalid_world"|
#                        "unknown_chunk"|"no_loader"|"invalid_position"}
# Failures never load anything and never crash.
static func resume(world_map: WorldMap, loader: ChunkLoader, character_state: CharacterState) -> Dictionary:
	if character_state == null:
		return {"ok": false, "reason": "no_character"}

	var chunk := character_state.chunk
	if chunk.is_empty():
		return {"ok": true, "chunked": false}

	if world_map == null:
		return {"ok": false, "reason": "no_map"}
	if not world_map.is_valid():
		return {"ok": false, "reason": "invalid_world"}
	if not world_map.has_chunk(chunk):
		return {"ok": false, "reason": "unknown_chunk", "chunk": chunk}
	if loader == null:
		return {"ok": false, "reason": "no_loader"}

	var local_tile_result: Variant = _local_tile(character_state.position, world_map.chunk_size)
	if local_tile_result == null:
		return {"ok": false, "reason": "invalid_position"}
	var local_tile: Vector2i = local_tile_result

	var world_tile := world_map.chunk_to_world(chunk, local_tile)
	var changes := loader.update(world_tile)
	return {
		"ok": true,
		"chunked": true,
		"chunk": chunk,
		"world_tile": world_tile,
		"loaded": changes.get("loaded", []),
		"unloaded": changes.get("unloaded", []),
	}


# Records a world tile on character_state as its chunk id and chunk-local
# position (as floats, matching CharacterState.position). Leaves `zone` alone.
# Returns:
#   {ok: true, chunk, local_tile, world_tile}
#   {ok: false, reason: "no_character"|"no_map"|"invalid_world"|"no_chunk"}
static func capture(world_map: WorldMap, character_state: CharacterState, world_tile: Vector2i) -> Dictionary:
	if character_state == null:
		return {"ok": false, "reason": "no_character"}
	if world_map == null:
		return {"ok": false, "reason": "no_map"}
	if not world_map.is_valid():
		return {"ok": false, "reason": "invalid_world"}

	var placement := world_map.world_to_chunk(world_tile)
	var chunk := str(placement.get("chunk_id", ""))
	if chunk.is_empty():
		return {"ok": false, "reason": "no_chunk"}

	var local_tile: Vector2i = placement.get("local_tile", world_tile)
	character_state.chunk = chunk
	character_state.position = [float(local_tile.x), float(local_tile.y)]
	return {
		"ok": true,
		"chunk": chunk,
		"local_tile": local_tile,
		"world_tile": world_tile,
	}


# Converts a CharacterState.position into a chunk-local tile. Returns null when
# the value is not a pair of finite numbers or falls outside the chunk.
static func _local_tile(position: Array, chunk_size: Vector2i) -> Variant:
	if position.size() < 2:
		return null
	var px: Variant = position[0]
	var py: Variant = position[1]
	if not (((px is int or px is float) and not (px is bool)) and ((py is int or py is float) and not (py is bool))):
		return null
	var fx := float(px)
	var fy := float(py)
	if not is_finite(fx) or not is_finite(fy):
		return null
	var local_tile := Vector2i(roundi(fx), roundi(fy))
	if local_tile.x < 0 or local_tile.y < 0 or local_tile.x >= chunk_size.x or local_tile.y >= chunk_size.y:
		return null
	return local_tile
