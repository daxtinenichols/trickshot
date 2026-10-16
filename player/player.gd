class_name Player
extends CharacterBody3D
## First-person parkour controller.
##
## Everything that changes the simulation happens in simulate(), which reads one
## InputFrame per physics tick. Camera effects (bob, tilt, FOV) live in _process
## and never feed back into movement, so the simulation stays deterministic.
##
## The node origin sits at the player's feet.

signal trick(trick_name: StringName, info: Dictionary)
signal state_changed(from: State, to: State)
signal landed(fall_speed: float)
signal respawned

enum State { GROUND, AIR, CROUCH, SLIDE, VAULT, MANTLE, WALLRUN, WALLCLIMB, ROLL, STUN }

const RADIUS := 0.38
const EYE_OFFSET := 0.14
const WALL_PROBE := 0.35

@export var tuning: MovementTuning
## Off for players driven by tests or replays.
@export var use_device_input := true

## Set by tests or replays: the frame to use for the next tick.
var scripted_input: InputFrame = null

var state: State = State.AIR
var state_time := 0.0
## 0..1. Builds while you flow, raises ground top speed.
var momentum := 0.0
var yaw := 0.0
var pitch := 0.0

var _since_floor := 0.0
var _jumped_since_floor := false
var _jump_buffer := 999.0
var _since_crouch_press := 999.0
var _slide_cooldown := 0.0
var _slide_flat_time := 0.0
var _wall_normal := Vector3.ZERO
var _since_wall := 999.0
var _wallrun_used_normal := Vector3.ZERO
var _wall_jump_lock := 0.0
var _climb_used := false
var _climb_start_speed := 0.0
var _kicks_left := 0
var _kicked_ids: Array[int] = []
var _pre_move_velocity := Vector3.ZERO
var _height := 1.8
var _stand_shape: CapsuleShape3D
var _crouch_shape: CapsuleShape3D
var _spawn := Transform3D.IDENTITY

# Scripted vault / mantle path (quadratic bezier).
var _path_from := Vector3.ZERO
var _path_ctrl := Vector3.ZERO
var _path_to := Vector3.ZERO
var _path_time := 0.3
var _path_exit_velocity := Vector3.ZERO

# Smooth automatic turn (after a wall-climb kick).
var _turn_left := 0.0
var _turn_rate := 0.0

# Visual-only camera state.
var _bob_phase := 0.0
var _dip := 0.0
var _roll := 0.0
var _eye_height := 1.66
var _mouse_captured := false

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var collision: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	if tuning == null:
		tuning = MovementTuning.new()
	_stand_shape = CapsuleShape3D.new()
	_stand_shape.radius = RADIUS
	_stand_shape.height = tuning.stand_height
	_crouch_shape = CapsuleShape3D.new()
	_crouch_shape.radius = RADIUS
	_crouch_shape.height = tuning.crouch_height
	_set_height(tuning.stand_height)
	_spawn = global_transform
	yaw = rotation.y
	rotation = Vector3(0.0, yaw, 0.0)
	floor_max_angle = deg_to_rad(46.0)
	floor_snap_length = 0.35
	wall_min_slide_angle = deg_to_rad(5.0)
	_eye_height = _height - EYE_OFFSET
	_kicks_left = tuning.kicks_per_air_time
	if use_device_input and DisplayServer.get_name() != "headless":
		_capture_mouse(true)


# ---------------------------------------------------------------- input / look

func _unhandled_input(event: InputEvent) -> void:
	if not use_device_input:
		return
	if event is InputEventMouseMotion and _mouse_captured:
		var m := event as InputEventMouseMotion
		_look(-m.relative.x * tuning.mouse_sensitivity, -m.relative.y * tuning.mouse_sensitivity)
	elif event is InputEventMouseButton and event.pressed and not _mouse_captured:
		_capture_mouse(true)
	elif event.is_action_pressed("toggle_mouse"):
		_capture_mouse(not _mouse_captured)
	elif event.is_action_pressed("reset"):
		respawn()


func _capture_mouse(on: bool) -> void:
	_mouse_captured = on
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


func _look(d_yaw: float, d_pitch: float) -> void:
	yaw = wrapf(yaw + d_yaw, -PI, PI)
	pitch = clampf(pitch + d_pitch, deg_to_rad(-89.0), deg_to_rad(89.0))


