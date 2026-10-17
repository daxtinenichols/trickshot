class_name BodyRig
extends Node3D
## Procedural third-person mannequin, posed from the player's state every
## frame. Presentation only: it reads the player and never writes to it, so
## the simulation stays deterministic.
##
## Built from primitive meshes on pivot joints (one Node3D per joint). Feet sit
## at the node origin, facing -Z. Every mesh is on render layer 2 only, so the
## first-person camera (which culls that layer) never sees it.
##
## Each frame the pose code writes per-joint *targets*; the joints then ease
## toward them with frame-rate independent exponential smoothing (quaternion
## slerp, so angles never wrap the long way). Nothing ever snaps.

## Render layer bit for the body (layer 2).
const LAYER := 2

# Body proportions (metres). Hip height = THIGH + SHIN + ANKLE.
const THIGH := 0.43
const SHIN := 0.43
const ANKLE := 0.08
const HIP_HEIGHT := THIGH + SHIN + ANKLE
const UPPER_ARM := 0.29
const FOREARM := 0.26
const SPINE_UP := 0.08
const TORSO := 0.5

## How fast joints chase their targets (1/s). Higher = snappier.
const JOINT_RATE := 20.0
const ROOT_RATE := 24.0
const POS_RATE := 14.0
const KICK_TIME := 0.3
const KICK_TRICKS: Array[StringName] = [&"kick", &"door_kick", &"window_kick", &"kick_off", &"kick_miss"]

const JOINTS: Array[StringName] = [
	&"pelvis", &"spine", &"neck",
	&"shoulder_l", &"elbow_l", &"shoulder_r", &"elbow_r",
	&"hip_l", &"knee_l", &"hip_r", &"knee_r",
]

var player: Player
## Whole-body pivot at the body's centre: flips and rolls rotate this.
var root_pivot: Node3D

var _joints: Dictionary[StringName, Node3D] = {}
var _meshes: Array[MeshInstance3D] = []
# Targets written by the pose code each frame.
var _t: Dictionary[StringName, Vector3] = {}
var _root_rot_t := Vector3.ZERO
var _root_pos_t := Vector3(0.0, HIP_HEIGHT, 0.0)
var _pelvis_pos_t := Vector3.ZERO
var _run_phase := 0.0
var _climb_phase := 0.0
var _kick_left := 0.0
var _kick_boost := 0.0


func _init() -> void:
	name = "BodyRig"
	_build()


## Attach to a player (the rig should be a child of it) and start posing.
func setup(p: Player) -> void:
	player = p
	if not p.trick.is_connected(_on_trick):
		p.trick.connect(_on_trick)


## The pivot for a joint (pelvis, spine, neck, shoulder_l/r, elbow_l/r,
## hip_l/r, knee_l/r, or root).
func joint(joint_name: StringName) -> Node3D:
	if joint_name == &"root":
		return root_pivot
	return _joints.get(joint_name)


## Every mesh in the body (for tests and layer checks).
func meshes() -> Array[MeshInstance3D]:
	return _meshes


## Seconds left on the kick overlay (0 when not kicking).
func kick_left() -> float:
	return _kick_left


func _on_trick(trick_name: StringName, _info: Dictionary) -> void:
	if trick_name in KICK_TRICKS:
		_kick_left = KICK_TIME


# ---------------------------------------------------------------- posing

func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player) or delta <= 0.0:
		return
	_reset_targets()
	var speed := player.horizontal_speed()
	match player.state:
		Player.State.CROUCH: _pose_crouch(speed, delta)
		Player.State.SLIDE: _pose_slide(speed)
		Player.State.ROLL: _pose_roll()
		Player.State.WALLRUN: _pose_wallrun(speed, delta)
		Player.State.WALLCLIMB: _pose_wallclimb(delta)
		Player.State.VAULT: _pose_vault()
		Player.State.MANTLE: _pose_mantle()
		Player.State.STUN: _pose_stun()
		Player.State.PRONE: _pose_prone(speed, delta, false)
		Player.State.PRONE_SLIDE: _pose_prone(speed, delta, true)
		Player.State.AIR: _pose_air()
		_:
			# GROUND, and any state added later: grounded if on the floor.
			if player.is_on_floor() or player.state == Player.State.GROUND:
				_pose_ground(speed, delta)
			else:
				_pose_air()
	if player.state != Player.State.AIR:
		var spine := _t[&"spine"]
		spine.z -= player.lean * 0.35
		_t[&"spine"] = spine
	_overlay_aim()
	_overlay_kick(delta)
	_blend(delta)


