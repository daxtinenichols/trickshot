extends TestCase
## Third-person body rig and the corner camera: building, render layers,
## poses per state, the kick overlay and the F5 toggle. Presentation only.

const SANDBOX := preload("res://levels/sandbox.tscn")

var _w: TestWorld
var _cam: CornerCam


func _make() -> Player:
	_w = TestWorld.new()
	tree.root.add_child(_w)
	_w.add_floor()
	var p := _w.spawn_player(Vector3(0, 0.05, 0))
	_cam = CornerCam.new()
	_w.add_child(_cam)
	_cam.setup(p)
	return p


func after_each() -> void:
	if is_instance_valid(_w):
		_w.queue_free()
	_w = null
	_cam = null
	await tree.process_frame


## Holds the player in a state (physics off) and lets the rig pose for a while.
func _hold(p: Player, s: Player.State, frames := 40) -> void:
	p.set_physics_process(false)
	p.state = s
	for i in frames:
		await tree.process_frame


func _pelvis_height(rig: BodyRig) -> float:
	return rig.to_local(rig.joint(&"pelvis").global_position).y


func test_rig_builds_and_attaches() -> void:
	var p := _make()
	var rig := _cam.rig
	check(rig != null and rig.get_parent() == p, "rig is a child of the player")
	check(rig.root_pivot != null, "has a root pivot")
	for j in BodyRig.JOINTS:
		check(rig.joint(j) != null, "joint %s exists" % j)
	check(rig.meshes().size() >= 20, "built from primitives (%d meshes)" % rig.meshes().size())
	check_near(rig.root_pivot.position.y, BodyRig.HIP_HEIGHT, 0.01, "root starts at the body's centre")
	# Head top is around 1.8 m above the feet.
	var top := 0.0
	for m in rig.meshes():
		var aabb := m.global_transform * m.get_aabb()
		top = maxf(top, aabb.end.y - p.global_position.y)
	check_between(top, 1.7, 1.9, "about 1.8 m tall")


func test_layers_and_cull_masks() -> void:
	var p := _make()
	for m in _cam.rig.meshes():
		check(m.layers == BodyRig.LAYER, "%s on layer 2 only (%d)" % [m.get_path(), m.layers])
	check(p.camera.cull_mask & BodyRig.LAYER == 0, "first-person camera skips the body")
	check(p.camera.cull_mask & Pistol.VIEW_LAYER != 0, "first-person camera still sees the gun")
	check(p.camera.cull_mask & 1 != 0, "first-person camera still sees the world")
	check(_cam.camera.cull_mask & BodyRig.LAYER != 0, "corner camera sees the body")
	check(_cam.camera.cull_mask & 1 != 0, "corner camera sees the world")
	check(_cam.camera.cull_mask & Pistol.VIEW_LAYER == 0, "corner camera skips the first-person gun")
	var gun_meshes := (p.weapon as Node).find_children("*", "MeshInstance3D", true, false)
	check(not gun_meshes.is_empty(), "pistol has meshes")
	for m: MeshInstance3D in gun_meshes:
		check(m.layers == Pistol.VIEW_LAYER, "pistol mesh on its own layer")
	check(_cam.viewport.world_3d == null and not _cam.viewport.own_world_3d, "corner view shares the main world")
	check(_cam.camera.get_viewport() == _cam.viewport and _cam.camera.current, "chase camera drives the corner view")


func test_roll_rotates_root() -> void:
	var p := _make()
	await _hold(p, Player.State.GROUND, 20)
	var rest := _cam.rig.root_pivot.quaternion.get_angle()
	check(rest < 0.05, "upright on the ground (%.2f)" % rest)
	p.set_physics_process(false)
	p.state = Player.State.ROLL
	p.state_time = p.tuning.roll_time * 0.5
	for i in 30:
		await tree.process_frame
	# Halfway through the roll the body is upside down (half a turn forward).
	var root := _cam.rig.root_pivot
	check(root.quaternion.get_angle() > 2.5, "rolled over (%.2f rad)" % root.quaternion.get_angle())
	check(root.position.y < 0.7, "tucked low (%.2f)" % root.position.y)


