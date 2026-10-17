extends TestCase
## Steep ramps, quarter pipes and loops: run up them losing speed, run
## upside down when fast enough, drop off when not.

var w: TestWorld


func before_each() -> void:
	w = TestWorld.new()
	tree.root.add_child(w)


func after_each() -> void:
	w.queue_free()
	await tree.process_frame


func _fwd() -> InputFrame:
	return TestWorld.forward_input()


func _settle(pos := Vector3(0, 0.05, 0)) -> Player:
	var p := w.spawn_player(pos)
	await w.step(20)
	return p


func _add_loop(z: float) -> void:
	w.add_surface(SurfaceShapes.loop(Vector3(0, 0, z), 4.5, 3.5, 5.5))


func test_fast_enough_runs_the_loop_upside_down() -> void:
	w.add_floor()
	_add_loop(-70.0)
	var p := await _settle()
	var min_up := [1.0]  # array: lambdas capture locals by value
	var through := await w.step_until(func() -> bool:
		min_up[0] = minf(min_up[0], p.body_up().y)
		return p.global_position.z < -76.0 and p.state == Player.State.GROUND, 900, _fwd())
	check(min_up[0] < -0.9, "ran upside down at the top (body up y %.2f)" % min_up[0])
	check(&"loop" in w.tricks_seen, "loop reported")
	check(through, "came out the other side running (%s at %s)" % [Player.State.keys()[p.state], p.global_position])
	check_near(p.global_position.x, 5.5, 1.2, "beside where you went in")
	check(p.body_up().y > 0.99, "upright again")
	check(not (&"crash" in w.tricks_seen) and not (&"hard_landing" in w.tricks_seen), "no crash")


func test_too_slow_drops_off_the_loop() -> void:
	w.add_floor()
	_add_loop(-3.0)
	var p := await _settle()
	var min_up := 1.0
	var fell := false
	for i in 150:
		await w.step(1, _fwd())
		min_up = minf(min_up, p.body_up().y)
		if Player.State.SURFACE in w.states_seen and p.state == Player.State.AIR:
			fell = true
	check(Player.State.SURFACE in w.states_seen, "started up the loop")
	check(fell, "dropped off")
	check(not (&"loop" in w.tricks_seen), "never got round (body up y %.2f)" % min_up)


func test_run_up_a_steep_ramp_losing_speed() -> void:
	w.add_floor()
	# 80 degrees, 20 m tall: too tall to run all the way up.
	w.add_surface(SurfaceShapes.quarter_pipe(Vector3(0, 0, -40), 5.0, 80.0, 16.0, 4.0))
	var p := await _settle()
	await w.step_until(func() -> bool: return p.state == Player.State.SURFACE, 600, _fwd())
	check(p.state == Player.State.SURFACE, "ran onto the ramp")
	var entry_speed := p.velocity.length()
	var top := 0.0
	var slowest := 999.0
	for i in 240:
		await w.step(1, _fwd())
		top = maxf(top, p.global_position.y)
		if p.state == Player.State.SURFACE:
			slowest = minf(slowest, p.velocity.length())
	check(slowest < entry_speed - 3.0, "slowed going up (%.1f -> %.1f m/s)" % [entry_speed, slowest])
	check_between(top, 3.0, 15.0, "got partway up")
	await w.step_until(func() -> bool: return p.state in [Player.State.GROUND, Player.State.ROLL, Player.State.STUN], 300, _fwd())
	check(p.global_position.y < 0.5, "came back down")


func test_quarter_pipe_launches_you_up() -> void:
	w.add_floor()
	w.add_surface(SurfaceShapes.quarter_pipe(Vector3(0, 0, -40), 3.5, 85.0, 0.0, 4.0))
	var p := await _settle()
	await w.step_until(func() -> bool: return p.state == Player.State.SURFACE, 600, _fwd())
	var launched := await w.step_until(func() -> bool: return p.state == Player.State.AIR, 120, _fwd())
	check(launched, "flew off the lip")
	check(p.velocity.y > 3.0, "going up (vy %.1f)" % p.velocity.y)
	check(p.body_up().y > 0.99, "body upright in the air")


func test_jump_off_a_ramp() -> void:
	w.add_floor()
	w.add_surface(SurfaceShapes.quarter_pipe(Vector3(0, 0, -40), 5.0, 75.0, 10.0, 4.0))
	var p := await _settle()
	await w.step_until(func() -> bool: return p.state == Player.State.SURFACE and p.body_up().y < 0.6, 600, _fwd())
	var n := p.body_up()
	await w.press(InputFrame.make(Vector2(0, 1), true))
	check(p.state == Player.State.AIR, "jumped off")
	check(p.velocity.dot(n) > 4.0, "pushed away from the ramp")


func test_entering_a_ramp_keeps_the_view() -> void:
	w.add_floor()
	w.add_surface(SurfaceShapes.quarter_pipe(Vector3(0, 0, -40), 5.0, 75.0, 10.0, 4.0))
	var p := await _settle()
	await w.step_until(func() -> bool: return p.state == Player.State.SURFACE, 600, _fwd())
	var cam := p.camera.global_basis
	# A few frames on, the view has only tilted as far as the ramp turned it.
	check(cam.z.dot(Vector3(0, 0, 1)) > 0.95, "still looking down the run (%s)" % -cam.z)
