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


func _fwd_crouch_hold() -> InputFrame:
	var f := InputFrame.make(Vector2(0, 1), false, true)
	f.crouch_pressed = false
	return f


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
	check_between(max_y, 1.45, 1.7, "jump apex")
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


func test_early_jump_clears_a_hurdle_without_vaulting() -> void:
	w.add_floor()
	w.add_box(Vector3(0, 0.5, -8), Vector3(6, 1.0, 0.4))
	var p := await _settle()
	await w.step_until(func() -> bool: return p.global_position.z < -4.6, 300, _fwd())
	await w.press(_fwd_jump())
	await w.step(50, _fwd())
	check(not (Player.State.VAULT in w.states_seen), "no automatic hurdle in the air")
	check(p.global_position.z < -8.5, "jumped clean over (z %.2f)" % p.global_position.z)


func test_jump_press_in_the_air_vaults() -> void:
	w.add_floor()
	w.add_box(Vector3(0, 0.5, -8), Vector3(6, 1.0, 0.4))
	var p := w.spawn_player(Vector3(0, 0.3, -7.0))
	p.velocity = Vector3(0, 1.0, -7.0)
	p._jumped_since_floor = true
	await w.step(1, _fwd())
	check(p.state == Player.State.AIR, "airborne")
	await w.press(_fwd_jump())
	check(p.state == Player.State.VAULT, "pressing jump at the wall mid-air vaults (%s)" % Player.State.keys()[p.state])


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


func test_wall_to_wall_chain_is_not_a_bonk() -> void:
	# A second wall on the left, 4 m across: face at x = -2.5.
	w.add_box(Vector3(-3.0, 3.0, -30.0), Vector3(1.0, 6.0, 60.0))
	var ok := await _enter_wallrun()
	check(ok, "wallrun starts on the right wall")
	if not ok:
		return
	var p := w.player
	await w.step(8, _fwd())
	p.set_view(0.5)  # look forward-left, at the other wall
	await w.press(_fwd_jump())
	var other := await w.step_until(func() -> bool: return p.state == Player.State.WALLRUN and p.wall_normal().x > 0.5, 90, _fwd())
	check(other, "chained onto the left wall")
	check(not (&"wall_impact" in w.tricks_seen), "hitting the next wall to run on it isn't a bonk")


func test_crouch_drops_off_wallrun() -> void:
	var ok := await _enter_wallrun()
	check(ok, "wallrun starts")
	if not ok:
		return
	var p := w.player
	await w.press(InputFrame.make(Vector2(0, 1), false, true))
	await w.step(2, _fwd())
	check(p.state != Player.State.WALLRUN, "crouch drops off the wall")


func test_free_look_while_wallrunning() -> void:
	# Look across the corridor (away from the wall) while holding forward:
	# you keep running along the wall at full speed, free to aim.
	var ok := await _enter_wallrun()
	check(ok, "wallrun starts")
	if not ok:
		return
	var p := w.player
	var speed0 := p.horizontal_speed()
	p.set_view(PI * 0.5)  # facing -X, straight away from the wall
	var z0 := p.global_position.z
	await w.step(30, _fwd())
	check(p.state == Player.State.WALLRUN, "still wallrunning while looking away")
	check(z0 - p.global_position.z > 2.5, "still moving along the wall (%.2f m)" % (z0 - p.global_position.z))
	check(p.horizontal_speed() >= speed0 - 0.3, "no speed lost for looking around (%.2f -> %.2f)" % [speed0, p.horizontal_speed()])


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
	var run_in := p.horizontal_speed()
	await w.press(_fwd_jump())
	await w.step_until(func() -> bool: return Player.State.MANTLE in w.states_seen and p.state != Player.State.MANTLE, 90, _fwd())
	check(Player.State.MANTLE in w.states_seen, "climb ends in a mantle")
	check(p.horizontal_speed() > run_in * 0.7, "the mantle gives back the speed you climbed with (%.2f of %.2f)" % [p.horizontal_speed(), run_in])
	await w.step(20, _fwd())
	check_near(p.global_position.y, 3.0, 0.08, "on top of the 3 m wall")


func test_wall_climb_kick_never_turns_the_camera() -> void:
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
	check(absf(p.yaw) < 0.01, "camera stays where you pointed it (yaw %.2f)" % p.yaw)


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


func _tuck_drop(tuck_degrees: float) -> Player:
	w.add_floor()
	var p := w.spawn_player(Vector3(0, 12, 0))
	p.velocity = Vector3(0, 0, -8)
	await w.step(2, _fwd())
	var steps := 10
	for i in steps:
		p._look(0.0, deg_to_rad(-tuck_degrees) / steps)
		await w.step(1, _fwd())
	await w.step_until(func() -> bool: return p.state != Player.State.AIR, 200, _fwd())
	return p


