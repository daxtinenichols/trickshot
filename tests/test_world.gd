class_name TestWorld
extends Node3D
## Throwaway geometry + a scripted player for integration tests.

const PLAYER_SCENE := preload("res://player/player.tscn")

var player: Player
var states_seen: Array[Player.State] = []
var tricks_seen: Array[StringName] = []


func add_box(center: Vector3, size: Vector3, rot_x_deg := 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	body.global_transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(rot_x_deg), 0.0, 0.0)), center)
	return body


## Runnable pieces from SurfaceShapes (ramps, loops).
func add_surface(pieces: Array[Dictionary]) -> void:
	for piece in pieces:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.add_to_group("runnable")
		body.set_meta("flow", piece.flow)
		body.set_meta("face", piece.face)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = piece.size
		shape.shape = box
		body.add_child(shape)
		add_child(body)
		body.global_transform = piece.transform


## Big flat floor with its top at y = 0.
func add_floor(size := 400.0) -> void:
	add_box(Vector3(0.0, -0.5, 0.0), Vector3(size, 1.0, size))


func spawn_player(pos: Vector3, yaw := 0.0) -> Player:
	player = PLAYER_SCENE.instantiate()
	player.use_device_input = false
	player.scripted_input = InputFrame.new()
	# Each test gets fresh tuning so live edits never leak between tests.
	player.tuning = MovementTuning.new()
	add_child(player)
	player.global_position = pos
	player.set_view(yaw)
	player.set_spawn(player.global_transform)
	player.state_changed.connect(func(_from: Player.State, to: Player.State) -> void: states_seen.append(to))
	player.trick.connect(func(n: StringName, _i: Dictionary) -> void: tricks_seen.append(n))
	return player


## Run `frames` physics ticks with the given input held.
func step(frames: int, f: InputFrame = null) -> void:
	player.scripted_input = f if f != null else InputFrame.new()
	for i in frames:
		await get_tree().physics_frame


## Run until cond() is true or max_frames pass. Returns true if cond was met.
func step_until(cond: Callable, max_frames: int, f: InputFrame = null) -> bool:
	player.scripted_input = f if f != null else InputFrame.new()
	for i in max_frames:
		await get_tree().physics_frame
		if cond.call():
			return true
	return false


## One tick with a fresh press (jump/crouch/kick), then held for `hold` ticks.
func press(f: InputFrame, hold := 0) -> void:
	await step(1, f)
	if hold > 0:
		var held := InputFrame.new()
		held.move = f.move
		held.jump_held = f.jump_held
		held.crouch_held = f.crouch_held
		await step(hold, held)


static func forward_input() -> InputFrame:
	return InputFrame.make(Vector2(0.0, 1.0))
