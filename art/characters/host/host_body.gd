extends Node3D
## The Host's body in the chase: his own model (host.glb, built by
## art/source/build_host.py on the runners' skeleton) driven like a person
## running. Pursuer adds it as a child and sets `pursuer`; it only reads
## his state (position, velocity, lunging, cutting, since_close_in), so it
## can't affect the chase.
##
## Poses come from RunnerPoses, blended here by what he's doing:
##   * the run cycle follows the ground he covers (feet don't skate), with a
##     longer stride for his size and the upper body driving forward;
##   * dropping off a ledge (your path goes down) he falls, then lands in a
##     crouch;
##   * close to you he lunges: chest down, both arms reaching for you;
##   * a set piece that brings him in plays a drop-down landing.
## Heavy footsteps play from where he is, so you hear him gaining.

const BODY_SCRIPT_PATH := "res://art/characters/runner/runner_body.gd"
## He's a big man: shown 1.1x the runners' size.
const SCALE := 1.1
## How fast each pose eases in and out (1/s).
## Dropping in after a shortcut: from this high, over this many ticks.
const DROP_HEIGHT := 4.0
## The layer every camera renders (not RunnerBody.LAYER).
const WORLD_LAYER := 1
const DROP_TICKS := 26
const RATES := {"run": 10.0, "fall": 7.0, "lunge": 9.0, "land": 14.0, "idle": 6.0}

var pursuer: Node3D
var body: Node3D

var _weights := {"run": 0.0, "fall": 0.0, "lunge": 0.0, "land": 0.0, "idle": 1.0}
var _phase := 0.0
var _prev_pos := Vector3.ZERO
var _cur_pos := Vector3.ZERO
var _speed := 0.0
var _vy := 0.0
var _land := 0.0
var _lean := 0.0
var _yaw_basis := Basis.IDENTITY
var _was_visible := false
var _last_step := 0


func _ready() -> void:
	var script := load(BODY_SCRIPT_PATH) as Script if ResourceLoader.exists(BODY_SCRIPT_PATH) else null
	if script == null or not script.can_instantiate():
		push_warning("HostBody: couldn't load the runner body")
		return
	body = script.new()
	body.name = "RunnerBody"
	body.runner = "host"
	add_child(body)
	body.pose_override = RunnerPoses.idle()
	# RunnerBody draws on its own layer, which the first-person camera
	# skips (so you don't see your own body). He's not you: everyone sees him.
	if body.model != null:
		for mi: MeshInstance3D in body.model.find_children("*", "MeshInstance3D", true, false):
			mi.layers = WORLD_LAYER
	# His carbine is for the Head Office fight (enemies/host_boss.gd).
	var gun: Node3D = body.model.find_child("Rifle", true, false) if body.model else null
	if gun != null:
		gun.visible = false


func _process(delta: float) -> void:
	if body == null or pursuer == null:
		return
	delta = minf(delta, 0.1)
	var shown: bool = pursuer.visible
	body.visible = shown
	if not shown:
		_was_visible = false
		return
	var p: Vector3 = pursuer.global_position
	if not _was_visible:
		_prev_pos = p
		_cur_pos = p
		_was_visible = true
	elif p != _cur_pos:
		_prev_pos = _cur_pos
		_cur_pos = p
	# Between physics ticks, like the player's visual_transform.
	var at := _prev_pos.lerp(_cur_pos, Engine.get_physics_interpolation_fraction())
	# A set piece brought him in: he drops down from the floor above.
	var since := int(pursuer.since_close_in)
	if since < DROP_TICKS:
		var k := 1.0 - float(since) / DROP_TICKS
		at.y += DROP_HEIGHT * k * k
	var vel: Vector3 = pursuer.velocity
	var flat := Vector2(vel.x, vel.z).length()
	_speed = lerpf(_speed, flat, 1.0 - exp(-10.0 * delta))
	_vy = lerpf(_vy, vel.y, 1.0 - exp(-12.0 * delta))

	var targets := {}
	var falling := clampf((-_vy - 4.0) / 4.0, 0.0, 1.0)
	if int(pursuer.since_close_in) < 40:
		_land = 1.0
	if falling > 0.5:
		_land = maxf(_land, 0.7)
	elif _land > 0.0 and falling <= 0.01:
		_land = maxf(_land - delta * 2.6, 0.0)
	var moving := clampf(_speed / 2.0, 0.0, 1.0)
	targets["fall"] = falling
	targets["lunge"] = (1.0 - falling) * (1.0 if pursuer.lunging else 0.0)
	targets["land"] = (1.0 - falling) * (_land if falling <= 0.01 else 0.0) * 0.8
	targets["run"] = (1.0 - falling) * moving
	targets["idle"] = (1.0 - falling) * (1.0 - moving)
	for k: String in _weights:
		_weights[k] = lerpf(_weights[k], targets.get(k, 0.0), 1.0 - exp(-float(RATES[k]) * delta))

	# The stride follows ground covered, scaled to his size.
	var cycle_len := (1.4 + 0.27 * _speed) * SCALE
	var before := _phase
	_phase = fposmod(_phase + _speed * delta / cycle_len, 1.0)
	_footsteps(before, at)

	var amount := clampf(_speed / 9.0, 0.0, 1.15)
	var pose := _mix({
		"run": RunnerPoses.run(_phase, amount),
		"fall": RunnerPoses.fall(),
		"lunge": lunge(_phase),
		"land": RunnerPoses.crouch(),
		"idle": RunnerPoses.idle(),
	})
	body.pose_override = pose

	# Facing: where he's heading (Pursuer turns him), eased so corners
	# don't snap. Leaning into speed, more in a lunge.
	_yaw_basis = _yaw_basis.slerp(pursuer.global_basis.orthonormalized(), 1.0 - exp(-10.0 * delta))
	var lean_target: float = deg_to_rad(9.0) * clampf(_speed / 11.0, 0.0, 1.2) + deg_to_rad(10.0) * float(_weights.lunge)
	_lean = lerpf(_lean, lean_target, 1.0 - exp(-8.0 * delta))
	var b := _yaw_basis * Basis(Vector3.RIGHT, -_lean) * Basis(Vector3.UP, PI)
	body.global_transform = Transform3D(b.scaled(Vector3.ONE * SCALE), at)


## Reaching for you mid-stride: chest down, both arms out in front, the
## legs still running.
static func lunge(phase: float) -> Dictionary:
	var pose := RunnerPoses.run(phase, 1.0)
	pose["Spine"] = Vector3(18, 0, 0)
	pose["Chest"] = Vector3(10, 0, 0)
	pose["Neck"] = Vector3(-18, 0, 0)
	pose["Head"] = Vector3(-14, 0, 0)
	var reach := 6.0 * sin(TAU * phase)
	pose["LeftUpperArm"] = Vector3(84 + reach, 0, 14)
	pose["LeftLowerArm"] = Vector3(18, 0, 0)
	pose["LeftHand"] = Vector3(-20, 0, 0)
	pose["RightUpperArm"] = Vector3(84 - reach, 0, -14)
	pose["RightLowerArm"] = Vector3(18, 0, 0)
	pose["RightHand"] = Vector3(-20, 0, 0)
	return pose


func weight(pose_name: String) -> float:
	return _weights.get(pose_name, 0.0)


## Weighted average of the poses (angles, bone by bone).
func _mix(poses: Dictionary) -> Dictionary:
	var total := 0.0
	for k: String in poses:
		total += _weights[k]
	if total <= 0.0001:
		return RunnerPoses.idle()
	var out := {}
	for k: String in poses:
		var w: float = _weights[k] / total
		if w < 0.001:
			continue
		var pose: Dictionary = poses[k]
		for bone: String in pose:
			out[bone] = out.get(bone, Vector3.ZERO) + (pose[bone] as Vector3) * w
	return out


## A heavy footfall each time a foot strikes, when he's on his feet.
func _footsteps(before: float, at: Vector3) -> void:
	if weight("run") + weight("lunge") < 0.5 or _speed < 2.0:
		return
	var crossed := (before < 0.5 and _phase >= 0.5) or _phase < before
	if not crossed:
		return
	var frame := Engine.get_process_frames()
	if frame - _last_step < 6:
		return
	_last_step = frame
	var audio := get_node_or_null("/root/GameAudio")
	if audio != null and audio.has_method("play_at"):
		audio.play_at("land_concrete", at, -4.0)
