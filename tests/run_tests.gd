extends SceneTree
## Headless test runner:
##   godot --headless --path . --fixed-fps 60 -s res://tests/run_tests.gd
## Optional filter: append `-- <substring>` to run matching tests only.
## Exits with code 1 if any test fails.

const SUITES := [
	"res://tests/test_movement_math.gd",
	"res://tests/test_player_moves.gd",
	"res://tests/test_skill.gd",
	"res://tests/test_sandbox_level.gd",
	"res://tests/test_weapons.gd",
	"res://tests/test_settings.gd",
	"res://tests/test_combo.gd",
	"res://tests/test_surfaces.gd",
	"res://tests/test_body_rig.gd",
]


## Collects script errors raised while a test runs.
class ErrorCatcher extends Logger:
	var script_errors: Array[String] = []
	var _mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_SCRIPT:
			return
		_mutex.lock()
		script_errors.append("%s (%s:%d %s)" % [rationale if rationale != "" else code, file.get_file(), line, function])
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass


var _errors := ErrorCatcher.new()


func _initialize() -> void:
	OS.add_logger(_errors)
	_run.call_deferred()


func _run() -> void:
	var filter := ""
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		filter = args[0]
	var passed := 0
	var failed := 0
	var t0 := Time.get_ticks_msec()
	for path: String in SUITES:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			print("\n## %s\n  FAIL  could not load (script error)" % path.get_file())
			failed += 1
			continue
		var suite: TestCase = script.new()
		suite.tree = self
		print("\n## %s" % path.get_file())
		for m in suite.get_method_list():
			var test_name: String = m.name
			if not test_name.begins_with("test_"):
				continue
			if filter != "" and not test_name.contains(filter):
				continue
			suite.current_test = test_name
			var before := suite.failures.size()
			_errors.script_errors.clear()
			if suite.has_method("before_each"):
				await suite.before_each()
			await suite.call(test_name)
			if suite.has_method("after_each"):
				await suite.after_each()
			# A script error aborts the test function silently, skipping its
			# remaining checks, so any script error fails the test.
			for e: String in _errors.script_errors:
				suite.failures.append("%s: script error: %s" % [test_name, e])
			if suite.failures.size() == before:
				passed += 1
				print("  PASS  %s" % test_name)
			else:
				failed += 1
				print("  FAIL  %s" % test_name)
				for i in range(before, suite.failures.size()):
					print("        - %s" % suite.failures[i])
	print("\n%d passed, %d failed (%.1fs)" % [passed, failed, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(1 if failed > 0 else 0)
