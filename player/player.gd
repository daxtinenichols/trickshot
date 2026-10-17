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

enum State { GROUND, AIR, CROUCH, SLIDE, VAULT, MANTLE, WALLRUN, WALLCLIMB, ROLL, STUN, SURFACE }

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
## This tick's crouch press came right after another one.
var _crouch_double := false
var _crouch_released := true
var _slide_cooldown := 0.0
var _slide_flat_time := 0.0
var _wall_normal := Vector3.ZERO
var _since_wall := 999.0
var _wallrun_used_normal := Vector3.ZERO
var _wall_jump_lock := 0.0
var _climb_used := false
var _climb_start_speed := 0.0
## Horizontal speed you hit a climb with, given back by a clean mantle at
## the top.
var _climb_entry_speed := 0.0
var _climb_quality := 0.0
var _ground_time := 0.0
## Seconds between the jump press and touching down (-1 = no early press).
var _land_press_age := -1.0
var _wallrun_time_limit := 1.0
var _wallrun_gravity := 0.3
## The wallrun's path: its angle up the wall (radians, negative runs down)
## and your speed along it.
var _wallrun_angle := 0.0
var _wallrun_speed := 0.0
## The player's transform at the previous tick, for smoothing the view
## between ticks.
var _prev_origin := Vector3.ZERO
var _prev_rotation := Quaternion.IDENTITY
var _kicks_left := 0
var _kicked_ids: Array[int] = []
var _pre_move_velocity := Vector3.ZERO
var _height := 1.8
var _stand_shape: CapsuleShape3D
var _crouch_shape: CapsuleShape3D
var _crouch_hold := 0.0
# Rotation done in the air since takeoff (radians, unwrapped).
var _air_yaw := 0.0
var _air_pitch := 0.0
## Side-flip roll (radians, unwrapped, + = to the right).
var _air_roll := 0.0
## Side-flip spin: direction (locked once started) and speed (rad/s).
var _roll_dir := 0.0
var _roll_rate := 0.0
## A roll carried off a surface: keeps its rate until you lean.
var _roll_carry := false
## Still holding the lean you steered a wallrun with: it won't start a side
## flip until you let go and lean again.
var _lean_locked := false
## View turned by the player since the last tick, and the spin carried on
## from it in the air (yaw, pitch, rad/s).
var _look_acc := Vector2.ZERO
var _spin_vel := Vector2.ZERO
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

# Running on steep ramps and loops (SURFACE). The body turns to match the
# surface, so the view goes upside down with it.
## Normal of the surface you're running on.
var _surface_n := Vector3.UP
## The body's up, following _surface_n smoothly so seams don't jolt the view.
var _surface_up := Vector3.UP
## How fast the body is turning to follow the surface (rotation vector, rad/s).
var _body_spin := Vector3.ZERO
## Where you're looking, relative to the direction you're running.
var _surface_look_yaw := 0.0
var _surface_looped := false
## Direction the track under you runs (from its "flow" meta), or zero.
var _surface_flow := Vector3.ZERO
## Flying off a ramp or loop: how far round you are (as a flip), how tilted
## (as a side flip), and how fast the surface was turning you (yaw, pitch
## and roll rates), all carried into the air.
var _exit_air_pitch := 0.0
var _exit_spin := Vector2.ZERO
var _exit_air_roll := 0.0
var _exit_roll_rate := 0.0
## The current spin carry came from a loop: it keeps its rate (no fade, no
## halfway rule) until you take over with the view or come round level.
var _carry_free := false
## Visual: the difference between the view on the surface and the upright
## view after leaving it, eased out so leaving never snaps the camera.
var _view_offset := Quaternion.IDENTITY
var _view_offset_start := Quaternion.IDENTITY
var _view_offset_time := 0.0
var _view_offset_rate := 6.0

# Scripted vault / mantle path (quadratic bezier).
var _path_from := Vector3.ZERO
var _path_ctrl := Vector3.ZERO
var _path_to := Vector3.ZERO
var _path_time := 0.3
var _path_exit_velocity := Vector3.ZERO

# Quick turn: a held lean speeds up turning toward its side (Q left, E
# right) and carries your speed round. -1 = left, 1 = right, 0 = off.
var _turn_side := 0.0
## The last tick rolled you with the mouse.
var _mouse_rolled := false
# Mouse roll (boost held + mouse left/right in the air or on a wall):
# radians gathered since the last tick, and what this tick uses.
var _roll_input := 0.0
var _roll_tick := 0.0
# Mouse lean (boost held + turning on your feet): turn gathered since the
# last tick (radians, + = left), and the lean it gives (-1 left .. 1 right).
var _mouse_turn := 0.0
var _mouse_lean := 0.0
## View yaw turned while quick turning since the last tick (radians).
var _turn_carry := 0.0
var _boost_cooldown := 0.0
## Seconds left of the boost's raised top speed.
var _boost_time := 0.0
## Speed into a wall hit this tick (a bonk unless the hit becomes a move).
var _pending_impact := 0.0

# Visual-only camera state.
var _bob_phase := 0.0
var _dip := 0.0
var _roll := 0.0
var _air_roll_view := 0.0
## _air_roll at the start of the tick, so the view can roll smoothly between
## ticks.
var _prev_air_roll := 0.0
var _peek := 0.0
var _eye_height := 1.66
# Weapon recoil: a visual view kick on top of the aim, so flips/spins
# (which read `pitch`) are never affected by shooting.
var _kick_pitch := 0.0
var _kick_yaw := 0.0
var _kick_recovery := 12.0
## Recoil springs: the kick punches up over a couple of frames and settles
## (critically damped), plus a little roll and a field-of-view punch.
var _kick_vel := Vector2.ZERO
var _kick_roll := 0.0
var _kick_roll_vel := 0.0
var _fov_base := 0.0
var _fov_punch := 0.0

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
	_prev_origin = global_position
	_prev_rotation = Quaternion(global_basis.orthonormalized())
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
		var d_pitch := -m.relative.y * sens * (-1.0 if invert_y else 1.0)
		if Input.is_action_pressed("boost") and state in [State.AIR, State.WALLRUN]:
			# Holding boost, left and right rolls you instead of turning.
			roll_look(m.relative.x * sens)
			_look(0.0, d_pitch)
		elif Input.is_action_pressed("boost"):
			# On your feet it leans you into the turn.
			lean_look(-m.relative.x * sens, d_pitch)
		else:
			_look(-m.relative.x * sens, d_pitch)
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


## How much faster this turn goes: quick_turn_look_scale toward the side of
## a held lean button, scaled by the mouse lean toward its side, else 1.
## (Positive yaw turns left.)
func _quick_turn_scale(d_yaw: float) -> float:
	if _turn_side != 0.0 and d_yaw * _turn_side < 0.0:
		return tuning.quick_turn_look_scale
	if d_yaw * _mouse_lean < 0.0:
		return lerpf(1.0, tuning.quick_turn_look_scale, absf(_mouse_lean))
	return 1.0


## Turns the view. In the air the pitch is free, so pulling the view all the
## way over is a flip and turning a full circle is a 360. On the ground the
## pitch is clamped as usual.
func _look(d_yaw: float, d_pitch: float) -> void:
	if state == State.SURFACE:
		d_yaw *= _quick_turn_scale(d_yaw)
		_surface_look_yaw = wrapf(_surface_look_yaw + d_yaw, -PI, PI)
		pitch = clampf(pitch + d_pitch, deg_to_rad(-89.0), deg_to_rad(89.0))
		return
	if state == State.AIR:
		# Aim follows the view however you're turned: tilted by a side flip,
		# the view moves with the tilted screen, and upside down (past
		# vertical in a flip) turning left and right swap round.
		var r := _air_roll
		var dx := d_yaw * cos(r) - d_pitch * sin(r)
		var dy := d_yaw * sin(r) + d_pitch * cos(r)
		d_yaw = -dx if cos(pitch) < 0.0 else dx
		d_pitch = dy
	var scale := _quick_turn_scale(d_yaw)
	if scale > 1.0:
		d_yaw *= scale
		_turn_carry += d_yaw
	yaw = wrapf(yaw + d_yaw, -PI, PI)
	if state == State.AIR:
		if absf(wrapf(pitch, -PI, PI)) > deg_to_rad(75.0):
			d_pitch *= tuning.flip_look_gain
		pitch += d_pitch
		_air_yaw += d_yaw
		_air_pitch += d_pitch
		_look_acc += Vector2(d_yaw, d_pitch)
	else:
		var raw := pitch + d_pitch
		if raw < deg_to_rad(-89.0) and d_pitch < 0.0:
			_ground_flick += deg_to_rad(-89.0) - raw
		pitch = clampf(raw, deg_to_rad(-89.0), deg_to_rad(89.0))


## Mouse lean (boost held on your feet): turns the view like _look, and
## the turn's speed leans you into it, turning harder the more you lean.
func lean_look(d_yaw: float, d_pitch: float) -> void:
	_mouse_turn += d_yaw
	_look(d_yaw, d_pitch)


## Mouse roll: + rolls right. In the air it's a side flip you steer
## directly; on a wall it rolls your path round (like leaning). Elsewhere
## it does nothing.
func roll_look(d: float) -> void:
	d *= tuning.mouse_roll_scale
	_roll_input += d
	if state == State.AIR:
		# Straight away, like turning and pitching, so it's as smooth as the
		# mouse; the tick only reads how fast you're rolling.
		_air_roll += d
		_prev_air_roll += d


## Point the view somewhere (used by spawns and tests).
func set_view(new_yaw: float, new_pitch := 0.0) -> void:
	yaw = new_yaw
	pitch = new_pitch
	rotation = Vector3(0.0, yaw, 0.0)


# ---------------------------------------------------------------- tick

func _physics_process(delta: float) -> void:
	_prev_origin = global_position
	_prev_rotation = Quaternion(global_basis.orthonormalized())
	_prev_air_roll = _air_roll
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
	_roll_tick = _roll_input if state in [State.AIR, State.WALLRUN] else 0.0
	_roll_input = 0.0
	var feet := state not in [State.AIR, State.WALLRUN]
	var lean_to := clampf(-_mouse_turn / delta / deg_to_rad(tuning.mouse_lean_full_rate), -1.0, 1.0) if feet else 0.0
	_mouse_turn = 0.0
	_mouse_lean = move_toward(_mouse_lean, lean_to, tuning.lean_speed * delta)
	# On a wall, lean angles your run instead.
	_turn_side = signf(f.lean) if absf(f.lean) > 0.3 and state != State.WALLRUN else 0.0
	_carry_turn()
	if f.boost_pressed:
		_boost(f)
	if state != State.SURFACE:
		rotation = Vector3(0.0, yaw, 0.0)
	lean = move_toward(lean, clampf(f.lean + _mouse_lean, -1.0, 1.0), tuning.lean_speed * delta)
	var wish := wish_direction(f)
	if _ground_flick >= deg_to_rad(tuning.ground_roll_flick) and state in [State.GROUND, State.CROUCH, State.SLIDE] \
			and horizontal_speed() > 1.0 and _can_stand():
		_ground_flick = 0.0
		pitch = 0.0
		_start_roll(1.0, &"ground_roll", deg_to_rad(-89.0), MovementMath.horizontal(velocity), 0.0)
	_ground_flick = maxf(_ground_flick - tuning.ground_roll_flick_decay * delta, 0.0)
	if _crouch_double and state in [State.GROUND, State.CROUCH, State.SLIDE] and horizontal_speed() > 2.0:
		# Double-tap crouch while running: a forward roll.
		_since_crouch_press = 999.0
		_start_roll(1.0, &"ground_roll", 0.0, MovementMath.horizontal(velocity), 0.0)

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
		State.SURFACE: _tick_surface(f, delta)

	_resolve_wall_impact()
	_update_momentum(delta)
	if global_position.y < -40.0:
		respawn()


func _update_timers(f: InputFrame, delta: float) -> void:
	_jump_buffer = 0.0 if f.jump_pressed else _jump_buffer + delta
	_crouch_double = f.crouch_pressed and _crouch_released and _since_crouch_press <= tuning.double_tap_window
	_crouch_released = not f.crouch_held
	_since_crouch_press = 0.0 if f.crouch_pressed else _since_crouch_press + delta
	_slide_cooldown = maxf(_slide_cooldown - delta, 0.0)
	_wall_jump_lock = maxf(_wall_jump_lock - delta, 0.0)
	_boost_cooldown = maxf(_boost_cooldown - delta, 0.0)
	_boost_time = maxf(_boost_time - delta, 0.0)
	_since_wall += delta
	_crouch_hold = _crouch_hold + delta if f.crouch_held else 0.0
	if state in [State.GROUND, State.CROUCH, State.SLIDE, State.ROLL, State.STUN, State.SURFACE]:
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
		_roll_dir = 0.0
		_roll_rate = 0.0
		_look_acc = Vector2.ZERO
		_air_pitch = _exit_air_pitch
		_spin_vel = _exit_spin
		_carry_free = _exit_spin != Vector2.ZERO
		_air_roll = _exit_air_roll
		_roll_dir = signf(_exit_roll_rate)
		_roll_rate = absf(_exit_roll_rate)
		_roll_carry = _exit_roll_rate != 0.0
		_lean_locked = from == State.WALLRUN and absf(lean) > 0.3
		_mouse_rolled = false
		_prev_air_roll = _air_roll
		_exit_air_pitch = 0.0
		_exit_spin = Vector2.ZERO
		_exit_air_roll = 0.0
		_exit_roll_rate = 0.0
	elif from == State.AIR:
		_spin_vel = Vector2.ZERO
		_carry_free = false
		_roll_carry = false
		_settle_pitch()
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


