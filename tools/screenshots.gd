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
	var player: Player = level.get_node("Player")
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
	# A hit on the 10 m target, to check the hit marker and damage number.
	level.go_to_zone(9)
	for i in 30:
		await physics_frame
	var gun: Pistol = player.weapon
	var head := Vector3(-124, 1.62, -10)
	var eye := player.camera.global_position
	var d := head - eye
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
	player.state = Player.State.AIR
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
