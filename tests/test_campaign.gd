extends TestCase
## The campaign: the mission list matches the story, every built mission
## loads and is safe to stand in, MissionRun's checkpoints, falls,
## objectives, tapes and results work, the radio plays the right lines, the
## Host's chase catches you when you stop, and scripted runs can finish
## missions 0 and 12 and every mission built from a route.

const MISSION := preload("res://campaign/mission.tscn")
const MENU := preload("res://campaign/campaign.tscn")
const PIECE_KEYS := ["box", "building", "prop", "row", "door", "doors", "window", "target", "ramp", "loop",
	"quarter_pipe", "bank", "label", "mark", "tape", "fire", "encounter", "slab", "figure", "set_piece"]

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
	player.global_position = _camp()
	await _step(3)
	check(run.phase == MissionRun.Phase.COMPLETE, "reaching camp completes the mission")
	check(Campaign.is_complete(_index("m00_dawn_run")), "progress saved")
	check(level.mission_hud.results_visible(), "results shown")
	check(int(Campaign.best(_index("m00_dawn_run")).ticks) == run.ticks, "best time saved")


## Dawn Run's camp: the end of its route along the docks.
func _camp() -> Vector3:
	var at := MissionBuilder.vec(run.mission.objectives[1].at)
	return Vector3(at.x, 4.05, at.z)


func test_zone_key_starts_a_practice_run() -> void:
	await _load(_index("m00_dawn_run"))
	level.go_to_zone(3)
	await _step(3)
	check(run.practice and run.checkpoint == 3, "practice from the third checkpoint")
	check(run.objective == 1, "on that checkpoint's objective (%d)" % run.objective)
	player.global_position = _camp()
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
	run._back_to_checkpoint()
	check(not beam.fired and shapes.all(func(c: CollisionShape3D) -> bool: return c.disabled), "a checkpoint puts it back")


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
## the route's frame ("veer" heads across to a far lane). Returns true once
## the mission is complete; false if it runs out of time or passes stop_z
## first.
func _run_route(route: Array, max_frames := 2400, stop_z := -INF, legs: Array = []) -> bool:
	_legs = legs if not legs.is_empty() else [[0.0, 0.0, 0.0, 0.0]]
	_leg = 0
	var lane: float = route[0][2] if route[0][1] == "" and not is_nan(route[0][2]) else _local(player.global_position, 0).x
	var veer := false
	var next := 0
	var roll_armed := false
	for i in max_frames:
		var pos := player.global_position
		if run.phase == MissionRun.Phase.COMPLETE:
			return true
		_update_leg(pos)
		var z := _local(pos, _leg).y
		if z < stop_z:
			return false
		if OS.has_environment("ROUTE_LOG") and i % 10 == 0:
			print("  t%4d pos %s leg %d along %.1f state %s speed %.1f obj %d falls %d caught %d gap %.1f" % [i, pos.snapped(Vector3.ONE * 0.01), _leg, z, Player.State.keys()[player.state], player.horizontal_speed(), run.objective, run.falls, run.catches, run.pursuer.gap if run.pursuer else 0.0])
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
			next += 1
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


## Rooftops as legs for the bot: the lines between its corners, so local z
## runs on continuously from leg to leg ([origin x, origin z, yaw, z0]).
const ROOFTOPS_LEGS := [[0.0, 0.0, 0.0, 0.0], [0.0, -369.0, PI * 0.5, -369.0], [-198.0, -369.0, 0.0, -567.0]]


## test_maps' run of the whole Rooftops course (distances along its racing
## line, which rounds the corners) turned into steps on ROOFTOPS_LEGS.
func _rooftops_steps() -> Array:
	var course: Array = load("res://tests/test_maps.gd").get_script_constant_map().COURSE_ROUTE
	var out: Array = []
	for step: Array in course:
		var s: float = step[0]
		var shift := 0.0 if s < 378.7 else (7.3 if s < 570.0 else 15.0)
		out.append([-s - shift, step[1], step[2]])
	return out


## Dawn Run is the whole Rooftops course (the delivery on its high roof),
## then the mission's own route along the docks to camp.
func test_dawn_run_can_be_finished() -> void:
	await _load(_index("m00_dawn_run"))
	PlayerHealth.ensure(player).can_die = false
	await _step(10)
	var m: Dictionary = run.mission
	var exit_z: float = float(m.route_legs[0][1]) - 198.0
	var base_done := await _run_route(_rooftops_steps(), 9000, exit_z + 6.0, ROOFTOPS_LEGS)
	check(not base_done and run.objective == 1, "the bot crosses Rooftops with the parcel delivered (objective %d, at %s)" % [run.objective, player.global_position])
	var done := await _run_route(m.bot, 3000, -INF, m.route_legs)
	check(done, "and finishes Dawn Run at camp (stopped at %s, objective %d)" % [player.global_position, run.objective])
	check(run.falls == 0, "without falling (%d)" % run.falls)
	check(m.checkpoints.size() == 10 and m.checkpoints[0].name == "Door and window", "the base's checkpoints come before the route's")