## Side flips: lean in the air to start rolling that way. The direction is
## then set until you land; what you control is the speed, like curling up
## or opening out: hold lean (or crouch) to tuck and spin fast, let go to
## open up and slow down. Opened up near level you settle upright; land
## on your side and you crash.
func _tick_air_roll(f: InputFrame, delta: float) -> void:
	if _mouse_roll(delta):
		return
	if _lean_locked:
		if absf(f.lean) > 0.3:
			return
		_lean_locked = false
	if _roll_carry:
		# Rolling off a surface: it turns at its own rate until you lean,
		# then it's an ordinary side flip in that direction.
		if absf(f.lean) <= 0.3:
			_air_roll += _roll_dir * _roll_rate * delta
			return
		_roll_carry = false
	if _roll_dir == 0.0:
		if absf(f.lean) <= 0.3:
			return
		_roll_dir = signf(f.lean)
	var tucked := absf(f.lean) > 0.3 or f.crouch_held
	var target := deg_to_rad(tuning.side_flip_speed) * (1.0 if tucked else tuning.spin_open_share)
	_roll_rate = move_toward(_roll_rate, target, deg_to_rad(tuning.spin_accel) * delta)
	var level := roundf(_air_roll / TAU) * TAU
	if not tucked and absf(_air_roll - level) <= deg_to_rad(tuning.side_settle_degrees):
		_air_roll = move_toward(_air_roll, level, maxf(_roll_rate, deg_to_rad(tuning.side_flip_speed) * 0.5) * delta)
		if is_equal_approx(_air_roll, level):
			_roll_rate = 0.0
		return
	_air_roll += _roll_dir * _roll_rate * delta


## Rolling with the mouse (boost held) turns you directly, either way.
## Let go mid-spin and a fast roll carries on like an opened-up side flip
## (settling near level); a slow one just stops where it is.
func _mouse_roll(delta: float) -> bool:
	if _roll_tick != 0.0:
		_roll_dir = signf(_roll_tick)
		_roll_rate = minf(absf(_roll_tick) / delta, deg_to_rad(tuning.side_flip_speed))
		_roll_carry = false
		_lean_locked = false
		_mouse_rolled = true
		return true
	if not _mouse_rolled:
		return false
	_mouse_rolled = false
	if _roll_rate < deg_to_rad(tuning.spin_carry_min):
		_roll_dir = 0.0
		_roll_rate = 0.0
	return false


## Would `step` take `total` round past the next whole turn?
static func _comes_round(total: float, step: float) -> bool:
	if step == 0.0 or signf(step) != signf(total):
		return false
	return fmod(absf(total), TAU) + absf(step) >= TAU


## Flips and turns have momentum: past halfway round, let go of the view
## and the spin carries on, fading out (tucking with crouch keeps it going)
## and stopping when you come round level. Slow aiming never carries on.
func _tick_spin_carry(f: InputFrame, delta: float) -> void:
	var turned := _look_acc
	_look_acc = Vector2.ZERO
	if turned.length() > 0.0001:
		var rate := turned / delta
		_spin_vel = _spin_vel.lerp(rate, 0.5) if _spin_vel.dot(rate) > 0.0 else rate
		_carry_free = false
		return
	if not _carry_free:
		if _spin_vel.length() < deg_to_rad(tuning.spin_carry_min):
			_spin_vel = Vector2.ZERO
			return
		# Only a flip or spin past halfway round carries on, so looking
		# around (aiming, tucking for a landing, overshooting a finished
		# flip) never runs away from you.
		if fmod(absf(_air_pitch), TAU) < PI:
			_spin_vel.y = 0.0
		if fmod(absf(_air_yaw), TAU) < PI:
			_spin_vel.x = 0.0
	var step := _spin_vel * delta
	# A flip or spin that carries round to level stops there, so letting go
	# just before you come round lands you straight.
	if _comes_round(_air_pitch, step.y):
		step.y = 0.0
		_spin_vel.y = 0.0
	if _comes_round(_air_yaw, step.x):
		step.x = 0.0
		_spin_vel.x = 0.0
	yaw = wrapf(yaw + step.x, -PI, PI)
	pitch += step.y
	_air_yaw += step.x
	_air_pitch += step.y
	if not f.crouch_held and not _carry_free:
		_spin_vel *= exp(-delta / maxf(tuning.spin_carry_time, 0.01))


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


## Running or sliding into a window fast enough goes straight through.
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


## Notes a hard hit on a wall. It only counts as a bonk at the end of the
## tick, if the hit didn't turn into a wallrun, climb or vault.
func _check_wall_impact() -> void:
	if state not in [State.GROUND, State.AIR] or not _runnable_contact().is_empty():
		return
	var n := MovementMath.horizontal(_wall_normal).normalized()
	var into := -MovementMath.horizontal(_pre_move_velocity).dot(n)
	if into > tuning.wall_impact_speed:
		_pending_impact = maxf(_pending_impact, into)


func _resolve_wall_impact() -> void:
	var into := _pending_impact
	_pending_impact = 0.0
	if into <= 0.0 or state not in [State.GROUND, State.AIR]:
		return
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
	# Arrived on the ground short (crouched) under something
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
	# A boost lifts your top speed for a moment, fading back down.
	top += tuning.boost_speed * _boost_time / maxf(tuning.boost_time, 0.01)
	var wish_speed := top * wish.length()
	velocity = MovementMath.accelerate(velocity, wish.normalized(), wish_speed, tuning.ground_accel, delta)
	velocity.y -= tuning.gravity * delta
	_move()
	if _try_enter_surface():
		return
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
	if f.crouch_held:
		_set_height(tuning.crouch_height)
	elif _can_stand():
		_set_height(tuning.stand_height)
	_tick_air_roll(f, delta)
	_tick_spin_carry(f, delta)
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

	if _try_enter_surface():
		return
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
	if _tuck_roll(f, fall, crouch_age):
		return
	if _landing_tipped() and not _landing_crashed():
		# Down on your side partway round a side flip: a shoulder roll that
		# keeps you moving. The further off upright, the more speed it costs.
		var off := absf(rad_to_deg(wrapf(_air_roll, -PI, PI)))
		var flipped := _sideflips_done > 0
		_air_roll = 0.0
		_start_roll(timing_quality(off, 25.0, 160.0), &"flip_roll" if flipped else &"landing_roll", 0.0, MovementMath.horizontal(_pre_move_velocity), fall)
		return
	if _landing_tipped() or (_landing_crashed() and not tucked):
		trick.emit(&"crash", {"speed": horizontal_speed()})
		_start_stun()
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


## Crouch held in the air is a tuck: you land in a roll whatever angle
## you're at. A crouch pressed just before landing is a slide landing
## instead (unless you'd otherwise crash or the drop is hard).
func _tuck_roll(f: InputFrame, fall: float, crouch_age: float) -> bool:
	if not f.crouch_held or _crouch_hold < tuning.tuck_hold_time or fall < tuning.tuck_roll_min_fall:
		return false
	var bad_angle := _landing_tipped() or _landing_crashed()
	if not bad_angle and crouch_age <= tuning.slide_land_window and fall < tuning.hard_landing_speed:
		return false
	var p := wrapf(pitch, -PI, PI)
	var off := maxf(absf(rad_to_deg(wrapf(_air_roll, -PI, PI))), maxf(absf(rad_to_deg(p)) - 60.0, 0.0))
	var q := timing_quality(off, 25.0, 160.0)
	var flipped := _flips_done > 0 or _sideflips_done > 0
	_air_roll = 0.0
	pitch = 0.0
	_start_roll(q, &"flip_roll" if flipped else &"landing_roll", p if p < 0.0 else 0.0, MovementMath.horizontal(_pre_move_velocity), fall)
	return true


## Tucked in the air (crouch held): you'll land in a roll.
func is_tucked() -> bool:
	return state == State.AIR and _crouch_hold >= tuning.tuck_hold_time


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

	if _try_enter_surface():
		return
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
	# Your path along the wall is the angle you came in at: rising steeply,
	# you run up at a steep angle; coming down, you run down.
	var h := maxf(speed, tuning.wallrun_min_speed)
	var vy := velocity.y
	_wallrun_angle = clampf(atan2(vy, h), -deg_to_rad(tuning.wallrun_max_down_angle), deg_to_rad(tuning.wallrun_max_up_angle))
	_wallrun_speed = Vector2(h, vy).length()
	velocity = (t * cos(_wallrun_angle) + Vector3.UP * sin(_wallrun_angle)) * _wallrun_speed
	_change_state(State.WALLRUN)
	_trick(&"wallrun", {"quality": quality})


func _tick_wallrun(f: InputFrame, wish: Vector3, delta: float) -> void:
	_set_height(tuning.stand_height if _can_stand() else tuning.crouch_height)
	if _jump_buffer <= tuning.jump_buffer:
		# The steeper you're running up the wall, the harder you kick off.
		var steep := clampf(_wallrun_angle / deg_to_rad(tuning.wallrun_max_up_angle), 0.0, 1.0)
		_wall_jump(wish, &"wall_jump", 1.0 + tuning.wallrun_steep_kick * steep)
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
	var a := _wallrun_angle
	var speed := _wallrun_speed
	# Gravity bends your path down the wall; running up it costs speed,
	# running down gains it.
	var g := tuning.gravity * _wallrun_gravity
	speed -= tuning.gravity * (tuning.wallrun_climb_cost if a > 0.0 else _wallrun_gravity) * sin(a) * delta
	# Gravity always bends the path down a little (nothing holds you up).
	# Leaning rolls your path round on the wall at a steady rate: toward
	# the wall turns it up, away turns it down.
	a -= g * cos(a) / maxf(speed, 1.0) * delta
	a += _lean_toward_wall(f.lean) * deg_to_rad(tuning.wallrun_angle_rate) * delta
	# Rolling with the mouse (boost held) turns the path the same way, by
	# as much as you move it.
	a += _roll_tick * _wall_side()
	a = clampf(a, -deg_to_rad(tuning.wallrun_max_down_angle), deg_to_rad(tuning.wallrun_max_up_angle))
	# Hold any direction to keep running (and build up to wallrun speed);
	# let go and the run bleeds speed. Where you look doesn't matter.
	if f.move.length() > 0.3:
		if speed < tuning.wallrun_speed:
			speed = minf(speed + tuning.wallrun_accel * delta, tuning.wallrun_speed)
	else:
		speed = maxf(speed - tuning.wallrun_misalign_drag * delta, 0.0)
	_wallrun_angle = a
	_wallrun_speed = speed
	velocity = (t * cos(a) + Vector3.UP * sin(a)) * speed - MovementMath.horizontal(_wall_normal).normalized() * 1.5
	_move()
	if is_on_floor():
		_land(f)
	elif speed < tuning.wallrun_min_speed * 0.5:
		_change_state(State.AIR)


## How much a lean points toward the wall you're running on (1 = all the
## way toward it, -1 = away). Left and right are as you see them.
func _lean_toward_wall(lean: float) -> float:
	if absf(lean) < 0.05:
		return 0.0
	return lean * _wall_side()


## Which side of you the wall is on: 1 = right, -1 = left (as you see it,
## or by where you run when looking straight at or away from it).
func _wall_side() -> float:
	var right := forward().cross(Vector3.UP)
	right.y = 0.0
	var side := right.normalized().dot(MovementMath.horizontal(_wall_normal).normalized())
	if absf(side) < 0.2:
		# Looking straight at (or away from) the wall: go by where you run.
		right = MovementMath.horizontal(velocity).cross(Vector3.UP).normalized()
		side = right.dot(MovementMath.horizontal(_wall_normal).normalized())
	# The wall normal points away from the wall, so a wall on your right
	# has it pointing left.
	return -signf(side)


func _wall_jump(wish: Vector3, trick_name := &"wall_jump", power := 1.0) -> void:
	var boost_dir := wish.normalized() if wish.length() > 0.1 else forward()
	velocity = MovementMath.wall_jump_velocity(velocity, _wall_normal, tuning.wall_jump_push * power, tuning.wall_jump_up * lerpf(1.0, power, 0.5), boost_dir, tuning.wall_jump_boost)
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
	_climb_entry_speed = MovementMath.horizontal(velocity).length()
	_climb_quality = climb_q
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


# ---------------------------------------------------------------- steep ramps and loops

## The first contact with a runnable surface (group "runnable") from the
## last move, as {normal, collider}, or {}.
func _runnable_contact() -> Dictionary:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var col := c.get_collider()
		if _is_running_face(col, c.get_normal()):
			return {"normal": c.get_normal(), "collider": col}
	return {}


## Runnable pieces of track (with a "face" meta) are only runnable on their
## running side, not their edges or underside.
static func _is_running_face(col: Object, normal: Vector3) -> bool:
	if not (col is Node and (col as Node).is_in_group("runnable")):
		return false
	return not col.has_meta("face") or normal.dot(col.get_meta("face")) > 0.8


static func _flow_of(col: Object) -> Vector3:
	return col.get_meta("flow") if col != null and col.has_meta("flow") else Vector3.ZERO


## Speed you need to keep running on a surface with this normal: none on
## floor-like slopes, more on steep ones, the most upside down.
func surface_need_speed(n: Vector3) -> float:
	var floor_y := cos(floor_max_angle)
	if n.y >= floor_y:
		return 0.0
	var t := clampf((floor_y - n.y) / (floor_y + 1.0), 0.0, 1.0)
	return lerpf(tuning.surface_min_speed, tuning.surface_inverted_speed, t)


## Running (or sliding, or landing fast) onto a steep runnable surface
## sticks you to it.
func _try_enter_surface() -> bool:
	# Coming down mid-flip or on your side you can't run it: you hit it.
	if state == State.AIR and (_landing_crashed() or _landing_tipped()):
		return false
	var c := _runnable_contact()
	if c.is_empty():
		return false
	var n: Vector3 = c.normal
	if n.y > tuning.surface_enter_flatness:
		return false
	var v := _pre_move_velocity
	var along := v - n * v.dot(n)
	if along.length() < 0.1:
		return false
	# From the ground the run carries straight into the ramp (as if it had a
	# smooth curve at the bottom); from the air only the part of your speed
	# along the surface counts.
	var speed := along.length() if state == State.AIR else maxf(along.length(), MovementMath.horizontal(v).length())
	if speed < surface_need_speed(n) + 0.5:
		return false
	velocity = along.normalized() * speed
	var travel_yaw := yaw
	var h := MovementMath.horizontal(velocity)
	if h.length() > 0.2:
		travel_yaw = atan2(-h.x, -h.z)
	var view_before := Basis.from_euler(Vector3(pitch, yaw, -_air_roll if state == State.AIR else 0.0))
	_change_state(State.SURFACE)
	_surface_n = n
	_surface_up = Vector3.UP
	_body_spin = Vector3.ZERO
	_surface_look_yaw = angle_difference(travel_yaw, yaw)
	rotation = Vector3(0.0, travel_yaw, 0.0)  # start upright, facing the run
	_surface_looped = false
	_surface_flow = _flow_of(c.collider)
	_orient_to_surface(0.0)
	# Landing partway round a flip settles the view; ease into it rather
	# than snapping.
	var view_after := global_basis * Basis.from_euler(Vector3(pitch, _surface_look_yaw, 0.0))
	var offset := (Quaternion(view_before.orthonormalized()) * Quaternion(view_after.orthonormalized()).inverse()).normalized()
	if offset.get_angle() > 0.01:
		_view_offset_start = offset
		_view_offset = offset
		_view_offset_time = 0.0
		_view_offset_rate = 10.0
	_trick(&"ramp_run")
	return true


func _tick_surface(f: InputFrame, delta: float) -> void:
	var n := _surface_n
	if _jump_buffer <= tuning.jump_buffer:
		velocity += n * tuning.jump_velocity
		_jump_buffer = 999.0
		_jumped_since_floor = true
		_leave_surface()
		_change_state(State.AIR)
		return
	# Gravity along the surface slows you going up and speeds you coming
	# down; holding forward keeps running, up to your top speed.
	var v := velocity - n * velocity.dot(n)
	var down := Vector3.DOWN - n * Vector3.DOWN.dot(n)
	var g := down * tuning.gravity * tuning.surface_gravity_scale * delta
	var heading := v.normalized() if v.length() > 0.01 else -global_basis.z
	# The part of gravity along your path slows or speeds you; the part
	# across it (running sideways along a slope) pulls you down the slope
	# more gently, like a wallrun on a slope.
	# Running up or round loops and ramps (tracks that run up the slope)
	# keeps full gravity so you come round them. Running across any slope,
	# a ramp's included, holds your line like a sideways ramp.
	var track := _surface_flow.length() > 0.1 and not _is_bank(n, _surface_flow) \
			and not _runs_across(n, heading)
	var g_along := heading * g.dot(heading)
	v += g_along + (g - g_along) * (1.0 if track else tuning.surface_cross_gravity)
	var speed := v.length()
	var dir := v / speed if speed > 0.01 else -global_basis.z
	# Steer with the stick or keys, and toward where you look.
	var steer := deg_to_rad(tuning.surface_steer) * delta
	dir = dir.rotated(n, -f.move.x * steer)
	# Looking off to one side turns your path toward it; the view stays
	# where you put it while the path (and body) catches up. Not on loops,
	# where the track already guides you and you're free to look around.
	if not track and absf(_surface_look_yaw) < deg_to_rad(100.0):
		var turn := clampf(_surface_look_yaw, -steer, steer)
		dir = dir.rotated(n, turn)
		_surface_look_yaw -= turn
	# Tracks gently steer you along themselves, either way round: loops
	# all the way, sideways ramps only where they're steep enough to fall
	# off, so you can still steer up and down them.
	var flow := _surface_flow - n * _surface_flow.dot(n)
	if flow.length() > 0.1 and (track or n.y < 0.2):
		flow = flow.normalized() * signf(dir.dot(flow))
		var assist := tuning.surface_flow_assist * (1.0 - clampf(absf(f.move.x), 0.0, 1.0))
		if dir.dot(flow) > 0.5:
			dir = dir.slerp(flow, 1.0 - exp(-assist * delta)).normalized()
	if f.move.y > 0.3:
		speed = minf(speed + tuning.surface_accel * delta, maxf(speed, tuning.top_speed))
	elif f.move.y < -0.3:
		speed = maxf(speed - tuning.surface_accel * delta, 0.0)
	if speed < surface_need_speed(n):
		# Too slow to hold on: drop off.
		velocity = dir * speed + n * 1.0
		_leave_surface()
		_change_state(State.AIR)
		return
	# A loop counts once you've been upside down and come back down the
	# other side still on the track.
	if n.y < -0.7:
		_surface_looped = true
	elif n.y > 0.7 and _surface_looped:
		_surface_looped = false
		_trick(&"loop")
	velocity = dir * speed - n * tuning.surface_stick
	up_direction = n
	_orient_to_surface(delta)
	_move()
	var floor_hit := _floor_contact()
	if floor_hit.is_empty():
		# Off the lip of a ramp (or the surface ran out): fly.
		_leave_surface()
		_change_state(State.AIR)
		return
	var nn: Vector3 = floor_hit.normal
	var runnable: bool = floor_hit.runnable
	if nn.dot(n) < cos(deg_to_rad(30.0)):
		# A sharp edge (the lip at the top of a ramp): fly off it.
		_leave_surface()
		_change_state(State.AIR)
		return
	if nn.y > tuning.surface_exit_flatness or (not runnable and nn.y >= cos(floor_max_angle)):
		var keep := velocity - Vector3.UP * velocity.dot(Vector3.UP)
		_leave_surface(true)
		velocity = keep.normalized() * speed if keep.length() > 0.01 else Vector3.ZERO
		_change_state(State.GROUND)
		return
	_surface_n = nn
	_surface_flow = floor_hit.flow
	# Keep the speed through the seams between surface pieces.
	var t := velocity - nn * velocity.dot(nn)
	velocity = t.normalized() * speed if t.length() > 0.01 else velocity


## Is `dir` running across the slope (more sideways than up or down it)?
static func _runs_across(n: Vector3, dir: Vector3) -> bool:
	var down := Vector3.DOWN - n * Vector3.DOWN.dot(n)
	var along := dir - n * dir.dot(n)
	if down.length() < 0.3 or along.length() < 0.1:
		return false
	return absf(along.normalized().dot(down.normalized())) < 0.5


## A sideways ramp: its track runs across the slope rather than up it.
static func _is_bank(n: Vector3, flow: Vector3) -> bool:
	var down := Vector3.DOWN - n * Vector3.DOWN.dot(n)
	var along := flow - n * flow.dot(n)
	if down.length() < 0.3 or along.length() < 0.1:
		return false
	return absf(along.normalized().dot(down.normalized())) < 0.5


## The floor touched in the last move (relative to up_direction), as
## {normal, runnable}, or {}.
func _floor_contact() -> Dictionary:
	if not is_on_floor():
		return {}
	var limit := cos(floor_max_angle) - 0.01
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		if c.get_normal().dot(up_direction) >= limit:
			var col := c.get_collider()
			return {"normal": get_floor_normal(), "runnable": _is_running_face(col, c.get_normal()), "flow": _flow_of(col)}
	return {"normal": get_floor_normal(), "runnable": false, "flow": Vector3.ZERO}


## Turns the body so its up matches the surface and it faces where it's
## going. The track is built from flat pieces, so the turn follows a
## critically damped spring: the pieces' small steps blend into one smooth
## roll instead of a jolt at every seam.
func _orient_to_surface(delta: float) -> void:
	var n := _surface_n
	var fwd := velocity - n * velocity.dot(n)
	if fwd.length() < 0.05:
		fwd = -global_basis.z - n * (-global_basis.z).dot(n)
	fwd = fwd.normalized()
	var target := Quaternion(Basis(fwd.cross(n), n, -fwd).orthonormalized())
	var q := Quaternion(global_basis.orthonormalized())
	var diff := (target * q.inverse()).normalized()
	if diff.w < 0.0:
		diff = -diff
	var err := diff.get_axis() * diff.get_angle() if diff.get_angle() > 0.00001 else Vector3.ZERO
	var w := tuning.surface_align_rate
	_body_spin += (err * w * w - _body_spin * 2.0 * w) * delta
	var turn := _body_spin.length() * delta
	if turn > 0.000001:
		q = (Quaternion(_body_spin.normalized(), turn) * q).normalized()
	global_basis = Basis(q)
	_surface_up = global_basis.y


## Back to upright. Flying off (a bail, a jump, a ramp's lip) you keep
## looking exactly where you were, tilt and all, and keep turning the way
## the surface was turning you, like any body flying free. Running
## off onto the ground you keep your view relative to your body (so the
## body's tilt at the bottom of a loop doesn't leave you staring at the
## floor), and the tilt eases out.
func _leave_surface(onto_ground := false) -> void:
	var view := (global_basis * Basis.from_euler(Vector3(pitch, _surface_look_yaw, 0.0))).orthonormalized()
	var spin := _body_spin
	var look_pitch := pitch
	if onto_ground:
		# Relative to where you're running (the body can lag a little
		# behind it through the bottom of a loop).
		var bh := Vector2(velocity.x, velocity.z)
		if bh.length() < 0.05:
			var body_fwd := -global_basis.z
			bh = Vector2(body_fwd.x, body_fwd.z)
		yaw = wrapf(atan2(-bh.x, -bh.y) + _surface_look_yaw, -PI, PI)
		pitch = clampf(pitch, deg_to_rad(-89.0), deg_to_rad(89.0))
	else:
		var fwd := -view.z
		var h := Vector2(fwd.x, fwd.z)
		if h.length() < 0.05:
			var body_up := global_basis.y
			h = Vector2(body_up.x, body_up.z) * signf(-fwd.y)
		if h.length() > 0.0001:
			yaw = atan2(-h.x, -h.y)
		pitch = clampf(asin(clampf(fwd.y, -1.0, 1.0)), deg_to_rad(-89.0), deg_to_rad(89.0))
		var flip_rate := spin.dot(Basis(Vector3.UP, yaw).x)
		if view.y.y < 0.0:
			# Head below your feet (off a loop past upside down, or tipped
			# back off a steep ramp): you're partway through a flip, so
			# count it as one instead of rolling the view upright.
			yaw = wrapf(yaw + PI, -PI, PI)
			flip_rate = spin.dot(Basis(Vector3.UP, yaw).x)
			pitch = (PI if flip_rate >= 0.0 else -PI) - pitch
			_exit_air_pitch = pitch - look_pitch
		# Whatever tilt is left is a side-flip angle, kept as it is.
		var tilt := (Basis.from_euler(Vector3(pitch, yaw, 0.0)).inverse() * view).get_euler().z
		_exit_air_roll = -tilt
		# Keep turning as the surface turned you: flip, spin and roll.
		var roll_rate := spin.dot(fwd)
		_exit_spin = Vector2(spin.y, flip_rate)
		var spin_min := deg_to_rad(tuning.surface_exit_spin_min)
		if _exit_spin.length() < spin_min:
			_exit_spin = Vector2.ZERO
		_exit_roll_rate = roll_rate if absf(roll_rate) >= spin_min else 0.0
	var upright := Basis.from_euler(Vector3(pitch, yaw, -_exit_air_roll))
	_view_offset_start = (Quaternion(view) * Quaternion(upright).inverse()).normalized()
	_view_offset = _view_offset_start
	_view_offset_time = 0.0
	_view_offset_rate = 10.0 if onto_ground else 6.0
	up_direction = Vector3.UP
	_surface_up = Vector3.UP
	_body_spin = Vector3.ZERO
	_surface_look_yaw = 0.0
	# Turn upright around the middle of the body, not the feet, so coming
	# off upside down doesn't swing your head through the track.
	var center := global_position + global_basis.y * (_height * 0.5)
	rotation = Vector3(0.0, yaw, 0.0)
	global_position = center - Vector3.UP * (_height * 0.5)


