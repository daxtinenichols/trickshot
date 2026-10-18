extends TestCase
## The runner body (built by the art look): building, render layers, poses
## per state, the kick overlay and aiming. Presentation only.

const SANDBOX := preload("res://levels/sandbox.tscn")

var _w: TestWorld
var _rig: RunnerBody


func _make() -> Player:
	_w = TestWorld.new()
	tree.root.add_child(_w)
	_w.add_floor()
	var p := _w.spawn_player(Vector3(0, 0.05, 0))
	_rig = ArtLook.ensure_body(p)
	return p


func after_each() -> void:
	if is_instance_valid(_w):
		_w.queue_free()
	_w = null
	_rig = null
	await tree.process_frame


## Holds the player in a state (physics off) and lets the body pose a while.
func _hold(p: Player, s: Player.State, frames := 40) -> void:
	p.set_physics_process(false)
	p.state = s
	for i in frames:
		await tree.process_frame


func _root() -> Basis:
	return _rig.model.transform.basis


func _hips_height() -> float:
	return _rig.to_local(_rig.bone_world_position("Hips")).y


func _bone(name: String) -> Quaternion:
	var sk := _rig.skeleton
	return sk.get_bone_pose_rotation(sk.find_bone(name))


func test_body_builds_and_attaches() -> void:
	var p := _make()
	var rig := _rig
	check(rig != null and rig.get_parent() == p, "body is a child of the player")
	check(p.get_node("RunnerBody") == rig, "one body, shared with the art look")
	await _hold(p, Player.State.GROUND, 10)
	var head := rig.bone_world_position("Head").y - p.global_position.y
	check_between(head, 1.45, 1.7, "head joint at standing height")


func test_runner_meta_picks_the_model() -> void:
	_w = TestWorld.new()
	tree.root.add_child(_w)
	_w.add_floor()
	var p := _w.spawn_player(Vector3(0, 0.05, 0))
	p.set_meta("runner", "echo")
	_rig = ArtLook.ensure_body(p)
	check(_rig.runner == "echo", "the runner meta picks Echo")
	check(String(_rig.model.scene_file_path).ends_with("echo.glb"), "Echo's model is shown (%s)" % _rig.model.scene_file_path)
	for b: String in ["Hips", "Head", "LeftHand", "RightFoot", "LeftToes"]:
		check(_rig.skeleton.find_bone(b) >= 0, "Echo has bone %s" % b)
	await _hold(p, Player.State.SLIDE, 20)
	var hips := _hips_height()
	check_between(hips, 0.05, 0.6, "Echo slides low on Parker's slide pose (hips %.2f)" % hips)
	# Swapping back rebuilds the skeleton and keeps the layers.
	_rig.set_runner("parker")
	check(String(_rig.model.scene_file_path).ends_with("runner.glb"), "back to Parker's model")
	for m: MeshInstance3D in _rig.model.find_children("*", "MeshInstance3D", true, false):
		check(m.layers == RunnerBody.LAYER, "swapped model on layer 2")
	_rig.set_runner("nobody")
	check(String(_rig.model.scene_file_path).ends_with("runner.glb"), "unknown runner falls back to Parker")


func _vertex_count(model: Node) -> int:
	var n := 0
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			n += mi.mesh.surface_get_array_len(i)
	return n


## Echo is her own model, not Parker's with new colours, and she still shows
## when the editor hasn't imported echo.glb yet (read straight from the file).
func test_echo_model_is_her_own_and_loads_unimported() -> void:
	var body: Node3D = RunnerBody.new()
	var parker: Node3D = RunnerBody.MODEL.instantiate()
	var parker_verts := _vertex_count(parker)
	parker.free()
	var echo: Node3D = load(RunnerBody.MODELS["echo"]).instantiate()
	check(_vertex_count(echo) > parker_verts * 1.4, "Echo has her own hair, face and gear (%d vs %d verts)" % [_vertex_count(echo), parker_verts])
	var raw: Node3D = body._load_gltf_file(RunnerBody.MODELS["echo"])
	check(raw != null, "echo.glb loads straight from the file")
	if raw != null:
		var skel: Skeleton3D = raw.find_children("*", "Skeleton3D", true, false)[0]
		check(skel.get_bone_count() == echo.find_children("*", "Skeleton3D", true, false)[0].get_bone_count(), "same skeleton from the file")
		check(_vertex_count(raw) > parker_verts * 1.4, "the file copy is Echo, not Parker")
		raw.free()
	check(body._load_gltf_file("res://art/characters/runner/nobody.glb") == null, "a missing file gives no model")
	echo.free()
	body.free()


