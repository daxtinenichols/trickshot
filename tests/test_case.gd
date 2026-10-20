class_name TestCase
extends RefCounted
## Minimal test base. Methods named test_* are run by tests/run_tests.gd.
## Tests may be coroutines (use await).

var tree: SceneTree
var failures: Array[String] = []
var current_test := ""


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append("%s: %s" % [current_test, msg])


func check_near(actual: float, expected: float, tolerance: float, msg: String) -> void:
	check(absf(actual - expected) <= tolerance,
		"%s (expected %.3f +/- %.3f, got %.3f)" % [msg, expected, tolerance, actual])


func check_between(actual: float, lo: float, hi: float, msg: String) -> void:
	check(actual >= lo and actual <= hi, "%s (expected %.3f..%.3f, got %.3f)" % [msg, lo, hi, actual])
