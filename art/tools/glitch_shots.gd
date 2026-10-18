extends SceneTree
## Renders fixed views for checking flicker, shadows and clipping, so the
## same shots can be taken before and after a change.
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --fixed-fps 60 -s res://art/tools/glitch_shots.gd -- <out_dir> <shot> [<shot>...]
## A shot is name@level@x,y,z@yaw,pitch (degrees; yaw 0 looks down -Z), or
## name@level@start+<meters> for head height that far down the course from
## the start. level is a mission id or a res:// scene.

const MISSION := "res://campaign/mission.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var campaign: Script = load("res://campaign/campaign.gd")
	campaign.persist = false
	root.size = Vector2i(1280, 720)
	for spec: String in args.slice(1):
		var parts := spec.split("@")
		var level := _open(campaign, parts[1])
		for i in 10:
			await physics_frame
		var player := level.get_node_or_null("Player") as Node3D
		var cam := Camera3D.new()
		cam.near = 0.05
		cam.far = 600.0
		cam.fov = 80.0
		cam.cull_mask &= ~4
		level.add_child(cam)
		if parts[2].begins_with("start"):
			var ahead := float(parts[2].trim_prefix("start+")) if parts[2].contains("+") else 0.0
			var fwd := -player.global_basis.z
			fwd.y = 0.0
			cam.global_position = player.global_position + fwd.normalized() * ahead + Vector3.UP * 1.6
			cam.look_at(cam.global_position + fwd)
		else:
			var p := parts[2].split_floats(",")
			var r := parts[3].split_floats(",")
			cam.global_position = Vector3(p[0], p[1], p[2])
			cam.rotation_degrees = Vector3(r[1], r[0], 0.0)
		cam.current = true
		for i in 30:
			await process_frame
		var img := root.get_texture().get_image()
		img.save_png("%s/%s.png" % [out, parts[0]])
		print("saved ", parts[0])
		level.queue_free()
		await process_frame
		await process_frame
	quit()


func _open(campaign: Script, id: String) -> Node:
	var level: Node
	if id.begins_with("res://"):
		level = (load(id) as PackedScene).instantiate()
	else:
		var all: Array = campaign.missions()
		for i in all.size():
			if all[i].id == id:
				campaign.current = i
		level = load(MISSION).instantiate()
	root.add_child(level)
	var p := level.get_node_or_null("Player")
	if p:
		p.set("use_device_input", false)
		p.set_physics_process(false)
	return level