func test_figure_stands_in_the_level() -> void:
	_w = TestWorld.new()
	tree.root.add_child(_w)
	var fig: Node3D = load("res://art/characters/runner/runner_figure.gd").new()
	fig.runner = "echo"
	_w.add_child(fig)
	fig.global_position = Vector3(3, 0, -2)
	for i in 4:
		await tree.process_frame
	var body: Node3D = fig.get_node("RunnerBody")
	check(body.runner == "echo", "figure shows Echo")
	check(body.global_position.distance_to(fig.global_position) < 0.01, "body stands where the figure is")
	var feet: float = body.bone_world_position("LeftFoot").y
	check_between(feet, -0.05, 0.25, "figure's feet on the floor (%.2f)" % feet)
	check(fig.get_node_or_null("Blocker") != null, "figure blocks the player")


## Mags (the Line's dispatcher, a figure in the camp) is her own model on
## the shared skeleton, and loads straight from the file before an import.
func test_mags_model_is_her_own_and_loads_unimported() -> void:
	var body: Node3D = RunnerBody.new()
	var parker: Node3D = RunnerBody.MODEL.instantiate()
	var parker_skel: Skeleton3D = parker.find_children("*", "Skeleton3D", true, false)[0]
	var parker_verts := _vertex_count(parker)
	var raw: Node3D = body._load_gltf_file(RunnerBody.MODELS["mags"])
	check(raw != null, "mags.glb loads straight from the file")
	if raw != null:
		var skel: Skeleton3D = raw.find_children("*", "Skeleton3D", true, false)[0]
		check(skel.get_bone_count() == parker_skel.get_bone_count(), "Mags shares Parker's skeleton")
		check(skel.find_bone("RightHand") >= 0 and skel.find_bone("Head") >= 0, "humanoid bone names")
		check(_vertex_count(raw) > parker_verts * 1.4, "Mags has her own hair, glasses, headset and vest (%d vs %d verts)" % [_vertex_count(raw), parker_verts])
		raw.free()
	parker.free()
	body.free()


## Mags's camp poses: sitting puts her on the floor, holding_out puts her
## right hand out in front at chest height with the pistol on it.
func test_mags_figure_poses() -> void:
	_w = TestWorld.new()
	tree.root.add_child(_w)
	var figure: Script = load("res://art/characters/runner/runner_figure.gd")
	var figs := {}
	var x := 0.0
	for pose: String in ["idle", "arms_crossed", "sitting", "holding_out"]:
		var fig: Node3D = figure.new()
		fig.runner = "mags"
		fig.pose_name = pose
		_w.add_child(fig)
		fig.global_position = Vector3(x, 0, 0)
		figs[pose] = fig
		x += 2.0
	for i in 4:
		await tree.process_frame
	for pose: String in figs:
		var body: Node3D = figs[pose].get_node("RunnerBody")
		check(body.runner == "mags", "%s figure shows Mags" % pose)
		var feet: float = body.bone_world_position("LeftFoot").y
		check_between(feet, -0.05, 0.3, "%s: feet on the floor (%.2f)" % [pose, feet])
	var stand: Node3D = figs["idle"].get_node("RunnerBody")
	var sit: Node3D = figs["sitting"].get_node("RunnerBody")
	var stand_hips: float = stand.bone_world_position("Hips").y
	var sit_hips: float = sit.bone_world_position("Hips").y
	check(sit_hips < stand_hips - 0.55, "sitting puts her hips near the floor (%.2f vs %.2f standing)" % [sit_hips, stand_hips])
	check(sit_hips > 0.05, "but not through it (%.2f)" % sit_hips)
	var hold: Node3D = figs["holding_out"]
	var hold_body: Node3D = hold.get_node("RunnerBody")
	var hand: Vector3 = hold.global_transform.affine_inverse() * hold_body.bone_world_position("RightHand")
	check(hand.z > 0.3, "the hand is held out in front of her (%.2f m)" % hand.z)
	check_between(hand.y, 1.0, 1.45, "at chest height (%.2f)" % hand.y)
	check(hold.held_model != null, "holding_out shows the pistol")
	if hold.held_model != null:
		var gun: Vector3 = hold.held_model.global_position
		check(gun.distance_to(hold_body.bone_world_position("RightHand")) < 0.2, "the pistol is on her hand")
	check(figs["idle"].held_model == null, "idle holds nothing")
	# The first-person camera skips the player's own body layer; figures
	# are other people and must still show.
	var fp_mask := 0xFFFFF & ~RunnerBody.LAYER
	for mi: MeshInstance3D in hold.find_children("*", "MeshInstance3D", true, false):
		check(mi.layers & fp_mask != 0, "%s shows in first person" % mi.name)


