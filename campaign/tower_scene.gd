extends Node3D
## Stage 6 set pieces (Calder House and the Tower), loaded by path by
## MissionBuilder for the kinds in KINDS, and ticked by MissionRun like the
## chase set pieces (campaign/set_piece.gd): same setup / reset / tick and
## `went` signal. Placed by the route ({"set_piece": kind, "at": d, ...};
## "x", "up" move it across and up; local -Z is on along the run).
##
##   "photo"  (6-1 Head Office) a framed photo on the Host's office wall,
##            lit, at eye height: Calder Radio twenty years ago, young Rook
##            at the mic and Mags behind the booth glass in headphones. The
##            picture is rendered once, in its own little world, from the
##            Host's and Mags's models, and toned like an old print.
##            "face": 1 hangs it on the run's right-hand wall facing left,
##            -1 on the left wall facing right. Shelves of labelled tapes
##            beside it. Never fires.
##   "uplink" (6-3 The Climb) Echo takes the drones. Before it fires, the
##            Host's camera drones circle the tower ("center", world) with
##            red lights and the big screen ("screen", world, "screen_yaw")
##            shows the show's card. When you reach it: the camera drones
##            stop, turn to you and go green, every Ward gun drone still in
##            the air above you cuts out and drops, and the screen shows
##            you climbing (a camera off the nearest drone).
##   "cage"   (6-3) the builders' lift cage on the second line: a steel
##            cage over the deck with a sliding door across it, shut until
##            you come near, then it slides open (Echo has the door).
##   "trap"   (6-4 Dead Air, the studio) Echo zip-tied in the chair in
##            front of the console, the Host in the control booth behind
##            the glass. Fired as you reach her: Parker cuts her ties, the
##            Host throws a switch, a section of the antenna mast comes
##            through the ceiling onto Parker, the carpet and cables catch,
##            and Echo, free, goes to the studio's west door and looks back
##            as the Host steps out of the booth. Plays on after the level
##            is won (busy()), TRAP_TICKS long.
##   "watchers" (6-3, top decks) people on the city's roofs round the
##            tower, watching with torches. Found by looking down onto the
##            roofs the first time it ticks. Never fires.

const FIGURE_PATH := "res://art/characters/runner/runner_figure.gd"
const KINDS := ["photo", "uplink", "cage", "watchers", "trap"]
## The trap's beats (ticks after it fires).
const TRAP_CUT := 200
const TRAP_SWITCH := 480
const TRAP_DROP := 560
const TRAP_LAND := 600
const TRAP_STAND := 680
const TRAP_DOOR := 1100
const TRAP_HOST_OUT := 1200
const TRAP_TICKS := 1500
## The uplink's camera drones: how many, how far out and how fast round.
const DRONES := 6
const DRONE_ORBIT := 40.0
const DRONE_SPIN := 0.12
## The big screen (m) and its picture.
const SCREEN_SIZE := Vector2(8.0, 4.5)
const SCREEN_PIXELS := Vector2i(384, 216)
## The cage door: how long it takes to slide open (ticks).
const DOOR_TICKS := 50
## The photo: its size on the wall (m) and the picture's pixels.
const PHOTO_SIZE := Vector2(1.25, 0.86)
const PHOTO_PIXELS := Vector2i(480, 330)

var kind := "photo"
var spec := {}
var trigger := Vector3.ZERO
var radius := 7.0
var fired := false
## Physics ticks since it fired.
var ticks := 0
## Emitted when it fires (MissionRun turns it into a mission event).
signal went(kind: String)

var _photo_view: SubViewport
## Uplink: the drones ([node, light material, angle, height]), the screen.
var _drones: Array = []
var _red: StandardMaterial3D
var _green: StandardMaterial3D
var _screen: MeshInstance3D
var _screen_card: Node3D
var _screen_view: SubViewport
var _screen_cam: Camera3D
## Ticks since the level started (the drones keep circling).
var _t := 0
## Cage: the door and its shut position.
var _door: Node3D
var _door_shut := Vector3.ZERO
## Trap: its people and moving parts, and where Echo goes out.
var _echo: Node3D
var _host: Node3D
var _ties: Node3D
var _lever: Node3D
var _mast: Node3D
var _fire: Array = []
var _fire_light: OmniLight3D
var _echo_door := Vector3.ZERO
## Watchers: placed yet, and the torch flames.
var _placed := false
var _flames: Array = []


