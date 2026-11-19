extends SceneTree
## Runs unit suites: godot --headless --path . -s res://tests/run_unit.gd -- res://tests/test_tricks.gd [...]
func _initialize() -> void:
	var fails := 0
	for path in OS.get_cmdline_user_args():
		var suite: TestCase = load(path).new()
		suite.run_all()
		print("  %s %d passed, %d failed" % [path.get_file(), suite.passes, suite.failures.size()])
		for f in suite.failures:
			print("    FAIL " + f)
		fails += suite.failures.size()
	quit(0 if fails == 0 else 1)