## Point the view somewhere (used by spawns and tests).
func set_view(new_yaw: float, new_pitch := 0.0) -> void:
	yaw = new_yaw
	pitch = new_pitch
	rotation = Vector3(0.0, yaw, 0.0)


# ---------------------------------------------------------------- tick

func _physics_process(delta: float) -> void:
	var f: InputFrame
	if scripted_input != null:
		f = scripted_input
	elif use_device_input:
		f = InputFrame.from_devices()
	else:
		f = InputFrame.new()
	simulate(f, delta)


func simulate(f: InputFrame, delta: float) -> void:
	state_time += delta
	_update_timers(f, delta)
	_apply_auto_turn(delta)
	rotation = Vector3(0.0, yaw, 0.0)
	var wish := wish_direction(f)

	match state:
		State.GROUND: _tick_ground(f, wish, delta)
		State.CROUCH: _tick_crouch(f, wish, delta)
		State.AIR: _tick_air(f, wish, delta)
		State.SLIDE: _tick_slide(f, wish, delta)
		State.VAULT, State.MANTLE: _tick_scripted(delta)
		State.WALLRUN: _tick_wallrun(f, wish, delta)
		State.WALLCLIMB: _tick_wallclimb(f, wish, delta)
		State.ROLL: _tick_roll(f, wish, delta)
		State.STUN: _tick_stun(f, wish, delta)

	_update_momentum(delta)
	if global_position.y < -40.0:
		respawn()


func _update_timers(f: InputFrame, delta: float) -> void:
	_jump_buffer = 0.0 if f.jump_pressed else _jump_buffer + delta
	_since_crouch_press = 0.0 if f.crouch_pressed else _since_crouch_press + delta
	_slide_cooldown = maxf(_slide_cooldown - delta, 0.0)
	_wall_jump_lock = maxf(_wall_jump_lock - delta, 0.0)
	_since_wall += delta
	if state in [State.GROUND, State.CROUCH, State.SLIDE, State.ROLL, State.STUN]:
		_since_floor = 0.0
	else:
		_since_floor += delta


func wish_direction(f: InputFrame) -> Vector3:
	var fwd := forward()
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var w := right * f.move.x + fwd * f.move.y
	return w.limit_length(1.0)


## Horizontal look direction.
func forward() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func horizontal_speed() -> float:
	return MovementMath.horizontal_speed(velocity)


func _change_state(to: State) -> void:
	if to == state:
		return
	var from := state
	state = to
	state_time = 0.0
	state_changed.emit(from, to)


func _trick(trick_name: StringName, info := {}) -> void:
	momentum = minf(momentum + tuning.momentum_trick_bump, 1.0)
	info["speed"] = horizontal_speed()
	trick.emit(trick_name, info)


func _move() -> void:
	_pre_move_velocity = velocity
	move_and_slide()
	if is_on_wall():
		_wall_normal = get_wall_normal()
		_since_wall = 0.0
		_check_wall_impact()


func _check_wall_impact() -> void:
	if state not in [State.GROUND, State.AIR]:
		return
	var n := MovementMath.horizontal(_wall_normal).normalized()
	var into := -MovementMath.horizontal(_pre_move_velocity).dot(n)
	if into > tuning.wall_impact_speed:
		momentum *= 1.0 - tuning.wall_impact_loss
		var h := MovementMath.horizontal(velocity) * (1.0 - tuning.wall_impact_loss * 0.5)
		velocity = Vector3(h.x, velocity.y, h.z)
		trick.emit(&"wall_impact", {"speed": into})


func _update_momentum(delta: float) -> void:
	var speed := horizontal_speed()
	var flowing := speed > tuning.run_speed * 0.85 and state not in [State.STUN, State.CROUCH]
	if flowing:
		momentum = minf(momentum + tuning.momentum_gain * delta, 1.0)
	elif speed < tuning.run_speed * 0.5 and state in [State.GROUND, State.CROUCH, State.STUN]:
		momentum = maxf(momentum - tuning.momentum_decay * delta, 0.0)


# ---------------------------------------------------------------- ground

