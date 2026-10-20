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


## Obstacles get dressed as part of the city (concrete, brick, crates,
## hoardings) without touching what you collide with, and turning the look
## off brings the plain color-coded blocks back.
func test_obstacles_dress_as_the_city() -> void:
	var look := _look()
	var shapes := {}
	var kinds := {"PARKOUR": 0, "WALLRUN": 0}
	for body: Node in level.find_children("*", "StaticBody3D", true, false):
		var k: String = body.get_meta("kind", "")
		if kinds.has(k) and not body.has_meta("look"):
			kinds[k] += 1
			for c in body.get_children():
				if c is CollisionShape3D:
					shapes[c] = [(c.shape as BoxShape3D).size, (c as Node3D).global_transform]
	check(kinds.PARKOUR > 0 and kinds.WALLRUN > 0, "the sandbox has obstacles to dress")
	look._apply_all(level)
	var dressed := {}
	var styles := {}
	for body: Node in level.find_children("*", "StaticBody3D", true, false):
		var k: String = body.get_meta("kind", "")
		if kinds.has(k) and not body.has_meta("look"):
			var d := body.get_node_or_null("Dress")
			if d != null:
				dressed[k] = dressed.get(k, 0) + 1
				styles[d.get_meta("style")] = true
	check(dressed.get("PARKOUR", 0) == kinds.PARKOUR, "every vault, ledge and climb dressed (%d of %d)" % [dressed.get("PARKOUR", 0), kinds.PARKOUR])
	check(dressed.get("WALLRUN", 0) == kinds.WALLRUN, "every wallrun wall dressed (%d of %d)" % [dressed.get("WALLRUN", 0), kinds.WALLRUN])
	check(styles.size() >= 4, "in a mix of styles (%s)" % [styles.keys()])
	var same := true
	for c: CollisionShape3D in shapes:
		if (c.shape as BoxShape3D).size != shapes[c][0] or not c.global_transform.is_equal_approx(shapes[c][1]):
			same = false
	check(same, "collision untouched")
	look.set_enabled(false)
	var left := 0
	var hidden := 0
	for body: Node in level.find_children("*", "StaticBody3D", true, false):
		if body.has_node("Dress"):
			left += 1
		for c in body.get_children():
			if c is MeshInstance3D and not (c as MeshInstance3D).visible:
				hidden += 1
	check(left == 0 and hidden == 0, "look off: plain blocks back (%d dressed, %d hidden)" % [left, hidden])
	look.set_enabled(true)
	var again := 0
	for body: Node in level.find_children("*", "StaticBody3D", true, false):
		if body.has_node("Dress"):
			again += 1
	check(again == kinds.PARKOUR + kinds.WALLRUN + _count_kind("SLIDE") + _count_kind("SURFACE"), "dressed again when back on")


## Ramps, banks and loops are dressed too (concrete channel walls, scrap
## steel track), each kind of piece in one style, collision untouched.
func test_surfaces_dress_as_the_city() -> void:
	var look := _look()
	var shapes := {}
	for body: Node in level.find_children("*", "StaticBody3D", true, false):
		if body.get_meta("kind", "") == "SURFACE":
			for c in body.get_children():
				if c is CollisionShape3D:
					shapes[c] = [(c.shape as BoxShape3D).size, (c as Node3D).global_transform]
	check(shapes.size() > 20, "the sandbox has ramps, banks and loops")
	look._apply_all(level)
	var styles := {}
	var plain := 0
	for body: Node in level.find_children("*", "StaticBody3D", true, false):
		if body.get_meta("kind", "") == "SURFACE":
			var d := body.get_node_or_null("Dress")
			if d == null:
				plain += 1
			else:
				styles[d.get_meta("style")] = true
	check(plain == 0, "every runnable surface dressed (%d plain)" % plain)
	check(styles.has("track") and styles.has("channel"), "loops and quarter pipes as track, banks as channel walls (%s)" % [styles.keys()])
	var same := true
	for c: CollisionShape3D in shapes:
		if (c.shape as BoxShape3D).size != shapes[c][0] or not c.global_transform.is_equal_approx(shapes[c][1]):
			same = false
	check(same, "collision untouched")


