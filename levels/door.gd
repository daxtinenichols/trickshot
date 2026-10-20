class_name KickDoor
extends StaticBody3D
## A door that swings open away from whoever kicks it, then closes again.
## The node origin is the hinge; the panel extends along +X.

const WIDTH := 1.1
const HEIGHT := 2.2
const THICK := 0.08
const OPEN_ANGLE := deg_to_rad(105.0)
const SWING_TIME := 0.18
const CLOSE_AFTER := 5.0

var is_open := false
var _closed_basis: Basis
var _tween: Tween


func _ready() -> void:
	add_to_group("breakable")
	add_to_group("doors")
	collision_layer = 1
	collision_mask = 0
	_closed_basis = transform.basis
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(WIDTH, HEIGHT, THICK)
	shape.shape = box
	shape.position = Vector3(WIDTH * 0.5, HEIGHT * 0.5, 0)
	add_child(shape)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(WIDTH, HEIGHT, THICK)
	mesh.mesh = bm
	mesh.position = shape.position
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.36, 0.22)
	mesh.material_override = mat
	add_child(mesh)


func on_kicked(_by: Node, dir: Vector3) -> void:
	if is_open:
		return
	is_open = true
	# Swing away from the kicker: pick the side the kick pushes toward.
	var normal := global_transform.basis.z
	var sign_dir := -1.0 if dir.dot(normal) > 0.0 else 1.0
	_swing(_closed_basis.rotated(Vector3.UP, OPEN_ANGLE * sign_dir))
	get_tree().create_timer(CLOSE_AFTER, false).timeout.connect(_close)
	# Double doors: the other leaf (meta "mate") goes too.
	var mate: Object = get_meta("mate") if has_meta("mate") else null
	if is_instance_valid(mate) and mate.has_method("on_kicked"):
		mate.on_kicked(_by, dir)


func _close() -> void:
	is_open = false
	_swing(_closed_basis)


func _swing(to: Basis) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(func(t: float) -> void:
		transform.basis = transform.basis.slerp(to, t), 0.0, 1.0, SWING_TIME)
