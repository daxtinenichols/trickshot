extends SceneTree
## Renders a few views of the sandbox to PNGs (used for docs and visual checks).
##   xvfb-run godot --path . --rendering-method gl_compatibility -s res://tools/screenshots.gd -- <out_dir>
const SHOTS := [
	# [zone index, position offset, yaw, pitch, name]
	[0, Vector3(0, 0, 0), 0.0, -0.05, "run_track"],
	[1, Vector3(-6, 3, 4), -0.35, -0.25, "vault_lane"],
	[2, Vector3(-8, 4, 4), -0.45, -0.2, "mantle_heights"],
	[3, Vector3(0, 2, -2), 0.0, -0.05, "wallrun"],
	[4, Vector3(6, 3, 4), 0.25, -0.05, "wall_climb"],
	[5, Vector3(14, 6, 2), 0.6, -0.15, "slide_hill"],
	[6, Vector3(14, 6, 2), 0.6, -0.1, "drop_tower"],
	[7, Vector3(0, 2, 2), 0.0, -0.1, "kick_yard"],
	[8, Vector3(0, 0, 0), 0.0, -0.05, "doors_windows"],
	[9, Vector3(0, 0, 0), 0.0, -0.03, "shooting_range"],
]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	var level: Node3D = load("res://levels/sandbox.tscn").instantiate()
	root.add_child(level)
	# Untyped on purpose: naming Player/Pistol here compiles them before the
	# autoloads they use exist, which fails under `-s`.
	var player: Node3D = level.get_node("Player")
	player.use_device_input = false
	player.scripted_input = InputFrame.new()
	for s in SHOTS:
		level.go_to_zone(s[0])
		player.global_position += s[1]
		player.set_physics_process(false)
		player.set_view(s[2], s[3])
		for i in 20:
			await process_frame
		var img := root.get_texture().get_image()
		img.save_png(out.path_join("%s.png" % s[4]))
		print("saved ", s[4])
		player.set_physics_process(true)
	await _body_shots(level, player, out)
	# A hit on the 10 m target, to check the hit marker and damage number.
	level.go_to_zone(9)
	for i in 30:
		await physics_frame
	var gun: Node3D = player.weapon
	var head := Vector3(-124, 1.62, -10)
	var eye: Vector3 = player.camera.global_position
	var d: Vector3 = head - eye
	player.set_view(atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))
	gun.aim_held = true
	for i in 20:
		await physics_frame
	gun.trigger_pressed = true
	for i in 4:
		await process_frame
	root.get_texture().get_image().save_png(out.path_join("range_headshot.png"))
	print("saved range_headshot")
	# A combo in progress (scripted tricks, player held mid-air so it doesn't bank).
	level.go_to_zone(3)
	for i in 10:
		await physics_frame
	player.set_physics_process(false)
	player.global_position += Vector3(0, 3, 0)
	player.velocity = Vector3(0, 0, -9)
	player.state = _state(player, "AIR")
	for t in [&"slide", &"vault", &"wallrun", &"wall_jump", &"backflip", &"backflip"]:
		level.combo.on_trick(t, {"speed": 8.5, "quality": 0.8})
	for i in 4:
		await process_frame
	root.get_texture().get_image().save_png(out.path_join("combo.png"))
	print("saved combo")
	player.set_physics_process(true)
	# Pause menu tabs.
	gun.aim_held = false
	for tab in 3:
		level.menu.open(tab)
		for i in 6:
			await process_frame
		root.get_texture().get_image().save_png(out.path_join("menu_%d.png" % tab))
		print("saved menu_%d" % tab)
	level.menu.close()
	quit()


## The third-person corner view mid-move: physics is paused and the player is
## staged in a state so the body rig poses for it.
func _body_shots(level: Node3D, player: Node3D, out: String) -> void:
	var shots := [
		# [zone, position offset, state, velocity, name]
		[0, Vector3(0, 0, -16), "GROUND", Vector3(0, 0, -10.5), "body_run"],
		[0, Vector3(0, 0, -16), "SLIDE", Vector3(0, 0, -10.0), "body_slide"],
		[0, Vector3(0, 2.2, -16), "AIR", Vector3(0, 1.0, -8.0), "body_backflip"],
		[0, Vector3(0, 1.4, -16), "AIR", Vector3(0, -1.0, -9.0), "body_sideflip"],
		[3, Vector3(-2.1, 1.2, -15), "WALLRUN", Vector3(0, 0.5, -9.5), "body_wallrun"],
	]
	for s in shots:
		level.go_to_zone(s[0])
		player.global_position += s[1]
		player.set_physics_process(false)
		player.set_view(0.0, -0.05)
		player.state = _state(player, s[2])
		player.state_time = 0.2
		player.velocity = s[3]
		player._air_pitch = 0.0
		player._air_roll = 0.0
		match s[4]:
			"body_backflip":
				player._air_pitch = 2.2
				player.pitch = 2.2
			"body_sideflip":
				player._air_roll = 1.9
			"body_wallrun":
				player._wall_normal = Vector3(1, 0, 0)
		for i in 37:
			await process_frame
		root.get_texture().get_image().save_png(out.path_join("%s.png" % s[4]))
		print("saved ", s[4])
		player.set_physics_process(true)


## Player.State value by name, looked up at run time (see the note in _run).
func _state(player: Node3D, state_name: String) -> int:
	return player.get_script().get_script_constant_map()["State"][state_name]
