extends TestCase
## The campaign: the mission list matches the story, every built mission
## loads and is safe to stand in, MissionRun's checkpoints, falls,
## objectives, tapes and results work, the radio plays the right lines, the
## Host's chase catches you when you stop, and scripted runs can finish
## missions 0 and 12 and every mission built from a route.

const MISSION := preload("res://campaign/mission.tscn")
const MENU := preload("res://campaign/campaign.tscn")
const PIECE_KEYS := ["box", "building", "prop", "row", "door", "doors", "window", "target", "ramp", "loop",
	"quarter_pipe", "bank", "label", "mark", "tape", "fire", "encounter", "slab", "figure", "set_piece", "chalk", "light", "skyline"]
const RouteMarker := preload("res://campaign/route_marker.gd")
const MALL := ["m05_atrium", "m06_anchor_store", "m07_parking_spiral"]

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
	# A restart a test didn't wait for leaves a fresh level behind.
	for n: Node in tree.root.get_children():
		if n.scene_file_path == MISSION.resource_path:
			n.queue_free()
	await tree.process_frame


## Waits for the level to restart after a loss and switches to the fresh one.
func _await_restart(max_frames := 120) -> bool:
	var old := level
	for i in max_frames:
		await tree.physics_frame
		if not is_instance_valid(old) or not old.is_inside_tree():
			break
	await tree.process_frame
	var fresh: Node3D = null
	for n: Node in tree.root.get_children():
		if n != old and n.scene_file_path == MISSION.resource_path and not n.is_queued_for_deletion():
			fresh = n
	if fresh == null:
		return false
	level = fresh
	player = level.get_node("Player")
	player.use_device_input = false
	player.scripted_input = InputFrame.new()
	run = level.run
	await tree.physics_frame
	return true


func _load(i: int) -> void:
	Campaign.current = i
	level = MISSION.instantiate()
	tree.root.add_child(level)
	player = level.get_node("Player")
	player.use_device_input = false
	player.scripted_input = InputFrame.new()
	run = level.run
	await tree.physics_frame


## Loads a mission data file that isn't in the campaign (test fixtures).
func _load_file(path: String) -> void:
	Campaign.current = -1
	level = MISSION.instantiate()
	(level.get_node("Builder") as MissionBuilder).mission_path = path
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
	check(all.size() == 16, "16 missions (%d)" % all.size())
	check(Campaign.acts().size() == 6, "the Docks, the Silt, three acts and Stage 6")
	for i in all.size():
		check(int(all[i].number) == i, "mission %d is numbered in order" % i)
		check(all[i].get("beat", "") != "", "%s has its story beat" % all[i].title)
	check(Campaign.entry(all.size() - 1).get("unlocks", "") == "echo", "the finale unlocks Echo")
	for id: String in ["l1_1_dawn_run", "l1_2_the_yard", "m02_on_air", "m12_signal_out"]:
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
			# Forward is the way the spawn faces (routes turn, so not always -Z).
			var p0 := player.global_position
			var fwd := -b.spawns[s].basis.z
			await _step(25, TestWorld.forward_input())
			check((player.global_position - p0).dot(fwd) > 1.5, "%s spawn %d: free to run forward" % [title, s + 1])
		level.queue_free()
		await tree.process_frame


func test_menu_lists_every_mission() -> void:
	var menu: Control = MENU.instantiate()
	tree.root.add_child(menu)
	await tree.process_frame
	check(menu._buttons.size() == Campaign.mission_count(), "a button per mission")
	var unbuilt := range(Campaign.mission_count()).filter(func(i: int) -> bool: return not Campaign.is_built(i))
	if not unbuilt.is_empty():
		menu._select(unbuilt[0])
		check(menu._play.disabled, "an unbuilt mission can't be played")
	menu._select(0)
	check(not menu._play.disabled, "mission 0 can")
	menu.queue_free()
	await tree.process_frame


# ---------------------------------------------------------------- rules

func test_checkpoints_falls_and_objectives() -> void:
	await _load(_index("l1_1_dawn_run"))
	var m: Dictionary = run.mission
	var start := MissionBuilder.vec(m.start.at)
	await _step(5)
	check(run.phase == MissionRun.Phase.READY, "waits at the start")
	check(run.objective == 0, "first objective active")
	player.global_position = start + Vector3(-8, 0.05, 0)
	await _step(3)
	check(run.phase == MissionRun.Phase.RUNNING, "leaving the start starts the clock")
	player.global_position = MissionBuilder.vec(m.checkpoints[0].at) + Vector3(0, 0.05, 0)
	await _step(3)
	check(run.checkpoint == 1, "first checkpoint (%d)" % run.checkpoint)
	# Through the drop zone: the first objective completes.
	player.global_position = MissionBuilder.vec(m.objectives[0].at) + Vector3(0, 0.05, 0)
	await _step(3)
	check(run.objective == 1, "delivered: on to the next objective")
	player.global_position = _camp()
	await _step(3)
	check(run.phase == MissionRun.Phase.COMPLETE, "reaching camp completes the mission")
	check(Campaign.is_complete(_index("l1_1_dawn_run")), "progress saved")
	check(int(Campaign.best(_index("l1_1_dawn_run")).ticks) == run.ticks, "best time saved")
	# The ending is seen, not read over a menu: the results wait for the
	# camp's last lines, and you keep control meanwhile.
	await _step(3)
	check(not level.mission_hud.results_visible(), "no results while the Host and Mags talk")
	check(player.use_device_input or player.scripted_input != null, "still in control")
	for k in 20:
		level.radio.advance(30.0)
	await _step(3)
	check(level.mission_hud.results_visible(), "results shown after the last line")


## Dawn Run's camp: the end of its route, back on the camp roof.
func _camp() -> Vector3:
	var at := MissionBuilder.vec(run.mission.objectives[1].at)
	return Vector3(at.x, 12.05, at.z)


func test_zone_key_starts_a_practice_run() -> void:
	await _load(_index("l1_1_dawn_run"))
	level.go_to_zone(3)
	await _step(3)
	check(run.practice and run.checkpoint == 3, "practice from the third checkpoint")
	check(run.objective == 1, "on that checkpoint's objective (%d)" % run.objective)
	check((player.weapon as Pistol).held == "hands", "past the drop: the parcel's delivered")
	player.global_position = _camp()
	await _step(3)
	check(run.phase == MissionRun.Phase.COMPLETE, "can finish")
	check(not Campaign.is_complete(_index("l1_1_dawn_run")), "but a practice run saves nothing")


## Losing sends you back to the very start (Dax 2026-10-18): a fall past a
## checkpoint, and the restart is a clean run.
func test_a_fall_restarts_the_mission_from_the_start() -> void:
	await _load(_index("l1_1_dawn_run"))
	var lost: Array[String] = []
	run.lost.connect(func(r: String) -> void: lost.append(r))
	await _step(5)
	_leave_start()
	await _step(3)
	player.global_position = _checkpoint(0)
	await _step(3)
	check(run.checkpoint == 1, "past the first checkpoint")
	level.combo.add(&"vault", 75, 8.0)
	player.global_position = _checkpoint(0) + Vector3(0, run.fail_y() - _checkpoint(0).y - 2.0, 0)
	await _step(3)
	check(run.falls == 1 and lost == ["fall"], "a fall loses the run (%s)" % [lost])
	check(run.phase == MissionRun.Phase.LOST, "the clock stops")
	check(level._fade_layer.visible and level._fade_label.text == "FELL", "it fades out on FELL")
	var old := level
	await _step(30)
	check(is_instance_valid(old) and old.is_inside_tree(), "not straight away: the loss reads first")
	check(await _await_restart(), "then the level starts again")
	check(level != old, "as a fresh copy of the level")
	check(player.global_position.distance_to(level.builder.spawns[0].origin) < 1.0, "at the start, not the checkpoint (%s)" % player.global_position)
	check(run.phase == MissionRun.Phase.READY and run.ticks == 0 and run.checkpoint == 0, "a clean run: clock at zero, no checkpoint")
	check(run.objective == 0 and not run.practice, "first objective, a real run")
	check(level.combo.score == 0 and level.combo.multiplier() <= 1, "no score or combo carried over")
	check(run.restarts == 1 and level.restarts == 1, "one restart counted")


func test_going_down_restarts_with_every_enemy_back() -> void:
	await _load(_index("m02_on_air"))
	var b: MissionBuilder = level.builder
	var enc: Node3D = b.encounters[0]
	var n: int = enc.alive_count()
	player.global_position = b.spawns[0].origin + Vector3(0, 0.05, -8)
	await _step(3)
	check(run.phase == MissionRun.Phase.RUNNING, "running")
	var c: Vector3 = enc.bounds.get_center()
	player.global_position = Vector3(c.x, 8.05, c.z)
	await _step(5)
	enc.enemies[0].take_hit({"damage": 500.0, "zone": &"body", "position": enc.enemies[0].global_position})
	check(enc.alive_count() == n - 1, "one killed")
	var at := player.global_position
	var health: PlayerHealth = PlayerHealth.of(player)
	health.take_damage(500.0, Vector3.ZERO)
	await _step(2)
	check(run.downs == 1 and run.phase == MissionRun.Phase.LOST, "going down loses the run")
	check(player.global_position.distance_to(at) < 1.0, "you go down where you were, no teleport mid-fade")
	check(level._fade_label.text == "DOWN", "it fades out on DOWN")
	check(await _await_restart(), "the level starts again")
	b = level.builder
	enc = b.encounters[0]
	check(player.global_position.distance_to(b.spawns[0].origin) < 1.0, "at the start (%s)" % player.global_position)
	check(enc.alive_count() == n, "every enemy is back (%d / %d)" % [enc.alive_count(), n])
	check(PlayerHealth.of(player).health == PlayerHealth.of(player).max_health, "full health")


func test_backspace_restarts_the_level() -> void:
	await _load(_index("l1_1_dawn_run"))
	await _step(3)
	player.respawn()
	await _step(3)
	check(run.phase == MissionRun.Phase.READY, "at the start before moving: nothing to restart")
	_leave_start()
	await _step(3)
	player.global_position = _checkpoint(0)
	await _step(3)
	player.respawn()  # Backspace
	await _step(2)
	check(run.phase == MissionRun.Phase.LOST and run.lost_reason == "restart", "Backspace restarts the level")
	check(run.falls == 0 and run.downs == 0, "without counting a fall")
	check(await _await_restart(30), "quickly")
	check(player.global_position.distance_to(level.builder.spawns[0].origin) < 1.0, "from the start")
	check(run.checkpoint == 0 and run.restarts == 1, "a fresh run")


func test_pause_menu_restarts_the_level() -> void:
	await _load(_index("l1_1_dawn_run"))
	var buttons: Array = level.menu.find_children("*", "Button", true, false).filter(func(x: Button) -> bool: return x.text == "Restart level")
	check(buttons.size() == 1, "the menu has Restart level")
	if buttons.is_empty():
		return
	level.menu.open()
	(buttons[0] as Button).pressed.emit()
	check(not tree.paused, "it closes the menu")
	check(await _await_restart(5), "and restarts")


func test_a_lost_practice_run_restarts_at_its_start() -> void:
	await _load(_index("l1_1_dawn_run"))
	level.go_to_zone(3)
	await _step(3)
	var sp: Transform3D = level.builder.spawns[3]
	player.global_position = sp.origin - sp.basis.z * 6.0
	await _step(3)
	player.global_position = Vector3(sp.origin.x, run.fail_y() - 20.0, sp.origin.z)
	await _step(2)
	check(run.phase == MissionRun.Phase.LOST, "a fall loses the practice run (%s, falls %d, y %.1f, fail %.1f)" % [MissionRun.Phase.keys()[run.phase], run.falls, player.global_position.y, run.fail_y()])
	check(await _await_restart(), "it restarts")
	check(run.practice and run.start_index == 3, "from the same practice start (%d)" % run.start_index)
	check(player.global_position.distance_to(level.builder.spawns[3].origin) < 1.0, "standing there")


## Off the start pad, along the first leg (Dawn Run heads west).
func _leave_start() -> void:
	player.global_position = MissionBuilder.vec(run.mission.start.at) + Vector3(-8, 0.05, 0)


func _checkpoint(i: int) -> Vector3:
	return MissionBuilder.vec(run.mission.checkpoints[i].at) + Vector3(0, 0.05, 0)


func test_tapes_are_collected() -> void:
	await _load(_index("l1_1_dawn_run"))
	var b: MissionBuilder = level.builder
	check(b.tapes.size() == 1, "Dawn Run hides a tape")
	player.global_position = (b.tapes[0].position as Vector3) + Vector3(0, 0.05, 0)
	await _step(2)
	check(run.tapes_found.size() == 1, "standing on it picks it up")
	check(not (b.tapes[0].node as Node3D).visible, "and it disappears")


func test_shoot_and_combo_objectives() -> void:
	await _load(_index("l1_2_the_yard"))
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
	await _load(_index("l1_1_dawn_run"))
	var radio: RadioFeed = level.radio
	radio.advance(0.0)
	check(radio.current.get("who", "") == "echo", "Echo opens the mission, in the camp")
	var first: String = radio.current.line
	radio.advance(30.0)
	check(radio.current.is_empty() or radio.current.line != first, "lines move on")
	# A zone line: the hurdles.
	radio.queue.clear()
	radio.current = {}
	for r: Dictionary in run.mission.radio:
		if String(r.line).begins_with("Rails coming up"):
			player.global_position = MissionBuilder.vec(r.at) + Vector3(0, 0.05, 0)
	for k in 8:
		radio.advance(30.0)
	radio.advance(0.0)
	var heard := radio.history.map(func(l: Dictionary) -> String: return l.line)
	check(heard.any(func(l: String) -> bool: return l.begins_with("Rails coming up")), "the hurdle tip plays at the hurdles")
	# Chatter only when the radio is free, and not twice in a row.
	radio.queue.clear()
	radio.current = {}
	radio._chatter_ready_at = 0.0
	radio.notify("bail")
	radio.notify("bail")
	check(radio.queue.size() == 1, "one reaction at a time (%d)" % radio.queue.size())
	check(RadioFeed.duration("short") >= 2.0 and RadioFeed.duration("x".repeat(400)) <= 7.0, "durations clamp")


func test_chatter_deals_every_line_before_repeating() -> void:
	await _load(_index("m02_on_air"))
	var radio: RadioFeed = level.radio
	RadioFeed.reset_chatter()
	var pool: Array = radio._chatter["bail"]
	var heard: Array = []
	for k in pool.size() * 3:
		radio.queue.clear()
		radio.current = {}
		radio._chatter_ready_at = 0.0
		radio.notify("bail")
		check(radio.queue.size() == 1, "a bail reaction")
		var line: String = radio.queue[0].line
		check(heard.is_empty() or heard.back() != line, "never the same line twice in a row")
		heard.append(line)
		radio.advance(0.0)
	var first: Array = heard.slice(0, pool.size())
	var all: Array = pool.map(func(l: Dictionary) -> String: return l.line)
	first.sort()
	all.sort()
	check(first == all, "every bail line once before any comes round again")


func test_echo_chatter_waits_for_the_uplink() -> void:
	await _load(_index("m10_the_climb"))
	var radio: RadioFeed = level.radio
	RadioFeed.reset_chatter()
	var echo := func() -> bool: return radio.queue.any(func(l: Dictionary) -> bool: return l.who == "echo")
	for k in 4:
		radio.queue.clear()
		radio.current = {}
		radio._chatter_ready_at = 0.0
		radio.notify("combo")
	check(not echo.call(), "Echo stays off the air before she takes the uplink")
	radio.notify("checkpoint:1")
	var heard := false
	for k in 4:
		radio.queue.clear()
		radio.current = {}
		radio._chatter_ready_at = 0.0
		radio.notify("combo")
		heard = heard or echo.call()
	check(heard, "and cheers him on after")


func test_juno_fate_carries_to_the_ending() -> void:
	# A boss's fate in a real (not practice) run is saved with its mission.
	await _load(_index("m08_storm_channels"))
	run.event.emit("fate:spared")
	check(Campaign.choice("m08_storm_channels", "fate") == "spared", "a fate event is saved")
	level.queue_free()
	await tree.process_frame
	for spared: bool in [false, true]:
		Campaign.reset_progress()
		if spared:
			Campaign.save().set_value("m07_parking_spiral", "fate", "spared")
		await _load(_index("m12_signal_out"))
		var radio: RadioFeed = level.radio
		radio.notify("complete")
		var juno := radio.queue.any(func(l: Dictionary) -> bool: return l.who == "juno")
		check(juno == spared, "Juno's ending line plays only if she was spared (spared %s, heard %s)" % [spared, juno])
		check(radio.queue.any(func(l: Dictionary) -> bool: return l.line == "Go outside. It's a nice day."), "the ending plays")
		level.queue_free()
		await tree.process_frame


# ---------------------------------------------------------------- the chase

func test_pursuer_follows_your_path() -> void:
	var p := Pursuer.new()
	p.speed = 5.0
	p.speed_gain = 0.0
	p.delay = 1.0
	p.grace = 0.0
	# Just the path following: no leash, lunge or shortcuts.
	p.leash = 1000.0
	p.lunge_range = 0.0
	p.shortcut_range = 0.0
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


## Running rings round him doesn't work: when you're close in a straight
## line he cuts across instead of following your path, and catches you.
func test_you_cant_circle_the_host() -> void:
	var p := Pursuer.new()
	p.grace = 0.0
	tree.root.add_child(p)
	p.reset(Vector3.ZERO)
	# Run 30 m away, then turn and loop back round past him.
	var at := Vector3.ZERO
	var caught_at := -1
	for i in 900:
		var t := i / 60.0
		if t < 2.6:
			at = Vector3(0, 0, -11.5 * t)
		else:
			# A circle of radius 9 m back toward where he's coming from.
			var a := (t - 2.6) * 11.5 / 9.0
			at = Vector3(9.0 - 9.0 * cos(a), 0, -30.0 + 9.0 * sin(a))
		p.tick(at, 1.0 / 60.0)
		if p.has_caught():
			caught_at = i
			break
	check(caught_at > 0, "circling back past him gets you caught (at tick %d)" % caught_at)
	check(p.cutting or p.lunging, "he came straight at you")
	p.queue_free()


## Close is caught: a couple of meters away in a straight line counts even
## when your path between you is long.
func test_close_to_the_host_is_caught() -> void:
	var p := Pursuer.new()
	p.delay = 0.0
	p.grace = 0.0
	tree.root.add_child(p)
	p.reset(Vector3.ZERO)
	# A long detour that ends right beside where he is.
	for i in 60:
		p.tick(Vector3(0, 0, -0.5 * i), 1.0 / 60.0)
	for i in 40:
		p.tick(Vector3(0.5 * i, 0, -30), 1.0 / 60.0)
	for i in 40:
		p.tick(Vector3(20, 0, -30 + 0.5 * i), 1.0 / 60.0)
	var gap_before := p.path_gap()
	var near := p.pos + Vector3(1.6, 0, 0)
	p.tick(near, 1.0 / 60.0)
	check(gap_before > 20.0, "your path is long (%.1f m)" % gap_before)
	check(p.has_caught(), "but %.1f m away in a straight line is caught" % p.direct)
	p.queue_free()


## He's quicker than you think: past the leash he sprints to catch up, and
## inside lunge range he lunges.
func test_the_host_keeps_up_and_lunges() -> void:
	var p := Pursuer.new()
	tree.root.add_child(p)
	p.reset(Vector3.ZERO)
	for i in 900:
		p.tick(Vector3(0, 0, -11.5 * (i + 1) / 60.0), 1.0 / 60.0)
	check(p.gap <= p.leash + 1.0, "a flat-out sprint can't shake him past the leash (%.1f m)" % p.gap)
	check(p.current_speed() >= p.max_speed, "he runs at least %.1f m/s" % p.max_speed)
	check(p.close_in(5.0), "a set piece brings him in")
	p.tick(Vector3(0, 0, -11.5 * 901 / 60.0), 1.0 / 60.0)
	check(p.lunging, "and that close he lunges (%.1f m)" % p.gap)
	check(p.current_speed() > 11.5 + 2.0, "faster than you can run (%.1f m/s)" % p.current_speed())
	check(not p.close_in(9.0), "a set piece never moves him further back")
	p.queue_free()


## A head start: for `grace` seconds after he sets off he can't catch you
## (or lunge, or sprint to catch up), even if you stand still.
func test_the_host_gives_you_a_head_start() -> void:
	var p := Pursuer.new()
	tree.root.add_child(p)
	p.reset(Vector3.ZERO)
	var caught_at := -1
	for i in 900:
		p.tick(Vector3(0, 0, -6.0), 1.0 / 60.0)
		if p.has_caught():
			caught_at = i
			break
	var grace_ticks := int((p.delay + p.grace) * 60.0)
	check(caught_at >= grace_ticks - 1, "not caught in the first %.1f s (caught at tick %d)" % [p.delay + p.grace, caught_at])
	check(caught_at > 0 and caught_at < grace_ticks + 30, "but right after it, standing still is caught (tick %d)" % caught_at)
	p.queue_free()


func test_the_host_has_his_own_model() -> void:
	await _load(_index("m12_signal_out"))
	var host: Node = run.pursuer.get_node_or_null("HostBody")
	check(host != null, "the Host has a body")
	var body: Node = host.get("body") if host != null else null
	check(body != null and body.runner == "host", "shown with the Host's model")
	if body != null:
		var model: Node = body.get("model")
		check(model != null and model.scene_file_path.ends_with("host.glb"), "host.glb (%s)" % (model.scene_file_path if model else "none"))
		var skel: Skeleton3D = body.get("skeleton")
		check(skel != null and skel.find_bone("LeftUpperLeg") >= 0, "on the runners' skeleton")
		# The first-person camera skips the runner's own layer; he must not be on it.
		var cull: int = 0xFFFFF & ~RunnerBody.LAYER  # what ArtLook sets on the player's camera
		var meshes := model.find_children("*", "MeshInstance3D", true, false) if model else []
		check(not meshes.is_empty(), "he has meshes")
		for mi: MeshInstance3D in meshes:
			check(mi.layers & cull != 0, "%s shows in first person (layers %d)" % [mi.name, mi.layers])


## The set pieces in Signal Out: a beam falls and only blocks once it has
## landed, the Host cuts in close, and going back to a checkpoint resets
## them.
func test_signal_out_set_pieces() -> void:
	await _load(_index("m12_signal_out"))
	var kinds := {}
	for sp: Node3D in level.builder.set_pieces:
		kinds[sp.kind] = kinds.get(sp.kind, 0) + 1
	check(kinds.get("debris", 0) >= 3 and kinds.get("host", 0) >= 3 and kinds.get("blast", 0) >= 2 and kinds.get("mast", 0) >= 2,
		"falling beams, shortcuts, blasts and masts (%s)" % kinds)
	var beam: Node3D = null
	for sp: Node3D in level.builder.set_pieces:
		if sp.kind == "debris":
			beam = sp
			break
	var shapes := beam.find_children("*", "CollisionShape3D", true, false)
	check(not shapes.is_empty() and shapes.all(func(c: CollisionShape3D) -> bool: return c.disabled), "a beam isn't solid before it falls")
	await _step(5)
	player.global_position = beam.trigger
	await _step(2)
	check(beam.fired, "it falls when you get near")
	await _step(40)
	check(shapes.all(func(c: CollisionShape3D) -> bool: return not c.disabled), "and blocks the run once it lands")
	var top := beam.global_transform * Vector3(0, 1.6, 0)
	var q := PhysicsRayQueryParameters3D.create(top + Vector3(0, 0.5, 0), top - Vector3(0, 3, 0), 1)
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	check(not hit.is_empty() and hit.collider.get_parent() == beam.get_node("Beam"), "lying across the roof")
	run.start_practice(0)
	check(not beam.fired and shapes.all(func(c: CollisionShape3D) -> bool: return c.disabled), "a new run puts it back")


func test_standing_still_in_the_chase_gets_you_caught() -> void:
	await _load(_index("m12_signal_out"))
	check(run.pursuer != null, "the finale has a pursuer")
	check(player.get_meta("runner") == "echo", "played as Echo")
	await _step(5)
	player.global_position = level.builder.spawns[0].origin + Vector3(0, 0.05, -8)
	await _step(1)
	check(run.phase == MissionRun.Phase.RUNNING, "the chase starts when you move")
	var caught := false
	for i in 600:
		await tree.physics_frame
		if run.catches > 0:
			caught = true
			break
	check(caught, "the Host catches you if you stand still")
	check(run.phase == MissionRun.Phase.LOST and level._fade_label.text == "CAUGHT", "and that loses the run")
	check(await _await_restart(), "the level restarts")
	check(player.global_position.distance_to(level.builder.spawns[0].origin) < 1.0, "back at the start")
	check(not run.pursuer.visible and run.catches == 0, "he waits again before coming")


func test_beating_the_finale_unlocks_echo() -> void:
	var i := _index("m12_signal_out")
	check(not Campaign.echo_unlocked(), "locked at first")
	Campaign.record(i, {"ticks": 3000, "score": 100})
	check(Campaign.echo_unlocked(), "unlocked by the finale")
	Campaign.set_runner("echo")
	check(Campaign.runner_for(_index("m02_on_air")) == "echo", "and playable in other missions")
	check(Campaign.runner_for(_index("l1_1_dawn_run")) == "parker", "except where the story says otherwise")


func test_echo_waits_in_the_studio_and_runs_the_finale() -> void:
	await _load(_index("m11_dead_air"))
	var echo: Node3D = level.find_child("Figure_echo", true, false)
	check(echo != null, "Echo stands in the Dead Air studio")
	if echo != null:
		var goal: Dictionary = run.mission.objectives[-1]
		var end := MissionBuilder.vec(goal.at)
		var d := Vector2(echo.global_position.x - end.x, echo.global_position.z - end.z).length()
		check(d < 10.0, "next to the 'Get to Echo' goal (%.1f m)" % d)
		check(absf(echo.global_position.y - (end.y - 2.0)) < 0.5, "standing on the studio floor")
	level.queue_free()
	await tree.process_frame
	await _load(_index("m12_signal_out"))
	ArtLook.attach_to_player(player)
	var body: Node = player.get_node("RunnerBody")
	check(body.runner == "echo", "Signal Out shows Echo's model")


# ---------------------------------------------------------------- full runs

## The route's legs ([origin x, origin z, yaw, z0] each, from Route): the
## bot works in its current leg's frame, x across the run and z along it
## (decreasing as it goes). One leg at the origin for hand-made routes.
var _legs: Array = [[0.0, 0.0, 0.0, 0.0]]
var _leg := 0
## Start turning this far before a corner's center.
const TURN_LEAD := 8.0
## How fast the bot turns its view (rad/s).
const TURN_RATE := 5.0


## A world position in leg `leg`'s frame: (across, along).
func _local(pos: Vector3, leg: int) -> Vector2:
	var l: Array = _legs[leg]
	var v := Basis(Vector3.UP, -float(l[2])) * Vector3(pos.x - l[0], 0.0, pos.z - l[1])
	return Vector2(v.x, v.z + l[3])


func _leg_point(leg: int, x: float, z: float) -> Vector3:
	var l: Array = _legs[leg]
	var v := Basis(Vector3.UP, float(l[2])) * Vector3(x, 0.0, z - l[3])
	return Vector3(l[0] + v.x, 0.0, l[1] + v.z)


## Moves on to the next leg once past the corner's diagonal.
func _update_leg(pos: Vector3) -> void:
	while _leg + 1 < _legs.size():
		var pivot: float = _legs[_leg + 1][3]
		var u := pivot - _local(pos, _leg).y
		var v := pivot - _local(pos, _leg + 1).y
		if u + v <= 0.0:
			return
		_leg += 1


## Forward along the leg with a little strafe to hold lane x. Near a corner,
## or veering across to the other line of a fork, it heads for a point
## ahead instead and turns its view that way while on its feet.
func _steer(x: float, veer: bool) -> InputFrame:
	var pos := player.global_position
	var here := _local(pos, _leg)
	var leg_basis := Basis(Vector3.UP, float(_legs[_leg][2]))
	var right := leg_basis.x
	var fwd := -leg_basis.z
	var side := (x - here.x) * 0.8 - player.velocity.dot(right) * 0.25
	var wish := fwd + right * clampf(side, -0.6, 0.6)
	var want_yaw: float = _legs[_leg][2]
	var target := Vector3.INF
	if _leg + 1 < _legs.size() and here.y < float(_legs[_leg + 1][3]) + TURN_LEAD:
		target = _leg_point(_leg + 1, 0.0, float(_legs[_leg + 1][3]) - 6.0)
	elif veer:
		target = _leg_point(_leg, x, here.y - 8.0)
	if target != Vector3.INF:
		var dir := Vector3(target.x - pos.x, 0.0, target.z - pos.z).normalized()
		wish = dir
		want_yaw = atan2(-dir.x, -dir.z)
	if player.state not in [Player.State.AIR, Player.State.WALLRUN]:
		var turn := clampf(angle_difference(player.yaw, want_yaw), -TURN_RATE / 60.0, TURN_RATE / 60.0)
		if absf(turn) > 0.0001:
			player._look(turn, 0.0)
	var face := Basis(Vector3.UP, player.yaw)
	var move := Vector2(wish.dot(face.x), wish.dot(-face.z))
	if move.y > 0.0:
		move /= move.y
	return InputFrame.make(Vector2(clampf(move.x, -0.6, 0.6), 1.0))


## Same scripted runner as test_maps: [trigger_z, action, lane_x] steps in
## the route's frame ("veer" heads across to a far lane; "flip", "front" and "spin" turn
## over in the air after the next take-off). Returns true once
## the mission is complete; false if it runs out of time or passes stop_z
## first.
func _run_route(route: Array, max_frames := 2400, stop_z := -INF, legs: Array = []) -> bool:
	_legs = legs if not legs.is_empty() else [[0.0, 0.0, 0.0, 0.0]]
	_leg = 0
	var lane: float = route[0][2] if route[0][1] == "" and not is_nan(route[0][2]) else _local(player.global_position, 0).x
	var veer := false
	var next := 0
	var roll_armed := false
	# "flip" (back), "front" or "spin": done in the air after the next take-off.
	var trick := ""
	var trick_left := 0
	# Still in the air from the last jump when the trick came up: wait for
	# the landing, so it goes into the next take-off.
	var trick_wait := false
	for i in max_frames:
		var pos := player.global_position
		if run.phase == MissionRun.Phase.COMPLETE:
			return true
		if run.phase == MissionRun.Phase.LOST:
			push_warning("route bot lost the run (%s) at %s" % [run.lost_reason, pos])
			return false
		_update_leg(pos)
		var z := _local(pos, _leg).y
		if z < stop_z:
			return false
		if OS.has_environment("ROUTE_LOG") and i % 10 == 0:
			print("  t%4d pos %s leg %d along %.1f state %s speed %.1f obj %d falls %d caught %d gap %.1f pitch %.2f" % [i, pos.snapped(Vector3.ONE * 0.01), _leg, z, Player.State.keys()[player.state], player.horizontal_speed(), run.objective, run.falls, run.catches, run.pursuer.gap if run.pursuer else 0.0, player.pitch])
		if veer and absf(lane - _local(pos, _leg).x) < 1.5:
			veer = false
		var f := _steer(lane, veer)
		while next < route.size() and z < route[next][0]:
			var step: Array = route[next]
			if not is_nan(step[2]):
				lane = step[2]
				veer = step[1] == "veer"
			match step[1]:
				"jump":
					f.jump_pressed = true
					f.jump_held = true
				"crouch":
					f.crouch_pressed = true
					f.crouch_held = true
				"roll":
					roll_armed = true
				"kick":
					f.kick_pressed = true
				"flip", "front", "spin":
					trick = step[1]
					trick_left = 24
					trick_wait = player.state == Player.State.AIR
					# Eyes level first, as a runner would after the last
					# landing (a flip lands looking up: flip_look_gain).
					player.pitch = 0.0
			next += 1
		if trick == "" and player.state == Player.State.GROUND:
			# Eyes back to the line once down (a flip lands looking up).
			player.pitch = 0.0
		if trick_wait and player.state != Player.State.AIR:
			trick_wait = false
		if trick != "" and not trick_wait and player.state == Player.State.AIR:
			var turn := TAU / 24.0
			player._look(turn if trick == "spin" else 0.0, turn if trick == "flip" else (-turn if trick == "front" else 0.0))
			trick_left -= 1
			if trick_left <= 0:
				trick = ""
		if roll_armed and player.state == Player.State.AIR and player.velocity.y < 0.0:
			var q := PhysicsRayQueryParameters3D.create(pos, pos + Vector3.DOWN * 1.2, 1)
			q.exclude = [player.get_rid()]
			if not player.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
				f.crouch_pressed = true
				f.crouch_held = true
				roll_armed = false
		if player.state == Player.State.SLIDE or player.state == Player.State.CROUCH:
			f.crouch_held = z > route[next - 1][0] - 4.0 if next > 0 else false
		if player.state == Player.State.WALLRUN and player.wallrun_angle() < 0.05:
			f.lean = 1.0 if player._lean_toward_wall(1.0) > 0.0 else -1.0
		player.scripted_input = f
		await tree.physics_frame
	return false


const Atlas_ := preload("res://campaign/atlas.gd")


## Levels on the city atlas meet: each starts exactly where the one before
## it ends (same spot, same facing), and spawns there.
func test_atlas_levels_meet() -> void:
	var order: Array = Atlas_.order()
	check(order.size() >= 2, "the Docks levels are on the atlas (%d)" % order.size())
	# (Levels next to each other in the campaign: stages not rebuilt yet
	# leave gaps between atlas levels.)
	var number := {}
	for m: Dictionary in Campaign.missions():
		number[m.id] = int(m.get("number", -1))
	for i in range(1, order.size()):
		if int(number.get(order[i][0], -9)) - int(number.get(order[i - 1][0], -9)) != 1:
			continue
		var a := Campaign.load_mission_file(order[i - 1][1])
		var b := Campaign.load_mission_file(order[i][1])
		var end := MissionBuilder.vec(a.route_end)
		var start := MissionBuilder.vec(b.route_origin.at)
		check(end.distance_to(start) < 0.05, "%s ends where %s starts (%s, %s)" % [a.id, b.id, end, start])
		check(is_equal_approx(wrapf(float(a.route_end_yaw) - float(b.route_origin.yaw), -180.0, 180.0), 0.0),
			"facing the same way (%s, %s)" % [a.route_end_yaw, b.route_origin.yaw])
		check(MissionBuilder.vec(b.start.at).distance_to(start) < 0.05 and is_equal_approx(float(b.start.yaw), float(b.route_origin.yaw)),
			"%s spawns there" % b.id)


## The broadcast tower is in sight from the start and end of every atlas
## level: nothing of the level, its city or its skyline stands across the
## line from there to the tower's top floors.
func test_tower_in_sight_from_atlas_levels() -> void:
	var t: Dictionary = Atlas_.data().tower
	var tower := Vector3(t.at[0], Atlas_.VIEW_AT + 6.0, t.at[1])
	for o: Array in Atlas_.order():
		var m := Campaign.load_mission_file(o[1])
		var boxes: Array = []
		for p: Dictionary in m.pieces:
			if p.has("building") and not p.get("tower", false):
				boxes.append([p.building[0], p.building[2], p.size[0], p.size[1], 0.0, p.building[1], 0, float(p.get("yaw", 0.0))])
			elif p.get("skyline", false):
				boxes.append_array(p.boxes)
		for eye: Vector3 in Atlas_.tower_views(m):
			var blocked := ""
			# Out to where the skyline ends; past it the tower is all there is.
			for k in range(1, 400):
				var q := eye + (tower - eye).normalized() * (k * 2.0)
				if Vector2(q.x - eye.x, q.z - eye.z).length() > Atlas_.SKY_RANGE + 200.0:
					break
				for b: Array in boxes:
					if q.y < float(b[5]) and q.y > float(b[4]) and Atlas_._rect(b).has_point(Vector2(q.x, q.z)):
						blocked = "%s at %s" % [b, q]
						break
				if blocked != "":
					break
			check(blocked == "", "%s: the tower's in sight from %s (%s)" % [m.id, eye, blocked])


## The Docks: two levels of 600-900 m on the atlas, no enemies, the city
## kept off the harbour, the skyline beyond with the tower; the last one
## ends at the south gate looking west at Warehouse Row.
func test_docks_levels_follow_the_atlas() -> void:
	for id: String in ["l1_1_dawn_run", "l1_2_the_yard"]:
		var m := Campaign.load_mission_file(Campaign.entry(_index(id)).file)
		check(m.route_length >= 600.0 and m.route_length <= 900.0, "%s: 600-900 m (%d)" % [id, int(m.route_length)])
		var sky := {}
		var in_water := 0
		var camp := 0
		for p: Dictionary in m.pieces:
			check(not p.has("encounter"), "%s: no enemies in the Docks" % id)
			if p.has("skyline"):
				sky = p
			if p.has("building") and p.has("city") and Atlas_.in_water(p.building[0], p.building[2]):
				in_water += 1
			if p.get("atlas", "") == "line_camp":
				camp += 1
		check(in_water == 0, "%s: no city on the harbour (%d)" % [id, in_water])
		check(camp == 1, "%s: runs over the Line's camp, from the atlas" % id)
		check(not sky.is_empty() and sky.boxes.size() > 100, "%s: a skyline past its own city" % id)
		check(not sky.is_empty() and sky.tower.size() == 5, "%s: the broadcast tower on it" % id)
	var yard := Campaign.load_mission_file(Campaign.entry(_index("l1_2_the_yard")).file)
	var end := MissionBuilder.vec(yard.route_end)
	check(Atlas_.district_at(end.x, end.z).get("id", "") == "docks", "the Yard ends in the Docks")
	check(is_equal_approx(float(yard.route_end_yaw), 90.0), "facing west (%s)" % yard.route_end_yaw)
	check(Atlas_.district_at(end.x - 120.0, end.z).get("id", "") == "warehouse_glass", "looking out at Warehouse Row")
	var ahead := 0
	for p: Dictionary in yard.pieces:
		if p.has("skyline"):
			for b: Array in p.boxes:
				if Atlas_.district_at(b[0], b[1]).get("id", "") == "warehouse_glass":
					ahead += 1
	check(ahead > 20, "Warehouse Row stands on the skyline ahead (%d)" % ahead)
	# Nothing of the city's lies on the yard's streets.
	var junk := 0
	for p: Dictionary in yard.pieces:
		if p.has("city") and (p.has("prop") or p.has("fire")):
			var at: Array = p.get("at", p.get("fire", [0, 0, 0]))
			if at[0] > 3414.0 and at[0] < 3436.0 and at[2] > 177.0 and at[2] < 305.0:
				junk += 1
	check(junk == 0, "no rubble in the yard (%d)" % junk)


## Dawn Run's way back: halfway down the waterfront the raid goes off where
## you can see it. The camp is wrecked, smoke over it, the pickup pulls
## away up the quay and the drone heads for the tower.
func test_dawn_run_raid_is_seen() -> void:
	await _load(_index("l1_1_dawn_run"))
	var camp: Node3D = level.builder.set_pieces[0]
	check(camp.get_node("Intact").visible and not camp.get_node("Wrecked").visible, "the camp's intact at dawn")
	check(level.builder.find_children("Figure_echo", "", true, false).size() >= 1, "Echo's in the camp")
	player.global_position = MissionBuilder.vec(run.mission.start.at) + Vector3(-8, 0.05, 0)
	await _step(3)
	var raid: Array[String] = []
	run.event.connect(func(e: String) -> void:
		if e == "set_piece:raid":
			raid.append(e))
	player.global_position = camp.trigger + Vector3(0, 0.05, 0)
	await _step(3)
	check(raid.size() == 1, "the raid goes off on the waterfront")
	check(not camp.get_node("Intact").visible and camp.get_node("Wrecked").visible, "the camp's wrecked")
	var truck: Node3D = camp.get_node("Pickup")
	var z0 := truck.global_position.z
	await _step(120)
	check(truck.visible and truck.global_position.z < z0 - 10.0, "the pickup pulls away north (%.1f -> %.1f)" % [z0, truck.global_position.z])
	var drone: Node3D = camp.get_node("Drone")
	check(drone.visible and drone.global_position.y > camp.global_position.y + 5.0, "the drone lifts off the roof")


