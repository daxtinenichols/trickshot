class_name RunnerBody
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
##   * flips, side flips, spins and rolls rotate the whole body around its
##     center, and the gun arm comes up when aiming.
##
## Everything is in the player's own frame, so the body tilts with it on
## ramps and loops (SURFACE).
##
## Read-only: it never writes to the player, so it can't affect gameplay or
## determinism. Shown on LAYER, which only third-person cameras render.

const MODEL := preload("res://art/characters/runner/runner.glb")
## Every runner's model, picked by the player's "runner" meta (set by
## campaign missions: "parker" or "echo"). They share one skeleton, so every
## pose works on each. Loaded by path: a model that isn't imported yet falls
## back to Parker instead of breaking the body.
const MODELS := {
	"parker": "res://art/characters/runner/runner.glb",
	"echo": "res://art/characters/runner/echo.glb",
	# Not playable: Mags, the Line's dispatcher (art/characters/runner/runner_figure.gd).
	"mags": "res://art/characters/runner/mags.glb",
	# Not a runner: the Host in the chase (art/characters/host/host_body.gd).
	"host": "res://art/characters/host/host.glb",
}
const TOON_SHADER := preload("res://art/shaders/toon.gdshader")
const MotionTrails := preload("res://art/fx/motion_trails.gd")
## Render layer 2: the first-person camera skips it, third-person cameras
## (the chase cam, tool cameras) see it.
const LAYER := 2

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
## States where the body stands, crouches or rolls on the floor.
const GROUNDED_STATES := [Player.State.GROUND, Player.State.CROUCH, Player.State.SLIDE,
	Player.State.ROLL, Player.State.STUN,
	Player.State.SURFACE]
## How fast each pose eases in/out (1/s). Higher = snappier.
const BLEND_RATE := {
	"idle": 6.0, "run": 10.0, "crouch": 12.0, "slide": 12.0, "rise": 9.0, "fall": 6.0,
	"tuck": 12.0, "vault": 16.0, "mantle_hang": 16.0, "mantle_push": 14.0, "wallrun": 14.0,
	"climb": 14.0, "stun": 14.0, "kick": 22.0,
}

var player: Player
var model: Node3D
var skeleton: Skeleton3D
var trails: Node3D
## Which runner's model is shown. Set it before adding the body to the tree
## (e.g. for a stand-in character), or let the player's "runner" meta pick.
var runner := "parker"
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
## Facing, in the player's frame (PI = where the player looks).
var _heading := PI
var _last_yaw := 0.0
## The pose actually shown: eases toward the blended pose so state changes,
## overlays and noisy inputs never pop a joint.
var _shown := {}
## Hip fire raises the gun arm for a moment; each shot kicks it.
var _fire_raise := 0.0
var _prev_speed := 0.0
var _accel := 0.0
var _drive := 0.0
var _recoil := 0.0
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
	var parent := get_parent()
	if parent != null and parent.has_meta("runner"):
		runner = String(parent.get_meta("runner"))
	_load_model()
	for k: String in BLEND_RATE:
		_weights[k] = 0.0
	_weights["idle"] = 1.0


## True when the editor has imported the asset (its .import file points at
## an imported copy that exists), so load() won't fail with errors.
func _imported(path: String) -> bool:
	if path == "" or not ResourceLoader.exists(path):
		return false
	var cfg := ConfigFile.new()
	if cfg.load(path + ".import") != OK:
		return true  # no import file to check against; let load() decide
	var remap := String(cfg.get_value("remap", "path", ""))
	return remap == "" or FileAccess.file_exists(remap)


## Reads a .glb straight from disk when the editor hasn't imported it yet
## (a freshly copied model shows up before Project > Reload Current
## Project), so the runner still gets their own model instead of Parker's.
func _load_gltf_file(path: String) -> Node3D:
	if path == "" or not FileAccess.file_exists(path):
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		return null
	var scene := doc.generate_scene(state) as Node3D
	if scene != null and scene.find_children("*", "Skeleton3D", true, false).is_empty():
		scene.free()
		return null
	return scene