func test_tucked_landing_rolls_and_keeps_speed() -> void:
	var p := await _tuck_drop(110.0)
	check(p.state == Player.State.ROLL, "landing tucked forward rolls (%s)" % Player.State.keys()[p.state])
	check(&"flip_roll" in w.tricks_seen, "flip roll reported")
	check(p.horizontal_speed() >= 7.5, "no speed lost from a big drop (%.2f)" % p.horizontal_speed())
	check(p.roll_spin() < deg_to_rad(-100.0) and p.roll_spin() > -PI, "camera carries on turning from where the flip was (%.0f deg)" % rad_to_deg(p.roll_spin()))
	await w.step(40, _fwd())
	check(p.state == Player.State.GROUND, "back up and running")
	check_near(p.roll_spin(), 0.0, 0.001, "camera level again")


func test_holding_crouch_in_the_air_rolls_from_any_angle() -> void:
	w.add_floor()
	var p := w.spawn_player(Vector3(0, 8, 0))
	p.velocity = Vector3(0, 0, -8)
	await w.step(2, _fwd())
	# Half a side flip: on your side, which would be a crash...
	await w.step_until(func() -> bool: return p.air_roll() > deg_to_rad(120.0), 60, _lean_frame(1.0))
	# ...but tucked (crouch held) you roll out of it.
	await w.step_until(func() -> bool: return p.state != Player.State.AIR, 200, _fwd_crouch_hold())
	check(p.state == Player.State.ROLL, "tucked landing rolls (%s)" % Player.State.keys()[p.state])
	check(not (&"crash" in w.tricks_seen), "no crash")
	check(p.horizontal_speed() > 6.0, "speed kept (%.2f)" % p.horizontal_speed())


func test_crouch_pressed_just_before_landing_still_slides() -> void:
	w.add_floor()
	var p := w.spawn_player(Vector3(0, 3, 0))
	p.velocity = Vector3(0, 0, -8)
	await w.step_until(func() -> bool: return p.global_position.y < 0.6, 120, _fwd())
	await w.step_until(func() -> bool: return p.state != Player.State.AIR, 30, _fwd_crouch())
	check(p.state == Player.State.SLIDE, "a late crouch is a slide landing (%s)" % Player.State.keys()[p.state])


func test_double_tap_crouch_rolls() -> void:
	w.add_floor()
	var p := await _settle()
	await _run_to(7.0)
	await w.press(_fwd_crouch())
	await w.step(3, _fwd())
	await w.press(_fwd_crouch())
	check(p.state == Player.State.ROLL, "double-tap crouch while running rolls (%s)" % Player.State.keys()[p.state])
	check(&"ground_roll" in w.tricks_seen, "roll reported")


func test_untucked_big_drop_still_lands_hard() -> void:
	var p := await _tuck_drop(20.0)
	check(p.state == Player.State.STUN, "looking ahead on a big drop is a hard landing (%s)" % Player.State.keys()[p.state])


func test_flick_down_on_the_ground_rolls() -> void:
	w.add_floor()
	var p := await _settle()
	await _run_to(7.0)
	var before := p.horizontal_speed()
	p._look(0.0, deg_to_rad(-89.0))
	p._look(0.0, deg_to_rad(-50.0))
	await w.step(1, _fwd())
	check(p.state == Player.State.ROLL, "flicking past your feet rolls (%s)" % Player.State.keys()[p.state])
	check(&"ground_roll" in w.tricks_seen, "ground roll reported")
	check(p.horizontal_speed() >= before * 0.95, "keeps speed (%.2f -> %.2f)" % [before, p.horizontal_speed()])
	await w.step(40, _fwd())
	check(p.state == Player.State.GROUND, "running again")


func test_slowly_looking_down_does_not_roll() -> void:
	w.add_floor()
	var p := await _settle()
	await _run_to(7.0)
	p._look(0.0, deg_to_rad(-89.0))
	for i in 40:
		p._look(0.0, deg_to_rad(-2.0))
		await w.step(1, _fwd())
	check(not (&"ground_roll" in w.tricks_seen), "a slow look down past your feet isn't a roll")


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


# ------------------------------------------------------------------ sprint

func test_always_sprinting_and_can_stop() -> void:
	w.add_floor()
	var p := await _settle()
	await w.step(60, _fwd())
	check(p.horizontal_speed() > p.tuning.run_speed - 0.2, "moving is sprinting (%.2f m/s)" % p.horizontal_speed())
	await w.step(60)
	check(p.horizontal_speed() < 0.3, "letting go stops you (%.2f m/s)" % p.horizontal_speed())
	check(p.state == Player.State.GROUND, "standing still is possible")


func test_holding_crouch_stays_crouched() -> void:
	w.add_floor()
	var p := await _settle()
	await w.press(InputFrame.make(Vector2.ZERO, false, true), 120)
	check(p.state == Player.State.CROUCH, "holding crouch still stays crouched (%s)" % Player.State.keys()[p.state])


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
	p._look(0.0, -0.01)  # stop the spin dead, upside down
	await w.step(1)
	await w.step_until(func() -> bool: return p.state != Player.State.AIR, 120)
	check(&"crash" in w.tricks_seen, "half-finished flip crashes")
	check(p.state == Player.State.STUN, "crash stuns")


