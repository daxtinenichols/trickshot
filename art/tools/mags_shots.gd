extends SceneTree
## Renders Mags for review: Parker, Echo and Mags side by side, close-ups of
## her face, and her four camp poses (idle, arms crossed, sitting, holding
## the pistol out) as figures.
##   xvfb-run -a godot --path . --fixed-fps 60 -s res://art/tools/mags_shots.gd -- <out_dir> [lineup,close,poses,fp]
## Scripts run with -s load before the autoloads, so nothing here is typed
## with classes that need them.

const BODY_PATH := "res://art/characters/runner/runner_body.gd"
const FIGURE_PATH := "res://art/characters/runner/runner_figure.gd"
const POSES := ["idle", "arms_crossed", "sitting", "holding_out"]

var out := "user://mags_shots"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	var parts := args[1].split(",") if args.size() > 1 else PackedStringArray(["lineup", "close", "poses", "fp"])
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	var level: Node3D = load("res://levels/sandbox.tscn").instantiate()
	root.add_child(level)
	var player: Node = level.get_node("Player")
	player.use_device_input = false
	player.scripted_input = InputFrame.new()
	await _frames(5)
	level.go_to_zone(0)
	player.set_physics_process(false)
	var spot: Vector3 = player.global_position + Vector3(-6, 0, -6)
	for c in level.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false
	if "lineup" in parts:
		await _lineup(level, spot)
	if "close" in parts:
		await _close(level, spot)
	if "poses" in parts:
		await _poses(level, spot)
	if "fp" in parts:
		await _first_person(level, player, spot)
	quit()


func _body(level: Node3D, runner: String, at: Vector3, yaw_deg: float) -> Node3D:
	var body: Node3D = load(BODY_PATH).new()
	body.runner = runner
	level.add_child(body)
	body.global_position = at
	body.rotation.y = deg_to_rad(yaw_deg)
	return body


func _figure(level: Node3D, pose: String, at: Vector3, yaw_deg: float) -> Node3D:
	var fig: Node3D = load(FIGURE_PATH).new()
	fig.runner = "mags"
	fig.pose_name = pose
	level.add_child(fig)
	fig.global_position = at
	fig.rotation.y = deg_to_rad(yaw_deg)
	return fig


func _camera(level: Node3D, from: Vector3, at: Vector3, fov: float) -> Camera3D:
	var cam := Camera3D.new()
	cam.cull_mask &= ~4  # skip the first-person gun (Pistol.VIEW_LAYER)
	level.add_child(cam)
	cam.fov = fov
	cam.look_at_from_position(from, at)
	cam.add_child(root.get_node("ArtLook").make_outline_quad())
	cam.make_current()
	return cam


## Parker, Echo and Mags in the same pose, front three-quarter and behind.
func _lineup(level: Node3D, spot: Vector3) -> void:
	var figure: Script = load(FIGURE_PATH)
	var bodies: Array[Node3D] = []
	for i in 3:
		bodies.append(_body(level, ["parker", "echo", "mags"][i], spot + Vector3(-0.9 + 0.9 * i, 0, 0), -20.0))
	for pose: String in ["idle", "arms_crossed"]:
		for b in bodies:
			b.pose_override = figure.pose(pose)
		var cam := _camera(level, spot + Vector3(-1.2, 1.25, 4.6), spot + Vector3(0, 0.9, 0), 40.0)
		await _frames(6)
		_save("mags_lineup_%s" % pose)
		cam.global_position = spot + Vector3(1.6, 1.4, -4.4)
		cam.look_at(spot + Vector3(0, 0.95, 0))
		await _frames(4)
		_save("mags_lineup_%s_back" % pose)
		cam.queue_free()
	for b in bodies:
		b.queue_free()
	await _frames(2)


## Her head and shoulders: front, side and back (the braid). A plain body,
## without the figure's key light, so the colours read true.
func _close(level: Node3D, spot: Vector3) -> void:
	var fig := _body(level, "mags", spot, 0.0)
	fig.pose_override = load(FIGURE_PATH).pose("idle")
	var shots := [[Vector3(0.35, 1.62, 1.1), "mags_closeup"], [Vector3(1.15, 1.6, 0.15), "mags_closeup_side"],
		[Vector3(-0.5, 1.65, -1.0), "mags_closeup_back"]]
	for s: Array in shots:
		var cam := _camera(level, spot + s[0], spot + Vector3(0, 1.5, 0), 34.0)
		await _frames(30)
		_save(s[1])
		cam.queue_free()
	fig.queue_free()
	await _frames(2)


## Each camp pose as a figure (the head follows the camera), then all four.
func _poses(level: Node3D, spot: Vector3) -> void:
	for pose: String in POSES:
		var fig := _figure(level, pose, spot, 0.0)
		var cam := _camera(level, spot + Vector3(-1.7, 1.35 if pose != "sitting" else 1.0, 2.9), spot + Vector3(0, 0.85 if pose != "sitting" else 0.5, 0), 40.0)
		await _frames(30)
		_save("mags_pose_%s" % pose)
		if pose in ["sitting", "holding_out"]:
			cam.look_at_from_position(spot + Vector3(-2.6, 1.1, 0.4), spot + Vector3(0, 0.7, 0.2))
			await _frames(20)
			_save("mags_pose_%s_side" % pose)
		if pose == "holding_out":
			cam.look_at_from_position(spot + Vector3(-0.5, 1.5, 1.3), spot + Vector3(-0.1, 1.2, 0.3))
			await _frames(20)
			_save("mags_pose_holding_out_close")
		cam.queue_free()
		fig.queue_free()
		await _frames(2)
	var figs: Array[Node3D] = []
	for i in POSES.size():
		figs.append(_figure(level, POSES[i], spot + Vector3(-1.8 + 1.2 * i, 0, 0), 0.0))
	var cam := _camera(level, spot + Vector3(0, 1.4, 5.4), spot + Vector3(0, 0.8, 0), 44.0)
	await _frames(30)
	_save("mags_poses")
	cam.queue_free()
	for f in figs:
		f.queue_free()


## Through the first-person camera's eyes (its cull mask skips the player's
## own body layer), so a figure that only drew on that layer would vanish.
func _first_person(level: Node3D, player: Node, spot: Vector3) -> void:
	var fig := _figure(level, "holding_out", spot, 0.0)
	var cam := _camera(level, spot + Vector3(0.3, 1.65, 2.2), spot + Vector3(0, 1.2, 0), 70.0)
	cam.cull_mask = player.camera.cull_mask
	await _frames(30)
	_save("mags_first_person")
	cam.queue_free()
	fig.queue_free()


func _save(shot: String) -> void:
	root.get_texture().get_image().save_png(out.path_join(shot + ".png"))
	print("saved ", shot)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
