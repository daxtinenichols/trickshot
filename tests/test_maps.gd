extends TestCase
## The rooftop course and the combo park: both load, every spawn is a safe
## place to stand, a scripted runner can finish the course without falling,
## the course timer starts, checkpoints, catches falls and finishes, the combo
## park's features work in place, and F11 cycles the levels.

const ROOFTOPS := preload("res://maps/rooftops.tscn")
const PARK := preload("res://maps/combo_park.tscn")
const MALL := preload("res://maps/mall.tscn")

var level: Node3D
var player: Player


func _load(scene: PackedScene) -> void:
	CourseTimer.persist = false
	level = scene.instantiate()
	tree.root.add_child(level)
	player = level.get_node("Player")
	player.use_device_input = false
	player.scripted_input = InputFrame.new()
	await tree.physics_frame


func after_each() -> void:
	Engine.time_scale = 1.0
	if is_instance_valid(level):
		level.queue_free()
	level = null
	await tree.process_frame


func _step(frames: int, f: InputFrame = null) -> void:
	player.scripted_input = f if f != null else InputFrame.new()
	for i in frames:
		await tree.physics_frame


## Forward with a little strafe to hold lane x (the view faces -Z).
func _steer(x: float) -> InputFrame:
	var side := (x - player.global_position.x) * 0.8 - player.velocity.x * 0.25
	return InputFrame.make(Vector2(clampf(side, -0.6, 0.6), 1.0))


## Runs forward along -Z, doing each step's action once when z passes its
## trigger. Steps: [trigger_z, action, lane_x]. Actions: "jump", "crouch",
## "" (just change lane), "roll" (crouch just before landing).
## Returns false if it ran out of time before end_z.
func _run_route(route: Array, end_z: float, max_frames := 1800, log := false) -> bool:
	var lane := player.global_position.x
	var next := 0
	var roll_armed := false
	for i in max_frames:
		var pos := player.global_position
		if log and i % 10 == 0:
			print("  t%4d pos %s state %s speed %.1f" % [i, pos.snapped(Vector3.ONE * 0.01), Player.State.keys()[player.state], player.horizontal_speed()])
		if pos.z < end_z:
			return true
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
			# Like a person would: lean toward the wall to keep the run level.
			f.lean = 1.0 if player._lean_toward_wall(1.0) > 0.0 else -1.0
		player.scripted_input = f
		await tree.physics_frame
	return false


const COURSE_ROUTE := [
	[-12.6, "jump", 0.0],     # hurdle at -14
	[-19.6, "jump", 0.0],     # hurdle at -21
	[-26.5, "crouch", 0.0],   # slide bar at -31
	[-38.8, "jump", 0.0],     # gap to R2
	[-42.0, "", 3.3],         # line up with the window
	[-55.0, "crouch", 3.3],   # window at -58: slide through
	[-62.0, "", 5.4],         # toward the wall
	[-71.3, "jump", 7.0],     # gap: into the wallrun wall
	[-86.0, "", 0.3],
	[-90.6, "jump", 0.3],     # hurdle at -92
	[-102.2, "jump", 0.3],    # climb face at -104
	[-110.5, "crouch", 0.3],  # window at -114: slide through
	[-122.0, "roll", 0.3],    # drop to R5
	[-130.0, "", 1.5],
	[-140.6, "jump", 1.5],    # hurdles at -142, -152, -162
	[-150.6, "jump", 1.5],
	[-160.6, "jump", 1.5],
	[-171.3, "jump", 1.5],    # gap to R6
]


# ---------------------------------------------------------------- rooftops

func test_rooftops_spawns_are_standable() -> void:
	await _load(ROOFTOPS)
	var b: RooftopCourseBuilder = level.builder
	check(b.spawns.size() == 1 + RooftopCourseBuilder.CHECKPOINTS.size(), "start + one spawn per checkpoint")
	for i in b.spawns.size():
		level.go_to_zone(i)
		await _step(40)
		check(player.state == Player.State.GROUND, "spawn %d: standing (%s)" % [i + 1, Player.State.keys()[player.state]])
		check_near(player.global_position.y, b.spawns[i].origin.y, 0.06, "spawn %d: on the roof" % (i + 1))
		var z0 := player.global_position.z
		await _step(30, TestWorld.forward_input())
		check(z0 - player.global_position.z > 2.0, "spawn %d: free to run forward" % (i + 1))