func test_flip_momentum_carries_round_to_level() -> void:
	var p := await _airborne(6.0)
	# Flick 200 degrees over fast and let go: the flip finishes itself and
	# stops level.
	for i in 10:
		p._look(0.0, deg_to_rad(20.0))
		await w.step(1)
	await w.step(30)
	check(&"backflip" in w.tricks_seen, "the spin carried on into a full backflip (air pitch %.0f)" % rad_to_deg(p.air_rotation().y))
	check(absf(wrapf(p.pitch, -PI, PI)) < deg_to_rad(40.0), "and stopped near level (%.0f deg)" % rad_to_deg(wrapf(p.pitch, -PI, PI)))
	await w.step_until(func() -> bool: return p.state != Player.State.AIR, 120)
	check(not (&"crash" in w.tricks_seen), "lands clean")


func test_aiming_in_the_air_has_no_momentum() -> void:
	var p := await _airborne(6.0)
	for i in 6:
		p._look(deg_to_rad(15.0), deg_to_rad(-10.0))  # a fast flick at a target
		await w.step(1)
	var yaw0 := p.yaw
	var pitch0 := p.pitch
	await w.step(10)
	check_near(p.yaw, yaw0, 0.0001, "the view stops where you stop it (yaw)")
	check_near(p.pitch, pitch0, 0.0001, "the view stops where you stop it (pitch)")


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


func _lean_frame(amount: float) -> InputFrame:
	var f := InputFrame.new()
	f.lean = amount
	return f


func test_side_flip_by_holding_lean() -> void:
	var p := await _airborne(10.0)
	await w.step_until(func() -> bool: return &"sideflip" in w.tricks_seen, 120, _lean_frame(1.0))
	check(&"sideflip" in w.tricks_seen, "a full roll is a side flip (roll %.0f deg)" % rad_to_deg(p.air_roll()))
	await w.step_until(func() -> bool: return p.state != Player.State.AIR, 120)
	check(not (&"crash" in w.tricks_seen), "let go near level: lands clean")


func test_side_flip_keeps_its_direction() -> void:
	var p := await _airborne(8.0)
	await w.step(15, _lean_frame(1.0))
	var roll0 := p.air_roll()
	check(roll0 > 0.2, "leaning right rolls right (%.0f deg)" % rad_to_deg(roll0))
	await w.step(15, _lean_frame(-1.0))
	check(p.air_roll() > roll0 + 0.5, "leaning left mid-roll speeds it up, never reverses it (%.0f -> %.0f deg)" % [rad_to_deg(roll0), rad_to_deg(p.air_roll())])


func test_side_flip_opened_up_spins_slower() -> void:
	var p := await _airborne(10.0)
	await w.step_until(func() -> bool: return p.air_roll() > deg_to_rad(80.0), 60, _lean_frame(1.0))
	var a := p.air_roll()
	await w.step(6, _lean_frame(1.0))
	var tucked := p.air_roll() - a
	await w.step(20)  # let go: opens up
	a = p.air_roll()
	await w.step(6)
	var open := p.air_roll() - a
	check(open > 0.0, "still rolling after letting go (%.1f deg)" % rad_to_deg(open))
	check(open < tucked * 0.6, "but slower than tucked (%.1f vs %.1f deg)" % [rad_to_deg(open), rad_to_deg(tucked)])


func test_mouse_roll_rolls_you_directly() -> void:
	var p := await _airborne(10.0)
	# Shift held, the mouse rolls you by as much as it moves, either way.
	# Slowly (2 degrees a tick is 120 degrees a second).
	for i in 15:
		p.roll_look(deg_to_rad(2.0))
		await w.step(1)
	check_near(rad_to_deg(p.air_roll()), 30.0, 1.0, "mouse right rolls right")
	for i in 5:
		p.roll_look(deg_to_rad(-2.0))
		await w.step(1)
	check_near(rad_to_deg(p.air_roll()), 20.0, 1.0, "and back left (no direction lock)")
	# A slow roll stops where you leave it.
	await w.step(10)
	check_near(rad_to_deg(p.air_roll()), 20.0, 1.0, "a slow roll just stops")
	# A fast one carries on after you let go, like an opened side flip.
	for i in 6:
		p.roll_look(deg_to_rad(12.0))
		await w.step(1)
	var r := p.air_roll()
	await w.step(6)
	check(p.air_roll() > r + deg_to_rad(10.0), "a fast roll carries on (%.0f -> %.0f deg)" % [rad_to_deg(r), rad_to_deg(p.air_roll())])


## Lands a running jump after side-flipping round to `roll_deg` (0 = no
## flip). Returns {state on landing, speed before, speed a second later}.
func _side_flip_landing(roll_deg: float) -> Dictionary:
	if is_instance_valid(w):
		w.queue_free()
		await tree.process_frame
	w = TestWorld.new()
	tree.root.add_child(w)
	w.add_floor()
	var p := w.spawn_player(Vector3(0, 4.0, 0))
	p.velocity = Vector3(0, 0, -9)
	await w.step(1, _fwd())
	if roll_deg > 0.0:
		await w.step_until(func() -> bool: return p.air_roll() <= deg_to_rad(-roll_deg), 90, _lean(-1.0))
	var out := {"state": "", "before": p.horizontal_speed(), "land": 0.0, "after": 0.0}
	await w.step_until(func() -> bool: return p.state != Player.State.AIR, 120, _fwd())
	out.state = Player.State.keys()[p.state]
	out.land = p.horizontal_speed()
	await w.step(60, _fwd())
	out.after = p.horizontal_speed()
	return out


