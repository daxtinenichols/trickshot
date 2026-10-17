extends "res://enemies/enemy.gd"
## A gun drone (the Ward's): a small quadcopter that hovers over its patch,
## circles you at range and fires short bursts. One hit anywhere drops it,
## but it's small, always in the air and always moving: the target that
## rewards air shots, wallrun shots and long shots most.
##
## Every burst is telegraphed like a raider's shot: a red laser tracks you
## from the gun while the lens glows, then turns white and stops tracking
## (with a beep) just before the burst, so a sideways move dodges it. It
## shares the encounter's aiming limit with raiders. The lens is the
## "head" zone (a headshot), the frame is the body.
##
## It guards its patch (leash_radius around where it spawned) like every
## enemy except the final level's: it never follows you off it.
##
## Shot down, it falls, spinning, and breaks apart on the ground. A kick
## (jump and kick it, or kick off a wall into it) knocks it tumbling away.

enum State { PATROL, AIM, BURST, RECOVER }

@export_group("Flight")
## Height it hovers at above its spawn point (m).
@export var hover_height := 4.0
@export var fly_speed := 6.5
@export var accel := 9.0
## The distance it keeps from you while circling (m)...
@export var preferred_range := 13.0
## ...how fast it circles you (m/s)...
@export var orbit_speed := 3.5
## ...and it never goes further than this from its spawn (m).
@export var leash_radius := 16.0

@export_group("Shooting")
@export var windup := 0.85
@export var lock_time := 0.3
@export var aim_track_rate := 70.0
@export var shots_per_burst := 3
@export var burst_gap := 0.11
@export var recover_time := 0.6
## Wait between bursts (s).
@export var between_bursts := 1.6
@export var bullet_speed := 34.0
@export var bullet_damage := 9.0
@export var max_range := 30.0

const LENS_RADIUS := 0.2
const BODY_SIZE := Vector3(0.95, 0.32, 0.95)
## Center height above the node origin (the node origin is at the bottom
## of its collision capsule, like every enemy).
const CENTER := 0.45
const LENS := Vector3(0, CENTER, -0.28)
const GUN := Vector3(0, CENTER - 0.16, -0.36)

var state := State.PATROL
var state_time := 0.0
var aim_dir := Vector3.FORWARD
var bursts := 0
var shots_fired := 0

var _shot_timer := 0.0
var _burst_left := 0
var _orbit := 1.0
var _orbit_flip := 0.0
var _has_token := false
var _laser: MeshInstance3D
var _laser_mat: StandardMaterial3D
var _spin := 0.0
var _crashed := false
var _bank := Vector3.ZERO


func _ready() -> void:
	max_health = 16.0
	turn_rate = 220.0
	kick_shove = 9.0
	kick_stagger = 0.9
	headshot_flinch = 0.3
	corpse_time = 2.5
	super()
	_on_reset()


func _body_radius() -> float:
	return 0.45


func _body_height() -> float:
	return 0.9


func _head_height() -> float:
	return CENTER


func _bar_height() -> float:
	return CENTER + 0.55


func _gravity() -> float:
	return 0.0


func _falls_over() -> bool:
	return false


func head_position() -> Vector3:
	return global_position + Basis(Vector3.UP, yaw) * LENS


func gun_position() -> Vector3:
	return global_position + Basis(Vector3.UP, yaw) * GUN


func is_aiming() -> bool:
	return state == State.AIM and not is_dead


func is_locked() -> bool:
	return is_aiming() and state_time >= windup - lock_time


func _build() -> void:
	_hitbox(&"body", box_shape(BODY_SIZE), Vector3(0, CENTER, 0))
	_hitbox(&"head", sphere_shape(LENS_RADIUS), LENS)
	_laser = MeshInstance3D.new()
	var lb := BoxMesh.new()
	lb.size = Vector3.ONE
	_laser.mesh = lb
	_laser_mat = StandardMaterial3D.new()
	_laser_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_laser_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_laser.material_override = _laser_mat
	_laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_laser.top_level = true
	_laser.visible = false
	add_child(_laser)


func _build_placeholder() -> void:
	var shell := _material(Color(0.8, 0.78, 0.7))
	var dark := _material(Color(0.15, 0.15, 0.16))
	var lens := _material(Color(1.0, 0.82, 0.28))
	_mesh_box(Vector3(0.36, 0.18, 0.44), Vector3.ZERO, shell)
	for i in 4:
		var a := PI * 0.25 + PI * 0.5 * i
		_mesh_box(Vector3(0.16, 0.03, 0.16), Vector3(cos(a) * 0.42, 0.06, sin(a) * 0.42), dark)
	_mesh_sphere(0.09, LENS - Vector3(0, CENTER, 0), lens)


