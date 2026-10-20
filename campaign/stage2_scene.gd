extends Node3D
## Stage 2's set pieces (Warehouse Row and the Glass District), loaded by
## path by MissionBuilder for their kinds and ticked by MissionRun like the
## chase set pieces (campaign/set_piece.gd): same setup / reset / tick and
## `went` signal. Local frame: -Z is on along the run, +X is its right.
##
##   "juno_crane" (2-1 On Air) a container gantry crane straddling the roof
##       at `at`, its boom 20 m up and out over the city on the left. Juno
##       sits on the boom with her legs over the edge, watching the run.
##       Fired at "trigger": she stands, looks down at Parker, walks out
##       along the boom and drops off its far side out of sight. No
##       shooting. went("juno_crane").
##   "walkway" (2-2 Glass District) a glass walkway from the roof's end
##       (`at`) `span` m on across the gap to the next tower's roof, with
##       Juno on the far side by a window cleaner's cradle. Fired at
##       "trigger": she kicks the cradle loose, it swings into the walkway
##       and smashes it out (panes and deck drop into the gap), and she
##       walks off. The way on is the stairs down under it. Visual only (no
##       collision), so nothing changes for the run. went("walkway").
##   "line_chalk" (2-2) a stairwell bulkhead on the roof's edge at `at`,
##       an old orange Line chalk mark on its face and a fresh Static tag
##       sprayed over it. Static dressing; never fires.

const JUNO_MODEL := "res://enemies/models/juno.glb"
const ENEMY_BODY_PATH := "res://enemies/enemy_body.gd"
const ENEMY_POSES_PATH := "res://enemies/enemy_poses.gd"
## The crane: legs either side of the roof, the boom this high over it and
## reaching this far out to the left; where Juno sits on it (x along it).
const CRANE_LEG_X := 5.8
const CRANE_UP := 20.0
const CRANE_REACH := 22.0
const JUNO_SIT_X := -4.0
## Her timeline on the crane (ticks from the trigger): stand, look, walk
## out, drop.
const CRANE_STAND := 30
const CRANE_WALK := 110
const CRANE_DROP := 210
const CRANE_GONE := 270
const CRANE_WALK_SPEED := 4.0
## The walkway: kick, the cradle's swing, the hit, everything down, gone.
const WALK_KICK := 24
const WALK_HIT := 64
const WALK_FALL_TICKS := 90
const WALK_LEAVE := 120
const WALK_GONE := 260
const GLASS_COLOR := Color(0.62, 0.78, 0.84, 0.32)
const LINE_ORANGE := Color(0.96, 0.45, 0.13)
const STATIC_RED := Color(0.78, 0.08, 0.06)

var kind := ""
var spec := {}
var trigger := Vector3.ZERO
var radius := 12.0
var fired := false
var ticks := 0
signal went(kind: String)

var _juno: Node3D
var _poses: Script
## The walkway's moving parts: [node, rest transform, fall velocity, spin].
var _falling: Array = []
var _cradle: Node3D
var _walkway: Node3D


func setup(p: Dictionary) -> void:
	kind = String(p.set_piece)
	spec = p
	position = _vec(p.get("at", [0, 0, 0]))
	rotation.y = deg_to_rad(float(p.get("yaw", 0.0)))
	trigger = _vec(p.get("trigger", [0, -1000, 0]))
	radius = float(p.get("radius", 12.0))
	_poses = load(ENEMY_POSES_PATH) as Script if ResourceLoader.exists(ENEMY_POSES_PATH) else null
	match kind:
		"juno_crane":
			_build_crane()
		"walkway":
			_build_walkway()
		"line_chalk":
			_build_chalk()
	reset()


func reset() -> void:
	fired = false
	ticks = 0
	if _juno != null:
		_juno.visible = true
		_juno.transform = _juno_start()
		if _juno.has_method("snap_pose"):
			_juno.snap_pose(_sitting() if kind == "juno_crane" else _standing())
	for f: Array in _falling:
		(f[0] as Node3D).transform = f[1]
		(f[0] as Node3D).visible = true
	if _cradle != null:
		_cradle.rotation = Vector3.ZERO


func busy() -> bool:
	return false


func tick(player_pos: Vector3, _run: Node) -> void:
	if kind == "line_chalk":
		return
	if not fired:
		if player_pos.distance_to(trigger) <= radius:
			fired = true
			ticks = 0
			went.emit(kind)
		_pose_juno(player_pos)
		return
	ticks += 1
	if kind == "juno_crane":
		_crane_tick(player_pos)
	else:
		_walkway_tick(player_pos)


# ------------------------------------------------------------------ crane