## Dawn Run: Parker carries the parcel, not the gun, delivers it on the
## run at the high roof's crate, and goes home empty-handed (Dax 2026-10-20).
func test_dawn_run_carries_and_delivers_the_parcel() -> void:
	await _load(_index("l1_1_dawn_run"))
	var gun := player.weapon as Pistol
	check(gun.held == "parcel" and not gun.is_armed(), "the parcel's in hand, not the gun")
	var drop: Node3D = run.drop_offs.get(0)
	check(drop != null, "a drop-off at the high roof")
	await _step(2)
	check(drop.find_children("*", "OmniLight3D", true, false).size() == 1, "lit")
	check(level.builder.find_children("Chalk", "", true, false).any(func(c: Node) -> bool:
		return c.find_children("*", "Label3D", true, false).any(func(l: Node) -> bool: return (l as Label3D).text == "DROP")), "chalked DROP")
	player.global_position = MissionBuilder.vec(run.mission.start.at) + Vector3(-8, 0.05, 0)
	await _step(3)
	# Running home first doesn't count the drop you skipped.
	player.global_position = _camp()
	await _step(3)
	check(run.objective == 0 and run.phase == MissionRun.Phase.RUNNING, "camp without delivering doesn't count")
	var events: Array[String] = []
	run.event.connect(func(e: String) -> void: events.append(e))
	player.global_position = MissionBuilder.vec(run.mission.objectives[0].at) + Vector3(0, 0.05, 0)
	player.velocity = Vector3(0, 0, -9.0)
	await _step(1)
	check("delivered" in events and run.objective == 1, "delivered on the run")
	check(gun.held == "hands" and not gun.is_armed(), "home empty-handed")
	check(player.velocity.length() > 8.0, "no stop to hand it over (%.1f)" % player.velocity.length())
	check(level.combo.entries.any(func(e: Dictionary) -> bool: return e.name == &"delivered"), "DELIVERED in the combo")
	await _step(30)
	check(drop.delivered and drop.get("_inside") != null, "the parcel sits in the crate")
	player.global_position = _camp()
	await _step(3)
	check(run.phase == MissionRun.Phase.COMPLETE, "back at camp ends it")
	check(run.objective_text() == "Level complete", "the goal line says so")
	await _step(2)
	check(level.mission_hud.get("_banner").visible, "a COMPLETE banner while the radio finishes")


## A loss restarts Dawn Run holding the parcel again.
func test_dawn_run_restart_gives_the_parcel_back() -> void:
	await _load(_index("l1_1_dawn_run"))
	player.global_position = MissionBuilder.vec(run.mission.start.at) + Vector3(-8, 0.05, 0)
	await _step(3)
	player.global_position = MissionBuilder.vec(run.mission.objectives[0].at) + Vector3(0, 0.05, 0)
	await _step(2)
	check((player.weapon as Pistol).held == "hands", "delivered")
	player.global_position = Vector3(player.global_position.x, run.fail_y() - 1.0, player.global_position.z)
	await _step(2)
	check(await _await_restart(), "the level restarts")
	check((player.weapon as Pistol).held == "parcel", "with the parcel back in hand")


## The Yard opens in the wrecked camp: Mags holds the pistol out by the way
## down, and running past her takes it.
func test_yard_pistol_handoff() -> void:
	await _load(_index("l1_2_the_yard"))
	var camp: Node3D = level.builder.set_pieces[0]
	check(camp.get_node("Wrecked").visible, "the camp's still wrecked")
	var pistol: Node3D = camp.get("_pistol")
	check(pistol != null and pistol.get_parent() is Node3D and pistol.get_parent().get("runner") == "mags", "in her hand: the figure's own pistol")
	check(pistol.visible, "Mags holds the pistol out")
	var start := MissionBuilder.vec(run.mission.start.at)
	var run_on := InputFrame.new()
	run_on.move = Vector2(0, 1)
	var hand: Vector3 = pistol.global_position
	for k in 150:
		if not pistol.visible:
			break
		await _step(1, run_on)
	check(not pistol.visible, "running past takes it (passed %.1f m from her hand)" % Vector2(player.global_position.x - hand.x, player.global_position.z - hand.z).length())
	check(player.horizontal_speed() > 4.0, "without stopping")
	level.radio.advance(0.0)
	var lines: Array = level.radio.queue.map(func(l: Dictionary) -> String: return l.line)
	lines.append(level.radio.current.get("line", ""))
	for l: Dictionary in level.radio.history:
		lines.append(l.line)
	check(lines.any(func(l: String) -> bool: return l.begins_with("Here. This was your granddad's")), "Mags says whose it was")
	check(player.global_position.distance_to(start) > 8.0, "on the way down")


## Stage 3, the Silt: 3-1 starts on the blown Calder Way bridge where 2-3
## ends (the atlas's "silt_bridge"), 3-2 comes up at the mall's south
## entrance where 4-1 starts. Hollows (and the Static herding them), no
## Ward; the Must play lines are marked; the drain holds the one loop.
func test_silt_levels_follow_the_atlas() -> void:
	var silt := Campaign.load_mission_file(Campaign.entry(_index("l3_1_the_silt")).file)
	var drain := Campaign.load_mission_file(Campaign.entry(_index("l3_2_the_drain")).file)
	var deck: Array = Atlas_.landmark("silt_bridge").boxes[0]
	var start := MissionBuilder.vec(silt.route_origin.at)
	check(Atlas_._rect(deck).has_point(Vector2(start.x, start.z)) and is_equal_approx(start.y, float(deck[5])), "3-1 starts on the Silt bridge's deck (%s)" % start)
	check(is_equal_approx(float(silt.route_origin.yaw), 90.0), "facing west")
	check(MissionBuilder.vec(drain.route_end).distance_to(Vector3(1500, 0, 380)) < 0.05 and is_equal_approx(float(drain.route_end_yaw), 90.0),
		"3-2 ends at the mall's south entrance, facing west (%s)" % [drain.route_end])
	check(MissionBuilder.vec(silt.route_end).distance_to(MissionBuilder.vec(drain.route_origin.at)) < 0.05, "3-2 starts where 3-1 ends")
	var musts := {"l3_1_the_silt": 4, "l3_2_the_drain": 1}
	for m: Dictionary in [silt, drain]:
		check(m.route_length >= 600.0 and m.route_length <= 900.0, "%s: 600-900 m (%d)" % [m.id, int(m.route_length)])
		check(m.get("plain_runner", false), "%s: checked by the plain runner" % m.id)
		var loops := 0
		var hollows := 0
		for p: Dictionary in m.pieces:
			loops += 1 if p.has("loop") else 0
			if p.has("encounter"):
				for e: Dictionary in p.get("enemies", []):
					check(e.type in ["crawler", "leaper", "brute", "raider"], "%s: %s is a Hollow or a Static herder" % [m.id, e.type])
					hollows += 1 if e.type != "raider" else 0
		check(loops == (1 if m.id == "l3_2_the_drain" else 0), "%s: the drain's ring pipe is the only loop (%d)" % [m.id, loops])
		check(hollows >= 12, "%s: Hollows on the line (%d)" % [m.id, hollows])
		var n := 0
		for r: Dictionary in m.radio:
			n += 1 if r.get("must", false) else 0
		check(n == musts[m.id], "%s: its Must play lines never drop (%d)" % [m.id, n])


## The Silt's set pieces: the relay box goes off as it comes into sight,
## and the Hollows pen's gate goes up (solid until it does).
func test_silt_relay_and_pens() -> void:
	await _load(_index("l3_1_the_silt"))
	var got: Array[String] = []
	run.event.connect(func(e: String) -> void:
		if e.begins_with("set_piece:"):
			got.append(e))
	var pieces := {}
	for sp: Node3D in level.builder.set_pieces:
		pieces[sp.kind] = sp
	check(pieces.has("silt_wreck") and pieces.has("relay_box") and pieces.has("hollows_cage"), "the wreck, the relay and the pen (%s)" % [pieces.keys()])
	# Set pieces run once the run's under way: a step off the start.
	player.global_position = MissionBuilder.vec(run.mission.start.at) + Vector3(-3, 0.05, 0)
	await _step(3)
	check("set_piece:wreck" in got, "the wreck is there from the start")
	player.global_position = pieces.relay_box.trigger + Vector3(0, 0.05, 0)
	await _step(3)
	check("set_piece:relay" in got, "the relay box goes off in sight")
	var cage: Node3D = pieces.hollows_cage
	var gate: CollisionShape3D = cage.get("_gate_shape")
	check(not gate.disabled, "the pen's gate is shut")
	player.global_position = cage.trigger + Vector3(0, 0.05, 0)
	await _step(60)
	check("set_piece:cage" in got and gate.disabled, "it goes up and lets the pack out")


## The Yard's lost tape is a Calder Radio reel: its lines play as a tape.
func test_yard_tape_plays_as_a_tape() -> void:
	await _load(_index("l1_2_the_yard"))
	var radio: RadioFeed = level.radio
	radio.queue.clear()
	radio.current = {}
	radio.notify("tape")
	check(radio.queue.size() == 3 and radio.queue.all(func(l: Dictionary) -> bool: return l.get("fx", "") == "tape"), "three lines off the old tape")
	radio.advance(0.0)
	check(radio._who.text.contains("OLD TAPE"), "marked as a tape (%s)" % radio._who.text)


## The atlas's skyline is built round a level, with the tower on it.
func test_skyline_and_tower_are_built() -> void:
	await _load(_index("l1_1_dawn_run"))
	var sky: Node3D = level.builder.find_child("Skyline", true, false)
	check(sky != null, "the skyline's there")
	if sky == null:
		return
	var mesh := sky.get_node("Buildings") as MeshInstance3D
	check(mesh != null and mesh.mesh.get_faces().size() > 1000, "its buildings, as one mesh")
	check(sky.find_children("*", "CollisionShape3D", true, false).is_empty(), "nothing in it to touch")
	var tower: Node3D = sky.get_node("Tower")
	var eye := player.global_position
	sky._place_proxy(eye)
	var real := Vector3(0, 0, 0)
	var dir_real := (real - eye).normalized()
	var dir_proxy := (tower.global_position - eye).normalized()
	check(dir_real.dot(dir_proxy) > 0.9999, "the tower stands where the real one is")
	check(tower.global_position.distance_to(eye) < 600.0, "inside the camera's reach")


func test_on_air_lookouts_are_raiders() -> void:
	await _load(_index("m02_on_air"))
	var b: MissionBuilder = level.builder
	check(b.encounters.size() == 2, "On Air has two lookout posts")
	var enc: Node3D = b.encounters[0]
	var n: int = enc.enemies.size()
	check(n == 4 or n == 5, "four raiders, and the camera drone once it exists (%d)" % n)
	for e: Node in enc.enemies:
		if e.get_meta("enemy_type", "") != "":
			continue
		check(e.get_script() == MissionBuilder.RAIDER_SCRIPT, "lookouts are raiders")
		check(absf(e.global_position.y - 8.0) < 0.5, "standing on the roof (%s)" % e.global_position)
	check(enc.covers.size() > 0, "with cover spots")
	check(level.find_children("*", "CanvasLayer", false, false).any(func(n: Node) -> bool: return n.get_script() == level.HURT_OVERLAY_SCRIPT), "and the hurt overlay")
	# Step onto the lookout roof: they wake.
	player.respawn(b.spawns[2])
	var c: Vector3 = enc.bounds.get_center()
	player.global_position = Vector3(c.x, 8.05, c.z)
	await _step(5)
	check(enc.phase == EnemyEncounter.Phase.ACTIVE, "the encounter starts on the roof")
	check(run.objective == 2, "practice from the lookout roof: the lookouts are a bonus, the mast is the goal")
	check(run.bonuses.has(1) and run.bonus_text().contains("(0 / 3)"), "the lookout bonus is open (%s)" % run.bonus_text())
	enc.enemies[0].take_hit({"damage": 500.0, "zone": &"body", "position": enc.enemies[0].global_position})
	check(run.bonus_text().contains("(1 / 3)"), "one down (%s)" % run.bonus_text())
	var score: int = level.combo.score
	for e: Node in enc.enemies:
		if not e.is_dead:
			e.take_hit({"damage": 500.0, "zone": &"head", "position": e.global_position})
	await _step(2)
	check(run.bonuses[1].done and run.bonuses_done() == 1, "the lookouts are down: bonus done")
	check(level.combo.score >= score + MissionRun.BONUS_POINTS, "and it pays (%d -> %d)" % [score, level.combo.score])
	check(run.objective == 2, "still heading for the mast")
	check(run.headshots == n - 1, "headshots counted (%d)" % run.headshots)
	await _step(400)
	check(enc.alive_count() == 0, "a cleared encounter stays cleared")


## The Static and the Ward never fight side by side (Dax: they don't like
## each other): every encounter in every mission is one faction. Hollows
## can turn up anywhere.
func test_raiders_and_the_ward_never_share_a_fight() -> void:
	const STATIC := ["raider", "hunter", "bruiser", "juno", "camera_drone", "spotter_drone"]
	const WARD := ["trooper", "shield", "marksman", "heavy", "drone", "gun_drone"]
	var checked := 0
	for f: String in DirAccess.get_files_at("res://campaign/missions"):
		if not f.ends_with(".json"):
			continue
		var m: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://campaign/missions/" + f))
		var stack: Array = [m]
		while not stack.is_empty():
			var o: Variant = stack.pop_back()
			if o is Array:
				stack.append_array(o)
			elif o is Dictionary:
				stack.append_array((o as Dictionary).values())
				if not o.has("encounter"):
					continue
				var types: Array = []
				for _r in o.get("raiders", []):
					types.append("raider")
				for _t in o.get("troopers", []):
					types.append("trooper")
				for _d in o.get("drones", []):
					types.append("drone")
				for e: Dictionary in o.get("enemies", []):
					types.append(String(e.get("type", "raider")))
				var s := types.any(func(t: String) -> bool: return t in STATIC)
				var wd := types.any(func(t: String) -> bool: return t in WARD)
				check(not (s and wd), "%s '%s' mixes the Static and the Ward (%s)" % [f, o.encounter, types])
				checked += 1
	check(checked > 30, "checked every encounter (%d)" % checked)


