class_name RunnerPoses
extends RefCounted
## Key poses and movement cycles for the runner, as joint angles in degrees.
## RunnerBody blends these by the player's state, so every move flows into
## the next without hand-made transition clips.
##
## A pose is {bone_name: Vector3(x, y, z)}. Bones left out stay at the
## reference pose (standing, arms hanging at the sides). Angles are about the
## character's own axes, so they read the same on every bone:
##   x  flex: + tips the bone forward (thigh up, arm forward, spine leans
##      forward). Knees bend with -x, elbows with +x, feet: + = toes down.
##   y  twist: + turns toward the character's left.
##   z  sideways: + moves the bone's tip outward (away from the body) on
##      the left side; for spine/neck/head + leans to the character's right.
## Write poses for the Left side; mirror() makes the right side match.
## Hips rotation turns the whole body, legs included: leaning the hips back
## also swings both legs forward, so leg angles are relative to the hips.

const LEFT_TO_RIGHT := {
	"LeftShoulder": "RightShoulder", "LeftUpperArm": "RightUpperArm",
	"LeftLowerArm": "RightLowerArm", "LeftHand": "RightHand",
	"LeftUpperLeg": "RightUpperLeg", "LeftLowerLeg": "RightLowerLeg",
	"LeftFoot": "RightFoot", "LeftToes": "RightToes",
}


## Mirrors one bone's angles to the other side of the body.
static func mirror_angles(v: Vector3) -> Vector3:
	return Vector3(v.x, -v.y, -v.z)


## Makes a symmetric pose: every Left entry is copied to the Right side.
static func mirror(pose: Dictionary) -> Dictionary:
	var out := pose.duplicate()
	for k: String in pose:
		if LEFT_TO_RIGHT.has(k) and not pose.has(LEFT_TO_RIGHT[k]):
			out[LEFT_TO_RIGHT[k]] = mirror_angles(pose[k])
	return out


## Swaps sides: what the left limbs do, the right limbs now do.
static func flip_sides(pose: Dictionary) -> Dictionary:
	var out := {}
	for k: String in pose:
		var v: Vector3 = pose[k]
		var other := k
		for l: String in LEFT_TO_RIGHT:
			if k == l:
				other = LEFT_TO_RIGHT[l]
			elif k == LEFT_TO_RIGHT[l]:
				other = l
		if k in ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head"]:
			out[k] = mirror_angles(v)
		else:
			out[other] = mirror_angles(v)
	return out


# ---------------------------------------------------------------- key poses

static func idle() -> Dictionary:
	return mirror({
		"Spine": Vector3(2, 0, 0),
		"Head": Vector3(-2, 0, 0),
		"LeftUpperArm": Vector3(4, 0, 6),
		"LeftLowerArm": Vector3(14, 0, 0),
		"LeftUpperLeg": Vector3(2, 0, 3),
		"LeftLowerLeg": Vector3(-4, 0, 0),
	})


static func crouch() -> Dictionary:
	return mirror({
		"Hips": Vector3(18, 0, 0),
		"Spine": Vector3(14, 0, 0),
		"Chest": Vector3(8, 0, 0),
		"Neck": Vector3(-14, 0, 0),
		"Head": Vector3(-14, 0, 0),
		"LeftUpperArm": Vector3(30, 0, 12),
		"LeftLowerArm": Vector3(70, 0, 0),
		"LeftUpperLeg": Vector3(78, 0, 10),
		"LeftLowerLeg": Vector3(-118, 0, 0),
		"LeftFoot": Vector3(-24, 0, 0),
	})


## Feet-first slide: lead leg out straight, back leg folded under, leaning
## back on one hand.
static func slide() -> Dictionary:
	# Hips tips the whole body back, which also swings both legs forward by
	# the same angle; the spine brings the chest partly upright again.
	return {
		"Hips": Vector3(-50, 10, 0),
		"Spine": Vector3(8, -4, 0),
		"Chest": Vector3(6, -6, 0),
		"Neck": Vector3(14, 0, 0),
		"Head": Vector3(14, 0, 0),
		"LeftUpperLeg": Vector3(22, 0, 4),
		"LeftLowerLeg": Vector3(-4, 0, 0),
		"LeftFoot": Vector3(16, 0, 0),
		"RightUpperLeg": Vector3(14, 0, -14),
		"RightLowerLeg": Vector3(-150, 0, 0),
		"RightFoot": Vector3(24, 0, 0),
		"LeftUpperArm": Vector3(70, 0, 30),
		"LeftLowerArm": Vector3(30, 0, 0),
		"RightUpperArm": Vector3(-30, 0, -26),
		"RightLowerArm": Vector3(10, 0, 0),
		"RightHand": Vector3(-60, 0, 0),
	}


static func jump_rise() -> Dictionary:
	return {
		"Spine": Vector3(4, 0, 0),
		"Chest": Vector3(-6, 0, 0),
		"LeftUpperLeg": Vector3(74, 0, 4),
		"LeftLowerLeg": Vector3(-92, 0, 0),
		"LeftFoot": Vector3(24, 0, 0),
		"RightUpperLeg": Vector3(-8, 0, -4),
		"RightLowerLeg": Vector3(-46, 0, 0),
		"RightFoot": Vector3(36, 0, 0),
		"LeftUpperArm": Vector3(-30, 0, 18),
		"LeftLowerArm": Vector3(40, 0, 0),
		"RightUpperArm": Vector3(70, 0, -16),
		"RightLowerArm": Vector3(50, 0, 0),
	}


static func fall() -> Dictionary:
	return {
		"Spine": Vector3(-2, 0, 0),
		"Chest": Vector3(-4, 0, 0),
		"Head": Vector3(10, 0, 0),
		"LeftUpperLeg": Vector3(38, 0, 8),
		"LeftLowerLeg": Vector3(-58, 0, 0),
		"RightUpperLeg": Vector3(8, 0, -6),
		"RightLowerLeg": Vector3(-34, 0, 0),
		"LeftUpperArm": Vector3(20, 0, 42),
		"LeftLowerArm": Vector3(36, 0, 0),
		"RightUpperArm": Vector3(28, 0, -38),
		"RightLowerArm": Vector3(32, 0, 0),
	}


## Balled up for flips and spins: rotates faster, reads clearly from afar.
static func tuck() -> Dictionary:
	return mirror({
		"Hips": Vector3(20, 0, 0),
		"Spine": Vector3(22, 0, 0),
		"Chest": Vector3(18, 0, 0),
		"Neck": Vector3(10, 0, 0),
		"LeftUpperLeg": Vector3(120, 0, 10),
		"LeftLowerLeg": Vector3(-140, 0, 0),
		"LeftFoot": Vector3(30, 0, 0),
		"LeftUpperArm": Vector3(70, -10, 8),
		"LeftLowerArm": Vector3(60, 0, 0),
	})


## Speed vault: hand planted on the obstacle, legs swung through to one side.
static func vault() -> Dictionary:
	return {
		"Hips": Vector3(10, -18, 18),
		"Spine": Vector3(16, -10, 6),
		"Chest": Vector3(10, -6, 0),
		"Neck": Vector3(-12, 8, 0),
		"Head": Vector3(-10, 8, 0),
		"LeftUpperArm": Vector3(54, 0, 6),
		"LeftLowerArm": Vector3(8, 0, 0),
		"LeftHand": Vector3(-60, 0, 0),
		"RightUpperArm": Vector3(40, 0, -28),
		"RightLowerArm": Vector3(40, 0, 0),
		"LeftUpperLeg": Vector3(84, 0, -12),
		"LeftLowerLeg": Vector3(-60, 0, 0),
		"RightUpperLeg": Vector3(74, 0, 26),
		"RightLowerLeg": Vector3(-30, 0, 0),
	}


## Mantle start: both hands on the ledge, knees up.
static func mantle_hang() -> Dictionary:
	return mirror({
		"Spine": Vector3(10, 0, 0),
		"Chest": Vector3(8, 0, 0),
		"Neck": Vector3(-16, 0, 0),
		"LeftUpperArm": Vector3(150, 0, 14),
		"LeftLowerArm": Vector3(40, 0, 0),
		"LeftHand": Vector3(-30, 0, 0),
		"LeftUpperLeg": Vector3(50, 0, 6),
		"LeftLowerLeg": Vector3(-80, 0, 0),
	})


## Mantle end: pushing down on the ledge, one knee coming up over it.
static func mantle_push() -> Dictionary:
	return {
		"Hips": Vector3(16, 0, 0),
		"Spine": Vector3(24, 0, 0),
		"Chest": Vector3(14, 0, 0),
		"Neck": Vector3(-20, 0, 0),
		"LeftUpperArm": Vector3(24, 0, 22),
		"LeftLowerArm": Vector3(10, 0, 0),
		"LeftHand": Vector3(-70, 0, 0),
		"RightUpperArm": Vector3(24, 0, -22),
		"RightLowerArm": Vector3(10, 0, 0),
		"RightHand": Vector3(-70, 0, 0),
		"LeftUpperLeg": Vector3(110, 0, 4),
		"LeftLowerLeg": Vector3(-120, 0, 0),
		"RightUpperLeg": Vector3(16, 0, -4),
		"RightLowerLeg": Vector3(-40, 0, 0),
	}


static func stun() -> Dictionary:
	return mirror({
		"Hips": Vector3(24, 0, 0),
		"Spine": Vector3(20, 0, 4),
		"Chest": Vector3(12, 0, 0),
		"Head": Vector3(12, 0, -6),
		"LeftUpperArm": Vector3(40, 0, 30),
		"LeftLowerArm": Vector3(50, 0, 0),
		"LeftUpperLeg": Vector3(60, 0, 12),
		"LeftLowerLeg": Vector3(-90, 0, 0),
	})


## Lying flat, face down (the root is tipped forward 90 degrees separately).
static func prone() -> Dictionary:
	return mirror({
		"Neck": Vector3(-36, 0, 0),
		"Head": Vector3(-30, 0, 0),
		"LeftUpperArm": Vector3(120, 0, 40),
		"LeftLowerArm": Vector3(90, 0, 0),
		"LeftUpperLeg": Vector3(0, 0, 8),
		"LeftFoot": Vector3(40, 0, 0),
	})


## Dolphin dive: arms reaching forward, body stretched out.
static func dive() -> Dictionary:
	return mirror({
		"Spine": Vector3(-8, 0, 0),
		"Chest": Vector3(-6, 0, 0),
		"Neck": Vector3(-34, 0, 0),
		"Head": Vector3(-20, 0, 0),
		"LeftUpperArm": Vector3(166, 0, 8),
		"LeftLowerArm": Vector3(8, 0, 0),
		"LeftUpperLeg": Vector3(-10, 0, 6),
		"LeftLowerLeg": Vector3(-20, 0, 0),
		"LeftFoot": Vector3(40, 0, 0),
	})


## Front kick (doors, windows, kick-offs): leading leg driven out straight.
static func kick() -> Dictionary:
	return {
		"Hips": Vector3(-14, 10, 0),
		"Spine": Vector3(-6, 0, 0),
		"Chest": Vector3(6, -8, 0),
		"Neck": Vector3(8, 0, 0),
		"LeftUpperLeg": Vector3(88, 0, 2),
		"LeftLowerLeg": Vector3(-6, 0, 0),
		"LeftFoot": Vector3(-24, 0, 0),
		"RightUpperLeg": Vector3(-6, 0, -4),
		"RightLowerLeg": Vector3(-30, 0, 0),
		"LeftUpperArm": Vector3(-20, 0, 40),
		"LeftLowerArm": Vector3(30, 0, 0),
		"RightUpperArm": Vector3(50, 0, -30),
		"RightLowerArm": Vector3(60, 0, 0),
	}


# ---------------------------------------------------------------- cycles

## Run cycle at phase 0..1 (one full stride: left step then right step).
## `amount` 0 = jog in place, 1 = full sprint stride.
static func run(phase: float, amount: float) -> Dictionary:
	var a := TAU * phase
	var s := clampf(amount, 0.0, 1.2)
	var pose := {
		"Hips": Vector3(6 + 6 * s, 10 * s * sin(a), 0),
		"Spine": Vector3(4 + 8 * s, -6 * s * sin(a), 0),
		"Chest": Vector3(2 + 2 * s, -10 * s * sin(a), 0),
		"Neck": Vector3(-4 - 6 * s, 4 * s * sin(a), 0),
		"Head": Vector3(-2 - 4 * s, 4 * s * sin(a), 0),
	}
	_leg(pose, "Left", a, s)
	_leg(pose, "Right", a + PI, s)
	_arm(pose, "Left", a + PI, s)
	_arm(pose, "Right", a, s)
	return pose


## Wallrun keeps the run cycle with a shorter, quicker stride and the arm
## on the wall side held out for balance (`side` = +1 wall on the right).
static func wallrun(phase: float, side: float) -> Dictionary:
	var pose := run(phase, 0.8)
	var arm := "LeftUpperArm" if side > 0.0 else "RightUpperArm"
	var lower := "LeftLowerArm" if side > 0.0 else "RightLowerArm"
	var outward := 62.0 if side > 0.0 else -62.0
	pose[arm] = Vector3(30, 0, outward)
	pose[lower] = Vector3(30, 0, 0)
	return pose


## Hand-over-hand up a wall.
static func climb(phase: float) -> Dictionary:
	var a := TAU * phase
	var pose := {
		"Spine": Vector3(6, 0, 0),
		"Neck": Vector3(-24, 0, 0),
		"Head": Vector3(-16, 0, 0),
	}
	for side: String in ["Left", "Right"]:
		var p := a if side == "Left" else a + PI
		var reach := 0.5 + 0.5 * sin(p)
		var z := 10.0 if side == "Left" else -10.0
		pose[side + "UpperArm"] = Vector3(lerpf(110.0, 170.0, reach), 0, z)
		pose[side + "LowerArm"] = Vector3(lerpf(80.0, 10.0, reach), 0, 0)
		var step := 0.5 + 0.5 * sin(p + PI)
		pose[side + "UpperLeg"] = Vector3(lerpf(10.0, 70.0, step), 0, z * 0.5)
		pose[side + "LowerLeg"] = Vector3(lerpf(-20.0, -100.0, step), 0, 0)
		pose[side + "Foot"] = Vector3(lerpf(30.0, -10.0, step), 0, 0)
	return pose


## One leg of the run cycle. `a` = 0 at foot strike under the body.
static func _leg(pose: Dictionary, side: String, a: float, s: float) -> void:
	var swing := sin(a)  # + = leg forward
	# The knee folds most while the leg swings through behind the body.
	var recover := maxf(0.0, -cos(a - 0.6))
	var z := 3.0 if side == "Left" else -3.0
	pose[side + "UpperLeg"] = Vector3((8 + 44 * s) * swing + 12 * s, 0, z)
	pose[side + "LowerLeg"] = Vector3(-(10 + 20 * s) - (40 + 70 * s) * recover, 0, 0)
	pose[side + "Foot"] = Vector3(-10 * swing * s + 18 * recover * s, 0, 0)


static func _arm(pose: Dictionary, side: String, a: float, s: float) -> void:
	var swing := sin(a)
	var z := 8.0 if side == "Left" else -8.0
	pose[side + "UpperArm"] = Vector3((14 + 46 * s) * swing + 4, 0, z)
	pose[side + "LowerArm"] = Vector3(40 + 46 * s + 18 * s * swing, 0, 0)
	pose[side + "Hand"] = Vector3(-6, 0, 0)