## A building with the "TOWER" look becomes the broadcast tower: everything
## but the roof mast stays inside its box, and F9 brings the block back.
func test_broadcast_tower_dress() -> void:
	var look := _look()
	var size := Vector3(50, 72, 50)
	var at := Vector3(200, 36, 200)
	var body := StaticBody3D.new()
	body.position = at
	body.set_meta("kind", "NEUTRAL")
	body.set_meta("look", "TOWER")
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	body.add_child(cs)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	var m := ShaderMaterial.new()
	m.shader = preload("res://levels/graybox.gdshader")
	m.set_shader_parameter("base_color", Color(0.6, 0.6, 0.6))
	mesh.material_override = m
	body.add_child(mesh)
	level.add_child(body)
	look._apply_all(body)
	var dress := body.get_node_or_null("Dress")
	check(dress != null and dress.get_meta("style", "") == "broadcast_tower", "dressed as the broadcast tower")
	check(not mesh.visible, "the plain block is hidden")
	var outside := 0
	var mast := 0
	var bounds := AABB(at - size * 0.5 - Vector3(0.05, 0.05, 0.05), size + Vector3(0.1, 0.1, 0.1))
	for mi: MeshInstance3D in dress.find_children("*", "MeshInstance3D", true, false):
		var a := mi.global_transform * mi.get_aabb()
		if a.position.y >= at.y + size.y * 0.5 - 0.1:
			mast += 1  # on the roof, out of reach
		elif not bounds.encloses(a):
			outside += 1
	check(outside == 0, "nothing below the roof sticks out of the box (%d)" % outside)
	check(mast > 20, "a lattice mast on the roof (%d pieces)" % mast)
	look.set_enabled(false)
	check(mesh.visible and body.get_node_or_null("Dress") == null, "look off: the block is back")
	look.set_enabled(true)
	body.queue_free()


## A slide-under bar dressed as a pipe or girder stands on a post at each
## end that reaches the floor 1.1 m below it, inside the bar's length.
func test_slide_bars_stand_on_posts() -> void:
	var look := _look()
	var size := Vector3(12, 0.5, 0.6)
	for at: Vector3 in [Vector3(200, 1.35, 200), Vector3(230.3, 1.35, 200)]:
		var body := StaticBody3D.new()
		body.position = at
		body.set_meta("kind", "PARKOUR")
		body.set_meta("dress", "pipe")
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		cs.shape = box
		body.add_child(cs)
		var mesh := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mesh.mesh = bm
		var m := ShaderMaterial.new()
		m.shader = preload("res://levels/graybox.gdshader")
		m.set_shader_parameter("base_color", Color(0.9, 0.75, 0.2))
		mesh.material_override = m
		body.add_child(mesh)
		level.add_child(body)
		look._apply_all(body)
		var dress := body.get_node_or_null("Dress")
		check(dress != null and dress.get_meta("style", "") == "pipe", "dressed as a pipe or girder")
		var low := INF
		var wide := 0.0
		for mi: MeshInstance3D in dress.find_children("*", "MeshInstance3D", true, false):
			var a := mi.global_transform * mi.get_aabb()
			low = minf(low, a.position.y)
			wide = maxf(wide, maxf(absf(a.position.x - at.x), absf(a.end.x - at.x)))
		check_near(low, 0.0, 0.05, "its posts reach the floor")
		check(wide <= size.x * 0.5 + 0.2, "and stand inside the bar's ends (%.2f m out)" % wide)
		body.queue_free()


