@tool
class_name SandboxBuilder
extends Node3D
## Builds the graybox movement sandbox from code, in the editor and in game.
## Generated nodes are not saved into the scene file, so edit the layout here.
##
## Color language (matches the art direction):
##   gray   = plain geometry
##   blue   = wallrun walls
##   yellow = vault / mantle / climb features
##   green  = slide ramps
##   red    = kickable targets

enum Kind { FLOOR, NEUTRAL, WALLRUN, PARKOUR, SLIDE }

const COLORS := {
	Kind.FLOOR: Color(0.56, 0.58, 0.62),
	Kind.NEUTRAL: Color(0.76, 0.77, 0.80),
	Kind.WALLRUN: Color(0.27, 0.6, 0.98),
	Kind.PARKOUR: Color(0.98, 0.78, 0.26),
	Kind.SLIDE: Color(0.32, 0.78, 0.58),
}

const SHADER := preload("res://levels/graybox.gdshader")
const DUMMY_SCRIPT := preload("res://levels/target_dummy.gd")

## Zone name -> spawn transform. Filled by build().
var spawns: Array[Transform3D] = []
var zone_names: Array[String] = []

var _materials := {}
var _root: Node3D


func _ready() -> void:
	build()


func build() -> void:
	if _root != null:
		_root.queue_free()
	_root = Node3D.new()
	_root.name = "Generated"
	add_child(_root)
	spawns.clear()
	zone_names.clear()

	_box(Vector3(10, -0.5, -40), Vector3(320, 1, 260), Kind.FLOOR)
	_zone_run_track(Vector3(0, 0, 0))
	_zone_vault_lane(Vector3(20, 0, 0))
	_zone_mantle_steps(Vector3(40, 0, 0))
	_zone_wallrun(Vector3(70, 0, 0))
	_zone_climb(Vector3(-25, 0, 0))
	_zone_slide_hill(Vector3(-55, 0, 0))
	_zone_drop_tower(Vector3(-85, 0, 0))
	_zone_kick_yard(Vector3(110, 0, 0))


# ---------------------------------------------------------------- zones

func _zone_run_track(o: Vector3) -> void:
	_spawn(o + Vector3(0, 0, 5), "1 · RUN TRACK")
	_label("Hold forward: momentum raises your top speed", o + Vector3(0, 3.2, 1), 0.9)
	for i in range(1, 13):
		_label("%d m" % (i * 10), o + Vector3(-3.5, 0.6, -i * 10.0), 1.2)
		_box(o + Vector3(-3.5, 0.15, -i * 10.0), Vector3(0.3, 0.3, 0.3), Kind.NEUTRAL)


func _zone_vault_lane(o: Vector3) -> void:
	_spawn(o + Vector3(0, 0, 5), "2 · VAULT LANE")
	_label("Jump at yellow walls to vault without losing speed", o + Vector3(0, 3.2, 1), 0.9)
	for z: float in [-10.0, -18.0, -26.0, -34.0]:
		_box(o + Vector3(0, 0.5, z), Vector3(6, 1.0, 0.4), Kind.PARKOUR)
	_label("Thick block: jump to mantle onto it", o + Vector3(0, 2.4, -42), 0.8)
	_box(o + Vector3(0, 0.5, -45.5), Vector3(6, 1.0, 3), Kind.PARKOUR)
	_box(o + Vector3(0, 0.6, -56.5), Vector3(6, 1.2, 3), Kind.PARKOUR)
	_box(o + Vector3(0, 0.4, -66), Vector3(6, 0.8, 0.4), Kind.PARKOUR)
	_box(o + Vector3(0, 0.55, -74), Vector3(6, 1.1, 0.6), Kind.PARKOUR)


