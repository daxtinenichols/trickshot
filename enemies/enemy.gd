class_name Enemy
extends CharacterBody3D
## Base for enemies: health, hit zones, kicks, staggers, death and the
## placeholder body. Raider and Mutant add the behaviour.
##
## All behaviour ticks in physics with the fixed tick, from game state only
## (positions, velocities, timers and a seeded RNG), never from the camera
## or anything rendered, so a run plays out the same every time.
##
## The node origin is at the feet. Faces -Z at yaw 0, like the player.
## Looks: a skinned model from enemies/models (built by
## enemies/source/build_enemies.py) posed from the state by EnemyBody, like
## the runner's body. If the model can't load, a placeholder of boxes
## stands in (red body, yellow head).

signal damaged(info: Dictionary)
signal killed(info: Dictionary)

## Movement collision layer: enemies bump into the world and each other,
## but the player runs through them (the player only collides with layer 1).
const BODY_LAYER := 8
## Kick knockdowns: how long the fall and the getting up take (s).
const FALL_TIME := 0.18
const GET_UP_TIME := 0.45
const GRAVITY := 22.0
const HEALTH_BAR_SHADER := preload("res://enemies/health_bar.gdshader")
## Enemy shots roll against how exposed you are (combo_armor.gd).
const ComboArmor := preload("res://enemies/combo_armor.gd")
# By path, not class name (see the project rule on stale class caches).
const BODY_SCRIPT := preload("res://enemies/enemy_body.gd")
const Poses := preload("res://enemies/enemy_poses.gd")
const Difficulty := preload("res://enemies/difficulty.gd")
const HitRig := preload("res://enemies/hit_rig.gd")

## Off: every enemy uses the placeholder look (tools, comparisons).
static var use_models := true

@export var max_health := 100.0
## Turn speed when facing the player (degrees per second).
@export var turn_rate := 360.0
## How long a kick knocks it off balance (s), and how hard it shoves.
@export var kick_stagger := 0.6
@export var kick_shove := 6.0
## A kick's damage before the combo multiplier (the same one shots use).
@export var kick_damage := 35.0
## A kick knocks it flat on its back for this long (s), getting up at the
## end (the last GET_UP_TIME). 0: too heavy to knock over, it only staggers.
@export var knockdown_time := 1.5
## A headshot that doesn't kill makes it flinch for this long (s),
## interrupting whatever it was doing.
@export var headshot_flinch := 0.45
## Seconds it waits after its encounter starts before joining in.
@export var wake_delay := 0.0
## Asleep: it stays put when its encounter starts and only joins in when
## woken by noise (gunshots, if the encounter listens for them) or when you
## come very close.
@export var sleeper := false
## Seconds a body stays down after a kill.
@export var corpse_time := 3.0

var player: Player
var player_health: PlayerHealth
## The EnemyEncounter that owns it (null when used on its own, e.g. tests).
var encounter: Node
## Inactive enemies stand still until their encounter starts.
var active := false
var health := 100.0
var is_dead := false
var yaw := 0.0
var hits_taken := 0
## 0..1, how ready an attack is (drives the glow).
var telegraph := 0.0
## How far it is ducking down (0 standing .. 1 fully ducked).
var duck := 0.0
var seed_value := 1

var _rng := RandomNumberGenerator.new()
var _home := Transform3D.IDENTITY
var _stagger := 0.0
var _dead_time := 0.0
var _wake_left := 0.0
var _hit_root: Node3D
var _hitboxes: Array[EnemyHitbox] = []
var _visual: Node3D
var _pose: Node3D
## The posed model (EnemyBody), or null when the placeholder is shown.
var body: Node3D
## Body-shaped hit zones posed from the state (HitRig), or null for enemies
## that keep simple boxes (drones).
var hit_rig: RefCounted
var _materials: Array[StandardMaterial3D] = []
var _bar: MeshInstance3D
var _bar_mat: ShaderMaterial
var _bar_show := 0.0
var _flash := 0.0
var _prev_xform := Transform3D.IDENTITY
var _killed_by: Dictionary = {}
var _difficulty_applied := false
## Seconds left lying down after a kick (0: on its feet).
var _knocked := 0.0
## The knockdown as drawn (eases toward knockdown_amount). Looks only.
var _knock_shown := 0.0


