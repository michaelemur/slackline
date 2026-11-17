extends SceneTree
## Headless test runner.
##   godot --headless --path . --import
##   godot --headless --path . -s res://tests/run_tests.gd
## Exit code 0 = all passed. Unit suites run first, then a scripted gameplay
## smoke test drives the real main scene through physics frames.

const UNIT_SUITES := [
	"res://tests/test_solver.gd",
	"res://tests/test_balance.gd",
	"res://tests/test_tricks.gd",
	"res://tests/test_character.gd",
	"res://tests/test_body.gd",
	"res://tests/test_rebound_lab.gd",
	"res://tests/test_cinematic.gd",
	"res://tests/test_touch_controls.gd",
]
const SMOKE := "res://tests/test_gameplay_smoke.gd"

var _total_pass := 0
var _failures: Array[String] = []
var _smoke: Node


func _initialize() -> void:
	for path in UNIT_SUITES:
		if not ResourceLoader.exists(path):
			continue
		var suite: TestCase = load(path).new()
		var t0 := Time.get_ticks_msec()
		suite.run_all()
		print("  %-36s %3d passed, %d failed (%d ms)" % [path.get_file(), suite.passes,
			suite.failures.size(), Time.get_ticks_msec() - t0])
		_total_pass += suite.passes
		_failures.append_array(suite.failures)
	if ResourceLoader.exists(SMOKE):
		_smoke = load(SMOKE).new()
		root.add_child(_smoke)
		_smoke.finished.connect(_on_smoke_finished)
	else:
		_finish()


func _on_smoke_finished(passes: int, failures: Array) -> void:
	print("  %-36s %3d passed, %d failed" % [SMOKE.get_file(), passes, failures.size()])
	_total_pass += passes
	for f in failures:
		_failures.append(str(f))
	_finish()


func _finish() -> void:
	print("")
	for f in _failures:
		print("FAIL ", f)
	print("RESULT: %d passed, %d failed" % [_total_pass, _failures.size()])
	quit(0 if _failures.is_empty() else 1)
