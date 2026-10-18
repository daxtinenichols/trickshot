extends RefCounted
## Hit zones shaped like the body: a head, chest, hips, upper and lower arms
## and legs, sized from the enemy's model (see PROFILES), so a shot that
## clips the model hits and one past its shoulder or between its legs
## misses.
##
## They follow the pose the game state calls for, posed in the physics tick
## from state only: crouching (duck), the hunch, running (a step cycle
## advanced by distance), where the hands hold the gun (aim direction),
## flinches and kick knockdowns. The drawn model eases between poses and the
## zones don't, so the two can be a few centimeters apart mid-move, but
## everything stays deterministic: the same inputs give the same hits.
##
## Head is the "head" zone; everything else is "body". Loaded by path
## (no class_name).

## Proportions in meters, standing, measured from the models' skeletons.
## Origin at the feet, facing -Z.
##   hip_y/hip_w     hip joints' height and half spacing
##   thigh/shin      leg segment lengths (knee, then ankle)
##   neck_y          base of the neck (top of the chest)
##   head_y/head_r   head center above the neck base, and its radius
##   head_z          how far the head sits forward of the neck
##   shoulder_w/_y   shoulder joints: half spacing, height below neck_y
##   upper_arm/fore  arm segment lengths
##   chest           chest box width and depth
##   pelvis          hip box width, depth, height
##   limb_r          [arm, thigh, shin] capsule radii
##   hand            where a free hand hangs from its shoulder (x outward)
##   lean            the torso's forward tilt standing (radians)
##   crouch          how far the hips sit below hip_y standing (bent knees)
const HUMAN := {
	"hip_y": 0.94, "hip_w": 0.1, "thigh": 0.43, "shin": 0.42,
	"neck_y": 1.47, "head_y": 0.16, "head_r": 0.14, "head_z": -0.02,
	"shoulder_w": 0.19, "shoulder_y": 0.03, "upper_arm": 0.27, "fore": 0.27,
	"chest": Vector2(0.38, 0.24), "pelvis": Vector3(0.34, 0.22, 0.22),
	"limb_r": [0.06, 0.085, 0.065], "lean": 0.03, "crouch": 0.0,
	"hand": Vector3(0.04, -0.5, -0.06),
}
## Hunters and Juno: lighter build, knees always a little bent.
const RUNNER := {
	"hip_y": 0.94, "hip_w": 0.1, "thigh": 0.43, "shin": 0.42,
	"neck_y": 1.47, "head_y": 0.15, "head_r": 0.13, "head_z": -0.03,
	"shoulder_w": 0.18, "shoulder_y": 0.03, "upper_arm": 0.27, "fore": 0.27,
	"chest": Vector2(0.34, 0.22), "pelvis": Vector3(0.31, 0.2, 0.2),
	"limb_r": [0.055, 0.08, 0.06], "lean": 0.12, "crouch": 0.1,
	"hand": Vector3(0.04, -0.48, -0.08),
}
## Bruisers and heavies: bulked out by gear.
const BULKY := {
	"hip_y": 0.94, "hip_w": 0.11, "thigh": 0.43, "shin": 0.42,
	"neck_y": 1.47, "head_y": 0.16, "head_r": 0.15, "head_z": -0.02,
	"shoulder_w": 0.22, "shoulder_y": 0.03, "upper_arm": 0.27, "fore": 0.27,
	"chest": Vector2(0.48, 0.32), "pelvis": Vector3(0.4, 0.26, 0.22),
	"limb_r": [0.075, 0.1, 0.08], "lean": 0.03, "crouch": 0.0,
	"hand": Vector3(0.06, -0.5, -0.06),
}
## Hollows: hunched, long arms hanging forward (scaled by size_scale).
const MUTANT := {
	"hip_y": 0.78, "hip_w": 0.13, "thigh": 0.36, "shin": 0.36,
	"neck_y": 1.3, "head_y": 0.12, "head_r": 0.16, "head_z": -0.1,
	"shoulder_w": 0.25, "shoulder_y": 0.0, "upper_arm": 0.36, "fore": 0.34,
	"chest": Vector2(0.56, 0.4), "pelvis": Vector3(0.42, 0.3, 0.24),
	"limb_r": [0.08, 0.1, 0.085], "lean": 0.42, "crouch": 0.04,
	"hand": Vector3(0.28, -0.5, -0.34),
}

