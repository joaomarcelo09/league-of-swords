class_name ChunkResume
extends RefCounted

# Pure-logic restore of a saved character into the chunked world.
# A character with an empty `chunk` comes from a classic single-zone save and
# is resumed without touching the loader. Otherwise `position` holds chunk-local
# tile coordinates (float tile units): resume converts them to a world tile and
# position, updates the loader so only the neighbourhood of that chunk stays
# loaded, and reports the changes. `capture`/`capture_position` do the inverse,
# recording a world tile/position as chunk + local position.
# No Node/SceneTree/Input/rendering dependencies.

# Restores character_state into the chunk streaming world.
# Returns:
#   {ok: true, chunked: false}                                   (classic save)
#   {ok: true, chunked: true, chunk, world_tile, world_pos, loaded, unloaded}
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

	var local_result: Variant = _local_position(character_state.position, world_map.chunk_size)
	if local_result == null:
		return {"ok": false, "reason": "invalid_position"}
	var local_position: Vector2 = local_result
	var local_tile := Vector2i(floori(local_position.x), floori(local_position.y))

	var world_tile := world_map.chunk_to_world(chunk, local_tile)
	var offset := world_map.chunk_to_world(chunk, Vector2i.ZERO)
	var world_pos := Vector2(offset) + local_position
	var changes := loader.update(world_tile)
	return {
		"ok": true,
		"chunked": true,
		"chunk": chunk,
		"world_tile": world_tile,
		"world_pos": world_pos,
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


# Records a float world position (Entity.pos, in world tile units) as its chunk
# and chunk-local position, keeping sub-tile precision, so the view never
# converts coordinates itself.
# Returns:
#   {ok: true, chunk, local_position, local_tile, world_tile, world_pos}
#   {ok: false, reason: "no_character"|"no_map"|"invalid_world"|"no_chunk"|
#                        "invalid_position"}
static func capture_position(world_map: WorldMap, character_state: CharacterState, world_pos: Vector2) -> Dictionary:
	if character_state == null:
		return {"ok": false, "reason": "no_character"}
	if world_map == null:
		return {"ok": false, "reason": "no_map"}
	if not world_map.is_valid():
		return {"ok": false, "reason": "invalid_world"}
	if not world_pos.is_finite():
		return {"ok": false, "reason": "invalid_position"}

	var world_tile := Vector2i(floori(world_pos.x), floori(world_pos.y))
	var placement := world_map.world_to_chunk(world_tile)
	var chunk := str(placement.get("chunk_id", ""))
	if chunk.is_empty():
		return {"ok": false, "reason": "no_chunk"}

	var offset := world_map.chunk_to_world(chunk, Vector2i.ZERO)
	var local_position := world_pos - Vector2(offset)
	var size := world_map.chunk_size
	if local_position.x < 0.0 or local_position.y < 0.0 or local_position.x >= float(size.x) or local_position.y >= float(size.y):
		return {"ok": false, "reason": "invalid_position"}

	character_state.chunk = chunk
	character_state.position = [local_position.x, local_position.y]
	return {
		"ok": true,
		"chunk": chunk,
		"local_position": local_position,
		"local_tile": Vector2i(floori(local_position.x), floori(local_position.y)),
		"world_tile": world_tile,
		"world_pos": world_pos,
	}


# Records a chunk-local tile (e.g. a door's return point) on character_state.
# Returns the same shape as capture().
static func capture_local(world_map: WorldMap, character_state: CharacterState, chunk: String, local_tile: Vector2i) -> Dictionary:
	if character_state == null:
		return {"ok": false, "reason": "no_character"}
	if world_map == null:
		return {"ok": false, "reason": "no_map"}
	if not world_map.is_valid():
		return {"ok": false, "reason": "invalid_world"}
	if not world_map.has_chunk(chunk):
		return {"ok": false, "reason": "unknown_chunk", "chunk": chunk}

	var size := world_map.chunk_size
	if local_tile.x < 0 or local_tile.y < 0 or local_tile.x >= size.x or local_tile.y >= size.y:
		return {"ok": false, "reason": "invalid_position"}

	var world_tile := world_map.chunk_to_world(chunk, local_tile)
	character_state.chunk = chunk
	character_state.position = [float(local_tile.x), float(local_tile.y)]
	return {
		"ok": true,
		"chunk": chunk,
		"local_tile": local_tile,
		"world_tile": world_tile,
	}


# Records where a door's zone returns to the chunked floor (the `chunk` and
# `to_tile` of GameSession.active_door), so a save made inside a door's zone
# (e.g. the dungeon) resumes on the chunked floor at the door's return point.
# Returns the same shape as capture_local().
static func capture_door_return(world_map: WorldMap, character_state: CharacterState, door: Dictionary) -> Dictionary:
	if character_state == null:
		return {"ok": false, "reason": "no_character"}
	var chunk := str(door.get("chunk", ""))
	if chunk.is_empty():
		return {"ok": false, "reason": "no_chunk"}
	var tile_value: Variant = door.get("to_tile", null)
	if not (tile_value is Vector2i):
		return {"ok": false, "reason": "invalid_position"}
	return capture_local(world_map, character_state, chunk, tile_value)


# Start chunk + chunk-local entry a new character begins at on the chunked
# floor, plus its world tile. Positions are the entry tile's center, like a
# spawned entity. Used for new characters and for falling back when a saved
# chunk cannot be resumed.
# Returns:
#   {ok: true, chunk, local_tile, local_position, world_tile, world_pos}
#   {ok: false, reason: "no_world"|"invalid_world"|"unknown_chunk"}
static func start_position(chunked_world: ChunkedWorld) -> Dictionary:
	if chunked_world == null:
		return {"ok": false, "reason": "no_world"}
	var world_map := chunked_world.map
	if world_map == null or not world_map.is_valid():
		return {"ok": false, "reason": "invalid_world"}
	var chunk := chunked_world.start_chunk
	if not world_map.has_chunk(chunk):
		return {"ok": false, "reason": "unknown_chunk", "chunk": chunk}

	var world_tile := chunked_world.start_entry()
	if world_tile.x < 0 or world_tile.y < 0:
		# The start zone never loaded: use the chunk's top-left tile.
		world_tile = chunked_world.chunk_offset(chunk)
	var placement := world_map.world_to_chunk(world_tile)
	var local_tile: Vector2i = placement.get("local_tile", world_tile)
	var tile_center := Vector2(0.5, 0.5)
	return {
		"ok": true,
		"chunk": chunk,
		"local_tile": local_tile,
		"local_position": Vector2(local_tile) + tile_center,
		"world_tile": world_tile,
		"world_pos": Vector2(world_tile) + tile_center,
	}


# Converts a CharacterState.position into a chunk-local position (tile units,
# float). Returns null when the value is not a pair of finite numbers or the
# tile it stands on falls outside the chunk.
static func _local_position(position: Array, chunk_size: Vector2i) -> Variant:
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
	var local_position := Vector2(fx, fy)
	var local_tile := Vector2i(floori(fx), floori(fy))
	if local_tile.x < 0 or local_tile.y < 0 or local_tile.x >= chunk_size.x or local_tile.y >= chunk_size.y:
		return null
	return local_position
