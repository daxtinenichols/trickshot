extends SceneTree
## Renders Echo for review: Parker and Echo side by side, Echo's pose sheet,
## Echo waiting in the Dead Air studio (m11) and the chase cam on Echo in
## Signal Out (m12).
##   xvfb-run -a godot --path . --fixed-fps 60 -s res://art/tools/echo_shots.gd -- <out_dir> [lineup,poses,m11,m12]
## Scripts run with -s load before the autoloads, so nothing here is typed
## with classes that need them.

const BODY_PATH := "res://art/characters/runner/runner_body.gd"
const FIGURE_PATH := "res://art/characters/runner/runner_figure.gd"
const POSES := ["idle", "arms_crossed", "run_a", "run_b", "slide", "jump_rise", "tuck",
	"vault", "mantle_push", "wallrun", "climb", "kick"]

var out := "user://echo_shots"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	var parts := args[1].split(",") if args.size() > 1 else PackedStringArray(["lineup", "poses", "m11", "m12"])
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
	if "m11" in parts:
		await _m11(campaign)
	if "m12" in parts:
		await _m12(campaign)
	quit()


func _body(level: Node3D, runner: String, at: Vector3, yaw_deg: float) -> Node3D:
	var body: Node3D = load(BODY_PATH).new()
	body.runner = runner
	level.add_child(body)
	body.global_position = at
	body.rotation.y = deg_to_rad(yaw_deg)
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


## Parker and Echo in the same pose, front three-quarter and from behind.
func _lineup(level: Node3D, spot: Vector3) -> void:
	var figure: Script = load(FIGURE_PATH)
	var parker := _body(level, "parker", spot + Vector3(-0.6, 0, 0), -20.0)
	var echo := _body(level, "echo", spot + Vector3(0.6, 0, 0), -20.0)
	for pose: String in ["idle", "arms_crossed"]:
		var p: Dictionary = figure.pose(pose)
		parker.pose_override = p
		echo.pose_override = p
		var cam := _camera(level, spot + Vector3(-1.2, 1.25, 4.2), spot + Vector3(0, 0.9, 0), 38.0)
		await _frames(6)
		_save("echo_lineup_%s" % pose)
		cam.global_position = spot + Vector3(1.6, 1.4, -4.0)
		cam.look_at(spot + Vector3(0, 0.95, 0))
		await _frames(4)
		_save("echo_lineup_%s_back" % pose)
		cam.queue_free()
	# A close-up of Echo's head and shoulders.
	echo.pose_override = figure.pose("idle")
	var close := _camera(level, spot + Vector3(0.1, 1.6, 1.25), spot + Vector3(0.6, 1.5, 0), 34.0)
	await _frames(4)
	_save("echo_closeup")
	close.global_position = spot + Vector3(1.6, 1.62, -0.6)
	close.look_at(spot + Vector3(0.6, 1.48, 0.05))
	await _frames(4)
	_save("echo_closeup_side")
	close.queue_free()
	parker.queue_free()
	echo.queue_free()


func _pose_sheet(level: Node3D, spot: Vector3) -> void:
	var figure: Script = load(FIGURE_PATH)
	var body := _body(level, "echo", spot, -60.0)
	var cam := _camera(level, spot + Vector3(-1.6, 1.3, 3.6), spot + Vector3(0, 0.85, 0), 40.0)
	var tiles: Array[Image] = []
	for p: String in POSES:
		body.pose_override = _pose(figure, p)
		await _frames(4)
		var img := root.get_texture().get_image()
		var tile := img.get_region(Rect2i(400, 40, 480, 640))
		tile.resize(240, 320)
		tiles.append(tile)
	var sheet := Image.create(240 * 6, 320 * 2, false, tiles[0].get_format())
	for i in tiles.size():
		sheet.blit_rect(tiles[i], Rect2i(0, 0, 240, 320), Vector2i((i % 6) * 240, (i / 6) * 320))
	sheet.save_png(out.path_join("echo_pose_sheet.png"))
	print("saved echo_pose_sheet  (order: %s)" % ", ".join(POSES))
	body.queue_free()
	cam.queue_free()


func _pose(figure: Script, p: String) -> Dictionary:
	match p:
		"run_a": return RunnerPoses.run(0.0, 1.0)
		"run_b": return RunnerPoses.run(0.3, 1.0)
		"slide": return RunnerPoses.slide()
		"jump_rise": return RunnerPoses.jump_rise()
		"tuck": return RunnerPoses.tuck()
		"vault": return RunnerPoses.vault()
		"mantle_push": return RunnerPoses.mantle_push()
		"wallrun": return RunnerPoses.wallrun(0.2, 1.0)
		"climb": return RunnerPoses.climb(0.2)
		"kick": return RunnerPoses.kick()
	return figure.pose(p)


## Echo waiting in the studio, as Parker comes in, then close.
func _m11(campaign: Script) -> void:
	var level := await _load_mission(campaign, "m11_dead_air")
	var echo: Node3D = level.find_child("Figure_echo", true, false)
	if echo == null:
		push_error("echo_shots: no Echo figure in m11")
		level.queue_free()
		return
	print("m11 Echo at ", echo.global_position)
	var fwd := echo.global_basis.z  # she faces the way the player comes in
	var at := echo.global_position
	for shot: Array in [[14.0, "m11_studio_echo"], [4.0, "m11_echo_close"]]:
		var from: Vector3 = at + fwd * shot[0] + Vector3(0, 1.65, 0) + echo.global_basis.x * 0.8
		var cam := _camera(level, from, at + Vector3(0, 1.1, 0), 70.0 if shot[0] > 6.0 else 45.0)
		_hide_ui(level)
		await _frames(30)
		_save(shot[1])
		cam.queue_free()
	level.queue_free()
	await _frames(2)


## The chase cam on Echo at the top of Signal Out.
func _m12(campaign: Script) -> void:
	var level := await _load_mission(campaign, "l7_1_signal_out")
	var p: Node = level.get_node("Player")
	var body: Node = p.get_node_or_null("RunnerBody")
	print("m12 runner meta=", p.get_meta("runner", "?"), " body=", body.runner if body else "none")
	var chase: Camera3D = p.get_node_or_null("ChaseCamera")
	p.scripted_input = InputFrame.new()
	p.scripted_input.move = Vector2(0, 1)
	await _frames(50)
	if chase != null:
		chase.make_current()
	_hide_ui(level)
	await _frames(20)
	_save("m12_chase_echo")
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


func _save(shot: String) -> void:
	root.get_texture().get_image().save_png(out.path_join(shot + ".png"))
	print("saved ", shot)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