## Practice targets look like junk set up to shoot at, without changing
## their hitboxes, and their own meshes come back when the look is off.
func test_targets_dress_as_junk() -> void:
	var look := _look()
	var targets := level.find_children("*", "ShootingTarget", true, false)
	check(targets.size() > 0, "the sandbox has targets")
	var before := {}
	for t: Node in targets:
		for hb in t.find_children("*", "StaticBody3D", true, false):
			before[hb] = (hb as Node3D).global_transform
	look._apply_all(level)
	var styles := {}
	var dressed := 0
	for t: Node in targets:
		var d := t.find_child("TargetLook", true, false)
		if d != null:
			dressed += 1
			styles[d.get_meta("style")] = true
	check(dressed == targets.size(), "every target dressed (%d of %d)" % [dressed, targets.size()])
	check(styles.size() >= 2, "in more than one style (%s)" % [styles.keys()])
	var same := true
	for hb: Node3D in before:
		if not hb.global_transform.is_equal_approx(before[hb]):
			same = false
	check(same, "hitboxes untouched")
	look.set_enabled(false)
	var left := 0
	for t: Node in targets:
		if t.find_child("TargetLook", true, false) != null:
			left += 1
	check(left == 0, "look off: plain targets back")
	look.set_enabled(true)


func _count_kind(kind: String) -> int:
	var n := 0
	for body: Node in level.find_children("*", "StaticBody3D", true, false):
		if body.get_meta("kind", "") == kind and not body.has_meta("look"):
			n += 1
	return n


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
	var to_body := cam.global_position.y - (player.global_position.y + 1.0)
	check(to_body > 1.0, "above the runner's head, looking past it (%.1f m)" % to_body)
	cam.set_active(false)
	cam.queue_free()


## A thin post just beside the line from the runner to the lens: a thin ray
## slips past it, but the lens would sit half inside it.
func test_chase_camera_stays_out_of_thin_posts() -> void:
	ArtLook.ensure_body(player)
	var cam: Camera3D = preload("res://art/look/chase_camera.gd").new()
	level.add_child(cam)
	cam.setup(player)
	cam.set_active(true)
	await tree.process_frame
	var post := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = Vector3(0.1, 6.0, 0.1)
	post.add_child(shape)
	level.add_child(post)
	post.global_position = cam.global_position + cam.global_basis.x * 0.08
	for i in 3:
		await tree.physics_frame
		await tree.process_frame
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = SphereShape3D.new()
	(q.shape as SphereShape3D).radius = 0.07
	q.transform = Transform3D(Basis.IDENTITY, cam.global_position)
	var hits := level.get_world_3d().direct_space_state.intersect_shape(q)
	check(hits.filter(func(h): return h.collider == post).is_empty(), "the lens stays out of the post")
	cam.set_active(false)
	cam.queue_free()


func _wheel(cam: Node, button: MouseButton) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = true
	cam._unhandled_input(e)


func test_chase_camera_tilts_with_the_view_and_zooms_to_first_person() -> void:
	ArtLook.ensure_body(player)
	var cam: Camera3D = preload("res://art/look/chase_camera.gd").new()
	level.add_child(cam)
	cam.setup(player)
	cam.set_active(true)
	await tree.process_frame
	var level_y := cam.global_position.y - player.global_position.y
	player.set_view(player.yaw, deg_to_rad(-40.0))
	await tree.process_frame
	var down_y := cam.global_position.y - player.global_position.y
	player.set_view(player.yaw, deg_to_rad(20.0))
	await tree.process_frame
	var up_y := cam.global_position.y - player.global_position.y
	check(down_y > level_y + 1.0 and up_y < level_y - 1.0, "looking down raises the camera, up lowers it (%.1f / %.1f / %.1f)" % [down_y, level_y, up_y])
	player.set_view(player.yaw, 0.0)
	# Scroll in until it hands over to the first-person camera.
	var before: float = cam.distance
	_wheel(cam, MOUSE_BUTTON_WHEEL_UP)
	check(cam.distance < before, "wheel up zooms in")
	for i in 30:
		_wheel(cam, MOUSE_BUTTON_WHEEL_UP)
	check(not cam.is_active() and player.camera.current, "zoomed all the way in = first person")
	_wheel(cam, MOUSE_BUTTON_WHEEL_DOWN)
	check(cam.is_active() and cam.current, "scrolling out of first person comes back to third")
	cam.set_active(false)
	cam.queue_free()