func setup(p: Dictionary) -> void:
	kind = String(p.set_piece)
	spec = p
	trigger = _vec(p.get("trigger", p.get("at", [0, 0, 0])))
	radius = float(p.get("radius", 7.0))
	position = _vec(p.get("at", [0, 0, 0]))
	rotation.y = deg_to_rad(float(p.get("yaw", 0.0)))
	match kind:
		"photo":
			_build_photo()
		"uplink":
			_build_uplink()
		"cage":
			_build_cage()
		"trap":
			_build_trap()
	reset()


## Back to before it fired (you went back to a checkpoint).
func reset() -> void:
	fired = false
	ticks = 0
	_t = 0
	if kind == "uplink":
		_uplink_show(false)
	if kind == "trap" and _mast != null:
		_trap_pose(0)
	if _door != null:
		_door.position = _door_shut
		(_door.get_node("Body/Shape") as CollisionShape3D).set_deferred("disabled", false)


func tick(player_pos: Vector3, run: Node) -> void:
	_t += 1
	match kind:
		"photo":
			return
		"watchers":
			_tick_watchers()
			return
		"uplink":
			_tick_drones(player_pos)
	if not fired:
		# A cage opens for anyone at its door, even someone who came at it
		# round the trigger.
		if player_pos.distance_to(trigger) < radius or kind == "cage" and player_pos.distance_to(global_position) < 4.0:
			fired = true
			ticks = 0
			if kind == "uplink":
				_uplink_show(true)
				_drop_gun_drones(run)
			went.emit(kind)
		return
	ticks += 1
	if kind == "cage":
		_tick_door()
	elif kind == "trap":
		_trap_pose(ticks)
	elif kind == "uplink" and ticks % 30 == 0:
		# Gun drones that come up later (a restart) go down too.
		_drop_gun_drones(run)


## Still playing out after the level is won.
func busy() -> bool:
	return fired and kind == "trap" and ticks < TRAP_TICKS


# ---------------------------------------------------------------- trap

