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
	# Jump the same distance short of the wall along your path, so both
	# reach it at the same point in the jump (your path along the wall
	# follows the angle you hit it at).
	var reach := 1.5 - 0.38  # wall face minus body radius
	await w.step_until(func() -> bool: return (reach - p.global_position.x) / sin(absf(yaw)) < 1.5, 300, _fwd())
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


## Frames to run from z = 0 to z = -16 over a waist-high hurdle at z = -8,
## either vaulting it (jump at the ideal distance) or jumping over early.
## Returns [frames, speed at the end].
func _hurdle_run(vault: bool) -> Array:
	var w := _world()
	w.add_floor()
	w.add_box(Vector3(0, 0.5, -8), Vector3(6, 1.0, 0.4))
	var p := w.spawn_player(Vector3(0, 0.05, 0))
	await w.step(20)
	var frames := [0]
	var press_z := -7.07 if vault else -5.3
	await w.step_until(func() -> bool:
		frames[0] += 1
		return p.global_position.z < press_z, 300, _fwd())
	await w.press(_fwd_jump())
	var vaulted := p.state == Player.State.VAULT
	await w.step_until(func() -> bool:
		frames[0] += 1
		return p.global_position.z < -16.0, 300, _fwd())
	check(vaulted == vault, "vaulted" if vault else "jumped over without vaulting")
	return [frames[0], p.horizontal_speed()]


func test_vault_beats_jumping_over() -> void:
	var vault := await _hurdle_run(true)
	var jump := await _hurdle_run(false)
	check(vault[1] > jump[1] + 0.5, "a vault comes out faster than a jump over (%.2f vs %.2f m/s)" % [vault[1], jump[1]])
	check(vault[0] <= jump[0], "and gets you there sooner (%d vs %d frames)" % [vault[0], jump[0]])


## Runs at a waist-high thick block (face at z = -8), jumps at press_z and
## mantles onto it. Returns [speed before, speed coming out], or [] if it
## wasn't a mantle.
func _mantle_speeds(press_z: float) -> Array:
	var w := _world()
	w.add_floor()
	w.add_box(Vector3(0, 0.5, -10), Vector3(6, 1.0, 4))
	var p := w.spawn_player(Vector3(0, 0.05, 0))
	await w.step(20)
	await w.step_until(func() -> bool: return p.global_position.z < press_z, 300, _fwd())
	var before := p.horizontal_speed()
	await w.press(_fwd_jump())
	if p.state != Player.State.MANTLE:
		return []
	await w.step_until(func() -> bool: return p.state != Player.State.MANTLE, 90, _fwd())
	return [before, p.horizontal_speed()]


func test_clean_mantle_keeps_your_speed() -> void:
	var clean := await _mantle_speeds(-7.07)
	var sloppy := await _mantle_speeds(-6.7)
	check(clean.size() == 2 and sloppy.size() == 2, "both jumps mantle (%s, %s)" % [clean, sloppy])
	if clean.size() < 2 or sloppy.size() < 2:
		return
	check(clean[1] >= clean[0] * 0.98, "a clean mantle keeps your speed (%.2f -> %.2f)" % clean)
	check(sloppy[1] >= sloppy[0] * 0.95, "a rough one still keeps almost all of it (%.2f -> %.2f)" % sloppy)
	check(clean[1] > sloppy[1] - 0.05 or clean[0] < sloppy[0], "clean comes out at least as fast as rough (%.2f vs %.2f)" % [clean[1], sloppy[1]])


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


## Runs up to full momentum on a long floor heading -z from z = 45.
func _top_speed_runner(w: TestWorld) -> Player:
	w.add_box(Vector3(0, -0.5, -100), Vector3(20, 1, 400))
	var p := w.spawn_player(Vector3(0, 0.05, 45))
	await w.step(20)
	await w.step_until(func() -> bool: return p.momentum >= 0.99, 900, _fwd())
	return p


func test_speed_above_top_speed_carries_while_you_run() -> void:
	var w := _world()
	var p := await _top_speed_runner(w)
	var top := p.tuning.top_speed
	p.velocity = Vector3(0, p.velocity.y, -(top + 4.0))
	await w.step(60, _fwd())
	var after := p.horizontal_speed()
	check(after > top + 2.5, "earned speed carries for a second of running (%.2f, top %.2f)" % [after, top])
	check(after < top + 4.0, "and bleeds slowly (%.2f)" % after)
	await w.step(90)
	check(p.horizontal_speed() < 1.0, "letting go of forward still stops you (%.2f)" % p.horizontal_speed())


