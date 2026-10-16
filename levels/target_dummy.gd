class_name TargetDummy
extends RigidBody3D
## Kickable practice target. Flashes when kicked and returns home a few
## seconds after being knocked away.

const HOME_DELAY := 4.0

var _home: Transform3D
var _knocked_for := -1.0
var _mesh: MeshInstance3D
var _mat: StandardMaterial3D


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 4
	mass = 40.0
	_home = global_transform
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)
	_mesh = MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.4
	cm.height = 1.8
	_mesh.mesh = cm
	_mesh.position.y = 0.9
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.95, 0.33, 0.25)
	_mesh.material_override = _mat
	add_child(_mesh)


func on_kicked(_by: Node) -> void:
	_knocked_for = 0.0
	_mat.albedo_color = Color(1.0, 0.85, 0.3)


func _physics_process(delta: float) -> void:
	if _knocked_for < 0.0:
		return
	_knocked_for += delta
	if _knocked_for > 0.15:
		_mat.albedo_color = Color(0.95, 0.33, 0.25)
	if _knocked_for >= HOME_DELAY:
		_knocked_for = -1.0
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		global_transform = _home