func _build_trap() -> void:
	var dark := _mat(Color(0.1, 0.1, 0.11))
	var steel := _mat(Color(0.3, 0.3, 0.32))
	var rug := _mat(Color(0.42, 0.08, 0.07))
	# The carpet, a hair off the floor, and cables snaking over it.
	_box(self, Vector3(0, 0.012, 1.0), Vector3(10.0, 0.015, 8.0), rug)
	for i in 5:
		var c := _box(self, Vector3(-3.0 + i * 1.4, 0.03, 1.4 - i * 0.3), Vector3(0.05, 0.04, 5.0), dark)
		c.rotation.y = 0.25 * (i - 2)
	# The console behind her: a long desk, faders, a mic on a boom.
	_box(self, Vector3(0, 0.45, -2.0), Vector3(5.0, 0.9, 1.0), dark)
	_box(self, Vector3(0, 0.93, -1.95), Vector3(4.6, 0.06, 0.8), _mat(Color(0.2, 0.2, 0.22), 0.4))
	for i in 12:
		_box(self, Vector3(-2.0 + i * 0.36, 0.98, -1.8), Vector3(0.05, 0.04, 0.2), _mat(Color(0.9, 0.5, 0.2), 1.5))
	_box(self, Vector3(1.4, 1.35, -1.8), Vector3(0.04, 0.8, 0.04), steel)
	_box(self, Vector3(1.4, 1.75, -1.5), Vector3(0.12, 0.2, 0.12), dark)
	# Her chair, turned to face the door you come in by.
	_box(self, Vector3(0, 0.45, 0), Vector3(0.6, 0.08, 0.6), dark)
	_box(self, Vector3(0, 0.85, -0.3), Vector3(0.6, 0.8, 0.08), dark)
	_box(self, Vector3(0, 0.22, 0), Vector3(0.08, 0.44, 0.08), steel)
	# The booth: a low wall and glass to the ceiling, a gap at its east end
	# (its door), the Host inside by a big switch.
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.6, 0.75, 0.8, 0.25)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.1
	_box(self, Vector3(-0.75, 0.5, -4.0), Vector3(10.5, 1.0, 0.25), _mat(Color(0.35, 0.3, 0.27)))
	_box(self, Vector3(-0.75, 2.55, -4.0), Vector3(10.5, 3.1, 0.06), glass)
	_box(self, Vector3(4.55, 2.05, -4.0), Vector3(0.12, 4.1, 0.12), steel)
	_lever = _node(self, "Switch")
	_lever.position = Vector3(3.6, 1.4, -5.3)
	_box(_lever, Vector3(0, 0, 0), Vector3(0.5, 0.7, 0.15), steel)
	var arm := _box(_lever, Vector3(0, 0.25, 0.25), Vector3(0.07, 0.5, 0.07), _mat(Color(0.8, 0.1, 0.08), 1.0))
	arm.name = "Arm"
	_host = _figure(self, "host", Vector3(2.4, 0, -4.9), 0.0, "arms_crossed")
	_echo = _figure(self, "echo", Vector3(0, 0.48, 0.05), 0.0, "sitting")
	# The zip ties: bands round her wrists on the chair's arms.
	_ties = _node(self, "Ties")
	for x: float in [-0.28, 0.28]:
		_box(_ties, Vector3(x, 0.72, 0.1), Vector3(0.1, 0.03, 0.1), _mat(Color(0.92, 0.92, 0.88)))
	# The mast section waiting up in the ceiling: a lattice girder.
	_mast = _node(self, "Mast")
	var red := _mat(Color(0.55, 0.12, 0.08))
	var white := _mat(Color(0.85, 0.82, 0.76))
	for i in 8:
		var m := red if i % 2 == 0 else white
		for c: Vector2 in [Vector2(-0.3, -0.3), Vector2(0.3, -0.3), Vector2(-0.3, 0.3), Vector2(0.3, 0.3)]:
			_box(_mast, Vector3(c.x, c.y, -3.5 + i), Vector3(0.08, 0.08, 1.0), m)
		var brace := _box(_mast, Vector3(0, -0.3, -3.5 + i), Vector3(0.05, 0.05, 0.85), m)
		brace.rotation.y = 0.78 if i % 2 == 0 else -0.78
	# The fire: flames along the carpet and cables, out from where it lands.
	var flame := _mat(Color(1.0, 0.38, 0.06), 2.5)
	var core := _mat(Color(1.0, 0.75, 0.3), 3.0)
	for i in 14:
		var f := _box(self, Vector3(-3.6 + float((i * 5) % 14) * 0.55, 0.45, 3.2 - float(i % 5) * 1.1), Vector3(0.35, 0.9, 0.35), flame)
		_box(f, Vector3(0, -0.15, 0), Vector3(0.22, 0.5, 0.22), core)
		f.rotation.y = float(i) * 0.7
		f.visible = false
		_fire.append(f)
	_fire_light = OmniLight3D.new()
	_fire_light.light_color = Color(1.0, 0.55, 0.2)
	_fire_light.omni_range = 12.0
	_fire_light.position = Vector3(0, 1.5, 2.0)
	_fire_light.light_energy = 0.0
	add_child(_fire_light)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.85, 0.65)
	lamp.omni_range = 14.0
	lamp.light_energy = 1.2
	lamp.position = Vector3(0, 3.6, 0)
	add_child(lamp)
	_echo_door = _vec(spec.get("echo_door", [-8.6, 0, 3.55]))


