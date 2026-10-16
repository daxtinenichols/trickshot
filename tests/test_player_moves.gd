extends TestCase
## Integration tests: a real Player in real physics, driven by scripted input.
## Coordinates: the player faces -Z at yaw 0.

var w: TestWorld


func before_each() -> void:
	w = TestWorld.new()
	tree.root.add_child(w)


func after_each() -> void:
	w.queue_free()
	await tree.process_frame


func _fwd() -> InputFrame:
	return TestWorld.forward_input()


func _fwd_jump() -> InputFrame:
	return InputFrame.make(Vector2(0, 1), true)


func _fwd_crouch() -> InputFrame:
	return InputFrame.make(Vector2(0, 1), false, true)


func _settle(pos := Vector3(0, 0.05, 0), yaw := 0.0) -> Player:
	var p := w.spawn_player(pos, yaw)
	await w.step(20)
	return p


## Run forward until momentum gives at least `speed`.
func _run_to(speed: float, max_frames := 900) -> void:
	await w.step_until(func() -> bool: return w.player.horizontal_speed() >= speed, max_frames, _fwd())


# ------------------------------------------------------------------ basics

func test_settles_on_floor() -> void:
	w.add_floor()
	var p := await _settle(Vector3(0, 1, 0))
	await w.step(30)
	check(p.state == Player.State.GROUND, "standing on the floor (state %s)" % Player.State.keys()[p.state])
	check_near(p.global_position.y, 0.0, 0.05, "feet on the floor")


func test_run_speed_without_momentum() -> void:
	w.add_floor()
	var p := await _settle()
	await w.step(40, _fwd())
	check_between(p.horizontal_speed(), p.tuning.run_speed * 0.9, p.tuning.run_speed * 1.15, "quickly reaches run speed")
	check(p.velocity.z < 0.0, "moves the way it faces")


func test_momentum_builds_to_top_speed() -> void:
	w.add_floor()
	var p := await _settle()
	await w.step(600, _fwd())
	check(p.momentum > 0.95, "momentum fills while flowing (got %.2f)" % p.momentum)
	check_between(p.horizontal_speed(), p.tuning.top_speed * 0.95, p.tuning.top_speed * 1.02, "top speed reached")


func test_stopping_drains_momentum() -> void:
	w.add_floor()
	var p := await _settle()
	await w.step(400, _fwd())
	await w.step(150)
	check(p.horizontal_speed() < 0.05, "stops when input released")
	check(p.momentum < 0.2, "momentum drains when stopped (got %.2f)" % p.momentum)


func test_jump_height() -> void:
	w.add_floor()
	var p := await _settle()
	await w.press(InputFrame.make(Vector2.ZERO, true))
	var max_y := 0.0
	for i in 60:
		await w.step(1)
		max_y = maxf(max_y, p.global_position.y)
	check_between(max_y, 1.1, 1.35, "jump apex")
	check(p.state == Player.State.GROUND, "lands again")


func test_bunny_hop_keeps_speed() -> void:
	w.add_floor()
	var p := await _settle()
	await _run_to(8.0)
	var start := p.horizontal_speed()
	await w.step(240, _fwd_jump())
	check(p.horizontal_speed() >= start * 0.97, "chained jumps keep speed (%.2f -> %.2f)" % [start, p.horizontal_speed()])


func test_coyote_jump_after_running_off_ledge() -> void:
	w.add_box(Vector3(0, -0.5, 0), Vector3(10, 1, 10))  # ends at z = -5
	w.add_box(Vector3(0, -20.5, 0), Vector3(400, 1, 400))
	var p := await _settle()
	var off := await w.step_until(func() -> bool: return p.state == Player.State.AIR, 200, _fwd())
	check(off, "ran off the ledge")
	await w.step(3, _fwd())
	await w.press(_fwd_jump())
	check_near(p.velocity.y, p.tuning.jump_velocity - p.tuning.gravity / 60.0, 0.3, "late jump still works")


func test_no_coyote_jump_long_after_ledge() -> void:
	w.add_box(Vector3(0, -0.5, 0), Vector3(10, 1, 10))
	w.add_box(Vector3(0, -20.5, 0), Vector3(400, 1, 400))
	var p := await _settle()
	await w.step_until(func() -> bool: return p.state == Player.State.AIR, 200, _fwd())
	await w.step(20, _fwd())
	await w.press(_fwd_jump())
	check(p.velocity.y < 0.0, "too late to jump")


# ------------------------------------------------------------------ crouch / slide

func test_slide_boosts_then_ends_on_flat() -> void:
	w.add_floor()
	var p := await _settle()
	await _run_to(6.5)
	var start := p.horizontal_speed()
	await w.press(_fwd_crouch(), 1)
	check(p.state == Player.State.SLIDE, "slide starts")
	check(p.horizontal_speed() > start + p.tuning.slide_boost * 0.7, "slide boost (%.2f -> %.2f)" % [start, p.horizontal_speed()])
	var ended := await w.step_until(func() -> bool: return p.state != Player.State.SLIDE, 600, _fwd_crouch())
	check(ended, "slide ends on flat ground")
	check(p.state == Player.State.CROUCH, "ends crouched while crouch is held")


func test_no_slide_when_slow() -> void:
	w.add_floor()
	var p := await _settle()
	await w.step(5, _fwd())
	await w.press(_fwd_crouch(), 2)
	check(p.state == Player.State.CROUCH, "slow crouch is just a crouch")


func test_slide_jump_keeps_speed() -> void:
	w.add_floor()
	var p := await _settle()
	await _run_to(6.5)
	await w.press(_fwd_crouch(), 5)
	var sliding := p.horizontal_speed()
	await w.press(InputFrame.make(Vector2(0, 1), true, true))
	check(p.state == Player.State.AIR, "slide jump goes airborne")
	check(p.horizontal_speed() >= sliding * 0.95, "slide jump keeps speed")
	check(&"slide_jump" in w.tricks_seen, "slide jump trick reported")


func test_slide_downhill_gains_speed() -> void:
	# 15 degree ramp descending toward -Z.
	w.add_box(Vector3(0, -5, -20), Vector3(10, 1, 60), -15.0)
	w.add_box(Vector3(0, -40, 0), Vector3(400, 1, 400))
	var p := await _settle(Vector3(0, 3, 0))
	await _run_to(6.0, 120)
	await w.press(_fwd_crouch(), 1)
	check(p.state == Player.State.SLIDE, "slide starts on the ramp")
	var start := p.horizontal_speed()
	await w.step(60, _fwd_crouch())
	check(p.state == Player.State.SLIDE, "still sliding downhill")
	check(p.horizontal_speed() > start + 1.0, "slope speeds the slide up (%.2f -> %.2f)" % [start, p.horizontal_speed()])


func test_crouch_under_low_ceiling_stays_crouched() -> void:
	w.add_floor()
	w.add_box(Vector3(0, 2.0, -5), Vector3(6, 1.4, 4))  # underside at y = 1.3, z -3..-7
	var p := await _settle()
	var crouch_walk := InputFrame.make(Vector2(0, 1), false, true)
	crouch_walk.crouch_pressed = false
	await w.press(InputFrame.make(Vector2.ZERO, false, true), 5)
	var under := await w.step_until(func() -> bool: return p.global_position.z < -5.0, 300, crouch_walk)
	check(under, "crouch-walked under the ceiling")
	await w.step(10)
	check(p.state == Player.State.CROUCH, "can't stand up under the ceiling")
	var out := await w.step_until(func() -> bool: return p.global_position.z < -8.0, 300, _fwd())
	check(out, "walked out still crouched")
	await w.step(5, _fwd())
	check(p.state == Player.State.GROUND, "stands once clear")


# ------------------------------------------------------------------ vault / mantle

func test_vault_over_low_wall() -> void:
	w.add_floor()
	w.add_box(Vector3(0, 0.5, -8), Vector3(6, 1.0, 0.4))  # face at z = -7.8, top 1.0
	var p := await _settle()
	await w.step_until(func() -> bool: return p.global_position.z < -6.8, 300, _fwd())
	var before := p.horizontal_speed()
	await w.press(_fwd_jump())
	check(p.state == Player.State.VAULT, "vault starts on jump near the wall")
	await w.step(30, _fwd())
	check(p.global_position.z < -8.5, "ended up on the far side (z %.2f)" % p.global_position.z)
	check(p.state == Player.State.GROUND, "back on the ground")
	check(p.horizontal_speed() >= before * 0.85, "speed kept through the vault (%.2f -> %.2f)" % [before, p.horizontal_speed()])


func test_running_into_low_wall_without_jump_stops() -> void:
	w.add_floor()
	w.add_box(Vector3(0, 0.5, -8), Vector3(6, 1.0, 0.4))
	var p := await _settle()
	await w.step(150, _fwd())
	check(p.global_position.z > -7.8, "blocked by the wall")
	check(not (Player.State.VAULT in w.states_seen), "no vault without a jump")


func test_step_up_onto_waist_high_block() -> void:
	w.add_floor()
	w.add_box(Vector3(0, 0.5, -10), Vector3(6, 1.0, 4))  # thick: face at z = -8
	var p := await _settle()
	await w.step_until(func() -> bool: return p.global_position.z < -7.0, 300, _fwd())
	await w.press(_fwd_jump())
	check(p.state == Player.State.MANTLE, "low thick block is mantled, not vaulted")
	await w.step(30, _fwd())
	check_near(p.global_position.y, 1.0, 0.08, "standing on top")


func test_air_mantle_catches_ledge() -> void:
	w.add_floor()
	w.add_box(Vector3(0, 0.8, -10), Vector3(6, 1.6, 4))  # face at z = -8, top 1.6
	var p := await _settle()
	await w.step_until(func() -> bool: return p.global_position.z < -5.2, 300, _fwd())
	await w.press(_fwd_jump())
	var caught := await w.step_until(func() -> bool: return p.state == Player.State.MANTLE, 60, _fwd())
	check(caught, "ledge caught mid-air")
	await w.step_until(func() -> bool: return p.state == Player.State.GROUND, 90, _fwd())
	check_near(p.global_position.y, 1.6, 0.08, "pulled up on top")
	check(p.state == Player.State.GROUND, "running on top")


# ------------------------------------------------------------------ walls

func _add_side_wall() -> void:
	# Long wall on the right: face at x = 1.5, from z = 0 to z = -60.
	w.add_box(Vector3(2.0, 3.0, -30.0), Vector3(1.0, 6.0, 60.0))


func _enter_wallrun() -> bool:
	_add_side_wall()
	w.add_floor()
	var p := await _settle(Vector3(-1.8, 0.05, 0), -0.3)
	await w.step_until(func() -> bool: return p.global_position.x > 0.3, 300, _fwd())
	await w.press(_fwd_jump())
	return await w.step_until(func() -> bool: return p.state == Player.State.WALLRUN, 90, _fwd())


func test_wallrun_starts_and_carries_you() -> void:
	var ok := await _enter_wallrun()
	check(ok, "wallrun starts when jumping into the wall at an angle")
	if not ok:
		return
	var p := w.player
	var z0 := p.global_position.z
	var y0 := p.global_position.y
	await w.step(36, _fwd())
	check(p.state == Player.State.WALLRUN, "still wallrunning after 0.6 s")
	check(z0 - p.global_position.z > 3.5, "travelled along the wall (%.2f m)" % (z0 - p.global_position.z))
	check(p.global_position.y > y0 - 0.4, "barely loses height")
	check(&"wallrun" in w.tricks_seen, "wallrun trick reported")


func test_wallrun_times_out() -> void:
	var ok := await _enter_wallrun()
	check(ok, "wallrun starts")
	if not ok:
		return
	var p := w.player
	var limit := int(p.tuning.wallrun_max_time * 60.0) + 10
	var left := await w.step_until(func() -> bool: return p.state != Player.State.WALLRUN, limit, _fwd())
	check(left, "wallrun ends by its time limit")
	await w.step(10, _fwd())
	check(p.state != Player.State.WALLRUN, "doesn't re-stick to the same wall")


func test_wall_jump_from_wallrun() -> void:
	var ok := await _enter_wallrun()
	check(ok, "wallrun starts")
	if not ok:
		return
	var p := w.player
	await w.step(10, _fwd())
	await w.press(_fwd_jump())
	check(p.state == Player.State.AIR, "airborne after the wall jump")
	check(p.velocity.x < -4.0, "pushed off the wall (vx %.2f)" % p.velocity.x)
	check(p.velocity.y > 5.0, "launched upward")
	check(&"wall_jump" in w.tricks_seen, "wall jump trick reported")


func test_steer_away_leaves_wallrun() -> void:
	var ok := await _enter_wallrun()
	check(ok, "wallrun starts")
	if not ok:
		return
	var p := w.player
	await w.step(3, InputFrame.make(Vector2(-1, 0)))
	check(p.state != Player.State.WALLRUN, "pulling away from the wall detaches")


func _add_front_wall(height: float) -> void:
	# Face at z = -6.
	w.add_box(Vector3(0, height * 0.5, -8.0), Vector3(8, height, 4))


func test_wall_climb_on_tall_wall() -> void:
	w.add_floor()
	_add_front_wall(8.0)
	var p := await _settle()
	await w.step_until(func() -> bool: return p.global_position.z < -4.9, 300, _fwd())
	await w.press(_fwd_jump())
	check(p.state == Player.State.WALLCLIMB, "jumping at a wall head-on starts a climb")
	var max_y := 0.0
	for i in 60:
		await w.step(1, InputFrame.make(Vector2(0, 1), false))
		max_y = maxf(max_y, p.global_position.y)
	check(max_y > 2.0, "climbed higher than a jump (%.2f m)" % max_y)
	check(max_y < 4.0, "but only a few steps")


func test_wall_climb_into_mantle() -> void:
	w.add_floor()
	_add_front_wall(3.0)
	var p := await _settle()
	await w.step_until(func() -> bool: return p.global_position.z < -4.9, 300, _fwd())
	await w.press(_fwd_jump())
	await w.step(45, _fwd())
	check(Player.State.MANTLE in w.states_seen, "climb ends in a mantle")
	check_near(p.global_position.y, 3.0, 0.08, "on top of the 3 m wall")


func test_wall_climb_kick_turns_you_around() -> void:
	w.add_floor()
	_add_front_wall(8.0)
	var p := await _settle()
	await w.step_until(func() -> bool: return p.global_position.z < -4.9, 300, _fwd())
	await w.press(_fwd_jump())
	await w.step(12, _fwd())
	check(p.state == Player.State.WALLCLIMB, "climbing")
	await w.press(_fwd_jump())
	check(p.velocity.z > 4.0, "kicked away from the wall")
	await w.step(15)
	check(absf(absf(p.yaw) - PI) < 0.05, "turned to face away (yaw %.2f)" % p.yaw)


# ------------------------------------------------------------------ landings

func _drop(crouch_before_landing: bool) -> Player:
	w.add_floor()
	var p := w.spawn_player(Vector3(0, 12, 0))
	p.velocity = Vector3(0, 0, -6)
	await w.step_until(func() -> bool: return p.global_position.y < 1.2, 200, _fwd())
	if crouch_before_landing:
		await w.press(_fwd_crouch())
	await w.step_until(func() -> bool: return p.state != Player.State.AIR, 60, _fwd())
	return p


func test_landing_roll_keeps_speed() -> void:
	var p := await _drop(true)
	check(p.state == Player.State.ROLL, "timed crouch rolls (state %s)" % Player.State.keys()[p.state])
	check(p.horizontal_speed() >= 6.0, "speed kept through the roll (%.2f)" % p.horizontal_speed())
	await w.step(40, _fwd())
	check(p.state == Player.State.GROUND, "back to running after the roll")
	check(&"landing_roll" in w.tricks_seen, "roll trick reported")


func test_hard_landing_without_roll() -> void:
	var p := await _drop(false)
	check(p.state == Player.State.STUN, "big fall without a roll stuns")
	check(p.horizontal_speed() < 6.0 * p.tuning.hard_landing_keep + 0.5, "and costs speed")


func test_small_drop_is_a_normal_landing() -> void:
	w.add_floor()
	var p := w.spawn_player(Vector3(0, 2.5, 0))
	await w.step(60)
	check(not (Player.State.STUN in w.states_seen), "no stun from a short drop")
	check(p.state == Player.State.GROUND, "standing")


# ------------------------------------------------------------------ kick-off

func test_kick_off_wall() -> void:
	w.add_floor()
	w.add_box(Vector3(0, 3, -2.5), Vector3(6, 6, 1))  # face at z = -2
	var p := w.spawn_player(Vector3(0, 2, -1.1))
	await w.step(1)
	await w.press(InputFrame.make(Vector2.ZERO, false, false, true))
	check(&"kick_off" in w.tricks_seen, "kick-off reported")
	check(p.velocity.z > 5.0, "launched away from the wall (vz %.2f)" % p.velocity.z)
	check(p.velocity.y > 4.0, "launched upward")


func test_cannot_kick_same_wall_twice() -> void:
	w.add_floor()
	w.add_box(Vector3(0, 3, -2.5), Vector3(6, 6, 1))
	var p := w.spawn_player(Vector3(0, 2, -1.1))
	await w.step(1)
	await w.press(InputFrame.make(Vector2.ZERO, false, false, true))
	p.global_position = Vector3(0, 2.5, -1.1)
	p.velocity = Vector3.ZERO
	await w.press(InputFrame.make(Vector2.ZERO, false, false, true))
	check(w.tricks_seen.count(&"kick_off") == 1, "second kick off the same wall is ignored")


