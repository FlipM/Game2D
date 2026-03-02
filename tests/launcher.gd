extends SceneTree
## Standalone launcher for test_item_system.gd.
## Usage: godot --headless --script tests/runner_item_system.gd

func _init():
	var suite = load("res://tests/test_item_system.gd").new()
	root.add_child(suite)
	await root.ready
	suite._run_all()
	print("\n=== Item System Tests: %d passed, %d failed ===" % [suite._passed, suite._failed])
	quit(1 if suite._failed > 0 else 0)