func test_landing_on_your_side_rolls_and_keeps_moving() -> void:
	var clean := await _side_flip_landing(0.0)
	var side := await _side_flip_landing(150.0)
	check(side.state == "ROLL", "coming down on your side is a shoulder roll (%s)" % side.state)
	check(not (&"crash" in w.tricks_seen), "not a crash")
	check(side.after > side.before * 0.85, "keeps moving (%.1f -> %.1f m/s)" % [side.before, side.after])
	check(clean.land >= side.land, "a clean landing keeps at least as much (%.1f vs %.1f m/s)" % [clean.land, side.land])


func test_held_wallrun_lean_doesnt_side_flip() -> void:
	var ok := await _enter_wallrun()
	check(ok, "wallrun starts")
	if not ok:
		return
	var p := w.player
	# Lean into the wall until the run ends, still holding the lean.
	await w.step_until(func() -> bool: return p.state != Player.State.WALLRUN, 300, _lean(1.0))
	check(p.state == Player.State.AIR, "came off the wall (%s)" % Player.State.keys()[p.state])
	await w.step(15, _lean(1.0))
	check(absf(p.air_roll()) < 0.01, "the held lean doesn't start a side flip (%.0f deg)" % rad_to_deg(p.air_roll()))
	await w.step(2, _fwd())
	await w.step(10, _lean(1.0))
	check(absf(p.air_roll()) > 0.3 or p.state != Player.State.AIR, "let go and lean again to side flip")


## Moves the view as a mouse would (right / up on screen) while held at an
## angle in the air, and returns how the crosshair moved on screen.
func _aim_on_screen(view_pitch: float, view_roll: float, right: float, up: float) -> Vector2:
	var p := await _airborne(20.0)
	p.set_physics_process(false)
	p.pitch = view_pitch
	p._air_roll = view_roll
	p.rotation = Vector3(0.0, p.yaw, 0.0)
	p._process(0.0)
	var before := p.camera.global_basis
	p._look(-right * 0.05, up * 0.05)
	p.rotation = Vector3(0.0, p.yaw, 0.0)  # what the next tick does
	p._process(0.0)
	var moved := -p.camera.global_basis.z - (-before.z)
	return Vector2(moved.dot(before.x), moved.dot(before.y))


func test_aim_follows_the_view_in_the_air() -> void:
	for c: Array in [[0.0, 0.0, "upright"], [PI, 0.0, "upside down"], [0.0, PI * 0.5, "on your side"], [2.4, 1.0, "mid flip and tilted"]]:
		var r := await _aim_on_screen(c[0], c[1], 1.0, 0.0)
		check(r.x > 0.03 and absf(r.y) < r.x * 0.5, "%s: moving right aims right (%s)" % [c[2], r])
		var u := await _aim_on_screen(c[0], c[1], 0.0, 1.0)
		check(u.y > 0.03 and absf(u.x) < u.y * 0.5, "%s: moving up aims up (%s)" % [c[2], u])
		w.queue_free()
		await tree.process_frame
		w = TestWorld.new()
		tree.root.add_child(w)


func test_lean_on_the_ground_peeks() -> void:
	w.add_floor()
	var p := await _settle()
	await w.step(20, _lean_frame(1.0))
	check_near(p.lean, 1.0, 0.01, "leaning right")
	check(p.state == Player.State.GROUND, "still standing")
	check(not (&"sideflip" in w.tricks_seen), "no flip on the ground")


## Runs up to speed, then turns right with the mouse lean (Shift held) at
## `deg_per_tick` for 20 ticks. Returns [lean, yaw turned, speed after].
func _mouse_lean_turn(deg_per_tick: float) -> Array:
	w.add_floor()
	var p := await _settle()
	await _run_to(9.0)
	var yaw0 := p.yaw
	var turned := 0.0
	for i in 20:
		p.lean_look(-deg_to_rad(deg_per_tick), 0.0)
		await w.step(1, _fwd())
		turned += absf(wrapf(p.yaw - yaw0, -PI, PI))
		yaw0 = p.yaw
	return [p.lean, turned, p.horizontal_speed()]


func test_mouse_lean_turns_harder_the_more_you_lean() -> void:
	var slow := await _mouse_lean_turn(0.5)  # 30 degrees a second
	w.queue_free()
	await tree.process_frame
	w = TestWorld.new()
	tree.root.add_child(w)
	var fast := await _mouse_lean_turn(4.0)  # 240 degrees a second
	check(slow[0] > 0.0 and slow[0] < 0.15, "a slow turn barely leans (%.2f)" % slow[0])
	check(fast[0] > 0.5, "a fast turn leans you right into it (%.2f)" % fast[0])
	check(slow[1] < deg_to_rad(0.5 * 20 * 1.2), "a slow turn is about as far as the mouse moved (%.1f deg)" % rad_to_deg(slow[1]))
	check(fast[1] > deg_to_rad(4.0 * 20 * 1.4), "a fast one turns harder than the mouse moved (%.1f deg)" % rad_to_deg(fast[1]))
	check(fast[2] > 8.0, "and keeps your speed round the turn (%.2f m/s)" % fast[2])