func test_kick_off_target_pushes_it() -> void:
	w.add_floor()
	var target := RigidBody3D.new()
	target.collision_layer = 4
	target.gravity_scale = 0.0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1, 2, 1)
	shape.shape = box
	target.add_child(shape)
	w.add_child(target)
	target.global_position = Vector3(0, 3.6, -1.6)
	var p := w.spawn_player(Vector3(0, 2, 0))
	await w.step(1)
	await w.press(InputFrame.make(Vector2.ZERO, false, false, true))
	await w.step(2)
	check(&"kick_off" in w.tricks_seen, "kicked the target")
	check(target.linear_velocity.z < -1.0, "target pushed away")
	check(p.velocity.z > 3.0, "player bounced back")


func test_no_kick_off_on_ground() -> void:
	w.add_floor()
	w.add_box(Vector3(0, 3, -2.5), Vector3(6, 6, 1))
	var p := await _settle(Vector3(0, 0.05, -1.1))
	await w.press(InputFrame.make(Vector2.ZERO, false, false, true))
	check(not (&"kick_off" in w.tricks_seen), "kick-off is airborne only")
	check(p.state == Player.State.GROUND, "still grounded")


# ------------------------------------------------------------------ misc

func test_falling_out_of_world_respawns() -> void:
	var p := w.spawn_player(Vector3(0, -39.9, 0))
	p.set_spawn(Transform3D(Basis.IDENTITY, Vector3(0, 50, 0)))
	await w.step(10)
	check(p.global_position.y > 45.0, "respawned at the spawn point")
	check(p.momentum == 0.0, "momentum reset")


func test_simulation_is_deterministic() -> void:
	# Same inputs from the same start must give the same result.
	var results: Array[Vector3] = []
	for run in 2:
		var world := TestWorld.new()
		tree.root.add_child(world)
		world.add_floor()
		world.add_box(Vector3(0, 0.5, -8), Vector3(6, 1.0, 0.4))
		var p := world.spawn_player(Vector3(0, 0.05, 0))
		await world.step(20)
		await world.step(30, _fwd())
		await world.press(_fwd_jump())
		await world.step(40, _fwd())
		await world.press(_fwd_crouch(), 30)
		results.append(p.global_position)
		world.queue_free()
		await tree.process_frame
	check(results[0].is_equal_approx(results[1]), "identical runs end in the same place (%s vs %s)" % [results[0], results[1]])


# ------------------------------------------------------------------ walk / sprint / prone / dive

func test_walk_is_slower_than_sprint() -> void:
	w.add_floor()
	var p := await _settle()
	await w.step(60, InputFrame.make(Vector2(0, 1), false, false, false, false))
	check_near(p.horizontal_speed(), p.tuning.walk_speed, 0.2, "walking speed")
	await w.step(60, _fwd())
	check(p.horizontal_speed() > p.tuning.walk_speed + 1.0, "sprint is faster")


func test_hold_crouch_goes_prone() -> void:
	w.add_floor()
	var p := await _settle()
	await w.press(InputFrame.make(Vector2.ZERO, false, true), int(p.tuning.prone_hold_time * 60.0) + 5)
	check(p.state == Player.State.PRONE, "holding crouch while still goes prone")
	await w.step(60, InputFrame.make(Vector2(0, 1), false, false, false, false))
	check(p.state == Player.State.PRONE, "still prone while crawling (%s)" % Player.State.keys()[p.state])
	check_near(p.horizontal_speed(), p.tuning.prone_speed, 0.2, "crawl speed")
	await w.press(_fwd_jump())
	check(p.state == Player.State.CROUCH, "jump gets you up to a crouch")


func test_prone_key_and_back() -> void:
	w.add_floor()
	var p := await _settle()
	var prone := InputFrame.new()
	prone.prone_pressed = true
	await w.press(prone)
	check(p.state == Player.State.PRONE, "prone key drops you prone")
	await w.step(5)
	await w.press(prone)
	check(p.state == Player.State.CROUCH, "prone key again gets you up")


func test_dolphin_dive_from_sprint() -> void:
	w.add_floor()
	var p := await _settle()
	await _run_to(7.0)
	var dive := _fwd()
	dive.prone_pressed = true
	await w.press(dive)
	check(p.state == Player.State.AIR, "dive leaves the ground")
	check(&"dolphin_dive" in w.tricks_seen, "dive reported")
	var landed := await w.step_until(func() -> bool: return p.state == Player.State.PRONE_SLIDE, 60, _fwd())
	check(landed, "lands into a prone slide")
	var ended := await w.step_until(func() -> bool: return p.state == Player.State.PRONE, 240, _fwd())
	check(ended, "slide ends prone")