func _build_crane() -> void:
	var steel := _material(Color(0.62, 0.42, 0.16), 0.8)
	var root := StaticBody3D.new()
	add_child(root)
	for side: float in [-1.0, 1.0]:
		for dz: float in [-3.0, 3.0]:
			_box(root, Vector3(side * CRANE_LEG_X, CRANE_UP * 0.5, dz), Vector3(0.8, CRANE_UP, 0.8), steel, true)
		# A sill beam along each side at the foot, and braces.
		_box(root, Vector3(side * CRANE_LEG_X, 0.4, 0), Vector3(0.6, 0.8, 7.4), steel, true)
		_box(root, Vector3(side * CRANE_LEG_X, CRANE_UP * 0.55, 0), Vector3(0.4, 0.4, 6.0), steel, false)
	# The boom: across the top and out over the city on the left.
	var boom_len := CRANE_LEG_X + CRANE_REACH + 4.0
	var boom_x := (CRANE_LEG_X + 4.0 - CRANE_REACH - CRANE_LEG_X) * 0.5
	for dz: float in [-1.4, 1.4]:
		_box(root, Vector3(boom_x, CRANE_UP + 0.5, dz), Vector3(boom_len, 1.0, 0.5), steel, false)
	# A walk plate between the girders (what she sits on and walks along).
	_box(root, Vector3(boom_x, CRANE_UP + 0.95, 0), Vector3(boom_len, 0.1, 2.3), _material(Color(0.3, 0.29, 0.27), 0.9), false)
	# The trolley and its cab, parked over the lane, and the machinery house
	# on the back end.
	_box(root, Vector3(1.0, CRANE_UP - 1.2, 0), Vector3(3.2, 2.2, 3.4), steel, false)
	_box(root, Vector3(CRANE_LEG_X + 2.0, CRANE_UP + 2.2, 0), Vector3(4.0, 2.6, 3.6), _material(Color(0.36, 0.38, 0.36), 0.9), false)
	_juno = _figure()


func _crane_tick(player_pos: Vector3) -> void:
	var dt := 1.0 / 60.0
	if _juno == null:
		return
	var seat := Vector3(JUNO_SIT_X, CRANE_UP + 1.0, 0.0)
	if ticks < CRANE_WALK:
		_juno.position = seat
		_face(_juno, player_pos)
		_show(_juno, _sitting() if ticks < CRANE_STAND else _standing(), dt, 0.0)
	elif ticks < CRANE_DROP:
		# Out along the boom, away over the city.
		var x := JUNO_SIT_X - CRANE_WALK_SPEED * float(ticks - CRANE_WALK) / 60.0
		_juno.position = Vector3(maxf(x, JUNO_SIT_X - CRANE_REACH + 3.0), CRANE_UP + 1.0, 0.0)
		_juno.rotation.y = -PI * 0.5
		_juno.step(CRANE_WALK_SPEED, 1.6, dt)
		_show(_juno, _poses.blend(_poses.stand(), _poses.legs(_juno.phase, 1.0), 1.0) if _poses else {}, dt, CRANE_WALK_SPEED)
	elif ticks < CRANE_GONE:
		# Off the far side: down behind the boom and gone.
		var t := float(ticks - CRANE_DROP) / 60.0
		var end_x := JUNO_SIT_X - CRANE_REACH + 3.0
		_juno.position = Vector3(end_x - 1.2 * t, CRANE_UP + 1.0 - 4.9 * t * t, -1.6 * t)
		_show(_juno, _poses.hop() if _poses else {}, dt, 0.0)
	else:
		_juno.visible = false


# ---------------------------------------------------------------- walkway

