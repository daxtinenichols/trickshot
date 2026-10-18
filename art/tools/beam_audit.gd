extends SceneTree
## Lists every thin bar the obstacle dresser turns into a pipe or girder, in
## every mission and base map, and how far the floor is under each end: the
## dress stands it on posts SLIDE_GAP m long, so any other gap floats.
##   godot --headless --path . --fixed-fps 60 -s res://art/tools/beam_audit.gd [-- filter]

const DRESSER := "res://art/look/obstacle_dresser.gd"
const BASES := ["res://maps/rooftops.tscn", "res://maps/combo_park.tscn", "res://maps/mall.tscn", "res://levels/sandbox.tscn"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var only := args[0] if args.size() > 0 else ""
	var campaign: Script = load("res://campaign/campaign.gd")
	campaign.persist = false
	var dresser: Script = load(DRESSER)
	var total := 0
	var floating := 0
	var ids: Array = []
	for m: Dictionary in campaign.missions():
		ids.append(m.id)
	for id: String in ids + BASES:
		if only != "" and not id.contains(only):
			continue
		var level: Node
		if id.begins_with("res://"):
			if not ResourceLoader.exists(id):
				print("missing ", id)
				continue
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
		for i in 4:
			await physics_frame
		var space := root.get_world_3d().direct_space_state
		for body: Node in level.find_children("*", "StaticBody3D", true, false):
			if body.get_meta("kind", "") != "PARKOUR" or body.has_meta("look"):
				continue
			var size: Vector3 = dresser._box_size(body)
			if size == Vector3.ZERO:
				continue
			var forced: String = body.get_meta("dress", "")
			var style: String = forced if forced != "" else dresser.pick_style("PARKOUR", size, body.global_position)
			if style != "pipe":
				continue
			total += 1
			var b := body as Node3D
			var along := b.global_basis.x.normalized() if size.x >= size.z else b.global_basis.z.normalized()
			var half := maxf(size.x, size.z) * 0.5
			var bottom := b.global_position.y - size.y * 0.5
			var gaps: Array = []
			for sgn in [-1.0, 1.0]:
				var end: Vector3 = b.global_position + along * (half - 0.1) * sgn
				end.y = bottom - 0.02
				var q := PhysicsRayQueryParameters3D.create(end, end - Vector3(0, 200, 0))
				q.exclude = [b.get_rid()]
				var hit := space.intersect_ray(q)
				gaps.append(snappedf(end.y - hit.position.y, 0.01) if hit else 999.0)
			var worst: float = maxf(absf(gaps[0] - dresser.SLIDE_GAP), absf(gaps[1] - dresser.SLIDE_GAP))
			var tag := "ok" if worst < 0.1 else "FLOATS"
			if worst >= 0.1:
				floating += 1
			print("%s  %s  at %s  size %s  gaps %s  %s" % [id, tag, b.global_position.snappedf(0.1), size.snappedf(0.01), gaps, b.get_path()])
		level.queue_free()
		await process_frame
		await process_frame
	print("TOTAL pipes %d, floating %d" % [total, floating])
	quit()
