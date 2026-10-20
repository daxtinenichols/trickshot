extends SceneTree
## Where does a mission wrongly end your run as a fall, or let you drop
## through what looks like solid ground? Loads each mission, finds every
## standable top near the course (rays straight down, like reach_probe),
## floods from the start with generous movement limits (a fall ends that
## branch), then prints:
##   false fall  a top you can stand on that MissionRun counts as a fall
##   no floor    a spot with a visible floor mesh and nothing solid in it
##   godot --headless --path . -s res://campaign/tools/fall_probe.gd -- [mission id ...]
## With no ids it probes every mission. FallProbe (tests) uses the same code.

const FallProbe := preload("res://campaign/tools/fall_probe_core.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var ids := OS.get_cmdline_user_args()
	if ids.is_empty():
		for m: Dictionary in (load("res://campaign/campaign.gd") as Script).missions():
			ids.append(m.id)
	for id: String in ids:
		var level := await FallProbe.load_level(self, id)
		var report := FallProbe.probe(level)
		print("%s: %d tops, %d reached, %d false falls, %d no-floor spots" % [id, report.tops, report.reached, report.false_falls.size(), report.no_floor.size()])
		for b: AABB in FallProbe.cluster(report.false_falls):
			print("  false fall  x %.1f..%.1f  y %.1f..%.1f  z %.1f..%.1f" % [b.position.x, b.end.x, b.position.y, b.end.y, b.position.z, b.end.z])
		for p: Vector3 in report.no_floor:
			print("  no floor    %s  %s" % [p.snapped(Vector3.ONE * 0.1), report.no_floor_what[p]])
		for b: AABB in FallProbe.cluster(report.seams):
			print("  seam        x %.1f..%.1f  y %.1f..%.1f  z %.1f..%.1f" % [b.position.x, b.end.x, b.position.y, b.end.y, b.position.z, b.end.z])
		var sample: Array[Vector3] = []
		var st: Array = report.standable
		var every := maxi(st.size() / int(OS.get_environment("DROPS") if OS.has_environment("DROPS") else "400"), 1)
		for i in range(0, st.size(), every):
			sample.append(st[i])
		var through := await FallProbe.drop_through(self, level, sample)
		print("  dropped onto %d tops, went through %d" % [sample.size(), through.size()])
		for b: AABB in FallProbe.cluster(through):
			print("  through     x %.1f..%.1f  y %.1f..%.1f  z %.1f..%.1f" % [b.position.x, b.end.x, b.position.y, b.end.y, b.position.z, b.end.z])
		level.queue_free()
		await process_frame
	quit()
