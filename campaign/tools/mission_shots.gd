extends SceneTree
## Renders the campaign for review: the campaign menu, overview shots of
## each built mission, a first-person shot with the radio and objective up,
## and a results card.
##   xvfb-run -a godot --path . --fixed-fps 60 -s res://campaign/tools/mission_shots.gd -- <out_dir>
## Scripts run with -s load before the autoloads, so nothing here is typed
## with classes that need them.

const SHOTS := [
	# [mission id, camera position, look at, name]
	["m00_dawn_run", Vector3(-11, 17, 6), Vector3(0, 10, -30), "m00_start"],
	["m00_dawn_run", Vector3(-12, 13, -180), Vector3(0, 4, -197), "m00_camp"],
	["m01_the_yard", Vector3(-6, 7, 74), Vector3(0, 1, 50), "m01_gate"],
	["m02_on_air", Vector3(-14, 18, 6), Vector3(0, 8, -40), "m02_start"],
	["m02_on_air", Vector3(-12, 16, -150), Vector3(0, 8, -190), "m02_lookouts"],
	["m02_on_air", Vector3(-50, 70, 30), Vector3(0, 8, -300), "m02_overview"],
	["m03_glass_district", Vector3(-14, 22, 10), Vector3(0, 14, -40), "m03_start"],
	["m03_glass_district", Vector3(-12, 18, -236), Vector3(0, 11, -275), "m03_toll_roof"],
	["m03_glass_district", Vector3(-50, 75, 30), Vector3(0, 10, -280), "m03_overview"],
	["m04_silt_line", Vector3(-10, 6, 8), Vector3(0, 0, -40), "m04_silt"],
	["m04_silt_line", Vector3(-14, 14, -215), Vector3(0, 6, -260), "m04_overpass"],
	["m12_signal_out", Vector3(-14, 48, 10), Vector3(0, 38, -30), "m12_tower"],
	["m12_signal_out", Vector3(-16, 35, -100), Vector3(2, 26, -140), "m12_roofs"],
]

var out := "user://mission_shots"


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

	var menu: Node = load("res://campaign/campaign.tscn").instantiate()
	root.add_child(menu)
	await _frames(4)
	menu._select(2)
	await _frames(3)
	_save("campaign_menu")
	menu.queue_free()
	await _frames(2)

	var current := ""
	var level: Node = null
	for s: Array in SHOTS:
		if s[0] != current:
			if level != null:
				level.queue_free()
				await _frames(2)
			current = s[0]
			level = await _load_mission(campaign, current)
		var cam := Camera3D.new()
		cam.cull_mask &= ~4
		cam.fov = 75.0
		cam.far = 500.0
		level.add_child(cam)
		cam.look_at_from_position(s[1], s[2])
		cam.make_current()
		_hide_ui(level, true)
		await _frames(10)
		_save(s[3])
		cam.queue_free()
	if level != null:
		level.queue_free()
		await _frames(2)

	# First person, a few seconds in, with the radio and objective up.
	level = await _load_mission(campaign, "m02_on_air")
	var p: Node = level.get_node("Player")
	p.set_physics_process(false)
	p.global_position = Vector3(0, 8, -40)
	p.set_view(0.15, -0.05)
	level.radio.say("host", "Ladies, gentlemen and whatever's left of you: our courier has left the building!")
	level.radio.advance(0.0)
	_hide_ui(level, false)
	await _frames(10)
	_save("m02_first_person_radio")
	# The results card.
	level.mission_hud.show_results({"seconds": 52.4, "score": 18450, "best_combo": 6200, "par_seconds": 60.0,
		"total_tapes": 1, "tapes": ["x"], "falls": 1, "catches": 0, "practice": false, "records": {"time": true}},
		"On Air", true)
	await _frames(6)
	_save("results")
	quit()


func _load_mission(campaign: Script, id: String) -> Node:
	var all: Array = campaign.missions()
	for i in all.size():
		if all[i].id == id:
			campaign.current = i
	var level: Node = load("res://campaign/mission.tscn").instantiate()
	root.add_child(level)
	var p: Node = level.get_node("Player")
	p.use_device_input = false
	await _frames(6)
	return level


func _hide_ui(level: Node, hide: bool) -> void:
	for c in level.find_children("*", "CanvasLayer", true, false):
		var keep: bool = c == level.radio or c == level.mission_hud
		(c as CanvasLayer).visible = not hide and keep


func _save(shot: String) -> void:
	root.get_texture().get_image().save_png(out.path_join(shot + ".png"))
	print("saved ", shot)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
