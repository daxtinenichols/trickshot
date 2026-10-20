extends Node3D
## A skinned enemy model (enemies/models/*.glb), posed every frame from the
## enemy's state, like the runner's body: each enemy type returns the pose
## its state calls for (EnemyPoses angles, the runner's convention), and the
## body eases toward it so nothing pops, keeps the lowest foot or knee on the
## ground, and carries the rifle in the right hand.
##
## Looks only: it reads the enemy and never writes to it, so hit zones and
## behaviour stay deterministic. Loaded by path (no class_name): if a model
## can't load, Enemy keeps its placeholder look instead.

const SHADER := preload("res://enemies/enemy_toon.gdshader")

## Bones whose x angle is mirrored so + always means "tip forward".
const HANGING := ["LeftUpperLeg", "LeftLowerLeg", "RightUpperLeg", "RightLowerLeg",
	"LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand"]
## Upper arms are lowered from the model's T-pose into the reference pose.
const ARM_DROP_DEG := 80.0
## Points that can touch the ground, with their distance below the joint (m).
const CONTACTS := {
	"LeftToes": 0.03, "RightToes": 0.03, "LeftFoot": 0.07, "RightFoot": 0.07,
	"LeftLowerLeg": 0.06, "RightLowerLeg": 0.06,
}
const POSE_EASE := 16.0

var model: Node3D
var skeleton: Skeleton3D
var body_material: ShaderMaterial
var glow_material: ShaderMaterial
## Meshes from the model file by name: rigid extras ("Rifle", "Shield"...)
## and separate gear ("Helmet", "Glow").
var parts := {}
## Distance-driven step phase (0..1 per stride), from the enemy's speed.
var phase := 0.0
## How far the model was lowered to keep its lowest contact on the ground.
var ground_offset := 0.0
## Keep feet on the ground (off while leaping or dead).
var grounded := true

var _bones := {}
var _ref_local := {}
var _ref_global := {}
var _hips_rest := Vector3.ZERO
var _shown := {}


## Loads the model file. Returns false (and leaves the body empty) if it
## can't, so the caller can fall back to the placeholder.
## A model the editor hasn't imported yet (freshly copied, before Project >
## Reload Current Project) is read straight from the .glb, like RunnerBody.
func load_model(path: String) -> bool:
	if _imported(path):
		var scene := load(path) as PackedScene
		if scene != null:
			model = scene.instantiate() as Node3D
	if model == null:
		model = _load_gltf_file(path)
	if model == null:
		return false
	# Modeled facing +Z; enemies face -Z.
	model.rotation.y = PI
	add_child(model)
	body_material = ShaderMaterial.new()
	body_material.shader = SHADER
	body_material.set_shader_parameter("rim_strength", 0.45)
	glow_material = ShaderMaterial.new()
	glow_material.shader = SHADER
	glow_material.set_shader_parameter("glow_part", true)
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = glow_material if mi.name.begins_with("Glow") or mi.name == "Lens" else body_material
		parts[String(mi.name)] = mi
	var skels := model.find_children("*", "Skeleton3D", true, false)
	if not skels.is_empty():
		skeleton = skels[0]
		_build_reference()
	return true


## True when the editor has imported the asset (its .import file points at
## an imported copy that exists), so load() won't fail with errors.
static func _imported(path: String) -> bool:
	if path == "" or not ResourceLoader.exists(path):
		return false
	var cfg := ConfigFile.new()
	if cfg.load(path + ".import") != OK:
		return true  # no import file to check against; let load() decide
	var remap := String(cfg.get_value("remap", "path", ""))
	return remap == "" or FileAccess.file_exists(remap)


static func _load_gltf_file(path: String) -> Node3D:
	if path == "" or not FileAccess.file_exists(path):
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		return null
	return doc.generate_scene(state) as Node3D


func has_bones() -> bool:
	return skeleton != null


## Hit flash (0..1) and telegraph glow color, from Enemy each frame.
func set_glow(flash: float, telegraph: Color) -> void:
	var t := Vector3(telegraph.r, telegraph.g, telegraph.b)
	body_material.set_shader_parameter("flash", flash)
	body_material.set_shader_parameter("telegraph", t)
	glow_material.set_shader_parameter("flash", flash)
	glow_material.set_shader_parameter("telegraph", t)


## Multiplies the painted colors (a darker brute, a paler leaper...).
func tint(c: Color) -> void:
	body_material.set_shader_parameter("base_color", c)


## Advances the step phase by distance travelled (feet don't skate).
func step(speed: float, stride: float, delta: float) -> void:
	phase = fposmod(phase + speed * delta / maxf(stride, 0.1), 1.0)


## Eases toward `pose` ({bone: Vector3 degrees}) and applies it.
func show_pose(pose: Dictionary, delta: float, ease := POSE_EASE) -> void:
	if skeleton == null:
		return
	var k := 1.0 - exp(-ease * delta) if delta > 0.0 else 1.0
	for bone: String in _bones:
		var target := to_quat(bone, pose.get(bone, Vector3.ZERO))
		_shown[bone] = target if not _shown.has(bone) else (_shown[bone] as Quaternion).slerp(target, k)
	_apply()
	_ground(delta)


## Jumps straight to a pose (no easing). For tools and tests.
func snap_pose(pose: Dictionary) -> void:
	_shown.clear()
	show_pose(pose, 0.0)


func to_quat(bone: String, e: Vector3) -> Quaternion:
	var x := -e.x if bone in HANGING else e.x
	return Basis.from_euler(Vector3(deg_to_rad(x), deg_to_rad(e.y), deg_to_rad(e.z)), EULER_ORDER_YXZ).get_rotation_quaternion()