func _reset_targets() -> void:
	for j in JOINTS:
		_t[j] = Vector3.ZERO
	_root_rot_t = Vector3.ZERO
	_root_pos_t = Vector3(0.0, HIP_HEIGHT, 0.0)
	_pelvis_pos_t = Vector3.ZERO


## Vertical reach of a leg from the hip for the given joint angles.
static func leg_drop(hip: Vector3, knee: Vector3) -> float:
	return (THIGH * cos(hip.x) + SHIN * cos(hip.x + knee.x)) * cos(hip.z) + ANKLE


## Lowers the pelvis so the lower foot touches the ground (standing poses).
func _plant_feet(extra := 0.0) -> void:
	var drop := maxf(leg_drop(_t[&"hip_l"], _t[&"knee_l"]), leg_drop(_t[&"hip_r"], _t[&"knee_r"]))
	_pelvis_pos_t.y = drop - HIP_HEIGHT + extra


## Sprint cycle on _run_phase, scaled by `amount` (0 = idle stance).
func _run_cycle(amount: float, lean_fwd: float) -> void:
	var s := sin(_run_phase)
	var c := cos(_run_phase)
	# Idle stance underneath; the cycle fades in with speed.
	var hip_l := lerpf(0.05, 0.3 + 0.95 * s, amount)
	var hip_r := lerpf(0.05, 0.3 - 0.95 * s, amount)
	# The swinging leg folds hard under the body (heel to backside).
	var knee_l := lerpf(-0.12, -(0.3 + 1.75 * maxf(c, 0.0)), amount)
	var knee_r := lerpf(-0.12, -(0.3 + 1.75 * maxf(-c, 0.0)), amount)
	_t[&"hip_l"] = Vector3(hip_l, 0.0, lerpf(-0.07, -0.02, amount))
	_t[&"hip_r"] = Vector3(hip_r, 0.0, lerpf(0.07, 0.02, amount))
	_t[&"knee_l"] = Vector3(knee_l, 0.0, 0.0)
	_t[&"knee_r"] = Vector3(knee_r, 0.0, 0.0)
	# Arms pump opposite to the legs, elbows bent.
	_t[&"shoulder_l"] = Vector3(lerpf(0.05, 0.15 - 0.85 * s, amount), 0.0, lerpf(-0.12, -0.1, amount))
	_t[&"shoulder_r"] = Vector3(lerpf(0.35, 0.15 + 0.85 * s, amount), 0.0, lerpf(0.1, 0.1, amount))
	_t[&"elbow_l"] = Vector3(lerpf(0.25, 1.5 + 0.25 * s, amount), 0.0, 0.0)
	_t[&"elbow_r"] = Vector3(lerpf(0.6, 1.5 - 0.25 * s, amount), 0.0, 0.0)
	# Shoulders counter-rotate against the hips.
	_t[&"spine"] = Vector3(-lean_fwd, 0.18 * s * amount, 0.0)
	_t[&"pelvis"] = Vector3(0.0, -0.12 * s * amount, 0.0)
	_t[&"neck"] = Vector3(lean_fwd * 0.6, -0.12 * s * amount, 0.0)


## Stride frequency (cycles/s) rises with speed, like a real sprinter.
static func stride_rate(speed: float) -> float:
	return clampf(0.45 + 0.12 * speed, 0.7, 2.1)


