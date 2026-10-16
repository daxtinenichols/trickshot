extends TestCase
## Skill ceiling: every move works when done roughly, but precise timing,
## angles and speed must give a measurably better result.

var worlds: Array[TestWorld] = []


func after_each() -> void:
	for w in worlds:
		w.queue_free()
	worlds.clear()
	await tree.process_frame


func _world() -> TestWorld:
	var w := TestWorld.new()
	tree.root.add_child(w)
	worlds.append(w)
	return w


func _fwd() -> InputFrame:
	return TestWorld.forward_input()


func _fwd_jump() -> InputFrame:
	return InputFrame.make(Vector2(0, 1), true)


## Run up to speed, jump, and land; returns air frames of that jump.
func _first_hop(w: TestWorld) -> int:
	w.add_floor()
	var p := w.spawn_player(Vector3(0, 0.05, 0))
	await w.step(20)
	await w.step_until(func() -> bool: return p.horizontal_speed() >= 8.0, 900, _fwd())
	await w.press(_fwd_jump())
	var frames := 0
	while p.state == Player.State.AIR and frames < 200:
		await w.step(1, _fwd())
		frames += 1
	return frames


func test_perfect_hop_keeps_more_speed_than_early_hop() -> void:
	# Perfect: press on the first tick after touching down.
	var a := _world()
	var air_frames := await _first_hop(a)
	await a.press(_fwd_jump())
	var perfect := a.player.horizontal_speed()
	check(&"hop" in a.tricks_seen, "hop reported")

	# Early: press 7 ticks before touching down (still inside the buffer).
	var b := _world()
	b.add_floor()
	var p := b.spawn_player(Vector3(0, 0.05, 0))
	await b.step(20)
	await b.step_until(func() -> bool: return p.horizontal_speed() >= 8.0, 900, _fwd())
	await b.press(_fwd_jump())
	await b.step(air_frames - 7, _fwd())
	await b.press(_fwd_jump())
	await b.step_until(func() -> bool: return p.state == Player.State.AIR and p.velocity.y > 0.0, 20, _fwd())
	var early := p.horizontal_speed()
	check(early < perfect - 0.2, "perfect hop (%.2f) beats an early one (%.2f)" % [perfect, early])
	check(early > perfect * 0.85, "an early hop still works")


func test_air_steering_never_adds_speed() -> void:
	var w := _world()
	w.add_floor()
	var p := w.spawn_player(Vector3(0, 0.05, 0))
	await w.step(20)
	await w.step_until(func() -> bool: return p.horizontal_speed() >= 8.0, 900, _fwd())
	await w.press(_fwd_jump())
	var start := p.horizontal_speed()
	var strafe := InputFrame.make(Vector2(1, 0))
	var max_speed := 0.0
	for i in 35:
		p.set_view(p.yaw - 0.04)  # turning right while strafing right
		await w.step(1, strafe)
		max_speed = maxf(max_speed, p.horizontal_speed())
	check(max_speed <= start + 0.01, "no strafe speed gain (%.2f -> %.2f)" % [start, max_speed])
	check(p.velocity.normalized().dot(Vector3.FORWARD) < 0.98, "but you can steer")


func _wallrun_frames(yaw: float) -> int:
	var w := _world()
	w.add_floor()
	w.add_box(Vector3(2.0, 3.0, -30.0), Vector3(1.0, 6.0, 60.0))
	var p := w.spawn_player(Vector3(-1.8, 0.05, 0), yaw)
	await w.step(20)
	await w.step_until(func() -> bool: return p.global_position.x > 0.3, 300, _fwd())
	await w.press(_fwd_jump())
	var started := await w.step_until(func() -> bool: return p.state == Player.State.WALLRUN, 90, _fwd())
	if not started:
		return -1
	var frames := 0
	while p.state == Player.State.WALLRUN and frames < 300:
		await w.step(1, _fwd())
		frames += 1
	return frames


func test_shallow_wallrun_lasts_longer_than_steep() -> void:
	var shallow := await _wallrun_frames(-0.25)
	var steep := await _wallrun_frames(-0.8)
	check(shallow > 0 and steep > 0, "both entries wallrun (%d, %d frames)" % [shallow, steep])
	check(shallow > steep + 20, "shallow entry runs longer (%d vs %d frames)" % [shallow, steep])


func _roll_speed(crouch_at_height: float) -> float:
	var w := _world()
	w.add_floor()
	var p := w.spawn_player(Vector3(0, 12, 0))
	p.velocity = Vector3(0, 0, -7)
	await w.step_until(func() -> bool: return p.global_position.y < crouch_at_height, 200, _fwd())
	await w.press(InputFrame.make(Vector2(0, 1), false, true))
	await w.step_until(func() -> bool: return p.state != Player.State.AIR, 60, _fwd())
	return p.horizontal_speed() if p.state == Player.State.ROLL else -1.0


func test_late_timed_roll_beats_early_roll() -> void:
	var tight := await _roll_speed(1.0)
	var early := await _roll_speed(4.5)
	check(tight > 0.0 and early > 0.0, "both presses roll")
	check(tight > early + 0.5, "crouch right before impact keeps more speed (%.2f vs %.2f)" % [tight, early])


func test_slide_landing_turns_fall_into_speed() -> void:
	var w := _world()
	w.add_floor()
	var p := w.spawn_player(Vector3(0, 4, 0))
	p.velocity = Vector3(0, 0, -6)
	await w.step_until(func() -> bool: return p.global_position.y < 0.9, 200, _fwd())
	var slide := InputFrame.make(Vector2(0, 1), false, true)
	await w.press(slide, 0)
	slide.crouch_pressed = false
	await w.step_until(func() -> bool: return p.state != Player.State.AIR, 60, slide)
	check(p.state == Player.State.SLIDE, "lands into a slide")
	check(p.horizontal_speed() > 9.0, "fall turned into speed (%.2f m/s)" % p.horizontal_speed())


func _vault_exit_speed(press_z: float) -> float:
	var w := _world()
	w.add_floor()
	w.add_box(Vector3(0, 0.5, -8), Vector3(6, 1.0, 0.4))
	var p := w.spawn_player(Vector3(0, 0.05, 0))
	await w.step(20)
	await w.step_until(func() -> bool: return p.global_position.z < press_z, 300, _fwd())
	await w.press(_fwd_jump())
	if p.state != Player.State.VAULT:
		return -1.0
	await w.step_until(func() -> bool: return p.state != Player.State.VAULT, 60, _fwd())
	return p.horizontal_speed()


func test_vault_from_ideal_distance_is_faster() -> void:
	var ideal := await _vault_exit_speed(-7.07)
	var far := await _vault_exit_speed(-6.7)
	check(ideal > 0.0 and far > 0.0, "both distances vault")
	check(ideal > far + 0.4, "ideal distance exits faster (%.2f vs %.2f)" % [ideal, far])


func _kick_push(run_in: float) -> float:
	var w := _world()
	w.add_floor()
	w.add_box(Vector3(0, 3, -2.5), Vector3(6, 6, 1))
	var p := w.spawn_player(Vector3(0, 2, -0.6))
	await w.step(1)
	p.velocity = Vector3(0, 0, -run_in)
	await w.press(InputFrame.make(Vector2.ZERO, false, false, true))
	return p.velocity.z


func test_kick_off_converts_incoming_speed() -> void:
	var slow := await _kick_push(0.0)
	var fast := await _kick_push(8.0)
	check(fast > slow + 2.0, "kicking while moving into the wall pushes harder (%.2f vs %.2f)" % [fast, slow])
