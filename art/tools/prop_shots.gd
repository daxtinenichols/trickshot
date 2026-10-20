extends SceneTree
## Renders the prop kit for review: every prop in a labeled row on a lot,
## plus a close-up of each.
##   xvfb-run -a godot --path . --fixed-fps 60 -s res://art/tools/prop_shots.gd -- <out_dir> [sheet,each]

const PropKit := preload("res://art/props/prop_kit.gd")
const COLUMNS := 6
const SPACING := 7.5

var out := "user://prop_shots"
var stage: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	var parts := args[1].split(",") if args.size() > 1 else PackedStringArray(["sheet", "each"])
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	_build_stage()
	await _frames(5)
	var names := PropKit.names()
	var spots := {}
	for i in names.size():
		var pos := Vector3((i % COLUMNS - (COLUMNS - 1) * 0.5) * SPACING, 0, -floorf(i / float(COLUMNS)) * SPACING)
		spots[names[i]] = pos
		PropKit.place(stage, names[i], Transform3D(Basis(Vector3.UP, 0.5), pos))
		var l := Label3D.new()
		l.text = names[i]
		l.position = pos + Vector3(0, 0.05, 2.6)
		l.rotation.x = -PI * 0.5
		l.pixel_size = 0.006
		l.font_size = 48
		l.outline_size = 10
		stage.add_child(l)
	await _frames(5)
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.far = 400.0
	stage.add_child(cam)
	cam.make_current()
	if "sheet" in parts:
		var rows := ceili(names.size() / float(COLUMNS))
		var depth := (rows - 1) * SPACING
		cam.look_at_from_position(Vector3(0, 30, 16), Vector3(0, 0, -depth * 0.5))
		await _frames(10)
		_save("props_sheet")
		cam.look_at_from_position(Vector3(-24, 6, 12), Vector3(0, 1.5, -depth * 0.35))
		await _frames(10)
		_save("props_street")
	if "each" in parts:
		for n: String in names:
			var size := PropKit.size_of(n)
			var reach := maxf(size.length(), 1.2)
			var target: Vector3 = spots[n] + Vector3(0, size.y * 0.45, 0)
			cam.look_at_from_position(target + Vector3(-0.75, 0.55, 1.1).normalized() * reach * 1.35, target)
			await _frames(6)
			_save("prop_" + n)
	quit()


func _build_stage() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	stage.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-45), deg_to_rad(30), 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.2
	stage.add_child(sun)
	# The lot: a graybox floor, so ArtLook paints it as asphalt.
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	floor_mesh.mesh = plane
	floor_mesh.position = Vector3(0, 0, -12)
	var m := ShaderMaterial.new()
	m.shader = load("res://levels/graybox.gdshader")
	m.set_shader_parameter("base_color", Color(0.56, 0.58, 0.62))
	floor_mesh.material_override = m
	var body := StaticBody3D.new()
	body.set_meta("kind", "FLOOR")
	body.add_child(floor_mesh)
	stage.add_child(body)


func _save(shot: String) -> void:
	root.get_texture().get_image().save_png(out.path_join(shot + ".png"))
	print("saved ", shot)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
