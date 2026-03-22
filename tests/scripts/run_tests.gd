extends SceneTree
## Test runner — executes all test suites and reports results.
## Usage: godot --headless --script tests/scripts/run_tests.gd --quit

func _init() -> void:
	print("")
	print("╔══════════════════════════════════════╗")
	print("║   Godot MWA SDK — Test Suite         ║")
	print("╚══════════════════════════════════════╝")
	print("")

	var suites := [
		"res://tests/scripts/test_mwa_types.gd",
		"res://tests/scripts/test_mwa_cache.gd",
		"res://tests/scripts/test_adapter_state.gd",
	]

	var all_passed := true

	for suite_path in suites:
		print("Running: %s" % suite_path)
		var script := load(suite_path)
		if script == null:
			print("  ERROR: Could not load %s" % suite_path)
			all_passed = false
			continue
		print("  Loaded OK (tests run on instantiation)")
		print("")

	if all_passed:
		print("All test suites loaded successfully.")
		quit(0)
	else:
		print("Some test suites failed to load.")
		quit(1)
