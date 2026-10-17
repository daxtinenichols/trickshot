extends Camera3D
## Full-screen third-person camera for watching the runner's animation.
## F10 toggles it. Gameplay keeps running exactly as in first person; this
## only moves the view. (The in-game corner camera is separate.)


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
	cull_mask = 0xFFFFF & ~Pistol.VIEW_LAYER


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_chase_cam") and not event.is_echo():
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
	_look()


func _snap() -> void:
	global_position = _desired()
	_look()


func _desired() -> Vector3:
	# The player's frame tilts on ramps and loops; follow it.
	var frame := player.global_basis.orthonormalized()
	return player.global_position + frame * Vector3(0, height, distance)


func _look() -> void:
	var up := player.global_basis.y.normalized()
	var target := player.global_position + up * 1.1
	if global_position.distance_to(target) > 0.05:
		look_at(target, up)