func test_layers_and_cull_masks() -> void:
	var p := _make()
	var meshes := _rig.find_children("*", "MeshInstance3D", true, false)
	check(not meshes.is_empty(), "body has meshes")
	for m: MeshInstance3D in meshes:
		check(m.layers == RunnerBody.LAYER, "%s on layer 2 only (%d)" % [m.name, m.layers])
	check(p.camera.cull_mask & RunnerBody.LAYER == 0, "first-person camera skips the body")
	check(p.camera.cull_mask & Pistol.VIEW_LAYER != 0, "first-person camera still sees the gun")
	check(p.camera.cull_mask & 1 != 0, "first-person camera still sees the world")


func test_roll_turns_body_over() -> void:
	var p := _make()
	await _hold(p, Player.State.GROUND, 20)
	check(_root().get_rotation_quaternion().get_angle() < 0.05, "upright on the ground")
	p.state = Player.State.ROLL
	p.state_time = p.tuning.roll_time * 0.5
	for i in 30:
		await tree.process_frame
	check(_root().get_rotation_quaternion().get_angle() > 2.5, "upside down halfway through the roll (%.2f)" % _root().get_rotation_quaternion().get_angle())


func test_slide_lowers_hips() -> void:
	var p := _make()
	await _hold(p, Player.State.GROUND, 30)
	var standing := _hips_height()
	await _hold(p, Player.State.SLIDE, 30)
	var sliding := _hips_height()
	check_between(standing, 0.85, 1.0, "standing hips")
	check(sliding < standing - 0.35, "slide drops the hips (%.2f -> %.2f)" % [standing, sliding])
	await _hold(p, Player.State.CROUCH, 30)
	check_between(_hips_height(), sliding, standing - 0.15, "crouch is between")


func test_flips_and_side_flips_turn_the_body() -> void:
	var p := _make()
	p.set_physics_process(false)
	p.state = Player.State.AIR
	p.velocity = Vector3.ZERO
	p._air_pitch = 2.0
	for i in 40:
		await tree.process_frame
	# Model space: +Z is the body's front. A backflip tips the head back.
	check_near(_root().get_rotation_quaternion().get_angle(), 2.0, 0.08, "turned by the air pitch")
	check(_root().y.z < -0.5, "backflip tips the head backwards (%s)" % _root().y)
	check(_rig.weight("tuck") > 0.0 or _bone("LeftLowerLeg").get_angle() > 0.5, "tucks while flipping")
	p._air_pitch = 0.0
	p._air_roll = 1.0
	for i in 40:
		await tree.process_frame
	# The body's right is model -X.
	check(_root().y.x < -0.5, "a right side flip tips the head right (%s)" % _root().y)


func test_wallrun_puts_feet_on_the_wall() -> void:
	var p := _make()
	p.set_physics_process(false)
	p.state = Player.State.WALLRUN
	p.velocity = Vector3(0, 0, -9)
	# Facing -Z with the wall on the right: its normal points left (-X).
	p._wall_normal = Vector3(-1, 0, 0)
	for i in 40:
		await tree.process_frame
	# Head leans away from the wall (body's left, model +X), feet toward it.
	check(_root().y.x > 0.3, "leans away from a wall on the right (%s)" % _root().y)
	p._wall_normal = Vector3(1, 0, 0)
	for i in 40:
		await tree.process_frame
	check(_root().y.x < -0.3, "and the other way for a wall on the left (%s)" % _root().y)


