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
	quit()