func _zone_mantle_steps(o: Vector3) -> void:
	_spawn(o + Vector3(0, 0, 5), "3 · MANTLE HEIGHTS")
	_label("Jump into a ledge to grab it. Tall ones: run up the wall first", o + Vector3(0, 3.2, 1), 0.9)
	var heights: Array[float] = [1.2, 1.6, 2.0, 2.6, 3.2, 4.0, 4.8]
	for i in heights.size():
		var h := heights[i]
		var z := -10.0 - i * 10.0
		_box(o + Vector3(0, h * 0.5, z - 2.0), Vector3(6, h, 4), Kind.PARKOUR)
		_label("%.1f m" % h, o + Vector3(0, h + 0.6, z), 1.4)
	# A staircase of 1.2 m steps to chain mantles.
	_label("Chain mantles up", o + Vector3(9, 2.0, -6), 0.8)
	for i in range(1, 6):
		var hh := 1.2 * i
		_box(o + Vector3(9, hh * 0.5, -10.0 - (i - 1) * 3.0 - 1.5), Vector3(4, hh, 3), Kind.PARKOUR)


func _zone_wallrun(o: Vector3) -> void:
	_spawn(o + Vector3(0, 0, 5), "4 · WALLRUN")
	_label("Jump into a blue wall at an angle. Jump again to kick off", o + Vector3(0, 3.2, 1), 0.9)
	# Corridor: two parallel walls 5 m apart.
	_box(o + Vector3(-3.0, 3, -20), Vector3(1, 6, 30), Kind.WALLRUN)
	_box(o + Vector3(3.0, 3, -20), Vector3(1, 6, 30), Kind.WALLRUN)
	# Zig-zag panels for wall-to-wall chains, over a pit you shouldn't touch.
	_label("Wall-to-wall: try not to touch the red floor", o + Vector3(0, 3.5, -40), 0.8)
	for i in 4:
		var side := -1.0 if i % 2 == 0 else 1.0
		_box(o + Vector3(side * 3.0, 3.5, -48.0 - i * 9.0), Vector3(1, 7, 8), Kind.WALLRUN)
	_floor_mark(o + Vector3(0, 0, -61.5), Vector2(5, 37), Color(0.85, 0.3, 0.25))
	# Long single wall for practice.
	_box(o + Vector3(12, 3, -40), Vector3(1, 6, 70), Kind.WALLRUN)


func _zone_climb(o: Vector3) -> void:
	_spawn(o + Vector3(0, 0, 5), "5 · WALL CLIMB")
	_label("Jump at a wall head-on to run up it. Jump again to kick back", o + Vector3(0, 3.2, 1), 0.9)
	_box(o + Vector3(0, 6, -17), Vector3(10, 12, 4), Kind.PARKOUR)
	_label("Climb + mantle", o + Vector3(14, 4.2, -15), 0.8)
	_box(o + Vector3(14, 1.75, -19), Vector3(6, 3.5, 4), Kind.PARKOUR)
	_label("3.5 m", o + Vector3(14, 4.2, -16.6), 1.0)
	_box(o + Vector3(14, 2.25, -33), Vector3(6, 4.5, 4), Kind.PARKOUR)
	_label("4.5 m", o + Vector3(14, 5.2, -30.6), 1.0)
	# Climb, kick back, catch the opposite ledge.
	_label("Climb, kick back, grab the ledge behind you", o + Vector3(0, 4.0, -36), 0.8)
	_box(o + Vector3(0, 5, -45), Vector3(8, 10, 2), Kind.PARKOUR)
	_box(o + Vector3(0, 1.5, -38), Vector3(8, 3.0, 2), Kind.PARKOUR)


func _zone_slide_hill(o: Vector3) -> void:
	_spawn(o + Vector3(0, 0, 12), "6 · SLIDE HILL")
	_label("Climb up, then slide down the green ramp", o + Vector3(0, 3.2, 8), 0.9)
	_staircase(o, 4, 2.0, -6.0)
	_box(o + Vector3(0, 5, -10), Vector3(10, 10, 8), Kind.NEUTRAL)
	_ramp(o + Vector3(0, 10, -14), o + Vector3(0, 0, -54), 10.0, Kind.SLIDE)
	_label("Crouch at speed to slide", o + Vector3(0, 12, -12), 0.9)


func _zone_drop_tower(o: Vector3) -> void:
	_spawn(o + Vector3(0, 0, 18), "7 · DROP TOWER")
	_label("Press crouch just before landing to roll", o + Vector3(0, 3.2, 14), 0.9)
	_staircase(o, 6, 2.0, -6.0)
	_box(o + Vector3(0, 6, -10), Vector3(8, 12, 8), Kind.NEUTRAL)
	_box(o + Vector3(5.5, 5.5, -10), Vector3(3, 1, 8), Kind.NEUTRAL)
	_label("6 m drop", o + Vector3(5.5, 7.0, -10), 1.0)
	_label("12 m drop: roll!", o + Vector3(0, 13.5, -14.5), 1.0)