## Dawn Run sets its base's hide_course_marks (via "base_set"), so none of
## the Rooftops course's own signs or its FINISH line show mid-mission.
func test_dawn_run_hides_the_course_signs() -> void:
	await _load(_index("m00_dawn_run"))
	var b: MissionBuilder = level.builder
	check(b.base != null and b.base.get("hide_course_marks") == true, "the base was told to hide its marks")
	var finish := 0
	for l: Label3D in b.base.find_children("*", "Label3D", true, false):
		finish += 1
	check(finish == 0, "no Rooftops labels (%d)" % finish)


## The Yard: the yard's lessons, then out of the park's far end and down
## the mission's own streets to the south gate.
func test_the_yard_ends_at_the_south_gate() -> void:
	await _load(_index("m01_the_yard"))
	var m: Dictionary = run.mission
	check(m.route_length > 150.0, "a run out past the park (%d m)" % int(m.route_length))
	var exit: Transform3D = load(m.base).EXIT
	player.respawn(exit)
	player.set_spawn(exit)
	await _step(10)
	# The lessons, done for the bot.
	run._begin_objective(4)
	var done := await _run_route(m.bot, 2400, -INF, m.route_legs)
	check(done, "a bot runs from the park's exit to the gate (stopped at %s, objective %d)" % [player.global_position, run.objective])
	check(run.falls == 0, "without falling (%d)" % run.falls)


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
	# One kill, then go down: the one you killed stays dead (Dax: killed
	# enemies don't respawn), the rest go back to their spots, and the
	# count keeps the kill.
	enc.enemies[0].take_hit({"damage": 500.0, "zone": &"body", "position": enc.enemies[0].global_position})
	check(run.bonus_text().contains("(1 / 3)"), "one down (%s)" % run.bonus_text())
	var health: PlayerHealth = PlayerHealth.of(player)
	health.take_damage(500.0, Vector3.ZERO)
	await _step(2)
	check(run.downs == 1, "went down once")
	check(player.global_position.distance_to(b.spawns[2].origin) < 1.0, "back at the checkpoint (%s)" % player.global_position)
	check(enc.enemies[0].is_dead and not enc.enemies[0].visible, "the killed raider stays dead")
	check(enc.alive_count() == n - 1, "the others reset (%d alive)" % enc.alive_count())
	check(run.bonus_text().contains("(1 / 3)"), "the kill still counts (%s)" % run.bonus_text())
	var score: int = level.combo.score
	for e: Node in enc.enemies:
		e.take_hit({"damage": 500.0, "zone": &"head", "position": e.global_position})
	await _step(2)
	check(run.bonuses[1].done and run.bonuses_done() == 1, "the lookouts are down: bonus done")
	check(level.combo.score >= score + MissionRun.BONUS_POINTS, "and it pays (%d -> %d)" % [score, level.combo.score])
	check(run.objective == 2, "still heading for the mast")
	check(run.headshots == n - 1, "headshots counted (%d)" % run.headshots)
	await _step(400)
	check(enc.alive_count() == 0, "a cleared encounter stays cleared")
	# Going down again doesn't bring anyone back either.
	health.take_damage(500.0, Vector3.ZERO)
	await _step(2)
	check(enc.alive_count() == 0 and enc.phase == EnemyEncounter.Phase.CLEARED, "still cleared after going down")


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
				check(m.id == "m01_the_yard", "%s: kill goal '%s' is required" % [m.id, o.get("text", "")])


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


## Runs the loaded mission's route bot (or its fork lines) to the end.
func _bot_run(label: String, alt := false) -> void:
	var health := PlayerHealth.ensure(player)
	health.can_die = false
	run.event.connect(func(e: String) -> void:
		if e.begins_with("objective:") and run.current_objective().get("type", "") in ["shoot", "clear", "duel"]:
			for enc: Node3D in level.builder.encounters:
				for en: Node in enc.enemies:
					if not en.is_dead:
						en.take_hit({"damage": 500.0, "zone": &"body", "position": en.global_position}))
	await _step(10)
	var bot: Array = run.mission.bot_alt if alt else run.mission.bot
	var frames := int(run.mission.route_length / 6.0 * 60.0) + 600
	if OS.has_environment("ROUTE_ONLY"):
		print("  %s: %d m, %d legs, %d checkpoints, %d encounters, %d enemies, legs %s" % [label, int(run.mission.route_length),
			run.mission.route_legs.size(), level.builder.spawns.size() - 1, level.builder.encounters.size(),
			level.builder.encounters.reduce(func(n: int, e: Node) -> int: return n + e.enemies.size(), 0), run.mission.route_legs])
	var done := await _run_route(bot, frames, -INF, run.mission.get("route_legs", []))
	check(done, "%s: a bot finishes the %d m route (stopped at %s, objective %d)" % [label, int(run.mission.route_length), player.global_position.snapped(Vector3.ONE * 0.1), run.objective])
	check(run.falls == 0, "%s: without falling (%d)" % [label, run.falls])
	check(run.mission.route_length >= 500.0, "%s: a long run (%d m)" % [label, int(run.mission.route_length)])
	level.queue_free()
	level = null
	await tree.process_frame


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
		if p.has("slab"):
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