func test_rooftops_full_run() -> void:
	await _load(ROOFTOPS)
	var timer: CourseTimer = level.timer
	await _step(10)
	check(timer.phase == CourseTimer.Phase.READY, "waits at the start")
	var done := await _run_route(COURSE_ROUTE, RooftopCourseBuilder.FINISH_Z - 1.0, 2400)
	check(done, "a scripted run reaches the finish (stopped at %s)" % player.global_position)
	check(timer.falls == 0, "without falling (%d falls)" % timer.falls)
	check(timer.phase == CourseTimer.Phase.FINISHED, "timer finished")
	check(timer.checkpoint == RooftopCourseBuilder.CHECKPOINTS.size(), "passed every checkpoint")
	check(timer.best_ticks == timer.ticks and timer.ticks > 0, "set a best time")
	check_between(timer.seconds(), 15.0, 45.0, "plausible time (%.2f s)" % timer.seconds())


func test_rooftops_fall_returns_to_checkpoint() -> void:
	await _load(ROOFTOPS)
	var timer: CourseTimer = level.timer
	var b: RooftopCourseBuilder = level.builder
	await _step(5)
	# Start the clock, then teleport past the first checkpoint and drop off.
	player.global_position = Vector3(0, 10.05, -8)
	await _step(5)
	check(timer.phase == CourseTimer.Phase.RUNNING, "crossing the start line starts the clock")
	player.global_position = Vector3(0, 10.05, -47)
	await _step(5)
	check(timer.checkpoint == 1, "checkpoint reached")
	var t := timer.ticks
	player.global_position = Vector3(0, 1.0, -75)
	await _step(3)
	check(timer.falls == 1, "fall counted")
	check(player.global_position.distance_to(b.spawns[1].origin) < 1.0, "back at the checkpoint (%s)" % player.global_position)
	check(timer.phase == CourseTimer.Phase.RUNNING and timer.ticks > t, "clock keeps running")
	# A number key restarts from that spawn, as practice.
	level.go_to_zone(2)
	await _step(2)
	check(timer.phase == CourseTimer.Phase.READY and timer.practice and timer.checkpoint == 2, "zone key resets to practice from there")
	level.go_to_zone(0)
	await _step(2)
	check(not timer.practice and timer.ticks == 0, "key 1 resets a real run")


func test_rooftops_wallrun_gap() -> void:
	await _load(ROOFTOPS)
	level.go_to_zone(1)
	await _step(20)
	# Like a person would: angle toward the wall, jump off the edge into it.
	player.global_position = Vector3(2.0, 10.05, -60)
	player.set_view(-0.3)
	await _step(5)
	var wallran := [false]
	player.state_changed.connect(func(_a: Player.State, b: Player.State) -> void:
		if b == Player.State.WALLRUN:
			wallran[0] = true)
	await _w_until(func() -> bool: return player.global_position.z < -71.0 or player.global_position.x > 5.6, 200)
	await _step(1, InputFrame.make(Vector2(0, 1), true))
	await _w_until(func() -> bool: return player.global_position.z < -88.0 or player.global_position.y < 5.0, 300)
	check(wallran[0], "wallruns across the gap")
	check(player.global_position.y > 9.5 and player.global_position.z < -84.0, "lands on the next roof (%s)" % player.global_position)


func _w_until(cond: Callable, frames: int) -> void:
	player.scripted_input = TestWorld.forward_input()
	for i in frames:
		await tree.physics_frame
		if cond.call():
			return


func test_rooftops_finish_time_formats() -> void:
	check(CourseTimer.format_time(0.0) == "0:00.00", "zero")
	check(CourseTimer.format_time(83.456) == "1:23.46", "minutes and hundredths (%s)" % CourseTimer.format_time(83.456))