## Kill goals are bonuses: in Storm Channels you can run past both Ward
## squads and still win at the end, and a bonus you ran past is closed,
## not something to go back for.
func test_kill_goals_are_bonuses() -> void:
	await _load(_index("m08_storm_channels"))
	var objs: Array = run.objectives
	check(MissionRun.is_bonus(objs[1]) and MissionRun.is_bonus(objs[3]), "the squad fights are bonus goals")
	check(not MissionRun.is_bonus(objs[0]) and not MissionRun.is_bonus(objs[4]), "the run itself isn't")
	await _step(10, _forward())
	for i in [0, 2, 4]:
		check(run.objective == i, "on objective %d (%d)" % [i, run.objective])
		player.global_position = MissionBuilder.vec(objs[i].at) + Vector3(0, 0.1, 0)
		await _step(2)
	check(run.phase == MissionRun.Phase.COMPLETE, "reaching the end wins without a kill")
	check(run.kills == 0 and run.result.bonuses == 0 and run.result.total_bonuses == 2, "no bonuses (%s)" % run.result)
	check(run.bonuses[1].closed and run.bonuses[3].closed, "the skipped bonuses closed")
	# Every campaign kill goal is a bonus; only The Yard's lessons are required.
	for m: Dictionary in Campaign.missions():
		if m.get("file", "") == "":
			continue
		for o: Dictionary in Campaign.load_mission_file(m.file).get("objectives", []):
			if String(o.get("type", "")) == "shoot" and not MissionRun.is_bonus(o):
				check(m.id == "l1_2_the_yard", "%s: kill goal '%s' is required" % [m.id, o.get("text", "")])


## Head Office: the Host turns up three times, every hit on him is a story
## event the radio answers in order, the hit bonus stays open the whole
## mission, and reaching his office wins whether or not you hit him.
func test_head_office_host_hits_are_a_bonus() -> void:
	await _load(_index("l6_1_head_office"))
	var hosts: Array[Node] = []
	for enc: Node3D in level.builder.encounters:
		for e: Node in enc.enemies:
			if e.has_signal("story_event"):
				hosts.append(e)
	check(hosts.size() == 3, "the Host turns up three times (%d)" % hosts.size())
	var heard: Array[String] = []
	run.event.connect(func(e: String) -> void: heard.append(e))
	await _step(40, _forward())
	check(run.phase == MissionRun.Phase.RUNNING, "the run is on")
	check(run.bonuses.has(0) and run.bonus_text().contains("Hit the Host"), "the hit bonus is open (%s)" % run.bonus_text())
	if hosts.size() == 3:
		hosts[0].story_event.emit("host:hit")
		hosts[1].story_event.emit("host:hit")
	await _step(2)
	check(heard.has("host:hit:1") and heard.has("host:hit:2"), "hits are numbered across his turns (%s)" % [heard])
	check(run.bonuses[0].done, "a hit finishes the bonus")
	var objs: Array = run.objectives
	for i in range(1, objs.size()):
		player.global_position = MissionBuilder.vec(objs[i].at) + Vector3(0, 0.1, 0)
		await _step(2)
	check(run.phase == MissionRun.Phase.COMPLETE, "reaching his office wins")
	check(run.result.bonuses == 1, "with the bonus (%s)" % run.result)
	# Every Head Office and Skybridge radio line has a trigger the mission can fire.
	for id: String in ["l6_1_head_office", "l6_2_skybridge"]:
		var m := Campaign.load_mission_file("res://campaign/missions/%s.json" % id)
		for r: Dictionary in m.radio:
			var on: String = r.get("on", "")
			check(r.has("at") or on in ["start", "go", "complete"] or on.begins_with("checkpoint:") or on.begins_with("host:")
				or on.begins_with("set_piece:"),
				"%s: line '%s' has a known trigger" % [id, r.line])


## Skybridge ends at the Ward's glass gate: you can't get past it, they
## walk Echo off, the bridge blows, and only then is the mission won.
func test_skybridge_ends_after_the_bridge_falls() -> void:
	await _load(_index("l6_2_skybridge"))
	var gate: Node3D = null
	for sp: Node3D in level.builder.set_pieces:
		if sp.kind == "skybridge":
			gate = sp
	check(gate != null, "the skybridge has its gate scene")
	if gate == null:
		return
	var heard: Array[String] = []
	run.event.connect(func(e: String) -> void: heard.append(e))
	await _step(40, _forward())
	var objs: Array = run.objectives
	for i in objs.size():
		if objs[i].get("type", "reach") == "reach":
			player.global_position = MissionBuilder.vec(objs[i].at) + Vector3(0, 0.1, 0)
			await _step(2)
	check(gate.fired, "reaching the gate starts the scene")
	check(heard.has("set_piece:skybridge"), "the radio hears it (%s)" % [heard])
	check(run.phase == MissionRun.Phase.RUNNING, "the gate alone doesn't win it")
	# Push into the gate (_forward() walks backwards: any loss now restarts
	# the level, so backing off the roof would end the test), facing it.
	player.set_view(gate.global_rotation.y)
	await _step(240, TestWorld.forward_input())
	check(gate.to_local(player.global_position).z > 0.0, "you can't get past the gate (%s)" % gate.to_local(player.global_position))
	check(gate.to_local(player.global_position).z < 3.0, "pressed up against it (%s)" % gate.to_local(player.global_position))
	await _step(set_piece_ticks(gate, gate.SKY_BLAST) + 2, TestWorld.forward_input())
	check(heard.has("set_piece:skybridge_blast") and run.phase == MissionRun.Phase.RUNNING, "the bridge blows before the end")
	await _step(set_piece_ticks(gate, gate.SKY_DOWN) + 2, TestWorld.forward_input())
	check(heard.has("set_piece:skybridge_down"), "the span comes down")
	check(run.phase == MissionRun.Phase.COMPLETE, "and that wins it")
	check(run.falls == 0 and run.downs == 0, "standing at the gate is safe")
	check(heard.find("set_piece:skybridge_down") < heard.find("complete"), "won only after the drop (%s)" % [heard])


func test_glass_district_bridge_falls_into_the_silt() -> void:
	await _load(_index("m03_glass_district"))
	var bridge: Node3D = null
	for sp: Node3D in level.builder.set_pieces:
		if sp.kind == "bridge_collapse":
			bridge = sp
	check(bridge != null, "the Silt bridge has its collapse")
	if bridge == null:
		return
	var heard: Array[String] = []
	run.event.connect(func(e: String) -> void: heard.append(e))
	await _step(40, _forward())
	var objs: Array = run.objectives
	for i in objs.size():
		if objs[i].get("type", "reach") == "reach":
			player.global_position = MissionBuilder.vec(objs[i].at) + Vector3(0, 0.1, 0)
			await _step(2)
	check(run.phase == MissionRun.Phase.COMPLETE, "reaching the bridge wins the level")
	check(bridge.fired and bridge.busy(), "and sets the bridge going")
	check(not heard.has("set_piece:bridge_collapse_blast"), "the charge waits for the Host's line")
	var deck_y := player.global_position.y
	# The Host's line comes and goes: the charge goes a moment later.
	bridge.hear(String(bridge.spec.cue))
	bridge.hear("")
	await _step(bridge.BRIDGE_CUE_DELAY + 2)
	check(heard.has("set_piece:bridge_collapse_blast"), "it blows after the line (%s)" % [heard])
	var lines: Array = level.radio.queue.map(func(l: Dictionary) -> String: return l.line) + [level.radio.current.get("line", "")]
	check(lines.any(func(l: String) -> bool: return l.begins_with("Whoops. Did the bridge")), "the Host's \"Whoops\" goes with it (%s)" % [lines])
	check(level._set_piece_busy(), "the results wait while it falls")
	await _step(bridge.BRIDGE_FALL_TICKS + 2)
	check(heard.has("set_piece:bridge_collapse_down"), "the spans come down")
	check(not bridge.busy(), "and it's done")
	await _step(90)
	check(player.global_position.y < deck_y - 6.0, "Parker goes down with it (y %.1f from %.1f)" % [player.global_position.y, deck_y])
	check(run.falls == 0 and run.downs == 0, "falling with it after the win isn't a loss")
	# Every span ends lower than it stood, and the piers between went.
	for span: Dictionary in bridge._spans:
		check(not span.nodes.is_empty(), "each span carries its deck")
	check(bridge._blown.size() == 3, "the three middle piers go (%d)" % bridge._blown.size())
	var piers: Array[Node3D] = bridge._blown.duplicate()
	bridge.reset()
	for n: Node3D in piers:
		check(n.visible, "a reset puts the piers back")


## Ticks until a fired set piece reaches tick `at` (0 if it's past).
func set_piece_ticks(sp: Node, at: int) -> int:
	return maxi(at - int(sp.ticks), 0)


func _forward() -> InputFrame:
	var f := InputFrame.new()
	f.move = Vector2(0, -1)
	return f


func test_signal_out_can_be_escaped() -> void:
	await _load(_index("m12_signal_out"))
	await _step(10)
	var frames := int(run.mission.route_length / 6.0 * 60.0) + 600
	var done := await _run_route(run.mission.bot, frames, -INF, run.mission.route_legs)
	check(done, "a scripted run outruns the Host (stopped at %s)" % player.global_position)
	check(run.mission.route_length >= 900.0, "a long chase (%d m)" % int(run.mission.route_length))
	check(run.catches == 0, "without being caught (%d)" % run.catches)
	check(run.falls == 0, "without falling (%d)" % run.falls)
	check(Campaign.echo_unlocked(), "Echo unlocked")


## Every mission built from a route: a bot runs the route it generates
## from start to finish (enemies can't take it down, and it kills nobody:
## kill goals are bonuses, so only a `clear` like Juno's is done for it),
## without falling; where the route forks, a
## second run takes the other line of every fork.
func test_route_missions_can_be_finished() -> void:
	var all := Campaign.missions()
	var ran := 0
	for i in all.size():
		var path: String = all[i].get("file", "")
		if path == "" or not Campaign.load_mission_file(path).has("bot"):
			continue
		# ROUTE_ONLY=m08 runs just the matching missions (while tuning one).
		if OS.has_environment("ROUTE_ONLY") and not String(all[i].id).contains(OS.get_environment("ROUTE_ONLY")):
			continue
		if Campaign.load_mission_file(path).get("route_from", "") == "base_exit":
			continue  # the base map comes first: its own test runs it
		for alt: bool in [false, true]:
			if alt and not Campaign.load_mission_file(path).has("bot_alt"):
				continue
			await _load(i)
			await _bot_run(all[i].id + (" (other lines)" if alt else ""), alt)
			ran += 1
	check(ran >= 1, "route missions were run (%d)" % ran)


## Every route that ends up high ends in a finish you can't run off:
## across the line at well over top speed, straight on or veering either
## way, holding forward or letting go, you stay on the finish's floor.
func test_route_finishes_keep_you_on_the_roof() -> void:
	var all := Campaign.missions()
	var ran := 0
	for i in all.size():
		var path: String = all[i].get("file", "")
		if path == "" or not Campaign.load_mission_file(path).has("route_finish"):
			continue
		await _load(i)
		PlayerHealth.ensure(player).can_die = false
		var e: Array = run.mission.route_end
		var end := Vector3(e[0], e[1], e[2])
		var yaw := deg_to_rad(float(run.mission.route_end_yaw))
		for veer: float in [0.0, 20.0, -20.0]:
			for hold: bool in [true, false]:
				var look := yaw + deg_to_rad(veer)
				var fwd := Vector3(-sin(look), 0, -cos(look))
				player.global_position = end - fwd * 6.0 + Vector3(0, 0.05, 0)
				player.basis = Basis(Vector3.UP, look)
				player.velocity = fwd * 22.0
				var f := InputFrame.new()
				f.move = Vector2(0, 1) if hold else Vector2.ZERO
				var low := INF
				for k in 240:
					await _step(1, f)
					low = minf(low, player.global_position.y)
				check(low > end.y - 0.6 and run.phase != MissionRun.Phase.LOST,
					"%s: %s at 22 m/s, veering %d, stays on the finish (lowest %.1f, line %.1f)" % [all[i].id, "holding forward" if hold else "letting go", int(veer), low, end.y])
		ran += 1
		level.queue_free()
		level = null
		await tree.physics_frame
	check(ran >= 6, "route finishes were tried (%d)" % ran)


## Runs the loaded mission's route bot (or its fork lines) to the end.
func _bot_run(label: String, alt := false) -> void:
	var health := PlayerHealth.ensure(player)
	health.can_die = false
	run.event.connect(func(e: String) -> void:
		if e.begins_with("objective:") and run.current_objective().get("type", "") in ["shoot", "clear", "duel"]:
			for enc: Node3D in level.builder.encounters:
				for en: Node in enc.enemies:
					if not en.is_dead:
						en.take_hit({"damage": 500.0, "zone": &"body", "position": en.global_position})
		if e.begins_with("objective:"):
			_skip_lessons())
	# Held at the start while the opening is said, as a player is.
	level.radio.sim_clock = true
	for k in 60 * 30:
		if not level.radio.opening_playing():
			break
		await tree.physics_frame
	_skip_lessons()
	await _step(10)
	var bot: Array = run.mission.bot_alt if alt else run.mission.bot
	var frames := int(run.mission.route_length / 6.0 * 60.0) + 600
	if OS.has_environment("ROUTE_ONLY"):
		print("  %s: %d m, %d legs, %d checkpoints, %d encounters, %d enemies, legs %s" % [label, int(run.mission.route_length),
			run.mission.route_legs.size(), level.builder.spawns.size() - 1, level.builder.encounters.size(),
			level.builder.encounters.reduce(func(n: int, e: Node) -> int: return n + e.enemies.size(), 0), run.mission.route_legs])
	var done := await _run_route(bot, frames, -INF, run.mission.get("route_legs", []))
	_check_radio_pacing(label)
	check(done, "%s: a bot finishes the %d m route (stopped at %s, objective %d)" % [label, int(run.mission.route_length), player.global_position.snapped(Vector3.ONE * 0.1), run.objective])
	check(run.falls == 0, "%s: without falling (%d)" % [label, run.falls])
	check(run.mission.route_length >= 500.0, "%s: a long run (%d m)" % [label, int(run.mission.route_length)])
	level.queue_free()
	level = null
	await tree.process_frame