func test_lean_peeks_less_while_running() -> void:
	w.add_floor()
	var p := await _settle()
	await w.step(30, _lean_frame(1.0))
	var standing := p.camera.position.x
	check(standing > p.tuning.lean_offset * 0.8, "standing, lean peeks fully (%.2f m)" % standing)
	var f := _fwd()
	f.lean = 1.0
	await w.step(90, f)
	var running := p.camera.position.x
	check(p.horizontal_speed() > p.tuning.run_speed - 0.5, "running")
	check(running < standing * 0.3, "running, the view barely shifts (%.2f vs %.2f m)" % [running, standing])


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


func test_slide_through_low_window() -> void:
	w.add_floor()
	# A low window from the floor up to 1.4 m, in a wall: too low to run
	# through standing, room to slide under.
	var win := BreakableWindow.new()
	win.size = Vector2(2.0, 1.4)
	w.add_child(win)
	win.global_position = Vector3(0, 0, -14)
	w.add_box(Vector3(0, 2.2, -14), Vector3(2.0, 1.6, 0.3))
	var p := await _settle()
	await _run_to(7.0)
	await w.step_until(func() -> bool: return p.global_position.z < -10.5, 300, _fwd())
	await w.press(_fwd_crouch())
	var slide := _fwd_crouch()
	slide.crouch_pressed = false
	await w.step_until(func() -> bool: return p.global_position.z < -15.0, 60, slide)
	check(win.is_broken, "slid through the window")
	check(p.global_position.z < -14.5, "came out the other side (z %.2f)" % p.global_position.z)
	check(&"window_smash" in w.tricks_seen, "smash reported")


# ------------------------------------------------------------------ quick turn / strafe sprint / flip feel

func _turn_run(lean: float) -> Player:
	w.add_floor()
	var p := await _settle()
	await _run_to(9.0)
	var f := _fwd()
	f.lean = lean
	await w.step(1, f)
	for i in 12:
		p._look(deg_to_rad(3.0), 0.0)
		await w.step(1, f)
	return p


func test_quick_turn_turns_faster_and_keeps_speed() -> void:
	# Q (lean left) while turning left.
	var p := await _turn_run(-1.0)
	var turned := rad_to_deg(absf(angle_difference(0.0, p.yaw)))
	check(turned > 80.0, "holding lean turns the view faster (%.0f deg)" % turned)
	var h := MovementMath.horizontal(p.velocity)
	check(h.length() > 8.5, "speed kept round the turn (%.2f m/s)" % h.length())
	check(h.normalized().dot(p.forward()) > 0.95, "and going where you look")


func test_quick_turn_only_toward_its_side() -> void:
	# E (lean right) while turning left: a normal turn.
	var p := await _turn_run(1.0)
	check_near(rad_to_deg(absf(angle_difference(0.0, p.yaw))), 36.0, 0.5, "the other lean doesn't speed up the turn")


func test_plain_turn_is_normal_speed() -> void:
	var p := await _turn_run(0.0)
	check_near(rad_to_deg(absf(angle_difference(0.0, p.yaw))), 36.0, 0.5, "without lean the view turns as you move it")


func test_strafing_is_sprinting() -> void:
	w.add_floor()
	var p := await _settle()
	await w.step(120, InputFrame.make(Vector2(1, 0)))
	check(p.horizontal_speed() > p.tuning.run_speed - 0.2, "sprint works sideways (%.2f m/s)" % p.horizontal_speed())


func test_flip_needs_less_input_once_past_vertical() -> void:
	# Gain past 75 deg: ~235 deg of input completes a flip (vs 325 without).
	var p := await _airborne(4.2)
	var steps := 24
	var total := deg_to_rad(245.0)
	for i in steps:
		p._look(0.0, total / steps)
		await w.step(1)
	check(&"backflip" in w.tricks_seen, "a committed 245 deg flick flips (air pitch %.0f deg)" % rad_to_deg(p.air_rotation().y))


# ------------------------------------------------------------------ regressions (review findings)

func test_landing_crouched_under_low_ceiling_stays_crouched() -> void:
	w.add_floor()
	# Ceiling at 1.3 m: crouch (1.0) fits, standing (1.8) doesn't.
	w.add_box(Vector3(0, 1.8, 0), Vector3(6, 1.0, 6))
	var p := w.spawn_player(Vector3(0, 0.3, 0))
	p._set_height(p.tuning.crouch_height)
	await w.step(30)
	check(p.state == Player.State.CROUCH, "stays crouched under the ceiling (%s)" % Player.State.keys()[p.state])
	check_near(p._height, p.tuning.crouch_height, 0.01, "crouch height kept")
	check(p.global_position.y < 0.2, "not pushed through the ceiling (y %.2f)" % p.global_position.y)


