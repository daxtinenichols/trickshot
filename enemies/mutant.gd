class_name Mutant
extends Enemy
## A melee mutant (a Hollow, in the story). Rushes you, hops over low
## cover, and leaps when it gets close. Keeps you moving: it runs a little
## slower than a good sprint, so carrying your speed keeps you ahead and
## stopping lets it catch you.
##
## It guards its patch rather than hunting you down: it only rushes you
## inside its leash, and gives up a chase that runs long, walking back to
## where it started. (Being chased for real is saved for one boss level.)
##
## Both attacks are telegraphed. Before a leap it crouches and glows (with a
## growl), then jumps at where you are, so a sidestep or a jump makes it
## miss. After landing it is winded for a moment: the best time for a
## headshot. Up close it winds up a swipe you can back out of. A kick
## knocks it back and cancels either attack.

enum State { CHASE, LEAP_WINDUP, LEAP, LAND, SWIPE_WINDUP, SWIPE_RECOVER, RETURN, CHARGE_WINDUP, CHARGE, DAZED }

@export_group("Chase")
## Just below your boosted sprint, above a plain run.
@export var run_speed := 8.6
@export var accel := 26.0
## How fast it can change direction while running (degrees per second).
## Sharp turns and wallruns shake it off.
@export var chase_turn_rate := 200.0
## Jump speed to hop over low cover in its way.
@export var hop_speed := 6.8

@export_group("Territory")
## It rushes you only while you're within this distance of its spawn (m)...
@export var leash_radius := 18.0
## ...and gives up a chase that lasts this long without landing a hit (s).
@export var give_up_time := 7.0
## Walking back, it ignores you for this long (s), then takes you on again
## if you're close (aggro_radius) and inside the leash.
@export var return_calm := 2.0
@export var aggro_radius := 14.0
@export var walk_speed := 3.0

@export_group("Leap")
@export var leap_min := 4.5
@export var leap_max := 10.0
## Crouch-and-glow time before the leap (s).
@export var leap_windup := 0.45
## Flight time (s).
@export var leap_time := 0.6
@export var leap_cooldown := 2.6
## 0 jumps at where you are; 1 at where you'll be by landing.
@export_range(0.0, 1.0, 0.05) var leap_lead := 0.35
## Winded after landing (s): the punish window.
@export var land_recover := 0.9
@export var leap_damage := 30.0
## Reach of the leap from its body center (m).
@export var leap_hit_radius := 0.75

@export_group("Swipe")
@export var swipe_range := 1.9
@export var swipe_windup := 0.38
## How far the swipe reaches once it lands (m).
@export var swipe_reach := 2.4
@export var swipe_damage := 20.0
@export var swipe_recover := 0.55

const HEAD_RADIUS := 0.26
const HEAD_HEIGHT := 1.38
## Hunched forward: the head sits ahead of the body.
const HEAD_FORWARD := -0.28
const BODY_SIZE := Vector3(0.78, 1.05, 0.6)

## Bigger or smaller kinds of mutant (brute, leaper) scale everything:
## body, hit zones, reach. Set before it enters the tree.
var size_scale := 1.0

var state := State.CHASE
var state_time := 0.0
var leaps := 0
var swipes := 0
var hits_landed := 0

var _leap_ready := 0.0
var _leap_hit := false
## Seconds chasing since it last landed a hit.
var _chase_time := 0.0


func _ready() -> void:
	max_health = 140.0
	turn_rate = 540.0
	kick_shove = 8.0
	kick_stagger = 0.75
	super()
	_on_reset()


func _body_radius() -> float:
	return 0.45 * size_scale


func _body_height() -> float:
	return 1.7 * size_scale


func _head_height() -> float:
	return HEAD_HEIGHT * size_scale


func _bar_height() -> float:
	return 1.95 * size_scale


func head_position() -> Vector3:
	if hit_rig:
		return super()
	return global_position + Basis(Vector3.UP, yaw) * (Vector3(0, HEAD_HEIGHT, HEAD_FORWARD) * size_scale)


func _build() -> void:
	_build_hit_rig(HitRig.MUTANT, size_scale)


## The hit zones crouch and lean with the leap and swipe, like the body.
func _hit_pose(delta: float) -> Dictionary:
	var speed := EnemyMath.horizontal(velocity).length()
	var crouch := 0.0
	var lean := 0.0
	match state:
		State.LEAP_WINDUP:
			crouch = telegraph * 0.55
			lean = telegraph * 0.3
		State.LEAP:
			lean = -0.35
		State.LAND:
			crouch = 0.22
			lean = 0.3
		State.SWIPE_WINDUP:
			lean = -telegraph * 0.3
		State.SWIPE_RECOVER:
			lean = 0.25
	return {"speed": speed, "delta": delta, "run": speed / maxf(run_speed, 0.1), "stride": 1.8,
		"crouch": crouch, "lean": lean}


