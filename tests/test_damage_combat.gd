extends Node
## Tests for HealthComponent in complete isolation (no scene required).
## Run standalone: godot --headless --path . tests/test_damage_combat.gd

const _HealthComponent = preload("res://scripts/core/HealthComponent.gd")

var _passed: int = 0
var _failed: int = 0


func _ready():
	# Only run automatically if we are the "main" scene being run.
	if get_tree().current_scene == self:
		_run_all()
		print("\n=== Damage/Combat Tests: %d passed, %d failed ===" % [_passed, _failed])
		get_tree().quit(1 if _failed > 0 else 0)


func _run_all():
	_test_initial_health()
	_test_take_damage()
	_test_heal()
	_test_clamp_below_zero()
	_test_clamp_above_max()
	_test_die_signal()
	_test_is_alive()
	_test_max_health_setter_adjusts_current()
	_test_damaged_signal()
	_test_healed_signal()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
func _make_health(max_hp: int = 10) -> Node:
	var h = _HealthComponent.new()
	add_child(h)
	h.max_health = max_hp
	return h

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
func _test_initial_health():
	print("\n[initial_health]")
	var h = _make_health(10)
	_assert(h.current_health == 10, "current_health starts at max_health")
	_assert(h.max_health == 10, "max_health is 10")
	h.queue_free()

func _test_take_damage():
	print("\n[take_damage]")
	var h = _make_health(10)
	h.take_damage(3)
	_assert(h.current_health == 7, "health reduced by 3")
	h.queue_free()

func _test_heal():
	print("\n[heal]")
	var h = _make_health(10)
	h.take_damage(5)
	h.heal(3)
	_assert(h.current_health == 8, "health restored by 3")
	h.queue_free()

func _test_clamp_below_zero():
	print("\n[clamp_below_zero]")
	var h = _make_health(10)
	h.take_damage(100)
	_assert(h.current_health == 0, "health clamped to 0 on over-damage")
	h.queue_free()

func _test_clamp_above_max():
	print("\n[clamp_above_max]")
	var h = _make_health(10)
	h.heal(100)
	_assert(h.current_health == 10, "health clamped to max_health on over-heal")
	h.queue_free()

var _died_fired := false
var _received_damaged := -1
var _received_healed := -1

func _on_died(): _died_fired = true
func _on_damaged(amt): _received_damaged = amt
func _on_healed(amt): _received_healed = amt

func _test_die_signal():
	print("\n[die_signal]")
	var h = _make_health(10)
	_died_fired = false
	h.died.connect(_on_died)
	h.take_damage(10)
	_assert(_died_fired, "died signal emitted at 0 health")
	h.queue_free()

func _test_is_alive():
	print("\n[is_alive]")
	var h = _make_health(10)
	_assert(h.is_alive(), "is_alive() true when health > 0")
	h.take_damage(10)
	_assert(not h.is_alive(), "is_alive() false when health == 0")
	h.queue_free()

func _test_max_health_setter_adjusts_current():
	print("\n[max_health_setter_adjusts_current]")
	var h = _make_health(10)
	h.max_health = 5
	_assert(h.current_health <= 5, "current_health clamped when max reduced")
	h.queue_free()

func _test_damaged_signal():
	print("\n[damaged_signal]")
	var h = _make_health(10)
	_received_damaged = -1
	h.damaged.connect(_on_damaged)
	h.take_damage(4)
	_assert(_received_damaged == 4, "damaged signal carries correct amount")
	h.queue_free()

func _test_healed_signal():
	print("\n[healed_signal]")
	var h = _make_health(10)
	h.take_damage(5)
	_received_healed = -1
	h.healed.connect(_on_healed)
	h.heal(3)
	_assert(_received_healed == 3, "healed signal carries correct amount")
	h.queue_free()