func _tick_ground(f: InputFrame, wish: Vector3, delta: float) -> void:
	_set_height(tuning.stand_height)
	if _jump_buffer <= tuning.jump_buffer:
		if _try_obstacle(f, true):
			return
		if _try_wall_climb(f, true):
			return
		_jump()
		_tick_air(f, wish, delta)
		return
	if not tuning.vault_requires_jump and _try_obstacle(f, false):
		return
	var speed := horizontal_speed()
	if f.crouch_held and speed >= tuning.slide_min_speed and (f.crouch_pressed or _since_crouch_press < 0.2):
		_start_slide()
		_tick_slide(f, wish, delta)
		return
	if f.crouch_held:
		_change_state(State.CROUCH)
		_tick_crouch(f, wish, delta)
		return

	velocity = MovementMath.apply_friction(velocity, tuning.ground_friction, tuning.stop_speed, delta)
	var wish_speed := MovementMath.ground_wish_speed(tuning.run_speed, tuning.top_speed, momentum) * wish.length()
	velocity = MovementMath.accelerate(velocity, wish.normalized(), wish_speed, tuning.ground_accel, delta)
	velocity.y -= tuning.gravity * delta
	_move()
	if not is_on_floor():
		_change_state(State.AIR)


func _tick_crouch(f: InputFrame, wish: Vector3, delta: float) -> void:
	_set_height(tuning.crouch_height)
	if _jump_buffer <= tuning.jump_buffer and _can_stand():
		_set_height(tuning.stand_height)
		_jump()
		_tick_air(f, wish, delta)
		return
	if not f.crouch_held and _can_stand():
		_change_state(State.GROUND)
		_tick_ground(f, wish, delta)
		return
	velocity = MovementMath.apply_friction(velocity, tuning.ground_friction, tuning.stop_speed, delta)
	velocity = MovementMath.accelerate(velocity, wish.normalized(), tuning.crouch_speed * wish.length(), tuning.ground_accel, delta)
	velocity.y -= tuning.gravity * delta
	_move()
	if not is_on_floor():
		_change_state(State.AIR)


func _jump() -> void:
	velocity.y = tuning.jump_velocity
	_jump_buffer = 999.0
	_jumped_since_floor = true
	_change_state(State.AIR)


# ---------------------------------------------------------------- air

func _tick_air(f: InputFrame, wish: Vector3, delta: float) -> void:
	if f.crouch_held:
		_set_height(tuning.crouch_height)
	elif _can_stand():
		_set_height(tuning.stand_height)

	# Coyote jump: just ran off a ledge.
	if _jump_buffer <= tuning.jump_buffer and not _jumped_since_floor and _since_floor <= tuning.coyote_time:
		_jump()
	elif f.kick_pressed and _try_kick_off():
		pass
	elif _try_obstacle(f, false):
		return
	elif _jump_buffer <= tuning.jump_buffer and _try_wall_climb(f, false):
		return
	elif _jump_buffer <= tuning.jump_buffer and _since_wall <= tuning.wall_jump_grace and _wall_jump_lock <= 0.0:
		_wall_jump(wish)

	velocity.y = maxf(velocity.y - tuning.gravity * delta, -tuning.max_fall_speed)
	velocity = MovementMath.accelerate(velocity, wish.normalized(), tuning.air_wish_speed * wish.length(), tuning.air_accel, delta)
	_move()

	if is_on_floor():
		_land(f)
		return
	if is_on_wall() and _try_start_wallrun(f, wish):
		return
	if is_on_wall() and f.jump_held and _try_wall_climb(f, false):
		return


func _land(f: InputFrame) -> void:
	var fall := -_pre_move_velocity.y
	_kicks_left = tuning.kicks_per_air_time
	_kicked_ids.clear()
	_wallrun_used_normal = Vector3.ZERO
	_climb_used = false
	_jumped_since_floor = false
	_dip = minf(fall * tuning.landing_dip, 0.4)
	landed.emit(fall)
	if fall >= tuning.hard_landing_speed:
		if _since_crouch_press <= tuning.roll_window:
			_start_roll()
		else:
			_start_stun()
		return
	if f.crouch_held and horizontal_speed() >= tuning.slide_min_speed:
		_start_slide()
		return
	_change_state(State.CROUCH if f.crouch_held else State.GROUND)


# ---------------------------------------------------------------- slide

func _start_slide() -> void:
	_set_height(tuning.crouch_height)
	var h := MovementMath.horizontal(velocity)
	if _slide_cooldown <= 0.0 and h.length() > 0.1:
		h += h.normalized() * tuning.slide_boost
		_slide_cooldown = tuning.slide_boost_cooldown
	velocity = Vector3(h.x, velocity.y, h.z)
	_slide_flat_time = 0.0
	_change_state(State.SLIDE)
	_trick(&"slide")


