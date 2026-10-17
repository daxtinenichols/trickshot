extends Camera3D
## Full-screen third-person camera for watching the runner's animation.
## F7 toggles it. Gameplay keeps running exactly as in first person; this
## only moves the view. (The in-game corner camera is separate.)

const FP_LAYER := 1 << 10  # layer 11: the view-model gun (see ArtLook)

var player: Player
var distance := 3.4
var height := 1.5
var _active := false


func setup(p: Player) -> void:
	player = p


func _ready() -> void:
	top_level = true
	fov = 70.0
	near = 0.05
	far = 600.0
	cull_mask = 0xFFFFF & ~FP_LAYER


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F7:
		set_active(not _active)
		get_viewport().set_input_as_handled()


func set_active(on: bool) -> void:
	_active = on
	if on:
		make_current()
		_snap()
	else:
		player.camera.make_current()


func _process(delta: float) -> void:
	if not _active or player == null:
		return
	var target := _desired()
	global_position = global_position.lerp(target, 1.0 - exp(-8.0 * delta))
	look_at(player.global_position + Vector3.UP * 1.1, Vector3.UP)


func _snap() -> void:
	global_position = _desired()
	look_at(player.global_position + Vector3.UP * 1.1, Vector3.UP)


func _desired() -> Vector3:
	var back := -player.forward()
	return player.global_position + back * distance + Vector3.UP * height