## Swaps the shown model ("parker", "echo"). Call it before anything is
## attached to the skeleton (the gun look's hand); setup() does it for you.
func set_runner(runner_name: String) -> void:
	if runner_name == runner and model != null:
		return
	runner = runner_name
	if model != null:
		remove_child(model)
		model.free()
	_load_model()


func _load_model() -> void:
	var path: String = MODELS.get(runner, "")
	model = null
	if runner != "parker":
		var res: Resource = load(path) if _imported(path) else null
		if res is PackedScene:
			model = res.instantiate()
		else:
			model = _load_gltf_file(path)
		if model == null:
			push_warning("RunnerBody: no model for runner '%s' (%s), showing Parker (reload the project if it was just added)" % [runner, path])
	if model == null:
		model = MODEL.instantiate()
	model.name = "Model"
	add_child(model)
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	var mat := ShaderMaterial.new()
	mat.shader = TOON_SHADER
	mat.set_shader_parameter("base_color", Color.WHITE)
	mat.set_shader_parameter("use_vertex_color", true)
	mat.set_shader_parameter("rim_strength", 0.5)
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = mat
		mi.layers = LAYER
	_bones.clear()
	_ref_local.clear()
	_ref_global.clear()
	_build_reference()


func setup(p: Player) -> void:
	player = p
	if p.has_meta("runner"):
		set_runner(String(p.get_meta("runner")))
	_heading = PI
	_last_yaw = p.yaw
	p.landed.connect(_on_landed)
	p.trick.connect(_on_trick)
	p.respawned.connect(func() -> void:
		_heading = PI
		_last_yaw = p.yaw)
	# The gun is read by name, not class, so the body works without one.
	var gun: Node = p.get("weapon")
	if gun and gun.has_signal("shot"):
		gun.shot.connect(func(_a: Vector3, _b: Vector3, _r: Dictionary) -> void:
			_fire_raise = 1.0
			_recoil = 1.0)
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
	# Hold the raised arm a beat after a hip-fire shot, then lower it.
	_fire_raise = maxf(_fire_raise - delta * 1.6, 0.0)
	_recoil = maxf(_recoil - delta * 9.0, 0.0)
	var targets := _targets(delta)
	for k: String in _weights:
		var rate: float = BLEND_RATE[k]
		_weights[k] = lerpf(_weights[k], targets.get(k, 0.0), 1.0 - exp(-rate * delta))
	_apply_pose(_ease_pose(_blend(), delta))
	_update_root(delta)


## Which poses the player's current state calls for (weights 0..1).
func _targets(delta: float) -> Dictionary:
	var t := {}
	var vel := _local_velocity()
	var speed := Vector2(vel.x, vel.z).length()
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
		Player.State.SURFACE when player.is_sliding():
			t["slide"] = 1.0
		Player.State.GROUND, Player.State.SURFACE:
			var moving := clampf(speed / 2.0, 0.0, 1.0)
			t["run"] = moving
			t["idle"] = 1.0 - moving
		Player.State.CROUCH:
			t["crouch"] = 1.0 - 0.3 * clampf(speed / 3.0, 0.0, 1.0)
			t["run"] = 0.3 * clampf(speed / 3.0, 0.0, 1.0)
		Player.State.SLIDE:
			t["slide"] = 1.0
		Player.State.AIR:
			_air_targets(t, vel, air)
		Player.State.VAULT:
			t["vault"] = 1.0
		Player.State.MANTLE:
			var k := player.vault_progress()
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
		_:
			# A state added later: stand or fall until it gets its own pose.
			if player.is_on_floor():
				t["run"] = clampf(speed / 2.0, 0.0, 1.0)
				t["idle"] = 1.0 - t["run"]
			else:
				_air_targets(t, vel, air)
	if _land_crouch > 0.0 and player.state in [Player.State.GROUND, Player.State.CROUCH]:
		t["crouch"] = maxf(t.get("crouch", 0.0), _land_crouch)
	if _kick_time < 0.32:
		t["kick"] = 1.0 - smoothstep(0.2, 0.32, _kick_time)
	return t


