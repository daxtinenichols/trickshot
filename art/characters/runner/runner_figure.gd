extends Node3D
## A runner standing in a level as a character, not the player: Echo waiting
## in the studio at the end of Dead Air (m11), Mags in the Line's camp. It shows the same RunnerBody
## and model the player would get for that runner, held in a still pose,
## and turns its head and shoulders to watch the camera as you come in.
##
## Visual only (with a small lamp that lights only her), plus a thin capsule so the player can't run through her.
## Missions place one with a {"figure": "echo", "at": [...], "yaw": deg,
## "pose": "arms_crossed"} piece (MissionBuilder loads this by path).
## Poses: idle, arms_crossed, sitting (on the floor, back to a wall or
## wreck), holding_out (right hand held out with the pistol in it: Mags's
## handoff). Figures: "parker", "echo", "mags".

const BODY_SCRIPT_PATH := "res://art/characters/runner/runner_body.gd"
## How far (degrees) she turns her head and chest toward the camera.
const LOOK_LIMIT := 70.0
## Render layers: the world layer every camera draws (1) plus the runner
## body's layer (2) that the lamp lights.
const FIGURE_LAYERS := 1 | 2
## The held pistol, in the figure's own space: lying on its side across
## her palm, muzzle to her left, grip toward whoever she's handing it to.
const HELD_PISTOL_BASIS := Basis(Vector3(0, 1, 0), Vector3(0, 0, -1), Vector3(-1, 0, 0))
## From the hand bone to where the pistol sits on the palm (figure space).
const HELD_PISTOL_OFFSET := Vector3(0.02, 0.01, 0.08)

var runner := "echo"
var pose_name := "arms_crossed"
var body: Node3D
## Walking speed (m/s) while someone moves her (the Ward walking Echo off
## the skybridge, campaign/set_piece.gd): legs cycle, head stops following
## the camera, and she pulls back against it. 0 = still, in her pose.
var walk_speed := 0.0
## What the figure holds in her right hand: "pistol", or "" for nothing.
## The holding_out pose shows the pistol unless this is set first.
var held := "auto"
var held_model: Node3D
var _look := 0.0
var _phase := 0.0


## Still poses, in RunnerPoses' angle convention (degrees, character space).
static func pose(pose_id: String) -> Dictionary:
	match pose_id:
		"arms_crossed":
			# Weight on her right leg, arms folded: "You're late."
			return {
				"Hips": Vector3(0, 4, -3),
				"Spine": Vector3(-3, 0, 2),
				"Chest": Vector3(-2, 0, 1),
				"Head": Vector3(-4, 0, 4),
				"LeftShoulder": Vector3(0, 8, 0),
				"RightShoulder": Vector3(0, -8, 0),
				"LeftUpperArm": Vector3(8, -76, 2),
				"LeftLowerArm": Vector3(92, 0, 0),
				"LeftHand": Vector3(0, 0, -10),
				"RightUpperArm": Vector3(5, 76, -2),
				"RightLowerArm": Vector3(88, 0, 0),
				"RightHand": Vector3(0, 0, 10),
				"LeftUpperLeg": Vector3(8, -6, 6),
				"LeftLowerLeg": Vector3(-14, 0, 0),
				"LeftFoot": Vector3(6, 0, 0),
				"RightUpperLeg": Vector3(0, 0, -3),
				"RightLowerLeg": Vector3(-2, 0, 0),
			}
		"sitting":
			# On the floor, back against the wreck, left knee up with her
			# forearm on it, right leg out, right hand on the ground.
			return {
				"Hips": Vector3(-14, 0, 0),
				"Spine": Vector3(10, 0, 0),
				"Chest": Vector3(6, 0, 0),
				"Neck": Vector3(4, 0, 0),
				"Head": Vector3(-4, -8, 3),
				"LeftUpperLeg": Vector3(134, 4, 12),
				"LeftLowerLeg": Vector3(-138, 0, 0),
				"LeftFoot": Vector3(-2, 0, 0),
				"RightUpperLeg": Vector3(92, -6, -8),
				"RightLowerLeg": Vector3(-14, 0, 0),
				"RightFoot": Vector3(-10, 0, 0),
				"LeftUpperArm": Vector3(34, 0, 6),
				"LeftLowerArm": Vector3(30, 0, 0),
				"LeftHand": Vector3(36, 0, 0),
				"RightUpperArm": Vector3(-8, 0, -12),
				"RightLowerArm": Vector3(10, 0, 0),
				"RightHand": Vector3(-60, 0, 0),
			}
		"holding_out":
			# Right arm out at chest height, the pistol on her open hand:
			# "Take it. And bring it back."
			return {
				"Hips": Vector3(0, -4, 0),
				"Spine": Vector3(5, -4, 0),
				"Chest": Vector3(3, -4, 0),
				"Head": Vector3(-3, 6, 0),
				"LeftUpperArm": Vector3(6, 0, 7),
				"LeftLowerArm": Vector3(16, 0, 0),
				"RightUpperArm": Vector3(62, 0, -4),
				"RightLowerArm": Vector3(24, 0, 0),
				"RightHand": Vector3(-8, 0, 0),
				"LeftUpperLeg": Vector3(-4, 0, 3),
				"LeftLowerLeg": Vector3(-6, 0, 0),
				"RightUpperLeg": Vector3(10, 0, -3),
				"RightLowerLeg": Vector3(-8, 0, 0),
			}
	return RunnerPoses.idle()


func _ready() -> void:
	var script := load(BODY_SCRIPT_PATH) as Script if ResourceLoader.exists(BODY_SCRIPT_PATH) else null
	if script == null or not script.can_instantiate():
		push_warning("RunnerFigure: couldn't load the runner body, skipping %s" % runner)
		return
	body = script.new()
	body.name = "RunnerBody"
	body.runner = runner
	add_child(body)
	body.pose_override = pose(pose_name)
	body.global_transform = global_transform
	# RunnerBody draws on its own layer, which the first-person camera
	# skips (it's the player's own body). A figure is someone else: on the
	# world layer too, so every camera sees her, and still on the body layer
	# for her lamp.
	for mi: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		mi.layers = FIGURE_LAYERS
	if held == "auto":
		held = "pistol" if pose_name == "holding_out" else ""
	if held == "pistol":
		_hold_pistol()
	# A soft key light from the front so she reads against a bright opening.
	var lamp := OmniLight3D.new()
	lamp.name = "Lamp"
	lamp.position = Vector3(0, 2.4, 1.6)
	lamp.light_color = Color(1.0, 0.82, 0.62)
	# Softer on Mags: she stands out in the camp's daylight, not a dark studio.
	lamp.light_energy = 0.5 if runner == "mags" else 1.4
	lamp.omni_range = 4.5
	lamp.light_cull_mask = 2  # the runner body's layer only
	add_child(lamp)
	if not Engine.is_editor_hint():
		var blocker := StaticBody3D.new()
		blocker.name = "Blocker"
		var shape := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.32
		capsule.height = 1.75
		shape.shape = capsule
		shape.position.y = 0.875
		blocker.add_child(shape)
		add_child(blocker)


## The scrap pistol on her right palm, grip toward whoever she hands it to
## (placed from the hand bone every frame). Loaded by path; skipped if it's
## missing.
func _hold_pistol() -> void:
	var path := "res://art/weapons/scrap_pistol.glb"
	var scene := load(path) as PackedScene if ResourceLoader.exists(path) else null
	if scene == null:
		return
	var gun: Node3D = scene.instantiate()
	gun.name = "Pistol"
	gun.top_level = true
	var mat: Material = null
	for mi: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		mat = mi.material_override
		break
	for mi: MeshInstance3D in gun.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = mat
		mi.layers = FIGURE_LAYERS
	add_child(gun)
	held_model = gun
	_place_held()


func _place_held() -> void:
	if held_model == null:
		return
	var hand: Vector3 = body.bone_world_position("RightHand")
	held_model.global_transform = Transform3D(global_basis * HELD_PISTOL_BASIS, hand + global_basis * HELD_PISTOL_OFFSET)


func _process(delta: float) -> void:
	if body == null:
		return
	if walk_speed > 0.0:
		_phase = fposmod(_phase + walk_speed * minf(delta, 0.1) / 1.3, 1.0)
		var w := RunnerPoses.run(_phase, clampf(walk_speed / 9.0, 0.0, 1.0))
		# Leaning back, twisting to look behind her.
		w["Spine"] = w.get("Spine", Vector3.ZERO) + Vector3(-10, 8, 0)
		w["Neck"] = w.get("Neck", Vector3.ZERO) + Vector3(0, 20, 0)
		w["Head"] = w.get("Head", Vector3.ZERO) + Vector3(0, 30, 0)
		body.pose_override = w
		body.global_transform = global_transform
		return
	# Head and chest follow the camera (the player's eye), within limits.
	var cam := get_viewport().get_camera_3d()
	var target := 0.0
	if cam != null:
		var local := global_transform.affine_inverse() * cam.global_position
		if Vector2(local.x, local.z).length() > 0.5:
			target = clampf(rad_to_deg(atan2(local.x, local.z)), -LOOK_LIMIT, LOOK_LIMIT)
	_look = lerpf(_look, target, 1.0 - exp(-4.0 * minf(delta, 0.1)))
	var p := pose(pose_name)
	p["Chest"] = p.get("Chest", Vector3.ZERO) + Vector3(0, _look * 0.3, 0)
	p["Neck"] = p.get("Neck", Vector3.ZERO) + Vector3(0, _look * 0.3, 0)
	p["Head"] = p.get("Head", Vector3.ZERO) + Vector3(0, _look * 0.4, 0)
	body.pose_override = p
	body.global_transform = global_transform
	_place_held()
