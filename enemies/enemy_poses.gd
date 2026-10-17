extends RefCounted
## Key poses and cycles for the enemy models, in the runner's convention
## (see art/characters/runner/runner_poses.gd): degrees per bone,
##   x  flex: + tips the bone forward (thigh up, arm forward, spine leans
##      forward). Knees bend with -x, elbows with +x.
##   y  twist: + turns toward the character's left.
##   z  sideways: + moves a left limb's tip outward; on the right side the
##      sign flips (- is outward). Spine/neck/head: + leans right.
## Bones left out stay at the reference pose (standing, arms at the sides).
## Loaded by path (no class_name).

const SIDES := {
	"LeftShoulder": "RightShoulder", "LeftUpperArm": "RightUpperArm",
	"LeftLowerArm": "RightLowerArm", "LeftHand": "RightHand",
	"LeftUpperLeg": "RightUpperLeg", "LeftLowerLeg": "RightLowerLeg",
	"LeftFoot": "RightFoot", "LeftToes": "RightToes",
}


static func mirror(pose: Dictionary) -> Dictionary:
	var out := pose.duplicate()
	for k: String in pose:
		if SIDES.has(k) and not pose.has(SIDES[k]):
			var v: Vector3 = pose[k]
			out[SIDES[k]] = Vector3(v.x, -v.y, -v.z)
	return out


## a + b * w, bone by bone (missing bones count as zero).
static func blend(a: Dictionary, b: Dictionary, w: float) -> Dictionary:
	if w <= 0.0:
		return a
	var out := a.duplicate()
	for k: String in b:
		out[k] = (a.get(k, Vector3.ZERO) as Vector3).lerp(b[k], w)
	for k: String in a:
		if not b.has(k):
			out[k] = (a[k] as Vector3).lerp(Vector3.ZERO, w)
	return out


## Adds b on top of a (for layering aim pitch, flinches...).
static func add(a: Dictionary, b: Dictionary, w := 1.0) -> Dictionary:
	var out := a.duplicate()
	for k: String in b:
		out[k] = (a.get(k, Vector3.ZERO) as Vector3) + (b[k] as Vector3) * w
	return out


## Overwrites a's legs (or any bones) with b's, blended by w.
static func take(a: Dictionary, b: Dictionary, bones: Array, w := 1.0) -> Dictionary:
	var out := a.duplicate()
	for k: String in bones:
		out[k] = (a.get(k, Vector3.ZERO) as Vector3).lerp(b.get(k, Vector3.ZERO), w)
	return out


## Lower body from `lower`, arms from `upper`; spine, neck and head bend
## by both.
static func layer(lower: Dictionary, upper: Dictionary) -> Dictionary:
	var out := lower.duplicate()
	for k: String in upper:
		out[k] = upper[k] if k in ARMS else (lower.get(k, Vector3.ZERO) as Vector3) + (upper[k] as Vector3)
	return out


const LEGS := ["LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot", "Hips"]
const ARMS := ["LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand"]


# ---------------------------------------------------------------- humans with rifles

static func stand() -> Dictionary:
	return mirror({
		"Spine": Vector3(2, 0, 0),
		"LeftUpperArm": Vector3(4, 0, 8),
		"LeftLowerArm": Vector3(12, 0, 0),
		"LeftUpperLeg": Vector3(0, 0, 4),
		"LeftLowerLeg": Vector3(-4, 0, 0),
		"LeftFoot": Vector3(4, 0, 0),
	})


## Walk/run legs at phase 0..1; amount 0 = in place .. 1 = full run.
static func legs(phase: float, amount: float) -> Dictionary:
	var a := TAU * phase
	var s := clampf(amount, 0.0, 1.2)
	var pose := {
		"Hips": Vector3(4 * s, 8 * s * sin(a), 0),
		"Spine": Vector3(4 + 6 * s, -5 * s * sin(a), 0),
	}
	for side: String in ["Left", "Right"]:
		var p := a if side == "Left" else a + PI
		var swing := sin(p)
		var recover := maxf(0.0, -cos(p - 0.6))
		var z := 3.0 if side == "Left" else -3.0
		pose[side + "UpperLeg"] = Vector3((10 + 36 * s) * swing + 8 * s, 0, z)
		pose[side + "LowerLeg"] = Vector3(-(8 + 14 * s) - (30 + 60 * s) * recover, 0, 0)
		pose[side + "Foot"] = Vector3(-8 * swing * s + 14 * recover * s, 0, 0)
	return pose


## Rifle up at the shoulder, both hands on it. `pitch` (degrees, + = up)
## bends the upper body toward the target.
static func aim(pitch := 0.0) -> Dictionary:
	var p := clampf(pitch, -60.0, 60.0)
	return {
		"Spine": Vector3(4 - p * 0.35, -10, 0),
		"Chest": Vector3(-p * 0.35, -8, 0),
		"Neck": Vector3(p * 0.15, 10, 0),
		"Head": Vector3(p * 0.15 + 4, 8, 2),
		"RightUpperArm": Vector3(62, 0, -26),
		"RightLowerArm": Vector3(96, 0, 0),
		"RightHand": Vector3(-6, 0, 0),
		"LeftUpperArm": Vector3(64, 0, -26),
		"LeftLowerArm": Vector3(44, 0, 0),
		"LeftHand": Vector3(-10, 0, 0),
	}


