extends Node3D
## Speed-colored ribbons streaming from the runner's hands and feet. They
## appear once you're moving faster than a run and shift from cool blue to
## hot red toward top speed, so speed reads at a glance in third person.

const POINTS := ["LeftHand", "RightHand", "LeftFoot", "RightFoot"]
const WIDTH := 0.07

var player: Player
var body: Node3D
## Seconds a trail point lives at run speed (longer when faster).
var lifetime := 0.28

var _mesh := ImmediateMesh.new()
var _trails := {}  # bone -> Array of [position, age, speed]
var _instance := MeshInstance3D.new()


func setup(p: Player, runner: Node3D) -> void:
	player = p
	body = runner


func _ready() -> void:
	# Points are in world space. top_level keeps the transform the node had
	# when it was added (the spawn point), so reset it or every trail would
	# be drawn offset by where the body was created.
	top_level = true
	global_transform = Transform3D.IDENTITY
	_instance.mesh = _mesh
	_instance.layers = RunnerBody.LAYER
	_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_instance.extra_cull_margin = 16384.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_instance.material_override = mat
	add_child(_instance)
	for b: String in POINTS:
		_trails[b] = []


## Blue -> yellow -> red with speed, matching the debug speed trail.
static func speed_color(speed: float, run: float, top: float) -> Color:
	if speed < run:
		return Color(0.25, 0.55, 1.0).lerp(Color(1.0, 0.85, 0.25), clampf(speed / run, 0.0, 1.0))
	return Color(1.0, 0.85, 0.25).lerp(Color(1.0, 0.25, 0.2), clampf((speed - run) / maxf(top - run, 0.1), 0.0, 1.0))


func _process(delta: float) -> void:
	if player == null or body == null:
		return
	var speed := player.velocity.length()
	var run := player.tuning.run_speed
	var life := lifetime * (1.0 + clampf((speed - run) / run, 0.0, 1.5))
	for b: String in POINTS:
		var pts: Array = _trails[b]
		for p: Array in pts:
			p[1] += delta
		while pts.size() > 0 and pts[0][1] > life:
			pts.pop_front()
		pts.append([body.bone_world_position(b), 0.0, speed])
	_rebuild(life)


func _rebuild(life: float) -> void:
	_mesh.clear_surfaces()
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var run := player.tuning.run_speed
	var top := player.tuning.top_speed
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	for b: String in POINTS:
		var pts: Array = _trails[b]
		for i in range(1, pts.size()):
			var a: Array = pts[i - 1]
			var c: Array = pts[i]
			var pa: Vector3 = a[0]
			var pc: Vector3 = c[0]
			var ca := _color(a, life, run, top)
			var cc := _color(c, life, run, top)
			if pa.distance_to(pc) < 0.001 or (ca.a <= 0.0 and cc.a <= 0.0):
				continue
			var side := _side(pa, pc, cam) * WIDTH
			var side_a: Vector3 = side * (1.0 - a[1] / life)
			var side_c: Vector3 = side * (1.0 - c[1] / life)
			for v: Array in [[pa - side_a, ca], [pa + side_a, ca], [pc + side_c, cc], [pa - side_a, ca], [pc + side_c, cc], [pc - side_c, cc]]:
				verts.append(v[0])
				colors.append(v[1])
	if verts.is_empty():
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in verts.size():
		_mesh.surface_set_color(colors[i])
		_mesh.surface_add_vertex(verts[i])
	_mesh.surface_end()


func _side(a: Vector3, b: Vector3, cam: Camera3D) -> Vector3:
	var dir := (b - a).normalized()
	var to_cam := (cam.global_position - a).normalized()
	var s := dir.cross(to_cam)
	return s.normalized() if s.length() > 0.001 else Vector3.UP


func _color(p: Array, life: float, run: float, top: float) -> Color:
	var c := speed_color(p[2], run, top)
	# Trails only show above run pace, and fade out along their length.
	var show := clampf((p[2] - run * 0.85) / (run * 0.3), 0.0, 1.0)
	c.a = show * 0.8 * (1.0 - p[1] / life)
	return c
