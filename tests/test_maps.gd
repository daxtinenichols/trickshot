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
			f.crouch_held = player.global_position.z > route[next - 1][0] - 4.0 if next > 0 else false
		if player.state == Player.State.WALLRUN and player.wallrun_angle() < 0.05:
			# Like a person would: lean toward the wall to keep the run level.
			f.lean = 1.0 if player._lean_toward_wall(1.0) > 0.0 else -1.0
		player.scripted_input = f
		await tree.physics_frame
	return false


## Like _run_route, but follows a path that turns: steps trigger on the
## distance run along `path` (s) and lanes are offsets to the right of it.
## The view turns toward the path ahead like a player's mouse would, at most
## `turn_rate` radians a tick, only while running or in the air. Starts
## measuring from the path point nearest the player.
func _run_path(path: PackedVector3Array, route: Array, end_s: float, max_frames := 1800, log := false, turn_rate := 0.06) -> bool:
	var cum := PackedFloat32Array([0.0])
	for i in range(1, path.size()):
		cum.append(cum[i - 1] + Vector2(path[i].x - path[i - 1].x, path[i].z - path[i - 1].z).length())
	var seg := 0
	var best := INF
	for i in path.size() - 1:
		var d := _path_point(path, i, player.global_position).distance_to(Vector2(player.global_position.x, player.global_position.z))
		if d < best:
			best = d
			seg = i
	var next := 0
	var lane := 0.0
	var roll_armed := false
	for i in max_frames:
		var pos := player.global_position
		var p2 := Vector2(pos.x, pos.z)
		# Move on to later segments once they're closer.
		while seg < path.size() - 2 and _path_point(path, seg + 1, pos).distance_to(p2) <= _path_point(path, seg, pos).distance_to(p2):
			seg += 1
		var a := Vector2(path[seg].x, path[seg].z)
		var b := Vector2(path[seg + 1].x, path[seg + 1].z)
		var t := (b - a).normalized()
		var s := cum[seg] + clampf((p2 - a).dot(t), 0.0, (b - a).length())
		var right := Vector2(-t.y, t.x)
		var lateral := (p2 - a).dot(right)
		if log and i % 10 == 0:
			print("  t%4d s %.1f lat %.2f pos %s state %s speed %.1f" % [i, s, lateral, pos.snapped(Vector3.ONE * 0.01), Player.State.keys()[player.state], player.horizontal_speed()])
		if s > end_s:
			return true
		# Strafe to hold the lane, in the view's frame (the lane a step sets
		# counts from the next tick, as in _run_route).
		var v2 := Vector2(player.velocity.x, player.velocity.z)
		var side := (lane - lateral) * 0.8 - v2.dot(right) * 0.25
		var f := InputFrame.make(Vector2(clampf(side, -0.6, 0.6), 1.0))
		while next < route.size() and s > route[next][0]:
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
				"kick":
					f.kick_pressed = true
			next += 1
		# Face the path a few meters ahead.
		var ahead := _path_tangent(path, cum, s + 3.0 + player.horizontal_speed() * 0.2)
		var want := atan2(-ahead.x, -ahead.y)
		var err := wrapf(want - player.yaw, -PI, PI)
		if absf(err) > 0.001 and player.state in [Player.State.GROUND, Player.State.SLIDE, Player.State.CROUCH]:
			player._look(clampf(err, -turn_rate, turn_rate), 0.0)
		if roll_armed and player.state == Player.State.AIR and player.velocity.y < 0.0:
			var q := PhysicsRayQueryParameters3D.create(pos, pos + Vector3.DOWN * 1.2, 1)
			q.exclude = [player.get_rid()]
			if not player.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
				f.crouch_pressed = true
				f.crouch_held = true
				roll_armed = false
		if player.state == Player.State.SLIDE or player.state == Player.State.CROUCH:
			# Keep sliding until 4 m past the last step, like _run_route.
			f.crouch_held = s < route[next - 1][0] + 4.0 if next > 0 else false
		if player.state == Player.State.WALLRUN and player.wallrun_angle() < 0.05:
			f.lean = 1.0 if player._lean_toward_wall(1.0) > 0.0 else -1.0
		player.scripted_input = f
		await tree.physics_frame
	return false


