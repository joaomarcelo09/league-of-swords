class_name ChunkTravel
extends RefCounted

# Pure-logic resolution of gate and door transitions between chunks.
# A gate moves the player to another chunk: the injected ChunkLoader is
# updated with the destination world tile so only the destination
# neighbourhood stays loaded. A door to an external zone (the dungeon) is
# resolved but not loaded here; the caller loads that zone itself.
# No Node/SceneTree/Input/rendering dependencies.

var errors: Array[String] = []

var _map: WorldMap = null
var _loader: ChunkLoader = null


func _init(world_map: WorldMap, loader: ChunkLoader = null) -> void:
	_map = world_map
	_loader = loader


# Resolves the transition at local_tile inside chunk_id.
# Returns:
#   {ok: false, reason: "none"}
#   {ok: false, reason: "locked", boss, id, label}
#   {ok: true, kind, id, label, to_chunk, to_local, to_world, loaded, unloaded}
#   {ok: true, kind: "door", id, label, to_zone, to_tile,
#    return_tile, return_chunk, return_to_tile}
# Failure reasons also include "no_map", "invalid_world", "unknown_chunk",
# "unknown_zone" and "no_loader"; they never crash and never load anything.
func travel(chunk_id: String, local_tile: Vector2i, defeated_bosses: Array = []) -> Dictionary:
	if _map == null:
		errors.append("ChunkTravel: no world map configured")
		return {"ok": false, "reason": "no_map"}
	if not _map.is_valid():
		errors.append("ChunkTravel: world map is invalid: %s" % str(_map.errors))
		return {"ok": false, "reason": "invalid_world"}
	if not _map.has_chunk(chunk_id):
		errors.append("ChunkTravel: unknown chunk '%s'" % chunk_id)
		return {"ok": false, "reason": "unknown_chunk", "chunk": chunk_id}

	var transition := _map.transition_at(chunk_id, local_tile)
	if transition.is_empty():
		return {"ok": false, "reason": "none"}

	var kind := str(transition.get("kind", ""))
	var transition_id := str(transition.get("id", ""))
	var label := str(transition.get("label", ""))
	var boss := str(transition.get("requires_boss", ""))
	if not boss.is_empty() and not defeated_bosses.has(boss):
		return {
			"ok": false,
			"reason": "locked",
			"boss": boss,
			"id": transition_id,
			"label": label,
		}

	var to_tile: Vector2i = transition.get("to_tile", Vector2i(-1, -1))
	var to_zone := str(transition.get("to_zone", ""))
	if not to_zone.is_empty():
		return {
			"ok": true,
			"kind": kind,
			"id": transition_id,
			"label": label,
			"to_zone": to_zone,
			"to_tile": to_tile,
			"return_tile": transition.get("return_tile", Vector2i(-1, -1)),
			"return_chunk": str(transition.get("return_chunk", "")),
			"return_to_tile": transition.get("return_to_tile", Vector2i(-1, -1)),
		}

	var to_chunk := str(transition.get("to_chunk", ""))
	if to_chunk.is_empty():
		errors.append("ChunkTravel: transition '%s' has no destination" % transition_id)
		return {"ok": false, "reason": "unknown_zone"}
	if not _map.has_chunk(to_chunk):
		errors.append("ChunkTravel: transition '%s' targets unknown chunk '%s'" % [transition_id, to_chunk])
		return {"ok": false, "reason": "unknown_chunk", "chunk": to_chunk}
	if _loader == null:
		errors.append("ChunkTravel: transition '%s' needs a chunk loader" % transition_id)
		return {"ok": false, "reason": "no_loader"}

	var to_world := _map.chunk_to_world(to_chunk, to_tile)
	var changes := _loader.update(to_world)
	return {
		"ok": true,
		"kind": kind,
		"id": transition_id,
		"label": label,
		"to_chunk": to_chunk,
		"to_local": to_tile,
		"to_world": to_world,
		"loaded": changes.get("loaded", []),
		"unloaded": changes.get("unloaded", []),
	}