func _air_targets(t: Dictionary, vel: Vector3, air: Vector2) -> void:
	var rise := clampf(vel.y / 5.0 + 0.4, 0.0, 1.0)
	var spinning := maxf(absf(air.x) / PI, absf(player.air_roll()) / PI)
	var tuck := maxf(_tuck, clampf(spinning, 0.0, 0.6) * 0.5)
	t["tuck"] = tuck
	t["rise"] = rise * (1.0 - tuck)
	t["fall"] = (1.0 - rise) * (1.0 - tuck)


func _blend() -> Dictionary:
	var vel := _local_velocity()
	var amount := clampf(Vector2(vel.x, vel.z).length() / 9.0, 0.0, 1.15)
	var wall := _local(player.wall_normal())
	if wall != Vector3.ZERO and player.state == Player.State.WALLRUN:
		# Which side of the body the wall is on, in the body's own frame.
		var fwd := Vector3(sin(_heading), 0.0, cos(_heading))
		var right := Vector3(-fwd.z, 0.0, fwd.x)
		var d := right.dot(-wall)
		_wall_side = signf(d) if absf(d) > 0.1 else _wall_side
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
			"kick": poses[k] = RunnerPoses.kick()
	# The kick is an overlay: it takes over the body on top of whatever the
	# other poses blend to, instead of being averaged in with them.
	var kick: Variant = poses.get("kick")
	poses.erase("kick")
	var out := _weighted(poses)
	if kick != null:
		for bone: String in _bones:
			var base: Quaternion = out.get(bone, Quaternion.IDENTITY)
			out[bone] = base.slerp(_to_quat(bone, kick.get(bone, Vector3.ZERO)), weight("kick"))
	_add_lean(out)
	_add_gun_hold(out)
	_add_aim(out)
	return out


## How fast the shown pose follows the blended one (1/s): fast enough to
## keep kicks and flips crisp, slow enough to round off any snap.
const POSE_EASE := 24.0


func _ease_pose(pose: Dictionary, delta: float) -> Dictionary:
	var k := 1.0 - exp(-POSE_EASE * delta)
	for bone: String in _bones:
		var target: Quaternion = pose.get(bone, Quaternion.IDENTITY)
		_shown[bone] = target if not _shown.has(bone) else (_shown[bone] as Quaternion).slerp(target, k)
	return _shown


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


## Turns the chest and head toward where the player is looking, and brings
## the gun arm up along the view while aiming down sights.
func _add_aim(pose: Dictionary) -> void:
	var twist := clampf(wrapf(PI - _heading, -PI, PI), deg_to_rad(-70.0), deg_to_rad(70.0))
	var look := clampf(player.pitch, deg_to_rad(-50.0), deg_to_rad(50.0)) * (1.0 - _tuck)
	var aim_weight := clampf(1.0 - weight("tuck") * 0.7, 0.0, 1.0)
	for part: Array in [["Spine", 0.25, 0.0], ["Chest", 0.35, 0.25], ["Neck", 0.2, 0.35], ["Head", 0.2, 0.4]]:
		var extra := Quaternion.from_euler(Vector3(-look * part[2], twist * part[1], 0.0) * aim_weight)
		pose[part[0]] = extra * pose.get(part[0], Quaternion.IDENTITY)
	var fire := smoothstep(0.0, 0.35, _fire_raise)
	var ads := maxf(clampf(player.aim_zoom, 0.0, 1.0), fire) * aim_weight * (1.0 - _reload_weight())
	if ads > 0.001:
		# The spine and chest already carry a quarter of the look pitch.
		var raise := 90.0 + rad_to_deg(look) * 0.75 + 7.0 * _recoil
		var arm := {"RightUpperArm": Vector3(raise, 0, -6), "RightLowerArm": Vector3(4 + 14.0 * _recoil, 0, 0), "RightHand": Vector3(0, 0, 0)}
		for bone: String in arm:
			pose[bone] = (pose.get(bone, Quaternion.IDENTITY) as Quaternion).slerp(_to_quat(bone, arm[bone]), ads)