## The most a story line may start after what triggered it (seconds), and
## the most lines from other moments that may be waiting ahead of it.
const RADIO_LATE := 4.0
const RADIO_BACKLOG := 2


## The radio kept pace with the run just finished: every story line started
## within RADIO_LATE of its trigger (a conversation's next line, of the
## line before ending), no line had more than RADIO_BACKLOG lines from
## other moments waiting ahead of it, and no "must" line was dropped. The
## opening (you're held for it) and the ending (the card waits) don't
## count. PACING=1 prints every mission's timeline.
func _check_radio_pacing(label: String) -> void:
	var radio: RadioFeed = level.radio
	radio.advance(0.0)
	var log := radio.story_log
	var lines: Array[String] = []
	var bad: Array[String] = []
	for i in log.size():
		var l: Dictionary = log[i]
		var on: String = l.get("on", "")
		var trigger: float = l.queued_at
		var waiting := 0
		for j in i:
			var o: Dictionary = log[j]
			if o.queued_at == l.queued_at and o.get("on", "") == on:
				trigger = maxf(trigger, float(o.get("ends_at", o.get("dropped", trigger))))
			elif o.get("on", "") != "start" and float(o.get("shown_at", o.get("dropped", INF))) > l.queued_at:
				waiting += 1
		var start: float = l.get("shown_at", -1.0)
		var state := "dropped" if l.has("dropped") else "start +%.1fs" % (start - trigger) if start >= 0.0 else "unsaid"
		lines.append("    %6.1fs  %-14s %s%s  %s: %s" % [l.queued_at, on, state, " MUST" if l.get("must", false) else "",
				l.who, String(l.line).left(60)])
		if on in ["start", "complete"]:
			continue
		if l.get("must", false) and (l.has("dropped") or start < 0.0):
			bad.append("must line %s" % state)
		elif start >= 0.0 and start - trigger > RADIO_LATE:
			bad.append("%.1fs late: %s" % [start - trigger, String(l.line).left(40)])
		if waiting > RADIO_BACKLOG:
			bad.append("%d lines waiting ahead of: %s" % [waiting, String(l.line).left(40)])
	if OS.has_environment("PACING") or not bad.is_empty():
		print("  radio timeline, %s:\n%s" % [label, "\n".join(lines)])
	# The city atlas's levels ("l<stage>_<n>") must keep pace; the older
	# missions they're replacing only report it (see the timeline above).
	if not String(run.mission.get("id", "")).begins_with("l"):
		if not bad.is_empty():
			print("  (not failed: %s is an older mission, rebuilt in the atlas later)" % label)
		return
	check(bad.is_empty(), "%s: the radio keeps pace (%s)" % [label, "; ".join(bad)])


## The Yard's lessons (a combo, the dummies, a score) aren't the bot's to
## learn: done for it, on to the next objective.
func _skip_lessons() -> void:
	var o := run.current_objective()
	var t: String = o.get("type", "")
	if t in ["combo", "score"] or t == "shoot" and level.builder.encounters.is_empty():
		# A player hears the lesson while doing it: the bot skips both.
		var lesson := ["objective:%d" % run.objective, "done:%d" % run.objective]
		var radio: RadioFeed = level.radio
		for list: Array[Dictionary] in [radio.queue, radio.story_log]:
			for i in range(list.size() - 1, -1, -1):
				if list[i].get("on", "") in lesson:
					list.remove_at(i)
		if radio.current.get("on", "") in lesson:
			radio.current = {}
		run.call_deferred("_begin_objective", run.objective + 1)


const Route_ := preload("res://campaign/route.gd")
const TWISTS := "res://tests/fixtures/route_twists.json"


## A route with corners, climbs, drops, ramps and a fork: its pieces turn
## with each leg, checkpoints face along the run, and bots finish both
## lines of the fork.
func test_route_turns_and_forks() -> void:
	var m := Campaign.load_mission_file(TWISTS)
	check(m.route_legs.size() == 4, "three corners make four legs (%d)" % m.route_legs.size())
	check(m.has("bot_alt"), "the fork gives a second bot run")
	check(m.route_length > 650.0, "a long route (%d m)" % int(m.route_length))
	var yaws := {}
	for p: Dictionary in m.pieces:
		var y := fposmod(float(p.get("yaw", 0.0)), 90.0)
		if p.has("building") and not (is_zero_approx(y) or is_equal_approx(y, 90.0)):
			check(false, "buildings stay square to the grid (%s)" % p)
		if p.has("building"):
			yaws[roundi(fposmod(float(p.get("yaw", 0.0)), 360.0))] = true
	check(yaws.has(90), "legs after a left corner turn their buildings")
	var corner: Dictionary = m.checkpoints[0]
	check(is_equal_approx(float(corner.yaw), 90.0), "the checkpoint after the left corner faces along the run (%s)" % corner.yaw)
	check(corner.at[0] < -10.0, "and sits off to the left of the start (%s)" % [corner.at])
	await _load_file(TWISTS)
	var b: MissionBuilder = level.builder
	check(b.encounters.size() == 1, "one encounter")
	var enc: Node3D = b.encounters[0]
	check(enc.enemies.size() == 3, "a raider, a trooper and a drone (%d)" % enc.enemies.size())
	var end: Array = m.route_end
	check(absf(float(m.route_end_yaw) - 90.0) < 0.1, "the route ends heading left of where it began (%s)" % m.route_end_yaw)
	await _bot_run("twists", false)
	await _load_file(TWISTS)
	await _bot_run("twists (fork)", true)
	check(end[1] == 7.0, "on the last roof")


const BREACH := "res://tests/fixtures/route_breach.json"


## Ways through a wall: glass hangs from a sill (never on the floor), holes
## have no glass in them, doors come in pairs that open together, and a bot
## runs through all of them: jumping the glass, kicking the doors, sliding
## the holes.
func test_route_glass_doors_and_holes() -> void:
	var m := Campaign.load_mission_file(BREACH)
	var panes := 0
	var openings := {}
	for p: Dictionary in m.pieces:
		if p.has("window"):
			panes += 1
			check(float(p.window[1]) > 0.5, "glass sits on a sill, not the floor (%s)" % [p.window])
		if p.get("meta", {}).has("opening"):
			openings[p.meta.opening] = true
	check(panes == 2, "two panes, both in walls with glass (%d)" % panes)
	for style: String in ["fence", "broken", "shutter", "duct", "wagon"]:
		check(openings.has(style), "a %s hole" % style)
	await _load_file(BREACH)
	var doors := tree.get_nodes_in_group("doors").filter(func(d: Node) -> bool: return level.is_ancestor_of(d))
	check(doors.size() == 4, "two double doors (%d leaves)" % doors.size())
	var glass := tree.get_nodes_in_group("windows").filter(func(w: Node) -> bool: return level.is_ancestor_of(w))
	var opened := {}
	var broken := {}
	for d: Node in doors:
		opened[d] = false
	var watch := func() -> void:
		for d: Node in doors:
			opened[d] = opened[d] or d.is_open
		for w: Node in glass:
			broken[w] = broken.get(w, false) or w.is_broken
	tree.physics_frame.connect(watch)
	await _bot_run("breach", false)
	tree.physics_frame.disconnect(watch)
	check(opened.values().all(func(o: bool) -> bool: return o), "the bot kicked both pairs open, each leaf swinging (%s)" % [opened.values()])
	check(broken.size() == 2 and broken.values().all(func(b: bool) -> bool: return b), "and jumped through both panes (%s)" % [broken.values()])


## The city round a route: blocks fill the ground next to the course
## without touching any of its roofs, and every block beside a roof stands
## too tall to climb onto from it.
func test_route_city_closes_the_course() -> void:
	var m := Campaign.load_mission_file(TWISTS)
	var roofs: Array[Array] = []
	var city: Array[Array] = []
	for p: Dictionary in m.pieces:
		if not p.has("building"):
			continue
		var s: Array = Route_._turn_size([p.size[0], 0, p.size[1]], deg_to_rad(float(p.get("yaw", 0.0))))
		var r := Rect2(p.building[0] - s[0] * 0.5, p.building[2] - s[2] * 0.5, s[0], s[2])
		(city if p.get("city", false) else roofs).append([r, float(p.building[1])])
	check(city.size() > 50, "a city round the route (%d blocks)" % city.size())
	var overlaps := 0
	var low := 0
	for c: Array in city:
		for r: Array in roofs:
			var cut: Rect2 = (c[0] as Rect2).intersection(r[0])
			if cut.get_area() > 0.01:
				overlaps += 1
			elif (c[0] as Rect2).grow(3.0).intersects(r[0]) and float(c[1]) < float(r[1]) + 9.0:
				low += 1
	check(overlaps == 0, "no block stands on the course (%d)" % overlaps)
	check(low == 0, "blocks beside a roof clear it by 9 m (%d too low)" % low)


## A route with streets and high roofs: down off a roof (into the slot
## beside it) counts as a fall, down on the street doesn't.
func test_route_pits_count_falls_off_the_streets() -> void:
	var m := Route_.expand({"id": "t", "route": [{"street": 40}, {"ramp_up": 8}, {"roof": 40}]})
	check(m.has("pits"), "a route with streets and roofs gets pits")
	var on_street := func(pos: Vector3) -> bool:
		for r: Dictionary in m.pits.streets:
			if MissionRun.inside(r, pos):
				return true
		return false
	check(on_street.call(Vector3(0, 0, -20)), "the street is not a pit")
	check(on_street.call(Vector3(8, 0.2, -20)), "nor its pavement")
	check(not on_street.call(Vector3(0, 0, -75)), "the ground under the roof is")
	var high := Route_.expand({"id": "t", "route": [{"roof": 40, "y": 8}, {"gap": 6}, {"roof": 40}]})
	check(not high.has("pits"), "an all-roof route falls by fail_y alone")


## A route can carry on from its base map's exit (the mall's loading dock
## road) instead of the world origin.
func test_route_from_base_exit() -> void:
	var m := Route_.expand({"id": "t", "base": "res://maps/mall_builder.gd", "route_from": "base_exit",
		"route": [{"roof": 40}, {"turn": "right"}, {"roof": 40}]})
	var leg0: Array = m.route_legs[0]
	check(is_equal_approx(leg0[1], -438.0) and is_zero_approx(leg0[0]), "starts at the mall's EXIT (%s)" % [leg0])
	check(m.route_legs.size() == 2 and is_equal_approx(m.route_legs[1][2], -PI * 0.5), "a right corner turns toward +X")
	check(float(m.route_end[0]) > 30.0, "and ends off to the right (%s)" % [m.route_end])


const ANGLES := "res://tests/fixtures/route_angles.json"


## Corners of 45 degrees: diagonal legs turn their roofs, a slab fills each
## corner, checkpoints on a diagonal are turned regions, typed enemies
## spawn (or their stand-ins do), free pieces turn with their leg, and a
## bot finishes the run.
func test_route_45_degree_corners() -> void:
	var m := Campaign.load_mission_file(ANGLES)
	check(m.route_legs.size() == 5, "four corners make five legs (%d)" % m.route_legs.size())
	check(is_equal_approx(float(m.route_legs[1][2]), PI * 0.25), "a 45 degree left corner (%s)" % m.route_legs[1][2])
	check(absf(float(m.route_legs[3][2]) + PI * 0.25) < 0.001, "two right corners make 45 degrees right of the start (%s)" % m.route_legs[3][2])
	var slabs := 0
	var diagonal := false
	var bank_yaw := INF
	for p: Dictionary in m.pieces:
		if p.has("slab") and not p.get("city", false):
			slabs += 1
		if p.has("building") and is_equal_approx(fposmod(float(p.get("yaw", 0.0)), 90.0), 45.0):
			diagonal = true
		if p.has("bank"):
			bank_yaw = float(p.get("yaw", 0.0))
	check(slabs == 4, "a slab for every 45 degree corner (%d)" % slabs)
	check(diagonal, "roofs on a diagonal leg are turned 45 degrees")
	check(is_zero_approx(bank_yaw), "a free piece turns with its leg (back square here: %s)" % bank_yaw)
	var cp: Dictionary = m.checkpoints[0]
	check(is_equal_approx(float(cp.get("area_yaw", 0.0)), 45.0), "a checkpoint on the diagonal is a turned region (%s)" % cp)
	var at := MissionBuilder.vec(cp.at)
	var along := Basis(Vector3.UP, PI * 0.25) * Vector3(0, 0, -1)
	var across := Basis(Vector3.UP, PI * 0.25) * Vector3(1, 0, 0)
	check(MissionRun.inside(cp, at + across * 6.5), "the region spans the turned roof")
	check(not MissionRun.inside(cp, at + along * 3.0), "and is thin along the run")
	await _load_file(ANGLES)
	var b: MissionBuilder = level.builder
	var enc: Node3D = b.encounters[0]
	check(enc.enemies.size() >= 3, "shield, marksman and brute spawn, as stand-ins if need be (%d)" % enc.enemies.size())
	var heard: Array = []
	run.event.connect(func(e: String) -> void: heard.append(e))
	var shield: Node = enc.enemies[0]
	check(shield.get_meta("enemy_type", "") == "shield", "enemies remember the type they were asked for")
	shield.take_hit({"damage": 500.0, "zone": &"body", "position": shield.global_position})
	check(heard.has("kill:shield"), "a kill names its type for the radio (%s)" % [heard])
	# Standing on a corner slab.
	var corner_mid := Vector3(float(m.route_legs[1][0]), 20.0, float(m.route_legs[1][1]))
	var q := PhysicsRayQueryParameters3D.create(corner_mid, corner_mid + Vector3.DOWN * 30.0, 1)
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	check(not hit.is_empty() and absf(hit.position.y - 10.0) < 0.01, "the corner slab is a roof at 10 m (%s)" % [hit.get("position", null)])
	await _bot_run("45 degree corners", false)