func test_respawn_clears_air_rotation() -> void:
	var p := await _airborne(30.0)
	for i in 10:
		p._look(deg_to_rad(30.0), 0.0)
		await w.step(1)
	p.respawn()
	await w.step(1)
	p._look(deg_to_rad(70.0), 0.0)
	await w.step(1)
	check(not (&"spin_360" in w.tricks_seen), "spin before respawning doesn't carry over")


func test_looking_down_while_falling_is_not_a_crash() -> void:
	var p := await _airborne(4.0)
	p.pitch = deg_to_rad(-89.0)
	p._look(0.0, deg_to_rad(-15.0))  # past straight down, aiming below
	await w.step_until(func() -> bool: return p.state != Player.State.AIR, 120)
	check(p.state != Player.State.STUN, "aiming down on a drop lands normally")


func _lean(amount: float) -> InputFrame:
	var f := _fwd()
	f.lean = amount
	return f


## Wallruns on the right-hand wall holding a lean (+1 = right, toward the
## wall). Returns {top: highest point above the start, frames: on the wall,
## dist: distance along it}.
func _lean_wallrun(lean: float) -> Dictionary:
	if is_instance_valid(w):
		w.queue_free()
		await tree.process_frame
	w = TestWorld.new()
	tree.root.add_child(w)
	var ok := await _enter_wallrun()
	var p := w.player
	var out := {"ok": ok, "top": 0.0, "frames": 0, "dist": 0.0, "angle": 0.0, "entry": 0.0}
	if not ok:
		return out
	out.entry = p.wallrun_angle()
	var y0 := p.global_position.y
	var z0 := p.global_position.z
	while p.state == Player.State.WALLRUN and out.frames < 200:
		await w.step(1, _lean(lean))
		out.frames += 1
		out.top = maxf(out.top, p.global_position.y - y0)
		if p.state == Player.State.WALLRUN:
			out.angle = maxf(out.angle, p.wallrun_angle())
			check(p.wallrun_speed() > 0.0, "wallrun speed is reported")
	out.dist = z0 - p.global_position.z
	return out


func test_lean_on_a_wallrun() -> void:
	var plain := await _lean_wallrun(0.0)
	var up := await _lean_wallrun(1.0)
	var down := await _lean_wallrun(-1.0)
	check(plain.ok and up.ok and down.ok, "all three wallrun")
	check(up.top > plain.top + 0.5, "leaning toward the wall rolls the run up it (%.2f m vs %.2f m)" % [up.top, plain.top])
	check(up.angle > up.entry + 0.3, "the path turns up (%.2f -> %.2f rad)" % [up.entry, up.angle])
	check(down.frames < plain.frames, "leaning away brings you down sooner (%d vs %d frames)" % [down.frames, plain.frames])


func test_lean_on_a_wall_is_not_a_quick_turn() -> void:
	var ok := await _enter_wallrun()
	check(ok, "wallrun starts")
	if not ok:
		return
	var p := w.player
	await w.step(1, _lean(1.0))
	var y := p.yaw
	p._look(0.1, 0.0)
	check_near(p.yaw - y, 0.1, 0.001, "turning on a wall is normal speed while leaning")


func test_steep_wallrun_kicks_off_harder() -> void:
	var push := []
	for steep: bool in [false, true]:
		if is_instance_valid(w):
			w.queue_free()
			await tree.process_frame
		w = TestWorld.new()
		tree.root.add_child(w)
		var ok := await _enter_wallrun()
		check(ok, "wallrun starts")
		if not ok:
			return
		# A steep run comes from jumping in rising hard; set it directly.
		w.player._wallrun_angle = deg_to_rad(w.player.tuning.wallrun_max_up_angle) if steep else 0.0
		await w.step(1, _fwd())
		await w.press(_fwd_jump())
		push.append(Vector2(-w.player.velocity.x, w.player.velocity.y))
	check(push[1].x > push[0].x + 1.0, "kicks off harder from a steep run (%.1f vs %.1f m/s)" % [push[1].x, push[0].x])
	check(push[1].y > push[0].y, "and higher (%.1f vs %.1f m/s)" % [push[1].y, push[0].y])


func test_wallrun_keeps_your_angle_and_lean_rolls_it() -> void:
	var ok := await _enter_wallrun()
	check(ok, "wallrun starts")
	if not ok:
		return
	var p := w.player
	var v := p._pre_move_velocity
	var came_in := atan2(v.y, MovementMath.horizontal(v).length())
	check_near(p.wallrun_angle(), came_in, 0.12, "runs at the angle you came in at (%.2f vs %.2f rad)" % [p.wallrun_angle(), came_in])
	# Let go: nothing holds you up, gravity bends the path down.
	var a0 := p.wallrun_angle()
	await w.step(10, _fwd())
	var fall := a0 - p.wallrun_angle()
	check(fall > 0.01, "gravity bends the run down (%.3f rad)" % fall)
	# Lean away: rolls down at a steady rate on top of that.
	var a1 := p.wallrun_angle()
	await w.step(10, _lean(-1.0))
	var a2 := p.wallrun_angle()
	await w.step(10, _lean(-1.0))
	var a3 := p.wallrun_angle()
	var rate := deg_to_rad(p.tuning.wallrun_angle_rate) * 10.0 / 60.0
	check(a1 - a2 > rate, "leaning away rolls the path down (%.3f rad)" % (a1 - a2))
	check_near(a2 - a3, a1 - a2, 0.04, "at a steady rate (%.3f then %.3f rad)" % [a1 - a2, a2 - a3])
	# Lean toward the wall: rolls it back up.
	await w.step(10, _lean(1.0))
	check(p.wallrun_angle() > a3 + rate * 0.5, "leaning in rolls it up (%.3f -> %.3f rad)" % [a3, p.wallrun_angle()])


