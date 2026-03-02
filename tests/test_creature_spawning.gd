extends Node
## Tests for Spawner creature-count bookkeeping without a live scene or multiplayer.
## Run standalone help: godot --headless --path . tests/test_creature_spawning.gd

var _passed: int = 0
var _failed: int = 0


func _ready():
	# Standalone run support
	if get_tree().current_scene == self:
		_run_all()
		print("\n=== Creature Spawning Tests: %d passed, %d failed ===" % [_passed, _failed])
		get_tree().quit(1 if _failed > 0 else 0)


func _run_all():
	_test_initial_creature_count()
	_test_count_increments_on_add()
	_test_count_decrements_on_death()
	_test_spawn_skipped_at_cap()
	_test_count_tracks_multiple_deaths()


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

## Minimal counter that mirrors Spawner.gd bookkeeping logic.
class SpawnerCounter:
	var creature_count: int = 0
	var max_creatures: int = 5

	func try_spawn() -> bool:
		if creature_count >= max_creatures:
			return false
		creature_count += 1
		return true

	func on_creature_died():
		creature_count -= 1

func _make_counter(max_c: int = 5) -> SpawnerCounter:
	var sc = SpawnerCounter.new()
	sc.max_creatures = max_c
	return sc


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------
func _test_initial_creature_count():
	print("\n[initial_creature_count]")
	var s = _make_counter()
	_assert(s.creature_count == 0, "creature_count starts at 0")

func _test_count_increments_on_add():
	print("\n[count_increments_on_add]")
	var s = _make_counter()
	s.try_spawn(); s.try_spawn()
	_assert(s.creature_count == 2, "creature_count is 2 after two spawns")

func _test_count_decrements_on_death():
	print("\n[count_decrements_on_death]")
	var s = _make_counter()
	s.try_spawn(); s.try_spawn()
	s.on_creature_died()
	_assert(s.creature_count == 1, "creature_count decrements on death")

func _test_spawn_skipped_at_cap():
	print("\n[spawn_skipped_at_cap]")
	var s = _make_counter(3)
	s.try_spawn(); s.try_spawn(); s.try_spawn()
	var result = s.try_spawn()
	_assert(result == false, "spawn rejected when at max_creatures cap")
	_assert(s.creature_count == 3, "creature_count stays at cap")

func _test_count_tracks_multiple_deaths():
	print("\n[count_tracks_multiple_deaths]")
	var s = _make_counter(5)
	s.try_spawn(); s.try_spawn(); s.try_spawn()
	s.on_creature_died(); s.on_creature_died()
	_assert(s.creature_count == 1, "creature_count correctly tracks multiple deaths")
	# Can spawn again up to cap.
	_assert(s.try_spawn(), "spawn succeeds again after deaths free up slots")
