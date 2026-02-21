extends Node
# ItemMoveController — handles all server-side item move/split/merge business logic.
#
# Owned by World as a child node. World.request_move_item() delegates here after
# doing network validation (proximity check, arena bounds check). This keeps the
# World node focused on scene/network concerns while item logic lives here.
#
# Depends on: GridService (autoload), FloorGrid (passed in), item_spawner (MultiplayerSpawner).

const _ItemInstance = preload("res://scripts/resources/ItemInstance.gd")

# Reference to the parent World's FloorGrid.
var floor_grid = null

# Reference to the World's ItemSpawner (MultiplayerSpawner).
var item_spawner = null

# Try to merge `moving` units from `entity` into the top-most stack at `drop_tile`.
# Only the top item (last placed, highest draw order) is considered — if it is not
# compatible, no merge happens and the caller places the item on top instead.
# Returns true if merge occurred, false otherwise.
func try_merge(entity, item_tile: Vector2i, drop_tile: Vector2i, moving: int) -> bool:
	var dest_entity = GridService.get_item_entity_at(drop_tile)
	if dest_entity == null or dest_entity == entity or dest_entity.item == null:
		return false
	if not dest_entity.item.can_stack_with(entity.item) or dest_entity.item.is_full():
		return false

	var room           = dest_entity.item.data.max_stack - dest_entity.item.count
	var actually_moved = min(moving, room)
	dest_entity.item.add_to_stack(actually_moved)
	entity.item.remove_from_stack(actually_moved)

	floor_grid.remove_item(item_tile, entity.item)
	if not entity.item.is_empty():
		floor_grid.add_item(item_tile, entity.item)

	if entity.item.is_empty():
		entity.queue_free()
	else:
		entity.update_visual()
		entity.sync_to_clients.rpc(entity.global_position, entity.item.data.resource_path, entity.item.count)
	dest_entity.update_visual()
	dest_entity.sync_to_clients.rpc(dest_entity.global_position, dest_entity.item.data.resource_path, dest_entity.item.count)

	print("ItemMoveController: merged %d '%s' from %s into %s (dest now %d)" % [
		actually_moved,
		dest_entity.item.data.name if dest_entity.item.data else "?",
		item_tile, drop_tile, dest_entity.item.count])
	return true

# Split `moving` units from `entity` at `item_tile` and create a new entity at `drop_tile`.
# The new entity is added last in the scene tree so it renders above existing items there.
func split(entity, item_tile: Vector2i, drop_tile: Vector2i, moving: int):
	var new_inst      = _ItemInstance.new()
	new_inst.data     = entity.item.data
	new_inst.count    = moving
	entity.item.remove_from_stack(moving)

	floor_grid.remove_item(item_tile, entity.item)
	floor_grid.add_item(item_tile, entity.item)
	floor_grid.add_item(drop_tile, new_inst)

	var new_entity    = item_spawner.spawn([new_inst, GridService.tile_to_world(drop_tile)])
	# Set item on the server entity after spawn() — not inside spawn_function.
	new_entity.set_item(new_inst)
	entity.update_visual()
	entity.sync_to_clients.rpc(entity.global_position, entity.item.data.resource_path, entity.item.count)
	new_entity.sync_to_clients.rpc(new_entity.global_position, new_inst.data.resource_path, new_inst.count)

	print("ItemMoveController: split %d '%s' to %s (source has %d left)" % [
		moving,
		entity.item.data.name if entity.item.data else "?",
		drop_tile, entity.item.count])

# Move the entire stack of `entity` from `item_tile` to `drop_tile`.
# The moved entity is raised to the top of the draw order so it appears above
# any items already sitting at the destination tile.
func move_whole(entity, item_tile: Vector2i, drop_tile: Vector2i):
	GridService.move_item_entity(entity, item_tile, drop_tile)
	floor_grid.remove_item(item_tile, entity.item)
	floor_grid.add_item(drop_tile, entity.item)
	entity.global_position = GridService.tile_to_world(drop_tile)
	entity.update_visual()
	# Raise to front so the moved item renders above items already at the tile.
	# In Godot 4, -1 is not "last child"; use get_child_count()-1 explicitly.
	var parent = entity.get_parent()
	parent.move_child(entity, parent.get_child_count() - 1)
	entity.sync_to_clients.rpc(entity.global_position, entity.item.data.resource_path, entity.item.count)

	print("ItemMoveController: moved '%s' from %s to %s" % [
		entity.item.data.name if entity.item.data else "?", item_tile, drop_tile])

# Main entry point — called from World.request_move_item after validation.
func execute(entity, item_tile: Vector2i, drop_tile: Vector2i, moving: int):
	# 1. Try merging into a compatible stack already at the destination.
	if try_merge(entity, item_tile, drop_tile, moving):
		return
	# 2. No merge possible — split or move the whole stack to the destination.
	#    Multiple incompatible items on the same tile are allowed (stacked visually).
	if moving < entity.item.count:
		split(entity, item_tile, drop_tile, moving)
	else:
		move_whole(entity, item_tile, drop_tile)