func _ready() -> void:
	add_to_group("enemies")
	collision_layer = BODY_LAYER
	collision_mask = 1 | BODY_LAYER
	floor_max_angle = deg_to_rad(46.0)
	health = max_health
	yaw = rotation.y
	_home = global_transform if is_inside_tree() else transform
	_rng.seed = seed_value
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = _body_radius()
	cap.height = _body_height()
	shape.shape = cap
	shape.position.y = cap.height * 0.5
	add_child(shape)
	_hit_root = Node3D.new()
	add_child(_hit_root)
	_visual = Node3D.new()
	_visual.top_level = true
	add_child(_visual)
	_pose = Node3D.new()
	_visual.add_child(_pose)
	_build()
	_build_look()
	_build_health_bar()
	_prev_xform = global_transform
	_visual.global_transform = global_transform


# ---------------------------------------------------------------- overrides

func _body_radius() -> float:
	return 0.4


func _body_height() -> float:
	return 1.8


## Build hit zones (with _hitbox) and the placeholder look.
func _build() -> void:
	pass


## Placeholder meshes, used when the model can't load.
func _build_placeholder() -> void:
	pass


## The model file for this enemy ("" = placeholder only).
func _model_path() -> String:
	return ""


## Called once the model has loaded (attach rifles, shields...).
func _on_model() -> void:
	pass


## Poses the model from the state each frame (alive only).
func _animate_body(_delta: float) -> void:
	pass


## Whether the body tips over backward when killed.
func _falls_over() -> bool:
	return true


## Gravity while alive (flyers return 0).
func _gravity() -> float:
	return GRAVITY


## Where the health bar floats (local, standing).
func _bar_height() -> float:
	return 2.15


## One tick of behaviour while alive, active and not staggered.
func _think(_delta: float) -> void:
	pass


## Called when the enemy is reset to its spawn (encounter restart).
func _on_reset() -> void:
	pass


## Called when an attack should stop (stagger, flinch, death).
func _interrupt() -> void:
	pass


# ---------------------------------------------------------------- public

func activate(p: Player) -> void:
	if not _difficulty_applied:
		_difficulty_applied = true
		Difficulty.apply(self)
	player = p
	player_health = PlayerHealth.of(p)
	active = true
	_wake_left = wake_delay


func deactivate() -> void:
	active = false


## Back to its spawn point with full health, standing idle.
func reset_to_home() -> void:
	global_transform = _home
	yaw = _home.basis.get_euler().y
	rotation = Vector3(0, yaw, 0)
	velocity = Vector3.ZERO
	health = max_health
	is_dead = false
	active = false
	hits_taken = 0
	telegraph = 0.0
	duck = 0.0
	_stagger = 0.0
	_knocked = 0.0
	_dead_time = 0.0
	_bar_show = 0.0
	_rng.seed = seed_value
	_set_alive_collision(true)
	visible = true
	if _pose:
		_pose.transform = Transform3D.IDENTITY
	_prev_xform = global_transform
	_on_reset()
	if _hit_root:
		_hit_root.transform = Transform3D.IDENTITY
	pose_hitboxes(0.0)


func set_home(t: Transform3D) -> void:
	_home = t


func is_staggered() -> bool:
	return _stagger > 0.0


func eye_position() -> Vector3:
	return global_position + Vector3.UP * (_head_height() * (1.0 - 0.38 * duck))


func head_position() -> Vector3:
	if hit_rig and _hit_root:
		return _hit_root.global_transform * hit_rig.head_local
	return _hit_root.global_position + Vector3.UP * _head_height() if _hit_root else global_position + Vector3.UP * _head_height()


func _head_height() -> float:
	return 1.62


func distance_to_player() -> float:
	return global_position.distance_to(player.global_position) if player else INF