## Everything in the trap where it is `t` ticks after it fired (0: before).
func _trap_pose(t: int) -> void:
	_ties.visible = t < TRAP_CUT
	(_lever.get_node("Arm") as Node3D).rotation.x = 0.0 if t < TRAP_SWITCH else -1.1
	# The mast: up in the ceiling, then down onto Parker, one end on the
	# console, the other on the floor where he stood.
	var rest := Vector3(0.6, 1.1, 2.0)
	var fall := clampf(float(t - TRAP_DROP) / (TRAP_LAND - TRAP_DROP), 0.0, 1.0)
	_mast.position = rest + Vector3(0, 9.0 * (1.0 - fall * fall), 0)
	_mast.rotation = Vector3(-0.32 * fall - 1.2 * (1.0 - fall), 0.45, 0.1)
	_mast.visible = t >= TRAP_DROP - 10
	# The fire spreads out over a few seconds.
	var burn := clampf(float(t - TRAP_LAND) / 420.0, 0.0, 1.0)
	for i in _fire.size():
		var f: MeshInstance3D = _fire[i]
		var lit := burn * _fire.size() > float(i)
		f.visible = lit
		if lit:
			f.scale = Vector3.ONE * (0.8 + 0.35 * absf(sin(float(t) * 0.23 + i * 1.3)))
	_fire_light.light_energy = burn * (2.2 + 0.4 * sin(float(t) * 0.3))
	if _echo != null:
		if t < TRAP_STAND:
			_echo.position = Vector3(0, 0.48, 0.05)
			_echo.rotation.y = 0.0
			_set_pose(_echo, "sitting")
			_echo.walk_speed = 0.0
		else:
			_set_pose(_echo, "arms_crossed")
			var k := clampf(float(t - TRAP_STAND - 80) / (TRAP_DOOR - TRAP_STAND - 80), 0.0, 1.0)
			_echo.position = Vector3(0, 0, 0.6).lerp(_echo_door, k)
			_echo.walk_speed = 2.2 if k > 0.0 and k < 1.0 else 0.0
			var to := _echo_door - Vector3(0, 0, 0.6)
			# Walking to the door, then turned back to look at him.
			_echo.rotation.y = atan2(to.x, to.z) if k < 1.0 else atan2(-to.x, -to.z)
	if _host != null:
		var h := clampf(float(t - TRAP_HOST_OUT) / 200.0, 0.0, 1.0)
		var near := 0.0 if t < TRAP_SWITCH - 200 else clampf(float(t - TRAP_SWITCH + 200) / 120.0, 0.0, 1.0)
		var at := Vector3(2.4, 0, -4.9).lerp(Vector3(3.2, 0, -4.9), near)
		_host.position = at.lerp(Vector3(5.3, 0, -3.2), h)
		_host.walk_speed = 1.6 if h > 0.0 and h < 1.0 else 0.0


func _set_pose(f: Node3D, pose: String) -> void:
	if f.pose_name == pose:
		return
	f.pose_name = pose
	if f.body != null and f.has_method("pose"):
		f.body.pose_override = f.pose(pose)


# ---------------------------------------------------------------- uplink

func _build_uplink() -> void:
	_red = _mat(Color(1.0, 0.12, 0.08), 4.0)
	_green = _mat(Color(0.2, 1.0, 0.35), 4.0)
	var dark := _mat(Color(0.1, 0.1, 0.11))
	var center := _vec(spec.get("center", [0, 0, 0]))
	for i in DRONES:
		var d := _node(self, "CameraDrone%d" % i)
		d.top_level = true
		_box(d, Vector3.ZERO, Vector3(0.55, 0.22, 0.55), dark)
		for c: Vector2 in [Vector2(-0.4, -0.4), Vector2(0.4, -0.4), Vector2(-0.4, 0.4), Vector2(0.4, 0.4)]:
			_box(d, Vector3(c.x, 0.12, c.y), Vector3(0.36, 0.02, 0.36), dark)
		_box(d, Vector3(0, -0.04, -0.3), Vector3(0.16, 0.16, 0.1), dark)
		var lamp := _box(d, Vector3(0, 0.0, -0.36), Vector3(0.09, 0.09, 0.04), _red)
		var a := TAU * float(i) / DRONES
		var h := trigger.y - 4.0 + float(i) * 5.0
		_drones.append([d, lamp, a, h])
		d.global_position = center + Vector3(sin(a), 0, cos(a)) * DRONE_ORBIT + Vector3(0, h, 0)
	# The big screen: a steel frame off the scaffold, the picture in it.
	var holder := _node(self, "Screen")
	holder.top_level = true
	holder.global_position = _vec(spec.get("screen", [0, 0, 0]))
	holder.rotation.y = deg_to_rad(float(spec.get("screen_yaw", 0.0)))
	var steel := _mat(Color(0.16, 0.15, 0.14))
	_box(holder, Vector3(0, 0, -0.12), Vector3(SCREEN_SIZE.x + 0.5, SCREEN_SIZE.y + 0.5, 0.22), steel)
	for x: float in [-SCREEN_SIZE.x * 0.35, SCREEN_SIZE.x * 0.35]:
		_box(holder, Vector3(x, SCREEN_SIZE.y * 0.5 + 1.5, -0.2), Vector3(0.12, 3.0, 0.12), steel)
	_screen = MeshInstance3D.new()
	_screen.name = "Picture"
	var q := QuadMesh.new()
	q.size = SCREEN_SIZE
	_screen.mesh = q
	_screen.position = Vector3(0, 0, 0.01)
	holder.add_child(_screen)
	# The show's card until Echo has it.
	_screen_card = _node(holder, "Card")
	var card := Label3D.new()
	card.text = "CALDER RADIO\nTHE HOST · LIVE"
	card.font_size = 96
	card.pixel_size = 0.012
	card.outline_size = 0
	card.modulate = Color(1.0, 0.85, 0.6)
	card.position = Vector3(0, 0, 0.03)
	_screen_card.add_child(card)
	if DisplayServer.get_name() != "headless":
		_screen_view = SubViewport.new()
		_screen_view.name = "Feed"
		_screen_view.size = SCREEN_PIXELS
		_screen_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(_screen_view)
		_screen_cam = Camera3D.new()
		_screen_cam.fov = 50.0
		_screen_view.add_child(_screen_cam)
	_uplink_show(false)