func _build_placeholder() -> void:
	_pose.scale = Vector3.ONE * size_scale
	var skin := _material(Color(0.55, 0.62, 0.3))
	var dark := _material(Color(0.3, 0.22, 0.2))
	var head := _material(Color(1.0, 0.82, 0.28))
	_mesh_box(Vector3(0.24, 0.6, 0.26), Vector3(-0.2, 0.3, 0.05), dark)
	_mesh_box(Vector3(0.24, 0.6, 0.26), Vector3(0.2, 0.3, 0.05), dark)
	_mesh_box(Vector3(0.78, 0.75, 0.6), Vector3(0, 0.95, 0.05), skin)
	# Long arms hanging forward.
	_mesh_box(Vector3(0.18, 0.95, 0.2), Vector3(-0.5, 0.75, -0.18), skin)
	_mesh_box(Vector3(0.18, 0.95, 0.2), Vector3(0.5, 0.75, -0.18), skin)
	_mesh_sphere(HEAD_RADIUS, Vector3(0, HEAD_HEIGHT, HEAD_FORWARD), head)
	_mesh_box(Vector3(0.3, 0.06, 0.06), Vector3(0, HEAD_HEIGHT - 0.06, HEAD_FORWARD - 0.24), dark)


func _telegraph_color() -> Color:
	return Color(1.0, 0.55, 0.05)


func _on_reset() -> void:
	if body == null and _pose:
		_pose.scale = Vector3.ONE * size_scale
	state = State.CHASE
	state_time = 0.0
	_leap_ready = 0.8
	_leap_hit = false
	_chase_time = 0.0


func _interrupt() -> void:
	if state in [State.LEAP_WINDUP, State.SWIPE_WINDUP]:
		_set_state(State.CHASE)
		_leap_ready = maxf(_leap_ready, 1.0)


func is_returning() -> bool:
	return state == State.RETURN and not is_dead


## The player is on its patch.
func _player_in_leash() -> bool:
	return EnemyMath.horizontal(player.global_position - _home.origin).length() <= leash_radius


func is_winded() -> bool:
	return state == State.LAND and not is_dead


# ---------------------------------------------------------------- behaviour

func _think(delta: float) -> void:
	state_time += delta
	_leap_ready = maxf(_leap_ready - delta, 0.0)
	var to_player := EnemyMath.horizontal(player.global_position - global_position)
	var dist := to_player.length()
	var dy := player.global_position.y - global_position.y
	if state != State.RETURN:
		_chase_time += delta
		if (not _player_in_leash() or _chase_time > give_up_time) and state in [State.CHASE, State.LAND, State.SWIPE_RECOVER]:
			_set_state(State.RETURN)
	match state:
		State.RETURN:
			var to_home := EnemyMath.horizontal(_home.origin - global_position)
			if to_home.length() > 0.5:
				steer(to_home.normalized() * walk_speed, accel, delta)
				face_toward(_home.origin, delta, 0.5)
			else:
				steer(Vector3.ZERO, accel, delta)
				face_toward(player.global_position, delta, 0.5)
			if is_on_floor() and is_on_wall() and to_home.length() > 0.5:
				velocity.y = hop_speed
			if state_time >= return_calm and dist <= aggro_radius and _player_in_leash():
				_chase_time = 0.0
				_set_state(State.CHASE)
		State.CHASE:
			_chase(to_player, delta)
			if dist <= swipe_range and absf(dy) < 1.6:
				_set_state(State.SWIPE_WINDUP)
			elif _leap_ready <= 0.0 and dist >= leap_min and dist <= leap_max and is_on_floor() and absf(dy) < 3.0 and can_see_player():
				_set_state(State.LEAP_WINDUP)
				EnemySfx.play_at(self, &"growl")
		State.LEAP_WINDUP:
			steer(Vector3.ZERO, 30.0, delta)
			face_toward(player.global_position, delta)
			telegraph = clampf(state_time / leap_windup, 0.0, 1.0)
			if state_time >= leap_windup:
				_launch()
		State.LEAP:
			if not _leap_hit:
				var axis := EnemyMath.player_axis(player)
				var center := global_position + Vector3.UP * 0.85 * size_scale
				if EnemyMath.point_segment_distance(center, axis[0], axis[1]) <= leap_hit_radius + Player.RADIUS:
					_leap_hit = true
					hits_landed += 1
					_chase_time = 0.0
					hurt_player(leap_damage, &"leap")
			if (state_time > 0.12 and is_on_floor()) or state_time > leap_time * 2.5:
				_set_state(State.LAND)
		State.LAND:
			steer(Vector3.ZERO, 22.0, delta)
			if state_time >= land_recover:
				_set_state(State.CHASE)
		State.SWIPE_WINDUP:
			steer(to_player.normalized() * run_speed * 0.3, accel, delta)
			face_toward(player.global_position, delta)
			telegraph = clampf(state_time / swipe_windup, 0.0, 1.0)
			if state_time >= swipe_windup:
				_swipe(to_player, dy)
				_set_state(State.SWIPE_RECOVER)
		State.SWIPE_RECOVER:
			steer(Vector3.ZERO, accel, delta)
			if state_time >= swipe_recover:
				_set_state(State.CHASE)
	move_and_slide()


