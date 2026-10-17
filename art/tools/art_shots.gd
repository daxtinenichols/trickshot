extends SceneTree
## Renders the art look for review: sandbox views with the look on and off,
## a contact sheet of the runner's key poses, and third-person action shots
## of the runner moving under scripted input.
##   xvfb-run godot --path . --fixed-fps 60 -s res://art/tools/art_shots.gd -- <out_dir> [views,poses,action]
## (--fixed-fps keeps scripted input in step with physics on slow renderers.)
## Add `--rendering-method gl_compatibility` where Vulkan isn't available.


const VIEWS := [
	# [zone index, position offset, yaw, pitch, name]
	[0, Vector3(4, 2, 8), 0.3, -0.12, "run_track"],
	[3, Vector3(0, 2, -2), 0.0, -0.05, "wallrun"],
	[6, Vector3(14, 6, 2), 0.6, -0.1, "drop_tower"],
	[9, Vector3(0, 0, 0), 0.0, -0.03, "shooting_range"],
]

const POSES := ["idle", "run_a", "run_b", "crouch", "slide", "jump_rise", "fall", "tuck",
	"vault", "mantle_hang", "mantle_push", "wallrun", "climb", "stun", "dive", "kick"]

var out := "user://art_shots"
var level: Node3D
var player  # untyped: Player needs autoloads, which load after this script compiles


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	var parts := args[1].split(",") if args.size() > 1 else PackedStringArray(["views", "poses", "action"])
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	level = load("res://levels/sandbox.tscn").instantiate()
	root.add_child(level)
	player = level.get_node("Player")
	player.use_device_input = false
	player.scripted_input = InputFrame.new()
	await _frames(5)
	if "views" in parts:
		await _views()
	if "poses" in parts:
		await _pose_sheet()
	if "action" in parts:
		await _action()
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	print("saved ", name)


func _views() -> void:
	var look: Node = root.get_node("ArtLook")
	for on: bool in [false, true]:
		look.set_enabled(on)
		await _frames(3)
		for v: Array in VIEWS:
			level.go_to_zone(v[0])
			player.global_position += v[1]
			player.set_physics_process(false)
			player.set_view(v[2], v[3])
			await _frames(12)
			_save("%s_%s" % [v[4], "art" if on else "graybox"])
			player.set_physics_process(true)


func _pose_sheet() -> void:
	# A posed runner on the run track, seen from a 3/4 front view.
	level.go_to_zone(0)
	player.set_physics_process(false)
	var spot: Vector3 = player.global_position + Vector3(-6, 0, -6)
	var body: Node3D = load("res://art/characters/runner/runner_body.gd").new()
	level.add_child(body)
	body.top_level = true
	body.global_position = spot
	body.rotation.y = deg_to_rad(-60.0)
	var cam := Camera3D.new()
	cam.cull_mask &= ~4  # skip the first-person gun (Pistol.VIEW_LAYER)
	level.add_child(cam)
	cam.fov = 40.0
	cam.global_position = spot + Vector3(-1.6, 1.3, 3.6)
	cam.look_at(spot + Vector3(0, 0.85, 0))
	cam.add_child(root.get_node("ArtLook").make_outline_quad())
	cam.make_current()
	var tiles: Array[Image] = []
	for p: String in POSES:
		body.pose_override = _pose(p)
		await _frames(4)
		var img := root.get_texture().get_image()
		img.crop(1280, 720)
		var tile := img.get_region(Rect2i(400, 40, 480, 640))
		tile.resize(240, 320)
		_label_tile(tile)
		tiles.append(tile)
	var sheet := Image.create(240 * 8, 320 * 2, false, tiles[0].get_format())
	for i in tiles.size():
		sheet.blit_rect(tiles[i], Rect2i(0, 0, 240, 320), Vector2i((i % 8) * 240, (i / 8) * 320))
	sheet.save_png(out.path_join("pose_sheet.png"))
	print("saved pose_sheet  (order: %s)" % ", ".join(POSES))
	body.queue_free()
	cam.queue_free()
	player.camera.make_current()
	player.set_physics_process(true)


