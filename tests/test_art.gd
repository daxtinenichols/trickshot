extends TestCase
## The art look: the runner rig loads, its animation follows the player
## without ever changing what the player does, and the world restyle can be
## switched on and off cleanly.

const SANDBOX := preload("res://levels/sandbox.tscn")
const HUMANOID_BONES := ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head",
	"LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes",
	"RightUpperLeg", "RightLowerLeg", "RightFoot", "RightToes"]

var level: Node3D
var player: Player


func before_each() -> void:
	level = SANDBOX.instantiate()
	tree.root.add_child(level)
	player = level.get_node("Player")
	player.use_device_input = false
	player.scripted_input = InputFrame.new()
	await tree.physics_frame


func after_each() -> void:
	level.queue_free()
	await tree.process_frame


func _look() -> Node:
	return tree.root.get_node("ArtLook")


## Sprint, jump, land, slide and run on: a little of everything, in a fresh
## copy of the sandbox each time.
func _run_course(record: Array, with_art: bool) -> void:
	level.queue_free()
	await tree.process_frame
	await before_each()
	if with_art:
		_look().attach_to_player(player)
		check(player.has_node("RunnerBody"), "runner body attached")
	level.go_to_zone(0)
	await tree.physics_frame
	for t in 200:
		var f := InputFrame.make(Vector2(0.0, 1.0))
		f.jump_pressed = t == 60
		f.jump_held = t >= 60 and t < 70
		f.crouch_pressed = t == 130
		f.crouch_held = t >= 130 and t < 165
		player.scripted_input = f
		await tree.physics_frame
		record.append([player.global_position, player.velocity, player.state])


func test_runner_rig_has_humanoid_bones() -> void:
	var body: Node3D = RunnerBody.new()
	level.add_child(body)
	for b: String in HUMANOID_BONES:
		check(body.skeleton.find_bone(b) >= 0, "bone %s exists" % b)
	body.queue_free()


func test_animation_never_changes_gameplay() -> void:
	var plain: Array = []
	await _run_course(plain, false)
	var styled: Array = []
	await _run_course(styled, true)
	check(plain.size() == styled.size(), "same length")
	var same := true
	for i in plain.size():
		if plain[i][0] != styled[i][0] or plain[i][1] != styled[i][1] or plain[i][2] != styled[i][2]:
			same = false
			failures.append("%s: tick %d differs: %s vs %s" % [current_test, i, plain[i], styled[i]])
			break
	check(same, "identical simulation with and without the art look")


func test_body_follows_states_and_stays_grounded() -> void:
	_look().attach_to_player(player)
	var body: Node3D = player.get_node("RunnerBody")
	var states := {}
	var worst_ground := 0.0
	level.go_to_zone(0)
	await tree.physics_frame
	for t in 200:
		var f := InputFrame.make(Vector2(0.0, 1.0))
		f.jump_pressed = t == 60
		f.crouch_pressed = t == 130
		f.crouch_held = t >= 130 and t < 165
		player.scripted_input = f
		await tree.physics_frame
		await tree.process_frame
		states[player.state] = true
		for b: String in HUMANOID_BONES:
			var p: Vector3 = body.bone_world_position(b)
			if not p.is_finite():
				failures.append("%s: bone %s not finite at tick %d" % [current_test, b, t])
				return
		# Running on flat ground: the lowest foot touches the floor.
		if player.state == Player.State.GROUND and player.state_time > 0.4:
			var lowest := INF
			for b: String in ["LeftToes", "RightToes", "LeftFoot", "RightFoot"]:
				lowest = minf(lowest, body.bone_world_position(b).y - RunnerBody.CONTACTS[b])
			worst_ground = maxf(worst_ground, absf(lowest - player.global_position.y))
	for s: Player.State in [Player.State.GROUND, Player.State.AIR, Player.State.SLIDE]:
		check(states.has(s), "went through %s" % Player.State.keys()[s])
	check_between(worst_ground, 0.0, 0.05, "feet stay on the floor while running (m)")
	check(body.weight("slide") < 0.05, "slide pose eased out after the slide")


func test_restyle_switches_on_and_off() -> void:
	var look := _look()
	look._apply_all(level)
	check(_graybox_count() == 0, "graybox materials replaced by toon ones")
	look.set_enabled(false)
	check(_graybox_count() > 0, "graybox materials restored when the look is off")
	look.set_enabled(true)
	check(_graybox_count() == 0, "and replaced again when back on")


func _graybox_count() -> int:
	var n := 0
	for g: GeometryInstance3D in level.find_children("*", "GeometryInstance3D", true, false):
		var m := g.material_override as ShaderMaterial
		if m and m.shader == preload("res://levels/graybox.gdshader"):
			n += 1
	return n


func test_motion_trails_follow_the_runner() -> void:
	# Body is built where the player spawned; the trails must still be drawn
	# in world space wherever the runner goes (they used to carry the spawn
	# offset with them).
	var body: RunnerBody = ArtLook.ensure_body(player)
	level.go_to_zone(3)
	await tree.physics_frame
	player.set_view(0.7)
	player.scripted_input = TestWorld.forward_input()
	for i in 150:
		await tree.physics_frame
	check(player.velocity.length() > player.tuning.run_speed, "running fast enough for trails (%.1f)" % player.velocity.length())
	var inst: MeshInstance3D = body.trails._instance
	var aabb: AABB = inst.global_transform * inst.mesh.get_aabb()
	check(aabb.size.length() > 0.1, "trails are drawn")
	for b: String in ["LeftFoot", "RightHand"]:
		var p := body.bone_world_position(b)
		check(aabb.grow(0.3).has_point(p), "%s trail is at the body (%s not in %s)" % [b, p, aabb])


func test_chase_camera_looks_down_on_the_runner() -> void:
	ArtLook.ensure_body(player)
	var cam: Camera3D = preload("res://art/look/chase_camera.gd").new()
	level.add_child(cam)
	cam.setup(player)
	cam.set_active(true)
	await tree.process_frame
	var rel := player.global_basis.inverse() * (cam.global_position - player.global_position)
	check(rel.y > 2.5 and rel.z > 3.5, "up and behind (%s)" % rel)
	var down := rad_to_deg(asin(-(-cam.global_basis.z).y))
	check_between(down, 18.0, 35.0, "looks down on the runner (%.0f degrees)" % down)
	cam.set_active(false)
	cam.queue_free()
