extends SceneTree
## Renders the Host for review: next to Parker, his pose sheet (run, lunge,
## fall, landing), and the chase in Signal Out from in front of Echo
## looking back at him (frames for a clip with `clip`).
##   xvfb-run -a godot --path . --fixed-fps 60 -s res://art/tools/host_shots.gd -- <out_dir> [lineup,poses,chase,clip]
## Scripts run with -s load before the autoloads, so nothing here is typed
## with classes that need them.

const BODY_PATH := "res://art/characters/runner/runner_body.gd"
const HOST_BODY_PATH := "res://art/characters/host/host_body.gd"
const POSES := ["idle", "run_a", "run_b", "run_c", "lunge", "fall", "land"]

var out := "user://host_shots"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	var parts := args[1].split(",") if args.size() > 1 else PackedStringArray(["lineup", "poses", "chase"])
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	var campaign: Script = load("res://campaign/campaign.gd")
	campaign.persist = false
	if "lineup" in parts or "poses" in parts:
		var level: Node3D = load("res://levels/sandbox.tscn").instantiate()
		root.add_child(level)
		var player: Node = level.get_node("Player")
		player.use_device_input = false
		player.scripted_input = InputFrame.new()
		await _frames(5)
		level.go_to_zone(0)
		player.set_physics_process(false)
		var spot: Vector3 = player.global_position + Vector3(-6, 0, -6)
		if "lineup" in parts:
			await _lineup(level, spot)
		if "poses" in parts:
			await _pose_sheet(level, spot)
		level.queue_free()
		await _frames(2)
	if "chase" in parts or "clip" in parts:
		await _chase(campaign, "clip" in parts)
	quit()


func _body(level: Node3D, runner: String, at: Vector3, yaw_deg: float, scale := 1.0) -> Node3D:
	var body: Node3D = load(BODY_PATH).new()
	body.runner = runner
	level.add_child(body)
	body.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)).scaled(Vector3.ONE * scale), at)
	return body


func _camera(level: Node3D, from: Vector3, at: Vector3, fov: float) -> Camera3D:
	var cam := Camera3D.new()
	cam.cull_mask &= ~4  # skip the first-person gun (Pistol.VIEW_LAYER)
	level.add_child(cam)
	cam.fov = fov
	cam.look_at_from_position(from, at)
	cam.add_child(root.get_node("ArtLook").make_outline_quad())
	cam.make_current()
	return cam


## Parker and the Host side by side, front three-quarter and from behind,
## then a close-up of the Host's head.
func _lineup(level: Node3D, spot: Vector3) -> void:
	var parker := _body(level, "parker", spot + Vector3(-0.7, 0, 0), -20.0)
	var host := _body(level, "host", spot + Vector3(0.7, 0, 0), -20.0, 1.1)
	parker.pose_override = RunnerPoses.idle()
	host.pose_override = RunnerPoses.idle()
	var cam := _camera(level, spot + Vector3(-1.2, 1.3, 4.6), spot + Vector3(0, 0.95, 0), 38.0)
	await _frames(6)
	_save("host_lineup")
	cam.global_position = spot + Vector3(1.6, 1.4, -4.4)
	cam.look_at(spot + Vector3(0, 1.0, 0))
	await _frames(4)
	_save("host_lineup_back")
	cam.global_position = spot + Vector3(0.35, 1.85, 1.3)
	cam.look_at(spot + Vector3(0.7, 1.72, 0))
	cam.fov = 34.0
	await _frames(4)
	_save("host_closeup")
	cam.global_position = spot + Vector3(2.0, 1.85, 0.5)
	cam.look_at(spot + Vector3(0.7, 1.7, 0))
	await _frames(4)
	_save("host_closeup_side")
	cam.queue_free()
	parker.queue_free()
	host.queue_free()