func _set_state(s: State) -> void:
	state = s
	state_time = 0.0
	if s not in [State.LEAP_WINDUP, State.SWIPE_WINDUP]:
		telegraph = 0.0


func _chase(to_player: Vector3, delta: float) -> void:
	var h := EnemyMath.horizontal(velocity)
	var cur := h.normalized() if h.length() > 0.5 else forward()
	var want := to_player.normalized() if to_player.length() > 0.01 else cur
	var dir := EnemyMath.turn_dir(cur, want, deg_to_rad(chase_turn_rate) * delta)
	var speed := move_toward(h.length(), run_speed, accel * delta)
	velocity = Vector3(dir.x * speed, velocity.y, dir.z * speed)
	face_toward(global_position + dir, delta)
	# Low cover in the way: hop it.
	if is_on_floor() and is_on_wall() and speed > 1.0:
		velocity.y = hop_speed


func _launch() -> void:
	leaps += 1
	_leap_hit = false
	_leap_ready = leap_cooldown
	var target := player.global_position + EnemyMath.horizontal(player.velocity) * leap_time * leap_lead
	var d := target - global_position
	var v := d / leap_time
	v.y = d.y / leap_time + 0.5 * GRAVITY * leap_time
	velocity = v
	_set_state(State.LEAP)


func _swipe(to_player: Vector3, dy: float) -> void:
	swipes += 1
	EnemySfx.play_at(self, &"swipe")
	var dist := to_player.length()
	if dist <= swipe_reach and absf(dy) < 1.6 and (dist < 0.6 or forward().dot(to_player.normalized()) > 0.4):
		hits_landed += 1
		_chase_time = 0.0
		hurt_player(swipe_damage, &"swipe")


# ---------------------------------------------------------------- presentation

func _model_path() -> String:
	return "res://enemies/models/mutant.glb"


func _on_model() -> void:
	body.scale = Vector3.ONE * size_scale
	body.show_part("Armor", false)


func _animate_body(delta: float) -> void:
	var speed := EnemyMath.horizontal(velocity).length()
	body.step(speed, 2.2, delta)
	var pose: Dictionary
	body.grounded = state != State.LEAP
	match state:
		State.LEAP_WINDUP:
			pose = Poses.coil(telegraph)
		State.LEAP:
			pose = Poses.pounce()
		State.LAND:
			pose = Poses.winded(sin(state_time * 9.0))
		State.SWIPE_WINDUP:
			pose = Poses.swipe(telegraph)
		State.SWIPE_RECOVER:
			pose = Poses.swipe(-clampf(state_time / 0.12, 0.0, 1.0))
		_:
			pose = Poses.blend(Poses.hunch(), Poses.lope(body.phase, speed / run_speed), clampf(speed, 0.0, 1.0))
	if is_staggered():
		pose = Poses.add(pose, Poses.flinch())
	body.show_pose(pose, delta, 22.0 if state in [State.SWIPE_RECOVER, State.LEAP] else 14.0)


func _animate(_delta: float) -> void:
	if is_dead or body != null:
		return
	var crouch := 0.0
	var lean := 0.25
	match state:
		State.LEAP_WINDUP:
			crouch = telegraph * 0.35
			lean = 0.25 + telegraph * 0.3
		State.LEAP:
			lean = -0.2
		State.LAND:
			crouch = 0.25
			lean = 0.6
		State.SWIPE_WINDUP:
			lean = 0.25 - telegraph * 0.4
		State.SWIPE_RECOVER:
			lean = 0.5
	_pose.position.y = -crouch
	_pose.rotation.x = -lean