# ---------------------------------------------------------------- combo park

func test_park_spawns_are_standable() -> void:
	await _load(PARK)
	var b: ComboParkBuilder = level.builder
	check(b.spawns.size() == 6, "six spawns (%d)" % b.spawns.size())
	for i in b.spawns.size():
		level.go_to_zone(i)
		await _step(40)
		check(player.state == Player.State.GROUND, "spawn %d: standing (%s)" % [i + 1, Player.State.keys()[player.state]])
		check_near(player.global_position.y, 0.0, 0.06, "spawn %d: on the floor" % (i + 1))
		var z0 := player.global_position.z
		await _step(30, TestWorld.forward_input())
		check(z0 - player.global_position.z > 2.0, "spawn %d: free to run forward" % (i + 1))


func test_park_tower_mantle_and_climb() -> void:
	await _load(PARK)
	level.go_to_zone(0)
	await _step(20)
	# Steps at z 7..11 (1.5 m), tier at 7 (3 m), climb face at z 1 (6 m).
	var ok := await _run_route([[12.5, "jump", 0.0], [8.5, "jump", 0.0], [3.0, "jump", 0.0]], -1.0, 400)
	check(ok, "got up the tower (stopped at %s)" % player.global_position)
	check(player.global_position.y > 5.9, "on the top tier (%s)" % player.global_position)


func test_park_half_pipe_both_sides() -> void:
	await _load(PARK)
	level.go_to_zone(1)
	await _step(20)
	var rode := [0]
	player.state_changed.connect(func(_a: Player.State, b: Player.State) -> void:
		if b == Player.State.SURFACE:
			rode[0] += 1)
	await _step(150, TestWorld.forward_input())
	check(rode[0] >= 1, "rides the north quarter pipe")
	# Turn around and ride the other one.
	level.go_to_zone(1)
	await _step(20)
	player.set_view(PI)
	var before: int = rode[0]
	await _step(150, TestWorld.forward_input())
	check(rode[0] > before, "rides the south (turned) quarter pipe")


func test_park_loop_runway() -> void:
	await _load(PARK)
	level.go_to_zone(2)
	await _step(20)
	var top := [-INF]
	for i in 600:
		await _step(1, TestWorld.forward_input())
		if player.state == Player.State.SURFACE:
			top[0] = maxf(top[0], player.global_position.y)
		if player.global_position.z < -40.0:
			break
	check(top[0] > 7.0, "goes over the top of the loop (max height %.1f)" % top[0])


func test_park_zigzag_wallrun() -> void:
	await _load(PARK)
	level.go_to_zone(3)
	await _step(20)
	var wallran := [false]
	player.state_changed.connect(func(_a: Player.State, b: Player.State) -> void:
		if b == Player.State.WALLRUN:
			wallran[0] = true)
	# First panel is on the left (x -3) from z -30 to -38: angle toward it.
	player.set_view(0.2)
	await _w_until(func() -> bool: return player.global_position.z < -29.0, 200)
	await _step(1, InputFrame.make(Vector2(0, 1), true))
	await _w_until(func() -> bool: return wallran[0], 90)
	check(wallran[0], "wallruns the first zigzag panel")


# ---------------------------------------------------------------- switcher

func test_level_keys() -> void:
	check(InputMap.has_action(Levels.ACTION), "next_level action registered")
	var k := InputEventKey.new()
	for key: Key in [KEY_F9, KEY_F10, KEY_F11]:
		k.physical_keycode = key
		k.pressed = true
		check(not GameSettings.is_bindable(k, false), "%s is reserved" % OS.get_keycode_string(key))
	for entry: Array in Levels.LEVELS:
		check(ResourceLoader.exists(entry[0]), "%s exists" % entry[1])


