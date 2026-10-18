extends Node3D
## A runner standing in a level as a character, not the player: Echo waiting
## in the studio at the end of Dead Air (m11). It shows the same RunnerBody
## and model the player would get for that runner, held in a still pose,
## and turns its head and shoulders to watch the camera as you come in.
##
## Visual only (with a small lamp that lights only her), plus a thin capsule so the player can't run through her.
## Missions place one with a {"figure": "echo", "at": [...], "yaw": deg,
## "pose": "arms_crossed"} piece (MissionBuilder loads this by path).

const BODY_SCRIPT_PATH := "res://art/characters/runner/runner_body.gd"
## How far (degrees) she turns her head and chest toward the camera.
const LOOK_LIMIT := 70.0

var runner := "echo"
var pose_name := "arms_crossed"
var body: Node3D
var _look := 0.0


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
	# A soft key light from the front so she reads against a bright opening.
	var lamp := OmniLight3D.new()
	lamp.name = "Lamp"
	lamp.position = Vector3(0, 2.4, 1.6)
	lamp.light_color = Color(1.0, 0.82, 0.62)
	lamp.light_energy = 1.4
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


func _process(delta: float) -> void:
	if body == null:
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
