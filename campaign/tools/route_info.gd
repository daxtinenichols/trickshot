extends SceneTree
## Prints a route mission's layout: length, legs, where it starts and ends,
## its checkpoints and how many pieces the city and skyline add.
##   godot --headless --path . -s res://campaign/tools/route_info.gd -- res://campaign/missions/<file>.json [path.json]
## With a second path, also writes the route's center line there as
## [[x, z], ...] (for maps of the atlas).

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var t := Time.get_ticks_msec()
	var f := FileAccess.open(args[0], FileAccess.READ)
	var m: Dictionary = JSON.parse_string(f.get_as_text())
	# Speed gates first, as Campaign.load_mission_file does.
	load("res://campaign/route.gd").expand(load("res://campaign/speed_gate.gd").prepare(m))
	print("%s: %d m, expanded in %d ms" % [m.id, int(m.route_length), Time.get_ticks_msec() - t])
	print("start %s  end %s yaw %s" % [m.get("route_origin", {}), m.route_end, m.route_end_yaw])
	for l: Array in m.route_legs:
		print("  leg o (%.1f, %.1f) yaw %.0f z0 %.1f" % [l[0], l[1], rad_to_deg(l[2]), l[3]])
	for c: Dictionary in m.checkpoints:
		print("  checkpoint %s at %s" % [c.name, c.at])
	var counts := {}
	for p: Dictionary in m.pieces:
		var k: String = "city" if p.has("city") else ("skyline" if p.has("skyline") else str(p.keys()[0]))
		counts[k] = counts.get(k, 0) + 1
		if p.has("skyline"):
			print("  skyline: %d boxes, water %s, silt %d, tower %s" % [p.boxes.size(), p.water, p.silt.size(), p.tower])
	print("  pieces ", counts)
	if args.size() > 1:
		var pts: Array = []
		var legs: Array = m.route_legs
		for i in legs.size():
			pts.append([legs[i][0], legs[i][1]])
		pts.append([m.route_end[0], m.route_end[2]])
		pts.push_front([m.route_origin.at[0], m.route_origin.at[2]] if m.has("route_origin") else [0, 0])
		var o := FileAccess.open(args[1], FileAccess.WRITE)
		o.store_string(JSON.stringify(pts))
	quit()
