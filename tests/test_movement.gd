extends Node
## Tests for GridService tile math and MovementComponent pure-state logic.
## Run standalone help: godot --headless --path . tests/test_movement.gd

const _MovementComponent = preload("res://scripts/core/MovementComponent.gd")

var _passed: int = 0
var _failed: int = 0


func _init():
	_run_all()
	print("\n=== Movement Tests: %d passed, %d failed ===" % [_passed, _failed])
	if get_tree(): get_tree().quit(1 if _failed > 0 else 0)


func _run_all():
	_test_tile_to_world_round_trip()
	_test_world_to_tile_round_trip()
	_test_adjacent_tiles()
	_test_teleport_clears_path()
	_test_move_to_empty_path_noop()
	_test_try_move_blocked_while_moving()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
func _make_mc() -> Node:
	var body = CharacterBody2D.new()
	var mc = _MovementComponent.new()
	body.add_child(mc)
	add_child(body)
	return mc

func _assert(condition: bool, description: String):
	if condition:
		print("  PASS: %s" % description)
		_passed += 1
	else:
		printerr("  FAIL: %s" % description)
		_failed += 1


# ---------------------------------------------------------------------------
# Tests — GridService tile math (autoload, always available)
# ---------------------------------------------------------------------------
func _test_tile_to_world_round_trip():
	print("\n[tile_to_world_round_trip]")
	var coords = Vector2i(3, -2)
	var world = GridService.tile_to_world(coords)
	var back = GridService.world_to_tile(world)
	_assert(back == coords, "tile→world→tile round-trip preserves coords")

func _test_world_to_tile_round_trip():
	print("\n[world_to_tile_round_trip]")
	var tile = Vector2i(0, 0)
	var world = GridService.tile_to_world(tile)
	_assert(GridService.world_to_tile(world) == tile, "world_to_tile recovers zero tile")

	var tile2 = Vector2i(-5, 4)
	var world2 = GridService.tile_to_world(tile2)
	_assert(GridService.world_to_tile(world2) == tile2, "world_to_tile recovers negative tile")

func _test_adjacent_tiles():
	print("\n[adjacent_tiles]")
	var center = Vector2i(0, 0)
	var world_center = GridService.tile_to_world(center)
	var ts = GameConstants.TILE_SIZE
	var right_world = world_center + Vector2(ts, 0)
	_assert(GridService.world_to_tile(right_world) == Vector2i(1, 0),
		"tile one step right is (1,0)")
	var diag_world = world_center + Vector2(ts, ts)
	_assert(GridService.world_to_tile(diag_world) == Vector2i(1, 1),
		"tile one diagonal step is (1,1)")


# ---------------------------------------------------------------------------
# Tests — MovementComponent state logic (no physics world)
# ---------------------------------------------------------------------------
func _test_teleport_clears_path():
	print("\n[teleport_clears_path]")
	var mc = _make_mc()
	mc.current_path = [Vector2(100, 100), Vector2(200, 200)]
	mc.is_moving = true

	mc.teleport(Vector2(50, 50))

	_assert(mc.target_position == Vector2(50, 50), "teleport sets target_position")
	_assert(mc.current_path.size() == 0, "teleport clears current_path")
	_assert(mc.is_moving == false, "teleport sets is_moving = false")
	mc.get_parent().queue_free()

func _test_move_to_empty_path_noop():
	print("\n[move_to_empty_path_noop]")
	var mc = _make_mc()
	mc.is_moving = false
	mc.move_to([])
	_assert(not mc.is_moving, "move_to empty path does not set is_moving")
	_assert(mc.current_path.size() == 0, "move_to empty path leaves current_path empty")
	mc.get_parent().queue_free()

func _test_try_move_blocked_while_moving():
	print("\n[try_move_blocked_while_moving]")
	var mc = _make_mc()
	mc.is_moving = true
	# mc._world is not set, so it should return false anyway
	var ok = mc.try_move(Vector2.RIGHT)
	_assert(not ok, "try_move returns false when already moving")
	mc.get_parent().queue_free()