func test_perfect_hops_stack_speed_with_no_cap() -> void:
	var w := _world()
	var p := await _top_speed_runner(w)
	var top := p.tuning.top_speed
	await w.press(_fwd_jump())
	for i in 10:
		await w.step_until(func() -> bool: return p.state != Player.State.AIR, 200, _fwd())
		await w.press(_fwd_jump())
	check(p.horizontal_speed() > top + 3.0, "ten perfect hops build well past top speed (%.2f, top %.2f)" % [p.horizontal_speed(), top])


## Runs at full speed into `box` and jumps `press_dz` before its face.
## Returns [speed before, slowest until back on the ground, speed just
## after, the move it made (VAULT or MANTLE, else the last state)].
func test_flow_raises_cruise_and_running_holds_it() -> void:
	var w := _world()
	var p := await _top_speed_runner(w)
	var top := p.tuning.top_speed
	var flow := [3.0]
	p.flow_source = func() -> float: return flow[0]
	await w.step(240, _fwd())
	check_near(p.horizontal_speed(), top + 3.0, 0.1, "flow raises the speed running holds (%.2f, cruise %.2f)" % [p.horizontal_speed(), top + 3.0])
	await w.step(120, _fwd())
	check_near(p.horizontal_speed(), top + 3.0, 0.1, "and it holds on the flat while the combo lives (%.2f)" % p.horizontal_speed())
	flow[0] = 0.0
	await w.step(60, _fwd())
	var after := p.horizontal_speed()
	check(after < top + 2.5 and after > top + 1.5, "with flow gone, the extra bleeds like any overspeed (%.2f)" % after)


func _move_at_speed(box_center: Vector3, box_size: Vector3, press_dz: float) -> Array:
	var w := _world()
	w.add_box(box_center, box_size)
	var p := await _top_speed_runner(w)
	var face_z := box_center.z + box_size.z * 0.5
	await w.step_until(func() -> bool: return p.global_position.z < face_z + press_dz, 900, _fwd())
	var before := p.horizontal_speed()
	await w.press(_fwd_jump())
	var seen := [INF, p.state]
	await w.step_until(func() -> bool:
		seen[0] = minf(seen[0], p.horizontal_speed())
		if p.state == Player.State.VAULT or p.state == Player.State.MANTLE:
			seen[1] = p.state
		return p.state == Player.State.GROUND, 120, _fwd())
	await w.step(3, _fwd())
	return [before, seen[0], p.horizontal_speed(), seen[1]]


func test_vault_keeps_your_run_speed() -> void:
	var r := await _move_at_speed(Vector3(0, 0.5, -8), Vector3(6, 1.0, 0.4), 1.15)
	check(r[3] == Player.State.VAULT, "vaulted (%s)" % Player.State.keys()[r[3]])
	check(r[1] >= r[0] * 0.95, "no slowdown crossing it (%.2f, slowest %.2f)" % [r[0], r[1]])
	check(r[2] >= r[0] - 0.05, "and comes out at least as fast (%.2f -> %.2f)" % [r[0], r[2]])


func test_mantle_at_full_speed_keeps_your_run() -> void:
	var r := await _move_at_speed(Vector3(0, 0.5, -10), Vector3(6, 1.0, 4), 1.15)
	check(r[3] == Player.State.MANTLE, "mantled (%s)" % Player.State.keys()[r[3]])
	check(r[1] >= r[0] * 0.3, "keeps moving forward while pulling up (%.2f, slowest %.2f)" % [r[0], r[1]])
	check(r[2] >= r[0] * 0.95, "comes out at nearly full speed (%.2f -> %.2f)" % [r[0], r[2]])


func test_mantle_from_the_air_keeps_your_run() -> void:
	var r := await _move_at_speed(Vector3(0, 0.8, -10), Vector3(6, 1.6, 4), 2.6)
	check(r[3] == Player.State.MANTLE, "caught the ledge (%s)" % Player.State.keys()[r[3]])
	check(r[1] >= r[0] * 0.3, "keeps moving forward while pulling up (%.2f, slowest %.2f)" % [r[0], r[1]])
	check(r[2] >= r[0] * 0.95, "comes out at nearly full speed (%.2f -> %.2f)" % [r[0], r[2]])
