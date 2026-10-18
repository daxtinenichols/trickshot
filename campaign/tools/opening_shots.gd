extends SceneTree
## Renders every way through a wall in the route missions: glass panes,
## kick doors and slide holes, each from a few meters back on the approach
## at head height, for review.
##   xvfb-run -a godot --path . --fixed-fps 60 -s res://campaign/tools/opening_shots.gd -- <out_dir> [mission id part]
## Holes are found by the body meta "opening" that route.gd sets on them.
## Scripts run with -s load before the autoloads, so nothing here is typed
## with classes that need them.

var out := "user://opening_shots"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	var only := args[1] if args.size() > 1 else ""
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	var campaign: Script = load("res://campaign/campaign.gd")
	campaign.persist = false
	var all: Array = campaign.missions()
	for i in all.size():
		var id: String = all[i].id
		if only != "" and not id.contains(only):
			continue
		campaign.current = i
		var level: Node = load("res://campaign/mission.tscn").instantiate()
		root.add_child(level)
		var p: Node = level.get_node("Player")
		p.use_device_input = false
		p.set_physics_process(false)
		await _frames(6)
		_hide_ui(level)
		var n := 0
		for o: Node3D in _openings(level):
			var normal := o.global_basis.z.normalized()
			var at := o.global_position
			if o.has_meta("opening"):
				# A hole's body is the wall piece over it.
				at = Vector3(at.x, float(o.get_meta("floor", at.y)), at.z)
			var cam := Camera3D.new()
			cam.cull_mask &= ~4
			cam.fov = 75.0
			cam.far = 400.0
			level.add_child(cam)
			cam.look_at_from_position(at + normal * 7.0 + Vector3(0, 1.7, 0), at + Vector3(0, 1.2, 0))
			cam.make_current()
			await _frames(8)
			var kind := "glass" if o.is_in_group("windows") else ("door" if o.is_in_group("doors") else String(o.get_meta("opening")))
			var img := root.get_texture().get_image()
			img.save_png("%s/%s_%02d_%s.png" % [out, id, n, kind])
			n += 1
			cam.queue_free()
		print("%s: %d openings" % [id, n])
		level.queue_free()
		await _frames(3)
	quit()


## Windows and doors (their own groups) and holes (meta "opening"), in the
## order they were built, skipping a door's second leaf.
func _openings(level: Node) -> Array:
	var found: Array = []
	var stack: Array[Node] = [level]
	while not stack.is_empty():
		var n: Node = stack.pop_front()
		if n is Node3D and (n.is_in_group("windows") or n.is_in_group("doors") or n.has_meta("opening")):
			if not n.has_meta("leaf") or int(n.get_meta("leaf")) == 0:
				found.append(n)
		stack.append_array(n.get_children())
	return found


func _hide_ui(level: Node) -> void:
	for c in level.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false


func _frames(n: int) -> void:
	for i in n:
		await process_frame
