extends Node
## Tests for AStarGrid2D pathfinding configured as in World._setup_astar.
## Run standalone help: godot --headless --path . tests/test_pathing.gd

var _passed: int = 0
var _failed: int = 0

class DiagonalCostGrid extends AStarGrid2D:
	func _compute_cost(from_id: Vector2i, to_id: Vector2i) -> float:
		var d = (to_id - from_id).abs()
		return GameConstants.ASTAR_DIAGONAL_COST if d.x == 1 and d.y == 1 \
		                                         else GameConstants.ASTAR_ORTHOGONAL_COST

var _astar: DiagonalCostGrid = null


func _ready():
	_setup_astar()
	# Standalone run support
	if get_tree().current_scene == self:
		_run_all()
		print("\n=== Pathing Tests: %d passed, %d failed ===" % [_passed, _failed])
		get_tree().quit(1 if _failed > 0 else 0)


func _setup_astar():
	_astar = DiagonalCostGrid.new()
	var size = GameConstants.ARENA_RADIUS * 2 + 1
	_astar.region = Rect2i(-GameConstants.ARENA_RADIUS, -GameConstants.ARENA_RADIUS, size, size)
	_astar.cell_size = Vector2(GameConstants.TILE_SIZE, GameConstants.TILE_SIZE)
	_astar.offset = GameConstants.WORLD_CENTER
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ALWAYS
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_astar.update()


func _run_all():
	_test_path_exists_on_open_grid()
	_test_path_ends_at_destination()
	_test_path_same_tile_empty_or_singular()
	_test_path_avoids_solid_tile()
	_test_diagonal_prefers_orthogonal()
	_test_tile_conversion_inverse()


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

func _get_path(from: Vector2i, to: Vector2i) -> PackedVector2Array:
	return _astar.get_point_path(from, to)


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------
func _test_path_exists_on_open_grid():
	print("\n[path_exists_on_open_grid]")
	var path = _get_path(Vector2i(0, 0), Vector2i(3, 0))
	_assert(path.size() > 0, "path found between two open tiles")

func _test_path_ends_at_destination():
	print("\n[path_ends_at_destination]")
	var dest = Vector2i(2, 2)
	var path = _get_path(Vector2i(-2, -2), dest)
	if path.size() > 0:
		var last_point = path[path.size() - 1]
		var last_tile = Vector2i(
			roundi((last_point.x - GameConstants.WORLD_CENTER.x) / GameConstants.TILE_SIZE),
			roundi((last_point.y - GameConstants.WORLD_CENTER.y) / GameConstants.TILE_SIZE)
		)
		_assert(last_tile == dest, "path last waypoint matches destination tile")
	else:
		_assert(false, "path must be non-empty to check destination")

func _test_path_same_tile_empty_or_singular():
	print("\n[path_same_tile]")
	var path = _get_path(Vector2i(0, 0), Vector2i(0, 0))
	_assert(path.size() <= 1, "path from A to A has at most 1 waypoint")

func _test_path_avoids_solid_tile():
	print("\n[path_avoids_solid_tile]")
	_astar.set_point_solid(Vector2i(1, 0), true)
	var path = _get_path(Vector2i(0, 0), Vector2i(2, 0))
	_astar.set_point_solid(Vector2i(1, 0), false)
	var passed_solid = false
	for wp in path:
		var tile = Vector2i(
			roundi((wp.x - GameConstants.WORLD_CENTER.x) / GameConstants.TILE_SIZE),
			roundi((wp.y - GameConstants.WORLD_CENTER.y) / GameConstants.TILE_SIZE)
		)
		if tile == Vector2i(1, 0):
			passed_solid = true; break
	_assert(not passed_solid, "path does not cross a solid tile")
	_assert(path.size() > 0, "path still exists when single tile is solid")

func _test_diagonal_prefers_orthogonal():
	print("\n[diagonal_prefers_orthogonal]")
	var path = _get_path(Vector2i(0, 0), Vector2i(4, 0))
	var all_orthogonal = true
	for i in range(1, path.size()):
		var p1 = path[i - 1]
		var p2 = path[i]
		var t1 = Vector2i(roundi((p1.x - 576) / 32), roundi((p1.y - 324) / 32))
		var t2 = Vector2i(roundi((p2.x - 576) / 32), roundi((p2.y - 324) / 32))
		var dt = t2 - t1
		if abs(dt.x) == 1 and abs(dt.y) == 1:
			all_orthogonal = false; break
	_assert(all_orthogonal, "straight corridor path uses only orthogonal steps")

func _test_tile_conversion_inverse():
	print("\n[tile_conversion_inverse]")
	var tile = Vector2i(3, -2)
	# Manual world_to_tile(tile_to_world(tile))
	var world = GameConstants.WORLD_CENTER + Vector2(tile) * GameConstants.TILE_SIZE
	var recovered = Vector2i(
		roundi((world.x - GameConstants.WORLD_CENTER.x) / GameConstants.TILE_SIZE),
		roundi((world.y - GameConstants.WORLD_CENTER.y) / GameConstants.TILE_SIZE)
	)
	_assert(recovered == tile, "manual tile↔world is self-inverse")