func _pose_sheet(level: Node3D, spot: Vector3) -> void:
	var host_body: Script = load(HOST_BODY_PATH)
	var body := _body(level, "host", spot, -70.0, 1.1)
	var cam := _camera(level, spot + Vector3(-1.6, 1.4, 4.2), spot + Vector3(0, 0.95, 0), 40.0)
	var tiles: Array[Image] = []
	for p: String in POSES:
		match p:
			"idle": body.pose_override = RunnerPoses.idle()
			"run_a": body.pose_override = RunnerPoses.run(0.0, 1.1)
			"run_b": body.pose_override = RunnerPoses.run(0.25, 1.1)
			"run_c": body.pose_override = RunnerPoses.run(0.5, 1.1)
			"lunge": body.pose_override = host_body.lunge(0.1)
			"fall": body.pose_override = RunnerPoses.fall()
			"land": body.pose_override = RunnerPoses.crouch()
		await _frames(4)
		var img := root.get_texture().get_image()
		var tile := img.get_region(Rect2i(400, 20, 480, 680))
		tile.resize(240, 340)
		tiles.append(tile)
	var sheet := Image.create(240 * tiles.size(), 340, false, tiles[0].get_format())
	for i in tiles.size():
		sheet.blit_rect(tiles[i], Rect2i(0, 0, 240, 340), Vector2i(i * 240, 0))
	sheet.save_png(out.path_join("host_pose_sheet.png"))
	print("saved host_pose_sheet  (order: %s)" % ", ".join(POSES))
	body.queue_free()
	cam.queue_free()


## Signal Out: Echo runs the first stretch (the route's own bot steps:
## jumps, slides), with a camera ahead of her looking back at the Host; then
## she stops and he gets her. With `clip`, saves every other frame for a
## video (30 fps).
func _chase(campaign: Script, clip: bool) -> void:
	var level := await _load_mission(campaign, "m12_signal_out")
	var p: Node3D = level.get_node("Player")
	var run: Node = level.find_child("MissionRun", true, false)
	var steps: Array = run.mission.bot
	var next := 0
	_hide_ui(level)
	var cam := _camera(level, p.global_position + Vector3(0, 2, -4), p.global_position, 62.0)
	var look := p.global_position
	var frames := 1260
	var n := 0
	var shots := {300: "host_chase_beam", 520: "host_chase_shortcut", 1150: "host_chase_lunge"}
	for i in frames:
		var f := InputFrame.make(Vector2(0, 1))
		var z := p.global_position.z
		while next < steps.size() and z < float(steps[next][0]):
			match String(steps[next][1]):
				"jump":
					f.jump_pressed = true
					f.jump_held = true
				"crouch":
					f.crouch_pressed = true
					f.crouch_held = true
			next += 1
		if int(p.get("state")) in [2, 3] and next > 0:  # crouch, slide: hold it a few meters
			f.crouch_held = z > float(steps[next - 1][0]) - 4.0
		# Near the end, she stops and he catches her.
		if i > 1080:
			f = InputFrame.new()
		p.scripted_input = f
		await physics_frame
		var pursuer: Node3D = run.pursuer
		var ahead := Vector3(0, 0, -1)
		var target: Vector3 = p.global_position + Vector3(0, 1.0, 0)
		if pursuer != null and pursuer.visible:
			target = target.lerp(pursuer.global_position + Vector3(0, 1.3, 0), 0.45)
		else:
			target += ahead * 8.0
		look = look.lerp(target, 0.15)
		var want: Vector3 = p.global_position + ahead * 3.6 + Vector3(2.2, 2.0, 0)
		cam.global_position = cam.global_position.lerp(want, 0.2)
		cam.look_at(look)
		await process_frame
		if clip and i % 2 == 0:
			_save("clip/f%04d" % n)
			n += 1
		if shots.has(i):
			_save(shots[i])
	print("chase: catches %d, falls %d, at %s" % [run.catches, run.falls, p.global_position])
	level.queue_free()
	await _frames(2)


func _load_mission(campaign: Script, id: String) -> Node3D:
	var all: Array = campaign.missions()
	for i in all.size():
		if all[i].id == id:
			campaign.current = i
	var level: Node3D = load("res://campaign/mission.tscn").instantiate()
	root.add_child(level)
	var p: Node = level.get_node("Player")
	p.use_device_input = false
	await _frames(8)
	return level


func _hide_ui(level: Node) -> void:
	for c in level.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(shot: String) -> void:
	var path := out.path_join(shot + ".png")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	root.get_texture().get_image().save_png(path)
	print("saved ", shot)
