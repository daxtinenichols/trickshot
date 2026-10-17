extends TestCase
## Slow motion on the wheel click: drops to 40% for a while, then cools down;
## the simulation's tick length stays 1/60 s, the vignette, and a smooth view.

var w: TestWorld


func before_each() -> void:
	SlowMo.reset()


func after_each() -> void:
	SlowMo.duration = 3.0
	SlowMo.cooldown = 6.0
	SlowMo.reset()
	if is_instance_valid(w):
		w.queue_free()
	w = null
	await tree.process_frame


func _press(ev: InputEvent) -> void:
	ev.pressed = true
	SlowMo._unhandled_input(ev)


func _click() -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_MIDDLE
	_press(ev)


## Runs SlowMo's clock for `seconds` of real time in 1/60 s frames.
func _run(seconds: float) -> void:
	for i in roundi(seconds * 60.0):
		SlowMo._process(Engine.time_scale / 60.0)


func test_click_eases_down_to_40_percent() -> void:
	_click()
	check(SlowMo.is_active(), "a wheel click starts slow-mo")
	_run(0.05)
	check(SlowMo.speed < 1.0 and SlowMo.speed > 0.4, "eases down rather than snapping (%.2f)" % SlowMo.speed)
	_run(0.2)
	check_near(SlowMo.speed, 0.4, 0.001, "settles at 40%")
	check_near(Engine.time_scale, 0.4, 0.001, "time runs at 40%")
	check(Engine.physics_ticks_per_second == 24, "ticks run less often (%d per second)" % Engine.physics_ticks_per_second)
	check_near(Engine.time_scale / Engine.physics_ticks_per_second, 1.0 / 60.0, 1e-9, "each tick is still 1/60 s")


func test_slow_mo_runs_out_then_cools_down() -> void:
	_click()
	_run(SlowMo.duration + 0.5)
	check(not SlowMo.is_active() and SlowMo.speed == 1.0, "ends on its own and eases back to normal")
	check(SlowMo.cooldown_left() > 0.0 and SlowMo.label.text.begins_with("slow-mo in"), "then cools down (%s)" % SlowMo.label.text)
	_click()
	check(not SlowMo.is_active(), "can't use it again while cooling down")
	_run(SlowMo.cooldown)
	check(SlowMo.cooldown_left() == 0.0 and not SlowMo.label.visible, "ready again")
	_click()
	check(SlowMo.is_active(), "and works again")


func test_click_again_ends_it_early() -> void:
	_click()
	_run(1.0)
	_click()
	check(not SlowMo.is_active() and SlowMo.cooldown_left() == 1.0, "a second click ends it and starts the cooldown")
	_run(0.5)
	check(SlowMo.speed == 1.0, "back to normal speed")


func test_scrolling_does_nothing() -> void:
	for button: MouseButton in [MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_UP]:
		var ev := InputEventMouseButton.new()
		ev.button_index = button
		_press(ev)
	_run(0.5)
	check(not SlowMo.is_active() and SlowMo.speed == 1.0, "the wheel no longer changes the speed")


func test_dpad_down_on_a_controller() -> void:
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_DPAD_DOWN
	pad.device = 0
	_press(pad)
	check(SlowMo.is_active(), "D-pad down starts slow-mo")


func test_f3_holds_slow_motion_for_testing() -> void:
	var f3 := InputEventKey.new()
	f3.physical_keycode = KEY_F3
	_press(f3)
	_run(SlowMo.duration + 1.0)
	check(SlowMo.is_active() and SlowMo.speed == 0.4, "F3 holds 40% with no time limit")
	_press(f3)
	_run(0.5)
	check(SlowMo.speed == 1.0 and SlowMo.cooldown_left() == 0.0, "F3 again is normal speed, with no cooldown")


func test_vignette_only_in_slow_motion() -> void:
	check(not SlowMo.vignette.visible and not SlowMo.label.visible, "no vignette at normal speed")
	_click()
	_run(0.05)
	var light: float = (SlowMo.vignette.material as ShaderMaterial).get_shader_parameter("strength")
	check(SlowMo.vignette.visible and SlowMo.label.text == "SLOW-MO", "vignette and readout in slow motion (%s)" % SlowMo.label.text)
	_run(0.3)
	var heavy: float = (SlowMo.vignette.material as ShaderMaterial).get_shader_parameter("strength")
	check(heavy > light, "fades in as time slows (%.2f then %.2f)" % [light, heavy])
	SlowMo.reset()
	check(not SlowMo.vignette.visible, "gone at normal speed")


## Slow motion that stays on while a test watches it.
func _hold_slow() -> void:
	SlowMo.duration = 1000.0
	SlowMo.trigger()
	SlowMo.set_speed(SlowMo.MIN_SPEED)


func test_follows_a_reset_to_normal_speed() -> void:
	_hold_slow()
	Engine.time_scale = 1.0  # what changing level does
	await tree.process_frame
	await tree.process_frame
	check(SlowMo.speed == 1.0 and Engine.physics_ticks_per_second == 60, "tick rate follows back to normal")


func _running_player() -> Player:
	w = TestWorld.new()
	tree.root.add_child(w)
	w.add_floor()
	var p := w.spawn_player(Vector3(0, 0.05, 0))
	p.scripted_input = TestWorld.forward_input()
	return p


func test_slow_motion_keeps_the_tick_length() -> void:
	var p := _running_player()
	for i in 60:
		await tree.physics_frame
	var full_t := p.global_position.z
	_hold_slow()
	var count := [0]  # array: lambdas capture locals by value
	var frames := 0
	var z0 := p.global_position.z
	var ticked := func() -> void: count[0] += 1
	tree.physics_frame.connect(ticked)
	while frames < 120:
		await tree.process_frame
		frames += 1
	tree.physics_frame.disconnect(ticked)
	var ticks: int = count[0]
	check_between(ticks, 43, 53, "40% of the ticks (%d in %d frames)" % [ticks, frames])
	var per_tick := (z0 - p.global_position.z) / maxf(ticks, 1)
	check_near(per_tick, p.horizontal_speed() / 60.0, 0.02, "each tick still moves 1/60 s worth (%.3f m)" % per_tick)
	check(full_t < 0.0, "was running")


## Waits a frame and returns once the view is placed as it will be drawn.
## (process_frame fires after the frame's ticks but before the player's
## _process, so run that now; a zero delta changes nothing else.)
func _frame(p: Player) -> void:
	await tree.process_frame
	p._process(0.0)


func test_view_is_smooth_in_slow_motion() -> void:
	var p := _running_player()
	for i in 60:
		await tree.physics_frame
	_hold_slow()
	await tree.process_frame
	var biggest := 0.0
	var last := p.camera.global_position.z
	for i in 40:
		await _frame(p)
		var now := p.camera.global_position.z
		biggest = maxf(biggest, absf(now - last))
		last = now
	# A tick moves you ~0.19 m; two or three frames share it instead of one
	# taking it all.
	check(biggest < 0.12, "the view moves a little every frame, not in jumps on ticks (biggest step %.3f m)" % biggest)
	# Looking around answers straight away, between ticks.
	p.use_device_input = false
	# Just after a tick (physics_frame fires before it runs, process_frame
	# after it), so the next tick is 2-3 frames away.
	await tree.physics_frame
	await tree.process_frame
	var before := -p.camera.global_basis.z
	p._look(0.3, 0.0)
	await _frame(p)
	var turned := rad_to_deg(before.angle_to(-p.camera.global_basis.z))
	check(turned > 15.0, "the view turns right away (%.1f deg)" % turned)
