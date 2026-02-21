extends Node

const _ItemInstance = preload("res://scripts/resources/ItemInstance.gd")

# Maps Vector2i(tile_x, tile_y) => Array[ItemInstance]
# Efficient: O(1) tile lookup via Dictionary, linear only within a pile (usually tiny)
var grid: Dictionary = {}


# --- Query ---

# Returns the pile (Array) at `pos`, or an empty array if the tile is empty.
func get_items_at(pos) -> Array:
	return grid.get(pos, [])

# Returns true if there are any items at `pos`.
func has_items_at(pos) -> bool:
	return grid.has(pos) and grid[pos].size() > 0


# --- Modification ---

# Place `item` at tile `pos`, always as a new independent entry in the pile.
# Merging is the caller's responsibility (see ItemMoveController.try_merge).
# NOTE: stores the item by reference.
func add_item(pos, item):
	var pile: Array = grid.get(pos, [])
	pile.append(item)
	grid[pos] = pile

# Remove `item` from tile `pos` by object identity. No-op if not found.
func remove_item(pos, item):
	var pile: Array = grid.get(pos, [])
	for i in pile.size():
		if pile[i] == item:
			pile.remove_at(i)
			if pile.is_empty():
				grid.erase(pos)
			else:
				grid[pos] = pile
			return

# Remove and return the item at index `idx` from tile `pos`.
# Returns null if out of range.
func remove_item_at(pos, idx: int):
	var pile: Array = grid.get(pos, [])
	if idx < 0 or idx >= pile.size():
		return null
	var item = pile.pop_at(idx)
	if pile.is_empty():
		grid.erase(pos)
	else:
		grid[pos] = pile
	return item

# Move all (or `amount`) of a stack from tile `src`/index `idx` to tile `dst`.
# Pass amount = -1 to move the entire stack.
# Items are moved by reference (no duplicate); partial moves create a new ItemInstance.
func move_item_between(src, idx: int, dst, amount: int = -1):
	var pile: Array = grid.get(src, [])
	if idx < 0 or idx >= pile.size():
		return
	var item = pile[idx]
	var n = item.count if amount < 0 else min(amount, item.count)
	if n == item.count:
		# Moving the entire stack — pass the item reference directly.
		pile.remove_at(idx)
		if pile.is_empty():
			grid.erase(src)
		else:
			grid[src] = pile
		add_item(dst, item)
	else:
		# Partial move — reduce source count, create a new ItemInstance for the destination.
		# We must create a new instance here because the source item persists with its own count.
		var split = _ItemInstance.new()
		split.data  = item.data
		split.count = n
		item.remove_from_stack(n)
		grid[src] = pile
		add_item(dst, split)

# Clear all items from a tile.
func clear_tile(pos):
	grid.erase(pos)

# Clear the entire grid.
func clear():
	grid.clear()