func _tick_slide(f: InputFrame, wish: Vector3, delta: float) -> void:
	_set_height(tuning.crouch_height)
	if _jump_buffer <= tuning.jump_buffer:
		_jump()
		_trick(&"slide_jump")
		_tick_air(f, wish, delta)
		return
	# Friction only ramps up while the slide isn't going downhill, so flat
	# slides fade out but a slope can carry you as far as it goes.
	var downhill := false
	if is_on_floor():
		var n := get_floor_normal()
		var down_slope := Vector3.DOWN - n * Vector3.DOWN.dot(n)
		downhill = down_slope.length() > 0.07 and down_slope.dot(velocity) > 0.0
		velocity += down_slope * tuning.gravity * tuning.slide_slope_gain * delta
	if not downhill:
		_slide_flat_time += delta
	var friction := tuning.slide_friction + tuning.slide_friction_ramp * _slide_flat_time
	velocity = MovementMath.apply_friction(velocity, friction, 0.0, delta)
	velocity = MovementMath.accelerate(velocity, wish.normalized(), 1.0 * wish.length(), 6.0, delta)
	velocity.y -= tuning.gravity * delta
	_move()

	if not is_on_floor():
		_change_state(State.AIR)
	elif horizontal_speed() < tuning.slide_exit_speed:
		_change_state(State.CROUCH if (f.crouch_held or not _can_stand()) else State.GROUND)
	elif not f.crouch_held and _can_stand():
		_change_state(State.GROUND)


# ---------------------------------------------------------------- landing

func _start_roll() -> void:
	_set_height(tuning.crouch_height)
	var h := MovementMath.horizontal(_pre_move_velocity)
	var dir := h.normalized() if h.length() > 0.5 else forward()
	var speed := maxf(h.length(), tuning.run_speed * 0.8) + tuning.roll_boost
	velocity = dir * speed
	_change_state(State.ROLL)
	_trick(&"landing_roll", {"fall_speed": -_pre_move_velocity.y})


func _tick_roll(f: InputFrame, wish: Vector3, delta: float) -> void:
	_set_height(tuning.crouch_height)
	velocity = MovementMath.accelerate(velocity, wish.normalized(), 1.0 * wish.length(), 4.0, delta)
	velocity.y -= tuning.gravity * delta
	_move()
	if not is_on_floor():
		_change_state(State.AIR)
		return
	if state_time >= tuning.roll_time and _can_stand():
		if f.crouch_held and horizontal_speed() >= tuning.slide_min_speed:
			_start_slide()
		else:
			_change_state(State.GROUND)


func _start_stun() -> void:
	var h := MovementMath.horizontal(velocity) * tuning.hard_landing_keep
	velocity = Vector3(h.x, 0.0, h.z)
	momentum = maxf(momentum - 0.5, 0.0)
	_change_state(State.STUN)
	trick.emit(&"hard_landing", {"fall_speed": -_pre_move_velocity.y})


func _tick_stun(_f: InputFrame, _wish: Vector3, delta: float) -> void:
	velocity = MovementMath.apply_friction(velocity, tuning.ground_friction, tuning.stop_speed, delta)
	velocity.y -= tuning.gravity * delta
	_move()
	if state_time >= tuning.hard_landing_stun:
		_change_state(State.GROUND if is_on_floor() else State.AIR)


# ---------------------------------------------------------------- walls

func _wall_ray(n: Vector3, dist := RADIUS + WALL_PROBE) -> Dictionary:
	var from := global_position + Vector3.UP * (_height * 0.5)
	var to := from - MovementMath.horizontal(n).normalized() * dist
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or absf(hit.normal.y) > 0.4:
		return {}
	return hit


func _try_start_wallrun(f: InputFrame, wish: Vector3) -> bool:
	var n := _wall_normal
	if absf(n.y) > 0.3:
		return false
	var h := MovementMath.horizontal(velocity)
	var pre_h := MovementMath.horizontal(_pre_move_velocity)
	var speed := maxf(h.length(), pre_h.length())
	if speed < tuning.wallrun_min_speed or velocity.y < -9.0:
		return false
	if _wallrun_used_normal != Vector3.ZERO and _wallrun_used_normal.dot(n) > 0.9:
		return false
	# Must be travelling along the wall, not straight into it.
	var dir := pre_h.normalized()
	var angle_to_wall := rad_to_deg(asin(clampf(absf(dir.dot(MovementMath.horizontal(n).normalized())), 0.0, 1.0)))
	if angle_to_wall > tuning.wallrun_max_entry_angle:
		return false
	if wish.dot(n) > 0.5:
		return false
	_start_wallrun(n, speed)
	return true


