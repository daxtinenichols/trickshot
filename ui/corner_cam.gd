class_name CornerCam
extends CanvasLayer
## Picture-in-picture third-person view in the lower-left corner, so you can
## watch the body's animations while playing in first person. F5 toggles it.
##
## A SubViewport sharing the main world renders a chase camera that sees the
## BodyRig (render layer 2) and the level, but not the first-person pistol.
## The first-person camera is set to skip layer 2 so it never sees the body.

const VIEW_SIZE := Vector2i(340, 220)
const MARGIN := 16.0
## Sits above the debug HUD's help line, which runs along the bottom-left.
const BOTTOM_OFFSET := 60.0
const BORDER := 2

## Chase offset in the player's frame: right, up, back (from FOLLOW_HEIGHT).
const OFFSET := Vector3(0.8, 1.2, 3.5)
const FOLLOW_HEIGHT := 1.0
const LOOK_HEIGHT := 1.3
const FOLLOW_RATE := 10.0
## Teleports (respawn, zone keys) snap instead of gliding across the map.
const SNAP_DISTANCE := 12.0
## Stops this far short of a wall the camera ray hits.
const WALL_PAD := 0.25

var player: Player
var rig: BodyRig
var camera: Camera3D
var viewport: SubViewport
var frame: PanelContainer

var _cam_pos := Vector3.ZERO
var _placed := false


func _ready() -> void:
	layer = 8
	# Keeps rendering (and F5 keeps working) while the game is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	frame = PanelContainer.new()
	frame.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	frame.position = Vector2(MARGIN, -BOTTOM_OFFSET - VIEW_SIZE.y - BORDER * 2)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.09, 0.6)
	style.border_color = Color(1, 1, 1, 0.55)
	style.set_border_width_all(BORDER)
	style.set_content_margin_all(BORDER)
	frame.add_theme_stylebox_override("panel", style)
	add_child(frame)

	var container := SubViewportContainer.new()
	container.stretch = true
	container.custom_minimum_size = VIEW_SIZE
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(container)

	# No own_world_3d: it renders the same world as the main view.
	viewport = SubViewport.new()
	viewport.size = VIEW_SIZE
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.handle_input_locally = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)

	camera = Camera3D.new()
	camera.fov = 42.0
	camera.near = 0.05
	camera.far = 400.0
	# Everything except the first-person pistol (the body holds its own).
	camera.cull_mask = 0xFFFFF & ~Pistol.VIEW_LAYER
	camera.top_level = true
	viewport.add_child(camera)
	camera.current = true


## Builds the body on the player and points the chase camera at it.
func setup(p: Player) -> void:
	player = p
	rig = BodyRig.new()
	p.add_child(rig)
	rig.setup(p)
	# The first-person view must never see the body.
	p.camera.cull_mask &= ~BodyRig.LAYER
	_placed = false
	_follow(0.0)


func is_enabled() -> bool:
	return frame.visible


## Shows or hides the corner view; hidden, it stops rendering and posing.
func set_enabled(on: bool) -> void:
	frame.visible = on
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	if rig:
		rig.visible = on
		rig.set_process(on)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_corner_cam"):
		set_enabled(not is_enabled())


func _process(delta: float) -> void:
	if is_enabled():
		_follow(delta)


func _follow(delta: float) -> void:
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		return
	# The player's own basis is its yaw (or, later, a surface-aligned frame),
	# never the view pitch, so flips show as the body turning, not the camera.
	var basis := player.global_basis.orthonormalized()
	var up := basis.y
	var feet := player.global_position
	var desired := feet + up * FOLLOW_HEIGHT + basis * OFFSET
	if not _placed or _cam_pos.distance_to(desired) > SNAP_DISTANCE:
		_cam_pos = desired
		_placed = true
	else:
		_cam_pos = _cam_pos.lerp(desired, 1.0 - exp(-FOLLOW_RATE * delta))
	var chest := feet + up * LOOK_HEIGHT
	var pos := _cam_pos
	# Pull in when a wall is between the body and the camera.
	var space := player.get_world_3d().direct_space_state
	if space:
		var q := PhysicsRayQueryParameters3D.create(chest, _cam_pos, 1)
		q.exclude = [player.get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			var to_cam := _cam_pos - chest
			var dist := maxf(chest.distance_to(hit.position) - WALL_PAD, 0.3)
			pos = chest + to_cam.normalized() * minf(dist, to_cam.length())
	if pos.distance_to(chest) < 0.05:
		return
	camera.global_position = pos
	var look_up := up if absf((chest - pos).normalized().dot(up)) < 0.99 else basis.z
	camera.look_at(chest, look_up)
