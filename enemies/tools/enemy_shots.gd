extends SceneTree
## Renders the enemy models for review: a lineup of every enemy type in its
## key states, from the front and from a three-quarter view.
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --fixed-fps 60 -s res://enemies/tools/enemy_shots.gd -- <out_dir>
## Enemies are created inactive and their state is set by hand, so each one
## holds the pose that state calls for.

var out := "user://enemy_shots"
var world: Node3D
var cam: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	world = Node3D.new()
	root.add_child(world)
	_stage()
	var lineups: Array = load("res://enemies/tools/enemy_lineups.gd").lineups()
	for l: Dictionary in lineups:
		var made: Array[Node3D] = []
		var x := -float(l.items.size() - 1) * 1.1
		for item: Array in l.items:
			var e: Node3D = load(item[0]).new()
			for k: String in item[1]:
				if k != "_call":
					e.set(k, item[1][k])
			e.position = Vector3(x, 0, 0)
			x += 2.2
			world.add_child(e)
			# Frozen: the state set below holds, and nothing walks off.
			e.set_physics_process(false)
			if item[1].has("_call"):
				(item[1]["_call"] as Callable).call(e)
			made.append(e)
		for view: Array in l.views:
			cam.global_position = view[0]
			cam.look_at(view[1])
			for f in 40:
				for i in made.size():
					var props: Dictionary = l.items[i][1]
					for k: String in props:
						if k != "_call":
							made[i].set(k, props[k])
				await process_frame
			_save("%s_%s" % [l.name, view[2]])
		for e in made:
			e.queue_free()
		await _frames(2)
	quit()


func _stage() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.45, 0.5, 0.56)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.5, 0.48)
	e.ambient_light_energy = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 150, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	world.add_child(sun)
	var floor := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(60, 1, 60)
	cs.shape = bs
	floor.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = bs.size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.5, 0.46, 0.4)
	mi.material_override = m
	floor.add_child(mi)
	floor.position.y = -0.5
	world.add_child(floor)
	cam = Camera3D.new()
	cam.fov = 50
	world.add_child(cam)
	cam.current = true


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(n: String) -> void:
	root.get_texture().get_image().save_png(out.path_join(n + ".png"))
	print("saved ", n)