func _start_wallrun(n: Vector3, speed: float) -> void:
	_wall_normal = n
	_wallrun_used_normal = n
	var t := MovementMath.wall_tangent(n, _pre_move_velocity)
	var v := t * maxf(speed, tuning.wallrun_min_speed)
	v.y = maxf(velocity.y, tuning.wallrun_entry_lift)
	velocity = v
	_change_state(State.WALLRUN)
	_trick(&"wallrun")


func _tick_wallrun(f: InputFrame, wish: Vector3, delta: float) -> void:
	_set_height(tuning.stand_height if _can_stand() else tuning.crouch_height)
	if _jump_buffer <= tuning.jump_buffer:
		_wall_jump(wish)
		_tick_air(f, wish, delta)
		return
	if f.kick_pressed and _try_kick_off():
		_change_state(State.AIR)
		return
	var hit := _wall_ray(_wall_normal)
	var leaving := f.crouch_pressed or wish.dot(MovementMath.horizontal(_wall_normal)) > 0.6
	if hit.is_empty() or leaving or state_time >= tuning.wallrun_max_time:
		_since_wall = 0.0
		if leaving:
			velocity += MovementMath.horizontal(_wall_normal).normalized() * 2.0
		_change_state(State.AIR)
		_tick_air(f, wish, delta)
		return
	_wall_normal = hit.normal
	_since_wall = 0.0
	var t := MovementMath.wall_tangent(_wall_normal, velocity)
	var speed := MovementMath.horizontal_speed(velocity)
	if speed < tuning.wallrun_speed:
		speed = minf(speed + tuning.wallrun_accel * delta, tuning.wallrun_speed)
	var vy := velocity.y - tuning.gravity * tuning.wallrun_gravity_scale * delta
	velocity = t * speed - MovementMath.horizontal(_wall_normal).normalized() * 1.5
	velocity.y = vy
	_move()
	if is_on_floor():
		_land(f)
	elif MovementMath.horizontal_speed(velocity) < tuning.wallrun_min_speed * 0.5:
		_change_state(State.AIR)


func _wall_jump(wish: Vector3) -> void:
	var boost_dir := wish.normalized() if wish.length() > 0.1 else forward()
	velocity = MovementMath.wall_jump_velocity(velocity, _wall_normal, tuning.wall_jump_push, tuning.wall_jump_up, boost_dir, tuning.wall_jump_boost)
	_jump_buffer = 999.0
	_wall_jump_lock = 0.2
	_since_wall = 999.0
	_change_state(State.AIR)
	_trick(&"wall_jump")


func _try_wall_climb(f: InputFrame, from_ground: bool) -> bool:
	if _climb_used or f.move.y <= 0.3:
		return false
	var fwd := forward()
	var q := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * (_height * 0.5),
		global_position + Vector3.UP * (_height * 0.5) + fwd * (RADIUS + (0.9 if from_ground else 0.5)), 1)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or absf(hit.normal.y) > 0.3:
		return false
	var n: Vector3 = MovementMath.horizontal(hit.normal).normalized()
	if fwd.dot(-n) < tuning.wall_climb_facing:
		return false
	if not from_ground and velocity.y < -6.0:
		return false
	_wall_normal = n
	_climb_used = true
	_jumped_since_floor = true
	_jump_buffer = 999.0
	var keep := MovementMath.horizontal(velocity).length()
	_climb_start_speed = tuning.wall_climb_speed + minf(keep * 0.1, 1.0)
	velocity = Vector3(0.0, _climb_start_speed, 0.0)
	_change_state(State.WALLCLIMB)
	_trick(&"wall_climb")
	return true