func _model_path() -> String:
	return "res://enemies/models/drone.glb"


func _on_reset() -> void:
	state = State.PATROL
	state_time = 0.0
	_release_token()
	_burst_left = 0
	_crashed = false
	_spin = 0.0
	_orbit = 1.0 if seed_value % 2 == 0 else -1.0
	_orbit_flip = _rng.randf_range(3.0, 6.0)
	_shot_timer = _rng.randf_range(0.8, 1.6)
	if _pose:
		# The look pivots around the drone's middle.
		_pose.transform = Transform3D(Basis.IDENTITY, Vector3(0, CENTER, 0))


func _interrupt() -> void:
	if state in [State.AIM, State.BURST]:
		state = State.RECOVER
		state_time = 0.0
		_shot_timer = maxf(_shot_timer, 0.6)
	telegraph = 0.0
	_release_token()


# ---------------------------------------------------------------- tick

func tick(delta: float) -> void:
	if is_dead:
		_fall(delta)
		return
	if _stagger > 0.0:
		# Knocked tumbling: drifts and slows in the air.
		_stagger -= delta
		telegraph = 0.0
		velocity = velocity.move_toward(Vector3.ZERO, 8.0 * delta)
		move_and_slide()
		return
	if _wake_left > 0.0:
		_wake_left -= delta
	if not active or player == null or _wake_left > 0.0:
		# Hover in place, drifting back home.
		_fly_to(_hover_point(), delta, 0.5)
		move_and_slide()
		return
	_think(delta)


func _think(delta: float) -> void:
	state_time += delta
	_orbit_flip -= delta
	if _orbit_flip <= 0.0:
		_orbit = -_orbit
		_orbit_flip = _rng.randf_range(3.0, 6.0)
	var sees := can_see_player(gun_position())
	var dist := global_position.distance_to(player.global_position)
	face_toward(player.global_position, delta)
	match state:
		State.PATROL:
			_fly_to(_circle_point(), delta)
			_shot_timer -= delta
			if _shot_timer <= 0.0 and sees and dist <= max_range and _take_token():
				state = State.AIM
				state_time = 0.0
				aim_dir = (EnemyMath.player_chest(player) - gun_position()).normalized()
		State.AIM:
			# Slows to a hover to aim.
			_fly_to(global_position, delta, 0.6)
			telegraph = clampf(state_time / windup, 0.0, 1.0)
			if state_time < windup - lock_time:
				var want := (EnemyMath.player_chest(player) - gun_position()).normalized()
				aim_dir = EnemyMath.turn_dir(aim_dir, want, deg_to_rad(aim_track_rate) * delta)
			elif state_time - delta < windup - lock_time:
				EnemySfx.play_at(self, &"lock", -4.0)
			if state_time >= windup:
				state = State.BURST
				state_time = 0.0
				_burst_left = shots_per_burst
				bursts += 1
		State.BURST:
			_fly_to(global_position, delta, 0.6)
			telegraph = 1.0
			if state_time >= burst_gap * (shots_per_burst - _burst_left):
				_fire()
				_burst_left -= 1
				if _burst_left <= 0:
					state = State.RECOVER
					state_time = 0.0
					telegraph = 0.0
					_release_token()
		State.RECOVER:
			_fly_to(_circle_point(), delta, 0.6)
			if state_time >= recover_time:
				state = State.PATROL
				state_time = 0.0
				_shot_timer = between_bursts
	move_and_slide()


## Its station: hover_height over the spawn point.
func _hover_point() -> Vector3:
	return _home.origin + Vector3.UP * hover_height


## A point on a circle around you at preferred range, a little ahead in the
## orbit direction, kept on its patch and at hover height.
func _circle_point() -> Vector3:
	var station := _hover_point()
	var from_player := EnemyMath.horizontal(global_position - player.global_position)
	if from_player.length_squared() < 0.01:
		from_player = -forward()
	var r := from_player.normalized()
	var side := r.cross(Vector3.UP) * _orbit
	var want := player.global_position + r * preferred_range + side * orbit_speed
	var off := EnemyMath.horizontal(want - station)
	if off.length() > leash_radius:
		off = off.normalized() * leash_radius
	return Vector3(station.x + off.x, station.y, station.z + off.z)


func _fly_to(point: Vector3, delta: float, speed_scale := 1.0) -> void:
	var to := point - global_position
	var want := to.normalized() * minf(fly_speed * speed_scale, to.length() * 2.0) if to.length() > 0.05 else Vector3.ZERO
	# A gentle bob so it never sits dead still.
	want.y += 0.35 * sin(state_time * 2.3 + seed_value)
	velocity = velocity.move_toward(want, accel * delta)


func _fall(delta: float) -> void:
	if _crashed:
		_dead_time += delta
		if _dead_time >= corpse_time:
			visible = false
		return
	velocity.y -= GRAVITY * delta
	velocity.x = move_toward(velocity.x, 0.0, 2.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 2.0 * delta)
	# A dead drone keeps its body collision just for the fall (it never
	# blocks the player: they don't collide with layer 8 anyway).
	var c := move_and_collide(velocity * delta)
	if c or global_position.y < _home.origin.y - 60.0:
		_crashed = true
		_dead_time = 0.0
		EnemySfx.play_at(self, &"crash", -2.0)


func _set_alive_collision(on: bool) -> void:
	super(on)
	if not on:
		# Falls against the world only.
		collision_mask = 1


func _fire() -> void:
	shots_fired += 1
	var b := EnemyProjectile.new()
	b.velocity = aim_dir * bullet_speed
	b.damage = bullet_damage
	b.player = player
	b.player_health = player_health
	b.shooter = self
	b.hit_player.connect(func(amount: float) -> void:
		if encounter and encounter.has_method("on_player_hurt"):
			encounter.on_player_hurt(self, amount, &"bullet"))
	if encounter and encounter.has_method("on_bullet"):
		encounter.on_bullet(b)
	var parent: Node = encounter if encounter else get_parent()
	parent.add_child(b)
	b.global_position = gun_position()
	EnemySfx.play_at(self, &"drone_shot", -4.0)


func _take_token() -> bool:
	if _has_token:
		return true
	if encounter and encounter.has_method("request_aim"):
		_has_token = encounter.request_aim(self)
	else:
		_has_token = true
	return _has_token


func _release_token() -> void:
	if _has_token and encounter and encounter.has_method("release_aim"):
		encounter.release_aim(self)
	_has_token = false


# ---------------------------------------------------------------- presentation

func _animate(delta: float) -> void:
	_draw_laser()
	if is_dead:
		if not _crashed:
			_spin += delta * 9.0
			_pose.rotation = Vector3(0.6, _spin, 0.4)
		elif body:
			# Broken on the ground: lying tilted, rotors stopped.
			_pose.rotation.x = lerpf(_pose.rotation.x, 0.9, 1.0 - exp(-12.0 * delta))
			_pose.position.y = lerpf(_pose.position.y, 0.18, 1.0 - exp(-12.0 * delta))
		return
	# Banks into its motion; a kick sends it tumbling.
	var local_v := Basis(Vector3.UP, yaw).inverse() * velocity
	_bank = _bank.lerp(Vector3(local_v.z * 0.06, 0.0, -local_v.x * 0.06), 1.0 - exp(-6.0 * delta))
	var tumble := 0.0
	if is_staggered():
		_spin += delta * 14.0
		tumble = _spin
	_pose.rotation = Vector3(_bank.x + tumble * 0.4, 0.0, _bank.z + tumble)


func _animate_body(delta: float) -> void:
	var spin_rate := 50.0 if not is_dead else 0.0
	for i in 4:
		var rotor: Node3D = body.parts.get("Rotor%d" % i)
		if rotor:
			rotor.rotate_object_local(Vector3.UP, spin_rate * delta * (1.0 if i % 2 == 0 else -1.0))


func _draw_laser() -> void:
	if not is_aiming() or not is_inside_tree():
		_laser.visible = false
		return
	var from := gun_position()
	var to := from + aim_dir * 80.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if not r.is_empty():
		to = r.position
	var len := from.distance_to(to)
	if len < 0.05:
		_laser.visible = false
		return
	var locked := is_locked()
	var w := 0.03 if locked else 0.016
	var up := Vector3.UP if absf(aim_dir.y) < 0.99 else Vector3.RIGHT
	_laser.global_transform = Transform3D(Basis.looking_at(aim_dir, up) * Basis.from_scale(Vector3(w, w, len)), (from + to) * 0.5)
	_laser_mat.albedo_color = Color(1.0, 0.95, 0.9, 0.95) if locked else Color(1.0, 0.12, 0.05, 0.25 + 0.5 * telegraph)
	_laser.visible = true
