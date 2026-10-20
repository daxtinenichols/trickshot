extends Node3D
## Stage 6 set pieces (Calder House and the Tower), loaded by path by
## MissionBuilder for the kinds in KINDS, and ticked by MissionRun like the
## chase set pieces (campaign/set_piece.gd): same setup / reset / tick and
## `went` signal. Placed by the route ({"set_piece": kind, "at": d, ...};
## "x", "up" move it across and up; local -Z is on along the run).
##
##   "photo"  (6-1 Head Office) a framed photo on the Host's office wall,
##            lit, at eye height: Calder Radio twenty years ago, young Rook
##            at the mic and Mags behind the booth glass in headphones. The
##            picture is rendered once, in its own little world, from the
##            Host's and Mags's models, and toned like an old print.
##            "face": 1 hangs it on the run's right-hand wall facing left,
##            -1 on the left wall facing right. Shelves of labelled tapes
##            beside it. Never fires.

const FIGURE_PATH := "res://art/characters/runner/runner_figure.gd"
const KINDS := ["photo"]
## The photo: its size on the wall (m) and the picture's pixels.
const PHOTO_SIZE := Vector2(1.25, 0.86)
const PHOTO_PIXELS := Vector2i(480, 330)

var kind := "photo"
var spec := {}
var trigger := Vector3.ZERO
var radius := 7.0
var fired := false
## Physics ticks since it fired.
var ticks := 0
## Emitted when it fires (MissionRun turns it into a mission event).
signal went(kind: String)

var _photo_view: SubViewport


func setup(p: Dictionary) -> void:
	kind = String(p.set_piece)
	spec = p
	trigger = _vec(p.get("trigger", p.get("at", [0, 0, 0])))
	radius = float(p.get("radius", 7.0))
	position = _vec(p.get("at", [0, 0, 0]))
	rotation.y = deg_to_rad(float(p.get("yaw", 0.0)))
	match kind:
		"photo":
			_build_photo()
	reset()


## Back to before it fired (you went back to a checkpoint).
func reset() -> void:
	fired = false
	ticks = 0


func tick(player_pos: Vector3, _run: Node) -> void:
	if kind == "photo":
		return
	if not fired:
		if player_pos.distance_to(trigger) < radius:
			fired = true
			ticks = 0
			went.emit(kind)
		return
	ticks += 1


# ---------------------------------------------------------------- photo