func test_mouse_roll_steers_a_wallrun() -> void:
	var ok := await _enter_wallrun()
	check(ok, "wallrun starts")
	if not ok:
		return
	var p := w.player
	await w.step(1, _fwd())
	# The wall is on your right: rolling right (toward it) turns the path up.
	var a0 := p.wallrun_angle()
	p.roll_look(0.2)
	await w.step(1, _fwd())
	check(p.wallrun_angle() > a0 + 0.15, "rolling toward the wall turns it up (%.3f -> %.3f rad)" % [a0, p.wallrun_angle()])
	var a1 := p.wallrun_angle()
	p.roll_look(-0.3)
	await w.step(1, _fwd())
	check(p.wallrun_angle() < a1 - 0.25, "rolling away turns it down (%.3f -> %.3f rad)" % [a1, p.wallrun_angle()])


func test_lean_never_puts_the_view_in_a_wall() -> void:
	w.add_floor()
	# Wall face at x = 0.42, right beside the player (radius 0.38).
	w.add_box(Vector3(0.92, 2.0, 0.0), Vector3(1.0, 4.0, 6.0))
	var p := w.spawn_player(Vector3(0, 0.05, 0))
	await w.step(10)
	var f := InputFrame.new()
	f.lean = 1.0
	await w.step(30, f)
	p._process(0.0)
	check(p.camera.global_position.x < 0.42 - 0.1, "the view stops short of the wall (x %.2f)" % p.camera.global_position.x)
	# Open space on the left: the full lean.
	f.lean = -1.0
	await w.step(40, f)
	p._process(0.0)
	check(p.camera.global_position.x < -p.tuning.lean_offset * 0.8, "leans fully where there's room (x %.2f)" % p.camera.global_position.x)


# ------------------------------------------------------------------ debug pass regressions

func test_side_flip_before_a_wall_does_not_follow_you_onto_it() -> void:
	_add_side_wall()
	w.add_floor()
	var p := await _settle(Vector3(-1.8, 0.05, 0), -0.3)
	await w.step_until(func() -> bool: return p.global_position.x > 0.3, 300, _fwd())
	await w.press(_fwd_jump())
	# Partway round a side flip when you reach the wall.
	p._air_roll = 1.4
	p._prev_air_roll = 1.4
	var ok := await w.step_until(func() -> bool: return p.state == Player.State.WALLRUN, 90, _fwd())
	check(ok, "wallrun starts")
	if not ok:
		return
	check(p.air_roll() == 0.0, "the side flip ends on the wall")
	check(not (&"upside_down" in p.shot_tags()), "not upside down while running the wall")
	# Lean away so the run comes down onto the floor.
	w.states_seen.clear()
	w.tricks_seen.clear()
	var f := _fwd()
	f.lean = -1.0
	await w.step_until(func() -> bool: return p.state != Player.State.WALLRUN, 150, f)
	await w.step(2, _fwd())
	check(not (Player.State.ROLL in w.states_seen), "runs off the wall onto the floor without a roll (%s)" % [w.states_seen.map(func(s: int) -> String: return Player.State.keys()[s])])
	check(not (&"landing_roll" in w.tricks_seen), "no landing roll")


func test_respawn_forgets_the_wall() -> void:
	var ok := await _enter_wallrun()
	check(ok, "wallrun starts")
	if not ok:
		return
	var p := w.player
	p.set_spawn(Transform3D(Basis.IDENTITY, Vector3(-30, 0.05, 10)))
	await w.step(5, _fwd())
	p.respawn()
	w.tricks_seen.clear()
	await w.step(1)
	await w.press(InputFrame.make(Vector2.ZERO, true))
	check(not (&"wall_hop" in w.tricks_seen), "no wall hop off a wall that isn't there")
	check(MovementMath.horizontal(p.velocity).length() < 1.0, "no push sideways (%s)" % p.velocity)


func test_mouse_roll_on_a_wall_stays_on_the_wall() -> void:
	var ok := await _enter_wallrun()
	check(ok, "wallrun starts")
	if not ok:
		return
	var p := w.player
	await w.step(3, _fwd())
	p.roll_look(0.12)  # a mouse roll on the wall this tick
	await w.press(_fwd_jump())
	check(p.state == Player.State.AIR, "wall jump")
	var g := _fwd_crouch_hold()
	await w.step(30, g)
	check(absf(rad_to_deg(p.air_roll())) < 30.0, "the wall's roll doesn't start a side flip (%.0f deg)" % rad_to_deg(p.air_roll()))


