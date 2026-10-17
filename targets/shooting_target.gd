class_name ShootingTarget
extends Node3D
## A practice target shaped like a person: a head hitbox and a body hitbox.
## Can stand still or move (strafe, bob, circle). Health refills if you stop
## shooting it, so kills reward landing shots quickly, and headshots most.
## The node origin is at the target's feet.

signal damaged(info: Dictionary)
signal killed(info: Dictionary)
signal revived

enum Motion { STATIC, STRAFE, BOB, CIRCLE }

const HEAD_RADIUS := 0.18
const BODY_SIZE := Vector3(0.5, 1.35, 0.28)
const HEAD_HEIGHT := 1.62

@export var motion := Motion.STATIC
## How far it travels from its home position (m). Circle: the radius.
@export var amplitude := 3.0
## Top travel speed (m/s).
@export var move_speed := 4.0
@export var max_health := 100.0
## Seconds without being hit before health refills.
@export var regen_delay := 2.5
@export var respawn_time := 2.0

var health := 100.0
var is_dead := false
var hits_taken := 0

var _home := Vector3.ZERO
var _t := 0.0
var _since_hit := 999.0
var _dead_time := 0.0
var _pivot: Node3D
var _head_body: StaticBody3D
var _torso_body: StaticBody3D
var _body_mat: StandardMaterial3D
var _head_mat: StandardMaterial3D
var _flash := 0.0


func _ready() -> void:
	add_to_group("targets")
	health = max_health
	_home = position
	_pivot = Node3D.new()
	add_child(_pivot)
	_body_mat = _material(Color(0.85, 0.22, 0.2))
	_head_mat = _material(Color(1.0, 0.85, 0.3))
	_torso_body = _hitbox(&"body", _box_shape(BODY_SIZE), Vector3(0, BODY_SIZE.y * 0.5 + 0.05, 0))
	_head_body = _hitbox(&"head", _sphere_shape(HEAD_RADIUS), Vector3(0, HEAD_HEIGHT, 0))
	_mesh_box(BODY_SIZE, Vector3(0, BODY_SIZE.y * 0.5 + 0.05, 0), _body_mat)
	_mesh_sphere(HEAD_RADIUS, Vector3(0, HEAD_HEIGHT, 0), _head_mat)
	_mesh_box(Vector3(0.6, 0.05, 0.4), Vector3(0, 0.025, 0), _material(Color(0.2, 0.2, 0.24)))  # base


## Called by weapons. Returns true if this hit killed the target.
func take_hit(info: Dictionary) -> bool:
	if is_dead:
		return false
	hits_taken += 1
	health -= float(info.get("damage", 0.0))
	_since_hit = 0.0
	_flash = 1.0
	damaged.emit(info)
	_damage_number(info)
	if health <= 0.0:
		_die(info)
		return true
	return false


func velocity() -> Vector3:
	return _offset_velocity(_t)


func _physics_process(delta: float) -> void:
	if is_dead:
		_dead_time += delta
		_pivot.rotation.x = lerpf(_pivot.rotation.x, -PI * 0.5, 1.0 - exp(-14.0 * delta))
		if _dead_time >= respawn_time:
			_revive()
		return
	_since_hit += delta
	if _since_hit >= regen_delay:
		health = max_health
	if motion != Motion.STATIC:
		_t += delta
		position = _home + _offset(_t)


func _process(delta: float) -> void:
	_flash = move_toward(_flash, 0.0, delta * 6.0)
	_body_mat.emission = Color(1, 1, 1) * _flash
	_head_mat.emission = Color(1, 1, 1) * _flash


func _offset(t: float) -> Vector3:
	var w := move_speed / maxf(amplitude, 0.01)
	match motion:
		Motion.STRAFE:
			return Vector3(sin(t * w) * amplitude, 0, 0)
		Motion.BOB:
			# Crouch-peek: ducks down out of the head line and back up.
			return Vector3(0, -0.5 * (1.0 - cos(t * w)) * 0.5, 0)
		Motion.CIRCLE:
			return Vector3(cos(t * w) * amplitude - amplitude, 0, sin(t * w) * amplitude)
	return Vector3.ZERO


func _offset_velocity(t: float) -> Vector3:
	if motion == Motion.STATIC or is_dead:
		return Vector3.ZERO
	var dt := 1.0 / 120.0
	return (_offset(t + dt) - _offset(t - dt)) / (2.0 * dt)


func _die(info: Dictionary) -> void:
	is_dead = true
	_dead_time = 0.0
	_set_hitboxes(false)
	killed.emit(info)


func _revive() -> void:
	is_dead = false
	health = max_health
	_since_hit = 999.0
	_pivot.rotation = Vector3.ZERO
	_set_hitboxes(true)
	revived.emit()


func _set_hitboxes(on: bool) -> void:
	for b: StaticBody3D in [_head_body, _torso_body]:
		b.collision_layer = 4 if on else 0


func _hitbox(zone: StringName, shape: Shape3D, pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	body.set_meta("zone", zone)
	body.set_meta("target", self)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.position = pos
	_pivot.add_child(body)
	return body


func _box_shape(size: Vector3) -> BoxShape3D:
	var b := BoxShape3D.new()
	b.size = size
	return b


func _sphere_shape(r: float) -> SphereShape3D:
	var s := SphereShape3D.new()
	s.radius = r
	return s


func _mesh_box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.position = pos
	m.material_override = mat
	_pivot.add_child(m)


func _mesh_sphere(r: float, pos: Vector3, mat: Material) -> void:
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	m.mesh = s
	m.position = pos
	m.material_override = mat
	_pivot.add_child(m)


func _material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.6
	m.emission_enabled = true
	m.emission = Color.BLACK
	return m


func _damage_number(info: Dictionary) -> void:
	if not is_inside_tree():
		return
	var head: bool = info.get("zone", &"body") == &"head"
	var l := Label3D.new()
	l.text = "%d" % roundi(float(info.get("damage", 0.0)))
	l.font_size = 64 if head else 44
	l.outline_size = 12
	l.modulate = Color(1.0, 0.85, 0.2) if head else Color(1, 1, 1)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.top_level = true
	add_child(l)
	var at: Vector3 = info.get("position", global_position + Vector3.UP * 1.5)
	l.global_position = at + Vector3(randf_range(-0.15, 0.15), 0.25, 0)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "global_position:y", l.global_position.y + 0.7, 0.6)
	tw.tween_property(l, "modulate:a", 0.0, 0.6).set_delay(0.2)
	tw.chain().tween_callback(l.queue_free)
