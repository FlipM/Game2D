extends Node
## Tests for CombatComponent: attack mechanics, range, damage calculation, signals.
## Run standalone help: godot --headless --path . tests/test_attacking.gd

const _CombatComponent = preload("res://scripts/core/CombatComponent.gd")

var _passed: int = 0
var _failed: int = 0


func _ready():
	# Standalone run support
	if get_tree().current_scene == self:
		_run_all()
		print("\n=== Attacking Tests: %d passed, %d failed ===" % [_passed, _failed])
		get_tree().quit(1 if _failed > 0 else 0)


func _run_all():
	_test_is_in_range_true()
	_test_is_in_range_false()
	_test_perform_attack_calls_take_damage()
	_test_damage_never_negative()
	_test_defense_reduces_damage()
	_test_handle_combat_skips_before_interval()
	_test_target_changed_signal()


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

var _received_target: Node = null

func _on_target_changed(new_target):
	_received_target = new_target

class StubTarget extends Node:
	var damage_received: int = 0
	var global_position: Vector2 = Vector2.ZERO
	# CombatComponent checks target.get("combat")
	var combat = {"defense_power": 0}
	func take_damage(amount: int): damage_received += amount

func _make_combat(attack_power: int = 5, defense: int = 0) -> Node:
	var c = _CombatComponent.new()
	c.attack_power = attack_power
	c.defense_power = defense
	c.attack_interval = 1.5
	c.melee_range_multiplier = GameConstants.MELEE_RANGE_MULTIPLIER
	add_child(c)
	return c

func _make_attacker(pos: Vector2) -> Node2D:
	var a = Node2D.new()
	a.global_position = pos
	add_child(a)
	return a


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------
func _test_is_in_range_true():
	print("\n[is_in_range_true]")
	var c = _make_combat()
	var attacker = _make_attacker(Vector2.ZERO)
	var target = StubTarget.new()
	target.global_position = Vector2(GameConstants.TILE_SIZE, 0)
	add_child(target)
	_assert(c.is_in_range(attacker, target), "in range at 1 tile distance")
	attacker.queue_free(); target.queue_free(); c.queue_free()

func _test_is_in_range_false():
	print("\n[is_in_range_false]")
	var c = _make_combat()
	var attacker = _make_attacker(Vector2.ZERO)
	var target = StubTarget.new()
	target.global_position = Vector2(GameConstants.TILE_SIZE * 5, 0)
	add_child(target)
	_assert(not c.is_in_range(attacker, target), "out of range at 5 tile distance")
	attacker.queue_free(); target.queue_free(); c.queue_free()

func _test_perform_attack_calls_take_damage():
	print("\n[perform_attack_calls_take_damage]")
	var c = _make_combat(10, 0)
	var target = StubTarget.new()
	add_child(target)
	for _i in range(20):
		c.perform_attack(target)
	_assert(target.damage_received > 0, "repeated attacks deal some damage total")
	target.queue_free(); c.queue_free()

func _test_damage_never_negative():
	print("\n[damage_never_negative]")
	var c = _make_combat(1, 0)
	var target = StubTarget.new()
	add_child(target)
	for _i in range(50):
		c.perform_attack(target)
	_assert(target.damage_received >= 0, "accumulated damage is never negative")
	target.queue_free(); c.queue_free()

func _test_defense_reduces_damage():
	print("\n[defense_reduces_damage]")
	var c = _make_combat(1, 0) # attack_power=1
	var target = StubTarget.new()
	target.combat.defense_power = 100 # target has high defense
	add_child(target)
	for _i in range(30):
		c.perform_attack(target)
	_assert(target.damage_received == 0, "high defense absorbs all damage")
	target.queue_free(); c.queue_free()

func _test_handle_combat_skips_before_interval():
	print("\n[handle_combat_skips_before_interval]")
	var c = _make_combat(10, 0)
	c.attack_timer = 0.0
	var attacker = _make_attacker(Vector2.ZERO)
	var target = StubTarget.new()
	target.global_position = Vector2.ZERO
	add_child(target)
	c.handle_combat(attacker, target)
	_assert(target.damage_received == 0, "handle_combat skips when timer < interval")
	attacker.queue_free(); target.queue_free(); c.queue_free()

func _test_target_changed_signal():
	print("\n[target_changed_signal]")
	var c = _make_combat()
	_received_target = null
	c.target_changed.connect(_on_target_changed)
	var target = StubTarget.new()
	add_child(target)
	c.current_target = target
	_assert(_received_target == target, "target_changed emitted with new target")
	_received_target = null
	c.current_target = target
	_assert(_received_target == null, "target_changed not re-emitted for same target")
	target.queue_free(); c.queue_free()