func test_chase_camera_crosshair_is_where_shots_go() -> void:
	# Shots come from the first-person view; the third-person screen centre
	# must sit on the same point, from over the shoulder.
	ArtLook.ensure_body(player)
	level.go_to_zone(9)  # shooting range
	await tree.physics_frame
	var cam: Camera3D = preload("res://art/look/chase_camera.gd").new()
	level.add_child(cam)
	cam.setup(player)
	cam.set_active(true)
	for yaw: float in [0.0, 0.5, -0.4]:
		player.set_view(yaw, -0.05)
		for i in 30:
			await tree.process_frame
		var eye := player.camera.global_transform
		var q := PhysicsRayQueryParameters3D.create(eye.origin, eye.origin - eye.basis.z * 120.0, 1 | 4)
		q.exclude = [player.get_rid()]
		var r := player.get_world_3d().direct_space_state.intersect_ray(q)
		var hit: Vector3 = eye.origin - eye.basis.z * 120.0 if r.is_empty() else r.position
		var centre := cam.global_position - cam.global_basis.z * cam.global_position.distance_to(hit)
		check(centre.distance_to(hit) < 0.3, "screen centre on the shot's landing point (off by %.2f m)" % centre.distance_to(hit))
	var right := cam.global_basis.x.dot(cam.global_position - player.global_position)
	check(right > 0.3, "over the right shoulder (%.2f m)" % right)
	cam.set_active(false)
	cam.queue_free()


func test_chase_camera_can_follow_side_flips() -> void:
	ArtLook.ensure_body(player)
	var cam: Camera3D = preload("res://art/look/chase_camera.gd").new()
	level.add_child(cam)
	cam.setup(player)
	cam.set_active(true)
	player.set_physics_process(false)
	player.state = Player.State.AIR
	player.velocity = Vector3.ZERO
	player._air_roll = 1.0
	for i in 20:
		await tree.process_frame
	var tilt := func() -> float: return cam.global_basis.y.angle_to(Vector3.UP)
	var level_tilt: float = tilt.call()
	# The pause-menu setting wins over the camera's own fallback.
	Settings.camera_follow_flips = true
	await tree.process_frame
	await tree.process_frame
	var follow_tilt: float = tilt.call()
	var up_view := player.camera.global_basis.y
	check(level_tilt < 0.5, "off: the camera stays upright through a side flip (%.2f rad)" % level_tilt)
	check(follow_tilt > 0.7, "on: the camera rolls with the side flip (%.2f rad)" % follow_tilt)
	check(cam.global_basis.x.dot(player.camera.global_basis.x) > 0.95, "rolls the same way as the view (up %s)" % up_view)
	Settings.camera_follow_flips = false
	cam.set_active(false)
	cam.queue_free()


func test_runner_holds_raises_and_reloads_the_gun() -> void:
	var gun: Pistol = player.weapon
	_look().attach_to_player(player)
	var body: RunnerBody = player.get_node("RunnerBody")
	level.go_to_zone(9)
	for i in 40:
		await tree.process_frame
	var hand_y := func() -> float: return body.bone_world_position("RightHand").y - player.global_position.y
	var low: float = hand_y.call()
	gun.trigger_pressed = true
	for i in 12:
		await tree.process_frame
	var raised: float = hand_y.call()
	check(raised > low + 0.25, "hip fire raises the gun hand (%.2f -> %.2f m)" % [low, raised])
	for i in 80:
		await tree.process_frame
	check(hand_y.call() < raised - 0.2, "and lowers it again after a moment (%.2f m)" % hand_y.call())
	var apart := func() -> float: return body.bone_world_position("LeftHand").distance_to(body.bone_world_position("RightHand"))
	var before: float = apart.call()
	gun.reload_pressed = true
	for i in 30:
		await tree.process_frame
	check(apart.call() < before - 0.15, "reload brings the hands together (%.2f -> %.2f m)" % [before, apart.call()])
	var held: Node3D = player.get_node("GunLook").held_model
	check(held.is_visible_in_tree(), "gun stays in hand")


