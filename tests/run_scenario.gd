extends SceneTree
## Runs one scene scenario: godot --headless --path . --fixed-fps 60 -s res://tests/run_scenario.gd -- res://tests/test_x.gd
func _initialize() -> void:
	var path: String = OS.get_cmdline_user_args()[0]
	var n: Node = load(path).new()
	root.add_child(n)
	n.finished.connect(func(p: int, f: Array):
		print("  %s %d passed, %d failed" % [path.get_file(), p, f.size()])
		for x in f:
			print("    FAIL " + str(x))
		quit(0 if f.is_empty() else 1))
