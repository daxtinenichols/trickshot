extends SceneTree
## Lists z-fighting faces (two looks in one plane, see art/look/coplanar.gd)
## in every mission and base map, worst first.
##   godot --headless --path . --fixed-fps 60 -s res://art/tools/coplanar_audit.gd [-- filter [max_rows]]

const COPLANAR := "res://art/look/coplanar.gd"
const BASES := ["res://maps/rooftops.tscn", "res://maps/combo_park.tscn", "res://maps/mall.tscn", "res://levels/sandbox.tscn"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var only := args[0] if args.size() > 0 else ""
	var rows := int(args[1]) if args.size() > 1 else 25
	var campaign: Script = load("res://campaign/campaign.gd")
	campaign.persist = false
	var coplanar: Script = load(COPLANAR)
	# Headless runs leave the look off; the audit needs what players see.
	root.get_node("ArtLook").set("auto_attach", true)
	var ids: Array = []
	for m: Dictionary in campaign.missions():
		ids.append(m.id)
	var grand := 0
	for id: String in ids + BASES:
		if only != "" and not id.contains(only):
			continue
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
		for i in 6:
			await physics_frame
		var t0 := Time.get_ticks_msec()
		var found: Array = coplanar.find(level)
		var area := 0.0
		for f: Dictionary in found:
			area += f.area
		print("== %s  %d fighting pairs, %.1f m2  (%d ms)" % [id, found.size(), area, Time.get_ticks_msec() - t0])
		for f: Dictionary in found.slice(0, rows):
			print("  %6.2f m2 at %s\n      %s [%s]\n      %s [%s]" % [f.area, f.at.snappedf(0.1),
				level.get_path_to(f.a), _look(f.a), level.get_path_to(f.b), _look(f.b)])
		grand += found.size()
		level.queue_free()
		await process_frame
		await process_frame
	print("TOTAL fighting pairs %d" % grand)
	quit()


func _look(mi: MeshInstance3D) -> String:
	var body := mi.get_parent()
	var parts: Array = [mi.mesh.get_class()]
	if mi.mesh is BoxMesh:
		parts.append("size %s pos %s grow %s" % [(mi.mesh as BoxMesh).size.snappedf(0.01), mi.global_position.snappedf(0.01), mi.get_meta("box_grow", 0.0)])
	for k in ["kind", "look", "dress"]:
		if body.has_meta(k):
			parts.append("%s=%s" % [k, body.get_meta(k)])
	return " ".join(parts)