# ------------------------------------------------------------------ flips / spins / wall hop

func _airborne(height := 6.0) -> Player:
	w.add_floor()
	var p := w.spawn_player(Vector3(0, height, 0))
	await w.step(1)
	return p


func test_360_in_the_air() -> void:
	var p := await _airborne()
	for i in 24:
		p._look(TAU / 24.0, 0.0)
		await w.step(1)
	check(&"spin_360" in w.tricks_seen, "full turn in the air is a 360")


func test_backflip_and_clean_landing() -> void:
	var p := await _airborne(4.2)
	for i in 24:
		p._look(0.0, TAU / 24.0)
		await w.step(1)
	check(&"backflip" in w.tricks_seen, "pulling the view all the way over is a backflip")
	await w.step_until(func() -> bool: return p.state != Player.State.AIR, 120)
	check(p.state != Player.State.STUN, "landing after a full flip is clean")
	check(absf(p.pitch) <= deg_to_rad(89.1), "view settles after landing")


func test_frontflip() -> void:
	var p := await _airborne(4.2)
	for i in 24:
		p._look(0.0, -TAU / 24.0)
		await w.step(1)
	check(&"frontflip" in w.tricks_seen, "pushing the view over forward is a front flip")


func test_landing_upside_down_crashes() -> void:
	var p := await _airborne(3.0)
	for i in 12:
		p._look(0.0, PI / 12.0)
		await w.step(1)
	await w.step_until(func() -> bool: return p.state != Player.State.AIR, 120)
	check(&"crash" in w.tricks_seen, "half-finished flip crashes")
	check(p.state == Player.State.STUN, "crash stuns")


func test_no_flip_on_ground() -> void:
	w.add_floor()
	var p := await _settle()
	for i in 24:
		p._look(0.0, TAU / 24.0)
		await w.step(1)
	check(p.pitch <= deg_to_rad(89.1), "pitch stays clamped on the ground")
	check(not (&"backflip" in w.tricks_seen), "no flip on the ground")


func test_wall_hop_off_plain_wall() -> void:
	w.add_floor()
	w.add_box(Vector3(0, 3, -2.5), Vector3(6, 6, 1))  # face at z = -2
	var p := w.spawn_player(Vector3(0, 2, -1.5))
	p.set_view(PI / 2.0)  # side-on, too slow to wallrun
	p.velocity = Vector3(0, 0, -2)
	await w.step(8)
	await w.press(InputFrame.make(Vector2.ZERO, true))
	check(&"wall_hop" in w.tricks_seen, "jump off a touched wall is a wall hop")
	check(p.velocity.z > 4.0, "pushed off the wall")


# ------------------------------------------------------------------ doors and windows

func test_kick_door_open() -> void:
	w.add_floor()
	var door := KickDoor.new()
	w.add_child(door)
	door.global_position = Vector3(-0.55, 0, -1.5)
	var p := await _settle()
	await w.press(InputFrame.make(Vector2.ZERO, false, false, true))
	check(door.is_open, "front kick opens the door")
	check(&"door_kick" in w.tricks_seen, "door kick reported")
	await w.step(20)
	var through := await w.step_until(func() -> bool: return p.global_position.z < -3.0, 120, _fwd())
	check(through, "walk through the open doorway")


func test_kick_window() -> void:
	w.add_floor()
	var win := BreakableWindow.new()
	w.add_child(win)
	win.global_position = Vector3(0, 0.6, -1.4)
	var p := await _settle()
	await w.press(InputFrame.make(Vector2.ZERO, false, false, true))
	check(win.is_broken, "kick breaks the window")


func test_dive_through_window() -> void:
	w.add_floor()
	var win := BreakableWindow.new()
	win.size = Vector2(2.0, 1.4)
	w.add_child(win)
	win.global_position = Vector3(0, 0.5, -14)
	var p := await _settle()
	await _run_to(7.0)
	var dive := _fwd()
	dive.prone_pressed = true
	await w.step_until(func() -> bool: return p.global_position.z < -11.5, 300, _fwd())
	await w.press(dive)
	await w.step(50, _fwd())
	check(win.is_broken, "dove through the window")
	check(p.global_position.z < -14.5, "came out the other side")
	check(&"window_smash" in w.tricks_seen, "smash reported")