func _build_walkway() -> void:
	var span := float(spec.get("span", 24.0))
	var glass := _material(GLASS_COLOR, 0.1)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var frame := _material(Color(0.24, 0.26, 0.28), 0.6)
	var deck := _material(Color(0.5, 0.5, 0.48), 0.9)
	_walkway = Node3D.new()
	add_child(_walkway)
	# Two halves of deck that break in the middle, posts and roof beams,
	# and glass panes down both sides and over the top.
	var pane_len := 3.0
	var halves := 2
	for h in halves:
		var half := Node3D.new()
		var z0 := -span * float(h) / halves
		half.position = Vector3(0, 0, z0 if h == 0 else -span)
		_walkway.add_child(half)
		var dir := -1.0 if h == 0 else 1.0
		var hl := span / halves
		_box(half, Vector3(0, -0.15, dir * hl * 0.5), Vector3(3.2, 0.3, hl), deck, false)
		_box(half, Vector3(0, 2.75, dir * hl * 0.5), Vector3(3.2, 0.12, hl), frame, false)
		for side: float in [-1.0, 1.0]:
			_box(half, Vector3(side * 1.55, 0.5, dir * hl * 0.5), Vector3(0.1, 0.2, hl), frame, false)
		_falling.append([half, half.transform, Vector3(0, 0, 0), dir])
	var n := int(span / pane_len)
	for i in n:
		var z := -pane_len * (i + 0.5)
		for side: float in [-1.0, 1.0]:
			var pane := _box(_walkway, Vector3(side * 1.55, 1.45, z), Vector3(0.04, 2.5, pane_len - 0.1), glass, false)
			_falling.append([pane, pane.transform, Vector3(side * 1.6, 1.0, 0), 0.0])
			_box(_walkway, Vector3(side * 1.55, 1.45, z - pane_len * 0.5), Vector3(0.12, 2.6, 0.12), frame, false)
	# The cradle on its cables, hanging off the far tower's roof on the right.
	_cradle = Node3D.new()
	_cradle.position = Vector3(5.0, 6.0, -span - 1.0)
	add_child(_cradle)
	var cradle_body := _material(Color(0.72, 0.62, 0.2), 0.7)
	_box(_cradle, Vector3(0, -6.0, 0), Vector3(3.6, 1.1, 1.2), cradle_body, false)
	for dx: float in [-1.6, 1.6]:
		_box(_cradle, Vector3(dx, -3.0, 0), Vector3(0.05, 6.0, 0.05), frame, false)
	# The davit arm it hangs from.
	_box(self, Vector3(4.0, 6.2, -span - 1.0), Vector3(3.0, 0.3, 0.3), frame, false)
	_box(self, Vector3(2.6, 3.2, -span - 1.0), Vector3(0.3, 6.0, 0.3), frame, false)
	_juno = _figure()


func _walkway_tick(player_pos: Vector3) -> void:
	var dt := 1.0 / 60.0
	var span := float(spec.get("span", 24.0))
	# The cradle swings in off its arm into the walkway's middle.
	if ticks >= WALK_KICK:
		var swing := clampf(float(ticks - WALK_KICK) / float(WALK_HIT - WALK_KICK), 0.0, 1.0)
		var back := clampf(float(ticks - WALK_HIT) / 50.0, 0.0, 1.0)
		var a := sin(swing * PI * 0.5) * 0.9 * (1.0 - back * 0.6)
		_cradle.rotation = Vector3(-a * 0.8, 0, a)
	if ticks == WALK_KICK:
		_sound("door_bang", _cradle.position, 2.0)
	if ticks == WALK_HIT:
		_sound("glass", Vector3(0, 1.5, -span * 0.5), 6.0)
		_sound("glass", Vector3(0, 1.5, -span * 0.3), 4.0)
	if ticks > WALK_HIT:
		var t := float(ticks - WALK_HIT) / 60.0
		for f: Array in _falling:
			var n: Node3D = f[0]
			var rest: Transform3D = f[1]
			if t * 60.0 > WALK_FALL_TICKS + 30:
				n.visible = false
				continue
			var v: Vector3 = f[2]
			if f[3] is float and float(f[3]) != 0.0:
				# A deck half: tips down off its tower, hinged at its end.
				var tip := clampf(t * 1.4, 0.0, 1.3)
				n.transform = Transform3D(Basis(Vector3.RIGHT, -tip * float(f[3])), rest.origin - Vector3(0, 4.9 * maxf(t - 0.6, 0.0) ** 2, 0))
			else:
				n.transform = Transform3D(rest.basis.rotated(Vector3(0, 0, 1), t * 2.0), rest.origin + v * t + Vector3(0, -4.9 * t * t, 0))
	if _juno != null:
		if ticks < WALK_KICK:
			_face(_juno, player_pos)
			_show(_juno, _kick(clampf(float(ticks) / WALK_KICK, 0.0, 1.0)), dt, 0.0)
		elif ticks < WALK_LEAVE:
			_face(_juno, player_pos)
			_show(_juno, _standing(), dt, 0.0)
		elif ticks < WALK_GONE:
			var t2 := float(ticks - WALK_LEAVE) / 60.0
			_juno.rotation.y = 0.0
			_juno.position = _juno_start().origin + Vector3(0, 0, -3.2 * t2)
			_juno.step(3.2, 1.5, dt)
			_show(_juno, _poses.blend(_poses.stand(), _poses.legs(_juno.phase, 0.8), 1.0) if _poses else {}, dt, 3.2)
		else:
			_juno.visible = false


# ------------------------------------------------------------------ chalk