## The point of path segment i nearest `pos`, in (x, z).
func _path_point(path: PackedVector3Array, i: int, pos: Vector3) -> Vector2:
	var a := Vector2(path[i].x, path[i].z)
	var b := Vector2(path[i + 1].x, path[i + 1].z)
	var ab := b - a
	var t := clampf((Vector2(pos.x, pos.z) - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return a + ab * t


## The path's direction (x, z) at distance s along it.
func _path_tangent(path: PackedVector3Array, cum: PackedFloat32Array, s: float) -> Vector2:
	for i in range(1, path.size()):
		if cum[i] >= s or i == path.size() - 1:
			return Vector2(path[i].x - path[i - 1].x, path[i].z - path[i - 1].z).normalized()
	return Vector2(0, -1)


## The rooftop course by the low line and the girder, as distances along
## RooftopCourseBuilder.path(): s = -z on leg 1, then 361.7 - x on leg 2
## (local z = world x) and 183 - z on leg 3. Lanes are meters right of the
## racing line.
const COURSE_ROUTE := [
	[12.6, "jump", 0.0],     # hurdle at -14
	[19.6, "jump", 0.0],     # hurdle at -21
	[26.5, "crouch", 0.0],   # slide bar at -31
	[38.8, "jump", 0.0],     # gap to R2
	[42.0, "", 3.3],         # line up with the window
	[54.5, "jump", 3.3],     # window at -58: jump through the glass
	[62.0, "", 5.4],         # toward the wall
	[72.3, "jump", 7.0],     # gap: into the wallrun wall
	[86.0, "", 0.3],
	[90.6, "jump", 0.3],     # hurdle at -92
	[102.2, "jump", 0.3],    # climb face at -104
	[110.5, "crouch", 0.3],  # hole at -114: slide through
	[118.0, "crouch", 0.3],  # and on to the drop, so a fast run's landing roll stops short of the hurdle
	[122.0, "roll", 0.3],    # drop to R5
	[130.0, "", 1.5],
	[140.6, "jump", 1.5],    # hurdles at -142, -152, -162
	[150.6, "jump", 1.5],
	[160.6, "jump", 1.5],
	[171.3, "jump", 1.5],    # gap to R6
	[180.0, "", 0.0],
	[198.6, "jump", 0.0],    # hurdles at -200, -215
	[213.6, "jump", 0.0],
	[223.5, "crouch", 0.0],  # slide bar at -228
	[238.8, "jump", 0.0],    # gap to R7
	[260.6, "jump", 0.0],    # vault row at -262
	[298.2, "jump", 0.3],    # climb face at -300
	[311.5, "crouch", 0.3],  # hole at -315: slide through
	[320.0, "", 0.0],
	[328.6, "jump", 0.0],    # hurdle at -330, then the first corner
	[386.3, "jump", 0.0],    # leg 2: hurdle at x -26
	[390.0, "", -10.0],      # the low line
	[426.3, "jump", -10.0],  # hurdles at x -66, -78
	[438.3, "jump", -10.0],
	[450.5, "jump", -10.0],  # gap down to the low roofs
	[452.0, "roll", -10.0],
	[475.2, "crouch", -10.0],# pipe at x -118
	[492.3, "jump", -10.0],  # hurdles at x -132, -144
	[504.3, "jump", -10.0],
	[519.9, "jump", -10.0],  # climb face at x -160
	[526.0, "", 0.0],        # the second corner
	[606.6, "jump", 0.0],    # leg 3: hurdles at -425, -440
	[621.6, "jump", 0.0],
	[651.4, "jump", 0.0],    # mantle up at -470
	[671.4, "jump", 0.0],    # mantle up at -490
	[693.6, "jump", 0.0],    # hurdle at -512
	[715.0, "", 5.0],        # the girder on the right
	[757.0, "", 0.0],
	[773.6, "jump", 0.0],    # hurdle at -592
	[798.0, "crouch", 0.0],  # slide down the ramp at -616
	[825.0, "", -4.0],
	[837.4, "jump", -4.0],   # hurdles at -656, -674, -688
	[855.4, "jump", -4.0],
	[869.4, "jump", -4.0],
	[882.3, "jump", 1.5],    # last gap, past the pillar
]
## Distance along the path to the finish line (z -740 on leg 3).
const COURSE_FINISH_S := 924.0


# ---------------------------------------------------------------- rooftops

func test_rooftops_spawns_are_standable() -> void:
	await _load(ROOFTOPS)
	var b: RooftopCourseBuilder = level.builder
	check(b.spawns.size() == 1 + RooftopCourseBuilder.CHECKPOINTS.size(), "start + one spawn per checkpoint")
	check(b.spawns[0] == RooftopCourseBuilder.ENTRY, "spawns[0] is ENTRY")
	for i in b.spawns.size():
		level.go_to_zone(i)
		await _step(40)
		check(player.state == Player.State.GROUND, "spawn %d: standing (%s)" % [i + 1, Player.State.keys()[player.state]])
		check_near(player.global_position.y, b.spawns[i].origin.y, 0.06, "spawn %d: on the roof" % (i + 1))
		var p0 := player.global_position
		await _step(30, TestWorld.forward_input())
		var fwd := -b.spawns[i].basis.z
		check((player.global_position - p0).dot(fwd) > 2.0, "spawn %d: free to run forward" % (i + 1))


func test_rooftops_full_run() -> void:
	await _load(ROOFTOPS)
	var timer: CourseTimer = level.timer
	await _step(10)
	check(timer.phase == CourseTimer.Phase.READY, "waits at the start")
	var done := await _run_path(RooftopCourseBuilder.path(), COURSE_ROUTE, COURSE_FINISH_S, 9000, OS.has_environment("BOT_LOG"))
	check(done, "a scripted run reaches the finish (stopped at %s)" % player.global_position)
	check(timer.falls == 0, "without falling (%d falls)" % timer.falls)
	check(timer.phase == CourseTimer.Phase.FINISHED, "timer finished")
	check(timer.checkpoint == RooftopCourseBuilder.CHECKPOINTS.size(), "passed every checkpoint")
	check(timer.best_ticks == timer.ticks and timer.ticks > 0, "set a best time")
	check_between(timer.seconds(), 60.0, 180.0, "plausible time (%.2f s)" % timer.seconds())


## Leg 2's other way: up the slab onto the high line, wallrun its gap and
## drop to the second corner.
func test_rooftops_high_line() -> void:
	await _load(ROOFTOPS)
	level.go_to_zone(6)
	await _step(10)
	var route := [
		[386.3, "jump", 0.0],    # hurdle at x -26
		[390.0, "", 8.0],        # the high line
		[436.3, "jump", 8.0],    # hurdle on the high roof at x -76
		[450.0, "", 13.4],       # toward the wall
		[461.0, "jump", 15.0],   # gap: into the wallrun wall
		[476.0, "", 8.0],
		[485.2, "crouch", 8.0],  # slide bar at x -128
		[520.0, "roll", 8.0],    # drop to the corner
	]
	var done := await _run_path(RooftopCourseBuilder.path(), route, 530.0, 1500, OS.has_environment("BOT_LOG"))
	check(done, "runs the high line to the corner (stopped at %s)" % player.global_position)
	check(level.timer.falls == 0, "without falling")
	check_near(player.global_position.y, 7.0, 0.2, "on the corner roof (%s)" % player.global_position)


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
	check(b.spawns.size() == 10, "ten spawns, one per number key (%d)" % b.spawns.size())
	check(b.spawns[0] == ComboParkBuilder.ENTRY, "spawns[0] is ENTRY")
	for i in b.spawns.size():
		level.go_to_zone(i)
		await _step(40)
		check(player.state == Player.State.GROUND, "spawn %d: standing (%s)" % [i + 1, Player.State.keys()[player.state]])
		check_near(player.global_position.y, 0.0, 0.06, "spawn %d: on the floor" % (i + 1))
		var p0 := player.global_position
		await _step(30, TestWorld.forward_input())
		var fwd := -b.spawns[i].basis.z
		check((player.global_position - p0).dot(fwd) > 2.0, "spawn %d: free to run forward" % (i + 1))


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

## The high road along the park's east side runs end to end above the
## ground: slab up, hurdle, pipe, gap, crates, climb, hurdle, wallrun gap,
## hurdles, slide down.
func test_park_high_road() -> void:
	await _load(PARK)
	var x := ComboParkBuilder.HIGH_ROAD_X
	player.respawn(Transform3D(Basis.IDENTITY, Vector3(x, 0, -62)))
	await _step(10)
	var path := PackedVector3Array([Vector3(x, 0, -60), Vector3(x, 0, -330)])
	var route := [
		[34.6, "jump", 0.0],     # hurdle at -96
		[45.5, "crouch", 0.0],   # pipe at -110
		[69.3, "jump", 0.0],     # gap at -130
		[87.9, "jump", 0.0],     # crates at -150
		[117.9, "jump", 0.0],    # climb face at -180
		[133.6, "jump", 0.0],    # hurdle at -195
		[155.0, "", 5.4],        # toward the wall
		[169.3, "jump", 7.0],    # gap at -230: into the wallrun wall
		[185.0, "", 0.0],
		[194.6, "jump", 0.0],    # hurdles at -256, -270
		[208.6, "jump", 0.0],
		[229.0, "crouch", 0.0],  # slide down at -290
	]
	var low := [INF]
	var watch := func() -> void:
		var p := player.global_position
		if p.z < -86.0 and p.z > -288.0:
			low[0] = minf(low[0], p.y)
	tree.physics_frame.connect(watch)
	var done := await _run_path(path, route, 258.0, 1800, OS.has_environment("BOT_LOG"))
	tree.physics_frame.disconnect(watch)
	check(done, "runs the high road to the end (stopped at %s)" % player.global_position)
	check(low[0] > 3.9, "never drops off it (lowest %.2f)" % low[0])
	check_near(player.global_position.y, 0.0, 0.1, "back on the ground")


## The overpass: up the ramp, round the 45 degree bend over a barrier or
## two, across the gap, and down the slab toward the exit.
func test_park_overpass() -> void:
	await _load(PARK)
	level.go_to_zone(9)
	await _step(10)
	var path := PackedVector3Array([Vector3(0, 0, -414), Vector3(0, 0, -470)])
	for i in range(1, 13):
		path.append(ComboParkBuilder.curve_at(ComboParkBuilder.CURVE_ANGLE * i / 12.0).origin)
	var end := ComboParkBuilder.curve_at(ComboParkBuilder.CURVE_ANGLE)
	path.append(end.origin - end.basis.z * 60.0)
	# s: 0 at z -414; the bend runs from s 56 to 84.3.
	var route := [
		[44.6, "jump", 0.0],     # barrier at -460
		[68.7, "jump", 0.0],     # barrier halfway round the bend
		[93.6, "jump", 0.0],     # the gap
		[115.0, "crouch", 0.0],  # slide down the slab
	]
	var high := [true]
	var watch := func() -> void:
		var p := player.global_position
		# On the deck: past the ramp up, before the slab down.
		if p.z < -451.0 and p.x > -32.0 and player.state != Player.State.AIR and p.y < ComboParkBuilder.DECK_Y - 0.5:
			high[0] = false
	tree.physics_frame.connect(watch)
	var done := await _run_path(path, route, 132.0, 1500, OS.has_environment("BOT_LOG"))
	tree.physics_frame.disconnect(watch)
	check(done, "runs the overpass to the slab (stopped at %s)" % player.global_position)
	check(high[0], "stays up on the deck until the slab")
	check(player.global_position.y < 1.0, "slides down to the ground (%s)" % player.global_position)


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
	check(b.spawns.size() == 9, "nine spawns (%d)" % b.spawns.size())
	check(b.spawns[0] == MallBuilder.ENTRY, "spawns[0] is ENTRY")
	for i in b.spawns.size():
		level.go_to_zone(i)
		await _step(40)
		check(player.state == Player.State.GROUND, "spawn %d: standing (%s)" % [i + 1, Player.State.keys()[player.state]])
		check_near(player.global_position.y, b.spawns[i].origin.y, 0.06, "spawn %d: on its floor" % (i + 1))
		var p0 := player.global_position
		await _step(30, TestWorld.forward_input())
		var fwd := -b.spawns[i].basis.z
		check((player.global_position - p0).dot(fwd) > 2.0, "spawn %d: free to run forward" % (i + 1))


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


## No running off the world: from outside each edge, looking in at running,
## jumping and wallrun heights, the first thing hit is the ring of buildings
## standing on the floor's edge.
func _check_closed(center: Vector3, size: Vector2, depth := 10.0) -> void:
	var space := level.get_world_3d().direct_space_state
	var half := size * 0.5
	var open := 0
	var samples := 0
	for side: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var along := Vector3(side.z, 0, side.x)
		var reach := half.x if side.x != 0.0 else half.y
		var span := half.y if side.x != 0.0 else half.x
		for t in range(-10, 11):
			for h: float in [1.0, 8.0, 16.0]:
				var edge := center + side * reach + along * span * t * 0.095 + Vector3(0, h, 0)
				var from := edge + side * (depth + 5.0)
				var q := PhysicsRayQueryParameters3D.create(from, edge - side * 2.0, 1)
				var r := space.intersect_ray(q)
				samples += 1
				if r.is_empty() or from.distance_to(r.position) > 5.2:
					open += 1
					if open <= 3:
						print("    open edge at %s" % edge)
	check(open == 0, "edges closed (%d of %d samples open)" % [open, samples])


## Slide-under bars (dressed as pipes and girders) stand on posts that reach
## the floor SLIDE_GAP m below them, so there must be floor there at both
## ends, not a drop: nothing floats.
func _check_bars_grounded() -> void:
	var dresser: Script = load("res://art/look/obstacle_dresser.gd")
	var space := level.get_world_3d().direct_space_state
	var bars := 0
	var floating := 0
	for body: Node in level.find_children("*", "StaticBody3D", true, false):
		if body.get_meta("kind", "") != "PARKOUR" or body.has_meta("look"):
			continue
		var size: Vector3 = dresser._box_size(body)
		var style: String = body.get_meta("dress", "")
		if style == "":
			style = dresser.pick_style("PARKOUR", size, (body as Node3D).global_position)
		if style != "pipe":
			continue
		bars += 1
		var b := body as Node3D
		var along := b.global_basis.x if size.x >= size.z else b.global_basis.z
		var half := maxf(size.x, size.z) * 0.5 - 0.15
		for sgn: float in [-1.0, 1.0]:
			var end := b.global_position + along.normalized() * half * sgn - Vector3(0, size.y * 0.5 + 0.02, 0)
			var q := PhysicsRayQueryParameters3D.create(end, end - Vector3(0, 3, 0))
			q.exclude = [b.get_rid()]
			var r := space.intersect_ray(q)
			if r.is_empty() or absf(end.y + 0.02 - r.position.y - dresser.SLIDE_GAP) > 0.1:
				floating += 1
				print("    bar end without floor %.1f m under it at %s" % [dresser.SLIDE_GAP, end])
	check(bars > 0, "the map has slide-under bars (%d)" % bars)
	check(floating == 0, "every bar's posts reach the floor (%d ends float)" % floating)


func test_slide_bars_stand_on_the_floor() -> void:
	for scene: PackedScene in [ROOFTOPS, PARK]:
		await _load(scene)
		_check_bars_grounded()
		level.queue_free()
		await tree.process_frame


func test_park_edges_closed() -> void:
	await _load(PARK)
	_check_closed(ComboParkBuilder.FLOOR_CENTER, ComboParkBuilder.FLOOR_SIZE)


func test_mall_edges_closed() -> void:
	await _load(MALL)
	_check_closed(MallBuilder.GROUND_CENTER, MallBuilder.GROUND_SIZE)


func test_sandbox_edges_closed() -> void:
	await _load(preload("res://levels/sandbox.tscn"))
	_check_closed(Vector3(10, 0, -27.5), Vector2(320, 285))


## The campaign's hand-off points: the exit and the skybridge door (built
## the way m06 and m07 build the mall) are real ground, and the far edge
## opens on request.
func test_mall_campaign_points() -> void:
	CourseTimer.persist = false
	level = MALL.instantiate()
	level.get_node("Builder").set("skybridge", true)
	tree.root.add_child(level)
	await tree.physics_frame
	var space := level.get_world_3d().direct_space_state
	for xf: Transform3D in [MallBuilder.EXIT, MallBuilder.ANCHOR_ENTRY, MallBuilder.ANCHOR_EXIT]:
		var q := PhysicsRayQueryParameters3D.create(xf.origin + Vector3(0, 1, 0), xf.origin + Vector3(0, -1, 0), 1)
		var r := space.intersect_ray(q)
		check(not r.is_empty() and absf(r.position.y - xf.origin.y) < 0.6, "ground under %s" % xf.origin)
	# Open far edge: built standalone, nothing stands past the end of the road.
	var open := (load("res://maps/mall_builder.gd") as GDScript).new() as Node3D
	open.set("open_exit", true)
	open.call("build")
	var far := MallBuilder.GROUND_CENTER.z - MallBuilder.GROUND_SIZE.y * 0.5
	var blocking := 0
	for c in (open.get_child(0) as Node).get_children():
		if c is StaticBody3D and (c as Node3D).position.z < far - 1.0:
			blocking += 1
	check(blocking == 0, "open_exit leaves the road open (%d pieces past it)" % blocking)
	open.free()


## A mission can leave out the Rooftops course's own signs (tutorial labels,
## start and FINISH lines, the targets past the finish) and keep the course.
func test_rooftops_hide_course_marks() -> void:
	var counts := []
	for hide in [false, true]:
		var b := (load("res://maps/rooftop_course_builder.gd") as GDScript).new() as Node3D
		b.set("hide_course_marks", hide)
		b.call("build")
		var labels := 0
		var bodies := 0
		var marks := 0
		var targets := 0
		for c in (b.get_child(0) as Node).get_children():
			if c is Label3D:
				labels += 1
			elif c is StaticBody3D:
				bodies += 1
			elif c is MeshInstance3D:
				marks += 1
			elif c.has_method("take_hit"):
				targets += 1
		counts.append([labels, bodies, marks, targets, (b.get("spawns") as Array).size()])
		for c in (b.get_child(0) as Node).get_children():
			if c.has_method("take_hit"):
				c.free()  # never entered the tree
		b.free()
	check(counts[0][0] > 10 and counts[0][2] >= 2 and counts[0][3] >= 2, "the course has signs, lines and targets (%s)" % [counts[0]])
	check(counts[1][0] == 0 and counts[1][2] == 0 and counts[1][3] == 0, "hidden: no labels, lines or targets (%s)" % [counts[1]])
	check(counts[1][1] == counts[0][1] and counts[1][4] == counts[0][4], "same roofs and spawns either way")


## The department store's roof is shut: where the roof hatch used to be,
## climbing at the wall gets nowhere near the roof, and the dock's back doors
## are shuttered.
func test_mall_roof_and_back_closed() -> void:
	await _load(MALL)
	player.respawn(Transform3D(Basis.IDENTITY, Vector3(14, MallBuilder.UPPER_Y, -350)))
	await _step(10)
	var space := level.get_world_3d().direct_space_state
	var best := -INF
	for i in 400:
		var f := _steer(14.0)
		var pos := player.global_position
		var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.6, 0), pos + Vector3(0, 0.6, -1.4), 1)
		q.exclude = [player.get_rid()]
		if player.state == Player.State.GROUND and not space.intersect_ray(q).is_empty():
			f.jump_pressed = true
		f.jump_held = true
		player.scripted_input = f
		await tree.physics_frame
		best = maxf(best, player.global_position.y)
	check(best < MallBuilder.ROOF_Y, "no way up to the roof (best y %.2f)" % best)
	for x: float in [-13.0, 0.0, 13.0]:
		var d := PhysicsRayQueryParameters3D.create(Vector3(x, 1.5, MallBuilder.DOCK_BACK + 3.0), Vector3(x, 1.5, MallBuilder.DOCK_BACK - 3.0), 1)
		check(not space.intersect_ray(d).is_empty(), "dock door at x %.0f is shut" % x)


