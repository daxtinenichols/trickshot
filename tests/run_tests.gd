extends SceneTree
## Headless test runner:
##   godot --headless --path . --fixed-fps 60 -s res://tests/run_tests.gd
## Optional filter: append `-- <substring>` to run matching tests only.
## Exits with code 1 if any test fails.

const SUITES := [
	"res://tests/test_movement_math.gd",
	"res://tests/test_player_moves.gd",
	"res://tests/test_sandbox_level.gd",
]


func _initialize() -> void:
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
		var suite: TestCase = load(path).new()
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
			if suite.has_method("before_each"):
				await suite.before_each()
			await suite.call(test_name)
			if suite.has_method("after_each"):
				await suite.after_each()
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
