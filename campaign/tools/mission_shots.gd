extends SceneTree
## Renders the campaign for review: the campaign menu, overview shots of
## each built mission, a first-person shot with the radio and objective up,
## and a results card.
##   xvfb-run -a godot --path . --fixed-fps 60 -s res://campaign/tools/mission_shots.gd -- <out_dir>
## Add a second argument to render only shots whose name contains it, or
## "course:<mission id>" for shots down the course itself: from the start
## and each checkpoint toward the next, at head height and from above, or
## "angled:<mission id>" for shots along its diagonal legs (city edges), or
## "legs:<mission id>" down every leg from just past each corner.
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
	# Stage 5, Westside.
	["l5_1_storm_channels", Vector3(1012, 15, -110), Vector3(960, 4, -110), "ws_5_1_spillway"],
	["l5_1_storm_channels", Vector3(930, 14, -100), Vector3(870, 0, -110), "ws_5_1_channel"],
	["l5_1_storm_channels", Vector3(915, 1.7, -110), Vector3(895, 4, -110), "ws_5_1_listeners", 60],
	["l5_1_storm_channels", Vector3(822, 1.8, -26), Vector3(822, 2.5, -10), "ws_5_1_sluice", 90],
	["l5_1_storm_channels", Vector3(822, 11.7, 306), Vector3(818, 9, 330), "ws_5_1_ward_water", 10],
	["l5_1_storm_channels", Vector3(772, 2, 359.6), Vector3(720, 3, 359.6), "ws_5_1_outflow", 60],
	["l5_1_storm_channels", Vector3(640, 9.7, 359.6), Vector3(600, 11, 359.6), "ws_5_1_rail_line"],
	["l5_2_rail_line", Vector3(606, 11.7, 359.6), Vector3(570, 10, 359.6), "ws_5_2_old_line"],
	["l5_2_rail_line", Vector3(556, 14, 256), Vector3(555, 4, 222), "ws_5_2_blast_nine", 150],
	["l5_2_rail_line", Vector3(555, 11.7, 24), Vector3(555, 13, 6), "ws_5_2_junction", 100],
	["l5_2_rail_line", Vector3(556, 12.5, -78), Vector3(555, 11, -100), "ws_5_2_wagon", 140],
	["l5_2_rail_line", Vector3(556, 14, -96), Vector3(555, 4, -140), "ws_5_2_blast_four", 150],
	["l5_2_rail_line", Vector3(522, 12, -200), Vector3(480, 11, -200), "ws_5_2_station"],
	["l5_2_rail_line", Vector3(452, 11.7, -200), Vector3(150, 70, 20), "ws_5_2_calder_house"],
	["l5_2_rail_line", Vector3(470, 11.7, -200), Vector3(300, 30, -200), "ws_5_2_end_ahead"],
	# Stage 6, Calder House and the Tower (atlas coordinates).
	["l6_1_head_office", Vector3(452, 11.7, -200), Vector3(380, 9, -200), "s6_1_platform"],
	["l6_1_head_office", Vector3(560, 150, -420), Vector3(250, 0, -100), "s6_1_overview"],
	["l6_1_head_office", Vector3(262, 23.7, 74), Vector3(276, 23.0, 68), "s6_1_office"],
	["l6_1_head_office", Vector3(273.5, 23.75, 70.4), Vector3(273.5, 23.7, 67.1), "s6_1_photo"],
	["l6_2_skybridge", Vector3(197, 45.7, 168), Vector3(197, 44, 225), "s6_2_tanks"],
	["l6_2_skybridge", Vector3(0, 44.7, 150), Vector3(0, 46, 20), "s6_2_bridge"],
	["l6_2_skybridge", Vector3(110, 80, 150), Vector3(0, 40, 50), "s6_2_bridge_outside"],
	# Stage 3: the Silt.
	["l3_1_the_silt", Vector3(1792, 9.7, 40), Vector3(1740, 0, 30), "l3_1_wreck"],
	["l3_1_the_silt", Vector3(1720, 22, 70), Vector3(1780, 0, 0), "l3_1_wreck_behind"],
	["l3_1_the_silt", Vector3(1750, 1.7, 30), Vector3(1750, 1.0, -30), "l3_1_bed"],
	["l3_1_the_silt", Vector3(1751, 1.7, -92), Vector3(1755.4, 3.5, -113), "l3_1_relay"],
	["l3_1_the_silt", Vector3(1736, 5.5, -86), Vector3(1736, 3.5, -130), "l3_1_buses"],
	["l3_1_the_silt", Vector3(1750, 1.7, -238), Vector3(1753, 1.5, -270), "l3_1_pens"],
	["l3_1_the_silt", Vector3(1736, 9.5, -360), Vector3(1640, 6.5, -360), "l3_1_outfall"],
	["l3_1_the_silt", Vector3(1578, 1.7, -359), Vector3(1555, 3, -360), "l3_1_drain_mouth"],
	["l3_2_the_drain", Vector3(1558, 1.7, -360), Vector3(1540, 2.5, -352), "l3_2_drain_turn"],
	["l3_2_the_drain", Vector3(1545.9, 1.7, -340), Vector3(1545.9, 2.5, -290), "l3_2_main_pipe"],
	["l3_2_the_drain", Vector3(1546, 1.7, -232), Vector3(1551, 3, -216), "l3_2_ring_pipe"],
	["l3_2_the_drain", Vector3(1545.9, 1.7, -90), Vector3(1545.9, 4, -45), "l3_2_pump_hall"],
	["l3_2_the_drain", Vector3(1539, 4.7, 380), Vector3(1525, 4, 380), "l3_2_grate"],
	["l3_2_the_drain", Vector3(1508, 1.7, 380), Vector3(1470, 3, 380), "l3_2_mall_lot"],
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
	["l6_3_the_climb", Vector3(3, 45.5, 56), Vector3(0, 37, 28), "s6_3_stub"],
	["l6_3_the_climb", Vector3(70, 120, 110), Vector3(0, 50, 0), "s6_3_scaffold"],
	["l6_3_the_climb", Vector3(-28, 46, -18), Vector3(-28, 50, 40), "s6_3_uplink"],
	["l6_3_the_climb", Vector3(40, 58, -30), Vector3(46, 55, 10), "s6_3_cage"],
	["l6_3_the_climb", Vector3(28, 71, 20), Vector3(140, 30, 120), "s6_3_watchers", 2],
	["l6_3_the_climb", Vector3(-28, 46, -18), Vector3(-28, 50, 40), "s6_3_uplink_on", 40],
	["l6_3_the_climb", Vector3(-14, 77, 30), Vector3(0, 76, 22), "s6_3_door"],
	["l6_4_dead_air", Vector3(0, 76.7, 30), Vector3(0, 76, 10), "s6_4_door"],
	["l6_4_dead_air", Vector3(-4, 76.7, 20), Vector3(-12, 76, 4), "s6_4_vents"],
	["l6_4_dead_air", Vector3(15, 81.7, -4), Vector3(15, 84, 10), "s6_4_stairwell"],
	["l6_4_dead_air", Vector3(-12, 86.7, 15), Vector3(-15, 86, -10), "s6_4_corridor"],
	["l6_4_dead_air", Vector3(0, 106.8, 7), Vector3(0, 106, -4), "s6_4_studio"],
	["l6_4_dead_air", Vector3(1.2, 106.9, 1.5), Vector3(0, 106, -6), "s6_4_trap_reunion", 150],
	["l6_4_dead_air", Vector3(1.2, 106.9, 1.5), Vector3(0, 106, -6), "s6_4_trap_fire", 750],
	["l6_4_dead_air", Vector3(1.2, 106.9, 1.5), Vector3(-6, 106, 0), "s6_4_trap_door", 450],
	# Stage 7, Signal Out (atlas): the studio, the chute over the Silt, the
	# west roofs, the bank and the girder (campaign/tools/signal_out_shots.gd
	# plays the fall).
	["l7_1_signal_out", Vector3(-13.2, 106.6, 0), Vector3(4, 106.0, 0), "s7_opening"],
	["l7_1_signal_out", Vector3(4, 108.0, 3.5), Vector3(-14, 105.4, -1), "s7_studio"],
	["l7_1_signal_out", Vector3(-22, 107.2, 3), Vector3(-108, 52, 0), "s7_chute"],
	["l7_1_signal_out", Vector3(-40, 22, -70), Vector3(-55, 10, 10), "s7_over_silt"],
	["l7_1_signal_out", Vector3(-277, 49.7, 14), Vector3(-277, 44, 90), "s7_west_roofs"],
	["l7_1_signal_out", Vector3(-150, 16, 311), Vector3(-80, 0, 311), "s7_down_to_bank"],
	["l7_1_signal_out", Vector3(-88, 2.7, 311.5), Vector3(-21, 1.0, 311), "s7_girder"],
	["l7_1_signal_out", Vector3(-30, 14, 260), Vector3(-53, 0, 311), "s7_crossing"],
	["l7_1_signal_out", Vector3(150, 320, 560), Vector3(-140, 0, 160), "s7_overview"],
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
	if only.begins_with("legs:"):
		await _legs(campaign, only.trim_prefix("legs:"))
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
				var camp: bool = sp.get("kind") == "camp" and sp.get("state") == "intact"
				# Other set pieces in sight (Westside's blasts, wagon, signals).
				var near: bool = sp is Node3D and sp.get("fired") == false and sp.has_method("_fire") \
					and (sp as Node3D).global_position.distance_to(s[1]) < 90.0
				if near:
					sp.set("fired", true)
				if camp or near:
					sp.call("_fire")
					for t in int(s[4]):
						sp.call("tick", s[1], null)
				elif sp.get("kind") in ["trap", "uplink", "cage", "watchers"]:
					# Stage 6's: fired where they'd fire, then on (shots of
					# one level add up their ticks).
					for t in int(s[4]):
						sp.call("tick", sp.get("trigger"), null)
		var cam := Camera3D.new()
		cam.cull_mask &= ~4
		cam.fov = 75.0
		cam.far = 600.0 if s.size() > 4 or String(s[0]).begins_with("l") else 500.0
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