func _tick_wallclimb(f: InputFrame, wish: Vector3, delta: float) -> void:
	_set_height(tuning.stand_height if _can_stand() else tuning.crouch_height)
	if _jump_buffer <= tuning.jump_buffer:
		# Kick off the wall and turn to face away from it.
		var n := MovementMath.horizontal(_wall_normal).normalized()
		velocity = n * tuning.wall_climb_kick_push
		velocity.y = tuning.wall_climb_kick_up
		_jump_buffer = 999.0
		_since_wall = 999.0
		_wall_jump_lock = 0.2
		_start_auto_turn(atan2(-n.x, -n.z), 0.2)
		_change_state(State.AIR)
		_trick(&"wall_climb_kick")
		return
	if _try_obstacle(f, false):
		return
	# Run up the wall at near-constant speed, easing off toward the end.
	var t := clampf(state_time / tuning.wall_climb_time, 0.0, 1.0)
	# Close any gap to the wall first (a climb can start up to ~1 m away).
	var gap_hit := _wall_ray(_wall_normal, RADIUS + 1.3)
	var gap := 0.0
	if not gap_hit.is_empty():
		var center := global_position + Vector3.UP * (_height * 0.5)
		gap = maxf(MovementMath.horizontal(center - gap_hit.position).length() - RADIUS, 0.0)
	var approach := clampf(gap * 12.0, 1.0, 6.0)
	velocity = -MovementMath.horizontal(_wall_normal).normalized() * approach
	velocity.y = _climb_start_speed * (1.0 - 0.6 * t * t)
	_move()
	var hit := _wall_ray(_wall_normal, RADIUS + 1.3)
	if not hit.is_empty():
		_wall_normal = hit.normal
		_since_wall = 0.0
	if is_on_floor():
		_land(f)
	elif hit.is_empty() or state_time >= tuning.wall_climb_time:
		_change_state(State.AIR)


# ---------------------------------------------------------------- vault / mantle

## Looks for something in front to vault over or mantle onto. With
## vault_requires_jump the ground version only fires on a (buffered) jump.
func _try_obstacle(f: InputFrame, from_jump: bool) -> bool:
	var grounded := state in [State.GROUND, State.CROUCH, State.SLIDE, State.ROLL]
	if f.move.y <= 0.2:
		return false
	if grounded and tuning.vault_requires_jump and not from_jump:
		return false
	var info := probe_obstacle(grounded)
	if info.is_empty():
		return false
	if grounded and from_jump == false and info.kind == &"mantle" and info.height > tuning.vault_max_height:
		return false
	if info.kind == &"vault":
		_start_vault(info)
	else:
		_start_mantle(info)
	return true


## Returns {} or {kind, height, top, face_normal, land}.
func probe_obstacle(grounded: bool) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var fwd := forward()
	var feet := global_position
	var speed := horizontal_speed()
	var reach := RADIUS + 0.45 + speed * 0.06
	var max_h := tuning.vault_max_height if grounded else tuning.mantle_air_reach
	if state == State.WALLCLIMB:
		max_h = tuning.mantle_air_reach + 0.3

	# 1. Find a face in front.
	var face := {}
	for h: float in [0.3, 0.8, 1.3, max_h - 0.05]:
		if h > max_h:
			continue
		var q := PhysicsRayQueryParameters3D.create(feet + Vector3.UP * h, feet + Vector3.UP * h + fwd * reach, 1)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and absf(hit.normal.y) < 0.4:
			face = hit
			break
	if face.is_empty():
		return {}
	var n: Vector3 = MovementMath.horizontal(face.normal).normalized()
	if fwd.dot(-n) < 0.5:
		return {}

	# 2. Find the top just behind the face.
	var into: Vector3 = face.position - n * 0.25
	var top_q := PhysicsRayQueryParameters3D.create(
		Vector3(into.x, feet.y + max_h + 0.4, into.z), Vector3(into.x, feet.y - 0.1, into.z), 1)
	top_q.exclude = [get_rid()]
	var top_hit := space.intersect_ray(top_q)
	if top_hit.is_empty() or top_hit.normal.y < 0.7:
		return {}
	var top_y: float = top_hit.position.y
	var height := top_y - feet.y
	if height < tuning.vault_min_height or height > max_h:
		return {}

	# 3. Measure depth: where does the top end?
	var depth := -1.0
	var far_floor_y := feet.y
	var d := 0.35
	while d <= tuning.vault_max_depth + 0.01:
		var p: Vector3 = face.position - n * d
		var dq := PhysicsRayQueryParameters3D.create(Vector3(p.x, top_y + 0.1, p.z), Vector3(p.x, top_y - 4.0, p.z), 1)
		dq.exclude = [get_rid()]
		var dh := space.intersect_ray(dq)
		if dh.is_empty() or dh.position.y < top_y - 0.25:
			depth = d
			far_floor_y = dh.position.y if not dh.is_empty() else feet.y
			break
		d += 0.15

	if depth > 0.0 and height <= tuning.vault_max_height + (0.0 if grounded else 0.25):
		var land: Vector3 = face.position - n * (depth + RADIUS + 0.35)
		land.y = maxf(far_floor_y, feet.y - 3.0) + 0.02
		if _shape_fits(_stand_shape, land):
			return {"kind": &"vault", "height": height, "top": top_y, "face_normal": n, "land": land}

	# Mantle: stand on top, a little way in from the edge.
	var stand_on: Vector3 = face.position - n * (RADIUS + 0.2)
	stand_on.y = top_y + 0.03
	if _shape_fits(_stand_shape, stand_on):
		return {"kind": &"mantle", "height": height, "top": top_y, "face_normal": n, "land": stand_on}
	if _shape_fits(_crouch_shape, stand_on):
		return {"kind": &"mantle", "height": height, "top": top_y, "face_normal": n, "land": stand_on, "crouch": true}
	return {}