## With skybridge, the covered way leaves the sales floor at ANCHOR_EXIT:
## a bot walks from there through both turns and up to the dock wall.
func test_mall_skybridge() -> void:
	CourseTimer.persist = false
	level = MALL.instantiate()
	level.get_node("Builder").set("skybridge", true)
	tree.root.add_child(level)
	player = level.get_node("Player")
	player.use_device_input = false
	player.scripted_input = InputFrame.new()
	await tree.physics_frame
	player.respawn(MallBuilder.ANCHOR_EXIT)
	await _step(10)
	var points := [Vector2(15, -402), Vector2(13, -406), Vector2(2, -406), Vector2(0, -410), Vector2(0, -429)]
	var next := 0
	for i in 900:
		var pos := player.global_position
		if next < points.size() and Vector2(pos.x, pos.z).distance_to(points[next]) < 1.5:
			next += 1
		if next >= points.size():
			break
		var to: Vector2 = points[next] - Vector2(pos.x, pos.z)
		player.set_view(atan2(-to.x, -to.y), 0.0)
		player.scripted_input = InputFrame.make(Vector2(0, 1))
		await tree.physics_frame
	check(next >= points.size(), "walks the skybridge to the dock wall (at %s)" % player.global_position)
	check(player.global_position.y > MallBuilder.SKY_END.y - 0.5, "climbed to the end (y %.2f)" % player.global_position.y)


