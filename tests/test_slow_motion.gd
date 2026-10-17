extends TestCase
## The scroll wheel's slow motion: speed steps, never faster than normal,
## the simulation's tick length stays 1/60 s, the vignette, and a smooth view.

var w: TestWorld


func before_each() -> void:
	SlowMo.set_speed(1.0)


func after_each() -> void:
	SlowMo.set_speed(1.0)
	if is_instance_valid(w):
		w.queue_free()
	w = null
	await tree.process_frame


func _wheel(button: MouseButton) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	SlowMo._unhandled_input(ev)


func test_wheel_slows_time_in_steps() -> void:
	for i in 3:
		_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	check_near(SlowMo.speed, 0.7, 0.001, "three notches down is 70%")
	check_near(Engine.time_scale, 0.7, 0.001, "time runs at 70%")
	check(Engine.physics_ticks_per_second == 42, "ticks run less often (%d per second)" % Engine.physics_ticks_per_second)
	check_near(Engine.time_scale / Engine.physics_ticks_per_second, 1.0 / 60.0, 1e-9, "each tick is still 1/60 s")
	for i in 20:
		_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	check_near(SlowMo.speed, 0.1, 0.001, "bottoms out at 10%")


func test_wheel_up_only_returns_to_normal_speed() -> void:
	_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	for i in 6:
		_wheel(MOUSE_BUTTON_WHEEL_UP)
	check_near(SlowMo.speed, 1.0, 0.001, "back to 100%")
	check(Engine.time_scale == 1.0 and Engine.physics_ticks_per_second == 60, "never faster than normal")


func test_dpad_slows_and_speeds_up() -> void:
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_DPAD_DOWN
	pad.pressed = true
	SlowMo._unhandled_input(pad)
	SlowMo._unhandled_input(pad)
	check_near(SlowMo.speed, 0.8, 0.001, "D-pad down slows time")
	pad.button_index = JOY_BUTTON_DPAD_UP
	for i in 4:
		SlowMo._unhandled_input(pad)
	check_near(SlowMo.speed, 1.0, 0.001, "D-pad up brings it back, no faster")


func test_f3_toggles_slow_motion() -> void:
	var f3 := InputEventKey.new()
	f3.physical_keycode = KEY_F3
	f3.pressed = true
	SlowMo._unhandled_input(f3)
	check_near(SlowMo.speed, 0.3, 0.001, "F3 slows to 30%")
	SlowMo._unhandled_input(f3)
	check_near(SlowMo.speed, 1.0, 0.001, "F3 again is normal speed")


func test_vignette_only_in_slow_motion() -> void:
	check(not SlowMo.vignette.visible and not SlowMo.label.visible, "no vignette at normal speed")
	SlowMo.set_speed(0.9)
	var light: float = (SlowMo.vignette.material as ShaderMaterial).get_shader_parameter("strength")
	check(SlowMo.vignette.visible and SlowMo.label.text == "SLOW-MO 90%", "vignette and readout in slow motion (%s)" % SlowMo.label.text)
	SlowMo.set_speed(0.2)
	var heavy: float = (SlowMo.vignette.material as ShaderMaterial).get_shader_parameter("strength")
	check(heavy > light, "slower is darker (%.2f vs %.2f)" % [heavy, light])
	SlowMo.set_speed(1.0)
	check(not SlowMo.vignette.visible, "gone at normal speed")


func test_follows_a_reset_to_normal_speed() -> void:
	SlowMo.set_speed(0.4)
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
	SlowMo.set_speed(0.25)
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
	check_between(ticks, 25, 35, "a quarter of the ticks (%d in %d frames)" % [ticks, frames])
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
	SlowMo.set_speed(0.25)
	await tree.process_frame
	var biggest := 0.0
	var last := p.camera.global_position.z
	for i in 40:
		await _frame(p)
		var now := p.camera.global_position.z
		biggest = maxf(biggest, absf(now - last))
		last = now
	# A tick moves you ~0.19 m; four frames share it instead of one taking it all.
	check(biggest < 0.09, "the view moves a little every frame, not in jumps on ticks (biggest step %.3f m)" % biggest)
	# Looking around answers straight away, between ticks.
	p.use_device_input = false
	# Just after a tick (physics_frame fires before it runs, process_frame
	# after it), so the next tick is 4 frames away.
	await tree.physics_frame
	await tree.process_frame
	var before := -p.camera.global_basis.z
	p._look(0.3, 0.0)
	await _frame(p)
	var turned := rad_to_deg(before.angle_to(-p.camera.global_basis.z))
	check(turned > 15.0, "the view turns right away (%.1f deg)" % turned)