const LIMBS := ["LeftUpperArm", "LeftLowerArm", "RightUpperArm", "RightLowerArm",
	"LeftUpperLeg", "LeftLowerLeg", "RightUpperLeg", "RightLowerLeg"]

var enemy: Node
var p: Dictionary
var k := 1.0
## Name -> EnemyHitbox.
var parts := {}
## Step cycle (0..1 per stride), advanced in the physics tick.
var phase := 0.0
## Where the head zone is (enemy-local), after the last update.
var head_local := Vector3.ZERO


## Makes the zones. `enemy._hitbox(zone, shape, pos)` builds each one.
func build(e: Node, profile: Dictionary, scale := 1.0) -> void:
	enemy = e
	p = profile
	k = scale
	parts["Head"] = e._hitbox(&"head", e.sphere_shape(p.head_r * k), Vector3.ZERO)
	var c: Vector2 = p.chest
	var pel: Vector3 = p.pelvis
	parts["Chest"] = e._hitbox(&"body", e.box_shape(Vector3(c.x, 1.0, c.y) * k), Vector3.ZERO)
	parts["Hips"] = e._hitbox(&"body", e.box_shape(pel * k), Vector3.ZERO)
	var r: Array = p.limb_r
	for limb: String in LIMBS:
		var cap := CapsuleShape3D.new()
		cap.radius = (r[0] if limb.contains("Arm") else r[1] if limb.contains("Upper") else r[2]) * k
		cap.height = 1.0
		parts[limb] = e._hitbox(&"body", cap, Vector3.ZERO)
	update({})


## Poses the zones. pose keys (all optional):
##   crouch  extra hip drop (m, unscaled)
##   lean    extra forward tilt of the torso (radians)
##   speed   horizontal speed (m/s) and `stride` (m): the legs step
##   run     0..1 how much the legs swing
##   delta   tick length, for the step cycle
##   hands   [left, right] enemy-local points the hands reach for
##   head_pitch  extra nod of the head (radians, + down)
func update(pose: Dictionary) -> void:
	var stride: float = pose.get("stride", 1.5) * k
	phase = fposmod(phase + float(pose.get("speed", 0.0)) * float(pose.get("delta", 0.0)) / maxf(stride, 0.1), 1.0)
	var run: float = clampf(pose.get("run", 0.0), 0.0, 1.0)
	var drop: float = (p.crouch + float(pose.get("crouch", 0.0))) * k
	var lean: float = p.lean + float(pose.get("lean", 0.0))
	var hip_y: float = p.hip_y * k - drop
	# Legs: hip joints, knees bent to reach the ground from the dropped hips,
	# swung by the step cycle.
	for side: float in [-1.0, 1.0]:
		var name := "Left" if side < 0.0 else "Right"
		var hip := Vector3(side * p.hip_w * k, hip_y, 0.0)
		var swing := sin((phase + (0.5 if side > 0.0 else 0.0)) * TAU) * 0.55 * run
		var knee_pt := _knee(hip, swing, run)
		var ankle := Vector3(hip.x, 0.1 * k, knee_pt.z + (hip.z - knee_pt.z) * 0.3 - swing * 0.15 * k)
		ankle = knee_pt + (ankle - knee_pt).normalized() * p.shin * k
		_segment(name + "UpperLeg", hip, knee_pt)
		_segment(name + "LowerLeg", knee_pt, ankle)
	# Torso: tilts forward about the hips.
	var tilt := Basis(Vector3.RIGHT, -lean)
	var pel: Vector3 = p.pelvis
	var pelvis_c := Vector3(0, hip_y + pel.y * k * 0.25, 0)
	_place("Hips", Transform3D(tilt, pelvis_c))
	var spine: float = (p.neck_y - p.hip_y) * k
	var chest_bottom := Vector3(0, hip_y + pel.y * k * 0.5, 0)
	var neck := Vector3(0, hip_y, 0) + tilt * Vector3(0, spine, 0)
	var chest_len := (neck - chest_bottom).length()
	_place("Chest", Transform3D(tilt * Basis.from_scale(Vector3(1, chest_len, 1)), (chest_bottom + neck) * 0.5))
	# Head on the neck, nodding with the lean.
	var nod := Basis(Vector3.RIGHT, -(lean * 0.4 + float(pose.get("head_pitch", 0.0))))
	head_local = neck + tilt * Vector3(0, 0, p.head_z * k) + nod * Vector3(0, p.head_y * k, 0)
	_place("Head", Transform3D(Basis.IDENTITY, head_local))
	# Arms: shoulders below the neck, hands where the state holds them.
	var hands: Array = pose.get("hands", [])
	for side: float in [-1.0, 1.0]:
		var name := "Left" if side < 0.0 else "Right"
		var shoulder := neck + tilt * Vector3(side * p.shoulder_w * k, -p.shoulder_y * k, 0)
		var hand: Vector3
		if hands.size() == 2:
			hand = hands[0 if side < 0.0 else 1]
		else:
			# Hanging (the profile's rest), swinging against the legs.
			var swing := -sin((phase + (0.5 if side > 0.0 else 0.0)) * TAU) * 0.5 * run
			var rest: Vector3 = p.hand
			hand = shoulder + Basis(Vector3.RIGHT, swing) * Vector3(side * rest.x, rest.y, rest.z) * k
		var elbow := _elbow(shoulder, hand, side)
		_segment(name + "UpperArm", shoulder, elbow)
		_segment(name + "LowerArm", elbow, hand)