func test_slide_lowers_pelvis() -> void:
	var p := _make()
	await _hold(p, Player.State.GROUND, 30)
	var standing := _pelvis_height(_cam.rig)
	await _hold(p, Player.State.SLIDE, 30)
	var sliding := _pelvis_height(_cam.rig)
	check_between(standing, 0.85, 1.0, "standing hips")
	check(sliding < standing - 0.4, "slide drops the hips (%.2f -> %.2f)" % [standing, sliding])
	await _hold(p, Player.State.CROUCH, 30)
	check_between(_pelvis_height(_cam.rig), sliding, standing - 0.15, "crouch is between")


func test_air_flip_rotates_root_by_air_pitch() -> void:
	var p := _make()
	p.set_physics_process(false)
	p.state = Player.State.AIR
	p.velocity = Vector3.ZERO
	p._air_pitch = 2.0
	for i in 40:
		await tree.process_frame
	var root := _cam.rig.root_pivot
	var up := root.basis.y
	# +pitch is a backflip: head goes back (+Z), around local X.
	check_near(root.quaternion.get_angle(), 2.0, 0.05, "root turned by the air pitch")
	check(absf(root.quaternion.get_axis().x) > 0.99, "around the body's X axis")
	check(up.z > 0.5, "backflip tips the head backwards (%s)" % up)
	var knee := _cam.rig.joint(&"knee_l").quaternion.get_angle()
	check(knee > 1.5, "tucked mid-flip (knee %.2f)" % knee)
	# Side flip to the right tips the body to its right.
	p._air_pitch = 0.0
	p._air_roll = 1.0
	for i in 40:
		await tree.process_frame
	check(root.basis.y.x > 0.5, "right roll tips the head right (%s)" % root.basis.y)


func test_dive_is_horizontal() -> void:
	var p := _make()
	p.set_physics_process(false)
	p.state = Player.State.AIR
	p._diving = true
	for i in 40:
		await tree.process_frame
	var up := _cam.rig.root_pivot.basis.y
	check(up.y < 0.4 and up.z < -0.8, "head out in front (%s)" % up)


func test_wallrun_tilts_toward_wall() -> void:
	var p := _make()
	p.set_physics_process(false)
	p.state = Player.State.WALLRUN
	p.velocity = Vector3(0, 0, -9)
	# Facing -Z with the wall on the right: its normal points left (-X).
	p._wall_normal = Vector3(-1, 0, 0)
	for i in 40:
		await tree.process_frame
	check(_cam.rig.root_pivot.basis.y.x > 0.3, "leans right, toward the wall (%s)" % _cam.rig.root_pivot.basis.y)
	p._wall_normal = Vector3(1, 0, 0)
	for i in 40:
		await tree.process_frame
	check(_cam.rig.root_pivot.basis.y.x < -0.3, "leans left for a wall on the left")


func test_running_moves_legs_and_blends() -> void:
	var p := _make()
	await _w.step(90, TestWorld.forward_input())
	check(p.state == Player.State.GROUND and p.horizontal_speed() > 6.0, "running")
	var rig := _cam.rig
	var hip := rig.joint(&"hip_l")
	var lo := 9.0
	var hi := -9.0
	var max_step := 0.0
	var prev := hip.quaternion
	for i in 60:
		await _w.step(1, TestWorld.forward_input())
		var x := hip.basis.get_euler().x
		lo = minf(lo, x)
		hi = maxf(hi, x)
		max_step = maxf(max_step, prev.angle_to(hip.quaternion))
		prev = hip.quaternion
	check(hi - lo > 0.8, "legs swing while running (%.2f)" % (hi - lo))
	# Change state abruptly: joints must ease, never jump.
	var before := rig.root_pivot.quaternion
	p.set_physics_process(false)
	p.state = Player.State.PRONE
	await tree.process_frame
	await tree.process_frame
	# Prone is a quarter turn away; two frames only cover part of it.
	var jump := before.angle_to(rig.root_pivot.quaternion)
	check(jump < 1.2 and jump > 0.05, "root eases into a new state (%.2f rad in two frames)" % jump)
	check(max_step < 0.6, "no snapping while running (%.2f)" % max_step)


func test_kick_overlay_plays_and_ends() -> void:
	var p := _make()
	await _hold(p, Player.State.GROUND, 20)
	var knee := _cam.rig.joint(&"hip_r")
	var rest := knee.basis.get_euler().x
	p.trick.emit(&"kick", {})
	check(_cam.rig.kick_left() > 0.0, "kick starts")
	var peak := rest
	for i in 30:
		await tree.process_frame
		peak = maxf(peak, knee.basis.get_euler().x)
	check(peak > rest + 0.8, "leg kicks up (%.2f -> %.2f)" % [rest, peak])
	check(_cam.rig.kick_left() == 0.0, "kick finishes")
	p.trick.emit(&"hop", {})
	check(_cam.rig.kick_left() == 0.0, "other tricks don't kick")


