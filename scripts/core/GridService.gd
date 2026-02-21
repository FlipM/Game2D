extends Node
# GridService — authoritative tile-coordinate utilities and entity registry.
#
# Centralises every method that was previously duplicated across World.gd and
# accessed via per-frame scene-tree searches in MovementComponent, Creature, etc.
#
# Registered as an autoload ("GridService") in project.godot so any script can
# call GridService.tile_to_world(coords) etc. without a scene-tree lookup.

# ---------------------------------------------------------------------------
# Tile math
# ---------------------------------------------------------------------------

# Convert a world-space position to the nearest tile coordinate.
# Uses round() for robustness against floating-point drift.
func world_to_tile(pos: Vector2) -> Vector2i:
	var offset = pos - GameConstants.WORLD_CENTER
	return Vector2i(
		roundi(offset.x / GameConstants.TILE_SIZE),
		roundi(offset.y / GameConstants.TILE_SIZE)
	)

# Convert a tile coordinate back to world-space (centre of tile).
func tile_to_world(coords: Vector2i) -> Vector2:
	return GameConstants.WORLD_CENTER + Vector2(coords) * GameConstants.TILE_SIZE

# ---------------------------------------------------------------------------
# Entity registry — O(1) lookup of ItemEntities by tile
# ---------------------------------------------------------------------------
# Maps Vector2i(tile) -> Array of ItemEntity nodes.
# A tile may hold any number of overlapping item entities.
# ItemEntity calls register/unregister itself on add/remove from tree.

var _item_entity_map: Dictionary = {}

func register_item_entity(entity: Node) -> void:
	var tile = world_to_tile(entity.global_position)
	if not _item_entity_map.has(tile):
		_item_entity_map[tile] = []
	if not entity in _item_entity_map[tile]:
		_item_entity_map[tile].append(entity)

func unregister_item_entity(entity: Node) -> void:
	var tile = world_to_tile(entity.global_position)
	if not _item_entity_map.has(tile):
		return
	_item_entity_map[tile].erase(entity)
	if _item_entity_map[tile].is_empty():
		_item_entity_map.erase(tile)

# Call this whenever an ItemEntity moves to a new tile.
func move_item_entity(entity: Node, old_tile: Vector2i, new_tile: Vector2i) -> void:
	# Remove from old tile.
	if _item_entity_map.has(old_tile):
		_item_entity_map[old_tile].erase(entity)
		if _item_entity_map[old_tile].is_empty():
			_item_entity_map.erase(old_tile)
	# Add to new tile.
	if not _item_entity_map.has(new_tile):
		_item_entity_map[new_tile] = []
	if not entity in _item_entity_map[new_tile]:
		_item_entity_map[new_tile].append(entity)

# Return all valid ItemEntities at `tile` (may be empty array).
func get_item_entities_at(tile: Vector2i) -> Array:
	if not _item_entity_map.has(tile):
		return []
	# Prune any freed nodes in-place.
	var arr: Array = _item_entity_map[tile]
	var i := arr.size() - 1
	while i >= 0:
		if not is_instance_valid(arr[i]):
			arr.remove_at(i)
		i -= 1
	if arr.is_empty():
		_item_entity_map.erase(tile)
		return []
	return arr

# Return the top-most (last-placed) valid ItemEntity at `tile`, or null if none.
# LIFO order: the last element in the array was placed most recently and renders
# on top (highest child index), so it should be picked first.
func get_item_entity_at(tile: Vector2i):
	var arr := get_item_entities_at(tile)
	return arr[arr.size() - 1] if arr.size() > 0 else null

# ---------------------------------------------------------------------------
# Occupancy — shared between World.get_astar_path and MovementComponent
# ---------------------------------------------------------------------------
# Returns true if `pos` (world space) is occupied by any player or creature
# other than `exclude_entity`.  Checks both current position and reserved
# target_position so reservations are honoured.
func is_tile_occupied(pos: Vector2, exclude_entity: Node = null) -> bool:
	var check_coords = world_to_tile(pos)
	for group in ["players", "creatures"]:
		for entity in _get_group_safe(group):
			if not is_instance_valid(entity) or entity == exclude_entity:
				continue
			var movement = entity.get_node_or_null("MovementComponent")
			if not movement:
				continue
			var entity_coords = world_to_tile(entity.global_position)
			var reserved_coords = world_to_tile(movement.target_position)
			if entity_coords == check_coords or reserved_coords == check_coords:
				return true
	return false

# Builds the combined player+creature list without a temporary Array allocation
# by using a cached SceneTree group query result directly.
func _get_group_safe(group: String) -> Array:
	if get_tree():
		return get_tree().get_nodes_in_group(group)
	return []