## A bone's world position (after the last applied pose).
func bone_position(bone: String) -> Vector3:
	if skeleton == null or not _bones.has(bone):
		return global_position
	return skeleton.global_transform * skeleton.get_bone_global_pose(_bones[bone]).origin


func bone_transform(bone: String) -> Transform3D:
	return skeleton.global_transform * skeleton.get_bone_global_pose(_bones[bone])


## Places a rigid part ("Rifle", "Shield") at `xf`, in this node's space
## (the enemy's own: forward -Z). Parts are modeled facing +Z.
func hold(part_name: String, xf: Transform3D) -> void:
	var part: Node3D = parts.get(part_name)
	if part == null:
		return
	if part.get_parent() != self:
		part.get_parent().remove_child(part)
		add_child(part)
	part.transform = xf * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)


func show_part(part_name: String, on: bool) -> void:
	var part: Node3D = parts.get(part_name)
	if part:
		part.visible = on


## Two-bone IK: bends the arm on `side` ("Left"/"Right") so the hand reaches
## `target` (this node's space), elbow toward `pole`. Call after show_pose.
func reach(side: String, target: Vector3, pole: Vector3, weight := 1.0) -> void:
	if skeleton == null or weight <= 0.0:
		return
	var iu: int = _bones[side + "UpperArm"]
	var il: int = _bones[side + "LowerArm"]
	var ih: int = _bones[side + "Hand"]
	var to_skel := (model.transform * skeleton.transform).affine_inverse()
	var t := to_skel * target
	var pole_s := (to_skel.basis * pole).normalized()
	var s := skeleton.get_bone_global_pose(iu).origin
	var e := skeleton.get_bone_global_pose(il).origin
	var w := skeleton.get_bone_global_pose(ih).origin
	var l1 := s.distance_to(e)
	var l2 := e.distance_to(w)
	var to_t := t - s
	var d := clampf(to_t.length(), 0.02, (l1 + l2) * 0.999)
	var dir := to_t.normalized()
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var n := (pole_s - dir * pole_s.dot(dir))
	n = n.normalized() if n.length_squared() > 1e-6 else dir.cross(Vector3.UP).normalized()
	var elbow := s + dir * l1 * cos_a + n * l1 * sqrt(1.0 - cos_a * cos_a)
	var hand := s + dir * d
	elbow = e.lerp(elbow, weight)
	hand = w.lerp(hand, weight)
	_aim_bone(iu, e - s, elbow - s)
	var e2 := skeleton.get_bone_global_pose(il).origin
	var w2 := skeleton.get_bone_global_pose(ih).origin
	_aim_bone(il, w2 - e2, hand - e2)


## Turns bone i so its current direction `from` points along `to` (both in
## skeleton space), keeping its parent where it is.
func _aim_bone(i: int, from: Vector3, to: Vector3) -> void:
	if from.length_squared() < 1e-8 or to.length_squared() < 1e-8:
		return
	var turn := Quaternion(from.normalized(), to.normalized())
	var g := skeleton.get_bone_global_pose(i).basis.get_rotation_quaternion()
	var parent := skeleton.get_bone_parent(i)
	var pg := skeleton.get_bone_global_pose(parent).basis.get_rotation_quaternion() if parent >= 0 else Quaternion.IDENTITY
	skeleton.set_bone_pose_rotation(i, pg.inverse() * (turn * g))


# ---------------------------------------------------------------- internals

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
		var bname := skeleton.get_bone_name(i)
		if bname.ends_with("UpperArm"):
			var side := 1.0 if bname.begins_with("Left") else -1.0
			var drop := Quaternion(Vector3.BACK, deg_to_rad(-ARM_DROP_DEG) * side)
			var g: Quaternion = rest_global[i]
			local = local * (g.inverse() * drop * g)
		_ref_local[i] = local
		var parent_ref: Quaternion = _ref_global[parent] if parent >= 0 else Quaternion.IDENTITY
		_ref_global[i] = parent_ref * local


func _ordered_bones() -> Array[int]:
	var order: Array[int] = []
	var stack: Array = Array(skeleton.get_parentless_bones())
	while not stack.is_empty():
		var i: int = stack.pop_back()
		order.append(i)
		stack.append_array(skeleton.get_bone_children(i))
	return order


func _apply() -> void:
	for bone: String in _bones:
		var i: int = _bones[bone]
		var q: Quaternion = _shown.get(bone, Quaternion.IDENTITY)
		var g: Quaternion = _ref_global[i]
		skeleton.set_bone_pose_rotation(i, _ref_local[i] * (g.inverse() * q * g))
	skeleton.set_bone_pose_position(_bones["Hips"], _hips_rest)


## Lowers (or raises) the model so its lowest contact point rests on the
## floor: crouches and kneels get the right height without leg IK.
func _ground(delta: float) -> void:
	if not grounded:
		ground_offset = lerpf(ground_offset, 0.0, 1.0 - exp(-8.0 * delta)) if delta > 0.0 else 0.0
		model.position.y = ground_offset
		return
	var lowest := INF
	var to_model := model.transform
	for bone: String in CONTACTS:
		if not _bones.has(bone):
			continue
		var p := to_model * (skeleton.transform * skeleton.get_bone_global_pose(_bones[bone]).origin)
		lowest = minf(lowest, p.y - float(CONTACTS[bone]) - model.position.y)
	if lowest == INF:
		return
	var want := -lowest
	ground_offset = want if delta <= 0.0 else lerpf(ground_offset, want, 1.0 - exp(-30.0 * delta))
	model.position.y = ground_offset