func _build_chalk() -> void:
	var body := StaticBody3D.new()
	add_child(body)
	_box(body, Vector3(0, 1.75, 0), Vector3(2.0, 3.5, 4.0), _material(Color(0.5, 0.47, 0.43), 0.95), true)
	_box(body, Vector3(0.4, 1.1, 2.01), Vector3(0.9, 2.1, 0.04), _material(Color(0.32, 0.3, 0.28), 0.8), false)
	# On the face toward the run (+Z): the Line's old orange arrow, faded,
	# and the Static's fresh red tag sprayed across it.
	var line := _label("THE LINE  >>", Vector3(-0.3, 2.3, 2.03), LINE_ORANGE, 70, 0.0)
	line.modulate.a = 0.75
	_label("STATIC", Vector3(-0.1, 2.0, 2.04), STATIC_RED, 120, deg_to_rad(-8.0))
	_label("X", Vector3(-0.3, 2.3, 2.05), STATIC_RED, 200, 0.0)


func _label(text: String, at: Vector3, color: Color, size: int, roll: float) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.004
	l.modulate = color
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false
	l.position = at
	l.rotation.z = roll
	add_child(l)
	return l


# ------------------------------------------------------------------- Juno

func _figure() -> Node3D:
	if Engine.is_editor_hint():
		return null
	var script := load(ENEMY_BODY_PATH) as Script if ResourceLoader.exists(ENEMY_BODY_PATH) else null
	if script == null or not script.can_instantiate() or _poses == null:
		return null
	var b: Node3D = script.new()
	b.name = "Juno"
	add_child(b)
	if not b.load_model(JUNO_MODEL):
		b.queue_free()
		return null
	for part: String in ["Rifle", "LongRifle", "Shield", "Pistol"]:
		b.show_part(part, false)
	b.grounded = kind != "juno_crane"
	return b


func _juno_start() -> Transform3D:
	if kind == "juno_crane":
		return Transform3D(Basis(Vector3.UP, 0.0), Vector3(JUNO_SIT_X, CRANE_UP + 1.0, 0.0))
	var span := float(spec.get("span", 24.0))
	return Transform3D(Basis.IDENTITY, Vector3(1.2, 0.0, -span - 2.0))


func _pose_juno(player_pos: Vector3) -> void:
	if _juno == null or not _juno.visible:
		return
	_face(_juno, player_pos)
	_show(_juno, _sitting() if kind == "juno_crane" else _standing(), 1.0 / 60.0, 0.0)


## Turns her to face `at` (enemy models face +Z at 0).
func _face(n: Node3D, at: Vector3) -> void:
	var local := to_local(at) - n.position
	n.rotation.y = atan2(local.x, local.z)


func _show(n: Node3D, pose: Dictionary, dt: float, _speed: float) -> void:
	if n.has_method("show_pose"):
		n.show_pose(pose, dt)


func _standing() -> Dictionary:
	return _poses.stand() if _poses else {}


## Sat on the boom's edge, legs over it, hands on the plate.
func _sitting() -> Dictionary:
	if _poses == null:
		return {}
	var p: Dictionary = _poses.stand()
	p["Hips"] = Vector3(0, 0, 0)
	p["Spine"] = Vector3(14, 0, 0)
	p["Chest"] = Vector3(6, 0, 0)
	p["Head"] = Vector3(10, 0, 0)
	p["LeftUpperLeg"] = Vector3(88, 0, 8)
	p["RightUpperLeg"] = Vector3(88, 0, -8)
	p["LeftLowerLeg"] = Vector3(-70, 0, 0)
	p["RightLowerLeg"] = Vector3(-84, 0, 0)
	return p


## Her kick at the cradle's catch: the right leg comes up and out.
func _kick(k: float) -> Dictionary:
	if _poses == null:
		return {}
	var p: Dictionary = _poses.stand()
	var w := sin(k * PI)
	p["RightUpperLeg"] = Vector3(70 * w, 0, -10 * w)
	p["RightLowerLeg"] = Vector3(-30 * (1.0 - w), 0, 0)
	p["Spine"] = Vector3(-10 * w, 0, 0)
	return p


# ---------------------------------------------------------------- helpers

func _material(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _box(parent: Node3D, at: Vector3, size: Vector3, mat: Material, solid: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	parent.add_child(mi)
	if solid and parent is StaticBody3D:
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		cs.position = at
		parent.add_child(cs)
	return mi


func _sound(sound_name: String, at: Vector3, volume_db: float) -> void:
	var audio := get_node_or_null("/root/GameAudio")
	if audio != null and audio.has_method("play_at") and is_inside_tree():
		audio.play_at(sound_name, to_global(at), volume_db)


static func _vec(a: Variant) -> Vector3:
	if a is Array and a.size() >= 3:
		return Vector3(a[0], a[1], a[2])
	return Vector3.ZERO