func _start_vault(info: Dictionary) -> void:
	var speed := maxf(horizontal_speed(), tuning.run_speed * 0.75)
	var dir: Vector3 = -info.face_normal
	_path_from = global_position
	_path_to = info.land
	var mid := (_path_from + _path_to) * 0.5
	_path_ctrl = Vector3(mid.x, info.top + 0.55 + (info.top - mid.y) * 0.3, mid.z)
	_path_time = tuning.vault_time
	_path_exit_velocity = dir * speed * (1.0 + tuning.vault_speed_bonus)
	_jump_buffer = 999.0
	_change_state(State.VAULT)
	_trick(&"vault", {"height": info.height})


func _start_mantle(info: Dictionary) -> void:
	var dir: Vector3 = -info.face_normal
	var keep := maxf(horizontal_speed() * tuning.mantle_speed_keep, tuning.mantle_min_exit_speed)
	_path_from = global_position
	_path_to = info.land
	_path_ctrl = Vector3(_path_from.x, info.top + 0.35, _path_from.z)
	_path_time = tuning.mantle_time * clampf(0.6 + info.height * 0.3, 0.6, 1.3)
	_path_exit_velocity = dir * keep
	if info.get("crouch", false):
		_set_height(tuning.crouch_height)
	_jump_buffer = 999.0
	_change_state(State.MANTLE)
	_trick(&"mantle", {"height": info.height})


func _tick_scripted(_delta: float) -> void:
	var t := clampf(state_time / _path_time, 0.0, 1.0)
	var a := _path_from.lerp(_path_ctrl, t)
	var b := _path_ctrl.lerp(_path_to, t)
	var prev := global_position
	global_position = a.lerp(b, t)
	velocity = (global_position - prev) / maxf(_delta, 0.0001)
	if t >= 1.0:
		velocity = _path_exit_velocity
		velocity.y = -1.0
		_pre_move_velocity = velocity
		_jumped_since_floor = false
		_change_state(State.AIR)
		_move()
		if is_on_floor():
			_change_state(State.CROUCH if not _can_stand() else State.GROUND)


# ---------------------------------------------------------------- kick-off

func _try_kick_off() -> bool:
	if _kicks_left <= 0:
		return false
	var space := get_world_3d().direct_space_state
	var eye := global_position + Vector3.UP * (_height - EYE_OFFSET)
	var look := -camera.global_transform.basis.z if is_inside_tree() else forward()
	var q := PhysicsRayQueryParameters3D.create(eye, eye + look * tuning.kick_range, 1 | 4)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		# Forgiving fallback: any surface close around the body.
		var sphere := SphereShape3D.new()
		sphere.radius = 0.55
		var sq := PhysicsShapeQueryParameters3D.new()
		sq.shape = sphere
		sq.transform = Transform3D(Basis.IDENTITY, global_position + Vector3.UP * (_height * 0.5) + look * 0.6)
		sq.collision_mask = 1 | 4
		sq.exclude = [get_rid()]
		hit = space.get_rest_info(sq)
		if hit.is_empty():
			return false
		hit["collider"] = instance_from_id(hit.collider_id)
	var collider: Object = hit.get("collider")
	var cid := collider.get_instance_id() if collider else 0
	if cid in _kicked_ids:
		return false
	var n: Vector3 = hit.normal
	velocity = MovementMath.kick_velocity(velocity, n, tuning.kick_push, tuning.kick_up, tuning.kick_keep_tangent)
	_kicks_left -= 1
	_kicked_ids.append(cid)
	_since_wall = 999.0
	var is_target := collider is RigidBody3D
	if is_target:
		(collider as RigidBody3D).apply_central_impulse(-n * tuning.kick_target_impulse + Vector3.UP * 3.0)
		if collider.has_method("on_kicked"):
			collider.on_kicked(self)
	_trick(&"kick_off", {"target": is_target})
	return true