## The screen before (the card) or after (the feed) Echo takes over.
func _uplink_show(feed: bool) -> void:
	if _screen == null:
		return
	_screen_card.visible = not feed
	for d: Array in _drones:
		(d[1] as MeshInstance3D).material_override = _green if feed else _red
	if feed and _screen_view != null:
		_screen_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_texture = _screen_view.get_texture()
		_screen.material_override = m
	else:
		if _screen_view != null:
			_screen_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_screen.material_override = _mat(Color(0.09, 0.02, 0.02), 0.6)


func _tick_drones(player_pos: Vector3) -> void:
	var center := _vec(spec.get("center", [0, 0, 0]))
	var nearest: Node3D = null
	for d: Array in _drones:
		var node: Node3D = d[0]
		if not fired:
			var a: float = d[2] + float(_t) * DRONE_SPIN / 60.0
			var bob := sin(float(_t) / 60.0 * 1.3 + d[2]) * 0.6
			node.global_position = center + Vector3(sin(a), 0, cos(a)) * DRONE_ORBIT + Vector3(0, d[3] + bob, 0)
			node.look_at(node.global_position + Vector3(cos(a), 0, -sin(a)), Vector3.UP)
		else:
			# Holding where they stopped, turned to watch you.
			var to := player_pos + Vector3(0, 1.4, 0) - node.global_position
			if to.length() > 0.5:
				node.look_at(node.global_position + to, Vector3.UP)
		if nearest == null or node.global_position.distance_to(player_pos) < nearest.global_position.distance_to(player_pos):
			nearest = node
	if fired and _screen_cam != null and nearest != null:
		# The feed: from the nearest drone, a little closer in.
		var eye := nearest.global_position.lerp(player_pos + Vector3(0, 1.4, 0), 0.4)
		_screen_cam.global_position = eye
		_screen_cam.look_at(player_pos + Vector3(0, 1.2, 0), Vector3.UP)


## Every live Ward gun drone above the uplink cuts out and falls.
func _drop_gun_drones(run: Node) -> void:
	if run == null or not run.is_inside_tree():
		return
	for e: Node in run.get_tree().get_nodes_in_group("enemies"):
		var type := String(e.get_meta("enemy_type", ""))
		if type != "gun_drone" and type != "drone":
			continue
		if e.get("is_dead") or (e as Node3D).global_position.y < trigger.y - 3.0:
			continue
		e.call("_die", {"zone": &"body", "damage": 0.0, "source": "uplink"})


# ---------------------------------------------------------------- cage

func _build_cage() -> void:
	var w := 11.6
	var h := float(spec.get("height", 3.0))
	var deep := float(spec.get("depth", 6.0))
	var steel := _mat(Color(0.32, 0.27, 0.2))
	var cage := _node(self, "Cage")
	# Corner posts, the roof frame and mesh-ish bars down the sides.
	for x: float in [-w * 0.5, w * 0.5]:
		for z: float in [0.0, -deep]:
			_box(cage, Vector3(x, h * 0.5, z), Vector3(0.18, h, 0.18), steel)
		_box(cage, Vector3(x, h, -deep * 0.5), Vector3(0.14, 0.14, deep), steel)
		var z2 := -0.6
		while z2 > -deep:
			_box(cage, Vector3(x, h * 0.5, z2), Vector3(0.05, h, 0.05), steel)
			z2 -= 0.6
	_box(cage, Vector3(0, h, 0), Vector3(w, 0.14, 0.14), steel)
	_box(cage, Vector3(0, h, -deep), Vector3(w, 0.14, 0.14), steel)
	var plate := Label3D.new()
	plate.text = "WORK LIFT · 2 TONNE"
	plate.font_size = 48
	plate.pixel_size = 0.008
	plate.modulate = Color(0.95, 0.75, 0.2)
	plate.position = Vector3(0, h + 0.35, 0.1)
	cage.add_child(plate)
	# The door: a lattice gate across the front, solid until it opens.
	_door = _node(self, "Door")
	_door_shut = Vector3(0, 0, 0)
	for x in range(-5, 6):
		_box(_door, Vector3(float(x), h * 0.5, 0), Vector3(0.06, h - 0.1, 0.06), steel)
	for y: float in [0.15, h * 0.5, h - 0.15]:
		_box(_door, Vector3(0, y, 0), Vector3(w - 0.3, 0.08, 0.08), steel)
	var body := StaticBody3D.new()
	body.name = "Body"
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var b := BoxShape3D.new()
	b.size = Vector3(w - 0.3, h, 0.3)
	shape.shape = b
	shape.position = Vector3(0, h * 0.5, 0)
	body.add_child(shape)
	_door.add_child(body)


