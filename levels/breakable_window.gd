class_name BreakableWindow
extends StaticBody3D
## A glass pane that shatters when kicked, shot, or hit at speed (run or slide
## through it). Re-forms after a few seconds.
## The node origin is the bottom-center of the pane.

const RESET_AFTER := 5.0
const SHARDS := 14

@export var size := Vector2(1.6, 1.2)

var is_broken := false
var _shape: CollisionShape3D
var _mesh: MeshInstance3D


func _ready() -> void:
	add_to_group("breakable")
	add_to_group("windows")
	collision_layer = 1
	collision_mask = 0
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, size.y, 0.05)
	_shape.shape = box
	_shape.position = Vector3(0, size.y * 0.5, 0)
	add_child(_shape)
	_mesh = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(size.x, size.y, 0.03)
	_mesh.mesh = bm
	_mesh.position = _shape.position
	_mesh.material_override = _glass()
	add_child(_mesh)


func on_kicked(_by: Node, dir: Vector3) -> void:
	shatter(dir * 6.0)


## Called when something runs into the pane. Returns true if it broke.
func on_impact(_by: Node, velocity: Vector3) -> bool:
	return shatter(velocity * 0.6)


## Called by weapons.
func on_hit(hit_info: Dictionary) -> void:
	shatter(hit_info.get("direction", Vector3.ZERO) * 4.0)


func shatter(push: Vector3) -> bool:
	if is_broken:
		return false
	is_broken = true
	_shape.set_deferred("disabled", true)
	_mesh.visible = false
	_spawn_shards(push)
	get_tree().create_timer(RESET_AFTER).timeout.connect(_restore)
	return true


func _restore() -> void:
	is_broken = false
	_shape.set_deferred("disabled", false)
	_mesh.visible = true


func _spawn_shards(push: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(global_position)
	var mat := _glass()
	for i in SHARDS:
		var shard := RigidBody3D.new()
		shard.collision_layer = 0
		shard.collision_mask = 1
		var s := Vector3(rng.randf_range(0.1, 0.3), rng.randf_range(0.1, 0.3), 0.02)
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = s
		cs.shape = box
		shard.add_child(cs)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = s
		mi.mesh = bm
		mi.material_override = mat
		shard.add_child(mi)
		var host: Node = get_tree().current_scene if get_tree().current_scene else get_parent()
		host.add_child(shard)
		shard.global_position = global_transform * Vector3(rng.randf_range(-size.x, size.x) * 0.45, rng.randf_range(0.1, size.y - 0.1), 0)
		shard.linear_velocity = push + Vector3(rng.randf_range(-1.5, 1.5), rng.randf_range(0.0, 2.0), rng.randf_range(-1.5, 1.5))
		shard.angular_velocity = Vector3(rng.randf_range(-8, 8), rng.randf_range(-8, 8), rng.randf_range(-8, 8))
		get_tree().create_timer(2.5).timeout.connect(shard.queue_free)


func _glass() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.65, 0.85, 1.0, 0.35)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.metallic = 0.2
	m.roughness = 0.05
	return m