## Clear line from `from` to the player's chest (world geometry only).
func can_see_player(from := Vector3.INF) -> bool:
	if player == null or not is_inside_tree():
		return false
	var eye := eye_position() if from == Vector3.INF else from
	var q := PhysicsRayQueryParameters3D.create(eye, EnemyMath.player_chest(player), 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func hurt_player(amount: float, kind: StringName) -> void:
	if player_health:
		player_health.take_damage(amount, global_position + Vector3.UP * 1.2, kind)
	if encounter and encounter.has_method("on_player_hurt"):
		encounter.on_player_hurt(self, amount, kind)


## Called by weapons. Returns true if this hit killed it.
func take_hit(info: Dictionary) -> bool:
	if is_dead:
		return false
	hits_taken += 1
	health -= float(info.get("damage", 0.0))
	_flash = 1.0
	_bar_show = 3.0
	damaged.emit(info)
	_damage_number(info)
	if health <= 0.0:
		_die(info)
		return true
	if info.get("zone", &"body") == &"head":
		_stagger = maxf(_stagger, headshot_flinch)
		_interrupt()
	return false


## Kicked (by the player, or anything with a `kick_damage_scale` Callable):
## takes kick damage scaled like shots, and goes flying onto its back (or
## staggers, if it's too heavy to knock over). Returns true if it killed.
func on_kicked(by: Node, dir := Vector3.ZERO) -> bool:
	if is_dead:
		return false
	var d := EnemyMath.horizontal(dir)
	if d.length_squared() < 0.01 and by is Node3D:
		d = EnemyMath.horizontal(global_position - (by as Node3D).global_position)
	d = d.normalized() if d.length_squared() > 1e-6 else -forward()
	if kick_damage > 0.0:
		var scale_fn: Variant = by.get("kick_damage_scale") if by else null
		var k := float((scale_fn as Callable).call()) if scale_fn is Callable and (scale_fn as Callable).is_valid() else 1.0
		var info := {"damage": kick_damage * k, "damage_scale": k, "zone": &"body", "kick": true,
			"position": global_position + Vector3.UP * 1.1, "direction": d, "tags": [&"kick"]}
		if take_hit(info):
			# Killed: the body still flies with the kick.
			velocity = d * kick_shove * 0.6 + Vector3.UP * 2.0
			return true
	velocity = d * kick_shove + Vector3.UP * 3.0
	_stagger = maxf(_stagger, kick_stagger)
	if knockdown_time > 0.0:
		_knocked = maxf(_knocked, knockdown_time)
		_stagger = maxf(_stagger, knockdown_time)
	_flash = 1.0
	_interrupt()
	return false


func is_knocked_down() -> bool:
	return _knocked > 0.0


## How flat it lies (0 standing .. 1 on its back): falls fast, lies there,
## gets up over the last GET_UP_TIME. From the knockdown timer only.
func knockdown_amount() -> float:
	if _knocked <= 0.0:
		return 0.0
	var since := knockdown_time - _knocked
	var fall := clampf(since / FALL_TIME, 0.0, 1.0)
	var rise := clampf(_knocked / GET_UP_TIME, 0.0, 1.0)
	return minf(fall, rise)


# ---------------------------------------------------------------- tick

func _physics_process(delta: float) -> void:
	_prev_xform = global_transform
	tick(delta)
	pose_hitboxes(delta)


## Moves the hit zones to the pose the state calls for (physics tick only).
func pose_hitboxes(delta: float) -> void:
	if hit_rig == null or is_dead or _hit_root == null:
		return
	var pose := _hit_pose(delta)
	if is_staggered() and not is_knocked_down():
		pose["lean"] = float(pose.get("lean", 0.0)) - 0.15
	hit_rig.update(pose)
	# Knocked down: the whole body lies back, like the drawn one.
	var kd := knockdown_amount() if _falls_over() else 0.0
	_hit_root.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5 * kd), Vector3(0, 0.25 * kd, 0))


