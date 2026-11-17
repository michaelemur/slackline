class_name TestCase
extends RefCounted
## Minimal assertion helper for the headless test runner.

var failures: Array[String] = []
var passes: int = 0
var current: String = ""


func check(cond: bool, msg: String) -> void:
	if cond:
		passes += 1
	else:
		failures.append("[%s] %s" % [current, msg])


func near(actual: float, expected: float, rel_tol: float, msg: String) -> void:
	var err := absf(actual - expected) / maxf(absf(expected), 1e-9)
	check(err <= rel_tol, "%s: got %.4f expected %.4f (rel err %.1f%% > %.1f%%)"
		% [msg, actual, expected, err * 100.0, rel_tol * 100.0])


func run_all() -> void:
	for m in get_method_list():
		var name: String = m["name"]
		if name.begins_with("test_"):
			current = name
			call(name)