## The knee for a hip at height hip.y: the leg folds to reach the ground,
## the thigh swung forward by `swing` (radians).
func _knee(hip: Vector3, swing: float, run: float) -> Vector3:
	var thigh: float = p.thigh * k
	var shin: float = p.shin * k
	var reach := clampf(hip.y - 0.1 * k, 0.2 * k, (thigh + shin) * 0.999)
	# Knee bend from the two-bone triangle (knees point forward, -Z).
	var cos_a := clampf((thigh * thigh + reach * reach - shin * shin) / (2.0 * thigh * reach), -1.0, 1.0)
	var bend := acos(cos_a) + run * 0.15
	var a := bend + swing
	return hip + Vector3(0, -cos(a) * thigh, -sin(a) * thigh)


## Elbow out and down, bent so both arm segments keep their length.
func _elbow(shoulder: Vector3, hand: Vector3, side: float) -> Vector3:
	var l1: float = p.upper_arm * k
	var l2: float = p.fore * k
	var to := hand - shoulder
	var d := clampf(to.length(), 0.02, (l1 + l2) * 0.999)
	var dir := to.normalized() if to.length_squared() > 1e-8 else Vector3.DOWN
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var pole := Vector3(side, -1.0, 0.25).normalized()
	var n := pole - dir * pole.dot(dir)
	n = n.normalized() if n.length_squared() > 1e-6 else Vector3(side, 0, 0)
	return shoulder + dir * l1 * cos_a + n * l1 * sqrt(1.0 - cos_a * cos_a)


## A capsule (height 1, along Y) stretched from a to b.
func _segment(part: String, a: Vector3, b: Vector3) -> void:
	var hb: Node3D = parts[part]
	var cap: CapsuleShape3D = (hb.get_child(0) as CollisionShape3D).shape
	var len := maxf(a.distance_to(b), 0.01)
	cap.height = maxf(len + cap.radius * 2.0, cap.radius * 2.0 + 0.001)
	var y := (b - a) / len
	var x := y.cross(Vector3.FORWARD)
	if x.length_squared() < 1e-6:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	hb.transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)


func _place(part: String, xf: Transform3D) -> void:
	var hb: Node3D = parts[part]
	if part == "Chest":
		# The chest box is 1 m tall: scale it on the shape, not the body
		# (physics bodies must not be scaled).
		var box: BoxShape3D = (hb.get_child(0) as CollisionShape3D).shape
		var c: Vector2 = p.chest
		box.size = Vector3(c.x * k, xf.basis.get_scale().y, c.y * k)
		xf.basis = xf.basis.orthonormalized()
	hb.transform = xf