func _pose_ground(speed: float, delta: float) -> void:
	var amount := clampf(speed / 4.0, 0.0, 1.0)
	_run_phase = wrapf(_run_phase + delta * TAU * stride_rate(speed) * amount, 0.0, TAU)
	var tuning := player.tuning
	var fast := clampf((speed - tuning.run_speed) / maxf(tuning.top_speed - tuning.run_speed, 0.1), 0.0, 1.0)
	_run_cycle(amount, lerpf(0.02, 0.2, amount) + 0.12 * fast)
	_plant_feet()


func _pose_crouch(speed: float, delta: float) -> void:
	var amount := clampf(speed / 3.0, 0.0, 1.0)
	_run_phase = wrapf(_run_phase + delta * TAU * 1.4 * amount, 0.0, TAU)
	var s := sin(_run_phase)
	_t[&"hip_l"] = Vector3(1.25 + 0.35 * s * amount, 0.0, -0.18)
	_t[&"hip_r"] = Vector3(1.25 - 0.35 * s * amount, 0.0, 0.18)
	_t[&"knee_l"] = Vector3(-2.0 + 0.3 * maxf(-s, 0.0) * amount, 0.0, 0.0)
	_t[&"knee_r"] = Vector3(-2.0 + 0.3 * maxf(s, 0.0) * amount, 0.0, 0.0)
	_t[&"spine"] = Vector3(-0.5, 0.0, 0.0)
	_t[&"neck"] = Vector3(0.35, 0.0, 0.0)
	_t[&"shoulder_l"] = Vector3(0.6 - 0.3 * s * amount, 0.0, -0.15)
	_t[&"elbow_l"] = Vector3(1.0, 0.0, 0.0)
	_t[&"shoulder_r"] = Vector3(0.9, 0.0, 0.1)
	_t[&"elbow_r"] = Vector3(0.9, 0.0, 0.0)
	_plant_feet()


func _pose_slide(_speed: float) -> void:
	# Feet first, leaning back: left leg out in front, right leg folded under,
	# left hand trailing on the ground, gun hand forward.
	_pelvis_pos_t.y = 0.3 - HIP_HEIGHT
	_t[&"spine"] = Vector3(0.75, 0.0, 0.08)
	_t[&"neck"] = Vector3(-0.55, 0.0, 0.0)
	_t[&"hip_l"] = Vector3(1.4, 0.0, -0.05)
	_t[&"knee_l"] = Vector3(-0.12, 0.0, 0.0)
	_t[&"hip_r"] = Vector3(0.6, 0.0, 0.45)
	_t[&"knee_r"] = Vector3(-2.2, 0.0, 0.0)
	_t[&"shoulder_l"] = Vector3(-0.2, 0.0, -0.75)
	_t[&"elbow_l"] = Vector3(0.15, 0.0, 0.0)
	_t[&"shoulder_r"] = Vector3(0.35, 0.0, 0.2)
	_t[&"elbow_r"] = Vector3(0.9, 0.0, 0.0)


## Knees to chest, arms hugging the shins.
func _tuck(amount: float) -> void:
	_t[&"hip_l"] = _t[&"hip_l"].lerp(Vector3(2.0, 0.0, -0.1), amount)
	_t[&"hip_r"] = _t[&"hip_r"].lerp(Vector3(2.0, 0.0, 0.1), amount)
	_t[&"knee_l"] = _t[&"knee_l"].lerp(Vector3(-2.4, 0.0, 0.0), amount)
	_t[&"knee_r"] = _t[&"knee_r"].lerp(Vector3(-2.4, 0.0, 0.0), amount)
	_t[&"spine"] = _t[&"spine"].lerp(Vector3(-0.55, 0.0, 0.0), amount)
	_t[&"neck"] = _t[&"neck"].lerp(Vector3(-0.35, 0.0, 0.0), amount)
	_t[&"shoulder_l"] = _t[&"shoulder_l"].lerp(Vector3(0.9, 0.0, -0.1), amount)
	_t[&"shoulder_r"] = _t[&"shoulder_r"].lerp(Vector3(0.9, 0.0, 0.1), amount)
	_t[&"elbow_l"] = _t[&"elbow_l"].lerp(Vector3(1.7, 0.0, 0.0), amount)
	_t[&"elbow_r"] = _t[&"elbow_r"].lerp(Vector3(1.7, 0.0, 0.0), amount)