func _label_tile(_tile: Image) -> void:
	pass


func _pose(p: String) -> Dictionary:
	match p:
		"idle": return RunnerPoses.idle()
		"run_a": return RunnerPoses.run(0.0, 1.0)
		"run_b": return RunnerPoses.run(0.3, 1.0)
		"crouch": return RunnerPoses.crouch()
		"slide": return RunnerPoses.slide()
		"jump_rise": return RunnerPoses.jump_rise()
		"fall": return RunnerPoses.fall()
		"tuck": return RunnerPoses.tuck()
		"vault": return RunnerPoses.vault()
		"mantle_hang": return RunnerPoses.mantle_hang()
		"mantle_push": return RunnerPoses.mantle_push()
		"wallrun": return RunnerPoses.wallrun(0.2, 1.0)
		"climb": return RunnerPoses.climb(0.2)
		"stun": return RunnerPoses.stun()
		"dive": return RunnerPoses.dive()
		"kick": return RunnerPoses.kick()
	return {}


## Short movement scenarios under scripted input, each saved as a filmstrip
## of side-on frames (left to right in time), plus one chase-camera frame.
const SCENARIOS := [
	# [name, zone, [[frames, {inputs}], ...], capture every n frames, first
	# captured frame]. "until_z" ends a step early once the player passes z.
	["run_jump", 0, [[70, {}], [1, {"jump": true}], [50, {}]], 8, 0],
	["slide", 0, [[80, {}], [40, {"crouch": true}], [20, {}]], 4, 72],
	["vault", 1, [[200, {"until_z": -8.2}], [1, {"jump": true}], [40, {}]], 3, -1],
]


func _action() -> void:
	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.cull_mask = 0xFFFFF & ~(1 << 10) & ~4
	level.add_child(cam)
	cam.add_child(root.get_node("ArtLook").make_outline_quad())
	var f: InputFrame = player.scripted_input
	for sc: Array in SCENARIOS:
		level.go_to_zone(sc[1])
		await physics_frame
		cam.make_current()
		var frames: Array[Image] = []
		var tick := 0
		var first: int = sc[4]
		for step: Array in sc[2]:
			if first < 0 and step[1].get("jump", false):
				first = tick - 8  # frame the moments around the jump
			for i in step[0]:
				if step[1].has("until_z") and player.global_position.z < step[1]["until_z"]:
					break
				# physics_frame fires just before the player's tick, so inputs
				# set right after it are the ones this tick uses.
				await physics_frame
				f.move = Vector2(0, 1)
				f.jump_pressed = step[1].get("jump", false) and i == 0
				f.jump_held = step[1].get("jump", false)
				f.crouch_pressed = step[1].get("crouch", false) and i == 0
				f.crouch_held = step[1].get("crouch", false)
				tick += 1
				if first >= 0 and tick >= first and (tick - first) % sc[3] == 0 and frames.size() < 16:
					await process_frame
					# Presses last one tick; the frames below also tick physics.
					f.jump_pressed = false
					f.crouch_pressed = false
					var at: Vector3 = player.global_position
					cam.global_position = at + Vector3(4.2, 1.0, 0.6)
					cam.look_at(at + Vector3(0, 0.9, 0))
					await process_frame
					await process_frame
					var img := root.get_texture().get_image()
					frames.append(img.get_region(Rect2i(440, 110, 400, 500)))
		var strip := Image.create(200 * 8, 250 * 2, false, frames[0].get_format())
		for i in mini(frames.size(), 16):
			var t := frames[i]
			t.resize(200, 250)
			strip.blit_rect(t, Rect2i(0, 0, 200, 250), Vector2i((i % 8) * 200, (i / 8) * 250))
		strip.save_png(out.path_join("strip_%s.png" % sc[0]))
		print("saved strip_", sc[0])
	f.move = Vector2.ZERO
	cam.queue_free()