# ---------------------------------------------------------------- hand-made levels

## Missions laid out by hand on a base map (the mall missions) can't use a
## route's bot, so they carry a "bot_path": waypoints [x, z, action] the
## bot runs through in order ("jump", "crouch" or "roll" when it reaches
## one), and "bot_path_alt" for a second line if there is one. Enemies can't take it down and any shooting objective is done for
## it, like the route bots.
func test_hand_made_missions_can_be_finished() -> void:
	var all := Campaign.missions()
	var ran := 0
	for i in all.size():
		var path: String = all[i].get("file", "")
		if path == "" or not Campaign.load_mission_file(path).has("bot_path"):
			continue
		# MISSION_ONLY=m07 runs just the matching missions.
		if OS.has_environment("MISSION_ONLY") and not String(all[i].id).contains(OS.get_environment("MISSION_ONLY")):
			continue
		for key: String in ["bot_path", "bot_path_alt"]:
			if not Campaign.load_mission_file(path).has(key):
				continue
			var label: String = all[i].id + (" (high line)" if key == "bot_path_alt" else "")
			await _load(i)
			var health := PlayerHealth.ensure(player)
			health.can_die = false
			_auto_shoot_objectives()
			await _step(10)
			var done := await _run_path(run.mission[key])
			check(done, "%s: a bot finishes it (stopped at %s, objective %d)" % [label, player.global_position.snapped(Vector3.ONE * 0.1), run.objective])
			check(run.falls == 0, "%s: without falling (%d)" % [label, run.falls])
			level.queue_free()
			level = null
			await tree.process_frame
			ran += 1
	check(ran >= 1, "hand-made missions were run (%d)" % ran)


func _auto_shoot_objectives() -> void:
	run.event.connect(func(e: String) -> void:
		if e.begins_with("objective:") and run.current_objective().get("type", "") in ["shoot", "clear", "duel"]:
			for enc: Node3D in level.builder.encounters:
				for en: Node in enc.enemies:
					if not en.is_dead:
						en.take_hit({"damage": 500.0, "zone": &"body", "position": en.global_position}))


## Runs through waypoints [x, z, action?] in order, turning its view toward
## the next one while on its feet. Returns true once the mission is
## complete.
func _run_path(path: Array, max_frames := 6000) -> bool:
	var next := 0
	var roll_armed := false
	var crouch_until := -1
	for i in max_frames:
		if run.phase == MissionRun.Phase.COMPLETE:
			return true
		if run.phase == MissionRun.Phase.LOST:
			push_warning("path bot lost the run (%s) at %s" % [run.lost_reason, player.global_position])
			return false
		var pos := player.global_position
		var here := Vector2(pos.x, pos.z)
		var f := InputFrame.new()
		# Reached a waypoint (or passed it along its leg): act, move on.
		while next < path.size():
			var w: Array = path[next]
			var p := Vector2(w[0], w[1])
			var prev := Vector2(path[next - 1][0], path[next - 1][1]) if next > 0 else here
			var leg := (p - prev).normalized()
			if here.distance_to(p) > 1.2 and (here - p).dot(leg) < 0.0:
				break
			match w[2] if w.size() > 2 else "":
				"jump":
					f.jump_pressed = true
					f.jump_held = true
				"crouch":
					f.crouch_pressed = true
					f.crouch_held = true
					crouch_until = i + 30
				"roll":
					roll_armed = true
				"kick":
					f.kick_pressed = true
			next += 1
		if OS.has_environment("ROUTE_LOG") and i % 10 == 0:
			print("  t%4d pos %s wp %d state %s speed %.1f obj %d falls %d" % [i, pos.snapped(Vector3.ONE * 0.01), next, Player.State.keys()[player.state], player.horizontal_speed(), run.objective, run.falls])
		var target := Vector2(path[mini(next, path.size() - 1)][0], path[mini(next, path.size() - 1)][1])
		var to := target - here
		var dir := Vector3(to.x, 0.0, to.y).normalized() if to.length() > 0.01 else -Basis(Vector3.UP, player.yaw).z
		if player.state not in [Player.State.AIR, Player.State.WALLRUN]:
			var want := atan2(-dir.x, -dir.z)
			var turn := clampf(angle_difference(player.yaw, want), -TURN_RATE / 60.0, TURN_RATE / 60.0)
			if absf(turn) > 0.0001:
				player._look(turn, 0.0)
		var face := Basis(Vector3.UP, player.yaw)
		var move := Vector2(dir.dot(face.x), dir.dot(-face.z))
		if move.y > 0.0:
			move /= move.y
		f.move = Vector2(clampf(move.x, -0.6, 0.6), 1.0)
		if roll_armed and player.state == Player.State.AIR and player.velocity.y < 0.0:
			var q := PhysicsRayQueryParameters3D.create(pos, pos + Vector3.DOWN * 1.2, 1)
			q.exclude = [player.get_rid()]
			if not player.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
				f.crouch_pressed = true
				f.crouch_held = true
				roll_armed = false
		if i < crouch_until:
			f.crouch_held = true
		if player.state == Player.State.WALLRUN and player.wallrun_angle() < 0.05:
			f.lean = 1.0 if player._lean_toward_wall(1.0) > 0.0 else -1.0
		player.scripted_input = f
		await tree.physics_frame
	return false


## m07: Juno can't be killed outright, so her fight is a `clear` objective;
## sparing her or not plays a different line.
func test_juno_fate_picks_the_line() -> void:
	var i := _index_of("m07_parking_spiral")
	for choice: String in ["spared", "not_spared"]:
		await _load(i)
		var events: Array[String] = []
		run.event.connect(func(e: String) -> void: events.append(e))
		var enc: Node3D = null
		for e: Node3D in level.builder.encounters:
			if e.get_meta("id", "") == "Juno":
				enc = e
		check(enc != null, "m07 has Juno's encounter")
		if enc == null:
			return
		var juno: Node = null
		for en: Node in enc.enemies:
			if en.has_signal("fate_decided"):
				juno = en
		check(juno != null, "Juno is the real Juno, not a stand-in")
		if juno == null:
			return
		check(not run.encounter_cleared("Juno"), "Juno's fight isn't cleared at the start")
		enc.start()
		for en: Node in enc.enemies:
			if en != juno:
				en.take_hit({"damage": 500.0, "zone": &"body", "position": en.global_position})
		juno.take_hit({"damage": 1000.0, "zone": &"body", "position": juno.global_position})
		check(juno.is_beaten and juno.fate == "", "a big hit beats Juno without killing her")
		if choice == "not_spared":
			juno.take_hit({"damage": 10.0, "zone": &"body", "position": juno.global_position})
		else:
			juno._decide("spared")
			juno._leave()
		check(("fate:" + choice) in events, "%s: the radio hears fate:%s (%s)" % [choice, choice, events])
		check(run.encounter_cleared("Juno"), "%s: Juno's fight is cleared" % choice)
		var lines: Array = run.mission.radio.filter(func(r: Dictionary) -> bool: return r.get("on", "") == "fate:" + choice)
		check(lines.size() == 1, "%s: m07 has one line for it" % choice)
		level.queue_free()
		level = null
		await tree.process_frame


## m07: fighting is never required. Running up to Juno ends the duel without
## a shot fired, and she's left kneeling for the spare-or-not choice.
func test_reaching_juno_ends_the_duel() -> void:
	await _load(_index_of("m07_parking_spiral"))
	var duel := -1
	for k in run.objectives.size():
		if run.objectives[k].get("type", "") == "duel":
			duel = k
	check(duel >= 0, "m07 has a duel objective")
	var juno: Node3D = run.duel_boss("Juno")
	check(juno != null, "the duel's boss is Juno")
	if duel < 0 or juno == null:
		return
	run._begin_objective(duel)
	await _step(5)
	check(run.objective == duel, "the duel isn't over from far away")
	player.global_position = juno.global_position + Vector3(0, 0, 2.5)
	await _step(3)
	check(run.objective == duel + 1, "reaching Juno ends the duel (objective %d)" % run.objective)
	check(juno.is_beaten and juno.fate == "" and not juno.is_dead, "she kneels and it's your call")
	check(run.kills == 0, "without a shot fired")
	level.queue_free()
	level = null
	await tree.process_frame


## m05: the arena's shots wake its sleeping Hollows.
func test_atrium_shots_wake_sleepers() -> void:
	await _load(_index_of("m05_atrium"))
	var arena: Node3D = null
	for e: Node3D in level.builder.encounters:
		if e.get_meta("id", "") == "arena":
			arena = e
	check(arena != null and arena.hear_shots, "m05's arena hears shots")
	var sleepers: Array = arena.enemies.filter(func(e: Node) -> bool: return e.sleeper)
	check(sleepers.size() >= 4, "the arena has sleeping Hollows (%d)" % sleepers.size())
	level.queue_free()
	level = null
	await tree.process_frame


func _index_of(id: String) -> int:
	var all := Campaign.missions()
	for i in all.size():
		if all[i].id == id:
			return i
	return -1


# ------------------------------------------------------------ the way on

## The route mark heads for the next point of the guide line, moves on as
## you pass points or run on along a later stretch, and keeps stacked
## floors apart (the car park's laps stand 6.5 m over each other).
func test_route_marker_follows_the_line() -> void:
	var pts: Array[Vector3] = [Vector3(0, 0, 0), Vector3(0, 0, -20), Vector3(10, 0, -20), Vector3(10, 0, -40)]
	check(RouteMarker.advance(pts, 0, Vector3(0, 0, 8)) == 0, "before the start: head for the first point")
	check(RouteMarker.advance(pts, 0, Vector3(0, 0, -1)) == 1, "past the first point: the next")
	check(RouteMarker.advance(pts, 1, Vector3(0, 0, -10)) == 1, "halfway down a stretch: its end")
	check(RouteMarker.advance(pts, 1, Vector3(5, 0, -20.5)) == 2, "on the next stretch: its end")
	check(RouteMarker.advance(pts, 1, Vector3(10, 0, -41)) == 4, "at the end: all passed")
	# A lap below: same x and z, 6.5 m down, is not the stretch above.
	var helix: Array[Vector3] = [Vector3(0, 13, 0), Vector3(0, 13, -30), Vector3(20, 11, -30), Vector3(20, 9, 0), Vector3(0, 7, 0), Vector3(0, 6.5, -30)]
	check(RouteMarker.advance(helix, 1, Vector3(0, 13, -12)) == 1, "on the top lap: still the top lap's corner")
	check(RouteMarker.find(helix, Vector3(0, 6.5, -12)) == 5, "respawned a lap down: that lap's stretch")
	check(RouteMarker.find(helix, Vector3(0, 13, -12)) == 1, "respawned on the top lap: the top lap")


## Walking each mall mission's guide line from end to end moves the mark
## through every point in order, and every point stands on the run: near
## the bot's line and on a floor.
func test_mall_guides_lead_to_the_goal() -> void:
	for id: String in MALL:
		await _load(_index(id))
		var guide: Array = run.mission.get("guide", [])
		check(guide.size() >= 8, "%s has a guide line (%d points)" % [id, guide.size()])
		var pts: Array[Vector3] = []
		for g: Array in guide:
			pts.append(Vector3(g[0], g[1], g[2]))
		var t := 0
		var highest := 0
		var back := false
		for i in range(1, pts.size()):
			for k in 20:
				var at := pts[i - 1].lerp(pts[i], (k + 1) / 20.0)
				var nt := RouteMarker.advance(pts, t, at)
				back = back or nt < t
				t = nt
				highest = maxi(highest, t)
		check(not back and t == pts.size(), "%s: the mark runs the whole line in order (ended on %d of %d)" % [id, t, pts.size()])
		var path: Array = run.mission.bot_path
		var space := player.get_world_3d().direct_space_state
		for p in pts:
			var near := INF
			for j in range(1, path.size()):
				var a := Vector2(path[j - 1][0], path[j - 1][1])
				var b := Vector2(path[j][0], path[j][1])
				var q := Vector2(p.x, p.z)
				var ab := b - a
				var u := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
				near = minf(near, q.distance_to(a + ab * u))
			check(near < 3.5, "%s: guide point %s is on the bot's line (%.1f m off)" % [id, p, near])
			var ray := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.0, 0), p + Vector3(0, -1.5, 0), 1)
			check(not space.intersect_ray(ray).is_empty(), "%s: guide point %s stands on a floor" % [id, p])
		# The goal text is short enough to read at a glance.
		for o: Dictionary in run.mission.objectives:
			check(String(o.get("text", "")).length() <= 56, "%s: short goal \"%s\"" % [id, o.get("text", "")])
		# Chalk and lights point the way.
		check(level.builder.get_tree().get_nodes_in_group("chalk").size() >= 4, "%s has courier chalk at its turns" % id)
		level.queue_free()
		level = null
		await tree.process_frame