## Up direction of the body (tilts on ramps and loops).
func body_up() -> Vector3:
	return global_basis.y

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
	_path_exit_velocity = dir * speed * (1.0 + lerpf(-0.03, tuning.vault_speed_bonus, q))
	momentum = minf(momentum + tuning.clean_move_momentum * q, 1.0)
	_jump_buffer = 999.0
	_change_state(State.VAULT)
	_trick(&"vault", {"height": info.height, "quality": q})


func _start_mantle(info: Dictionary) -> void:
	# From the ground: judged on jump distance. In the air: catching the ledge
	# low on your body (not at the fingertips) is fast and keeps speed.
	var q := _distance_quality(info) if info.grounded else 1.0 - clampf((info.reach - 0.45) / 0.55, 0.0, 1.0)
	var dir: Vector3 = -info.face_normal
	# A clean mantle keeps all your speed; a sloppy one loses some. Off a
	# climb, it's the speed you ran into the wall with, kept as well as you
	# hit the climb.
	var speed := maxf(horizontal_speed(), MovementMath.horizontal(_pre_move_velocity).length())
	if state == State.WALLCLIMB:
		speed = _climb_entry_speed
		q = _climb_quality
	var share := lerpf(tuning.mantle_speed_keep, 1.0, smoothstep(0.0, tuning.mantle_clean_quality, q))
	var keep := maxf(speed * share, tuning.mantle_min_exit_speed)
	momentum = minf(momentum + tuning.clean_move_momentum * q, 1.0)
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
	# A strong kick keeps all your speed along the surface; a weak one
	# scrubs a little.
	var keep := lerpf(tuning.kick_keep_tangent, 1.0, kick_q)
	velocity = MovementMath.kick_velocity(velocity, n, tuning.kick_push + into * tuning.kick_reflect, tuning.kick_up, keep)
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
	else:
		collision.shape = _crouch_shape
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


# ---------------------------------------------------------------- quick turn / boost

## Quick turn: while a lean button is held the view turns faster and your
## speed swings round with it, so a hard turn doesn't cost you speed.
func _carry_turn() -> void:
	var turned := _turn_carry
	_turn_carry = 0.0
	if is_zero_approx(turned):
		return
	var share := 0.0
	if state in [State.GROUND, State.CROUCH, State.SLIDE, State.ROLL]:
		share = 1.0
	elif state == State.AIR:
		share = tuning.quick_turn_air_carry
	if share <= 0.0:
		return
	var h := MovementMath.horizontal(velocity).rotated(Vector3.UP, turned * share)
	velocity = Vector3(h.x, velocity.y, h.z)


## Shift: a short burst of speed where you're going, then a cooldown. Only
## with your feet on something (no air dash).
func _boost(f: InputFrame) -> void:
	if _boost_cooldown > 0.0 or state not in [State.GROUND, State.CROUCH, State.SLIDE, State.ROLL, State.SURFACE, State.WALLRUN]:
		return
	var h := MovementMath.horizontal(velocity)
	var dir := h.normalized() if h.length() > 1.0 else wish_direction(f).normalized()
	if dir == Vector3.ZERO:
		dir = forward()
	var speed := minf(h.length() + tuning.boost_speed, maxf(h.length(), tuning.top_speed + tuning.boost_speed))
	h = dir * speed
	velocity = Vector3(h.x, velocity.y, h.z)
	_boost_cooldown = tuning.boost_cooldown
	_boost_time = tuning.boost_time
	_trick_feedback(&"boost")


## How far the view can lean sideways (`want`, + right) without poking into
## a wall: stops short of anything in the way.
func _peek_room(want: float) -> float:
	if absf(want) < 0.001 or not is_inside_tree():
		return want
	const MARGIN := 0.18
	var from := head.global_position
	var side := head.global_basis.x * signf(want)
	var q := PhysicsRayQueryParameters3D.create(from, from + side * (absf(want) + MARGIN), 1)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return want
	return signf(want) * maxf(from.distance_to(hit.position) - MARGIN, 0.0)


## Where the player is drawn this frame: between the last two ticks, facing
## where you look right now. Ticks come at a fixed rate, frames whenever the
## screen is ready (and far less often than frames in slow motion), so this
## keeps the view and body gliding instead of stepping from tick to tick.
func visual_transform() -> Transform3D:
	if not is_physics_processing():
		return global_transform
	var t := Engine.get_physics_interpolation_fraction()
	var pos := _prev_origin.lerp(global_position, t)
	if state == State.SURFACE:
		return Transform3D(Basis(_prev_rotation.slerp(Quaternion(global_basis.orthonormalized()), t)), pos)
	return Transform3D(Basis(Vector3.UP, yaw), pos)


## 0 = boost ready, 1 = just used.
func boost_cooldown() -> float:
	return _boost_cooldown / maxf(tuning.boost_cooldown, 0.01)


## The wallrun's path angle up the wall in radians (negative runs down it).
## Only meaningful while wallrunning.
func wallrun_angle() -> float:
	return _wallrun_angle


## Speed along the wallrun's path (m/s). Only meaningful while wallrunning.
func wallrun_speed() -> float:
	return _wallrun_speed


# ---------------------------------------------------------------- respawn

func set_spawn(t: Transform3D) -> void:
	_spawn = t


func respawn(t: Variant = null) -> void:
	if t is Transform3D:
		_spawn = t
	if state == State.SURFACE:
		_leave_surface()
	global_position = _spawn.origin
	set_view(_spawn.basis.get_euler().y, 0.0)
	_prev_origin = global_position
	_prev_rotation = Quaternion(global_basis)
	velocity = Vector3.ZERO
	momentum = 0.0
	_set_height(tuning.stand_height)
	_kicks_left = tuning.kicks_per_air_time
	_kicked_ids.clear()
	_wallrun_used_normal = Vector3.ZERO
	_climb_used = false
	_since_floor = 999.0
	_change_state(State.AIR)
	pitch = 0.0
	_kick_vel = Vector2.ZERO
	_kick_roll = 0.0
	_kick_roll_vel = 0.0
	_fov_punch = 0.0
	_kick_pitch = 0.0
	_kick_yaw = 0.0
	_air_yaw = 0.0
	_air_pitch = 0.0
	_air_roll = 0.0
	_spins_done = 0
	_flips_done = 0
	_sideflips_done = 0
	_roll_dir = 0.0
	_roll_rate = 0.0
	_roll_carry = false
	_spin_vel = Vector2.ZERO
	_look_acc = Vector2.ZERO
	_pending_impact = 0.0
	_ground_flick = 0.0
	lean = 0.0
	_turn_carry = 0.0
	_boost_cooldown = 0.0
	_boost_time = 0.0
	_roll_input = 0.0
	_roll_tick = 0.0
	_mouse_rolled = false
	_mouse_turn = 0.0
	_mouse_lean = 0.0
	_prev_air_roll = 0.0
	_jump_buffer = 999.0
	state_time = 0.0
	respawned.emit()