func _tick_door() -> void:
	# Slides off to the outside (+X) along the cage's front.
	var k := clampf(float(ticks) / DOOR_TICKS, 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k)
	_door.position = _door_shut + Vector3(11.0 * k, 0, 0)
	if ticks == 1:
		(_door.get_node("Body/Shape") as CollisionShape3D).set_deferred("disabled", true)


# ---------------------------------------------------------------- watchers

## Once, the first tick: look down onto the roofs in a ring round the tower
## and stand a few people with torches on each one found.
func _tick_watchers() -> void:
	if _placed:
		if _t % 4 == 0:
			for i in _flames.size():
				var f: MeshInstance3D = _flames[i]
				f.scale = Vector3.ONE * (0.85 + 0.25 * absf(sin(float(_t) * 0.21 + float(i) * 1.7)))
		return
	_placed = true
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space == null:
		return
	var center := _vec(spec.get("center", [0, 0, 0]))
	var cloth := _mat(Color(0.12, 0.11, 0.1))
	var fire := _mat(Color(1.0, 0.55, 0.15), 6.0)
	var groups := 0
	for i in 20:
		var a := TAU * float(i) / 20.0 + 0.13
		var r := 95.0 + float((i * 37) % 70)
		var p := center + Vector3(sin(a) * r, 0, cos(a) * r)
		var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 160, 0), p + Vector3(0, 6, 0))
		var hit := space.intersect_ray(q)
		if hit.is_empty() or (hit.normal as Vector3).y < 0.9:
			continue
		var top: Vector3 = hit.position
		var group := _node(self, "Watchers%d" % i)
		group.top_level = true
		group.global_position = top
		var face := atan2(center.x - top.x, center.z - top.z)
		for k in 3 + i % 3:
			var off := Vector3(float(k) * 1.1 - 1.4, 0, float((k * 5) % 3) * 0.6)
			var f := _node(group, "Person%d" % k)
			f.position = off.rotated(Vector3.UP, face)
			_box(f, Vector3(0, 0.85, 0), Vector3(0.45, 1.7, 0.3), cloth)
			_box(f, Vector3(0, 1.82, 0), Vector3(0.24, 0.26, 0.24), cloth)
			if k % 2 == 0:
				# A torch held up.
				_box(f, Vector3(0.3, 1.9, 0), Vector3(0.05, 0.7, 0.05), cloth)
				var flame := _box(f, Vector3(0.3, 2.35, 0), Vector3(0.28, 0.4, 0.28), fire)
				_flames.append(flame)
		groups += 1
		if groups >= 10:
			break


# ---------------------------------------------------------------- photo

