extends SceneTree
## Renders the campaign for review: the campaign menu, overview shots of
## each built mission, a first-person shot with the radio and objective up,
## and a results card.
##   xvfb-run -a godot --path . --fixed-fps 60 -s res://campaign/tools/mission_shots.gd -- <out_dir>
## Add a second argument to render only shots whose name contains it, or
## "course:<mission id>" for shots down the course itself: from the start
## and each checkpoint toward the next, at head height and from above, or
## "angled:<mission id>" for shots along its diagonal legs (city edges).
## Scripts run with -s load before the autoloads, so nothing here is typed
## with classes that need them.

const SHOTS := [
	# [mission id, camera position, look at, name]
	# Stage 1, the Docks (atlas coordinates). A fifth field fires the
	# level's set pieces that many ticks before the shot (the raid).
	["l1_1_dawn_run", Vector3(3425, 15.5, 141), Vector3(3412, 13, 128), "dk_1_1_opening"],
	["l1_1_dawn_run", Vector3(3452, 32, 168), Vector3(3400, 12, 118), "dk_1_1_camp"],
	["l1_1_dawn_run", Vector3(3228, 40, 150), Vector3(3268, 10, 60), "dk_1_1_fish_market"],
	["l1_1_dawn_run", Vector3(3246, 18, 8), Vector3(3262, 14, -40), "dk_1_1_container_yard"],
	["l1_1_dawn_run", Vector3(3262, 17, -150), Vector3(3340, 9, -160), "dk_1_1_high_roof"],
	["l1_1_dawn_run", Vector3(3259, 16.7, -121), Vector3(3264, 15, -133), "dk_1_1_drop"],
	["l1_1_dawn_run", Vector3(3452, 24, 40), Vector3(3436, 2, 100), "dk_1_1_raid", 300],
	["l1_1_dawn_run", Vector3(3425, 13.7, 112), Vector3(3412, 12.5, 118), "dk_1_1_wreck", 2000],
	["l1_1_dawn_run", Vector3(3428, 16, 124), Vector3(3000, 30, 230), "dk_1_1_skyline_west"],
	["l1_1_dawn_run", Vector3(3424, 13.7, 136), Vector3(0, 120, 0), "dk_1_1_tower_ahead"],
	["l1_2_the_yard", Vector3(3425, 13.7, 117), Vector3(3423, 13.2, 130), "dk_1_2_handoff"],
	["l1_2_the_yard", Vector3(3448, 22, 156), Vector3(3420, 0, 240), "dk_1_2_yard"],
	["l1_2_the_yard", Vector3(3402, 15, 296), Vector3(3300, 3, 330), "dk_1_2_terminal"],
	["l1_2_the_yard", Vector3(3112, 6.5, 321), Vector3(3060, 2.5, 318), "dk_1_2_speed_gate"],
	["l1_2_the_yard", Vector3(2992, 1.7, 318), Vector3(2700, 30, 318), "dk_1_2_gate_west"],
	["l1_2_the_yard", Vector3(2972, 1.7, 318), Vector3(0, 120, 0), "dk_1_2_skyline_west"],
	# Stage 6, Calder House and the Tower (atlas coordinates).
	["l6_1_head_office", Vector3(452, 11.7, -200), Vector3(380, 9, -200), "s6_1_platform"],
	["l6_1_head_office", Vector3(560, 150, -420), Vector3(250, 0, -100), "s6_1_overview"],
	["l6_1_head_office", Vector3(262, 23.7, 74), Vector3(276, 23.0, 68), "s6_1_office"],
	["l6_1_head_office", Vector3(273.5, 23.75, 70.4), Vector3(273.5, 23.7, 67.1), "s6_1_photo"],
	["l6_2_skybridge", Vector3(197, 45.7, 168), Vector3(197, 44, 225), "s6_2_tanks"],
	["l6_2_skybridge", Vector3(0, 44.7, 150), Vector3(0, 46, 20), "s6_2_bridge"],
	["l6_2_skybridge", Vector3(110, 80, 150), Vector3(0, 40, 50), "s6_2_bridge_outside"],
	["m04_silt_line", Vector3(-10, 6, 8), Vector3(0, 0, -40), "m04_silt"],
	["m04_silt_line", Vector3(-3, 1.8, 3), Vector3(0, 6, -40), "m04_wreck"],
	["m04_silt_line", Vector3(-22, 16, 40), Vector3(0, 3, -30), "m04_wreck_behind"],
	["m04_silt_line", Vector3(-14, 14, -215), Vector3(0, 6, -260), "m04_overpass"],
	# Act 2: the mall.
	["m05_atrium", Vector3(-8, 9, -6), Vector3(2, 2, -40), "act2_m05_arena"],
	["m05_atrium", Vector3(-6, 10, -112), Vector3(4, 5, -150), "act2_m05_walkways"],
	["m06_anchor_store", Vector3(9, 9, -343), Vector3(-3, 3, -368), "act2_m06_well"],
	["m06_anchor_store", Vector3(-8, 9.5, -380), Vector3(-22, 7, -360), "act2_m06_electronics"],
	["m05_atrium", Vector3(10.5, 8.2, -219), Vector3(-4, 6.5, -236), "act2_m05_bridge_turn"],
	["m05_atrium", Vector3(-12, 9.5, -250), Vector3(4, 0, -275), "act2_m05_pit"],
	["m06_anchor_store", Vector3(15, 8.2, -352), Vector3(15, 7.2, -386), "act2_m06_to_skybridge"],
	["m06_anchor_store", Vector3(-2, 8.2, -380.5), Vector3(10, 7.5, -380.5), "act2_m06_back_shut"],
	["m07_parking_spiral", Vector3(15, 7.6, -388), Vector3(15, 7.4, -404), "act2_m07_skybridge_in"],
	["m07_parking_spiral", Vector3(0, 11.1, -428), Vector3(0, 19, -470), "act2_m07_skybridge"],
	["m07_parking_spiral", Vector3(-15.5, 21.5, -478), Vector3(-15.5, 17, -520), "act2_m07_top_lap"],
	["m07_parking_spiral", Vector3(-15.5, 8.5, -485), Vector3(-15.5, 5, -530), "act2_m07_lower_lap"],
	["m07_parking_spiral", Vector3(70, 45, -430), Vector3(0, 10, -510), "act2_m07_garage_outside"],
	["m07_parking_spiral", Vector3(8, 4, -486), Vector3(-2, 2, -530), "act2_m07_core"],
	["m08_storm_channels", Vector3(-14, 14, 10), Vector3(0, 4, -40), "m08_start"],
	["m08_storm_channels", Vector3(-11, 7, -104), Vector3(0, 0, -150), "m08_channel"],
	["m08_storm_channels", Vector3(100, 260, 100), Vector3(-220, 0, -400), "m08_overview"],
	["m09_rail_bridge", Vector3(-14, 16, 10), Vector3(0, 8, -40), "m09_start"],
	["m09_rail_bridge", Vector3(-80, 24, -392), Vector3(-150, 8, -426), "m09_junction"],
	["m09_rail_bridge", Vector3(120, 300, 100), Vector3(-260, 0, -420), "m09_overview"],
	["m10_the_climb", Vector3(20, 30, -150), Vector3(-40, 20, -172), "m10_platforms"],
	["m10_the_climb", Vector3(80, 200, 80), Vector3(-90, 30, -90), "m10_overview"],
	["m10_the_climb", Vector3(-62, 52, -70), Vector3(-90, 40, -110), "m10_tower_scaffold"],
	["m10_the_climb", Vector3(30, 40, 20), Vector3(-60, 25, -60), "m10_tower_decks"],
	["m11_dead_air", Vector3(0, 48.6, -36), Vector3(0, 47.5, -80), "m11_lobby"],
	["m11_dead_air", Vector3(100, 260, 60), Vector3(-220, 40, -300), "m11_overview"],
	["m12_signal_out", Vector3(-14, 66, 10), Vector3(0, 56, -30), "m12_tower"],
	["m12_signal_out", Vector3(80, 260, 80), Vector3(-120, 30, -320), "m12_overview"],
	# The route generator's test route: corners, a fork, climbs and ramps.
	["res://tests/fixtures/route_twists.json", Vector3(-150, 300, 120), Vector3(-260, 0, -130), "twists_overview"],
	["res://tests/fixtures/route_twists.json", Vector3(10, 22, -40), Vector3(-30, 10, -66), "twists_corner"],
	["res://tests/fixtures/route_twists.json", Vector3(-160, 30, -40), Vector3(-260, 9, -76), "twists_fork"],
	# 45 degree corners.
	["res://tests/fixtures/route_angles.json", Vector3(-30, 140, 60), Vector3(-60, 0, -120), "angles_overview"],
	["res://tests/fixtures/route_angles.json", Vector3(12, 18, -28), Vector3(-6, 10, -60), "angles_corner"],
]

var out := "user://mission_shots"


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

	if only.begins_with("course:"):
		await _course(campaign, only.trim_prefix("course:"))
		quit()
		return
	if only.begins_with("angled:"):
		await _angled(campaign, only.trim_prefix("angled:"))
		quit()
		return
	if only == "carry":
		await _carry(campaign)
		quit()
		return
	if only != "":
		await _shots(campaign, only)
		quit()
		return
	var menu: Node = load("res://campaign/campaign.tscn").instantiate()
	root.add_child(menu)
	await _frames(4)
	menu._select(2)
	await _frames(3)
	_save("campaign_menu")
	menu.queue_free()
	await _frames(2)

	await _shots(campaign, "")

	# First person, a few seconds in, with the radio and objective up.
	var level: Node = await _load_mission(campaign, "l2_1_on_air")
	var p: Node = level.get_node("Player")
	p.set_physics_process(false)
	# 2-1's first warehouse roof, heading west.
	p.global_position = Vector3(2885, 6, 318)
	p.basis = Basis(Vector3.UP, PI * 0.5)
	p.yaw = PI * 0.5
	p.set_view(0.15, -0.05)
	level.radio.say("host", "Ladies, gentlemen, and... whatever the rest of you are. Our courier has left the building!")
	level.radio.advance(0.0)
	_hide_ui(level, false)
	await _frames(10)
	_save("l2_1_first_person_radio")
	# The results card.
	level.mission_hud.show_results({"seconds": 52.4, "score": 18450, "best_combo": 6200, "par_seconds": 60.0,
		"total_tapes": 1, "tapes": ["x"], "restarts": 1, "practice": false, "records": {"time": true}},
		"On Air", true)
	await _frames(6)
	_save("results")
	quit()


## The overview shots (those whose name contains `only`).
func _shots(campaign: Script, only: String) -> void:
	var current := ""
	var level: Node = null
	for s: Array in SHOTS:
		if not String(s[3]).contains(only):
			continue
		if s[0] != current:
			if level != null:
				level.queue_free()
				await _frames(2)
			current = s[0]
			level = await _load_mission(campaign, current)
		if s.size() > 4:
			# Play the set pieces out first.
			for sp: Node in level.builder.set_pieces:
				if sp.get("kind") == "camp" and sp.get("state") == "intact":
					sp.call("_fire")
					for t in int(s[4]):
						sp.call("tick", s[1], null)
		var cam := Camera3D.new()
		cam.cull_mask &= ~4
		cam.fov = 75.0
		cam.far = 600.0 if s.size() > 4 or String(s[0]).begins_with("l1_") else 500.0
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


## Dawn Run's parcel in hand: first person on the opening roof, then the
## chase camera's view of Parker carrying it, then the toss into the crate.
func _carry(campaign: Script) -> void:
	var level: Node = await _load_mission(campaign, "l1_1_dawn_run")
	var p: Node = level.get_node("Player")
	p.set_physics_process(false)
	p.set_view(PI * 0.5, -0.1)
	_hide_ui(level, false)
	await _frames(10)
	_save("dk_1_1_parcel_first_person")
	var chase: Node = p.get_node_or_null("ChaseCamera")
	if chase != null:
		chase.set_active(true)
		await _frames(20)
		_save("dk_1_1_parcel_third_person")
		chase.set_active(false)
	# The toss: stand short of the drop, deliver, catch it mid-flight.
	var drop: Node = level.run.drop_offs[0]
	p.global_position = Vector3(3260, 15.05, -122)
	p.set_view(0.25, -0.15)
	await _frames(4)
	drop.deliver(p.camera.global_position + Vector3(0.2, -0.25, -0.4), "parcel")
	await _frames(8)
	_save("dk_1_1_parcel_toss")
	await _frames(30)
	_save("dk_1_1_parcel_delivered")
	level.queue_free()
	await _frames(2)