func test_aim_raises_gun_arm() -> void:
	var p := _make()
	await _hold(p, Player.State.GROUND, 30)
	var shoulder := _cam.rig.joint(&"shoulder_r")
	var hip_fire := shoulder.basis.get_euler().x
	# The pistol owns aim_zoom; hold its aim like a scripted player would.
	(p.weapon as Pistol).aim_held = true
	p.pitch = 0.0
	for i in 40:
		await tree.process_frame
	# Arm points forward along the view: forearm direction ~ -Z.
	var hand := _cam.rig.joint(&"elbow_r")
	var dir := -(hand.global_basis.y).normalized()
	check(p.aim_zoom > 0.99, "aimed in")
	check(dir.z < -0.85, "gun arm points forward when aiming (%s, hip %.2f)" % [dir, hip_fire])
	(p.weapon as Pistol).aim_held = false


func test_every_state_poses_without_errors() -> void:
	var p := _make()
	p.set_physics_process(false)
	p.aim_zoom = 0.5
	p.lean = 0.7
	p.velocity = Vector3(0, 2, -9)
	p._wall_normal = Vector3(1, 0, 0)
	for s: int in Player.State.values():
		p.state = s as Player.State
		p.state_time = 0.1
		for i in 6:
			await tree.process_frame
		for j in BodyRig.JOINTS:
			check(_cam.rig.joint(j).quaternion.is_normalized(), "%s: %s stays valid" % [Player.State.keys()[s], j])
	# A state the rig doesn't know (added later) falls back to ground/air.
	p.state = 99 as Player.State
	for i in 6:
		await tree.process_frame
	check(_cam.rig.root_pivot.quaternion.is_normalized(), "unknown state is fine")


func test_f5_toggles_corner_view() -> void:
	var p := _make()
	check(InputMap.has_action("toggle_corner_cam"), "action registered")
	check(not GameSettings.is_bindable(_f5(), false), "F5 is reserved")
	check(_cam.is_enabled() and _cam.rig.visible, "on by default")
	_cam._unhandled_input(_f5())
	check(not _cam.is_enabled() and not _cam.frame.visible, "F5 hides it")
	check(not _cam.rig.visible, "body hidden too")
	check(_cam.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "stops rendering")
	_cam._unhandled_input(_f5())
	check(_cam.is_enabled() and _cam.rig.visible, "F5 brings it back")
	check(p.camera.cull_mask & BodyRig.LAYER == 0, "first-person still hides the body")


func test_chase_camera_follows_behind_and_avoids_walls() -> void:
	var p := _make()
	await _hold(p, Player.State.GROUND, 10)
	var cam := _cam.camera.global_position
	var local := p.global_basis.inverse() * (cam - p.global_position)
	check(local.z > 2.5 and local.x > 0.3 and local.y > 1.5, "behind, right and above (%s)" % local)
	# A wall right behind the player pulls the camera in front of it.
	_w.add_box(p.global_position + Vector3(0, 1.5, 1.5), Vector3(6, 4, 0.4))
	for i in 10:
		await tree.process_frame
	var pulled := p.global_basis.inverse() * (_cam.camera.global_position - p.global_position)
	check(pulled.z < 1.3, "pulled in front of the wall (%s)" % pulled)


func test_sandbox_has_corner_cam_and_survives_pause() -> void:
	var level: Node3D = SANDBOX.instantiate()
	tree.root.add_child(level)
	var player: Player = level.get_node("Player")
	player.use_device_input = false
	await tree.process_frame
	var cc: CornerCam = level.corner_cam
	check(cc != null and cc.rig != null and cc.rig.get_parent() == player, "sandbox builds the corner cam")
	check(player.camera.cull_mask & BodyRig.LAYER == 0, "sandbox first-person view hides the body")
	level.menu.open(0)
	for i in 5:
		await tree.process_frame
	check(tree.paused, "paused")
	level.menu.close()
	await tree.process_frame
	level.queue_free()
	await tree.process_frame


func _f5() -> InputEventKey:
	var k := InputEventKey.new()
	k.physical_keycode = KEY_F5
	k.pressed = true
	return k
