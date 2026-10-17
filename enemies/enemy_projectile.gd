class_name EnemyProjectile
extends Node3D
## A raider's bullet: a bright, fast slug you can see coming and step out of
## the way of. Flies straight, stops at walls, and hurts the player if it
## passes through their body. Ticks in physics like everything else.

signal hit_player(amount: float)
## Passed close to the player without hitting (a dodge). distance in m.
signal near_miss(distance: float)

const NEAR_MISS_DISTANCE := 1.2

var velocity := Vector3.ZERO
var damage := 18.0
## Extra radius around the bullet (m), on top of the player's body radius.
var radius := 0.1
var life := 3.0
var player: Player
var player_health: PlayerHealth
var shooter: Node3D
var done := false

var _closest := INF
var _mesh: MeshInstance3D
var _mat: StandardMaterial3D
var _prev := Vector3.ZERO


func _ready() -> void:
	top_level = true
	_prev = global_position
	_mesh = MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.09, 0.09, 1.1)
	_mesh.mesh = b
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = Color(1.0, 0.45, 0.15)
	_mesh.material_override = _mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.5, 0.2)
	light.omni_range = 2.5
	light.light_energy = 1.5
	add_child(light)
	_orient()


func _physics_process(delta: float) -> void:
	_prev = global_position
	tick(delta)


func tick(delta: float) -> void:
	if done:
		return
	var from := global_position
	var to := from + velocity * delta
	var end := to
	var blocked := false
	if is_inside_tree():
		var q := PhysicsRayQueryParameters3D.create(from, to, 1)
		var r := get_world_3d().direct_space_state.intersect_ray(q)
		if not r.is_empty():
			end = r.position
			blocked = true
	if player:
		var axis := EnemyMath.player_axis(player)
		var d := EnemyMath.segment_distance(from, end, axis[0], axis[1])
		_closest = minf(_closest, d)
		if d <= Player.RADIUS + radius:
			if player_health:
				player_health.take_damage(damage, shooter.global_position if is_instance_valid(shooter) else from, &"bullet")
			hit_player.emit(damage)
			_finish(end)
			return
	global_position = end
	life -= delta
	if blocked or life <= 0.0:
		_finish(end)


func _finish(at: Vector3) -> void:
	done = true
	global_position = at
	if _closest <= NEAR_MISS_DISTANCE + Player.RADIUS and _closest > Player.RADIUS + radius:
		near_miss.emit(_closest - Player.RADIUS)
	set_physics_process(false)
	queue_free()


func _process(_delta: float) -> void:
	_orient()


func _orient() -> void:
	if _mesh == null or velocity.length_squared() < 0.01:
		return
	var dir := velocity.normalized()
	var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	_mesh.global_basis = Basis.looking_at(dir, up)
	# Smoothed between ticks, trailing behind the bullet's true position.
	var t := Engine.get_physics_interpolation_fraction() if is_physics_processing() else 1.0
	_mesh.global_position = _prev.lerp(global_position, t) - dir * 0.55