## The old parking-lot kerb used to cross the north wing's concourse at
## z -100: the floor there is clear now.
func test_mall_concourse_floor_clear() -> void:
	await _load(MALL)
	var space := level.get_world_3d().direct_space_state
	for x: float in [-12.0, -6.0, 0.0, 6.0, 12.0]:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 0.5, -94), Vector3(x, 0.5, -106), 1)
		var hit := space.intersect_ray(q)
		check(hit.is_empty(), "nothing across the floor at x %.0f (%s)" % [x, hit.get("position", "")])


## The well through the store's sales floor (for the campaign's m06): the
## high line goes up the display stacks, along the partition wall and out
## onto the back of the sales floor; the escalators beside it climb there too.
func test_mall_store_well() -> void:
	await _load(MALL)
	player.respawn(Transform3D(Basis.IDENTITY, Vector3(-2.65, 0, -341)))
	await _step(10)
	var path := PackedVector3Array([Vector3(-2.65, 0, -340), Vector3(-2.65, 0, -400)])
	var route := [
		[8.4, "jump", 0.0],      # mantle the 1.5 m stack at -350
		[13.0, "jump", 0.0],     # mantle the 3 m stack at -355
		[16.5, "", -1.8],        # toward the wall
		[20.5, "jump", -3.2],    # into the wall
	]
	var done := await _run_path(path, route, 40.0, 900, OS.has_environment("BOT_LOG"))
	check(done, "gets through the well (stopped at %s)" % player.global_position)
	check(player.global_position.y > MallBuilder.UPPER_Y - 0.1, "up on the sales floor (%s)" % player.global_position)
	# The escalators run straight up to the same edge.
	for x: float in MallBuilder.WELL_ESCALATORS:
		player.respawn(Transform3D(Basis.IDENTITY, Vector3(x, 0, MallBuilder.WELL_Z.y + 18.0)))
		await _step(5)
		var best := 0.0
		player.scripted_input = TestWorld.forward_input()
		for i in 240:
			await tree.physics_frame
			best = maxf(best, player.global_position.y)
			if player.global_position.z < MallBuilder.WELL_Z.y - 3.0:
				break
		check(best > MallBuilder.UPPER_Y - 0.1 and player.global_position.z < MallBuilder.WELL_Z.y - 1.0, "escalator at x %.1f reaches the sales floor (%s)" % [x, player.global_position])


func test_rooftops_edges_closed() -> void:
	await _load(ROOFTOPS)
	_check_closed(RooftopCourseBuilder.STREET_CENTER, RooftopCourseBuilder.STREET_SIZE)


## The canal carries speed: run down the middle of it and stay on the floor
## the whole way.
func test_park_canal_run() -> void:
	await _load(PARK)
	level.go_to_zone(6)
	await _step(10)
	var low := INF
	for i in 900:
		var f := _steer(0.0)
		# Slide under the bars at -96, -140 and -184.
		for bar: float in [-96.0, -140.0, -184.0]:
			var d := player.global_position.z - bar
			if d < 5.0 and d > -1.0:
				f.crouch_pressed = d > 4.0
				f.crouch_held = true
		player.scripted_input = f
		await tree.physics_frame
		low = minf(low, player.global_position.y)
		if player.global_position.z < -205.0:
			break
	check(player.global_position.z < -205.0, "ran the length of the canal (at %s)" % player.global_position)
	check(low > -0.2, "never fell through")
