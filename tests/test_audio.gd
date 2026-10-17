extends TestCase
## GameAudio: synthesised sounds, footsteps that follow pace and ground,
## graded landings, music layers that follow the combo, the radio "on air"
## filter, the slow-mo muffle, and that sound never changes the simulation.

var w: TestWorld


func before_each() -> void:
	w = TestWorld.new()
	tree.root.add_child(w)
	GameAudio.heard.clear()
	GameAudio.enabled = true


func after_each() -> void:
	GameAudio.enabled = true
	SlowMo.reset()
	w.queue_free()
	await tree.process_frame


static func _stats(stream: AudioStreamWAV) -> Vector2:
	var data := stream.data
	var peak := 0.0
	var sum := 0.0
	var n := data.size() / 2
	for i in n:
		var v := absf(data.decode_s16(i * 2) / 32767.0)
		peak = maxf(peak, v)
		sum += v * v
	return Vector2(peak, sqrt(sum / maxf(n, 1)))


func test_every_sound_is_audible_and_unclipped() -> void:
	for sound_name: String in GameAudio.sounds:
		var entry: Variant = GameAudio.sounds[sound_name]
		var list: Array = entry if entry is Array else [entry]
		check(list.size() > 0, "%s has variations" % sound_name)
		for stream: AudioStreamWAV in list:
			var st := _stats(stream)
			check(st.x > 0.2 and st.x < 0.99, "%s peaks between -14 dB and clipping (%.2f)" % [sound_name, st.x])
			check(st.y > 0.005, "%s isn't silent (rms %.4f)" % [sound_name, st.y])


func test_loops_wrap_without_a_click() -> void:
	for sound_name: String in ["wind_low", "wind_high", "slide_concrete", "slide_metal", "radio_crackle"]:
		var stream: AudioStreamWAV = GameAudio.sounds[sound_name]
		check(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "%s loops" % sound_name)
		var n := stream.data.size() / 2
		var jump := absf(stream.data.decode_s16(0) - stream.data.decode_s16((n - 1) * 2)) / 32767.0
		check(jump < 0.15, "%s's seam is smooth (%.3f)" % [sound_name, jump])


func test_music_layers_line_up() -> void:
	var len := -1
	for layer in MusicSynth.Layer.values():
		var s := MusicSynth.render(layer, 2)
		var n := s.data.size()
		if len < 0:
			len = n
		check(n == len, "layer %d is as long as the others" % layer)
		check(s.loop_mode == AudioStreamWAV.LOOP_FORWARD, "layer %d loops" % layer)
		check(_stats(s).y > 0.01, "layer %d plays something" % layer)
	check_near(len / 2.0 / MusicSynth.RATE, MusicSynth.BAR * 2.0, 0.001, "two bars long")


func test_music_layers_follow_the_combo() -> void:
	var L := MusicSynth.Layer
	var idle := GameAudio.layer_targets(0)
	check(idle[L.PAD] == 1.0 and idle[L.BASS] == 0.0 and idle[L.LEAD] == 0.0, "no combo: just the pad")
	check(idle[L.DRUMS] > 0.0 and idle[L.DRUMS] < 1.0, "and quiet drums")
	var one := GameAudio.layer_targets(1)
	check(one[L.DRUMS] == 1.0 and one[L.BASS] == 1.0 and one[L.PERC] == 0.0, "a combo brings in drums and bass")
	check(GameAudio.layer_targets(3)[L.PERC] == 1.0, "3 tricks add percussion")
	check(GameAudio.layer_targets(4)[L.LEAD] == 0.0 and GameAudio.layer_targets(5)[L.LEAD] == 1.0, "5 tricks add the lead")
	check(GameAudio.on_air_target(0) == 1.0 and GameAudio.on_air_target(2) == 0.0, "the radio filter opens during a combo")


func test_combo_milestones_play_radio_jingles() -> void:
	var p := w.spawn_player(Vector3(0, 0.05, 0))
	w.add_floor()
	var c := ComboTracker.new()
	w.add_child(c)
	c.setup(p)
	check(GameAudio.combo == c, "follows the new combo tracker")
	for t: StringName in [&"slide", &"vault", &"wallrun"]:
		c.add(t, 100.0, 8.0)
	GameAudio._process(1.0 / 60.0)
	check(GameAudio.heard.has("sting_1"), "3 tricks: first jingle (%s)" % [GameAudio.heard])
	GameAudio._process(1.0 / 60.0)
	check(GameAudio.heard.count("sting_1") == 1, "only once per combo")
	for k in 30:
		GameAudio._process(1.0 / 60.0)
	check(GameAudio.on_air < 0.5, "the music opens up off the radio (%.2f)" % GameAudio.on_air)
	c.bank(&"rest")
	GameAudio._process(1.0 / 60.0)
	check(GameAudio.heard.has("bank"), "banking rings out")
	c.add(&"slide", 100.0, 8.0)
	c.bail(&"crash")
	GameAudio._process(1.0 / 60.0)
	check(GameAudio.heard.has("bail"), "a bail stings")


func test_footsteps_speed_up_with_pace() -> void:
	check(GameAudio.step_rate(12.0, 11.5) > GameAudio.step_rate(4.0, 11.5) * 1.4, "sprinting steps come faster")
	w.add_floor()
	var p := w.spawn_player(Vector3(0, 0.05, 0))
	check(GameAudio.player == p, "follows the newest player")
	await w.step(30)
	var start := GameAudio._footsteps
	await w.step(120, TestWorld.forward_input())
	var steps := GameAudio._footsteps - start
	check_between(steps, 5, 12, "about 2 to 5 steps a second while running")
	check(GameAudio.heard.has("step_concrete"), "untagged ground sounds like concrete")


func test_ground_type_changes_the_step() -> void:
	var floor := w.add_box(Vector3(0, -0.5, 0), Vector3(200, 1, 200))
	floor.set_meta("kind", "FLOOR")
	check(GameAudio.surface_of(floor) == &"asphalt", "the map's floor is asphalt")
	floor.set_meta("kind", "WALLRUN")
	check(GameAudio.surface_of(floor) == &"metal", "wallrun panels are metal")
	floor.set_meta("look", "FACADE")
	check(GameAudio.surface_of(floor) == &"concrete", "facades are concrete")
	check(GameAudio.surface_of(null) == &"concrete", "nothing found: concrete")
	floor.remove_meta("look")
	w.spawn_player(Vector3(0, 0.05, 0))
	await w.step(5)
	check(GameAudio.surface_under() == &"metal", "reads what you're standing on")


func test_landings_are_graded_by_impact() -> void:
	var soft := GameAudio.landing_grade(3.0, false)
	var hard := GameAudio.landing_grade(15.0, false)
	check(hard.x > soft.x + 10.0, "a hard landing is much louder (%.1f vs %.1f dB)" % [hard.x, soft.x])
	check(hard.y < soft.y, "and deeper")
	check(GameAudio.landing_grade(15.0, true).x < hard.x, "rolling it out softens it")
	w.add_floor()
	var p := w.spawn_player(Vector3(0, 6.0, 0))
	await w.step_until(func() -> bool: return p.state != Player.State.AIR, 120)
	await tree.process_frame
	check(GameAudio.heard.has("land_concrete"), "a drop lands audibly (%s)" % [GameAudio.heard])


func test_moves_make_sounds() -> void:
	w.add_floor()
	var p := w.spawn_player(Vector3(0, 0.05, 0))
	await w.step(30, TestWorld.forward_input())
	await w.press(InputFrame.make(Vector2(0, 1), true), 2)
	check(GameAudio.heard.has("jump"), "jumping")
	await w.step_until(func() -> bool: return p.state == Player.State.GROUND, 120, TestWorld.forward_input())
	var slide := InputFrame.make(Vector2(0, 1), false, true)
	await w.press(slide, 10)
	check(p.state == Player.State.SLIDE, "sliding")
	await tree.process_frame
	check(GameAudio._slide_gain > 0.0 and GameAudio._slide.stream == GameAudio.sounds.slide_concrete, "the slide scrapes")


