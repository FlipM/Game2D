extends Node
## Non-GUI automated tests for the item system (ItemData, ItemInstance, FloorGrid).
## Run headless: godot --headless --script tests/test_item_system.gd
## Exit code 0 = all passed, 1 = failures.

const _ItemData     = preload("res://scripts/resources/ItemData.gd")
const _ItemInstance = preload("res://scripts/resources/ItemInstance.gd")
const _FloorGrid    = preload("res://scripts/core/FloorGrid.gd")

var _passed: int = 0
var _failed: int = 0


func _ready():
	_run_all()
	print("\n=== Item System Tests: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _run_all():
	_test_stack_basic()
	_test_stack_limit()
	_test_stack_incompatible()
	_test_pickup_removes_from_floor_grid()
	_test_anti_cycle()
	_test_floor_grid_add_and_get()
	_test_floor_grid_remove_by_ref()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_data(id: String, stackable: bool = false, max_stack: int = 1):
	var d = _ItemData.new()
	d.id = id
	d.name = id
	d.is_stackable = stackable
	d.max_stack = max_stack
	d.is_container = false
	return d

func _make_instance(data, count: int = 1):
	var inst = _ItemInstance.new()
	inst.data = data
	inst.count = count
	return inst

func _assert(condition: bool, description: String):
	if condition:
		print("  PASS: %s" % description)
		_passed += 1
	else:
		printerr("  FAIL: %s" % description)
		_failed += 1


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func _test_stack_basic():
	print("\n[stack_basic]")
	var d = _make_data("coin", true, 99)
	var a = _make_instance(d, 5)
	var b = _make_instance(d, 3)
	_assert(a.can_stack_with(b), "can_stack_with same data")
	var added = a.add_to_stack(3)
	_assert(added == 3, "add_to_stack returns amount added")
	_assert(a.count == 8, "count after add is correct")

func _test_stack_limit():
	print("\n[stack_limit]")
	var d = _make_data("coin", true, 10)
	var a = _make_instance(d, 9)
	var added = a.add_to_stack(5)
	_assert(added == 1, "add_to_stack capped at max_stack")
	_assert(a.count == 10, "count == max_stack after capped add")
	_assert(a.is_full(), "is_full() true when at max_stack")

func _test_stack_incompatible():
	print("\n[stack_incompatible]")
	var d1 = _make_data("sword")
	var d2 = _make_data("shield")
	var a = _make_instance(d1)
	var b = _make_instance(d2)
	_assert(not a.can_stack_with(b), "cannot stack items with different data")
	var d3 = _make_data("sword2", false)
	var c = _make_instance(d3)
	var d4 = _make_data("sword2", false)
	var e = _make_instance(d4)
	_assert(not c.can_stack_with(e), "cannot stack non-stackable items")

func _test_pickup_removes_from_floor_grid():
	print("\n[pickup_removes_from_floor_grid]")
	var grid = _FloorGrid.new()
	var d = _make_data("sword")
	var inst = _make_instance(d)
	var tile = Vector2i(0, 0)
	grid.add_item(tile, inst)
	_assert(grid.has_items_at(tile), "item present after add_item")
	grid.remove_item(tile, inst)
	_assert(not grid.has_items_at(tile), "tile empty after remove_item")
	grid.free()

func _test_anti_cycle():
	print("\n[anti_cycle]")
	var container_data = _ItemData.new()
	container_data.id = "bag"
	container_data.name = "bag"
	container_data.is_container = true
	container_data.container_slots = 0

	var bag = _ItemInstance.new()
	bag.data = container_data

	var coin_data = _make_data("coin")
	var coin = _make_instance(coin_data)

	_assert(bag.can_add_to_container(coin), "bag can contain coin")
	# Self-containment should be rejected
	_assert(not bag.can_add_to_container(bag), "bag cannot contain itself")

func _test_floor_grid_add_and_get():
	print("\n[floor_grid_add_and_get]")
	var grid = _FloorGrid.new()
	var d = _make_data("potion", true, 10)
	var a = _make_instance(d, 3)
	var b = _make_instance(d, 4)
	var tile = Vector2i(1, 2)
	grid.add_item(tile, a)
	# Second add of compatible stackable item should stack onto existing entry
	grid.add_item(tile, b)
	var pile = grid.get_items_at(tile)
	# a was added first (non-full), b stacked onto it
	_assert(pile.size() == 1, "stackable items merge into one pile entry")
	_assert(pile[0].count == 7, "merged pile has combined count")
	grid.free()

func _test_floor_grid_remove_by_ref():
	print("\n[floor_grid_remove_by_ref]")
	var grid = _FloorGrid.new()
	var d1 = _make_data("sword")
	var d2 = _make_data("shield")
	var sword = _make_instance(d1)
	var shield = _make_instance(d2)
	var tile = Vector2i(0, 0)
	grid.add_item(tile, sword)
	grid.add_item(tile, shield)
	_assert(grid.get_items_at(tile).size() == 2, "two items on same tile")
	grid.remove_item(tile, sword)
	var pile = grid.get_items_at(tile)
	_assert(pile.size() == 1, "one item remains after remove_item by ref")
	_assert(pile[0] == shield, "correct item remains")
	grid.free()