# ---------------------------------------------------------------- camera (visual only)

func _process(delta: float) -> void:
	if use_device_input:
		var stick := InputSetup.look_stick()
		if stick.length() > 0.15:
			# Real time, so looking around isn't slowed down in slow motion.
			var pad := tuning.gamepad_look_speed * aim_sensitivity_scale() * delta / maxf(Engine.time_scale, 0.01)
			var pitch_scale := 0.7
			if state == State.AIR:
				pad *= tuning.gamepad_air_spin
				pitch_scale = 1.0
			if weapon and weapon.has_method("look_slowdown"):
				pad *= weapon.look_slowdown()
			_look(-stick.x * pad, -stick.y * pad * pitch_scale * (-1.0 if invert_y else 1.0))
	var w := _kick_omega()
	var ks := _spring(Vector2(_kick_pitch, _kick_yaw), _kick_vel, w, delta)
	var kick: Vector2 = ks[0]
	_kick_vel = ks[1]
	_kick_pitch = minf(kick.x, deg_to_rad(8.0))
	_kick_yaw = clampf(kick.y, deg_to_rad(-3.0), deg_to_rad(3.0))
	var r := _spring(_kick_roll, _kick_roll_vel, w, delta)
	_kick_roll = r[0]
	_kick_roll_vel = r[1]
	_fov_punch *= exp(-14.0 * delta)
	head.rotation = Vector3(pitch + _kick_pitch + roll_spin(), _surface_look_yaw if state == State.SURFACE else 0.0, 0.0)

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
	# (On a wall, lean angles the run instead.)
	var peek_share := lerpf(1.0, tuning.lean_peek_running_share, clampf(horizontal_speed() / tuning.run_speed, 0.0, 1.0))
	_peek = lerpf(_peek, 0.0 if state in [State.AIR, State.WALLRUN] else lean * peek_share, 1.0 - exp(-14.0 * delta))
	target_roll -= _peek * deg_to_rad(tuning.lean_tilt_degrees)
	_roll = lerpf(_roll, target_roll, 1.0 - exp(-10.0 * delta))
	if state == State.AIR:
		var frac := Engine.get_physics_interpolation_fraction() if is_physics_processing() else 1.0
		_air_roll_view = wrapf(lerpf(_prev_air_roll, _air_roll, frac), -PI, PI)
	else:
		_air_roll_view = lerp_angle(_air_roll_view, 0.0, 1.0 - exp(-12.0 * delta))
	camera.rotation = Vector3(0.0, _kick_yaw, _roll - _air_roll_view + _kick_roll)
	# Smooth the view between ticks.
	head.global_transform = visual_transform() * head.transform
	if not _view_offset.is_equal_approx(Quaternion.IDENTITY):
		# Eases out from a standstill (critically damped), so the view starts
		# moving gently instead of jumping.
		_view_offset_time += delta
		var wt := _view_offset_rate * _view_offset_time
		var k := (1.0 + wt) * exp(-wt)
		_view_offset = Quaternion.IDENTITY if k < 0.001 else Quaternion.IDENTITY.slerp(_view_offset_start, k)
		head.global_basis = Basis(_view_offset) * head.global_basis
	camera.position = Vector3(_peek_room(_peek * tuning.lean_offset), 0.0, 0.0)

	var over := clampf((speed - tuning.run_speed) / maxf(tuning.top_speed + 4.0 - tuning.run_speed, 0.1), 0.0, 1.0)
	var target_fov := lerpf(tuning.base_fov + tuning.speed_fov_bonus * over, aim_fov, aim_zoom)
	if _fov_base <= 0.0:
		_fov_base = camera.fov
	_fov_base = lerpf(_fov_base, target_fov, 1.0 - exp(-(6.0 + 20.0 * aim_zoom) * delta))
	camera.fov = _fov_base + _fov_punch * (1.0 - aim_zoom * 0.7)


## Recoil: kicks the view up (and a little sideways), settling back at
## `recovery` per second. Purely visual on top of the aim direction.
## Recoil: the view punches up by about pitch_amount (and yaw_amount, roll)
## over a couple of frames, then settles. Presentation only: the real pitch
## and yaw never change, so aim and flips stay clean. fov_punch widens the
## view for a moment (degrees).
func add_view_kick(pitch_amount: float, yaw_amount: float, recovery: float, roll_amount := 0.0, fov_punch := 0.0) -> void:
	_kick_recovery = recovery
	# A critically damped spring started with this speed peaks at `amount`.
	var w := _kick_omega()
	_kick_vel += Vector2(pitch_amount, yaw_amount) * w * exp(1.0)
	_kick_roll_vel += roll_amount * w * exp(1.0)
	_fov_punch += fov_punch


func _kick_omega() -> float:
	return maxf(_kick_recovery * 2.0, 1.0)


## Advances a critically damped spring (toward 0) exactly, at any frame time.
static func _spring(x: Variant, v: Variant, w: float, dt: float) -> Array:
	var e := exp(-w * dt)
	var c: Variant = v + x * w
	return [(x + c * dt) * e, (v - c * w * dt) * e]


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


## 0..1 through the current vault or mantle (0 otherwise).
func vault_progress() -> float:
	if state not in [State.VAULT, State.MANTLE]:
		return 0.0
	return clampf(state_time / _path_time, 0.0, 1.0)


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
		State.WALLCLIMB:
			tags.append(&"climbing")
		State.VAULT, State.MANTLE:
			tags.append(&"vaulting")
		State.SURFACE:
			tags.append(&"surface")
	if state == State.AIR:
		if absf(_air_pitch) > deg_to_rad(90.0):
			tags.append(&"flipping")
		if absf(_air_yaw) > deg_to_rad(180.0):
			tags.append(&"spinning")
		if absf(_air_roll) > deg_to_rad(90.0):
			tags.append(&"side_flipping")
	if cos(pitch) < 0.0 or cos(_air_roll) < 0.0 or body_up().y < 0.0:
		tags.append(&"upside_down")
	if horizontal_speed() >= tuning.top_speed * 0.9:
		tags.append(&"fast")
	return tags


func debug_text() -> String:
	return "%s  %.1fs" % [State.keys()[state], state_time]