func test_running_moves_legs_and_blends() -> void:
	var p := _make()
	await _w.step(90, TestWorld.forward_input())
	check(p.state == Player.State.GROUND and p.horizontal_speed() > 6.0, "running")
	var lo := 9.0
	var hi := -9.0
	var max_step := 0.0
	var prev := _bone("LeftUpperLeg")
	for i in 60:
		await _w.step(1, TestWorld.forward_input())
		var x := _bone("LeftUpperLeg").get_euler().x
		lo = minf(lo, x)
		hi = maxf(hi, x)
		max_step = maxf(max_step, prev.angle_to(_bone("LeftUpperLeg")))
		prev = _bone("LeftUpperLeg")
	check(hi - lo > 0.8, "legs swing while running (%.2f)" % (hi - lo))
	check(max_step < 0.6, "no snapping while running (%.2f)" % max_step)
	# Change state abruptly: the body must ease, never jump.
	var before := _root().get_rotation_quaternion()
	p.set_physics_process(false)
	p.state = Player.State.AIR
	p._air_roll = 1.5  # partway round a side flip
	await tree.process_frame
	await tree.process_frame
	var jump := before.angle_to(_root().get_rotation_quaternion())
	check(jump < 1.2 and jump > 0.02, "eases into a new state (%.2f rad in two frames)" % jump)


func test_kick_overlay_plays_and_ends() -> void:
	var p := _make()
	await _hold(p, Player.State.GROUND, 20)
	var rest := _bone("LeftUpperLeg")
	p.trick.emit(&"kick", {})
	var peak := 0.0
	for i in 40:
		await tree.process_frame
		peak = maxf(peak, rest.angle_to(_bone("LeftUpperLeg")))
	check(peak > 0.8, "leg kicks up (%.2f rad)" % peak)
	check(_rig.weight("kick") < 0.05, "kick finishes")


func test_aim_raises_gun_arm() -> void:
	var p := _make()
	await _hold(p, Player.State.GROUND, 30)
	(p.weapon as Pistol).aim_held = true
	p.pitch = 0.0
	for i in 40:
		await tree.process_frame
	var rig := _rig
	var dir := (rig.bone_world_position("RightHand") - rig.bone_world_position("RightLowerArm")).normalized()
	check(p.aim_zoom > 0.99, "aimed in")
	check(dir.dot(p.forward()) > 0.85, "gun arm points along the view when aiming (%s)" % dir)
	(p.weapon as Pistol).aim_held = false


func test_follows_the_player_on_ramps_and_loops() -> void:
	var p := _make()
	p.set_physics_process(false)
	p.state = Player.State.SURFACE
	# Upside down at the top of a loop.
	p.global_basis = Basis(Vector3.RIGHT, PI)
	p.velocity = p.global_basis * Vector3(0, 0, -9)
	for i in 30:
		await tree.process_frame
	check(_rig.global_basis.y.dot(p.global_basis.y) > 0.95, "body up matches the player's up (%s)" % _rig.global_basis.y)
	check(_rig.weight("run") > 0.8, "runs on the surface")


func test_every_state_poses_without_errors() -> void:
	var p := _make()
	p.set_physics_process(false)
	p.aim_zoom = 0.5
	p.lean = 0.7
	p.velocity = Vector3(0, 2, -9)
	p._wall_normal = Vector3(1, 0, 0)
	var sk := _rig.skeleton
	for s: int in Player.State.values():
		p.state = s as Player.State
		p.state_time = 0.1
		for i in 6:
			await tree.process_frame
		for b in sk.get_bone_count():
			check(sk.get_bone_pose_rotation(b).is_normalized(), "%s: %s stays valid" % [Player.State.keys()[s], sk.get_bone_name(b)])
	# A state the body doesn't know (added later) falls back to run/fall.
	p.state = 99 as Player.State
	for i in 6:
		await tree.process_frame
	check(_root().get_rotation_quaternion().is_normalized(), "unknown state is fine")


func test_sandbox_has_the_body_and_survives_pause() -> void:
	var level: Node3D = SANDBOX.instantiate()
	tree.root.add_child(level)
	var player: Player = level.get_node("Player")
	player.use_device_input = false
	await tree.process_frame
	# The art look attaches the body in a real game (not headless).
	ArtLook.attach_to_player(player)
	check(player.get_node_or_null("RunnerBody") != null, "sandbox has the runner body")
	check(player.camera.cull_mask & RunnerBody.LAYER == 0, "sandbox first-person view hides the body")
	level.menu.open(0)
	for i in 5:
		await tree.process_frame
	check(tree.paused, "paused")
	level.menu.close()
	await tree.process_frame
	level.queue_free()
	await tree.process_frame
