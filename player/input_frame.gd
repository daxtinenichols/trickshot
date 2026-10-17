class_name InputFrame
extends RefCounted
## One tick of player intent. The controller only ever reads these, never the
## Input singleton directly, so the same frames can drive tests, replays and,
## later, networked prediction.

## x = strafe (right +), y = forward (forward +). Length <= 1.
var move := Vector2.ZERO
var jump_pressed := false
var jump_held := false
var crouch_pressed := false
var crouch_held := false
var kick_pressed := false
var sprint_held := false
var prone_pressed := false
var prone_held := false
## Quick 180 turn.
var turn_pressed := false


static func from_devices() -> InputFrame:
	var f := InputFrame.new()
	f.move = Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_forward") - Input.get_action_strength("move_back"))
	f.move = f.move.limit_length(1.0)
	f.jump_pressed = Input.is_action_just_pressed("jump")
	f.jump_held = Input.is_action_pressed("jump")
	f.crouch_pressed = Input.is_action_just_pressed("crouch")
	f.crouch_held = Input.is_action_pressed("crouch")
	f.kick_pressed = Input.is_action_just_pressed("kick")
	f.sprint_held = Input.is_action_pressed("sprint")
	f.prone_pressed = Input.is_action_just_pressed("prone")
	f.prone_held = Input.is_action_pressed("prone")
	f.turn_pressed = Input.is_action_just_pressed("quick_turn")
	return f


## Sprint defaults to on: scripted movement is usually "running".
static func make(move := Vector2.ZERO, jump := false, crouch := false, kick := false, sprint := true) -> InputFrame:
	var f := InputFrame.new()
	f.move = move
	f.jump_pressed = jump
	f.jump_held = jump
	f.crouch_pressed = crouch
	f.crouch_held = crouch
	f.kick_pressed = kick
	f.sprint_held = sprint
	return f