func _pose_roll() -> void:
	var t := player.roll_progress()
	# Same ease as the first-person roll camera, so both views agree.
	_root_rot_t.x = -TAU * t * t * (3.0 - 2.0 * t)
	_root_pos_t.y = 0.5
	_pelvis_pos_t = Vector3(0.0, -0.12, 0.08)
	_tuck(1.0)


func _pose_air() -> void:
	if player.is_diving():
		# Superman dive: flat, arms out in front, legs together.
		_root_rot_t.x = -1.35
		_t[&"shoulder_l"] = Vector3(2.95, 0.0, -0.12)
		_t[&"shoulder_r"] = Vector3(2.95, 0.0, 0.12)
		_t[&"elbow_l"] = Vector3(0.1, 0.0, 0.0)
		_t[&"elbow_r"] = Vector3(0.1, 0.0, 0.0)
		_t[&"spine"] = Vector3(0.12, 0.0, 0.0)
		_t[&"neck"] = Vector3(0.4, 0.0, 0.0)
		_t[&"hip_l"] = Vector3(-0.05, 0.0, -0.03)
		_t[&"hip_r"] = Vector3(-0.05, 0.0, 0.03)
		_t[&"knee_l"] = Vector3(-0.2, 0.0, 0.0)
		_t[&"knee_r"] = Vector3(-0.3, 0.0, 0.0)
		return
	# Loose airborne pose: knee up while rising, legs reaching down to land.
	var rise := clampf(player.velocity.y / 6.0, -1.0, 1.0)
	var up := maxf(rise, 0.0)
	var down := maxf(-rise, 0.0)
	_t[&"hip_l"] = Vector3(lerpf(0.5, 1.2, up) - 0.2 * down, 0.0, -0.1)
	_t[&"hip_r"] = Vector3(lerpf(0.0, -0.2, up) + 0.3 * down, 0.0, 0.1)
	_t[&"knee_l"] = Vector3(lerpf(-0.8, -1.5, up) + 0.3 * down, 0.0, 0.0)
	_t[&"knee_r"] = Vector3(lerpf(-0.6, -0.9, up) + 0.2 * down, 0.0, 0.0)
	_t[&"shoulder_l"] = Vector3(0.5 + 0.4 * up, 0.0, -0.45 - 0.35 * down)
	_t[&"shoulder_r"] = Vector3(0.6 + 0.2 * up, 0.0, 0.3 + 0.3 * down)
	_t[&"elbow_l"] = Vector3(0.6, 0.0, 0.0)
	_t[&"elbow_r"] = Vector3(0.7, 0.0, 0.0)
	_t[&"spine"] = Vector3(-0.1, 0.0, 0.0)
	# Flips: the whole body turns with the view pitch, tucking mid-rotation
	# and opening up again as it comes round to upright.
	var flip := player.air_rotation().y
	var roll := player.air_roll()
	_root_rot_t = Vector3(flip, 0.0, -roll)
	var tuck := clampf(maxf(absf(sin(flip * 0.5)), absf(sin(roll * 0.5))) * 1.6, 0.0, 1.0)
	_tuck(tuck)


