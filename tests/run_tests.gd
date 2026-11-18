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
	"res://tests/test_audio.gd",
	"res://tests/test_touch_controls.gd",
	"res://tests/test_progression.gd",
	"res://tests/test_line_config.gd",
	"res://tests/test_environment_polish.gd",
	"res://tests/test_gameflow.gd",
]
const SMOKE := "res://tests/test_gameplay_smoke.gd"
## Further scene scenarios, run one after another after the smoke test.
const SCENARIOS := ["res://tests/test_sticky_bounce.gd"]
var _scenario_i := -1

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
	var path: String = SMOKE if _scenario_i < 0 else SCENARIOS[_scenario_i]
	print("  %-36s %3d passed, %d failed" % [path.get_file(), passes, failures.size()])
	_total_pass += passes
	for f in failures:
		_failures.append(str(f))
	if is_instance_valid(_smoke):
		_smoke.queue_free()
		_smoke = null
		await process_frame
	Engine.time_scale = 1.0
	_scenario_i += 1
	if _scenario_i < SCENARIOS.size():
		_smoke = load(SCENARIOS[_scenario_i]).new()
		root.add_child(_smoke)
		_smoke.finished.connect(_on_smoke_finished)
		return
	_finish()


func _finish() -> void:
	if is_instance_valid(_smoke):
		_smoke.queue_free()
		_smoke = null
		await process_frame
	print("")
	for f in _failures:
		print("FAIL ", f)
	print("RESULT: %d passed, %d failed" % [_total_pass, _failures.size()])
	quit(0 if _failures.is_empty() else 1)