## Down every leg of a route with corners: from just past each corner (and
## the start) along the leg at head height, and from above and behind, with
## the player hidden. With "+fire" after the id ("legs:<id>+fire") every
## set piece is fired first and run on a few seconds.
func _legs(campaign: Script, id: String) -> void:
	var fire := id.ends_with("+fire")
	id = id.trim_suffix("+fire")
	var level: Node = await _load_mission(campaign, id)
	var m: Dictionary = level.builder.mission
	var legs: Array = m.get("route_legs", [])
	var space := (level as Node3D).get_world_3d().direct_space_state
	(level.get_node("Player") as Node3D).visible = false
	_hide_ui(level, true)
	if fire:
		for sp: Node3D in level.builder.set_pieces:
			sp.tick(sp.trigger, null)
			for k in 200:
				sp.tick(sp.trigger + Vector3(0, 0, -float(k) * 0.2).rotated(Vector3.UP, sp.rotation.y), null)
	for i in legs.size():
		var yaw: float = legs[i][2]
		var o := Vector3(legs[i][0], 0, legs[i][1])
		var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
		var at := o + fwd * (8.0 if i > 0 else 6.0)
		if i == 0 and m.has("start"):
			var s: Array = m.start.at
			at = Vector3(s[0], 0, s[2]) + fwd * 2.0
		var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 60, 0), at - Vector3(0, 10, 0))
		# The floor: the first thing straight down, or indoors (something
		# a few meters under that) the floor under the ceiling.
		var hits: Array[float] = []
		var from := at + Vector3(0, 60, 0)
		for k in 2:
			q = PhysicsRayQueryParameters3D.create(from, at - Vector3(0, 10, 0))
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				break
			hits.append((hit.position as Vector3).y)
			from = (hit.position as Vector3) - Vector3(0, 0.6, 0)
		at.y = 0.0 if hits.is_empty() else hits[0]
		if hits.size() == 2 and hits[0] - hits[1] > 2.5 and hits[0] - hits[1] < 16.0:
			at.y = hits[1]
		for v: Array in [["eye", Vector3(0, 1.7, 0), 0.0], ["high", Vector3(0, 4.5, 0), 6.0]]:
			var cam := Camera3D.new()
			cam.cull_mask &= ~4
			cam.fov = 75.0
			cam.far = 600.0
			level.add_child(cam)
			cam.look_at_from_position(at + v[1] - fwd * float(v[2]), at + fwd * 30.0 + Vector3(0, 1.0, 0))
			cam.make_current()
			await _frames(8)
			_save("%s_leg%02d_%s" % [id, i, v[0]])
			cam.queue_free()
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
