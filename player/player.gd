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

enum State { GROUND, AIR, CROUCH, SLIDE, VAULT, MANTLE, WALLRUN, WALLCLIMB, ROLL, STUN, PRONE, PRONE_SLIDE }

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

var _since_floor := 999.0
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
var _ground_time := 0.0
## Seconds between the jump press and touching down (-1 = no early press).
var _land_press_age := -1.0
var _wallrun_time_limit := 1.0
var _wallrun_gravity := 0.3
var _kicks_left := 0
var _kicked_ids: Array[int] = []
var _pre_move_velocity := Vector3.ZERO
var _height := 1.8
var _stand_shape: CapsuleShape3D
var _crouch_shape: CapsuleShape3D
var _prone_shape: CapsuleShape3D
var _crouch_hold := 0.0
var _diving := false
# Rotation done in the air since takeoff (radians, unwrapped).
var _air_yaw := 0.0
var _air_pitch := 0.0
## Side-flip roll (radians, unwrapped, + = to the right).
var _air_roll := 0.0
var _spins_done := 0
var _flips_done := 0
var _sideflips_done := 0
## Lean, -1 (left) .. 1 (right), eased toward the input.
var lean := 0.0
## How far you've pulled the view down past straight down on the ground.
var _ground_flick := 0.0
## Where the roll's visual forward spin starts (radians, view pitch).
var _roll_spin_from := 0.0
var _spawn := Transform3D.IDENTITY

# Scripted vault / mantle path (quadratic bezier).
var _path_from := Vector3.ZERO
var _path_ctrl := Vector3.ZERO
var _path_to := Vector3.ZERO
var _path_time := 0.3
var _path_exit_velocity := Vector3.ZERO

# Smooth automatic turn (quick turn).
var _turn_left := 0.0
var _turn_rate := 0.0

# Visual-only camera state.
var _bob_phase := 0.0
var _dip := 0.0
var _roll := 0.0
var _air_roll_view := 0.0
var _peek := 0.0
var _eye_height := 1.66
# Weapon recoil: a visual view kick on top of the aim, so flips/spins
# (which read `pitch`) are never affected by shooting.
var _kick_pitch := 0.0
var _kick_yaw := 0.0
var _kick_recovery := 12.0

## Set by the held weapon: 0 = hip, 1 = fully aimed down sights.
var invert_y := false
## Multiplies look speed while aiming down sights (player setting).
var ads_sensitivity := 1.0
var aim_zoom := 0.0
var aim_fov := 62.0
var weapon: Node

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
	_prone_shape = CapsuleShape3D.new()
	_prone_shape.radius = RADIUS
	_prone_shape.height = tuning.prone_height
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
		capture_mouse(true)
	weapon = get_node_or_null("Head/Camera3D/Pistol")
	if weapon and weapon.has_method("setup"):
		weapon.setup(self)


# ---------------------------------------------------------------- input / look

func _unhandled_input(event: InputEvent) -> void:
	if not use_device_input:
		return
	if event is InputEventMouseMotion and is_mouse_captured():
		var m := event as InputEventMouseMotion
		var sens := tuning.mouse_sensitivity * aim_sensitivity_scale()
		_look(-m.relative.x * sens, -m.relative.y * sens * (-1.0 if invert_y else 1.0))
	elif event is InputEventMouseButton and event.pressed and not is_mouse_captured():
		capture_mouse(true)
	elif event.is_action_pressed("reset"):
		respawn()


func is_mouse_captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


## Aiming zooms in; scale look speed by the same amount so aim feels the same.
func aim_sensitivity_scale() -> float:
	var hip := tan(deg_to_rad(tuning.base_fov) * 0.5)
	var ads := tan(deg_to_rad(aim_fov) * 0.5)
	return lerpf(1.0, ads / hip * ads_sensitivity, aim_zoom)


func capture_mouse(on: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


## Turns the view. In the air the pitch is free, so pulling the view all the
## way over is a flip and turning a full circle is a 360. On the ground the
## pitch is clamped as usual.
func _look(d_yaw: float, d_pitch: float) -> void:
	yaw = wrapf(yaw + d_yaw, -PI, PI)
	if state == State.AIR:
		if absf(wrapf(pitch, -PI, PI)) > deg_to_rad(75.0):
			d_pitch *= tuning.flip_look_gain
		pitch += d_pitch
		_air_yaw += d_yaw
		_air_pitch += d_pitch
	else:
		var raw := pitch + d_pitch
		if raw < deg_to_rad(-89.0) and d_pitch < 0.0:
			_ground_flick += deg_to_rad(-89.0) - raw
		pitch = clampf(raw, deg_to_rad(-89.0), deg_to_rad(89.0))


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
	if f.turn_pressed:
		_quick_turn()
	_apply_auto_turn(delta)
	rotation = Vector3(0.0, yaw, 0.0)
	lean = move_toward(lean, clampf(f.lean, -1.0, 1.0), tuning.lean_speed * delta)
	var wish := wish_direction(f)
	if _ground_flick >= deg_to_rad(tuning.ground_roll_flick) and state in [State.GROUND, State.CROUCH, State.SLIDE] \
			and horizontal_speed() > 1.0 and _can_stand():
		_ground_flick = 0.0
		pitch = 0.0
		_start_roll(1.0, &"ground_roll", deg_to_rad(-89.0), MovementMath.horizontal(velocity), 0.0)
	_ground_flick = maxf(_ground_flick - tuning.ground_roll_flick_decay * delta, 0.0)

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
		State.PRONE: _tick_prone(f, wish, delta)
		State.PRONE_SLIDE: _tick_prone_slide(f, wish, delta)

	_update_momentum(delta)
	if global_position.y < -40.0:
		respawn()


func _update_timers(f: InputFrame, delta: float) -> void:
	_jump_buffer = 0.0 if f.jump_pressed else _jump_buffer + delta
	_since_crouch_press = 0.0 if f.crouch_pressed else _since_crouch_press + delta
	_slide_cooldown = maxf(_slide_cooldown - delta, 0.0)
	_wall_jump_lock = maxf(_wall_jump_lock - delta, 0.0)
	_since_wall += delta
	_crouch_hold = _crouch_hold + delta if f.crouch_held else 0.0
	if state in [State.GROUND, State.CROUCH, State.SLIDE, State.ROLL, State.STUN, State.PRONE, State.PRONE_SLIDE]:
		_since_floor = 0.0
		_ground_time += delta
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
	if to == State.AIR:
		_air_yaw = 0.0
		_air_pitch = 0.0
		_air_roll = 0.0
		_spins_done = 0
		_flips_done = 0
		_sideflips_done = 0
	elif from == State.AIR:
		_settle_pitch()
		# A dive ends when you touch anything (landing reads it before this).
		_diving = false
	state_changed.emit(from, to)


## Brings a free (flipped) pitch back into the normal range.
func _settle_pitch() -> void:
	pitch = clampf(wrapf(pitch, -PI, PI), deg_to_rad(-89.0), deg_to_rad(89.0))


## Upside down or tipped too far to land on your feet?
## Only counts once a flip was actually started (90+ degrees of rotation in
## this air time), so looking straight down to aim while dropping is safe.
func _landing_crashed() -> bool:
	return absf(_air_pitch) >= deg_to_rad(90.0) and absf(wrapf(pitch, -PI, PI)) > deg_to_rad(tuning.crash_pitch)


## Rolled over sideways (a side flip let go of halfway)?
func _landing_tipped() -> bool:
	return absf(wrapf(_air_roll, -PI, PI)) > deg_to_rad(tuning.side_crash_degrees)


## Landing tucked forward (view pointing down or further over, partway
## into a front flip) turns into a roll that keeps your speed.
func _landing_tucked(fall: float) -> bool:
	var p := rad_to_deg(wrapf(pitch, -PI, PI))
	if p > -50.0 or p < -175.0 or _air_pitch >= 0.0:
		return false
	return fall >= tuning.flip_roll_min_fall or _air_pitch <= deg_to_rad(-90.0)


## Side flips: hold lean in the air to roll. Let go near level and you
## settle upright; let go halfway and you land tipped (a crash).
func _tick_air_roll(f: InputFrame, delta: float) -> void:
	if absf(f.lean) > 0.3:
		_air_roll += signf(f.lean) * deg_to_rad(tuning.side_flip_speed) * delta
		return
	var level := roundf(_air_roll / TAU) * TAU
	if absf(_air_roll - level) <= deg_to_rad(tuning.side_settle_degrees):
		_air_roll = move_toward(_air_roll, level, deg_to_rad(tuning.side_flip_speed) * 0.5 * delta)


func _check_air_rotation() -> void:
	var full := TAU - deg_to_rad(tuning.rotation_tolerance)
	while absf(_air_yaw) >= full + TAU * _spins_done:
		_spins_done += 1
		_trick(StringName("spin_%d" % (360 * _spins_done)), {"turns": _spins_done})
	while absf(_air_pitch) >= full + TAU * _flips_done:
		_flips_done += 1
		_trick(&"backflip" if _air_pitch > 0.0 else &"frontflip", {"flips": _flips_done})
	while absf(_air_roll) >= full + TAU * _sideflips_done:
		_sideflips_done += 1
		_trick(&"sideflip", {"flips": _sideflips_done, "side": &"right" if _air_roll > 0.0 else &"left"})


func _trick(trick_name: StringName, info := {}) -> void:
	momentum = minf(momentum + tuning.momentum_trick_bump, 1.0)
	info["speed"] = horizontal_speed()
	trick.emit(trick_name, info)


## 1 when `error` is inside `perfect`, falling to 0 at `worst`.
static func timing_quality(error: float, perfect: float, worst: float) -> float:
	if worst <= perfect:
		return 1.0 if error <= perfect else 0.0
	return 1.0 - clampf((error - perfect) / (worst - perfect), 0.0, 1.0)


func _move() -> void:
	_pre_move_velocity = velocity
	move_and_slide()
	_smash_breakables()
	if is_on_wall():
		_wall_normal = get_wall_normal()
		_since_wall = 0.0
		_check_wall_impact()


## Running, sliding or diving into a window fast enough goes straight through.
func _smash_breakables() -> void:
	if _pre_move_velocity.length() < tuning.smash_speed:
		return
	for i in get_slide_collision_count():
		var c := get_slide_collision(i).get_collider()
		if c and c.is_in_group("windows") and c.has_method("on_impact"):
			if c.on_impact(self, _pre_move_velocity):
				velocity = _pre_move_velocity
				_trick(&"window_smash")
				return


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
	# Arrived on the ground short (crouched, prone, diving) under something
	# low: stay crouched instead of standing up into it.
	if _height < tuning.stand_height - 0.01 and not _can_stand():
		_change_state(State.CROUCH)
		_tick_crouch(f, wish, delta)
		return
	_set_height(tuning.stand_height)
	if _jump_buffer <= tuning.jump_buffer:
		if _try_obstacle(f, true):
			return
		if _try_wall_climb(f, true):
			return
		_hop()
		_tick_air(f, wish, delta)
		return
	if not tuning.vault_requires_jump and _try_obstacle(f, false):
		return
	if f.kick_pressed:
		_ground_kick()
	var speed := horizontal_speed()
	if f.prone_pressed:
		_start_dive()
		_tick_air(f, wish, delta)
		return
	if f.crouch_held and speed >= tuning.slide_min_speed and (f.crouch_pressed or _since_crouch_press < 0.2):
		_start_slide()
		_tick_slide(f, wish, delta)
		return
	if f.crouch_held:
		_change_state(State.CROUCH)
		_tick_crouch(f, wish, delta)
		return

	velocity = MovementMath.apply_friction(velocity, tuning.ground_friction, tuning.stop_speed, delta)
	# Always sprinting, in any direction, so you can strafe-run while aiming
	# at something. Backpedalling caps at run speed; momentum only carries
	# forward and sideways.
	var top := MovementMath.ground_wish_speed(tuning.run_speed, tuning.top_speed, momentum) if f.move.y > -0.3 else tuning.run_speed
	var wish_speed := top * wish.length()
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
	if f.prone_pressed:
		_start_dive()
		_tick_air(f, wish, delta)
		return
	if f.kick_pressed:
		_ground_kick()
	velocity = MovementMath.apply_friction(velocity, tuning.ground_friction, tuning.stop_speed, delta)
	velocity = MovementMath.accelerate(velocity, wish.normalized(), tuning.crouch_speed * wish.length(), tuning.ground_accel, delta)
	velocity.y -= tuning.gravity * delta
	_move()
	if not is_on_floor():
		_change_state(State.AIR)


## A jump from the ground. Chained straight out of a landing it's a hop:
## pressing right as you touch down keeps all your speed, pressing early
## (buffered) keeps a little less, pressing late lets friction eat speed.
func _hop() -> void:
	var chained := _ground_time <= 0.25 and horizontal_speed() > tuning.run_speed * 0.8
	if chained:
		var early := _land_press_age >= 0.0
		var err := _land_press_age if early else _ground_time
		var q := timing_quality(err, tuning.hop_perfect_window, tuning.jump_buffer)
		if early:
			var h := MovementMath.horizontal(velocity) * lerpf(tuning.hop_early_keep, 1.0, q)
			velocity = Vector3(h.x, velocity.y, h.z)
		trick.emit(&"hop", {"speed": horizontal_speed(), "quality": q})
	_jump()


func _jump() -> void:
	velocity.y = tuning.jump_velocity
	_jump_buffer = 999.0
	_jumped_since_floor = true
	_change_state(State.AIR)


# ---------------------------------------------------------------- air

func _tick_air(f: InputFrame, wish: Vector3, delta: float) -> void:
	if _diving:
		_set_height(tuning.prone_height)
	elif f.crouch_held:
		_set_height(tuning.crouch_height)
	elif _can_stand():
		_set_height(tuning.stand_height)
	_tick_air_roll(f, delta)
	_check_air_rotation()

	# Coyote jump: just ran off a ledge.
	if _jump_buffer <= tuning.jump_buffer and not _jumped_since_floor and _since_floor <= tuning.coyote_time:
		_jump()
	elif f.kick_pressed and _try_kick_off():
		pass
	elif _try_obstacle(f, _jump_buffer <= tuning.jump_buffer):
		return
	elif _jump_buffer <= tuning.jump_buffer and _try_wall_climb(f, false):
		return
	elif _jump_buffer <= tuning.jump_buffer and _since_wall <= tuning.wall_jump_grace and _wall_jump_lock <= 0.0:
		_wall_jump(wish, &"wall_hop")

	velocity.y = maxf(velocity.y - tuning.gravity * delta, -tuning.max_fall_speed)
	var speed_before := horizontal_speed()
	velocity = MovementMath.accelerate(velocity, wish.normalized(), tuning.air_wish_speed * wish.length(), tuning.air_accel, delta)
	if not tuning.air_strafe_gain:
		# Air control steers but never adds speed beyond what you took off with.
		var speed_after := horizontal_speed()
		var cap := maxf(speed_before, tuning.air_wish_speed)
		if speed_after > cap:
			var h := MovementMath.horizontal(velocity) * (cap / speed_after)
			velocity = Vector3(h.x, velocity.y, h.z)
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
	_ground_time = 0.0
	_land_press_age = _jump_buffer if _jump_buffer <= tuning.jump_buffer else -1.0
	_dip = minf(fall * tuning.landing_dip, 0.4)
	landed.emit(fall)
	var crouch_age := _since_crouch_press
	var tucked := _landing_tucked(fall) and not _landing_tipped()
	if _landing_tipped() or (_landing_crashed() and not tucked):
		_diving = false
		trick.emit(&"crash", {"speed": horizontal_speed()})
		_start_stun()
		return
	if _diving:
		_diving = false
		_change_state(State.PRONE_SLIDE)
		return
	if tucked:
		var p := wrapf(pitch, -PI, PI)
		var q := timing_quality(absf(rad_to_deg(p) + 100.0), 20.0, 75.0)
		pitch = 0.0
		_start_roll(q, &"flip_roll", p, MovementMath.horizontal(_pre_move_velocity), fall)
		return
	if fall >= tuning.hard_landing_speed:
		if crouch_age <= tuning.roll_window:
			_start_roll(timing_quality(crouch_age, 0.05, tuning.roll_window), &"landing_roll", 0.0, MovementMath.horizontal(_pre_move_velocity), fall)
		else:
			_start_stun()
		return
	if f.crouch_held and crouch_age <= tuning.slide_land_window and fall > 3.0:
		# Slide landing: a well-timed crouch turns some fall speed into speed.
		var q := timing_quality(crouch_age, 0.05, tuning.slide_land_window)
		var h := MovementMath.horizontal(velocity)
		var dir := h.normalized() if h.length() > 0.5 else forward()
		h += dir * fall * tuning.slide_land_conversion * q
		velocity = Vector3(h.x, velocity.y, h.z)
		if horizontal_speed() >= tuning.slide_min_speed:
			_start_slide(q)
			return
	if f.crouch_held and horizontal_speed() >= tuning.slide_min_speed:
		_start_slide()
		return
	_change_state(State.CROUCH if f.crouch_held else State.GROUND)


# ---------------------------------------------------------------- slide

func _start_slide(quality := -1.0) -> void:
	_set_height(tuning.crouch_height)
	var h := MovementMath.horizontal(velocity)
	if _slide_cooldown <= 0.0 and h.length() > 0.1:
		h += h.normalized() * tuning.slide_boost
		_slide_cooldown = tuning.slide_boost_cooldown
	velocity = Vector3(h.x, velocity.y, h.z)
	_slide_flat_time = 0.0
	_change_state(State.SLIDE)
	_trick(&"slide", {} if quality < 0.0 else {"quality": quality})


func _tick_slide(f: InputFrame, wish: Vector3, delta: float) -> void:
	_set_height(tuning.crouch_height)
	if _jump_buffer <= tuning.jump_buffer:
		_jump()
		_trick(&"slide_jump")
		_tick_air(f, wish, delta)
		return
	if f.prone_pressed:
		_start_dive()
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

## A forward roll: from a landing (crouch timed, or tucked forward out of a
## flip) or on the ground (flick the view down past your feet). Keeps your
## speed; the camera does a full forward turn. `spin_from` is the view pitch
## the camera's turn starts from.
func _start_roll(quality: float, trick_name: StringName, spin_from: float, h: Vector3, fall: float) -> void:
	_set_height(tuning.crouch_height)
	var dir := h.normalized() if h.length() > 0.5 else forward()
	var speed := h.length()
	if fall > 0.0:
		speed = maxf(speed * lerpf(0.8, 1.0, quality), tuning.run_speed * 0.8) + tuning.roll_boost * quality
	velocity = dir * speed
	_roll_spin_from = spin_from
	_change_state(State.ROLL)
	var info := {"quality": quality}
	if fall > 0.0:
		info["fall_speed"] = fall
	_trick(trick_name, info)


func _tick_roll(f: InputFrame, wish: Vector3, delta: float) -> void:
	_set_height(tuning.crouch_height)
	velocity = MovementMath.accelerate(velocity, wish.normalized(), 1.0 * wish.length(), 4.0, delta)
	velocity.y -= tuning.gravity * delta
	_move()
	if not is_on_floor():
		_change_state(State.AIR)
		return
	if state_time >= tuning.roll_time:
		if f.crouch_held and horizontal_speed() >= tuning.slide_min_speed:
			_start_slide()
		elif _can_stand():
			_change_state(State.GROUND)
		else:
			_change_state(State.CROUCH)  # rolled under something low


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


# ---------------------------------------------------------------- prone / dive

## Only happens when a dive slide stops under something too low to get up
## in. You get up by yourself as soon as there's room; until then you can
## shuffle out slowly so you're never stuck. There's no crawling otherwise.
func _tick_prone(f: InputFrame, wish: Vector3, delta: float) -> void:
	_set_height(tuning.prone_height)
	if _get_up_from_prone(f):
		return
	# Low stop speed so friction doesn't swamp the slow shuffle.
	velocity = MovementMath.apply_friction(velocity, tuning.ground_friction, tuning.prone_speed * 0.5, delta)
	velocity = MovementMath.accelerate(velocity, wish.normalized(), tuning.prone_speed * wish.length(), tuning.ground_accel, delta)
	velocity.y -= tuning.gravity * delta
	_move()
	if not is_on_floor():
		_change_state(State.AIR)


## Up to crouch (and standing, unless crouch is held) if there's room.
func _get_up_from_prone(f: InputFrame) -> bool:
	if not _shape_fits(_crouch_shape, global_position):
		return false
	_set_height(tuning.crouch_height)
	_crouch_hold = -999.0
	_jump_buffer = 999.0  # the jump that got you up isn't also a jump
	_change_state(State.CROUCH)
	if not f.crouch_held and _can_stand():
		_set_height(tuning.stand_height)
		_change_state(State.GROUND)
	return true


## Dolphin dive (prone jump): a low forward leap that lands on your belly.
func _start_dive() -> void:
	var h := MovementMath.horizontal(velocity)
	var dir := h.normalized() if h.length() > 0.5 else forward()
	h += dir * tuning.dive_boost
	velocity = Vector3(h.x, tuning.dive_up, h.z)
	_diving = true
	_jumped_since_floor = true
	_jump_buffer = 999.0
	_set_height(tuning.prone_height)
	_change_state(State.AIR)
	_trick(&"dolphin_dive")


func _tick_prone_slide(f: InputFrame, wish: Vector3, delta: float) -> void:
	_set_height(tuning.prone_height)
	# Tap prone to dive and pop up into a slide; hold it to stay on your belly
	# (under low gaps). You get up by yourself once the slide runs out.
	if (f.jump_pressed or not f.prone_held) and _shape_fits(_crouch_shape, global_position):
		_set_height(tuning.crouch_height)
		_slide_flat_time = 0.0
		if horizontal_speed() >= tuning.slide_min_speed:
			_change_state(State.SLIDE)
		else:
			_change_state(State.CROUCH)
		return
	velocity = MovementMath.apply_friction(velocity, tuning.prone_slide_friction, 0.0, delta)
	if is_on_floor():
		var n := get_floor_normal()
		velocity += (Vector3.DOWN - n * Vector3.DOWN.dot(n)) * tuning.gravity * tuning.slide_slope_gain * delta
	velocity.y -= tuning.gravity * delta
	_move()
	if not is_on_floor():
		_change_state(State.AIR)
	elif horizontal_speed() < tuning.prone_speed:
		_change_state(State.PRONE)
		_get_up_from_prone(f)


# ---------------------------------------------------------------- kicks (doors, windows)

## Front kick on the ground: opens doors, breaks windows, shoves targets.
func _ground_kick() -> void:
	var eye := global_position + Vector3.UP * (_height - EYE_OFFSET)
	var look := -camera.global_transform.basis.z
	var q := PhysicsRayQueryParameters3D.create(eye, eye + look * (tuning.kick_range + 0.3), 1 | 4)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		_trick_feedback(&"kick_miss")
		return
	var collider: Object = hit.collider
	if collider is RigidBody3D:
		(collider as RigidBody3D).apply_central_impulse(look * tuning.kick_target_impulse)
	if collider.has_method("on_kicked"):
		collider.on_kicked(self, look)
		_trick(&"door_kick" if collider.is_in_group("doors") else &"kick")


## A trick-feed event with no momentum bump (feedback only).
func _trick_feedback(trick_name: StringName, info := {}) -> void:
	info["speed"] = horizontal_speed()
	trick.emit(trick_name, info)


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
	# Shallow, fast entries make longer, flatter wallruns.
	var q_angle := 1.0 - clampf(angle_to_wall / tuning.wallrun_max_entry_angle, 0.0, 1.0)
	var q_speed := clampf((speed - tuning.wallrun_min_speed) / maxf(tuning.top_speed + 2.0 - tuning.wallrun_min_speed, 0.1), 0.0, 1.0)
	_start_wallrun(n, speed, clampf(0.65 * q_angle + 0.35 * q_speed, 0.0, 1.0))
	return true


func _start_wallrun(n: Vector3, speed: float, quality: float) -> void:
	_wall_normal = n
	_wallrun_used_normal = n
	_wallrun_time_limit = lerpf(tuning.wallrun_min_time, tuning.wallrun_max_time, quality)
	_wallrun_gravity = lerpf(tuning.wallrun_sloppy_gravity, tuning.wallrun_gravity_scale, quality)
	var t := MovementMath.wall_tangent(n, _pre_move_velocity)
	var v := t * maxf(speed, tuning.wallrun_min_speed)
	v.y = maxf(velocity.y, tuning.wallrun_entry_lift)
	velocity = v
	_change_state(State.WALLRUN)
	_trick(&"wallrun", {"quality": quality})


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
	# The view is free while wallrunning (look at targets, aim, line up the
	# jump), so steering doesn't detach you: crouch drops off, jump kicks off.
	var leaving := f.crouch_pressed
	if hit.is_empty() or leaving or state_time >= _wallrun_time_limit:
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
	# Hold any direction to keep running (and build up to wallrun speed);
	# let go and the run bleeds speed. Where you look doesn't matter.
	if f.move.length() > 0.3:
		if speed < tuning.wallrun_speed:
			speed = minf(speed + tuning.wallrun_accel * delta, tuning.wallrun_speed)
	else:
		speed = maxf(speed - tuning.wallrun_misalign_drag * delta, 0.0)
	var vy := velocity.y - tuning.gravity * _wallrun_gravity * delta
	velocity = t * speed - MovementMath.horizontal(_wall_normal).normalized() * 1.5
	velocity.y = vy
	_move()
	if is_on_floor():
		_land(f)
	elif MovementMath.horizontal_speed(velocity) < tuning.wallrun_min_speed * 0.5:
		_change_state(State.AIR)


func _wall_jump(wish: Vector3, trick_name := &"wall_jump") -> void:
	var boost_dir := wish.normalized() if wish.length() > 0.1 else forward()
	velocity = MovementMath.wall_jump_velocity(velocity, _wall_normal, tuning.wall_jump_push, tuning.wall_jump_up, boost_dir, tuning.wall_jump_boost)
	_jump_buffer = 999.0
	_wall_jump_lock = 0.2
	_since_wall = 999.0
	_change_state(State.AIR)
	_trick(trick_name)


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
	# Hitting the wall square-on and fast runs you higher.
	var q_face := clampf((fwd.dot(-n) - tuning.wall_climb_facing) / maxf(1.0 - tuning.wall_climb_facing, 0.01), 0.0, 1.0)
	var q_speed := clampf(MovementMath.horizontal(velocity).length() / tuning.top_speed, 0.0, 1.0)
	var climb_q := 0.5 * q_face + 0.5 * q_speed
	_climb_start_speed = tuning.wall_climb_speed * lerpf(0.85, 1.15, climb_q)
	velocity = Vector3(0.0, _climb_start_speed, 0.0)
	_change_state(State.WALLCLIMB)
	_trick(&"wall_climb", {"quality": climb_q})
	return true


func _tick_wallclimb(f: InputFrame, wish: Vector3, delta: float) -> void:
	_set_height(tuning.stand_height if _can_stand() else tuning.crouch_height)
	if _jump_buffer <= tuning.jump_buffer:
		# Kick off the wall. The camera never turns by itself: quick turn
		# if you want to face away.
		var n := MovementMath.horizontal(_wall_normal).normalized()
		velocity = n * tuning.wall_climb_kick_push
		velocity.y = tuning.wall_climb_kick_up
		_jump_buffer = 999.0
		_since_wall = 999.0
		_wall_jump_lock = 0.2
		_change_state(State.AIR)
		_trick(&"wall_climb_kick")
		return
	if _try_obstacle(f, true):
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
## vault_requires_jump, vaults (hurdles) only happen on a (buffered) jump
## press, on the ground or in the air, so you can always just jump over
## things. Catching a ledge in the air stays automatic.
func _try_obstacle(f: InputFrame, from_jump: bool) -> bool:
	var grounded := state in [State.GROUND, State.CROUCH, State.SLIDE, State.ROLL]
	if f.move.y <= 0.2:
		return false
	if grounded and tuning.vault_requires_jump and not from_jump:
		return false
	var info := probe_obstacle(grounded)
	if info.is_empty():
		return false
	if info.kind == &"vault" and tuning.vault_requires_jump and not from_jump:
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
			return {"kind": &"vault", "height": height, "top": top_y, "face_normal": n, "land": land,
				"face_dist": _face_distance(face.position), "reach": height / max_h, "grounded": grounded}

	# Mantle: stand on top, a little way in from the edge.
	var stand_on: Vector3 = face.position - n * (RADIUS + 0.2)
	stand_on.y = top_y + 0.03
	if _shape_fits(_stand_shape, stand_on):
		return {"kind": &"mantle", "height": height, "top": top_y, "face_normal": n, "land": stand_on,
			"face_dist": _face_distance(face.position), "reach": height / max_h, "grounded": grounded}
	if _shape_fits(_crouch_shape, stand_on):
		return {"kind": &"mantle", "height": height, "top": top_y, "face_normal": n, "land": stand_on, "crouch": true,
			"face_dist": _face_distance(face.position), "reach": height / max_h, "grounded": grounded}
	return {}


func _face_distance(p: Vector3) -> float:
	return maxf(MovementMath.horizontal(p - global_position).length() - RADIUS, 0.0)


## Jumping at the ideal distance from an obstacle gives a fast, clean move.
func _distance_quality(info: Dictionary) -> float:
	return 1.0 - clampf(absf(info.face_dist - tuning.vault_ideal_distance) / 0.7, 0.0, 1.0)


func _start_vault(info: Dictionary) -> void:
	var q := _distance_quality(info)
	var speed := maxf(horizontal_speed(), tuning.run_speed * 0.75)
	var dir: Vector3 = -info.face_normal
	_path_from = global_position
	_path_to = info.land
	var mid := (_path_from + _path_to) * 0.5
	_path_ctrl = Vector3(mid.x, info.top + 0.55 + (info.top - mid.y) * 0.3, mid.z)
	_path_time = tuning.vault_time * lerpf(1.35, 0.85, q)
	_path_exit_velocity = dir * speed * (1.0 + lerpf(-0.1, tuning.vault_speed_bonus, q))
	_jump_buffer = 999.0
	_change_state(State.VAULT)
	_trick(&"vault", {"height": info.height, "quality": q})


func _start_mantle(info: Dictionary) -> void:
	# From the ground: judged on jump distance. In the air: catching the ledge
	# low on your body (not at the fingertips) is fast and keeps speed.
	var q := _distance_quality(info) if info.grounded else 1.0 - clampf((info.reach - 0.45) / 0.55, 0.0, 1.0)
	var dir: Vector3 = -info.face_normal
	var keep := maxf(horizontal_speed() * minf(tuning.mantle_speed_keep * lerpf(0.6, 1.3, q), 1.0), tuning.mantle_min_exit_speed)
	_path_from = global_position
	_path_to = info.land
	_path_ctrl = Vector3(_path_from.x, info.top + 0.35, _path_from.z)
	_path_time = tuning.mantle_time * clampf(0.6 + info.height * 0.3, 0.6, 1.3) * lerpf(1.4, 0.8, q)
	_path_exit_velocity = dir * keep
	if info.get("crouch", false):
		_set_height(tuning.crouch_height)
	_jump_buffer = 999.0
	_change_state(State.MANTLE)
	_trick(&"mantle", {"height": info.height, "quality": q})


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
	if collider and collider.is_in_group("breakable"):
		# Doors and windows give way: no surface to push off.
		collider.on_kicked(self, -camera.global_transform.basis.z)
		_kicks_left -= 1
		_trick(&"door_kick" if collider.is_in_group("doors") else &"window_kick")
		return true
	var n: Vector3 = hit.normal
	# Kicking while moving into the surface turns that speed into push.
	var into := maxf(-MovementMath.horizontal(velocity).dot(MovementMath.horizontal(n).normalized()), 0.0)
	var kick_q := clampf(into / tuning.top_speed, 0.0, 1.0)
	velocity = MovementMath.kick_velocity(velocity, n, tuning.kick_push + into * tuning.kick_reflect, tuning.kick_up, tuning.kick_keep_tangent)
	_kicks_left -= 1
	_kicked_ids.append(cid)
	_since_wall = 999.0
	var is_target := collider is RigidBody3D
	if is_target:
		(collider as RigidBody3D).apply_central_impulse(-n * tuning.kick_target_impulse + Vector3.UP * 3.0)
		if collider.has_method("on_kicked"):
			collider.on_kicked(self, -n)
	_trick(&"kick_off", {"target": is_target, "quality": kick_q})
	return true


# ---------------------------------------------------------------- shape helpers

func _set_height(h: float) -> void:
	if is_equal_approx(_height, h) and collision.shape != null:
		return
	_height = h
	if h >= tuning.stand_height - 0.01:
		collision.shape = _stand_shape
	elif h >= tuning.crouch_height - 0.01:
		collision.shape = _crouch_shape
	else:
		collision.shape = _prone_shape
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


## Quick 180. On a wall it turns you to face away from it, ready to jump off.
## Doesn't count toward 360s (only turning with the mouse or stick does).
func _quick_turn() -> void:
	if _turn_left > 0.0:
		return
	var target := yaw + PI
	if state in [State.WALLRUN, State.WALLCLIMB]:
		var n := MovementMath.horizontal(_wall_normal).normalized()
		target = atan2(-n.x, -n.z)
	_start_auto_turn(target, tuning.quick_turn_time)
	_trick_feedback(&"quick_turn")


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
	_diving = false
	_since_floor = 999.0
	_change_state(State.AIR)
	pitch = 0.0
	_kick_pitch = 0.0
	_kick_yaw = 0.0
	_air_yaw = 0.0
	_air_pitch = 0.0
	_air_roll = 0.0
	_spins_done = 0
	_flips_done = 0
	_sideflips_done = 0
	_ground_flick = 0.0
	lean = 0.0
	_turn_left = 0.0
	_jump_buffer = 999.0
	state_time = 0.0
	respawned.emit()


# ---------------------------------------------------------------- camera (visual only)

func _process(delta: float) -> void:
	if use_device_input:
		var stick := InputSetup.look_stick()
		if stick.length() > 0.15:
			var pad := tuning.gamepad_look_speed * aim_sensitivity_scale() * delta
			var pitch_scale := 0.7
			if state == State.AIR:
				pad *= tuning.gamepad_air_spin
				pitch_scale = 1.0
			_look(-stick.x * pad, -stick.y * pad * pitch_scale * (-1.0 if invert_y else 1.0))
	var settle := exp(-_kick_recovery * delta)
	_kick_pitch *= settle
	_kick_yaw *= settle
	head.rotation = Vector3(pitch + _kick_pitch + roll_spin(), 0.0, 0.0)

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
	# Lean peeks on the ground; in the air it's a side flip instead.
	_peek = lerpf(_peek, 0.0 if state == State.AIR else lean, 1.0 - exp(-14.0 * delta))
	target_roll -= _peek * deg_to_rad(tuning.lean_tilt_degrees)
	_roll = lerpf(_roll, target_roll, 1.0 - exp(-10.0 * delta))
	if state == State.AIR:
		_air_roll_view = wrapf(_air_roll, -PI, PI)
	else:
		_air_roll_view = lerp_angle(_air_roll_view, 0.0, 1.0 - exp(-12.0 * delta))
	camera.rotation = Vector3(0.0, _kick_yaw, _roll - _air_roll_view)
	camera.position = Vector3(_peek * tuning.lean_offset, 0.0, 0.0)

	var over := clampf((speed - tuning.run_speed) / maxf(tuning.top_speed + 4.0 - tuning.run_speed, 0.1), 0.0, 1.0)
	var target_fov := lerpf(tuning.base_fov + tuning.speed_fov_bonus * over, aim_fov, aim_zoom)
	camera.fov = lerpf(camera.fov, target_fov, 1.0 - exp(-(6.0 + 20.0 * aim_zoom) * delta))


## Recoil: kicks the view up (and a little sideways), settling back at
## `recovery` per second. Purely visual on top of the aim direction.
func add_view_kick(pitch_amount: float, yaw_amount: float, recovery: float) -> void:
	_kick_pitch = minf(_kick_pitch + pitch_amount, deg_to_rad(8.0))
	_kick_yaw = clampf(_kick_yaw + yaw_amount, deg_to_rad(-3.0), deg_to_rad(3.0))
	_kick_recovery = recovery


## The roll's forward camera turn (radians, added to the view pitch).
func roll_spin() -> float:
	if state != State.ROLL:
		return 0.0
	var t := clampf(state_time / tuning.roll_time, 0.0, 1.0)
	return lerpf(_roll_spin_from, -TAU, t * t * (3.0 - 2.0 * t))


## 0..1 through the current roll (0 when not rolling).
func roll_progress() -> float:
	return clampf(state_time / tuning.roll_time, 0.0, 1.0) if state == State.ROLL else 0.0


## Side-flip roll done in the air since takeoff (radians, + = right).
func air_roll() -> float:
	return _air_roll


func wall_normal() -> Vector3:
	return _wall_normal


func is_diving() -> bool:
	return _diving


## Seconds since last on the ground (wallruns and climbs count as off it).
func time_off_ground() -> float:
	return _since_floor


## Rotation done in the air since takeoff (x = yaw, y = pitch; radians).
func air_rotation() -> Vector2:
	return Vector2(_air_yaw, _air_pitch)


func view_kick() -> Vector2:
	return Vector2(_kick_pitch, _kick_yaw)


## What the player is doing right now, for style bonuses on shots
## (airborne headshot, mid-flip, while wallrunning...).
func shot_tags() -> Array[StringName]:
	var tags: Array[StringName] = []
	match state:
		State.AIR:
			tags.append(&"airborne")
		State.WALLRUN:
			tags.append(&"wallrun")
		State.SLIDE:
			tags.append(&"sliding")
		State.PRONE_SLIDE:
			tags.append(&"diving")
		State.PRONE:
			tags.append(&"prone")
		State.WALLCLIMB:
			tags.append(&"climbing")
		State.VAULT, State.MANTLE:
			tags.append(&"vaulting")
	if _diving and state == State.AIR:
		tags.append(&"diving")
	if state == State.AIR:
		if absf(_air_pitch) > deg_to_rad(90.0):
			tags.append(&"flipping")
		if absf(_air_yaw) > deg_to_rad(180.0):
			tags.append(&"spinning")
		if absf(_air_roll) > deg_to_rad(90.0):
			tags.append(&"side_flipping")
	if cos(pitch) < 0.0 or cos(_air_roll) < 0.0:
		tags.append(&"upside_down")
	if horizontal_speed() >= tuning.top_speed * 0.9:
		tags.append(&"fast")
	return tags


func debug_text() -> String:
	return "%s  %.1fs" % [State.keys()[state], state_time]