## How much of the gun-arm pose applies: full when running, standing or in
## the air; less while the hands are busy (climbing, mantling, vaulting).
func _gun_hold_weight() -> float:
	var busy := weight("climb") + weight("mantle_hang") + weight("mantle_push") + weight("vault") * 0.7 \
		+ weight("stun") + weight("tuck") * 0.4 + weight("wallrun") * 0.3
	return clampf(1.0 - busy, 0.0, 1.0)


## 0..1 through the middle of a reload (eased in and out), else 0.
func _reload_weight() -> float:
	var gun: Node = player.get("weapon")
	if gun == null or not gun.has_method("reload_progress"):
		return 0.0
	var t: float = gun.reload_progress()
	return 0.0 if t < 0.0 else smoothstep(0.0, 0.18, t) * (1.0 - smoothstep(0.82, 1.0, t))


## The gun hand at low ready: forearm forward, muzzle a little down, with a
## small swing in the run. A reload brings the gun up and the other hand to it.
func _add_gun_hold(pose: Dictionary) -> void:
	var hold := _gun_hold_weight()
	if hold <= 0.001:
		return
	var swing := sin(TAU * _phase) * weight("run")
	var ready := {
		"RightUpperArm": Vector3(16 + 10 * swing, 0, -10),
		"RightLowerArm": Vector3(68, 0, 0),
		"RightHand": Vector3(-8, 0, 0),
	}
	var reload := _reload_weight()
	if reload > 0.0:
		var t: float = (player.get("weapon") as Node).reload_progress()
		var jiggle := sin(t * TAU * 2.0) * 6.0
		ready["RightUpperArm"] = ready["RightUpperArm"].lerp(Vector3(26, 0, -4), reload)
		ready["RightLowerArm"] = ready["RightLowerArm"].lerp(Vector3(100 + jiggle, 0, 0), reload)
		ready["RightHand"] = ready["RightHand"].lerp(Vector3(-24, 0, 0), reload)
		for bone: String in ["LeftUpperArm", "LeftLowerArm", "LeftHand"]:
			var to: Vector3 = {"LeftUpperArm": Vector3(34, 0, -24), "LeftLowerArm": Vector3(96 - jiggle, 0, 0), "LeftHand": Vector3(-10, 0, 0)}[bone]
			pose[bone] = (pose.get(bone, Quaternion.IDENTITY) as Quaternion).slerp(_to_quat(bone, to), reload * hold)
	for bone: String in ready:
		pose[bone] = (pose.get(bone, Quaternion.IDENTITY) as Quaternion).slerp(_to_quat(bone, ready[bone]), hold)