func _build_photo() -> void:
	var face := float(spec.get("face", -1.0))
	# Turned to look out from the wall into the room.
	var holder := _node(self, "Photo")
	holder.rotation.y = -face * PI * 0.5
	var wood := _mat(Color(0.24, 0.15, 0.09))
	var w := PHOTO_SIZE.x
	var h := PHOTO_SIZE.y
	# The frame and its mount, a hair off the wall.
	_box(holder, Vector3(0, 0, 0.02), Vector3(w + 0.12, h + 0.12, 0.04), wood)
	var pic := MeshInstance3D.new()
	pic.name = "Picture"
	var quad := QuadMesh.new()
	quad.size = PHOTO_SIZE
	pic.mesh = quad
	pic.position = Vector3(0, 0, 0.045)
	holder.add_child(pic)
	var mat := ShaderMaterial.new()
	mat.shader = _print_shader()
	pic.material_override = mat
	if not Engine.is_editor_hint() and DisplayServer.get_name() != "headless":
		_photo_view = _render_photo()
		mat.set_shader_parameter("picture", _photo_view.get_texture())
	# A brass plate under it.
	var plate := Label3D.new()
	plate.text = "CALDER RADIO  ·  THE LATE SHOW\nRook & Margaret"
	plate.font_size = 40
	plate.pixel_size = 0.0016
	plate.modulate = Color(0.85, 0.72, 0.42)
	plate.position = Vector3(0, -h * 0.5 - 0.17, 0.05)
	holder.add_child(plate)
	# A picture light over it: you can't miss it from the door.
	var lamp := SpotLight3D.new()
	lamp.light_color = Color(1.0, 0.86, 0.62)
	lamp.light_energy = 3.0
	lamp.spot_range = 3.0
	lamp.spot_angle = 40.0
	lamp.position = Vector3(0, h * 0.5 + 0.35, 0.45)
	lamp.rotation.x = -deg_to_rad(65.0)
	holder.add_child(lamp)
	_box(holder, Vector3(0, h * 0.5 + 0.22, 0.12), Vector3(0.4, 0.05, 0.16), _mat(Color(0.55, 0.45, 0.25)))
	# Shelves of his tapes either side: every show, labelled by year.
	var spine := [Color(0.12, 0.12, 0.13), Color(0.6, 0.55, 0.45), Color(0.2, 0.22, 0.3)]
	for side: float in [-1.0, 1.0]:
		var x := side * (w * 0.5 + 0.9)
		for row in 3:
			var y := -0.55 + row * 0.42
			_box(holder, Vector3(x, y - 0.03, 0.14), Vector3(1.3, 0.04, 0.28), wood)
			for i in 14:
				var c: Color = spine[(i + row) % spine.size()]
				_box(holder, Vector3(x - 0.6 + i * 0.09, y + 0.12, 0.13), Vector3(0.07, 0.24, 0.22), _mat(c))
			var tag := Label3D.new()
			tag.text = str(1998 + row * 3 + (0 if side < 0.0 else 9)) + "-" + str(2000 + row * 3 + (0 if side < 0.0 else 9))
			tag.font_size = 32
			tag.pixel_size = 0.0014
			tag.modulate = Color(0.9, 0.88, 0.8)
			tag.position = Vector3(x, y - 0.03, 0.29)
			holder.add_child(tag)


