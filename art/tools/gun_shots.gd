extends SceneTree
## Renders the gun for review: first person at rest, mid-shot, just after
## (tracer, smoke, casing), aimed in, a bullet hole close-up, and the runner
## holding it in third person.
##   xvfb-run godot --path . --fixed-fps 60 -s res://art/tools/gun_shots.gd -- <out_dir>

var out := "user://gun_shots"
var level: Node3D
var player  # untyped: autoload-dependent classes must not compile before autoloads exist
var gun


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	level = load("res://levels/sandbox.tscn").instantiate()
	root.add_child(level)
	player = level.get_node("Player")
	player.use_device_input = false
	player.scripted_input = InputFrame.new()
	gun = player.weapon
	await _frames(5)
	root.get_node("ArtLook").attach_to_player(player)
	level.go_to_zone(9)
	await _frames(20)
	player.set_view(0.0, -0.02)
	await _frames(10)
	_save("fp_idle")
	gun.trigger_pressed = true
	await _frames(2)
	_save("fp_fire")
	await _frames(5)
	_save("fp_after")
	for i in 3:
		await _frames(9)
		gun.trigger_pressed = true
	await _frames(2)
	_save("fp_rapid")
	gun.aim_held = true
	await _frames(25)
	_save("fp_ads")
	gun.trigger_pressed = true
	await _frames(2)
	_save("fp_ads_fire")
	gun.aim_held = false
	# Bullet holes on the range's side wall, seen up close.
	player.set_view(0.75, -0.02)
	await _frames(5)
	for i in 4:
		gun.trigger_pressed = true
		await _frames(10)
		player.set_view(0.75 + 0.01 * (i + 1), -0.02 + 0.01 * i)
	await _frames(4)
	var look = player.get_node("GunLook")
	if not look._holes.is_empty():
		var hole: Decal = look._holes[0]
		var close := Camera3D.new()
		root.add_child(close)
		close.cull_mask &= ~4
		close.look_at_from_position(hole.global_position + hole.global_basis.y * 0.9 + Vector3(0, 0.2, 0), hole.global_position)
		close.current = true
		await _frames(3)
		_save("wall_holes")
		close.queue_free()
		player.camera.current = true
	# Third person: a camera beside the runner's gun hand.
	level.go_to_zone(9)
	await _frames(20)
	player.set_view(0.0, 0.0)
	await _frames(10)
	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.cull_mask &= ~4  # Pistol.VIEW_LAYER: the first-person gun
	root.add_child(cam)
	var p: Vector3 = player.global_position
	cam.look_at_from_position(p + Vector3(1.4, 1.5, -1.6), p + Vector3(0.1, 1.15, 0.0))
	cam.current = true
	await _frames(5)
	_save("tp_hold")
	gun.aim_held = true
	await _frames(25)
	_save("tp_aim")
	gun.trigger_pressed = true
	await _frames(2)
	_save("tp_fire")
	cam.look_at_from_position(p + Vector3(0.55, 1.45, -0.7), p + Vector3(0.15, 1.35, -0.3))
	await _frames(20)
	_save("tp_closeup")
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	print("saved ", name)