## Leaning (the player's lean input) bends the upper body to the side.
func _add_lean(pose: Dictionary) -> void:
	var bend := deg_to_rad(14.0) * player.lean * (1.0 - _tuck)
	for bone: String in ["Spine", "Chest"]:
		pose[bone] = Quaternion(Vector3.RIGHT, _drive * 0.5) * Quaternion(Vector3.BACK, bend) * pose.get(bone, Quaternion.IDENTITY)


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
	var vel := _local_velocity()
	vel.y = 0.0
	var speed := vel.length()
	var target := PI
	var rate := 10.0
	match player.state:
		Player.State.AIR:
			rate = 22.0  # spins: the body turns with the view
		Player.State.WALLCLIMB:
			var n := _local(player.wall_normal())
			if n != Vector3.ZERO:
				target = atan2(-n.x, -n.z)
		_:
			if speed > 1.0 and _run_direction() > 0.0:
				target = atan2(vel.x, vel.z)
	if player.state in [Player.State.WALLRUN, Player.State.VAULT, Player.State.MANTLE, Player.State.SLIDE] and speed > 0.5:
		target = atan2(vel.x, vel.z)
	# The body keeps its facing in the world when the view turns, then turns
	# toward where it's going. (Following the view instantly and easing back
	# made it wobble on every mouse movement.) On ramps and loops the frame
	# itself tilts, so it stays relative there.
	var yaw_step := wrapf(player.yaw - _last_yaw, -PI, PI)
	_last_yaw = player.yaw
	if player.state != Player.State.SURFACE:
		_heading = wrapf(_heading - yaw_step, -PI, PI)
	var before := _heading
	_heading = lerp_angle(_heading, target, 1.0 - exp(-rate * delta))
	var turn_rate := wrapf(_heading - before, -PI, PI) / maxf(delta, 0.001)

	# Leaning: into turns when running, with the lean input, and away from
	# the wall on a wallrun (feet on the wall, head out).
	var lean_target := clampf(-turn_rate * speed * 0.035, -0.45, 0.45) * weight("run")
	_turn_lean = lerpf(_turn_lean, lean_target, 1.0 - exp(-8.0 * delta))
	var roll := _turn_lean - deg_to_rad(28.0) * _wall_side * weight("wallrun")
	roll += deg_to_rad(8.0) * player.lean

	# Whole-body rotation: flips and side flips in the air, forward roll,
	# lying down.
	var air := player.air_rotation()
	var pitch := 0.0
	var pivot := Vector3(0, 0.95, 0)
	var offset := Vector3.ZERO
	if player.state == Player.State.AIR:
		pitch = wrapf(-air.y, -PI, PI)
		roll += wrapf(player.air_roll(), -PI, PI)
	elif player.state == Player.State.ROLL:
		pitch = wrapf(TAU * player.roll_progress(), -PI, PI)
		pivot = Vector3(0, 0.5, 0)
	# Runners lean into speed, more while speeding up, upright when braking
	# (applied to the upper body in _add_lean so the feet stay planted).
	_accel = lerpf(_accel, (speed - _prev_speed) / maxf(delta, 0.001), 1.0 - exp(-6.0 * delta))
	_prev_speed = speed
	_drive = (deg_to_rad(10.0) * clampf(speed / 12.0, 0.0, 1.0) + clampf(_accel * 0.01, -0.14, 0.12)) * weight("run")
	_root_pitch = lerp_angle(_root_pitch, pitch, 1.0 - exp(-30.0 * delta))
	_root_roll = lerp_angle(_root_roll, roll, 1.0 - exp(-(30.0 if player.state == Player.State.AIR else 12.0) * delta))
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
	_ground_offset = target if delta <= 0.0 else lerpf(_ground_offset, target, 1.0 - exp(-60.0 * delta))
	local.origin.y += _ground_offset
	model.transform = local
	if player:
		# Interpolated between ticks in slow-mo, so the body doesn't step.
		var vt := player.visual_transform()
		global_transform = Transform3D(vt.basis.orthonormalized() * Basis(Vector3.UP, _heading), vt.origin)


# ---------------------------------------------------------------- helpers

## A world direction in the player's frame (which tilts on ramps and loops).
func _local(v: Vector3) -> Vector3:
	return player.global_basis.orthonormalized().inverse() * v


func _local_velocity() -> Vector3:
	return _local(player.velocity)


## +1 running forward, -1 backing up (the cycle plays in reverse).
func _run_direction() -> float:
	var vel := _local_velocity()
	vel.y = 0.0
	if vel.length() < 0.5:
		return 1.0
	return -1.0 if vel.normalized().z > 0.3 else 1.0


func _on_landed(fall_speed: float) -> void:
	_land_crouch = clampf(fall_speed / 14.0, 0.0, 0.7)


func _on_trick(trick_name: StringName, _info: Dictionary) -> void:
	if String(trick_name).contains("kick"):
		_kick_time = 0.0
