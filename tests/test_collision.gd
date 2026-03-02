extends Node
## Tests for GridService.is_tile_occupied using mock entities in scene groups.
## Run standalone help: godot --headless --path . tests/test_collision.gd

var _passed: int = 0
var _failed: int = 0


func _ready():
	# Standalone run support
	if get_tree().current_scene == self:
		_run_all()
		print("\n=== Collision Tests: %d passed, %d failed ===" % [_passed, _failed])
		get_tree().quit(1 if _failed > 0 else 0)


func _run_all():
	_test_tile_free_when_no_entities()
	_test_tile_occupied_by_entity_position()
	_test_tile_occupied_by_reservation()
	_test_excluded_entity_does_not_block()
	_test_two_entities_different_tiles()


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

class StubMovement extends Node:
	var target_position: Vector2 = Vector2.ZERO

class StubEntity extends Node2D:
	var _stub_mc: StubMovement

	func setup(pos: Vector2, target: Vector2 = pos):
		global_position = pos
		_stub_mc = StubMovement.new()
		_stub_mc.name = "MovementComponent"
		_stub_mc.target_position = target
		add_child(_stub_mc)

func _make_entity(tile: Vector2i, group: String) -> StubEntity:
	var e = StubEntity.new()
	e.setup(GridService.tile_to_world(tile))
	add_child(e)
	e.add_to_group(group)
	return e

func _make_entity_with_reservation(pos_tile: Vector2i,
		res_tile: Vector2i, group: String) -> StubEntity:
	var e = StubEntity.new()
	e.setup(GridService.tile_to_world(pos_tile), GridService.tile_to_world(res_tile))
	add_child(e)
	e.add_to_group(group)
	return e


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------
func _test_tile_free_when_no_entities():
	print("\n[tile_free_when_no_entities]")
	var world_pos = GridService.tile_to_world(Vector2i(99, 99))
	_assert(not GridService.is_tile_occupied(world_pos), "empty tile is not occupied")

func _test_tile_occupied_by_entity_position():
	print("\n[tile_occupied_by_entity_position]")
	var tile = Vector2i(20, 20)
	var e = _make_entity(tile, "players")
	_assert(GridService.is_tile_occupied(GridService.tile_to_world(tile)),
		"tile occupied by entity's current position")
	e.queue_free()

func _test_tile_occupied_by_reservation():
	print("\n[tile_occupied_by_reservation]")
	var pos_tile = Vector2i(21, 21)
	var res_tile = Vector2i(22, 21)
	var e = _make_entity_with_reservation(pos_tile, res_tile, "creatures")
	_assert(GridService.is_tile_occupied(GridService.tile_to_world(res_tile)),
		"tile occupied by entity's reserved target_position")
	e.queue_free()

func _test_excluded_entity_does_not_block():
	print("\n[excluded_entity_does_not_block]")
	var tile = Vector2i(23, 23)
	var e = _make_entity(tile, "players")
	_assert(not GridService.is_tile_occupied(GridService.tile_to_world(tile), e),
		"excluded entity does not mark tile as occupied")
	e.queue_free()

func _test_two_entities_different_tiles():
	print("\n[two_entities_different_tiles]")
	var tile_a = Vector2i(24, 0)
	var tile_b = Vector2i(25, 0)
	var ea = _make_entity(tile_a, "players")
	var eb = _make_entity(tile_b, "creatures")
	_assert(GridService.is_tile_occupied(GridService.tile_to_world(tile_a)), "tile A occupied")
	_assert(GridService.is_tile_occupied(GridService.tile_to_world(tile_b)), "tile B occupied")
	_assert(not GridService.is_tile_occupied(GridService.tile_to_world(Vector2i(26, 0))),
		"unrelated tile is free")
	ea.queue_free(); eb.queue_free()