func _pose_wallrun(speed: float, delta: float) -> void:
	_run_phase = wrapf(_run_phase + delta * TAU * stride_rate(speed), 0.0, TAU)
	_run_cycle(1.0, 0.12)
	_plant_feet()
	# Which side is the wall on, in the body's own frame? (+1 = right)
	var n := player.wall_normal()
	var side := 0.0
	if n.length_squared() > 0.0001:
		var local := global_basis.orthonormalized().inverse() * -n
		side = signf(local.x) if absf(local.x) > 0.05 else 0.0
	# Tilt toward the wall (a right tilt is -Z) and reach for it.
	_root_rot_t.z = -side * deg_to_rad(25.0)
	if side > 0.0:
		_t[&"shoulder_r"] = Vector3(0.4, 0.0, 1.35)
		_t[&"elbow_r"] = Vector3(0.35, 0.0, 0.0)
	elif side < 0.0:
		_t[&"shoulder_l"] = Vector3(0.4, 0.0, -1.35)
		_t[&"elbow_l"] = Vector3(0.35, 0.0, 0.0)


func _pose_wallclimb(delta: float) -> void:
	_climb_phase = wrapf(_climb_phase + delta * TAU * 2.4, 0.0, TAU)
	var s := sin(_climb_phase)
	var c := cos(_climb_phase)
	# Hands take turns reaching up the wall; feet push alternately.
	_t[&"shoulder_l"] = Vector3(2.55 + 0.45 * s, 0.0, -0.2)
	_t[&"shoulder_r"] = Vector3(2.55 - 0.45 * s, 0.0, 0.2)
	_t[&"elbow_l"] = Vector3(0.5 - 0.4 * s, 0.0, 0.0)
	_t[&"elbow_r"] = Vector3(0.5 + 0.4 * s, 0.0, 0.0)
	_t[&"hip_l"] = Vector3(0.9 - 0.6 * s, 0.0, -0.1)
	_t[&"hip_r"] = Vector3(0.9 + 0.6 * s, 0.0, 0.1)
	_t[&"knee_l"] = Vector3(-1.3 + 0.8 * maxf(-c, 0.0) - 0.4 * s, 0.0, 0.0)
	_t[&"knee_r"] = Vector3(-1.3 + 0.8 * maxf(c, 0.0) + 0.4 * s, 0.0, 0.0)
	_t[&"spine"] = Vector3(-0.1, 0.0, 0.0)
	_t[&"neck"] = Vector3(0.45, 0.0, 0.0)
	_root_rot_t.x = -0.12


func _pose_vault() -> void:
	var t := clampf(player.state_time / maxf(player.tuning.vault_time, 0.05), 0.0, 1.0)
	var arc := sin(PI * t)
	# Side vault: left hand planted, legs swung up and over to the right.
	_root_rot_t.z = 0.25 + 0.2 * arc
	_t[&"spine"] = Vector3(-0.25, 0.0, 0.1)
	_t[&"shoulder_l"] = Vector3(0.35, 0.0, 0.15)
	_t[&"elbow_l"] = Vector3(0.05, 0.0, 0.0)
	_t[&"shoulder_r"] = Vector3(0.8, 0.0, 0.6)
	_t[&"elbow_r"] = Vector3(0.6, 0.0, 0.0)
	_t[&"hip_l"] = Vector3(0.9 + 0.5 * arc, 0.0, 0.5 * arc + 0.1)
	_t[&"hip_r"] = Vector3(1.0 + 0.6 * arc, 0.0, 0.6 + 0.5 * arc)
	_t[&"knee_l"] = Vector3(-0.6, 0.0, 0.0)
	_t[&"knee_r"] = Vector3(-0.3, 0.0, 0.0)


func _pose_mantle() -> void:
	var t := clampf(player.state_time / maxf(player.tuning.mantle_time, 0.05), 0.0, 1.0)
	# Hands start on the ledge and press down past the hips; knees come up.
	_t[&"shoulder_l"] = Vector3(lerpf(1.7, 0.15, t), 0.0, -0.25)
	_t[&"shoulder_r"] = Vector3(lerpf(1.7, 0.15, t), 0.0, 0.25)
	_t[&"elbow_l"] = Vector3(lerpf(1.5, 0.05, t), 0.0, 0.0)
	_t[&"elbow_r"] = Vector3(lerpf(1.5, 0.05, t), 0.0, 0.0)
	var knees := sin(PI * minf(t * 1.2, 1.0))
	_t[&"hip_l"] = Vector3(0.4 + 1.2 * knees, 0.0, -0.1)
	_t[&"hip_r"] = Vector3(0.2 + 1.0 * knees, 0.0, 0.1)
	_t[&"knee_l"] = Vector3(-0.6 - 1.4 * knees, 0.0, 0.0)
	_t[&"knee_r"] = Vector3(-0.5 - 1.2 * knees, 0.0, 0.0)
	_t[&"spine"] = Vector3(-0.45, 0.0, 0.0)
	_t[&"neck"] = Vector3(0.3, 0.0, 0.0)