func _ride_bank(spawn: int, view: float, approach: Callable, max_frames := 300, steer := 0.0) -> Dictionary:
	level.go_to_zone(spawn)
	await _step(20)
	player.set_view(view)
	var on := [0, INF, -INF]  # frames on the surface, min z, max height
	player.scripted_input = TestWorld.forward_input()
	for i in max_frames:
		await tree.physics_frame
		# Once on the ramp, steer up it.
		player.scripted_input = InputFrame.make(Vector2(steer if player.state == Player.State.SURFACE else 0.0, 1.0))
		if player.state == Player.State.SURFACE:
			on[0] += 1
			on[1] = minf(on[1], player.global_position.z)
			on[2] = maxf(on[2], player.global_position.y)
		if approach.call():
			break
	return {"frames": on[0], "min_z": on[1], "top": on[2]}


func test_park_banked_ramp() -> void:
	await _load(PARK)
	# Spawn 6 is beside the first bank (starts x -34, rises toward -X); angle
	# a little left so you run up onto it.
	var r := await _ride_bank(5, 0.3, func() -> bool: return player.global_position.z < 10.0)
	check(r.frames > 30, "runs along the sideways ramp (%d frames)" % r.frames)
	# Steering into it carries you up the slope.
	var up := await _ride_bank(5, 0.3, func() -> bool: return player.global_position.z < 10.0, 300, -0.7)
	check(up.top > 0.6, "steering up the slope gains height (%.2f m)" % up.top)


func test_rooftops_banked_ramp() -> void:
	await _load(ROOFTOPS)
	player.global_position = Vector3(4.5, 4.05, -128.5)
	await _step(5)
	player.set_view(-0.32)
	var on := 0
	player.scripted_input = TestWorld.forward_input()
	for i in 200:
		await tree.physics_frame
		if player.state == Player.State.SURFACE:
			on += 1
		if player.global_position.z < -140.0:
			break
	check(on > 15, "runs on the rooftop sideways ramp (%d frames)" % on)
	check(player.global_position.y > 3.5, "still on the roof (%s)" % player.global_position)


# ---------------------------------------------------------------- ruined mall

func test_mall_spawns_are_standable() -> void:
	await _load(MALL)
	var b: MallBuilder = level.builder
	check(b.spawns.size() == 6, "six spawns (%d)" % b.spawns.size())
	for i in b.spawns.size():
		level.go_to_zone(i)
		await _step(40)
		check(player.state == Player.State.GROUND, "spawn %d: standing (%s)" % [i + 1, Player.State.keys()[player.state]])
		check_near(player.global_position.y, b.spawns[i].origin.y, 0.06, "spawn %d: on its floor" % (i + 1))
		var z0 := player.global_position.z
		await _step(30, TestWorld.forward_input())
		check(z0 - player.global_position.z > 2.0, "spawn %d: free to run forward" % (i + 1))


## Running straight up the west escalator ends on the upper floor.
func test_mall_escalator_climbs() -> void:
	await _load(MALL)
	player.respawn(Transform3D(Basis.IDENTITY, Vector3(-MallBuilder.ESCALATOR_X, 0, -10)))
	await _step(10)
	var top := -INF
	for i in 150:
		player.scripted_input = _steer(-MallBuilder.ESCALATOR_X)
		await tree.physics_frame
		top = maxf(top, player.global_position.y)
		if player.global_position.z < -32.0:
			break
	check(player.global_position.y > MallBuilder.UPPER_Y - 0.3, "reached the landing (%s, best y %.2f)" % [player.global_position, top])
	check(player.state == Player.State.GROUND, "standing on it (%s)" % Player.State.keys()[player.state])


## The storefronts are real breakable glass, turned to face the corridor.
func test_mall_storefront_glass() -> void:
	await _load(MALL)
	var panes := tree.get_nodes_in_group("windows").filter(func(w: Node) -> bool: return level.is_ancestor_of(w))
	check(panes.size() >= 20, "storefront and door glass (%d panes)" % panes.size())
	var side := 0
	for w: Node3D in panes:
		if absf(absf(w.global_position.x) - MallBuilder.SHOP_X - 0.2) < 0.05:
			side += 1
			check_near(absf(w.global_basis.x.z), 1.0, 0.01, "shop pane spans along the front")
	check(side >= 20, "two panes per ground shop (%d)" % side)
