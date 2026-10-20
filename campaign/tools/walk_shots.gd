extends SceneTree
## Runs a hand-made mission's bot line (as the tests do) and renders what
## the runner sees, first person with the mission HUD up, a few meters
## before each turn in the line and at each checkpoint: for checking that
## the goal and the way on read at every decision.
##   xvfb-run -a godot --path . --fixed-fps 60 -s res://campaign/tools/walk_shots.gd -- <out_dir> <mission id> [alt]
## "alt" runs bot_path_alt instead; "guide" prints a "guide" line for the
## mission file instead of shots: where the bot stood as it passed each
## waypoint (feet height), points closer than 3 m dropped. Scripts run with -s load before the
## autoloads, so nothing here is typed with classes that need them.

const TURN_RATE := 5.0
## How far before a turn the shot is taken.
const LOOKAHEAD := 7.0
const AIR := 1
const WALLRUN := 6

var out := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	var id: String = args[1]
	var key := "bot_path_alt" if args.size() > 2 and args[2] == "alt" else "bot_path"
	var guide_only := args.size() > 2 and args[2] == "guide"
	var guide: Array = []
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	var campaign: Script = load("res://campaign/campaign.gd")
	campaign.persist = false
	var all: Array = campaign.missions()
	for i in all.size():
		if all[i].id == id:
			campaign.current = i
	var level: Node = load("res://campaign/mission.tscn").instantiate()
	root.add_child(level)
	var player: Node3D = level.get_node("Player")
	player.use_device_input = false
	var frame_script: Script = load("res://player/input_frame.gd")
	player.scripted_input = frame_script.new()
	await physics_frame
	var health: Object = load("res://enemies/player_health.gd").ensure(player)
	health.can_die = false
	for c in level.find_children("*", "CanvasLayer", true, false):
		var keep: bool = c == level.radio or c == level.mission_hud
		(c as CanvasLayer).visible = keep
	var run: Node = level.run
	run.event.connect(func(e: String) -> void:
		if e.begins_with("objective:") and run.current_objective().get("type", "") in ["shoot", "clear", "duel"]:
			for enc: Node3D in level.builder.encounters:
				for en: Node in enc.enemies:
					if not en.is_dead:
						en.take_hit({"damage": 500.0, "zone": &"body", "position": en.global_position}))
	var path: Array = level.builder.mission[key]
	# Software rendering is slow: draw only the shots.
	RenderingServer.render_loop_enabled = false
	# Where to take shots: before each turn of 25 degrees or more.
	var shots: Array[int] = []
	for i in range(1, path.size() - 1):
		var a := Vector2(path[i][0] - path[i - 1][0], path[i][1] - path[i - 1][1]).normalized()
		var b := Vector2(path[i + 1][0] - path[i][0], path[i + 1][1] - path[i][1]).normalized()
		if a.dot(b) < cos(deg_to_rad(25.0)):
			shots.append(i)
	var taken := {}
	var last_checkpoint: int = run.checkpoint
	var walked := 0.0
	var last_pos := player.global_position
	var n := 0
	var next := 0
	var roll_armed := false
	var crouch_until := -1
	for t in 8000:
		if run.phase == 2:
			break
		var pos := player.global_position
		walked += Vector2(pos.x - last_pos.x, pos.z - last_pos.z).length()
		last_pos = pos
		var here := Vector2(pos.x, pos.z)
		var f: Object = frame_script.new()
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
					crouch_until = t + 30
				"roll":
					roll_armed = true
				"kick":
					f.kick_pressed = true
			next += 1
			var g := pos.snapped(Vector3.ONE * 0.5)
			if guide.is_empty() or Vector3(guide.back()[0], guide.back()[1], guide.back()[2]).distance_to(g) > 3.0:
				guide.append([g.x, g.y, g.z])
		# A shot coming up to a turn, or on crossing a checkpoint.
		var shoot_now := ""
		if next < path.size() and shots.has(next) and not taken.has(next) \
				and here.distance_to(Vector2(path[next][0], path[next][1])) < LOOKAHEAD:
			taken[next] = true
			shoot_now = "turn"
		if run.checkpoint != last_checkpoint:
			last_checkpoint = run.checkpoint
			shoot_now = "checkpoint"
		if shoot_now != "" and not guide_only:
			Engine.time_scale = 0.0
			RenderingServer.render_loop_enabled = true
			await _frames(4)
			var name := "%s_%02d_%dm_%s" % [id, n, roundi(walked), shoot_now]
			root.get_texture().get_image().save_png(out.path_join(name + ".png"))
			print("saved %s at %s  objective %d: %s" % [name, pos.snapped(Vector3.ONE * 0.1), run.objective, run.objective_text()])
			n += 1
			Engine.time_scale = 1.0
			RenderingServer.render_loop_enabled = false
		var target := Vector2(path[mini(next, path.size() - 1)][0], path[mini(next, path.size() - 1)][1])
		var to := target - here
		var dir := Vector3(to.x, 0.0, to.y).normalized() if to.length() > 0.01 else -Basis(Vector3.UP, player.yaw).z
		if player.state not in [AIR, WALLRUN]:
			var want := atan2(-dir.x, -dir.z)
			var turn := clampf(angle_difference(player.yaw, want), -TURN_RATE / 60.0, TURN_RATE / 60.0)
			if absf(turn) > 0.0001:
				player._look(turn, 0.0)
		var face := Basis(Vector3.UP, player.yaw)
		var move := Vector2(dir.dot(face.x), dir.dot(-face.z))
		if move.y > 0.0:
			move /= move.y
		f.move = Vector2(clampf(move.x, -0.6, 0.6), 1.0)
		if roll_armed and player.state == AIR and player.velocity.y < 0.0:
			var q := PhysicsRayQueryParameters3D.create(pos, pos + Vector3.DOWN * 1.2, 1)
			q.exclude = [player.get_rid()]
			if not player.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
				f.crouch_pressed = true
				f.crouch_held = true
				roll_armed = false
		if t < crouch_until:
			f.crouch_held = true
		if player.state == WALLRUN and player.wallrun_angle() < 0.05:
			f.lean = 1.0 if player._lean_toward_wall(1.0) > 0.0 else -1.0
		player.scripted_input = f
		await physics_frame
	if guide_only:
		print("GUIDE ", JSON.stringify(guide))
	print("finished: ", run.phase == 2, " falls ", run.falls, " walked ", roundi(walked))
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame
