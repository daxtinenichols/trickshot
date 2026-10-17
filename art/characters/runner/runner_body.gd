extends Node3D
## The runner's body, animated from the player's state every frame.
##
## Instead of playing clips, each movement state has a key pose or a cycle
## (RunnerPoses), and every frame the body blends toward the poses that match
## what the player is doing. Weights ease in and out, so any move can flow
## into any other mid-way with no transition clips to author or to pop.
## On top of that:
##   * the run cycle is driven by distance travelled, so feet never skate;
##   * the lowest contact point is kept on the ground, which gives crouches,
##     slides, rolls and landings the right height for free;
##   * the upper body and head turn toward where the player aims;
##   * flips, spins and rolls rotate the whole body around its center.
##
## Read-only: it never writes to the player, so it can't affect gameplay or
## determinism. Shown on ArtLook.BODY_LAYER (third-person cameras only).

const MODEL := preload("res://art/characters/runner/runner.glb")
const TOON_SHADER := preload("res://art/shaders/toon.gdshader")
const MotionTrails := preload("res://art/fx/motion_trails.gd")
const BODY_LAYER := 1 << 9

## Bones whose x angle is mirrored so that + always means "tip forward"
## (they hang down in the reference pose).
const HANGING := ["LeftUpperLeg", "LeftLowerLeg", "RightUpperLeg", "RightLowerLeg",
	"LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand"]
## Upper arms are lowered from the model's T-pose into this reference.
const ARM_DROP_DEG := 80.0
## Points that touch the ground, with their distance from the joint (m).
const CONTACTS := {
	"LeftToes": 0.03, "RightToes": 0.03, "LeftFoot": 0.08, "RightFoot": 0.08,
	"LeftLowerLeg": 0.06, "RightLowerLeg": 0.06, "LeftHand": 0.04, "RightHand": 0.04,
	"Hips": 0.13, "UpperChest": 0.13, "Head": 0.12,
}
## States where the body stands, crouches or lies on the floor.
const GROUNDED_STATES := [Player.State.GROUND, Player.State.CROUCH, Player.State.SLIDE,
	Player.State.ROLL, Player.State.STUN, Player.State.PRONE, Player.State.PRONE_SLIDE]
## How fast each pose eases in/out (1/s). Higher = snappier.
const BLEND_RATE := {
	"idle": 6.0, "run": 10.0, "crouch": 12.0, "slide": 12.0, "rise": 9.0, "fall": 6.0,
	"tuck": 12.0, "vault": 16.0, "mantle_hang": 16.0, "mantle_push": 14.0, "wallrun": 14.0,
	"climb": 14.0, "stun": 14.0, "prone": 8.0, "dive": 12.0, "kick": 22.0,
}

var player: Player
var model: Node3D
var skeleton: Skeleton3D
var trails: Node3D
## When set, the body holds this pose instead of following the player.
## Used by the pose preview tool.
var pose_override: Dictionary = {}

var _bones := {}  # name -> index
var _ref_local := {}  # index -> Quaternion
var _ref_global := {}  # index -> Quaternion
var _hips_rest := Vector3.ZERO
var _weights := {}
var _phase := 0.0
var _climb_phase := 0.0
var _heading := 0.0
var _prev_view_yaw := 0.0
var _turn_lean := 0.0
var _wall_side := 1.0
var _tuck := 0.0
var _prev_air_pitch := 0.0
var _land_crouch := 0.0
var _kick_time := 99.0
var _ground_offset := 0.0
var _root_pitch := 0.0
var _root_roll := 0.0
var _pivot := Vector3(0, 0.95, 0)
var _grounded := 1.0


func _ready() -> void:
	top_level = true
	model = MODEL.instantiate()
	add_child(model)
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	var mat := ShaderMaterial.new()
	mat.shader = TOON_SHADER
	mat.set_shader_parameter("base_color", Color.WHITE)
	mat.set_shader_parameter("use_vertex_color", true)
	mat.set_shader_parameter("rim_strength", 0.5)
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = mat
		mi.layers = BODY_LAYER
	_build_reference()
	for k: String in BLEND_RATE:
		_weights[k] = 0.0
	_weights["idle"] = 1.0


func setup(p: Player) -> void:
	player = p
	_heading = p.yaw + PI
	_prev_view_yaw = p.yaw
	p.landed.connect(_on_landed)
	p.trick.connect(_on_trick)
	p.respawned.connect(func() -> void: _heading = player.yaw + PI)
	trails = MotionTrails.new()
	add_child(trails)
	trails.setup(p, self)


func bone_world_position(bone_name: String) -> Vector3:
	var i: int = _bones[bone_name]
	return skeleton.global_transform * skeleton.get_bone_global_pose(i).origin


func weight(pose_name: String) -> float:
	return _weights.get(pose_name, 0.0)


func _build_reference() -> void:
	for i in skeleton.get_bone_count():
		_bones[skeleton.get_bone_name(i)] = i
	_hips_rest = skeleton.get_bone_rest(_bones["Hips"]).origin
	var rest_global := {}
	for i in _ordered_bones():
		var parent := skeleton.get_bone_parent(i)
		var local := skeleton.get_bone_rest(i).basis.get_rotation_quaternion()
		var parent_rest: Quaternion = rest_global[parent] if parent >= 0 else Quaternion.IDENTITY
		rest_global[i] = parent_rest * local
		var name := skeleton.get_bone_name(i)
		if name.ends_with("UpperArm"):
			# Arms down at the sides: the neutral pose every arm angle is from.
			var side := 1.0 if name.begins_with("Left") else -1.0
			var drop := Quaternion(Vector3.BACK, deg_to_rad(-ARM_DROP_DEG) * side)
			var g: Quaternion = rest_global[i]
			local = local * (g.inverse() * drop * g)
		_ref_local[i] = local
		var parent_ref: Quaternion = _ref_global[parent] if parent >= 0 else Quaternion.IDENTITY
		_ref_global[i] = parent_ref * local


func _ordered_bones() -> Array[int]:
	# Parents before children.
	var order: Array[int] = []
	var stack: Array = Array(skeleton.get_parentless_bones())
	while not stack.is_empty():
		var i: int = stack.pop_back()
		order.append(i)
		stack.append_array(skeleton.get_bone_children(i))
	return order


# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	if player == null and pose_override.is_empty():
		return
	if not pose_override.is_empty():
		_apply_pose(pose_override)
		_place_root(0.0, Vector3.ZERO, 0.0, 0.0)
		return
	delta = minf(delta, 0.1)
	var targets := _targets(delta)
	for k: String in _weights:
		var rate: float = BLEND_RATE[k]
		_weights[k] = lerpf(_weights[k], targets.get(k, 0.0), 1.0 - exp(-rate * delta))
	_apply_pose(_blend())
	_update_root(delta)


## Which poses the player's current state calls for (weights 0..1).
func _targets(delta: float) -> Dictionary:
	var t := {}
	var speed := player.horizontal_speed()
	var vel := player.velocity
	_land_crouch = maxf(_land_crouch - delta * 2.4, 0.0)
	_kick_time += delta
	var air := player.air_rotation()
	var flip_rate := absf(air.y - _prev_air_pitch) / maxf(delta, 0.001)
	_prev_air_pitch = air.y
	_tuck = lerpf(_tuck, clampf(flip_rate / 7.0, 0.0, 1.0), 1.0 - exp(-8.0 * delta))

	# The run cycle follows distance travelled, so feet plant without sliding.
	var cycle_len := 1.4 + 0.27 * speed
	_phase = fposmod(_phase + speed * delta / cycle_len * _run_direction(), 1.0)

	match player.state:
		Player.State.GROUND:
			var moving := clampf(speed / 2.0, 0.0, 1.0)
			t["run"] = moving
			t["idle"] = 1.0 - moving
		Player.State.CROUCH:
			t["crouch"] = 1.0 - 0.3 * clampf(speed / 3.0, 0.0, 1.0)
			t["run"] = 0.3 * clampf(speed / 3.0, 0.0, 1.0)
		Player.State.SLIDE:
			t["slide"] = 1.0
		Player.State.AIR:
			if player.get("_diving"):
				t["dive"] = 1.0
			else:
				var rise := clampf(vel.y / 5.0 + 0.4, 0.0, 1.0)
				var tuck := maxf(_tuck, clampf(absf(air.x) / PI, 0.0, 0.6) * 0.5)
				t["tuck"] = tuck
				t["rise"] = rise * (1.0 - tuck)
				t["fall"] = (1.0 - rise) * (1.0 - tuck)
		Player.State.VAULT:
			t["vault"] = 1.0
		Player.State.MANTLE:
			var k := _path_progress()
			t["mantle_hang"] = 1.0 - smoothstep(0.2, 0.7, k)
			t["mantle_push"] = smoothstep(0.2, 0.7, k)
		Player.State.WALLRUN:
			t["wallrun"] = 1.0
		Player.State.WALLCLIMB:
			_climb_phase = fposmod(_climb_phase + delta * 2.4, 1.0)
			t["climb"] = 1.0
		Player.State.ROLL:
			t["tuck"] = 1.0
		Player.State.STUN:
			t["stun"] = 1.0
		Player.State.PRONE:
			t["prone"] = 1.0
		Player.State.PRONE_SLIDE:
			t["dive"] = 1.0
	if _land_crouch > 0.0 and player.state in [Player.State.GROUND, Player.State.CROUCH]:
		t["crouch"] = maxf(t.get("crouch", 0.0), _land_crouch)
	if _kick_time < 0.32:
		t["kick"] = 1.0 - smoothstep(0.2, 0.32, _kick_time)
	return t


func _blend() -> Dictionary:
	var speed := player.horizontal_speed() if player else 0.0
	var amount := clampf(speed / 9.0, 0.0, 1.15)
	var wall := _wall_normal()
	if wall != Vector3.ZERO:
		var fwd := MovementMath.horizontal(player.velocity).normalized()
		var right := Vector3(-fwd.z, 0.0, fwd.x)
		_wall_side = signf(right.dot(-wall)) if absf(right.dot(-wall)) > 0.1 else _wall_side
	var poses := {}
	for k: String in _weights:
		if _weights[k] < 0.002:
			continue
		match k:
			"idle": poses[k] = RunnerPoses.idle()
			"run": poses[k] = RunnerPoses.run(_phase, amount)
			"crouch": poses[k] = RunnerPoses.crouch()
			"slide": poses[k] = RunnerPoses.slide()
			"rise": poses[k] = RunnerPoses.jump_rise()
			"fall": poses[k] = RunnerPoses.fall()
			"tuck": poses[k] = RunnerPoses.tuck()
			"vault": poses[k] = RunnerPoses.vault()
			"mantle_hang": poses[k] = RunnerPoses.mantle_hang()
			"mantle_push": poses[k] = RunnerPoses.mantle_push()
			"wallrun": poses[k] = RunnerPoses.wallrun(_phase, _wall_side)
			"climb": poses[k] = RunnerPoses.climb(_climb_phase)
			"stun": poses[k] = RunnerPoses.stun()
			"prone": poses[k] = RunnerPoses.prone()
			"dive": poses[k] = RunnerPoses.dive()
			"kick": poses[k] = RunnerPoses.kick()
	var out := _weighted(poses)
	_add_aim(out)
	return out


## Weighted average of poses, joint by joint (quaternion blend).
func _weighted(poses: Dictionary) -> Dictionary:
	var acc := {}  # bone -> [Quaternion, total weight]
	var total := 0.0
	for k: String in poses:
		total += _weights[k]
	if total <= 0.0:
		return {}
	for bone: String in _bones:
		var q := Quaternion.IDENTITY
		var w_sum := 0.0
		for k: String in poses:
			var w: float = _weights[k] / total
			var e: Vector3 = poses[k].get(bone, Vector3.ZERO)
			w_sum += w
			q = q.slerp(_to_quat(bone, e), w / w_sum)
		acc[bone] = q
	return acc


## Turns the chest and head toward where the player is looking.
func _add_aim(pose: Dictionary) -> void:
	if player == null:
		return
	var view_heading := player.yaw + PI
	var twist := clampf(wrapf(view_heading - _heading, -PI, PI), deg_to_rad(-70.0), deg_to_rad(70.0))
	var look := clampf(player.pitch, deg_to_rad(-50.0), deg_to_rad(50.0)) * (1.0 - _tuck)
	var aim_weight := 1.0 - weight("prone") - weight("tuck") * 0.7
	for part: Array in [["Spine", 0.25, 0.0], ["Chest", 0.35, 0.25], ["Neck", 0.2, 0.35], ["Head", 0.2, 0.4]]:
		var extra := Quaternion.from_euler(Vector3(-look * part[2], twist * part[1], 0.0) * aim_weight)
		pose[part[0]] = extra * pose.get(part[0], Quaternion.IDENTITY)


func _to_quat(bone: String, e: Vector3) -> Quaternion:
	var x := -e.x if bone in HANGING else e.x
	var r := Vector3(deg_to_rad(x), deg_to_rad(e.y), deg_to_rad(e.z))
	return Basis.from_euler(r, EULER_ORDER_YXZ).get_rotation_quaternion()


## Applies a pose of character-space rotations. Accepts Quaternions (from
## blending) or Vector3 degrees (raw pose data, e.g. the preview tool).
func _apply_pose(pose: Dictionary) -> void:
	for bone: String in _bones:
		var i: int = _bones[bone]
		var r: Variant = pose.get(bone, Quaternion.IDENTITY)
		var q: Quaternion = r if r is Quaternion else _to_quat(bone, r)
		var g: Quaternion = _ref_global[i]
		skeleton.set_bone_pose_rotation(i, _ref_local[i] * (g.inverse() * q * g))
	skeleton.set_bone_pose_position(_bones["Hips"], _hips_rest)


# ---------------------------------------------------------------- root

func _update_root(delta: float) -> void:
	var vel := MovementMath.horizontal(player.velocity)
	var speed := vel.length()
	var target := player.yaw + PI
	var rate := 10.0
	match player.state:
		Player.State.AIR:
			rate = 22.0  # spins: the body turns with the view
		Player.State.WALLCLIMB:
			var n := _wall_normal()
			if n != Vector3.ZERO:
				target = atan2(-n.x, -n.z)
		_:
			if speed > 1.0 and _run_direction() > 0.0:
				target = atan2(vel.x, vel.z)
	if player.state in [Player.State.WALLRUN, Player.State.VAULT, Player.State.MANTLE, Player.State.SLIDE, Player.State.PRONE_SLIDE] and speed > 0.5:
		target = atan2(vel.x, vel.z)
	var before := _heading
	_heading = lerp_angle(_heading, target, 1.0 - exp(-rate * delta))
	var turn_rate := wrapf(_heading - before, -PI, PI) / maxf(delta, 0.001)

	# Leaning: into turns when running, away from the wall on a wallrun.
	var lean_target := clampf(-turn_rate * speed * 0.035, -0.45, 0.45) * weight("run")
	_turn_lean = lerpf(_turn_lean, lean_target, 1.0 - exp(-8.0 * delta))
	var roll := _turn_lean - deg_to_rad(28.0) * _wall_side * weight("wallrun")

	# Whole-body rotation: flips in the air, forward roll, lying down.
	var air := player.air_rotation()
	var pitch := 0.0
	var pivot := Vector3(0, 0.95, 0)
	var offset := Vector3.ZERO
	if player.state == Player.State.AIR and not player.get("_diving"):
		pitch = wrapf(-air.y, -PI, PI)
	elif player.state == Player.State.ROLL:
		pitch = wrapf(TAU * clampf(player.state_time / player.tuning.roll_time, 0.0, 1.0), -PI, PI)
		pivot = Vector3(0, 0.5, 0)
	var lie := weight("prone") + weight("dive") * 0.9
	pitch += deg_to_rad(88.0) * lie
	offset += Vector3(0, 0.15, -0.85) * lie
	_root_pitch = lerp_angle(_root_pitch, pitch, 1.0 - exp(-30.0 * delta))
	_root_roll = lerpf(_root_roll, roll, 1.0 - exp(-12.0 * delta))
	_pivot = _pivot.lerp(pivot, 1.0 - exp(-12.0 * delta))
	var on_ground := 1.0 if player.state in GROUNDED_STATES else 0.0
	_grounded = lerpf(_grounded, on_ground, 1.0 - exp(-14.0 * delta))
	_place_root(_root_pitch, offset, _root_roll, delta)


func _place_root(pitch: float, offset: Vector3, roll: float, delta: float) -> void:
	var rot := Basis.from_euler(Vector3(pitch, 0.0, roll), EULER_ORDER_YXZ)
	var local := Transform3D(rot, _pivot - rot * _pivot + offset)
	# Keep the lowest contact point on the ground in grounded states.
	var lowest := INF
	for bone: String in CONTACTS:
		var p := local * skeleton.get_bone_global_pose(_bones[bone]).origin
		lowest = minf(lowest, p.y - CONTACTS[bone])
	var target := -lowest * _grounded if player else -lowest
	_ground_offset = target if delta <= 0.0 else lerpf(_ground_offset, target, 1.0 - exp(-40.0 * delta))
	local.origin.y += _ground_offset
	model.transform = local
	if player:
		global_transform = Transform3D(Basis(Vector3.UP, _heading), player.global_position)


# ---------------------------------------------------------------- helpers

## +1 running forward, -1 backing up (the cycle plays in reverse).
func _run_direction() -> float:
	var vel := MovementMath.horizontal(player.velocity)
	if vel.length() < 0.5:
		return 1.0
	return -1.0 if vel.normalized().dot(player.forward()) < -0.3 else 1.0


func _path_progress() -> float:
	var total: Variant = player.get("_path_time")
	return clampf(player.state_time / float(total), 0.0, 1.0) if total else 0.5


func _wall_normal() -> Vector3:
	var n: Variant = player.get("_wall_normal")
	return n if n is Vector3 else Vector3.ZERO


func _on_landed(fall_speed: float) -> void:
	_land_crouch = clampf(fall_speed / 14.0, 0.0, 0.7)


func _on_trick(trick_name: StringName, _info: Dictionary) -> void:
	if String(trick_name).contains("kick"):
		_kick_time = 0.0