## The pose for the hit zones (see HitRig.update). Default: standing, legs
## stepping with the speed.
func _hit_pose(delta: float) -> Dictionary:
	var speed := EnemyMath.horizontal(velocity).length()
	return {"speed": speed, "delta": delta, "run": speed / 4.0}


## Body-shaped hit zones from a HitRig profile (call from _build).
func _build_hit_rig(profile: Dictionary, scale := 1.0) -> void:
	hit_rig = HitRig.new()
	hit_rig.build(self, profile, scale)


func tick(delta: float) -> void:
	if is_dead:
		_dead_time += delta
		if _dead_time >= corpse_time:
			visible = false
		return
	if not is_on_floor():
		velocity.y -= _gravity() * delta
	if _knocked > 0.0:
		_knocked = maxf(_knocked - delta, 0.0)
	if _stagger > 0.0:
		_stagger -= delta
		telegraph = 0.0
		# Knocked back: friction until it stops.
		var h := EnemyMath.horizontal(velocity)
		h = h.move_toward(Vector3.ZERO, 14.0 * delta)
		velocity = Vector3(h.x, velocity.y, h.z)
		move_and_slide()
		return
	if _wake_left > 0.0:
		_wake_left -= delta
	if not active or player == null or _wake_left > 0.0:
		var h := EnemyMath.horizontal(velocity).move_toward(Vector3.ZERO, 20.0 * delta)
		velocity = Vector3(h.x, velocity.y, h.z)
		move_and_slide()
		return
	_think(delta)


## Turns toward a world point at turn_rate.
func face_toward(point: Vector3, delta: float, rate_scale := 1.0) -> void:
	var d := EnemyMath.horizontal(point - global_position)
	if d.length_squared() < 1e-4:
		return
	yaw = EnemyMath.turn_yaw(yaw, EnemyMath.yaw_of(d), deg_to_rad(turn_rate * rate_scale) * delta)
	rotation = Vector3(0, yaw, 0)


func forward() -> Vector3:
	return Vector3(-sin(yaw), 0, -cos(yaw))


## Walks toward a horizontal velocity with the given acceleration.
func steer(want: Vector3, accel: float, delta: float) -> void:
	var h := EnemyMath.horizontal(velocity).move_toward(EnemyMath.horizontal(want), accel * delta)
	velocity = Vector3(h.x, velocity.y, h.z)


func _die(info: Dictionary) -> void:
	is_dead = true
	_dead_time = 0.0
	telegraph = 0.0
	velocity = Vector3.ZERO
	_killed_by = info
	_interrupt()
	_set_alive_collision(false)
	killed.emit(info)
	if encounter and encounter.has_method("on_enemy_killed"):
		encounter.on_enemy_killed(self)


func _set_alive_collision(on: bool) -> void:
	collision_layer = BODY_LAYER if on else 0
	collision_mask = (1 | BODY_LAYER) if on else 0
	for b in _hitboxes:
		b.set_enabled(on)


# ---------------------------------------------------------------- building helpers

func _build_look() -> void:
	var path := _model_path() if use_models else ""
	if path != "":
		body = BODY_SCRIPT.new()
		body.name = "Body"
		_pose.add_child(body)
		if body.load_model(path):
			_on_model()
			return
		body.free()
		body = null
	_build_placeholder()


func _hitbox(zone: StringName, shape: Shape3D, pos: Vector3, parent: Node3D = null) -> EnemyHitbox:
	var body := EnemyHitbox.new(self, zone)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.position = pos
	(parent if parent else _hit_root).add_child(body)
	_hitboxes.append(body)
	return body


static func box_shape(size: Vector3) -> BoxShape3D:
	var b := BoxShape3D.new()
	b.size = size
	return b


static func sphere_shape(r: float) -> SphereShape3D:
	var s := SphereShape3D.new()
	s.radius = r
	return s


func _material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.7
	m.emission_enabled = true
	m.emission = Color.BLACK
	_materials.append(m)
	return m