func test_crouch_held_through_a_slide_hop_lands_in_a_slide() -> void:
	w.add_floor()
	await _settle()
	var p := w.player
	await w.step(60, _fwd())
	await w.press(_fwd_crouch())
	await w.step(15, _fwd_crouch_hold())
	check(p.state == Player.State.SLIDE, "sliding")
	var j := InputFrame.make(Vector2(0, 1), true, true)
	j.crouch_pressed = false
	await w.step(1, j)
	check(p.state == Player.State.AIR and not p.is_tucked(), "a slide hop isn't a tuck")
	w.states_seen.clear()
	w.tricks_seen.clear()
	await w.step_until(func() -> bool: return p.state != Player.State.AIR, 120, _fwd_crouch_hold())
	check(p.state == Player.State.SLIDE, "lands back in the slide (%s)" % Player.State.keys()[p.state])
	check(not (&"landing_roll" in w.tricks_seen), "no roll")
	# Pressing crouch in the air still tucks.
	await w.press(InputFrame.make(Vector2(0, 1), true))
	await w.step(2, _fwd())
	await w.press(_fwd_crouch())
	await w.step(15, _fwd_crouch_hold())
	check(p.is_tucked(), "crouch pressed in the air tucks")


func test_late_jump_off_a_rising_lip_keeps_its_climb() -> void:
	w.add_floor()
	var p := await _settle()
	# Just flown off the top of a ramp, still climbing fast.
	p.global_position += Vector3(0, 3, 0)
	p._change_state(Player.State.AIR)
	p.velocity = Vector3(0, 12.0, -8.0)
	p._since_floor = 0.0
	p._jumped_since_floor = false
	await w.press(_fwd_jump())
	check(p.velocity.y > 12.0, "a coyote jump adds to the climb (vy %.1f)" % p.velocity.y)


func test_kick_goes_where_you_look_not_where_the_camera_eases() -> void:
	w.add_floor()
	var door := KickDoor.new()
	w.add_child(door)
	door.global_position = Vector3(-0.55, 0, -1.5)
	var p := await _settle()
	# The camera still easing round from a loop, turned well off your aim.
	p._view_offset_start = Quaternion(Vector3.UP, PI * 0.5)
	p._view_offset = p._view_offset_start
	p._view_offset_time = 0.0
	p._view_offset_rate = 0.01
	await w.step(2)
	check((-p.camera.global_basis.z).dot(p.forward()) < 0.5, "the camera is turned away")
	await w.press(InputFrame.make(Vector2.ZERO, false, false, true))
	check(door.is_open, "the kick hits the door you're facing")


## A pane of glass standing on a low sill: the sill looks vaultable, but the
## glass above it is in the way.
func test_no_vault_through_glass_on_a_sill() -> void:
	w.add_floor()
	w.add_box(Vector3(0, 0.2, -4.2), Vector3(4, 0.4, 0.4))  # sill, front face at z = -4
	w.add_box(Vector3(0, 1.6, -4.2), Vector3(4, 2.4, 0.05))  # glass on it
	var p := await _settle()
	await w.step_until(func() -> bool: return p.global_position.z < -3.3, 120, _fwd())
	w.states_seen.clear()
	await w.press(_fwd_jump())
	await w.step(60, _fwd())
	check(not (Player.State.VAULT in w.states_seen) and not (Player.State.MANTLE in w.states_seen), "no vault or mantle")
	check(p.global_position.z > -4.0, "still on this side (z %.2f)" % p.global_position.z)


## A thin railing in front of a lower walkway: no mantling through the rail.
func test_no_mantle_through_a_thin_rail() -> void:
	w.add_floor()
	w.add_box(Vector3(0, 0.5, -4.09), Vector3(4, 1.0, 0.18))  # rail, z -4.0 to -4.18
	w.add_box(Vector3(0, 0.3, -5.2), Vector3(4, 0.6, 2.0))  # walkway behind it, lower than the rail
	var p := await _settle()
	await w.step_until(func() -> bool: return p.global_position.z < -3.3, 120, _fwd())
	# Lowest the feet get while the body is over the rail.
	var low := [INF]
	var track := func() -> bool:
		var z := p.global_position.z
		if z < -4.0 + Player.RADIUS - 0.05 and z > -4.18 - Player.RADIUS + 0.05:
			low[0] = minf(low[0], p.global_position.y)
		return false
	w.states_seen.clear()
	await w.press(_fwd_jump())
	await w.step_until(track, 90, _fwd())
	# (A rounded capsule resting on the rail's edge sits a little below its top.)
	check(low[0] > 0.85, "never passes through the rail (lowest feet over it %.2f)" % low[0])


## Scale stays 1: turning every tick while moving used to shrink it.
func test_turning_never_shrinks_the_player() -> void:
	w.add_floor()
	var p := await _settle()
	for i in 600:
		p.yaw = wrapf(p.yaw + 0.037, -PI, PI)
		await w.step(1, _fwd())
	var s := p.global_basis.get_scale()
	check(absf(s.x - 1.0) < 1e-6 and absf(s.z - 1.0) < 1e-6, "scale %s" % s)
