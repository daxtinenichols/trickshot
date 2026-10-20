extends SceneTree
## Renders the end of Signal Out (Stage 7) for review: the Host following
## Echo onto the girder over the Silt, the far half giving under him, the
## Hollows rising and closing over him, and Echo's drone feed on screen.
##   xvfb-run -a godot --path . --fixed-fps 60 -s res://campaign/tools/signal_out_shots.gd -- <out_dir>
## Scripts run with -s load before the autoloads, so nothing here is typed
## with classes that need them.

var out := "user://shots"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	var campaign: Script = load("res://campaign/campaign.gd")
	campaign.persist = false
	for i in campaign.missions().size():
		if campaign.missions()[i].id == "l7_1_signal_out":
			campaign.current = i
	var level: Node = load("res://campaign/mission.tscn").instantiate()
	root.add_child(level)
	var p: Node3D = level.get_node("Player")
	p.use_device_input = false
	await _physics(6)
	var run: Node = level.get("run")
	var fall: Node3D = null
	for sp: Node3D in level.builder.set_pieces:
		if sp.get("kind") == "silt_fall":
			fall = sp
	var span: float = fall.get("_length")
	var spawn: Transform3D = level.builder.spawns[0]
	p.global_position = spawn.origin + Vector3(-6, 0.05, 0)
	await _physics(2)
	p.global_position = fall.to_global(Vector3(0, 0.05, -span * 0.5))
	await _physics(4)
	var host: Node3D = run.get("pursuer")
	host.set("along", host.call("total") - 7.0)
	host.set("pos", host.call("point_at", host.get("along")))
	p.global_position = fall.to_global(Vector3(0, 0.05, -span - 8.0))
	var cam := Camera3D.new()
	cam.cull_mask &= ~4
	cam.fov = 60.0
	cam.far = 500.0
	level.add_child(cam)
	var side_from := fall.to_global(Vector3(13.0, 5.0, -span * 0.62))
	var side_at := fall.to_global(Vector3(0.0, -0.6, -span * 0.7))
	cam.look_at_from_position(side_from, side_at)
	cam.make_current()
	_hide_ui(level)
	await _physics(16)
	await _frames(2)
	_save("s7_fall_1_on_the_girder")
	# Wait for the break, then the beats after it.
	for i in 300:
		if fall.get("_broken"):
			break
		await _physics(1)
	for beat: Array in [[10, "s7_fall_2_it_gives"], [40, "s7_fall_3_hollows_rise"], [60, "s7_fall_4_they_close"], [70, "s7_fall_5_under"]]:
		await _physics(int(beat[0]))
		await _frames(2)
		_save(beat[1])
		if beat[1] == "s7_fall_3_hollows_rise":
			# What the player sees: Echo's view with the drone feed.
			var fp := Camera3D.new()
			fp.cull_mask &= ~2
			fp.fov = 80.0
			fp.far = 500.0
			level.add_child(fp)
			var eye := p.global_position + Vector3(0, 1.6, 0)
			fp.look_at_from_position(eye, eye + (eye - fall.to_global(Vector3(0, 1.6, -span * 0.4))).normalized() * -1.0)
			fp.make_current()
			await _frames(3)
			_save("s7_fall_echo_view")
			cam.make_current()
			fp.queue_free()
	quit()


func _hide_ui(level: Node) -> void:
	for c in level.find_children("*", "CanvasLayer", true, false):
		var keep: bool = c.name == "EchoCam" or c == level.get("radio")
		(c as CanvasLayer).visible = keep and (c as CanvasLayer).visible


func _save(shot: String) -> void:
	root.get_texture().get_image().save_png(out.path_join(shot + ".png"))
	print("saved ", shot)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _physics(n: int) -> void:
	for i in n:
		await physics_frame