## The high line in the car park skips the second lap's corner: reaching a
## later "reach" goal counts the ones before it, so nobody is sent back.
func test_reaching_a_later_goal_counts_the_ones_before() -> void:
	await _load(_index("m07_parking_spiral"))
	run.phase = MissionRun.Phase.RUNNING
	run._begin_objective(1)
	check(run.current_objective().get("name", "") == "level 2", "heading for level 2")
	# Straight onto the third lap's corner (level 1's start).
	run._check_objective(Vector3(-15.5, 7.0, -474.5))
	check(run.objective == 2, "level 2 counted on reaching level 1's corner (%d)" % run.objective)
	run._check_objective(Vector3(-15.5, 7.0, -474.5))
	check(run.objective == 3, "and level 1 itself (%d)" % run.objective)


## A line that tells you the way jumps the queue; a line about a place that
## waited too long is dropped; a conversation queued together waits for
## its own lines.
func test_radio_cues_jump_the_queue_and_stale_lines_drop() -> void:
	await _load(_index("m05_atrium"))
	var radio: RadioFeed = level.radio
	radio.queue.clear()
	radio.current = {}
	radio.say("host", "One.")
	radio.say("host", "Two.")
	radio.say("mags", "Left here.", true)
	check(radio.queue[0].line == "Left here.", "the cue goes first")
	radio.queue.clear()
	radio.say("host", "A long bit of banter that keeps going for quite a while, honestly.")
	radio.say("host", "Back at the food court!", false, true)
	radio.advance(0.0)
	radio.advance(RadioFeed.STALE_AFTER + 1.0)
	radio.advance(0.0)
	check(radio.history.all(func(l: Dictionary) -> bool: return l.line != "Back at the food court!"), "a stale place line is dropped")
	radio.queue.clear()
	radio.current = {}
	for k in 4:
		radio.say("mags", "Line %d of a conversation, said in full before the next one." % k, false, true)
	var heard := 0
	for k in 40:
		radio.advance(1.0)
		if not radio.current.is_empty() and String(radio.current.line).begins_with("Line "):
			heard = maxi(heard, int(String(radio.current.line).substr(5, 1)) + 1)
	check(heard == 4, "a conversation plays to the end (%d of 4)" % heard)


## A line the story needs goes ahead of every other line waiting and is
## never dropped; the lines of one conversation stay together.
func test_radio_must_lines_go_first_and_never_drop() -> void:
	await _load(_index("m05_atrium"))
	var radio: RadioFeed = level.radio
	radio.queue.clear()
	radio.current = {}
	radio.say("host", "A riff.", false, true, "", false, "checkpoint:0")
	radio.say("mags", "Left here.", true, true, "", false, "checkpoint:1")
	radio.say("echo", "The story.", false, false, "", true, "set_piece:a")
	radio.say("parker", "The answer.", false, false, "", true, "set_piece:a")
	var order: Array = radio.queue.map(func(l: Dictionary) -> String: return l.line)
	check(order == ["The story.", "The answer.", "Left here.", "A riff."], "must lines first, then the cue (%s)" % [order])
	radio.advance(0.0)
	radio.advance(RadioFeed.STALE_AFTER * 3.0)
	for k in 10:
		radio.advance(1.0)
	var heard: Array = radio.history.map(func(l: Dictionary) -> String: return l.line)
	check("The story." in heard and "The answer." in heard, "must lines are said, however long they wait")


## A spot's lines start early, by your speed, so they've been said as you
## get there: not yet when the spot is further than the lines take to say,
## now when it's within that, worked out at a run at least when you're
## slow, and never for a spot behind you.
func test_radio_spot_lines_start_early() -> void:
	await _load(_index("m05_atrium"))
	var radio: RadioFeed = level.radio
	var s: Dictionary = run.mission.radio.filter(func(r: Dictionary) -> bool: return r.has("at"))[0]
	var key := "at:%s" % str(s.at)
	var at := MissionBuilder.vec(s.at)
	var half := MissionBuilder.vec(s.size) * 0.5
	var reach := minf(half.x, half.z)
	var lead := radio._lead(key)
	check(lead >= RadioFeed.clip_length(s.who, s.line) + RadioFeed.LEAD - 0.01, "the lead covers the clip (%.1fs)" % lead)
	var toward := Vector3(0, 0, -15)
	check(not radio._coming_up(s, key, at + Vector3(0, 0, reach + lead * 15.0 + 5.0), toward), "too far at 15 m/s: not yet")
	check(radio._coming_up(s, key, at + Vector3(0, 0, reach + lead * 15.0 - 2.0), toward), "close enough at 15 m/s: now")
	var slow := Vector3(0, 0, -2)
	check(radio._coming_up(s, key, at + Vector3(0, 0, reach + lead * RadioFeed.LEAD_MIN_SPEED - 1.0), slow), "slow: worked out at a run")
	check(not radio._coming_up(s, key, at + Vector3(0, 0, reach + 3.0), -toward), "not for a spot behind you")


## The first time you play a level it holds you while the opening is said,
## then lets you go; after a restart the opening is skipped and you can go
## at once.
func test_opening_holds_you_until_it_is_said() -> void:
	var saved: ConfigFile = Campaign._save
	Campaign._save = ConfigFile.new()
	await _load(_index("l1_1_dawn_run"))
	check(level.holding(), "held at the start")
	check(level.radio.opening_playing(), "while the opening plays")
	player.scripted_input = level._hold
	var at := player.global_position
	for k in 40:
		if not level.holding():
			break
		level.radio.advance(1.0)
		await tree.physics_frame
	check(not level.holding(), "let go once the opening is said")
	check(player.scripted_input == null, "your controls are back")
	check(player.global_position.distance_to(at) < 0.5, "you stayed put meanwhile")
	var opening: Array = run.mission.radio.filter(func(r: Dictionary) -> bool: return r.get("on", "") == "start")
	var heard: Array = level.radio.history.map(func(l: Dictionary) -> String: return l.line)
	check(opening.all(func(r: Dictionary) -> bool: return r.line in heard), "every opening line was said")
	level.restart()
	check(await _await_restart(), "restarted")
	check(not level.holding(), "no hold after a restart")
	check(not level.radio.opening_playing(), "and no opening")
	Campaign._save = saved


## Along diagonal legs and 45 degree corners the city's fronts and kerbs
## run straight beside the course, not in 2 m steps: just past the slot (or
## pavement) beside a diagonal roof or street there is always a building,
## standing clear of the roofs, and just inside it never is; the kerb is
## straight too.
func test_city_edges_run_straight_along_angled_legs() -> void:
	var City_: Script = load("res://campaign/city.gd")
	var roofs := Route_.expand({"id": "t_edges", "route": [{"roof": 40, "y": 8}, {"turn": "left", "angle": 45, "size": 22},
		{"roof": 60}, {"gap": 5}, {"roof": 60}, {"turn": "right", "angle": 45, "size": 22}, {"roof": 40}]})
	var city := _city_shapes(roofs)
	var sides := 0
	var gaps := 0
	var pokes := 0
	var low := 0
	for p: Dictionary in roofs.pieces:
		if not p.has("building") or p.get("city", false) or not is_equal_approx(fposmod(float(p.get("yaw", 0.0)), 90.0), 45.0):
			continue
		var yaw := deg_to_rad(float(p.yaw))
		var c := Vector2(p.building[0], p.building[2])
		var across := Vector2(cos(yaw), -sin(yaw))
		var along := Vector2(sin(yaw), cos(yaw))
		var hw: float = float(p.size[0]) * 0.5 + City_.ROOF_MARGIN
		var d := -float(p.size[1]) * 0.5 + 2.0
		while d < float(p.size[1]) * 0.5 - 2.0:
			for side: float in [-1.0, 1.0]:
				sides += 1
				var out := _cover(city.buildings, c + along * d + across * side * (hw + 0.3))
				if out < 0.0:
					gaps += 1
				elif out < float(p.building[1]) + City_.CLEAR:
					low += 1
				if _cover(city.buildings, c + along * d + across * side * (hw - 0.3)) >= 0.0:
					pokes += 1
			d += 1.0
	check(sides > 200, "diagonal roofs to check (%d)" % sides)
	check(gaps == 0, "a front straight along the slot beside diagonal roofs (%d gaps of %d)" % [gaps, sides])
	check(pokes == 0, "and none pokes into the slot (%d)" % pokes)
	check(low == 0, "fronts stand clear of the roofs (%d too low)" % low)
	# A street: pavement right up to a straight kerb, fronts behind it.
	var street := Route_.expand({"id": "t_edges_street", "route": [{"street": 40}, {"turn": "left", "angle": 45, "size": 22},
		{"street": 80}, {"turn": "right", "angle": 45, "size": 22}, {"street": 40}]})
	city = _city_shapes(street)
	var leg: Array = street.route_legs[1]
	var o := Vector2(leg[0], leg[1])
	var yaw: float = leg[2]
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var right := Vector2(cos(yaw), -sin(yaw))
	var length: float = float(leg[3]) - float(street.route_legs[2][3]) - 11.0
	var kerb := 0
	var fronts := 0
	var n := 0
	# (Past the corners, which are wider than the street, plus their margin.)
	var d := 16.0
	while d < length - 5.0:
		for side: float in [-1.0, 1.0]:
			n += 1
			var at := o + fwd * d
			var w := Route_.WIDTH * 0.5
			if _cover(city.pavements, at + right * side * (w + 0.3)) < 0.0 or _cover(city.pavements, at + right * side * (w - 0.3)) >= 0.0:
				kerb += 1
			if _cover(city.buildings, at + right * side * (w + City_.STREET_MARGIN + 0.3)) < 0.0 \
					or _cover(city.buildings, at + right * side * (w + City_.STREET_MARGIN - 0.3)) >= 0.0:
				fronts += 1
		d += 1.0
	check(n > 100, "a diagonal street to check (%d)" % n)
	check(kerb == 0, "a straight kerb along the diagonal street (%d off of %d)" % [kerb, n])
	check(fronts == 0, "straight fronts behind its pavement (%d off of %d)" % [fronts, n])


## The city's buildings and pavements as outlines [PackedVector2Array, top].
func _city_shapes(m: Dictionary) -> Dictionary:
	var out := {"buildings": [], "pavements": []}
	for p: Dictionary in m.pieces:
		if not p.get("city", false):
			continue
		var poly := PackedVector2Array()
		var top := 0.0
		if p.has("slab"):
			for a: Array in p.slab:
				poly.append(Vector2(a[0], a[1]))
			top = float(p.top)
		elif p.has("building") or (p.has("box") and p.get("look", "") == "TILE"):
			var c: Array = p.get("building", p.get("box"))
			var s := Vector2(p.size[0], p.size[1]) if p.has("building") else Vector2(p.size[0], p.size[2])
			var yaw := deg_to_rad(float(p.get("yaw", 0.0)))
			var ax := Vector2(cos(yaw), -sin(yaw)) * s.x * 0.5
			var az := Vector2(sin(yaw), cos(yaw)) * s.y * 0.5
			var mid := Vector2(c[0], c[2])
			poly = PackedVector2Array([mid - ax - az, mid + ax - az, mid + ax + az, mid - ax + az])
			top = float(c[1]) if p.has("building") else float(c[1]) + float(p.size[1]) * 0.5
		else:
			continue
		(out.buildings if top > 1.0 else out.pavements).append([poly, top])
	return out


## The top of the highest outline over a point, or -1 for none.
func _cover(shapes: Array, at: Vector2) -> float:
	var best := -1.0
	for s: Array in shapes:
		if Geometry2D.is_point_in_polygon(at, s[0]):
			best = maxf(best, float(s[1]))
	return best


## The city's street and ground props (wrecks, dumpsters, rubble) stand
## clear of every building, never sunk into a facade.
func test_city_props_stand_clear_of_buildings() -> void:
	var PropKit_: Script = load("res://art/props/prop_kit.gd")
	for id: String in ["l1_2_the_yard", "l3_1_the_silt", "m08_storm_channels", "m09_rail_bridge"]:
		var m := Campaign.load_mission_file("res://campaign/missions/%s.json" % id)
		var walls: Array = []
		for p: Dictionary in m.pieces:
			if p.has("slab") and float(p.get("top", 6.0)) > 1.0:
				var poly := PackedVector2Array()
				for a: Array in p.slab:
					poly.append(Vector2(a[0], a[1]))
				walls.append(poly)
			elif p.has("building"):
				walls.append(_footprint(Vector2(p.building[0], p.building[2]), Vector2(p.size[0], p.size[1]), float(p.get("yaw", 0.0))))
		var props := 0
		var sunk: Array = []
		for p: Dictionary in m.pieces:
			if not p.get("city", false) or not p.has("prop") or p.get("collide", true) == false:
				continue
			props += 1
			var s: Vector3 = PropKit_.size_of(p.prop)
			var foot := _footprint(Vector2(p.at[0], p.at[2]), Vector2(s.x, s.z), float(p.get("yaw", 0.0)))
			for w: PackedVector2Array in walls:
				if not Geometry2D.intersect_polygons(foot, w).is_empty():
					sunk.append("%s at %s" % [p.prop, p.at])
					break
		check(props > 10, "%s has city props (%d)" % [id, props])
		check(sunk.is_empty(), "%s: no city prop in a building (%d: %s)" % [id, sunk.size(), sunk.slice(0, 4)])


func _footprint(c: Vector2, s: Vector2, yaw_deg: float) -> PackedVector2Array:
	var r := deg_to_rad(yaw_deg)
	var ax := Vector2(cos(r), -sin(r)) * s.x * 0.5
	var az := Vector2(sin(r), cos(r)) * s.y * 0.5
	return PackedVector2Array([c - ax - az, c + ax - az, c + ax + az, c - ax + az])
