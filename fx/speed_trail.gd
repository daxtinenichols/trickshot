class_name SpeedTrail
extends MeshInstance3D
## Debug ribbon on the floor of the path you took, colored by speed
## (blue = slow, yellow = run speed, red = top speed and above). F4 toggles.

const SECONDS := 6.0
const WIDTH := 0.18

var player: Player
var _points: Array[Vector3] = []
var _speeds: Array[float] = []
var _mesh := ImmediateMesh.new()


func _ready() -> void:
	top_level = true
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = mat
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_trail"):
		visible = not visible
		_points.clear()
		_speeds.clear()


func _physics_process(_delta: float) -> void:
	if player == null or not visible:
		return
	_points.append(player.global_position + Vector3.UP * 0.05)
	_speeds.append(player.horizontal_speed())
	var keep := int(SECONDS * Engine.physics_ticks_per_second)
	if _points.size() > keep:
		_points = _points.slice(_points.size() - keep)
		_speeds = _speeds.slice(_speeds.size() - keep)
	_rebuild()


func _rebuild() -> void:
	_mesh.clear_surfaces()
	if _points.size() < 2:
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in _points.size():
		var a := _points[maxi(i - 1, 0)]
		var b := _points[mini(i + 1, _points.size() - 1)]
		var dir := (b - a)
		dir.y = 0.0
		var side := Vector3(-dir.z, 0.0, dir.x).normalized() * WIDTH if dir.length() > 0.001 else Vector3(WIDTH, 0, 0)
		var c := _color(_speeds[i])
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(_points[i] - side)
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(_points[i] + side)
	_mesh.surface_end()


func _color(speed: float) -> Color:
	var run := player.tuning.run_speed
	var top := player.tuning.top_speed
	if speed < run:
		return Color(0.25, 0.55, 1.0).lerp(Color(1.0, 0.85, 0.25), clampf(speed / run, 0.0, 1.0))
	return Color(1.0, 0.85, 0.25).lerp(Color(1.0, 0.25, 0.2), clampf((speed - run) / maxf(top - run, 0.1), 0.0, 1.0))
