extends SceneTree
## Close shots of slide-under bars (pipes and girders on their posts) in a
## few missions and base maps, for review.
##   xvfb-run -a godot --path . --fixed-fps 60 -s res://art/tools/beam_shots.gd -- <out_dir> [prefix]

const SHOTS := [
	# [mission id or scene, camera position, look at, name]
	["res://maps/rooftops.tscn", Vector3(-6, 12.6, -21), Vector3(0, 11.0, -31), "rooftops_bar"],
	["res://maps/combo_park.tscn", Vector3(-7, 2.4, -86), Vector3(0, 1.0, -96), "park_bars"],
	["m09_rail_bridge", Vector3(-7, 10.6, -40), Vector3(0, 9.0, -50), "m09_bar"],
	["m03_glass_district", Vector3(-7, 16.6, -18), Vector3(0, 15.0, -28), "m03_bar"],
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://beam_shots"
	var prefix: String = args[1] if args.size() > 1 else ""
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	var campaign: Script = load("res://campaign/campaign.gd")
	campaign.persist = false
	for s: Array in SHOTS:
		var id: String = s[0]
		var level: Node
		if id.begins_with("res://"):
			level = (load(id) as PackedScene).instantiate()
		else:
			var all: Array = campaign.missions()
			for i in all.size():
				if all[i].id == id:
					campaign.current = i
			level = load("res://campaign/mission.tscn").instantiate()
		root.add_child(level)
		var p := level.get_node_or_null("Player")
		if p:
			p.set("use_device_input", false)
			p.set_physics_process(false)
		await _frames(6)
		for c in level.find_children("*", "CanvasLayer", true, false):
			(c as CanvasLayer).visible = false
		var cam := Camera3D.new()
		cam.cull_mask &= ~4
		cam.fov = 70.0
		cam.far = 500.0
		level.add_child(cam)
		cam.look_at_from_position(s[1], s[2])
		cam.make_current()
		await _frames(10)
		root.get_texture().get_image().save_png(out.path_join(prefix + String(s[3]) + ".png"))
		print("saved ", s[3])
		level.queue_free()
		await _frames(3)
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame
