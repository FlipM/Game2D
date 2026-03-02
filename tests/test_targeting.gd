extends Node
## Tests for CombatComponent target tracking and nearest-player selection logic.
## Run standalone help: godot --headless --path . tests/test_targeting.gd

const _CombatComponent = preload("res://scripts/core/CombatComponent.gd")

var _passed: int = 0
var _failed: int = 0


func _ready():
	# Standalone run support
	if get_tree().current_scene == self:
		_run_all()
		print("\n=== Targeting Tests: %d passed, %d failed ===" % [_passed, _failed])
		get_tree().quit(1 if _failed > 0 else 0)


func _run_all():
	_test_set_target_emits_signal()
	_test_set_same_target_no_repeat_signal()
	_test_set_null_target_emits()
	_test_nearest_player_returns_closest()
	_test_nearest_player_empty_list_returns_null()


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

class StubPlayer extends Node2D:
	pass

## Standalone nearest-player logic (mirrors Creature._find_nearest_player).
func _find_nearest_player(from: Vector2, candidates: Array) -> Node:
	var nearest: Node = null
	var best_dist: float = INF
	for p in candidates:
		if not is_instance_valid(p): continue
		var d = from.distance_to(p.global_position)
		if d < best_dist:
			best_dist = d
			nearest = p
	return nearest


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------
var _received_target: Node = null
var _signal_count: int = 0

func _on_target_changed(new_target):
	_received_target = new_target
	_signal_count += 1

func _test_set_target_emits_signal():
	print("\n[set_target_emits_signal]")
	var c = _CombatComponent.new()
	add_child(c)
	_received_target = null
	c.target_changed.connect(_on_target_changed)
	var stub = StubPlayer.new()
	add_child(stub)
	c.current_target = stub
	_assert(_received_target == stub, "target_changed emitted when target set")
	stub.queue_free(); c.queue_free()

func _test_set_same_target_no_repeat_signal():
	print("\n[set_same_target_no_repeat_signal]")
	var c = _CombatComponent.new()
	add_child(c)
	_signal_count = 0
	c.target_changed.connect(_on_target_changed)
	var stub = StubPlayer.new()
	add_child(stub)
	c.current_target = stub
	c.current_target = stub
	_assert(_signal_count == 1, "target_changed fires exactly once for the same target")
	stub.queue_free(); c.queue_free()

func _test_set_null_target_emits():
	print("\n[set_null_target_emits]")
	var c = _CombatComponent.new()
	add_child(c)
	var stub = StubPlayer.new()
	add_child(stub)
	c.current_target = stub
	_received_target = stub
	c.target_changed.connect(_on_target_changed)
	c.current_target = null
	_assert(_received_target == null, "target_changed emits null when target cleared")
	stub.queue_free(); c.queue_free()

func _test_nearest_player_returns_closest():
	print("\n[nearest_player_returns_closest]")
	var p1 = StubPlayer.new()
	var p2 = StubPlayer.new()
	p1.global_position = Vector2(100, 0)
	p2.global_position = Vector2(10, 0)
	add_child(p1); add_child(p2)
	var nearest = _find_nearest_player(Vector2.ZERO, [p1, p2])
	_assert(nearest == p2, "nearest player returned when two at different distances")
	p1.queue_free(); p2.queue_free()

func _test_nearest_player_empty_list_returns_null():
	print("\n[nearest_player_empty_list_returns_null]")
	var nearest = _find_nearest_player(Vector2.ZERO, [])
	_assert(nearest == null, "returns null when candidate list is empty")
