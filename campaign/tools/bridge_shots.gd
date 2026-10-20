extends SceneTree
## Renders Glass District's Silt bridge going down, frame by frame, from the
## side and over Parker's shoulder (first person), for review:
##   xvfb-run -a godot --path . --fixed-fps 60 -s res://campaign/tools/bridge_shots.gd -- <out_dir> [mission id] [side|fp] [camera x,y,z]
## Writes side_NNNN.png and fp_NNNN.png (every third tick); join them with
##   ffmpeg -framerate 20 -i side_%04d.png -pix_fmt yuv420p side.mp4
## Scripts run with -s load before the autoloads, so nothing here is typed
## with classes that need them.

var out := "user://bridge_shots"
var mission := "m03_glass_district"
## The chase camera (behind and above Parker: the city walls the
## bridge in, so a true side view sees only buildings), local to the bridge's collapse (the end mark; -Z on
## across the bridge), and what it looks at.
var side_at := Vector3(3, 7, 16)
var side_look := Vector3(0, -4, -34)
## Ticks to keep filming after the level is won.
const AFTER := 480


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	if args.size() > 1:
		mission = args[1]
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	var campaign: Script = load("res://campaign/campaign.gd")
	campaign.persist = false
	if args.size() > 3:
		var v := args[3].split_floats(",")
		side_at = Vector3(v[0], v[1], v[2])
	var views: Array = [args[2]] if args.size() > 2 else ["side", "fp"]
	for view: String in views:
		await _film(campaign, view)
	quit()


func _film(campaign: Script, view: String) -> void:
	var all: Array = campaign.missions()
	for i in all.size():
		if all[i].id == mission:
			campaign.current = i
	var level: Node = load("res://campaign/mission.tscn").instantiate()
	root.add_child(level)
	var p: Node3D = level.get_node("Player")
	p.use_device_input = false
	await _frames(6)
	var bridge: Node3D = null
	for sp: Node3D in level.builder.set_pieces:
		if sp.get("kind") == "bridge_collapse":
			bridge = sp
	if bridge == null:
		push_error("bridge_shots: %s has no bridge_collapse" % mission)
		level.queue_free()
		return
	# Every goal but the last done, then a run-up onto the bridge.
	var objs: Array = level.run.objectives
	for i in objs.size() - 1:
		if objs[i].get("type", "reach") == "reach":
			p.global_position = Vector3(objs[i].at[0], objs[i].at[1] + 0.1, objs[i].at[2])
			await _frames(2)
	p.global_position = bridge.to_global(Vector3(0, 0.1, 16))
	p.velocity = Vector3.ZERO
	var yaw: float = bridge.global_rotation.y
	p.set_view(yaw, -0.08 if view == "fp" else 0.0)
	var cam: Camera3D = null
	if view == "side":
		cam = Camera3D.new()
		cam.cull_mask &= ~4
		cam.fov = 70.0
		cam.far = 600.0
		level.add_child(cam)
		cam.look_at_from_position(bridge.to_global(side_at), bridge.to_global(side_look))
		cam.make_current()
	for c in level.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = view == "fp" and (c == level.radio or c == level.mission_hud)
	var frame := 0
	var after := -1
	var tick := 0
	while after < AFTER and tick < 2400:
		# Run to the end mark, then stand and watch.
		var won: bool = level.run.phase == level.run.Phase.COMPLETE
		if won and after < 0:
			after = 0
		var f: Object = load("res://player/input_frame.gd").new()
		if not won and bridge.to_local(p.global_position).z > 1.5:
			f.move = Vector2(0, 1)
		p.scripted_input = f
		await physics_frame
		await process_frame
		tick += 1
		if after >= 0:
			after += 1
		if tick % 3 == 0:
			root.get_texture().get_image().save_png(out.path_join("%s_%04d.png" % [view, frame]))
			frame += 1
	print("%s: %d frames" % [view, frame])
	level.queue_free()
	await _frames(3)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
