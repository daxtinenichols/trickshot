extends TestCase
## The prop kit: the catalog matches the models, placing a prop gives it
## its colliders and material, a missing model falls back to boxes, and the
## player treats props like any other geometry (a crate is a vault).

const PropKit := preload("res://art/props/prop_kit.gd")

var w: TestWorld


func before_each() -> void:
	w = TestWorld.new()
	tree.root.add_child(w)


func after_each() -> void:
	w.queue_free()
	await tree.process_frame


func test_catalog_lists_every_model() -> void:
	var names := PropKit.names()
	check(names.size() >= 25, "the kit has its props (%d)" % names.size())
	for n in names:
		var path := PropKit.DIR + n + ".glb"
		check(ResourceLoader.exists(path), "%s has a model" % n)
		var size := PropKit.size_of(n)
		check(size.x > 0.0 and size.y > 0.0 and size.z > 0.0, "%s has a size" % n)
		var bottom: float = PropKit.catalog()[n].get("bottom", 1.0)
		# Rubble may sink a little into the ground on purpose.
		check_near(bottom, 0.0, 0.15, "%s stands on its origin" % n)


func test_colliders_sit_inside_the_model() -> void:
	for n in PropKit.names():
		var size := PropKit.size_of(n)
		for c: Dictionary in PropKit.catalog()[n].colliders:
			var center := Vector3(c.center[0], c.center[1], c.center[2])
			check(absf(center.x) <= size.x * 0.5 + 0.05 and absf(center.z) <= size.z * 0.5 + 0.05,
				"%s collider at %s is within its footprint %s" % [n, center, size])
			check(center.y >= 0.0 and center.y <= size.y + 0.05, "%s collider height in range" % n)


func test_place_adds_colliders_and_model() -> void:
	var xf := Transform3D(Basis(Vector3.UP, 0.3), Vector3(2, 0, -3))
	var body := PropKit.place(w, "car_wreck", xf)
	check(body is StaticBody3D, "a prop with colliders is a static body")
	check(body.collision_layer == 1, "on the world layer")
	check(body.get_meta("prop") == "car_wreck", "remembers its name")
	var shapes := body.find_children("*", "CollisionShape3D", false, false)
	check(shapes.size() == PropKit.catalog()["car_wreck"].colliders.size(), "one shape per catalog collider")
	var model := body.get_node_or_null("Model")
	check(model != null, "the model is loaded")
	if model != null:
		var meshes := model.find_children("*", "MeshInstance3D", true, false)
		check(meshes.size() > 0, "the model has a mesh")
		for mi in meshes:
			check((mi as MeshInstance3D).material_override == PropKit.material(), "uses the shared prop material")
	check(body.global_transform.is_equal_approx(xf), "placed where asked")


func test_props_without_colliders_are_plain_nodes() -> void:
	var tape := PropKit.place(w, "tape_cassette", Transform3D(Basis.IDENTITY, Vector3(0, 1, 0)))
	check(tape != null and not (tape is CollisionObject3D), "a collectible has no collision")
	var solid := PropKit.place(w, "crate_wood", Transform3D.IDENTITY, false)
	check(not (solid is CollisionObject3D), "collide = false skips collision")


func test_unknown_prop_is_null() -> void:
	check(PropKit.place(w, "no_such_prop") == null, "unknown names place nothing")


func test_missing_model_falls_back_to_boxes() -> void:
	var saved: Variant = PropKit._scenes.get("barrel_rust")
	PropKit._scenes["barrel_rust"] = null
	var body := PropKit.place(w, "barrel_rust")
	PropKit._scenes["barrel_rust"] = saved
	check(body.get_node_or_null("Model") == null, "no model")
	var boxes := body.find_children("*", "MeshInstance3D", false, false)
	check(boxes.size() == PropKit.catalog()["barrel_rust"].colliders.size(), "a gray box per collider")


func test_runner_vaults_a_crate() -> void:
	w.add_floor()
	PropKit.place(w, "crate_wood", Transform3D(Basis.IDENTITY, Vector3(0, 0, -8)))  # face at z = -7.5
	var p := w.spawn_player(Vector3(0, 0.05, 0))
	await w.step(20)
	await w.step_until(func() -> bool: return p.global_position.z < -6.6, 300, TestWorld.forward_input())
	await w.press(InputFrame.make(Vector2(0, 1), true))
	check(p.state == Player.State.VAULT, "jumping at a crate vaults it (%s)" % Player.State.keys()[p.state])
	await w.step(40, TestWorld.forward_input())
	check(p.global_position.z < -8.6, "over it (z %.2f)" % p.global_position.z)


func test_runner_wallruns_a_container() -> void:
	w.add_floor()
	# A container lying along the run; its side face is at x = 2.
	PropKit.place(w, "shipping_container", Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(3.22, 0, -12)))
	var p := w.spawn_player(Vector3(-1.8, 0.05, 0))
	p.set_view(-0.3)
	await w.step(20)
	await w.step_until(func() -> bool: return p.global_position.x > 0.6, 300, TestWorld.forward_input())
	await w.press(InputFrame.make(Vector2(0, 1), true))
	var ran := await w.step_until(func() -> bool: return p.state == Player.State.WALLRUN, 90, TestWorld.forward_input())
	check(ran, "jumping at a container side starts a wallrun")
