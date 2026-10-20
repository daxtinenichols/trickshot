extends SceneTree
## Lists enemies standing inside walls and props sunk into walls or each
## other, in every mission and base map.
##   godot --headless --path . --fixed-fps 60 -s res://art/tools/clip_audit.gd [-- filter]

const BASES := ["res://maps/rooftops.tscn", "res://maps/combo_park.tscn", "res://maps/mall.tscn", "res://levels/sandbox.tscn"]
const CLIP := "res://art/look/clipping.gd"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var only := args[0] if args.size() > 0 else ""
	var campaign: Script = load("res://campaign/campaign.gd")
	campaign.persist = false
	var clip: Script = load(CLIP)
	var ids: Array = []
	for m: Dictionary in campaign.missions():
		ids.append(m.id)
	var total := 0
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
		for i in 4:
			await physics_frame
		var found: Array = clip.find(level)
		print("== %s  %d stuck" % [id, found.size()])
		for f: Dictionary in found:
			print("  %s %s at %s in %s" % [f.what, level.get_path_to(f.node), f.at.snappedf(0.1), f.into])
		total += found.size()
		level.queue_free()
		await process_frame
		await process_frame
	print("TOTAL stuck %d" % total)
	quit()