func _pose_stun() -> void:
	var wob := sin(player.state_time * 7.0)
	_t[&"hip_l"] = Vector3(0.55, 0.0, -0.2)
	_t[&"hip_r"] = Vector3(0.25, 0.0, 0.2)
	_t[&"knee_l"] = Vector3(-1.0, 0.0, 0.0)
	_t[&"knee_r"] = Vector3(-0.8, 0.0, 0.0)
	_t[&"spine"] = Vector3(-0.35, 0.0, 0.15 * wob)
	_t[&"neck"] = Vector3(-0.2, 0.0, -0.1 * wob)
	_t[&"shoulder_l"] = Vector3(0.4, 0.0, -1.25 - 0.25 * wob)
	_t[&"shoulder_r"] = Vector3(0.4, 0.0, 1.25 - 0.25 * wob)
	_t[&"elbow_l"] = Vector3(0.4, 0.0, 0.0)
	_t[&"elbow_r"] = Vector3(0.4, 0.0, 0.0)
	_plant_feet()


func _pose_prone(speed: float, delta: float, sliding: bool) -> void:
	# Flat on the belly, head forward, arms out in front.
	_root_rot_t.x = -PI * 0.5
	_root_pos_t.y = 0.16
	var crawl := 0.0 if sliding else clampf(speed / 2.0, 0.0, 1.0)
	_run_phase = wrapf(_run_phase + delta * TAU * 1.2 * crawl, 0.0, TAU)
	var s := sin(_run_phase) * crawl
	_t[&"spine"] = Vector3(0.12, 0.0, 0.0)
	_t[&"neck"] = Vector3(0.6, 0.0, 0.0)
	_t[&"shoulder_l"] = Vector3(2.85 - 0.35 * s, 0.0, -0.25)
	_t[&"shoulder_r"] = Vector3(2.85 + 0.35 * s, 0.0, 0.25)
	_t[&"elbow_l"] = Vector3(0.15 if sliding else 0.5 + 0.4 * s, 0.0, 0.0)
	_t[&"elbow_r"] = Vector3(0.15 if sliding else 0.5 - 0.4 * s, 0.0, 0.0)
	_t[&"hip_l"] = Vector3(0.0, 0.0, -0.08 - 0.25 * maxf(s, 0.0))
	_t[&"hip_r"] = Vector3(0.0, 0.0, 0.08 + 0.25 * maxf(-s, 0.0))
	_t[&"knee_l"] = Vector3(-0.1 - 0.6 * maxf(s, 0.0), 0.0, 0.0)
	_t[&"knee_r"] = Vector3(-0.1 - 0.6 * maxf(-s, 0.0), 0.0, 0.0)


## Aiming down sights: gun arm comes up to eye level along the view pitch,
## off hand joins it.
func _overlay_aim() -> void:
	var w := clampf(player.aim_zoom, 0.0, 1.0)
	if w <= 0.0 or player.state in [Player.State.ROLL, Player.State.PRONE_SLIDE, Player.State.PRONE, Player.State.WALLCLIMB]:
		return
	var p := clampf(wrapf(player.pitch, -PI, PI), -1.1, 1.1)
	# Shoulder angles are relative to the torso, so undo its lean.
	var arm := PI * 0.5 + p - _t[&"spine"].x
	_t[&"shoulder_r"] = _t[&"shoulder_r"].lerp(Vector3(arm, 0.3, 0.0), w)
	_t[&"elbow_r"] = _t[&"elbow_r"].lerp(Vector3(0.05, 0.0, 0.0), w)
	_t[&"shoulder_l"] = _t[&"shoulder_l"].lerp(Vector3(arm - 0.1, -0.5, 0.0), w)
	_t[&"elbow_l"] = _t[&"elbow_l"].lerp(Vector3(0.45, 0.0, 0.0), w)
	_t[&"neck"] = _t[&"neck"].lerp(Vector3(p * 0.5 - _t[&"spine"].x, 0.0, 0.0), w)