func _build_photo() -> void:
	var face := float(spec.get("face", -1.0))
	# Turned to look out from the wall into the room.
	var holder := _node(self, "Photo")
	holder.rotation.y = -face * PI * 0.5
	var wood := _mat(Color(0.24, 0.15, 0.09))
	var w := PHOTO_SIZE.x
	var h := PHOTO_SIZE.y
	# The frame and its mount, a hair off the wall.
	_box(holder, Vector3(0, 0, 0.02), Vector3(w + 0.12, h + 0.12, 0.04), wood)
	var pic := MeshInstance3D.new()
	pic.name = "Picture"
	var quad := QuadMesh.new()
	quad.size = PHOTO_SIZE
	pic.mesh = quad
	pic.position = Vector3(0, 0, 0.045)
	holder.add_child(pic)
	var mat := ShaderMaterial.new()
	mat.shader = _print_shader()
	pic.material_override = mat
	if not Engine.is_editor_hint() and DisplayServer.get_name() != "headless":
		_photo_view = _render_photo()
		mat.set_shader_parameter("picture", _photo_view.get_texture())
	# A brass plate under it.
	var plate := Label3D.new()
	plate.text = "CALDER RADIO  ·  THE LATE SHOW\nRook & Margaret"
	plate.font_size = 40
	plate.pixel_size = 0.0016
	plate.modulate = Color(0.85, 0.72, 0.42)
	plate.position = Vector3(0, -h * 0.5 - 0.17, 0.05)
	holder.add_child(plate)
	# A picture light over it: you can't miss it from the door.
	var lamp := SpotLight3D.new()
	lamp.light_color = Color(1.0, 0.86, 0.62)
	lamp.light_energy = 3.0
	lamp.spot_range = 3.0
	lamp.spot_angle = 40.0
	lamp.position = Vector3(0, h * 0.5 + 0.35, 0.45)
	lamp.rotation.x = -deg_to_rad(65.0)
	holder.add_child(lamp)
	_box(holder, Vector3(0, h * 0.5 + 0.22, 0.12), Vector3(0.4, 0.05, 0.16), _mat(Color(0.55, 0.45, 0.25)))
	# Shelves of his tapes either side: every show, labelled by year.
	var spine := [Color(0.12, 0.12, 0.13), Color(0.6, 0.55, 0.45), Color(0.2, 0.22, 0.3)]
	for side: float in [-1.0, 1.0]:
		var x := side * (w * 0.5 + 0.9)
		for row in 3:
			var y := -0.55 + row * 0.42
			_box(holder, Vector3(x, y - 0.03, 0.14), Vector3(1.3, 0.04, 0.28), wood)
			for i in 14:
				var c: Color = spine[(i + row) % spine.size()]
				_box(holder, Vector3(x - 0.6 + i * 0.09, y + 0.12, 0.13), Vector3(0.07, 0.24, 0.22), _mat(c))
			var tag := Label3D.new()
			tag.text = str(1998 + row * 3 + (0 if side < 0.0 else 9)) + "-" + str(2000 + row * 3 + (0 if side < 0.0 else 9))
			tag.font_size = 32
			tag.pixel_size = 0.0014
			tag.modulate = Color(0.9, 0.88, 0.8)
			tag.position = Vector3(x, y - 0.03, 0.29)
			holder.add_child(tag)


## The picture: its own little world, rendered once. The booth: a desk and
## a mic, the glass behind, Mags at the desk on the other side of it.
func _render_photo() -> SubViewport:
	var view := SubViewport.new()
	view.name = "PhotoView"
	view.size = PHOTO_PIXELS
	view.own_world_3d = true
	view.transparent_bg = false
	view.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(view)
	var world := Node3D.new()
	view.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.32, 0.27, 0.22)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.68, 0.6)
	e.ambient_light_energy = 0.7
	env.environment = e
	world.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-35.0), deg_to_rad(30.0), 0)
	key.light_energy = 1.3
	world.add_child(key)
	var flash := OmniLight3D.new()
	flash.position = Vector3(0, 1.7, 2.2)
	flash.light_energy = 1.5
	flash.omni_range = 6.0
	world.add_child(flash)
	# Back wall with acoustic panels, the booth glass and its frame.
	_box(world, Vector3(0, 1.5, -2.6), Vector3(6, 3, 0.1), _mat(Color(0.35, 0.3, 0.27)))
	for i in 5:
		_box(world, Vector3(-2.0 + i, 1.8, -2.53), Vector3(0.8, 0.8, 0.04), _mat(Color(0.25, 0.22, 0.2)))
	_box(world, Vector3(0, 2.3, -0.7), Vector3(4.2, 0.08, 0.08), _mat(Color(0.2, 0.2, 0.2)))
	_box(world, Vector3(-2.1, 1.4, -0.7), Vector3(0.08, 1.9, 0.08), _mat(Color(0.2, 0.2, 0.2)))
	_box(world, Vector3(2.1, 1.4, -0.7), Vector3(0.08, 1.9, 0.08), _mat(Color(0.2, 0.2, 0.2)))
	# His desk and the mic on its arm.
	_box(world, Vector3(0, 0.75, 0.25), Vector3(2.4, 0.08, 0.9), _mat(Color(0.3, 0.2, 0.12)))
	_box(world, Vector3(0, 0.37, 0.25), Vector3(2.2, 0.74, 0.7), _mat(Color(0.18, 0.13, 0.09)))
	_box(world, Vector3(-0.45, 1.3, 0.5), Vector3(0.09, 0.2, 0.09), _mat(Color(0.08, 0.08, 0.08)))
	_box(world, Vector3(-0.45, 1.05, 0.35), Vector3(0.03, 0.5, 0.03), _mat(Color(0.3, 0.3, 0.3)))
	# Her desk behind the glass, the board and two VU meters glowing.
	_box(world, Vector3(0.6, 0.75, -1.25), Vector3(2.0, 0.08, 0.5), _mat(Color(0.25, 0.2, 0.15)))
	_box(world, Vector3(0.6, 0.82, -1.25), Vector3(1.4, 0.06, 0.35), _mat(Color(0.12, 0.12, 0.12)))
	_box(world, Vector3(1.3, 1.0, -1.4), Vector3(0.2, 0.12, 0.04), _mat(Color(0.9, 0.7, 0.3), 1.5))
	_box(world, Vector3(1.55, 1.0, -1.4), Vector3(0.2, 0.12, 0.04), _mat(Color(0.9, 0.7, 0.3), 1.5))
	# Rook at the mic, leaning in; Mags behind the glass, headphones on.
	# (Figures face +Z: the camera.)
	var rook := _figure(world, "host", Vector3(-0.45, 0, 0.95), 0.25, "idle")
	if rook != null:
		rook.scale = Vector3.ONE * 0.97
	var mags := _figure(world, "mags", Vector3(0.7, 0, -1.5), -0.2, "arms_crossed")
	if mags != null:
		_box(mags, Vector3(0, 1.62, 0), Vector3(0.24, 0.05, 0.05), _mat(Color(0.1, 0.1, 0.1)))
		_box(mags, Vector3(-0.11, 1.55, 0), Vector3(0.05, 0.11, 0.09), _mat(Color(0.1, 0.1, 0.1)))
		_box(mags, Vector3(0.11, 1.55, 0), Vector3(0.05, 0.11, 0.09), _mat(Color(0.1, 0.1, 0.1)))
	var cam := Camera3D.new()
	cam.position = Vector3(0.1, 1.45, 3.4)
	cam.rotation.x = deg_to_rad(-4.0)
	cam.fov = 34.0
	world.add_child(cam)
	cam.current = true
	return view