## Down the course: from the start and each checkpoint toward the next one
## (the end after the last), at head height and from 8 m up behind.
func _course(campaign: Script, id: String) -> void:
	var level: Node = await _load_mission(campaign, id)
	var m: Dictionary = level.builder.mission
	var points: Array[Vector3] = [(level.get_node("Player") as Node3D).global_position]
	for c: Dictionary in m.get("checkpoints", []):
		var a: Array = c.get("spawn", c.at)
		var down := 0.0 if c.has("spawn") else float(c.get("size", [0, 4, 0])[1]) * 0.5
		points.append(Vector3(a[0], a[1] - down, a[2]))
	if m.has("route_end"):
		var e: Array = m.route_end
		points.append(Vector3(e[0], e[1], e[2]))
	_hide_ui(level, true)
	for i in points.size() - 1:
		var from := points[i]
		var to := points[i + 1]
		var flat := Vector3(to.x - from.x, 0, to.z - from.z).normalized()
		for v: Array in [["eye", Vector3(0, 1.7, 0), 0.0], ["high", Vector3(0, 8.0, 0), 10.0]]:
			var cam := Camera3D.new()
			cam.cull_mask &= ~4
			cam.fov = 75.0
			cam.far = 600.0
			level.add_child(cam)
			var at: Vector3 = from + v[1] - flat * float(v[2])
			cam.look_at_from_position(at, from + flat * 30.0 + Vector3(0, 1.0, 0))
			cam.make_current()
			await _frames(8)
			_save("%s_course_%02d_%s" % [id, i, v[0]])
			cam.queue_free()
	level.queue_free()
	await _frames(2)


## Along each diagonal leg: at head height down the leg and from above
## and behind, so the city's fronts and kerbs beside it show.
func _angled(campaign: Script, id: String) -> void:
	var level: Node = await _load_mission(campaign, id)
	var m: Dictionary = level.builder.mission
	var legs: Array = m.get("route_legs", [])
	var space := (level as Node3D).get_world_3d().direct_space_state
	_hide_ui(level, true)
	var n := 0
	for i in legs.size() - 1:
		var yaw: float = legs[i][2]
		var y := fposmod(yaw, PI * 0.5)
		if y < 0.01 or y > PI * 0.5 - 0.01:
			continue
		var o := Vector3(legs[i][0], 0, legs[i][1])
		var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
		var length: float = float(legs[i][3]) - float(legs[i + 1][3])
		for v: Array in [["eye", 0.25, Vector3(0, 1.7, 0), 0.0], ["high", 0.2, Vector3(0, 14.0, 0), 12.0], ["mid", 0.55, Vector3(0, 1.7, 0), 0.0]]:
			var at := o + fwd * length * float(v[1])
			var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 200, 0), at - Vector3(0, 10, 0))
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				at.y = (hit.position as Vector3).y
			var cam := Camera3D.new()
			cam.cull_mask &= ~4
			cam.fov = 75.0
			cam.far = 600.0
			level.add_child(cam)
			cam.look_at_from_position(at + v[2] - fwd * float(v[3]), at + fwd * 30.0 + Vector3(0, 1.0, 0))
			cam.make_current()
			await _frames(8)
			_save("%s_leg%d_%s" % [id.get_file().get_basename(), i, v[0]])
			cam.queue_free()
		n += 1
	print("diagonal legs: ", n)
	level.queue_free()
	await _frames(2)


## A mission by id, or any mission data file by its res:// path.
func _load_mission(campaign: Script, id: String) -> Node:
	var all: Array = campaign.missions()
	for i in all.size():
		if all[i].id == id:
			campaign.current = i
	var level: Node = load("res://campaign/mission.tscn").instantiate()
	if id.begins_with("res://"):
		campaign.current = -1
		level.get_node("Builder").mission_path = id
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