## Front kick on the right leg: chamber, snap out, recover (~0.3 s).
func _overlay_kick(delta: float) -> void:
	_kick_boost = 0.0
	if _kick_left <= 0.0:
		return
	_kick_left = maxf(_kick_left - delta, 0.0)
	var t := 1.0 - _kick_left / KICK_TIME
	var w := sin(PI * t)
	var extend := smoothstep(0.15, 0.55, t)
	_t[&"hip_r"] = _t[&"hip_r"].lerp(Vector3(1.6, 0.0, 0.05), w)
	_t[&"knee_r"] = _t[&"knee_r"].lerp(Vector3(lerpf(-1.8, -0.05, extend), 0.0, 0.0), w)
	_t[&"spine"] = _t[&"spine"].lerp(Vector3(0.3, 0.0, 0.0), w)
	_t[&"shoulder_l"] = _t[&"shoulder_l"].lerp(Vector3(0.6, 0.0, -0.6), w)
	# Kicks are fast: let the joints follow more tightly while it plays.
	_kick_boost = 25.0 * w


func _blend(delta: float) -> void:
	var w := 1.0 - exp(-(JOINT_RATE + _kick_boost) * delta)
	for j in JOINTS:
		var n: Node3D = _joints[j]
		n.quaternion = n.quaternion.slerp(Quaternion.from_euler(_t[j]), w)
	var wr := 1.0 - exp(-ROOT_RATE * delta)
	root_pivot.quaternion = root_pivot.quaternion.slerp(Quaternion.from_euler(_root_rot_t), wr)
	var wp := 1.0 - exp(-POS_RATE * delta)
	root_pivot.position = root_pivot.position.lerp(_root_pos_t, wp)
	var pelvis: Node3D = _joints[&"pelvis"]
	pelvis.position = pelvis.position.lerp(_pelvis_pos_t, wp)


# ---------------------------------------------------------------- building

