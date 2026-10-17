extends TestCase
## The campaign: the mission list matches the story, every built mission
## loads and is safe to stand in, MissionRun's checkpoints, falls,
## objectives, tapes and results work, the radio plays the right lines, the
## Host's chase catches you when you stop, and scripted runs can finish
## missions 0, 2 and 12.

const MISSION := preload("res://campaign/mission.tscn")
const MENU := preload("res://campaign/campaign.tscn")
const PIECE_KEYS := ["box", "building", "prop", "row", "door", "window", "target", "ramp", "loop",
	"quarter_pipe", "bank", "label", "mark", "tape", "fire"]

var level: Node3D
var player: Player
var run: MissionRun


func before_each() -> void:
	Campaign.persist = false
	Campaign.reset_progress()
	Campaign.unlock_all = true


func after_each() -> void:
	Engine.time_scale = 1.0
	if is_instance_valid(level):
		level.queue_free()
	level = null
	await tree.process_frame


func _load(i: int) -> void:
	Campaign.current = i
	level = MISSION.instantiate()
	tree.root.add_child(level)
	player = level.get_node("Player")
	player.use_device_input = false
	player.scripted_input = InputFrame.new()
	run = level.run
	await tree.physics_frame


func _step(frames: int, f: InputFrame = null) -> void:
	player.scripted_input = f if f != null else InputFrame.new()
	for i in frames:
		await tree.physics_frame


func _index(id: String) -> int:
	var all := Campaign.missions()
	for i in all.size():
		if all[i].id == id:
			return i
	return -1


# ---------------------------------------------------------------- data

func test_campaign_lists_the_story() -> void:
	var all := Campaign.missions()
	check(all.size() == 13, "13 missions (%d)" % all.size())
	check(Campaign.acts().size() == 3, "three acts")
	for i in all.size():
		check(int(all[i].number) == i, "mission %d is numbered in order" % i)
		check(all[i].get("beat", "") != "", "%s has its story beat" % all[i].title)
	check(Campaign.entry(12).get("unlocks", "") == "echo", "the finale unlocks Echo")
	for id: String in ["m00_dawn_run", "m01_the_yard", "m02_on_air", "m12_signal_out"]:
		check(Campaign.is_built(_index(id)), "%s is built" % id)


func test_mission_files_are_well_formed() -> void:
	for i in Campaign.mission_count():
		if not Campaign.is_built(i):
			continue
		var m := Campaign.load_mission(i)
		var title: String = m.get("title", "?")
		check(m.get("id", "") == Campaign.entry(i).id, "%s: id matches the index" % title)
		check(not m.get("objectives", []).is_empty(), "%s has objectives" % title)
		for p: Dictionary in m.get("pieces", []):
			var known := false
			for k: String in PIECE_KEYS:
				if p.has(k):
					known = true
			check(known, "%s: known piece %s" % [title, p])
			if p.has("prop") or p.has("row"):
				check(PropKit_has(p.get("prop", p.get("row", ""))), "%s: prop %s exists" % [title, p])
		for r: Dictionary in m.get("radio", []):
			check(RadioFeed.SPEAKERS.has(r.get("who", "")), "%s: speaker %s" % [title, r.get("who", "")])
			check(r.has("on") or r.has("at"), "%s: radio line has a trigger" % title)
		var pool: Dictionary = m.get("chatter", {})
		for k: String in pool:
			for r: Dictionary in pool[k]:
				check(RadioFeed.SPEAKERS.has(r.get("who", "")), "%s: chatter speaker %s" % [title, r.get("who", "")])


func PropKit_has(n: String) -> bool:
	return MissionBuilder.PropKit.has(n)


# ---------------------------------------------------------------- loading

func test_every_built_mission_loads_and_spawns_are_standable() -> void:
	for i in Campaign.mission_count():
		if not Campaign.is_built(i):
			continue
		await _load(i)
		var b: MissionBuilder = level.builder
		var title: String = b.mission.title
		check(b.spawns.size() == 1 + b.mission.get("checkpoints", []).size(), "%s: a spawn per checkpoint" % title)
		for s in b.spawns.size():
			level.go_to_zone(s)
			await _step(40)
			check(player.state == Player.State.GROUND, "%s spawn %d: standing (%s)" % [title, s + 1, Player.State.keys()[player.state]])
			check_near(player.global_position.y, b.spawns[s].origin.y, 0.08, "%s spawn %d: at its height" % [title, s + 1])
			var z0 := player.global_position.z
			await _step(25, TestWorld.forward_input())
			check(z0 - player.global_position.z > 1.5, "%s spawn %d: free to run forward" % [title, s + 1])
		level.queue_free()
		await tree.process_frame