func test_gun_look_replaces_the_test_pistol_visuals() -> void:
	var gun: Pistol = player.weapon
	_look().attach_to_player(player)
	var look: GunLook = player.get_node("GunLook")
	check(not gun.builtin_visuals, "test pistol boxes and effects off")
	check(look.fp_model.get_parent() == gun.view_model, "first-person model rides the view model")
	var fp_mats: Array = look.fp_model.find_children("*", "MeshInstance3D", true, false).map(
		func(mi: MeshInstance3D) -> Variant: return (mi.material_override as ShaderMaterial).get_shader_parameter("depth_scale")).filter(
		func(d: Variant) -> bool: return d != null)
	check(fp_mats.size() >= 2 and fp_mats.all(func(d: Variant) -> bool: return float(d) < 0.2),
		"first-person gun draws over walls instead of poking through them")
	var tp_mats: Array = look.held_model.find_children("*", "MeshInstance3D", true, false).map(
		func(mi: MeshInstance3D) -> Variant: return (mi.material_override as ShaderMaterial).get_shader_parameter("depth_scale"))
	check(tp_mats.all(func(d: Variant) -> bool: return d == null or is_equal_approx(float(d), 1.0)), "the held gun keeps normal depth")
	var hand := look.held_model.get_parent() as BoneAttachment3D
	check(hand != null and hand.bone_name == "RightHand", "third-person gun is in the right hand")
	level.go_to_zone(9)
	await tree.physics_frame
	gun.trigger_pressed = true
	await tree.physics_frame
	await tree.process_frame
	check(look._flashes.all(func(f: Node3D) -> bool: return f.visible), "muzzle flash shows")
	check(look._tracers.size() == 1, "tracer spawned")
	check(look._casings.size() == 1, "casing ejected")
	var slide: Node3D = look._slides[0]
	check(slide.position.z > slide.get_meta("rest_z") + 0.005, "slide blows back")
	for i in 20:
		await tree.process_frame
	check(look._flashes.all(func(f: Node3D) -> bool: return not f.visible), "flash is brief")
	_look().set_enabled(false)
	await tree.process_frame
	check(gun.builtin_visuals, "test pistol visuals back with the art look off")
	_look().set_enabled(true)


func test_body_holds_its_facing_when_the_view_snaps() -> void:
	# Running straight, a sudden mouse flick must not swing the body with the
	# camera and back (that read as jitter in third person).
	var body: RunnerBody = ArtLook.ensure_body(player)
	level.go_to_zone(0)
	player.scripted_input = TestWorld.forward_input()
	for i in 90:
		await tree.physics_frame
	var facing := func() -> Vector3:
		var f := body.global_basis.z
		return Vector3(f.x, 0, f.z).normalized()
	var before: Vector3 = facing.call()
	player.set_view(player.yaw + 0.6, player.pitch)
	# process_frame fires before nodes' _process: wait for the body's update.
	await tree.process_frame
	await tree.process_frame
	var after: Vector3 = facing.call()
	check(before.angle_to(after) < 0.15, "body barely turns on the flick frame (%.2f rad)" % before.angle_to(after))


func test_body_is_smooth_in_slow_motion() -> void:
	# In slow-mo the sim ticks less often than frames are drawn; the body must
	# follow the interpolated transform, moving a little every frame instead
	# of jumping once per tick.
	var body: RunnerBody = ArtLook.ensure_body(player)
	player.scripted_input = TestWorld.forward_input()
	for i in 60:
		await tree.physics_frame
	Engine.time_scale = 0.25
	# Settle: the frames around the switch still carry a full-speed step.
	for i in 6:
		await tree.process_frame
	var steps: Array[float] = []
	var last := body.global_position
	for i in 24:
		await tree.process_frame
		steps.append(body.global_position.distance_to(last))
		last = body.global_position
	Engine.time_scale = 1.0
	var total := 0.0
	var still := 0
	for d in steps:
		total += d
		if d < 0.002:
			still += 1
	check(total > 0.3, "moving (%.2f m)" % total)
	check(still <= 2, "moves on almost every frame (%d still frames of %d)" % [still, steps.size()])
	check(steps.max() < total / steps.size() * 2.5, "no jumps (largest step %.3f, mean %.3f)" % [steps.max(), total / steps.size()])