func _build() -> void:
	var skin := _toon(Color(0.96, 0.75, 0.58))
	var shirt := _toon(Color(0.95, 0.42, 0.16))
	var pants := _toon(Color(0.16, 0.24, 0.45))
	var shoes := _toon(Color(0.95, 0.95, 0.92))
	var dark := _toon(Color(0.1, 0.11, 0.14))
	var accent := _toon(Color(0.2, 0.85, 0.95))

	root_pivot = _pivot(self, &"root", Vector3(0.0, HIP_HEIGHT, 0.0))
	var pelvis := _pivot(root_pivot, &"pelvis", Vector3.ZERO)
	_box(pelvis, Vector3(0.32, 0.18, 0.2), Vector3(0.0, 0.03, 0.0), pants)

	var spine := _pivot(pelvis, &"spine", Vector3(0.0, SPINE_UP, 0.0))
	_capsule(spine, 0.13, 0.36, Vector3(0.0, 0.12, 0.0), shirt, Vector3(1.15, 1.0, 0.8))   # belly
	_box(spine, Vector3(0.4, 0.3, 0.22), Vector3(0.0, 0.33, 0.0), shirt)                   # chest
	_box(spine, Vector3(0.12, 0.2, 0.02), Vector3(0.0, 0.3, -0.112), accent)               # chest stripe (shows the front)
	var neck := _pivot(spine, &"neck", Vector3(0.0, TORSO, 0.0))
	_capsule(neck, 0.05, 0.14, Vector3(0.0, 0.02, 0.0), skin)
	_sphere(neck, 0.125, Vector3(0.0, 0.15, 0.0), skin)                                    # head
	_box(neck, Vector3(0.2, 0.06, 0.06), Vector3(0.0, 0.17, -0.1), dark)                   # visor (shows the face)
	_box(neck, Vector3(0.24, 0.07, 0.24), Vector3(0.0, 0.25, 0.01), dark)                  # cap

	for side in [-1.0, 1.0]:
		var sfx := "_l" if side < 0.0 else "_r"
		var shoulder := _pivot(spine, StringName("shoulder" + sfx), Vector3(0.22 * side, 0.44, 0.0))
		_sphere(shoulder, 0.07, Vector3.ZERO, shirt)
		_capsule(shoulder, 0.055, UPPER_ARM + 0.06, Vector3(0.0, -UPPER_ARM * 0.5, 0.0), shirt)
		var elbow := _pivot(shoulder, StringName("elbow" + sfx), Vector3(0.0, -UPPER_ARM, 0.0))
		_capsule(elbow, 0.045, FOREARM + 0.05, Vector3(0.0, -FOREARM * 0.5, 0.0), skin)
		_sphere(elbow, 0.055, Vector3(0.0, -FOREARM - 0.03, 0.0), skin)                    # hand
		if side > 0.0:
			# Pistol: barrel continues the forearm, grip points along +Z
			# (down when the arm is raised to aim).
			_box(elbow, Vector3(0.04, 0.2, 0.055), Vector3(0.0, -FOREARM - 0.1, -0.02), dark)
			_box(elbow, Vector3(0.035, 0.045, 0.1), Vector3(0.0, -FOREARM - 0.02, 0.04), dark)

		var hip := _pivot(pelvis, StringName("hip" + sfx), Vector3(0.1 * side, 0.0, 0.0))
		_capsule(hip, 0.08, THIGH + 0.08, Vector3(0.0, -THIGH * 0.5, 0.0), pants)
		var knee := _pivot(hip, StringName("knee" + sfx), Vector3(0.0, -THIGH, 0.0))
		_capsule(knee, 0.062, SHIN + 0.06, Vector3(0.0, -SHIN * 0.5, 0.0), pants)
		_box(knee, Vector3(0.11, 0.08, 0.26), Vector3(0.0, -SHIN - 0.04, -0.06), shoes)    # foot

	for j in JOINTS:
		_t[j] = Vector3.ZERO


func _pivot(parent: Node3D, pivot_name: StringName, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = pivot_name
	n.position = pos
	# Quaternion storage: no lossy euler round trip when the body is flat or
	# upside down.
	n.rotation_edit_mode = Node3D.ROTATION_EDIT_MODE_QUATERNION
	parent.add_child(n)
	if pivot_name != &"root":
		_joints[pivot_name] = n
	return n


func _add_mesh(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material, scl := Vector3.ONE) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.position = pos
	m.scale = scl
	m.material_override = mat
	m.layers = LAYER
	# No shadows: the body isn't where the first-person view expects it.
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	_meshes.append(m)
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _add_mesh(parent, b, pos, mat)


func _capsule(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material, scl := Vector3.ONE) -> MeshInstance3D:
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = maxf(height, radius * 2.0)
	c.radial_segments = 12
	c.rings = 4
	return _add_mesh(parent, c, pos, mat, scl)


func _sphere(parent: Node3D, radius: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 16
	s.rings = 8
	return _add_mesh(parent, s, pos, mat)


## Flat toon shading with a dark inverted-hull outline for a readable
## silhouette in the small corner view.
static func _toon(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_TOON
	m.roughness = 0.8
	var outline := StandardMaterial3D.new()
	outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outline.albedo_color = Color(0.05, 0.05, 0.07)
	outline.cull_mode = BaseMaterial3D.CULL_FRONT
	outline.grow = true
	outline.grow_amount = 0.012
	m.next_pass = outline
	return m