func _zone_kick_yard(o: Vector3) -> void:
	_spawn(o + Vector3(0, 0, 5), "8 · KICK-OFF YARD")
	_label("In the air, kick (F / right mouse) off walls and red targets", o + Vector3(0, 3.2, 1), 0.9)
	for i in 3:
		var z := -14.0 - i * 10.0
		_box(o + Vector3(-2.5, 5, z), Vector3(1.2, 10, 1.2), Kind.NEUTRAL)
		_box(o + Vector3(2.5, 5, z), Vector3(1.2, 10, 1.2), Kind.NEUTRAL)
	for i in 6:
		var p := o + Vector3(-12.0 + (i % 3) * 6.0 - 6.0, 0, -18.0 - floorf(i / 3.0) * 12.0)
		var raised := i >= 3
		if raised:
			_box(p + Vector3(0, 0.75, 0), Vector3(1.2, 1.5, 1.2), Kind.NEUTRAL)
		_dummy(p + Vector3(0, 1.5 if raised else 0.0, 0))


# ---------------------------------------------------------------- helpers

## Steps of `step` meters climbing toward -Z, ending at z_end (relative to o).
func _staircase(o: Vector3, count: int, step: float, z_end: float) -> void:
	for i in range(1, count + 1):
		var h := step * i
		var z := z_end + 3.0 * (count + 1 - i) - 1.5
		_box(o + Vector3(0, h * 0.5, z), Vector3(4, h, 3), Kind.PARKOUR)


func _ramp(top: Vector3, bottom: Vector3, width: float, kind: Kind) -> void:
	var run := bottom.z - top.z
	var rise := top.y - bottom.y
	var length := sqrt(run * run + rise * rise)
	var angle := atan2(rise, absf(run))
	var basis := Basis.from_euler(Vector3(-angle if run < 0.0 else angle, 0, 0))
	var mid := (top + bottom) * 0.5
	var normal := basis.y
	_box_basis(mid - normal * 0.5, Vector3(width, 1, length), basis, kind)


func _box(center: Vector3, size: Vector3, kind: Kind) -> StaticBody3D:
	return _box_basis(center, size, Basis.IDENTITY, kind)


func _box_basis(center: Vector3, size: Vector3, basis: Basis, kind: Kind) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.transform = Transform3D(basis, center)
	body.set_meta("kind", Kind.keys()[kind])
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	mesh.material_override = _material(kind)
	body.add_child(mesh)
	_root.add_child(body)
	return body


## Visual-only colored patch on the floor (no collision, so nothing to trip on).
func _floor_mark(center: Vector3, size: Vector2, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = size
	mesh.mesh = plane
	mesh.position = center + Vector3(0, 0.01, 0)
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("base_color", color)
	mesh.material_override = m
	_root.add_child(mesh)


func _material(kind: Kind) -> ShaderMaterial:
	if not _materials.has(kind):
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("base_color", COLORS[kind])
		_materials[kind] = m
	return _materials[kind]


func _label(text: String, pos: Vector3, size := 1.0) -> void:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	l.pixel_size = 0.004 * size
	l.font_size = 64
	l.outline_size = 12
	l.modulate = Color(1, 1, 1)
	l.outline_modulate = Color(0.08, 0.09, 0.12)
	_root.add_child(l)


func _spawn(pos: Vector3, title: String) -> void:
	spawns.append(Transform3D(Basis.IDENTITY, pos))
	zone_names.append(title)
	_label(title, pos + Vector3(0, 4.2, -4), 1.6)


func _dummy(pos: Vector3) -> void:
	if Engine.is_editor_hint():
		# Show a stand-in in the editor; physics targets are game-only.
		var mesh := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.4
		cm.height = 1.8
		mesh.mesh = cm
		mesh.position = pos + Vector3(0, 0.9, 0)
		_root.add_child(mesh)
		return
	var d: RigidBody3D = DUMMY_SCRIPT.new()
	d.position = pos
	_root.add_child(d)