# ---------------------------------------------------------------- shape helpers

func _set_height(h: float) -> void:
	if is_equal_approx(_height, h) and collision.shape != null:
		return
	_height = h
	collision.shape = _stand_shape if h >= tuning.stand_height - 0.01 else _crouch_shape
	(collision.shape as CapsuleShape3D).height = h
	collision.position = Vector3(0.0, h * 0.5, 0.0)


func _shape_fits(shape: CapsuleShape3D, feet: Vector3) -> bool:
	var probe := CapsuleShape3D.new()
	probe.radius = shape.radius - 0.03
	probe.height = shape.height - 0.06
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = probe
	q.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * (shape.height * 0.5 + 0.04))
	q.collision_mask = 1
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func _can_stand() -> bool:
	if _height >= tuning.stand_height - 0.01:
		return true
	return _shape_fits(_stand_shape, global_position)


# ---------------------------------------------------------------- auto turn

func _start_auto_turn(target_yaw: float, duration: float) -> void:
	_turn_left = duration
	_turn_rate = angle_difference(yaw, target_yaw) / duration


func _apply_auto_turn(delta: float) -> void:
	if _turn_left <= 0.0:
		return
	var step := minf(delta, _turn_left)
	yaw = wrapf(yaw + _turn_rate * step, -PI, PI)
	_turn_left -= step


# ---------------------------------------------------------------- respawn

func set_spawn(t: Transform3D) -> void:
	_spawn = t


func respawn(t: Variant = null) -> void:
	if t is Transform3D:
		_spawn = t
	global_position = _spawn.origin
	set_view(_spawn.basis.get_euler().y, 0.0)
	velocity = Vector3.ZERO
	momentum = 0.0
	_set_height(tuning.stand_height)
	_kicks_left = tuning.kicks_per_air_time
	_kicked_ids.clear()
	_wallrun_used_normal = Vector3.ZERO
	_climb_used = false
	_change_state(State.AIR)
	respawned.emit()


# ---------------------------------------------------------------- camera (visual only)

func _process(delta: float) -> void:
	if use_device_input:
		var stick := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
		if stick.length() > 0.15:
			_look(-stick.x * tuning.gamepad_look_speed * delta, -stick.y * tuning.gamepad_look_speed * 0.7 * delta)
	head.rotation = Vector3(pitch, 0.0, 0.0)

	var speed := horizontal_speed()
	var target_eye := _height - EYE_OFFSET
	_eye_height = lerpf(_eye_height, target_eye, 1.0 - exp(-14.0 * delta))
	if state == State.GROUND and speed > 1.0:
		_bob_phase += speed * delta * 1.7
	else:
		_bob_phase = lerpf(_bob_phase, roundf(_bob_phase / PI) * PI, 1.0 - exp(-8.0 * delta))
	var bob := sin(_bob_phase * 2.0) * tuning.head_bob * clampf(speed / tuning.run_speed, 0.0, 1.5)
	_dip = lerpf(_dip, 0.0, 1.0 - exp(-7.0 * delta))
	head.position = Vector3(0.0, _eye_height + bob - _dip, 0.0)

	var target_roll := 0.0
	if state == State.WALLRUN:
		var fwd := forward()
		var right := Vector3(-fwd.z, 0.0, fwd.x)
		var side := right.dot(-MovementMath.horizontal(_wall_normal).normalized())
		target_roll = deg_to_rad(tuning.wallrun_tilt_degrees) * side
	elif state == State.SLIDE:
		target_roll = deg_to_rad(-2.5)
	_roll = lerpf(_roll, target_roll, 1.0 - exp(-10.0 * delta))
	camera.rotation = Vector3(0.0, 0.0, _roll)

	var over := clampf((speed - tuning.run_speed) / maxf(tuning.top_speed + 4.0 - tuning.run_speed, 0.1), 0.0, 1.0)
	camera.fov = lerpf(camera.fov, tuning.base_fov + tuning.speed_fov_bonus * over, 1.0 - exp(-6.0 * delta))


func debug_text() -> String:
	return "%s  %.1fs" % [State.keys()[state], state_time]
