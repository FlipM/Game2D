extends Node
## Tests for ItemMoveController: merge, split, move_whole using stub entities.
## Run standalone help: godot --headless --path . tests/test_item_pushing.gd

const _ItemData = preload("res://scripts/resources/ItemData.gd")
const _ItemInstance = preload("res://scripts/resources/ItemInstance.gd")
const _FloorGrid = preload("res://scripts/core/FloorGrid.gd")
const _IMC = preload("res://scripts/core/ItemMoveController.gd")

var _passed: int = 0
var _failed: int = 0


func _ready():
	# Standalone run support
	if get_tree().current_scene == self:
		_run_all()
		print("\n=== Item Pushing Tests: %d passed, %d failed ===" % [_passed, _failed])
		get_tree().quit(1 if _failed > 0 else 0)


func _run_all():
	_test_try_merge_compatible()
	_test_try_merge_full_dest_rejected()
	_test_try_merge_incompatible_rejected()
	_test_move_whole_updates_floor_grid()
	_test_split_reduces_source()
	_test_execute_routes_to_move_whole()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
func _assert(condition: bool, description: String):
	if condition:
		print("  PASS: %s" % description)
		_passed += 1
	else:
		printerr("  FAIL: %s" % description)
		_failed += 1

func _make_data(id: String, stackable: bool = false, max_stack: int = 1):
	var d = _ItemData.new()
	d.id = id; d.name = id
	d.is_stackable = stackable; d.max_stack = max_stack
	d.is_container = false
	return d

func _make_inst(data, count: int = 1):
	var i = _ItemInstance.new()
	i.data = data; i.count = count
	return i

class StubEntity extends Node2D:
	var item = null
	func _init():
		rpc_config("sync_to_clients", {"call_local": true, "transfer_mode": 0, "rpc_mode": 1})
	func update_visual(): pass
	func sync_to_clients(_p, _r, _c): pass

func _make_entity(inst, tile: Vector2i) -> StubEntity:
	var e = StubEntity.new()
	e.item = inst
	# Inlined GridService.tile_to_world(tile)
	e.global_position = GameConstants.WORLD_CENTER + Vector2(tile) * GameConstants.TILE_SIZE
	add_child(e)
	return e

func _setup() -> Array:
	var grid = _FloorGrid.new()
	add_child(grid)
	var imc = _IMC.new()
	imc.floor_grid = grid
	imc.item_spawner = null
	add_child(imc)
	return [grid, imc]


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------
func _test_try_merge_compatible():
	print("\n[try_merge_compatible]")
	var s = _setup(); var grid = s[0]; var imc = s[1]
	var d = _make_data("coin", true, 10)
	var src_inst = _make_inst(d, 3)
	var dst_inst = _make_inst(d, 4)
	var src_tile = Vector2i(30, 0); var dst_tile = Vector2i(31, 0)
	var src_e = _make_entity(src_inst, src_tile)
	var dst_e = _make_entity(dst_inst, dst_tile)
	grid.add_item(src_tile, src_inst); grid.add_item(dst_tile, dst_inst)
	GridService.register_item_entity(dst_e)
	var merged = imc.try_merge(src_e, src_tile, dst_tile, 3)
	GridService.unregister_item_entity(dst_e)
	_assert(merged, "try_merge returns true for compatible stacks")
	_assert(dst_inst.count == 7, "destination count increased by merged amount")
	src_e.queue_free(); dst_e.queue_free(); grid.queue_free(); imc.queue_free()

func _test_try_merge_full_dest_rejected():
	print("\n[try_merge_full_dest_rejected]")
	var s = _setup(); var grid = s[0]; var imc = s[1]
	var d = _make_data("coin", true, 5)
	var src_inst = _make_inst(d, 2)
	var dst_inst = _make_inst(d, 5) # Full.
	var src_tile = Vector2i(32, 0); var dst_tile = Vector2i(33, 0)
	var src_e = _make_entity(src_inst, src_tile)
	var dst_e = _make_entity(dst_inst, dst_tile)
	GridService.register_item_entity(dst_e)
	var merged = imc.try_merge(src_e, src_tile, dst_tile, 2)
	GridService.unregister_item_entity(dst_e)
	_assert(not merged, "try_merge rejected when destination is full")
	src_e.queue_free(); dst_e.queue_free(); grid.queue_free(); imc.queue_free()

func _test_try_merge_incompatible_rejected():
	print("\n[try_merge_incompatible_rejected]")
	var s = _setup(); var grid = s[0]; var imc = s[1]
	var src_inst = _make_inst(_make_data("sword"))
	var dst_inst = _make_inst(_make_data("shield"))
	var src_tile = Vector2i(34, 0); var dst_tile = Vector2i(35, 0)
	var src_e = _make_entity(src_inst, src_tile)
	var dst_e = _make_entity(dst_inst, dst_tile)
	GridService.register_item_entity(dst_e)
	var merged = imc.try_merge(src_e, src_tile, dst_tile, 1)
	GridService.unregister_item_entity(dst_e)
	_assert(not merged, "try_merge rejected for incompatible item types")
	src_e.queue_free(); dst_e.queue_free(); grid.queue_free(); imc.queue_free()

func _test_move_whole_updates_floor_grid():
	print("\n[move_whole_updates_floor_grid]")
	var s = _setup(); var grid = s[0]; var imc = s[1]
	var inst = _make_inst(_make_data("sword"))
	var src_tile = Vector2i(36, 0); var dst_tile = Vector2i(37, 0)
	var entity = _make_entity(inst, src_tile)
	GridService.register_item_entity(entity)
	grid.add_item(src_tile, inst)
	imc.move_whole(entity, src_tile, dst_tile)
	GridService.unregister_item_entity(entity)
	_assert(not grid.has_items_at(src_tile), "source tile empty after move_whole")
	_assert(grid.has_items_at(dst_tile), "destination tile occupied after move_whole")
	entity.queue_free(); grid.queue_free(); imc.queue_free()

func _test_split_reduces_source():
	print("\n[split_reduces_source]")
	# Test the FloorGrid-level split logic (removes from source, not calling spawn).
	var s = _setup(); var grid = s[0]; var imc = s[1]
	var d = _make_data("coin", true, 10)
	var inst = _make_inst(d, 5)
	var src_tile = Vector2i(38, 0)
	var entity = _make_entity(inst, src_tile)
	grid.add_item(src_tile, inst)
	# Directly exercise remove_from_stack + FloorGrid bookkeeping.
	inst.remove_from_stack(2)
	grid.remove_item(src_tile, inst)
	grid.add_item(src_tile, inst)
	_assert(inst.count == 3, "source stack reduced after split")
	_assert(grid.get_items_at(src_tile).size() == 1, "source tile still tracked")
	entity.queue_free(); grid.queue_free(); imc.queue_free()

func _test_execute_routes_to_move_whole():
	print("\n[execute_routes_to_move_whole]")
	var s = _setup(); var grid = s[0]; var imc = s[1]
	var inst = _make_inst(_make_data("sword"), 1)
	var src_tile = Vector2i(39, 0); var dst_tile = Vector2i(40, 0)
	var entity = _make_entity(inst, src_tile)
	GridService.register_item_entity(entity)
	grid.add_item(src_tile, inst)
	imc.execute(entity, src_tile, dst_tile, 1)
	GridService.unregister_item_entity(entity)
	_assert(grid.has_items_at(dst_tile), "execute correctly routes to move_whole for count==1")
	entity.queue_free(); grid.queue_free(); imc.queue_free()