func test_menu_lists_every_mission() -> void:
	var menu: Control = MENU.instantiate()
	tree.root.add_child(menu)
	await tree.process_frame
	check(menu._buttons.size() == Campaign.mission_count(), "a button per mission")
	menu._select(3)
	check(menu._play.disabled, "an unbuilt mission can't be played")
	menu._select(0)
	check(not menu._play.disabled, "mission 0 can")
	menu.queue_free()
	await tree.process_frame


# ---------------------------------------------------------------- rules

func test_checkpoints_falls_and_objectives() -> void:
	await _load(_index("m00_dawn_run"))
	await _step(5)
	check(run.phase == MissionRun.Phase.READY, "waits at the start")
	check(run.objective == 0, "first objective active")
	player.global_position = Vector3(0, 10.05, -8)
	await _step(3)
	check(run.phase == MissionRun.Phase.RUNNING, "leaving the start starts the clock")
	player.global_position = Vector3(0, 10.05, -46)
	await _step(3)
	check(run.checkpoint == 1, "first checkpoint (%d)" % run.checkpoint)
	player.global_position = Vector3(0, 1.0, -75)
	await _step(3)
	check(run.falls == 1, "a fall is counted")
	check(player.global_position.distance_to(level.builder.spawns[1].origin) < 1.0, "back at the checkpoint")
	check(run.phase == MissionRun.Phase.RUNNING, "the clock keeps going")
	# Through the drop zone: the first objective completes.
	player.global_position = Vector3(0, 13.05, -109)
	await _step(3)
	check(run.objective == 1, "delivered: on to the next objective")
	player.global_position = Vector3(0, 4.05, -190)
	await _step(3)
	check(run.phase == MissionRun.Phase.COMPLETE, "reaching camp completes the mission")
	check(Campaign.is_complete(_index("m00_dawn_run")), "progress saved")
	check(level.mission_hud.results_visible(), "results shown")
	check(int(Campaign.best(_index("m00_dawn_run")).ticks) == run.ticks, "best time saved")


func test_zone_key_starts_a_practice_run() -> void:
	await _load(_index("m00_dawn_run"))
	level.go_to_zone(3)
	await _step(3)
	check(run.practice and run.checkpoint == 3, "practice from the third checkpoint")
	check(run.objective == 1, "on that checkpoint's objective (%d)" % run.objective)
	player.global_position = Vector3(0, 4.05, -190)
	await _step(3)
	check(run.phase == MissionRun.Phase.COMPLETE, "can finish")
	check(not Campaign.is_complete(_index("m00_dawn_run")), "but a practice run saves nothing")


func test_tapes_are_collected() -> void:
	await _load(_index("m00_dawn_run"))
	var b: MissionBuilder = level.builder
	check(b.tapes.size() == 1, "mission 0 hides a tape")
	player.global_position = (b.tapes[0].position as Vector3) + Vector3(0, 0.05, 0)
	await _step(2)
	check(run.tapes_found.size() == 1, "standing on it picks it up")
	check(not (b.tapes[0].node as Node3D).visible, "and it disappears")


func test_shoot_and_combo_objectives() -> void:
	await _load(_index("m01_the_yard"))
	var combo: ComboTracker = level.combo
	check(run.current_objective().type == "combo", "starts with the combo")
	combo.add(&"vault", 75, 8.0)
	combo.add(&"backflip", 300, 8.0)
	combo.bank()
	await _step(2)
	check(run.objective == 0, "a x2 combo isn't enough")
	combo.add(&"vault", 75, 8.0)
	combo.add(&"backflip", 300, 8.0)
	combo.add(&"landing_roll", 100, 8.0)
	combo.bank()
	await _step(2)
	check(run.objective == 1, "a x3 combo is (multiplier %d)" % run.best_multiplier)
	var targets: Array[Node] = level.builder.find_children("*", "ShootingTarget", true, false)
	check(targets.size() >= 3, "the yard has dummies (%d)" % targets.size())
	for k in 3:
		(targets[k] as ShootingTarget).killed.emit({"zone": &"body"})
	await _step(2)
	check(run.objective == 2, "three kills done")
	(targets[0] as ShootingTarget).killed.emit({"zone": &"body"})
	(targets[1] as ShootingTarget).killed.emit({"zone": &"head"})
	await _step(2)
	check(run.objective == 2, "only headshots count now")
	(targets[2] as ShootingTarget).killed.emit({"zone": &"head"})
	await _step(2)
	check(run.objective == 3, "two headshots done")


func test_radio_plays_story_lines_and_chatter() -> void:
	await _load(_index("m00_dawn_run"))
	var radio: RadioFeed = level.radio
	radio.advance(0.0)
	check(radio.current.get("who", "") == "mags", "Mags opens the mission")
	var first: String = radio.current.line
	radio.advance(30.0)
	check(radio.current.is_empty() or radio.current.line != first, "lines move on")
	# A zone line: the hurdles.
	player.global_position = Vector3(0, 10.05, -11)
	radio.advance(30.0)
	radio.advance(0.0)
	var heard := radio.history.map(func(l: Dictionary) -> String: return l.line)
	check(heard.any(func(l: String) -> bool: return l.begins_with("Jump into those rails")), "the hurdle tip plays at the hurdles")
	# Chatter only when the radio is free, and not twice in a row.
	radio.queue.clear()
	radio.current = {}
	radio._chatter_ready_at = 0.0
	radio.notify("bail")
	radio.notify("bail")
	check(radio.queue.size() == 1, "one reaction at a time (%d)" % radio.queue.size())
	check(RadioFeed.duration("short") >= 2.0 and RadioFeed.duration("x".repeat(400)) <= 7.0, "durations clamp")


# ---------------------------------------------------------------- the chase

func test_pursuer_follows_your_path() -> void:
	var p := Pursuer.new()
	p.speed = 5.0
	p.speed_gain = 0.0
	p.delay = 1.0
	tree.root.add_child(p)
	p.reset(Vector3.ZERO)
	# You run 10 m/s down -Z for 2 s; he waits 1 s, then runs 5 m/s.
	for i in 120:
		p.tick(Vector3(0, 0, -10.0 * (i + 1) / 60.0), 1.0 / 60.0)
	check_near(p.along, 5.0, 0.15, "ran 1 s at 5 m/s along your path")
	check_near(p.gap, 15.0, 0.3, "15 m behind")
	check(not p.has_caught(), "not caught")
	# You stop; he keeps coming.
	for i in 200:
		p.tick(Vector3(0, 0, -20), 1.0 / 60.0)
	check(p.has_caught(), "stopping gets you caught")
	check(p.point_at(7.5).distance_to(Vector3(0, 0, -7.5)) < 0.3, "positions lie on your path")
	p.queue_free()


func test_standing_still_in_the_chase_gets_you_caught() -> void:
	await _load(_index("m12_signal_out"))
	check(run.pursuer != null, "the finale has a pursuer")
	check(player.get_meta("runner") == "echo", "played as Echo")
	await _step(5)
	player.global_position = Vector3(0, 40.05, -6)
	await _step(1)
	check(run.phase == MissionRun.Phase.RUNNING, "the chase starts when you move")
	var caught := false
	for i in 600:
		await tree.physics_frame
		if run.catches > 0:
			caught = true
			break
	check(caught, "the Host catches you if you stand still")
	check(player.global_position.distance_to(level.builder.spawns[0].origin) < 1.0, "back to the checkpoint")
	check(not run.pursuer.visible, "he waits again before coming")


func test_beating_the_finale_unlocks_echo() -> void:
	var i := _index("m12_signal_out")
	check(not Campaign.echo_unlocked(), "locked at first")
	Campaign.record(i, {"ticks": 3000, "score": 100})
	check(Campaign.echo_unlocked(), "unlocked by the finale")
	Campaign.set_runner("echo")
	check(Campaign.runner_for(_index("m02_on_air")) == "echo", "and playable in other missions")
	check(Campaign.runner_for(_index("m00_dawn_run")) == "parker", "except where the story says otherwise")


# ---------------------------------------------------------------- full runs

## Forward with a little strafe to hold lane x (the view faces -Z).
func _steer(x: float) -> InputFrame:
	var side := (x - player.global_position.x) * 0.8 - player.velocity.x * 0.25
	return InputFrame.make(Vector2(clampf(side, -0.6, 0.6), 1.0))