func _mesh_box(size: Vector3, pos: Vector3, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.position = pos
	m.material_override = mat
	(parent if parent else _pose).add_child(m)
	return m


func _mesh_sphere(r: float, pos: Vector3, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	m.mesh = s
	m.position = pos
	m.material_override = mat
	(parent if parent else _pose).add_child(m)
	return m


func _build_health_bar() -> void:
	_bar = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.8, 0.08)
	_bar.mesh = q
	_bar_mat = ShaderMaterial.new()
	_bar_mat.shader = HEALTH_BAR_SHADER
	_bar.material_override = _bar_mat
	_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bar.position = Vector3(0, _bar_height(), 0)
	_bar.visible = false
	_visual.add_child(_bar)


# ---------------------------------------------------------------- presentation

## Draws the body where the physics body is, smoothed between ticks.
func _process(delta: float) -> void:
	if _visual == null:
		return
	var t := Engine.get_physics_interpolation_fraction() if is_physics_processing() else 1.0
	var a := _prev_xform
	var b := global_transform
	_visual.global_transform = Transform3D(Basis(a.basis.get_rotation_quaternion().slerp(b.basis.get_rotation_quaternion(), t)), a.origin.lerp(b.origin, t))
	_flash = move_toward(_flash, 0.0, delta * 6.0)
	var glow := _telegraph_color() * telegraph
	for m in _materials:
		m.emission = Color(1, 1, 1) * _flash + glow
	if body:
		body.set_glow(_flash, _telegraph_color() * telegraph)
	_bar_show = maxf(_bar_show - delta, 0.0)
	_bar.visible = not is_dead and _bar_show > 0.0 and health < max_health
	if _bar.visible:
		_bar_mat.set_shader_parameter("fill", clampf(health / max_health, 0.0, 1.0))
		_bar_mat.set_shader_parameter("alpha", clampf(_bar_show, 0.0, 1.0))
		_bar.position.y = _bar_height() * (1.0 - 0.3 * duck)
	_animate(delta)
	var knocked := not is_dead and _falls_over()
	_knock_shown = lerpf(_knock_shown, knockdown_amount() if knocked else 0.0, 1.0 - exp(-24.0 * delta))
	if body:
		if not is_dead and _knock_shown > 0.4:
			# Flat on its back after a kick.
			body.grounded = false
			body.show_pose(Poses.dead(), delta, 14.0)
		elif not is_dead:
			body.grounded = true
			_animate_body(delta)
		elif body.has_bones():
			body.grounded = false
			body.show_pose(Poses.dead(), delta, 8.0)
	if is_dead and _falls_over():
		_pose.rotation.x = lerpf(_pose.rotation.x, -PI * 0.5, 1.0 - exp(-10.0 * delta))
		_pose.position.y = lerpf(_pose.position.y, 0.25, 1.0 - exp(-10.0 * delta))
	elif knocked and (_knock_shown > 0.001 or _knocked > 0.0):
		_pose.rotation.x = -PI * 0.5 * _knock_shown
		_pose.position.y = 0.25 * _knock_shown


func _telegraph_color() -> Color:
	return Color(1.0, 0.25, 0.1)


## Placeholder pose from the state (ducking, lunging...). Looks only.
func _animate(_delta: float) -> void:
	pass


func _damage_number(info: Dictionary) -> void:
	if not is_inside_tree():
		return
	var head: bool = info.get("zone", &"body") == &"head"
	var l := Label3D.new()
	l.text = "%d" % roundi(float(info.get("damage", 0.0)))
	l.font_size = 72 if head else 48
	l.outline_size = 14
	l.modulate = Color(1.0, 0.85, 0.2) if head else Color(1, 1, 1)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.top_level = true
	add_child(l)
	var at: Vector3 = info.get("position", global_position + Vector3.UP * 1.5)
	# Spread from the hit count, not a random number, so nothing random
	# happens outside the seeded simulation.
	l.global_position = at + Vector3(0.12 * sin(hits_taken * 2.4), 0.25, 0)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "global_position:y", l.global_position.y + 0.7, 0.6)
	tw.tween_property(l, "modulate:a", 0.0, 0.6).set_delay(0.2)
	tw.chain().tween_callback(l.queue_free)