## An old print: sepia, faded blacks, a soft vignette and some grain.
static func _print_shader() -> Shader:
	var s := Shader.new()
	s.code = """
shader_type spatial;
render_mode unshaded;
uniform sampler2D picture : source_color, filter_linear;
void fragment() {
	vec3 c = texture(picture, UV).rgb;
	float l = dot(c, vec3(0.3, 0.59, 0.11));
	vec3 sepia = vec3(l * 1.07 + 0.05, l * 0.9 + 0.04, l * 0.68 + 0.03);
	vec2 d = UV - 0.5;
	float vig = 1.0 - dot(d, d) * 1.4;
	float grain = fract(sin(dot(UV * 431.0, vec2(12.9898, 78.233))) * 43758.5453) * 0.05;
	ALBEDO = clamp(sepia * vig + grain, 0.0, 1.0) * 0.92;
}
"""
	return s


# ---------------------------------------------------------------- parts

func _figure(parent: Node3D, runner: String, at: Vector3, yaw: float, pose: String) -> Node3D:
	var script := load(FIGURE_PATH) as Script if ResourceLoader.exists(FIGURE_PATH) else null
	if script == null or not script.can_instantiate():
		return null
	var f: Node3D = script.new()
	f.name = "Figure_" + runner
	f.runner = runner
	f.pose_name = pose
	f.held = ""
	f.position = at
	f.rotation.y = yaw
	parent.add_child(f)
	return f


func _node(parent: Node3D, n: String) -> Node3D:
	var node := Node3D.new()
	node.name = n
	parent.add_child(node)
	return node


func _mat(c: Color, glow := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	return m


## A box part, visual only.
func _box(parent: Node3D, center: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = mat
	mesh.position = center
	parent.add_child(mesh)
	return mesh


static func _vec(a: Variant) -> Vector3:
	if a is Array and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO
