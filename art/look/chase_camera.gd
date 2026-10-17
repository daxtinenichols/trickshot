extends Camera3D
## Full-screen third-person camera. F10 toggles it; the scroll wheel zooms,
## and zooming all the way in drops back to first person (scrolling out from
## first person comes back here). Gameplay keeps running exactly as in first
## person; this only moves the view.
##
## An orbit around the runner: mouse/stick left-right turns it with the
## player's yaw, up-down tilts it with the player's look pitch. It follows
## the player's interpolated transform rigidly (no positional lag), so the
## runner stays steady on screen at any frame rate; only zoom and wall
## pull-in are smoothed.
##
## Aiming: the camera sits over the right shoulder and always looks at the
## point the first-person view (which shots come from) is aimed at, so the
## crosshair in the middle of the screen is where shots land. Aiming down
## sights pulls it in tight over the shoulder.
##
## Follow flips (off by default): the orbit turns with the first-person
## view's full orientation, so flips, side flips and rolls tumble the
## camera with the runner; mouse look still moves it on top. Read from the
## `camera_follow_flips` setting when Settings has one, else `follow_flips`.

## Wheel actions, registered here like ArtLook's function keys so the rebind
## menu reserves them.
const ZOOM_ACTIONS := {"camera_zoom_in": MOUSE_BUTTON_WHEEL_UP, "camera_zoom_out": MOUSE_BUTTON_WHEEL_DOWN}
const MIN_DISTANCE := 1.6
const MAX_DISTANCE := 9.0
## Each wheel notch scales the distance by this much.
const ZOOM_STEP := 1.18
## Coming out of first person lands this far back.
const ENTER_DISTANCE := 2.6

var player: Player
## Default distance and how far it looks down on the runner with a level view.
var distance := 4.6
var tilt_deg := 22.0
## Over-the-shoulder: sideways offset (m, + = right), and while aiming down
## sights the distance, offset, tilt and field of view it eases to.
var shoulder := 0.5
var ads_distance := 1.7
var ads_shoulder := 0.62
var ads_tilt_deg := 6.0
var ads_fov := 52.0
var base_fov := 70.0
## The point it orbits, above the runner's feet.
var look_height := 0.9
## Fallback when Settings has no camera_follow_flips value.
var follow_flips := false
var _active := false
var _zoom := 5.2  # smoothed distance
var _pull := 9999.0  # wall pull-in, smoothed
var _aim_dist := 60.0  # distance along the view to what it's aimed at, smoothed


static func register_actions() -> void:
	for action: String in ZOOM_ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var b := InputEventMouseButton.new()
			b.button_index = ZOOM_ACTIONS[action]
			InputMap.action_add_event(action, b)


func setup(p: Player) -> void:
	player = p


func _ready() -> void:
	# After the player has placed its first-person view this frame.
	process_priority = 100
	top_level = true
	fov = base_fov
	near = 0.05
	far = 600.0
	cull_mask = 0xFFFFF & ~Pistol.VIEW_LAYER
	register_actions()
	_zoom = distance


func _unhandled_input(event: InputEvent) -> void:
	if player == null:
		return
	if event.is_action_pressed("toggle_chase_cam") and not event.is_echo():
		set_active(not _active)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("camera_zoom_out"):
		if _active:
			distance = minf(distance * ZOOM_STEP, MAX_DISTANCE)
		elif player.camera.current:
			distance = ENTER_DISTANCE
			set_active(true)
			_zoom = MIN_DISTANCE
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("camera_zoom_in") and _active:
		if distance <= MIN_DISTANCE + 0.01:
			set_active(false)
		else:
			distance = maxf(distance / ZOOM_STEP, MIN_DISTANCE)
		get_viewport().set_input_as_handled()


func is_active() -> bool:
	return _active


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
	# Real time, so zooming feels the same in slow motion.
	var real := delta / maxf(Engine.time_scale, 0.01)
	_zoom = lerpf(_zoom, distance, 1.0 - exp(-12.0 * real))
	_place(real)


func _snap() -> void:
	_zoom = distance
	_pull = 9999.0
	_aim_dist = _aim_hit_distance()
	_place(0.0)


func follows_flips() -> bool:
	var settings := get_node_or_null("/root/Settings")
	var v: Variant = settings.get("camera_follow_flips") if settings else null
	return v if v is bool else follow_flips


func _place(real_delta: float) -> void:
	var vt := player.visual_transform()
	var frame := vt.basis.orthonormalized()
	var pivot := vt.origin + frame.y * look_height
	var ads := clampf(player.aim_zoom, 0.0, 1.0)
	var tilt := deg_to_rad(lerpf(tilt_deg, ads_tilt_deg, ads))
	var orbit: Basis
	if follows_flips():
		# The first-person view already carries yaw, pitch, flips and rolls.
		var view := player.camera.global_basis.orthonormalized()
		pivot = vt.origin + player.body_up().normalized() * look_height
		orbit = view * Basis(Vector3.RIGHT, -tilt)
	else:
		# Level view = tilt down; looking up swings the camera low, looking
		# down swings it overhead.
		var angle := clampf(tilt - player.pitch, deg_to_rad(-55.0), deg_to_rad(85.0))
		orbit = frame * Basis(Vector3.RIGHT, -angle)
	# Over the right shoulder (kept out of walls by the same ray).
	var off := lerpf(shoulder, ads_shoulder, ads)
	off = clampf(_wall_distance(pivot, orbit.x, off + 0.25) - 0.25, 0.0, off)
	var origin := pivot + orbit.x * off
	var back := orbit.z
	var want := lerpf(_zoom, minf(ads_distance, _zoom), ads)
	# Pull in in front of walls; ease back out so it doesn't pop.
	var hit := _wall_distance(origin, back, want + 0.3)
	if hit < _pull or real_delta == 0.0:
		_pull = hit
	else:
		_pull = lerpf(_pull, hit, 1.0 - exp(-5.0 * real_delta))
	var d := maxf(minf(want, _pull - 0.3), 0.4)
	var pos := origin + back * d
	# Look at what the first-person view is aimed at. The distance along the
	# view ray is smoothed so sweeping across an edge doesn't jerk the view.
	var target := _aim_hit_distance()
	_aim_dist = target if real_delta == 0.0 else lerpf(_aim_dist, target, 1.0 - exp(-18.0 * real_delta))
	var eye := player.camera.global_transform
	var aim := eye.origin - eye.basis.z * _aim_dist
	var to_aim := aim - pos
	var basis := orbit
	if to_aim.length() > 1.0 and to_aim.normalized().dot(-orbit.z) > 0.2:
		basis = Basis.looking_at(to_aim, orbit.y)
	global_transform = Transform3D(basis, pos)
	fov = lerpf(base_fov, ads_fov, ads)


## How far along the first-person view the shot would land (to the first
## thing it hits, up to 120 m).
func _aim_hit_distance() -> float:
	if not is_inside_tree():
		return 60.0
	var eye := player.camera.global_transform
	var from := eye.origin
	var to := from - eye.basis.z * 120.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 4)
	q.exclude = [player.get_rid()]
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	return 120.0 if r.is_empty() else maxf(from.distance_to(r.position), 0.5)


func _wall_distance(from: Vector3, dir: Vector3, length: float) -> float:
	if not is_inside_tree():
		return length
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * length, 1)
	q.exclude = [player.get_rid()]
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	return length if r.is_empty() else from.distance_to(r.position)