## Same scripted runner as test_maps: [trigger_z, action, lane_x] steps.
## Returns true once the mission is complete; false if it runs out of time
## or passes stop_z first.
func _run_route(route: Array, max_frames := 2400, stop_z := -INF) -> bool:
	var lane: float = route[0][2] if route[0][1] == "" else player.global_position.x
	var next := 0
	var roll_armed := false
	for i in max_frames:
		var pos := player.global_position
		if run.phase == MissionRun.Phase.COMPLETE:
			return true
		if pos.z < stop_z:
			return false
		if OS.has_environment("ROUTE_LOG") and i % 10 == 0:
			print("  t%4d pos %s state %s speed %.1f obj %d falls %d caught %d gap %.1f" % [i, pos.snapped(Vector3.ONE * 0.01), Player.State.keys()[player.state], player.horizontal_speed(), run.objective, run.falls, run.catches, run.pursuer.gap if run.pursuer else 0.0])
		var f := _steer(lane)
		while next < route.size() and pos.z < route[next][0]:
			var step: Array = route[next]
			lane = step[2]
			match step[1]:
				"jump":
					f.jump_pressed = true
					f.jump_held = true
				"crouch":
					f.crouch_pressed = true
					f.crouch_held = true
				"roll":
					roll_armed = true
			next += 1
		if roll_armed and player.state == Player.State.AIR and player.velocity.y < 0.0:
			var q := PhysicsRayQueryParameters3D.create(pos, pos + Vector3.DOWN * 1.2, 1)
			q.exclude = [player.get_rid()]
			if not player.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
				f.crouch_pressed = true
				f.crouch_held = true
				roll_armed = false
		if player.state == Player.State.SLIDE or player.state == Player.State.CROUCH:
			f.crouch_held = player.global_position.z > route[next - 1][0] - 4.0 if next > 0 else false
		if player.state == Player.State.WALLRUN and player.wallrun_angle() < 0.05:
			f.lean = 1.0 if player._lean_toward_wall(1.0) > 0.0 else -1.0
		player.scripted_input = f
		await tree.physics_frame
	return false


const DAWN_RUN_ROUTE := [
	[-12.6, "jump", 0.0], [-19.6, "jump", 0.0], [-26.5, "crouch", 0.0], [-38.8, "jump", 0.0],
	[-42.0, "", 3.3], [-55.0, "crouch", 3.3], [-62.0, "", 5.4], [-71.3, "jump", 7.0],
	[-86.0, "", 0.3], [-90.6, "jump", 0.3], [-102.2, "jump", 0.3], [-110.5, "crouch", 0.3],
	[-122.0, "roll", 0.3], [-130.0, "", 1.5], [-140.6, "jump", 1.5], [-150.6, "jump", 1.5],
	[-160.6, "jump", 1.5], [-171.3, "jump", 1.5],
]


func test_dawn_run_can_be_finished() -> void:
	await _load(_index("m00_dawn_run"))
	await _step(10)
	var done := await _run_route(DAWN_RUN_ROUTE)
	check(done, "a scripted run finishes Dawn Run (stopped at %s, objective %d)" % [player.global_position, run.objective])
	check(run.falls == 0, "without falling (%d)" % run.falls)


const ON_AIR_ROUTE := [
	[-10.4, "jump", 0.0], [-19.5, "crouch", 0.0], [-28.8, "jump", 0.0],
	[-36.0, "", 3.3], [-60.0, "", 5.4], [-69.3, "jump", 7.0],
	[-86.0, "", 0.0], [-112.0, "", -5.4], [-122.0, "", -5.4], [-129.3, "jump", -7.0],
	[-146.0, "", 0.0],
]


func test_on_air_can_be_finished() -> void:
	await _load(_index("m02_on_air"))
	await _step(10)
	# Run to the lookouts, take them out, run on.
	await _run_route(ON_AIR_ROUTE.slice(0, 7), 1200, -88.0)
	check(run.objective == 1, "at the lookouts (objective %d, at %s)" % [run.objective, player.global_position])
	for t in level.builder.find_children("*", "ShootingTarget", true, false):
		(t as ShootingTarget).killed.emit({"zone": &"head"})
	var done := await _run_route(ON_AIR_ROUTE.slice(7), 1200)
	check(done, "a scripted run finishes On Air (stopped at %s, objective %d)" % [player.global_position, run.objective])
	check(run.falls == 0, "without falling (%d)" % run.falls)


const SIGNAL_OUT_ROUTE := [
	[-10.4, "jump", 0.0], [-19.5, "crouch", 0.0], [-26.8, "jump", 0.0],
	[-36.0, "", 3.3], [-54.0, "", 5.4], [-63.3, "jump", 7.0],
	[-78.0, "", 0.3], [-84.4, "jump", 0.3], [-98.0, "roll", 0.3], [-106.0, "", 1.5],
	[-114.6, "jump", 3.75], [-124.6, "jump", 3.75], [-140.0, "", 1.5], [-149.3, "jump", 1.5],
]


func test_signal_out_can_be_escaped() -> void:
	await _load(_index("m12_signal_out"))
	await _step(10)
	var done := await _run_route(SIGNAL_OUT_ROUTE)
	check(done, "a scripted run outruns the Host (stopped at %s)" % player.global_position)
	check(run.catches == 0, "without being caught (%d)" % run.catches)
	check(run.falls == 0, "without falling (%d)" % run.falls)
	check(Campaign.echo_unlocked(), "Echo unlocked")