func test_windows_and_doors_are_heard() -> void:
	w.add_floor()
	w.spawn_player(Vector3(0, 0.05, 0))
	var glass := BreakableWindow.new()
	w.add_child(glass)
	glass.position = Vector3(0, 0, -6)
	var door := KickDoor.new()
	w.add_child(door)
	door.position = Vector3(3, 0, -6)
	await w.step(2)
	glass.shatter(Vector3.FORWARD)
	door.on_kicked(null, Vector3.FORWARD)
	await w.step(2)
	check(GameAudio.heard.has("glass"), "glass breaking (%s)" % [GameAudio.heard])
	check(GameAudio.heard.has("door_bang"), "a door kicked open")


func test_slow_mo_muffles_the_mix() -> void:
	SlowMo.set_speed(1.0)
	GameAudio._process(1.0 / 60.0)
	check(GameAudio._lowpass.cutoff_hz > 15000.0, "full sound at normal speed")
	SlowMo.set_speed(0.4)
	GameAudio._process(0.4 / 60.0)
	check_near(GameAudio.slowed, 1.0, 0.01, "slow-mo at its floor")
	check(GameAudio._lowpass.cutoff_hz < 1500.0, "muffled (%.0f Hz)" % GameAudio._lowpass.cutoff_hz)
	check(GameAudio._reverb.wet > 0.1, "with a little space")
	SlowMo.reset()
	GameAudio._process(1.0 / 60.0)
	check(GameAudio._lowpass.cutoff_hz > 15000.0, "clear again after")


func test_sound_never_changes_the_run() -> void:
	var path := []
	for on in [true, false]:
		GameAudio.enabled = on
		var world := TestWorld.new()
		tree.root.add_child(world)
		world.add_floor()
		world.add_box(Vector3(0, 0.5, -12), Vector3(4, 1, 1))
		var p := world.spawn_player(Vector3(0, 0.05, 0))
		await world.step(40, TestWorld.forward_input())
		await world.press(InputFrame.make(Vector2(0, 1), true), 20)
		await world.press(InputFrame.make(Vector2(0, 1), false, true), 40)
		path.append([p.global_position, p.velocity, p.state])
		world.queue_free()
		await tree.process_frame
	check(path[0][0].is_equal_approx(path[1][0]) and path[0][1].is_equal_approx(path[1][1]) and path[0][2] == path[1][2],
		"same run with sound on and off (%s vs %s)" % [path[0], path[1]])


func test_built_sounds_are_cached_for_next_launch() -> void:
	var saved := GameAudio.cache_path
	GameAudio.cache_path = "user://test_audio_cache.bin"
	var bank := {"one": [SoundBank.jump(0), SoundBank.jump(1)], "loop": SoundBank.wind_loop(false)}
	var layers := [MusicSynth.render(MusicSynth.Layer.DRUMS, 1)]
	var key := GameAudio.cache_key()
	check(key.length() > 40, "keyed on the synth code (%s)" % key)
	GameAudio._write_cache(key, bank, layers)
	check(GameAudio._read_cache("stale").is_empty(), "a cache from other synth code is ignored")
	var back := GameAudio._read_cache(key)
	check(back.sounds.one.size() == 2 and back.sounds.one[1].data == bank.one[1].data, "variations come back intact")
	check(back.sounds.loop.loop_mode == AudioStreamWAV.LOOP_FORWARD and back.sounds.loop.data == bank.loop.data, "loops still loop")
	check(back.music.size() == 1 and back.music[0].data == layers[0].data, "and so does the music")
	DirAccess.remove_absolute(GameAudio.cache_path)
	GameAudio.cache_path = saved