## Rifle held across the body, muzzle down: walking, holding, reloading.
static func low_ready() -> Dictionary:
	return {
		"Spine": Vector3(4, -6, 0),
		"Chest": Vector3(0, -4, 0),
		"Head": Vector3(0, 8, 0),
		"RightUpperArm": Vector3(18, 0, -14),
		"RightLowerArm": Vector3(70, 0, 0),
		"RightHand": Vector3(-4, 0, 0),
		"LeftUpperArm": Vector3(36, 0, -20),
		"LeftLowerArm": Vector3(74, 0, 0),
		"LeftHand": Vector3(-8, 0, 0),
	}


## Rifle up to swap the magazine: chin down, left hand at the magazine.
static func reloading(t: float) -> Dictionary:
	var jiggle := sin(t * TAU * 3.0) * 8.0
	var pose := low_ready()
	pose["Head"] = Vector3(18, 4, 0)
	pose["RightUpperArm"] = Vector3(30, 0, -10)
	pose["RightLowerArm"] = Vector3(96, 0, 0)
	pose["LeftUpperArm"] = Vector3(30 + jiggle * 0.5, 0, -14)
	pose["LeftLowerArm"] = Vector3(100 + jiggle, 0, 0)
	return pose


## Down on one knee behind cover, head low.
static func kneel() -> Dictionary:
	return {
		"Hips": Vector3(16, 0, 0),
		"Spine": Vector3(16, 0, 0),
		"Chest": Vector3(10, 0, 0),
		"Neck": Vector3(-8, 0, 0),
		"Head": Vector3(-12, 0, 0),
		# Left foot planted ahead, right knee on the ground.
		"LeftUpperLeg": Vector3(80, 0, 6),
		"LeftLowerLeg": Vector3(-96, 0, 0),
		"LeftFoot": Vector3(-6, 0, 0),
		"RightUpperLeg": Vector3(-6, 0, -4),
		"RightLowerLeg": Vector3(-100, 0, 0),
		"RightFoot": Vector3(40, 0, 0),
	}


## Mid-hop over an obstacle: knees up.
static func hop() -> Dictionary:
	return {
		"Hips": Vector3(6, 0, 0),
		"Spine": Vector3(10, 0, 0),
		"LeftUpperLeg": Vector3(80, 0, 6),
		"LeftLowerLeg": Vector3(-100, 0, 0),
		"RightUpperLeg": Vector3(30, 0, -6),
		"RightLowerLeg": Vector3(-70, 0, 0),
	}


## Rocked back by a headshot or a kick.
static func flinch() -> Dictionary:
	return {
		"Spine": Vector3(-14, 6, 0),
		"Chest": Vector3(-10, 4, 0),
		"Neck": Vector3(-16, 0, 0),
		"Head": Vector3(-18, -10, 6),
		"LeftUpperArm": Vector3(30, 0, 30),
		"LeftLowerArm": Vector3(40, 0, 0),
	}


## Limp: what a body does as it goes down.
static func dead() -> Dictionary:
	return mirror({
		"Spine": Vector3(-6, 0, 0),
		"Head": Vector3(-20, 12, 0),
		"LeftUpperArm": Vector3(20, 0, 50),
		"LeftLowerArm": Vector3(20, 0, 0),
		"LeftUpperLeg": Vector3(20, 0, 6),
		"LeftLowerLeg": Vector3(-30, 0, 0),
	})


## Shield up in the left hand, carbine in the right poking past its edge.
static func shield_guard(pitch := 0.0) -> Dictionary:
	var pose := aim(pitch)
	pose["LeftUpperArm"] = Vector3(46, 0, 10)
	pose["LeftLowerArm"] = Vector3(76, 0, 0)
	pose["LeftHand"] = Vector3(0, 0, 0)
	pose["Spine"] = Vector3(10, 0, 0)
	return pose


# ---------------------------------------------------------------- rifles
# Rifles are placed from the state (not hung on a hand), and the hands
# reach for them with IK, so the gun points exactly where the enemy aims.
# Points are in the rifle's frame: grip at the origin, barrel toward -Z.