## The picture: its own little world, rendered once. The booth: a desk and
## a mic, the glass behind, Mags at the desk on the other side of it.
func _render_photo() -> SubViewport:
	var view := SubViewport.new()
	view.name = "PhotoView"
	view.size = PHOTO_PIXELS
	view.own_world_3d = true
	view.transparent_bg = false
	view.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(view)
	var world := Node3D.new()
	view.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.32, 0.27, 0.22)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.68, 0.6)
	e.ambient_light_energy = 0.7
	env.environment = e
	world.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-35.0), deg_to_rad(30.0), 0)
	key.light_energy = 1.3
	world.add_child(key)
	var flash := OmniLight3D.new()
	flash.position = Vector3(0, 1.7, 2.2)
	flash.light_energy = 1.5
	flash.omni_range = 6.0
	world.add_child(flash)
	# Back wall with acoustic panels, the booth glass and its frame.
	_box(world, Vector3(0, 1.5, -2.6), Vector3(6, 3, 0.1), _mat(Color(0.35, 0.3, 0.27)))
	for i in 5:
		_box(world, Vector3(-2.0 + i, 1.8, -2.53), Vector3(0.8, 0.8, 0.04), _mat(Color(0.25, 0.22, 0.2)))
	_box(world, Vector3(0, 2.3, -0.7), Vector3(4.2, 0.08, 0.08), _mat(Color(0.2, 0.2, 0.2)))
	_box(world, Vector3(-2.1, 1.4, -0.7), Vector3(0.08, 1.9, 0.08), _mat(Color(0.2, 0.2, 0.2)))
	_box(world, Vector3(2.1, 1.4, -0.7), Vector3(0.08, 1.9, 0.08), _mat(Color(0.2, 0.2, 0.2)))
	# His desk and the mic on its arm.
	_box(world, Vector3(0, 0.75, 0.25), Vector3(2.4, 0.08, 0.9), _mat(Color(0.3, 0.2, 0.12)))
	_box(world, Vector3(0, 0.37, 0.25), Vector3(2.2, 0.74, 0.7), _mat(Color(0.18, 0.13, 0.09)))
	_box(world, Vector3(-0.45, 1.3, 0.5), Vector3(0.09, 0.2, 0.09), _mat(Color(0.08, 0.08, 0.08)))
	_box(world, Vector3(-0.45, 1.05, 0.35), Vector3(0.03, 0.5, 0.03), _mat(Color(0.3, 0.3, 0.3)))
	# Her desk behind the glass, the board and two VU meters glowing.
	_box(world, Vector3(0.6, 0.75, -1.25), Vector3(2.0, 0.08, 0.5), _mat(Color(0.25, 0.2, 0.15)))
	_box(world, Vector3(0.6, 0.82, -1.25), Vector3(1.4, 0.06, 0.35), _mat(Color(0.12, 0.12, 0.12)))
	_box(world, Vector3(1.3, 1.0, -1.4), Vector3(0.2, 0.12, 0.04), _mat(Color(0.9, 0.7, 0.3), 1.5))
	_box(world, Vector3(1.55, 1.0, -1.4), Vector3(0.2, 0.12, 0.04), _mat(Color(0.9, 0.7, 0.3), 1.5))
	# Rook at the mic, leaning in; Mags behind the glass, headphones on.
	# (Figures face +Z: the camera.)
	var rook := _figure(world, "host", Vector3(-0.45, 0, 0.95), 0.25, "idle")
	if rook != null:
		rook.scale = Vector3.ONE * 0.97
	var mags := _figure(world, "mags", Vector3(0.7, 0, -1.5), -0.2, "arms_crossed")
	if mags != null:
		_box(mags, Vector3(0, 1.62, 0), Vector3(0.24, 0.05, 0.05), _mat(Color(0.1, 0.1, 0.1)))
		_box(mags, Vector3(-0.11, 1.55, 0), Vector3(0.05, 0.11, 0.09), _mat(Color(0.1, 0.1, 0.1)))
		_box(mags, Vector3(0.11, 1.55, 0), Vector3(0.05, 0.11, 0.09), _mat(Color(0.1, 0.1, 0.1)))
	var cam := Camera3D.new()
	cam.position = Vector3(0.1, 1.45, 3.4)
	cam.rotation.x = deg_to_rad(-4.0)
	cam.fov = 34.0
	world.add_child(cam)
	cam.current = true
	return view


## An old print: sepia, faded blacks, a soft vignette and some grain.
static func _print_shader() -> Shader:
	var s := Shader.new()
	s.code = """
shader_type spatial;
render_mode unshaded;
uniform sampler2D picture : source_color, filter_linear;
void fragment() {
	vec3 c = texture(picture, UV).rgb;
	float l = dot(c, vec3(0.3, 0.59, 0.11));
	vec3 sepia = vec3(l * 1.07 + 0.05, l * 0.9 + 0.04, l * 0.68 + 0.03);
	vec2 d = UV - 0.5;
	float vig = 1.0 - dot(d, d) * 1.4;
	float grain = fract(sin(dot(UV * 431.0, vec2(12.9898, 78.233))) * 43758.5453) * 0.05;
	ALBEDO = clamp(sepia * vig + grain, 0.0, 1.0) * 0.92;
}
"""
	return s


# ---------------------------------------------------------------- parts

func _figure(parent: Node3D, runner: String, at: Vector3, yaw: float, pose: String) -> Node3D:
	var script := load(FIGURE_PATH) as Script if ResourceLoader.exists(FIGURE_PATH) else null
	if script == null or not script.can_instantiate():
		return null
	var f: Node3D = script.new()
	f.name = "Figure_" + runner
	f.runner = runner
	f.pose_name = pose
	f.held = ""
	f.position = at
	f.rotation.y = yaw
	parent.add_child(f)
	return f


func _node(parent: Node3D, n: String) -> Node3D:
	var node := Node3D.new()
	node.name = n
	parent.add_child(node)
	return node


func _mat(c: Color, glow := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	return m


## A box part, visual only.
func _box(parent: Node3D, center: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = mat
	mesh.position = center
	parent.add_child(mesh)
	return mesh


static func _vec(a: Variant) -> Vector3:
	if a is Array and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO
