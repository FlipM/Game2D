extends Node
## Master test runner — runs every suite and exits with combined pass/fail code.
##
## Run all suites:  godot --headless --path . tests/test_runner_scene.tscn
##
## Each test_*.gd is now an extends Node script. This runner instantiates them,
## adds them to the tree (satisfying project dependencies), and calls _run_all().

const SUITES := [
	"res://tests/test_item_system.gd",
	"res://tests/test_movement.gd",
	"res://tests/test_item_pushing.gd",
	"res://tests/test_attacking.gd",
	"res://tests/test_creature_spawning.gd",
	"res://tests/test_collision.gd",
	"res://tests/test_damage_combat.gd",
	"res://tests/test_targeting.gd",
	"res://tests/test_pathing.gd",
	"res://tests/test_multiplayer_sync.gd",
]

var _total_passed: int = 0
var _total_failed: int = 0


func _ready():
	print("Test Runner: Initializing...")
	
	# Manually provision autoloads if they are missing (common in some headless modes)
	var autoloads = {
		"GameConstants": "res://scripts/core/GameConstants.gd",
		"GridService": "res://scripts/core/GridService.gd"
	}
	for name in autoloads:
		if not get_tree().root.has_node(name):
			var node = load(autoloads[name]).new()
			node.name = name
			get_tree().root.add_child(node)
			print("  [Runner] Manually provisioned autoload: %s" % name)

	# Small delay to ensure engine/autoloads are fully settled.
	await get_tree().create_timer(0.2).timeout
	await _run_all_suites()
	print("\n╔══════════════════════════════════════════════╗")
	print("║  ALL SUITES:  %d passed,  %d failed" % [_total_passed, _total_failed])
	print("╚══════════════════════════════════════════════╝")
	get_tree().quit(1 if _total_failed > 0 else 0)


func _run_all_suites():
	for suite_path in SUITES:
		var script = load(suite_path)
		if not script:
			printerr("run_all_tests: could not load %s" % suite_path)
			_total_failed += 1
			continue

		var suite = script.new()
		add_child(suite)
		
		# Ensure the suite is ready and dependencies are resolved.
		if suite.has_method("_setup_astar"):
			suite.call("_setup_astar")

		if suite.has_method("_run_all"):
			suite._passed = 0
			suite._failed = 0
			suite._run_all()
			
			var name_short = suite_path.get_file().trim_suffix(".gd")
			print("[%-30s] %d passed, %d failed" % [name_short, suite._passed, suite._failed])
			
			_total_passed += suite._passed
			_total_failed += suite._failed

		suite.queue_free()
		# Small yield to allow cleanup if needed.
		await get_tree().process_frame