## Where the rifle sits: `chest` is the UpperChest joint (body space),
## `aim` the aim direction (body space, unit). Weights 0..1.
static func rifle_xf(chest: Vector3, aim: Vector3, aim_w: float, reload_w: float, step := 0.0) -> Transform3D:
	var bob := Vector3(0, 0.015 * sin(step * TAU * 2.0), 0)
	var low := Transform3D(_facing(Vector3(-0.45, -0.55, -0.7)), chest + Vector3(0.14, -0.36, -0.2) + bob)
	var up := Transform3D(_facing(aim), chest + Vector3(0.13, 0.02, -0.16) + aim * 0.06)
	var rl := Transform3D(_facing(Vector3(-0.3, 0.1, -1.0)), chest + Vector3(0.1, -0.2, -0.3))
	var xf := low.interpolate_with(up, smoothstep(0.0, 1.0, aim_w))
	return xf.interpolate_with(rl, smoothstep(0.0, 1.0, reload_w))


static func _facing(dir: Vector3) -> Basis:
	var d := dir.normalized()
	var up := Vector3.UP if absf(d.y) < 0.98 else Vector3.BACK
	return Basis.looking_at(d, up)


## The elbows stay down and out.
const RIGHT_POLE := Vector3(1.0, -1.0, 0.3)
const LEFT_POLE := Vector3(-1.0, -1.2, 0.2)


# ---------------------------------------------------------------- mutant

static func hunch() -> Dictionary:
	return mirror({
		"Hips": Vector3(6, 0, 0),
		"Neck": Vector3(-20, 0, 0),
		"Head": Vector3(-10, 0, 0),
		"LeftUpperArm": Vector3(24, 0, 14),
		"LeftLowerArm": Vector3(30, 0, 0),
		"LeftHand": Vector3(10, 0, 0),
		"LeftUpperLeg": Vector3(26, 0, 10),
		"LeftLowerLeg": Vector3(-40, 0, 0),
		"LeftFoot": Vector3(14, 0, 0),
	})


## Loping run: big arm swings, low and forward.
static func lope(phase: float, amount: float) -> Dictionary:
	var a := TAU * phase
	var s := clampf(amount, 0.0, 1.2)
	var pose := legs(phase, amount * 1.1)
	pose = add(pose, hunch())
	pose["Spine"] = Vector3(10 * s, -8 * s * sin(a), 0)
	pose["Chest"] = Vector3(6 * s, -8 * s * sin(a), 0)
	for side: String in ["Left", "Right"]:
		var p := a + PI if side == "Left" else a
		var z := 16.0 if side == "Left" else -16.0
		pose[side + "UpperArm"] = Vector3(30 + 50 * s * sin(p), 0, z)
		pose[side + "LowerArm"] = Vector3(30 + 30 * s, 0, 0)
	return pose


## Coiled to leap (w 0..1 as the windup builds).
static func coil(w: float) -> Dictionary:
	return add(hunch(), mirror({
		"Hips": Vector3(16, 0, 0),
		"Spine": Vector3(10, 0, 0),
		"Neck": Vector3(-14, 0, 0),
		"LeftUpperArm": Vector3(-40, 0, 20),
		"LeftLowerArm": Vector3(30, 0, 0),
		"LeftUpperLeg": Vector3(50, 0, 6),
		"LeftLowerLeg": Vector3(-70, 0, 0),
		"LeftFoot": Vector3(-10, 0, 0),
	}), w)


## In the air: claws out ahead, legs trailing.
static func pounce() -> Dictionary:
	return mirror({
		"Hips": Vector3(-10, 0, 0),
		"Spine": Vector3(-4, 0, 0),
		"Neck": Vector3(-20, 0, 0),
		"LeftUpperArm": Vector3(130, 0, 30),
		"LeftLowerArm": Vector3(14, 0, 0),
		"LeftHand": Vector3(-30, 0, 0),
		"LeftUpperLeg": Vector3(-10, 0, 8),
		"LeftLowerLeg": Vector3(-70, 0, 0),
	})


## Winded after landing: hands on the ground, heaving.
static func winded(breath: float) -> Dictionary:
	return add(hunch(), mirror({
		"Hips": Vector3(20, 0, 0),
		"Spine": Vector3(16 + 4 * breath, 0, 0),
		"Chest": Vector3(8, 0, 0),
		"Neck": Vector3(-6, 0, 0),
		"LeftUpperArm": Vector3(40, 0, 6),
		"LeftLowerArm": Vector3(10, 0, 0),
		"LeftUpperLeg": Vector3(54, 0, 12),
		"LeftLowerLeg": Vector3(-80, 0, 0),
	}))


## Right claw drawn back (w 0..1), then raked across (w < 0).
static func swipe(w: float) -> Dictionary:
	var pose := hunch()
	if w >= 0.0:
		pose["Spine"] = Vector3(4, -26 * w, 0)
		pose["RightUpperArm"] = Vector3(lerpf(24, 120, w), 0, lerpf(-14, -50, w))
		pose["RightLowerArm"] = Vector3(lerpf(30, 70, w), 0, 0)
	else:
		var t := -w
		pose["Spine"] = Vector3(14, 30 * t, 0)
		pose["RightUpperArm"] = Vector3(lerpf(120, 70, t), 0, lerpf(-50, 30, t))
		pose["RightLowerArm"] = Vector3(20, 0, 0)
	return pose
