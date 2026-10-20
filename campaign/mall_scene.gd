extends Node3D
## Meridian's set pieces (Stage 4), as route features {"set_piece":
## kind, "at": d, "x": across, "trigger": d}. MissionBuilder loads this by
## path for these kinds, and MissionRun ticks them like the chase set
## pieces (campaign/set_piece.gd): same setup / reset / tick and `went`
## signal, and each went(kind) is a story event the radio answers
## ("on": "set_piece:<kind>").
##
## Local frame (the route's): -Z is on along the run, +X to the right.
##   "shutters"  rows of shop shutters along the walls (`sides`: 1 right,
##               -1 left; `length` m of them) that roll up all together when
##               you reach the trigger: the Host's "Open the gates!". The
##               encounter's Hollows wait behind them. went("gates").
##   "juno"      Juno on the far walkway: once you reach the trigger she
##               runs level with you along the other line of the wing
##               (`line_x` across: the fork's offset), a little ahead,
##               salutes half way and drops out of sight off the end
##               (`length` m on). Never shoots, never blocks: looks only.
##               went("juno") as she appears, went("juno_gone") as she
##               drops.
##   "billboard" a dead billboard hung over the atrium void that stutters
##               and shows the Ward's logo (white, blue stripe) for `hold`
##               seconds during the sponsor spot. went("billboard").
##   "tvs"       the electronics floor: rows of TVs and radios on shelves
##               down both walls (`length` m) stutter on together with
##               white noise, then every screen shows Echo's light-bulb test
##               card for `hold` seconds, then they all die. went("tvs").
##   "convoy"    4-2's west wall over Westside (a mission piece in world
##               space, `at` on the street below the end): Ward floodlight
##               masts down both storm channel walls (`count` a side,
##               `spacing` m apart, `channel_x` across) come on one after
##               another, and `trucks` white Ward trucks with a blue stripe
##               roll out along the channel road (`road_x` across) while
##               Vell speaks. went("convoy").
## Visual only apart from the shelves (solid, out of the lane).

const ENEMY_BODY_PATH := "res://enemies/enemy_body.gd"
const ENEMY_POSES_PATH := "res://enemies/enemy_poses.gd"
const JUNO_MODEL := "res://enemies/models/juno.glb"
const PROP_KIT := "res://art/props/prop_kit.gd"
## Shutters: how long they take to roll up (60 Hz ticks), panel size.
const SHUTTER_TICKS := 70
const SHUTTER_W := 3.6
const SHUTTER_H := 3.4
## Juno keeps this far ahead of you along the run, runs no faster than
## this, and falls this far when she drops off the end.
const JUNO_LEAD := 4.0
const JUNO_TOP_SPEED := 16.0
const JUNO_DROP := 7.0
## TVs: white noise for this long before the test card comes up.
const TV_NOISE_TICKS := 100
const TV_SPACING := 1.6
## Convoy: a mast comes on every this many ticks, trucks run this fast
## (m/s) this far apart (m).
const MAST_TICKS := 24
const TRUCK_SPEED := 9.0
const TRUCK_GAP := 16.0
const MAST_HEIGHT := 14.0

var kind := "shutters"
var spec := {}
var trigger := Vector3.ZERO
var radius := 7.0
var fired := false
var ticks := 0
signal went(kind: String)

var _panels: Array[Node3D] = []
var _juno: Node3D
var _poses: Script
var _juno_z := 0.0
var _juno_gone := false
var _screens: Array[MeshInstance3D] = []
var _screen_mat: StandardMaterial3D
var _noise_mat: StandardMaterial3D
var _card_mat: StandardMaterial3D
var _logo: Node3D
var _dark: Node3D
var _noise_seed := 0
var _lamps: Array[Node3D] = []
var _trucks: Array[Node3D] = []


func setup(p: Dictionary) -> void:
	kind = String(p.set_piece)
	spec = p
	position = _vec(p.get("at", [0, 0, 0]))
	rotation.y = deg_to_rad(float(p.get("yaw", 0.0)))
	trigger = _vec(p.get("trigger", [0, -1000, 0]))
	radius = float(p.get("radius", 7.0))
	match kind:
		"shutters":
			_build_shutters()
		"juno":
			_build_juno()
		"billboard":
			_build_billboard()
		"tvs":
			_build_tvs()
		"convoy":
			_build_convoy()
	reset()


func reset() -> void:
	fired = false
	ticks = 0
	_juno_gone = false
	for pn: Node3D in _panels:
		pn.position.y = pn.get_meta("y0", 0.0)
		pn.scale.y = 1.0
	if _juno != null:
		_juno.visible = false
	if _logo != null:
		_logo.visible = false
		_dark.visible = true
	_set_screens(null)
	for lamp: Node3D in _lamps:
		lamp.visible = false
	for i in _trucks.size():
		_trucks[i].position.z = _truck_z(i, 0)


func tick(player_pos: Vector3, _run: Node) -> void:
	if not fired:
		if player_pos.distance_to(trigger) <= radius:
			fired = true
			ticks = 0
			went.emit("gates" if kind == "shutters" else kind)
		return
	ticks += 1
	match kind:
		"shutters":
			# Rolling up: each panel shrinks up into its box at the top.
			var k := clampf(float(ticks) / SHUTTER_TICKS, 0.0, 1.0)
			for pn: Node3D in _panels:
				pn.scale.y = maxf(1.0 - k, 0.02)
				pn.position.y = pn.get_meta("y0", 0.0) + SHUTTER_H * 0.5 * k
		"juno":
			_tick_juno(to_local(player_pos))
		"billboard":
			var hold := int(float(spec.get("hold", 10.0)) * 60.0)
			# A stutter, then the logo, then dark again.
			var on := ticks > 40 and ticks < hold
			if ticks <= 40:
				on = (ticks / 5) % 2 == 1
			_logo.visible = on
			_dark.visible = not on
		"tvs":
			var hold := int(float(spec.get("hold", 16.0)) * 60.0)
			if ticks < TV_NOISE_TICKS:
				# Stuttering on: noise flickers screen by screen.
				_noise_seed = (_noise_seed * 1103515245 + 12345) & 0x7fffffff
				for i in _screens.size():
					var lit := ((i * 7 + ticks / 3 + (_noise_seed >> 8)) % 5) < 3
					_screens[i].material_override = _noise_mat if lit else _screen_mat
			elif ticks < TV_NOISE_TICKS + hold:
				if ticks == TV_NOISE_TICKS:
					_set_screens(_card_mat)
			elif ticks == TV_NOISE_TICKS + hold:
				_set_screens(null)
		"convoy":
			# Pair by pair down the channels, nearest first.
			for i in _lamps.size():
				_lamps[i].visible = ticks >= (i / 2) * MAST_TICKS
			for i in _trucks.size():
				_trucks[i].position.z = _truck_z(i, ticks)


# ------------------------------------------------------------------ convoy

func _build_convoy() -> void:
	var count := int(spec.get("count", 8))
	var spacing := float(spec.get("spacing", 24.0))
	var cx := float(spec.get("channel_x", 16.0))
	var steel := _mat(Color(0.3, 0.31, 0.33))
	var lit := _mat(Color(0.95, 0.97, 1.0), 6.0)
	for i in count:
		var z := -20.0 - i * spacing
		for side in [-1.0, 1.0]:
			var mast := _node(self, "Mast")
			mast.position = Vector3(side * cx, 0, z)
			_box(mast, Vector3(0, MAST_HEIGHT * 0.5, 0), Vector3(0.35, MAST_HEIGHT, 0.35), steel, false)
			_box(mast, Vector3(-side * 0.6, MAST_HEIGHT, 0), Vector3(1.6, 0.9, 1.0), steel, false)
			var lamp := _node(mast, "Lamp")
			_box(lamp, Vector3(-side * 0.6, MAST_HEIGHT - 0.5, 0), Vector3(1.4, 0.1, 0.8), lit, false)
			if i % 2 == 0:
				var light := OmniLight3D.new()
				light.light_color = Color(0.9, 0.95, 1.0)
				light.omni_range = 24.0
				light.light_energy = 2.5
				light.position = Vector3(-side * 2.0, MAST_HEIGHT - 2.0, 0)
				lamp.add_child(light)
			_lamps.append(lamp)
	var white := _mat(Color(0.9, 0.91, 0.9))
	var blue := _mat(Color(0.12, 0.35, 0.85), 0.6)
	var dark := _mat(Color(0.08, 0.08, 0.09))
	var head := _mat(Color(1.0, 0.95, 0.8), 4.0)
	for i in int(spec.get("trucks", 5)):
		var t := _node(self, "Truck")
		t.position.x = float(spec.get("road_x", -30.0))
		_box(t, Vector3(0, 1.9, 1.2), Vector3(2.5, 2.8, 5.6), white, false)
		_box(t, Vector3(0, 1.5, 1.2), Vector3(2.52, 0.4, 5.62), blue, false)
		_box(t, Vector3(0, 1.4, -2.6), Vector3(2.4, 2.0, 2.0), white, false)
		_box(t, Vector3(0, 0.45, 0), Vector3(2.3, 0.6, 8.0), dark, false)
		for k in [-0.8, 0.8]:
			_box(t, Vector3(k, 1.0, -3.62), Vector3(0.35, 0.25, 0.05), head, false)
		_trucks.append(t)


## Truck i's place down the road `ticks` after the convoy sets off: it
## comes on from the near end and drives away along the channels.
func _truck_z(i: int, t: int) -> float:
	return 10.0 + i * TRUCK_GAP - TRUCK_SPEED * t / 60.0


# ---------------------------------------------------------------- shutters

func _build_shutters() -> void:
	for side: float in spec.get("sides", [-1.0]):
		_shutter_row(float(side))


func _shutter_row(side: float) -> void:
	var length := float(spec.get("length", 40.0))
	var x := side * float(spec.get("wall_x", 5.0))
	var steel := _mat(Color(0.42, 0.44, 0.45))
	var box := _mat(Color(0.2, 0.2, 0.21))
	var dark := _mat(Color(0.03, 0.03, 0.035))
	var sign := _mat(Color(0.75, 0.6, 0.35), 0.4)
	var n := maxi(int(length / (SHUTTER_W + 1.2)), 1)
	for i in n:
		var z := -(i + 0.5) * length / n
		# The shop: a dark opening in a shopfront, a sign over it.
		_box(self, Vector3(x + side * 0.55, SHUTTER_H * 0.5, z), Vector3(0.1, SHUTTER_H, SHUTTER_W), dark, false)
		_box(self, Vector3(x + side * 0.3, SHUTTER_H + 0.3, z), Vector3(0.6, 0.6, SHUTTER_W + 0.4), box, false)
		_box(self, Vector3(x + side * 0.3, SHUTTER_H + 0.9, z), Vector3(0.1, 0.5, SHUTTER_W * 0.8), sign, false)
		for k in [-1.0, 1.0]:
			_box(self, Vector3(x + side * 0.3, SHUTTER_H * 0.5, z + k * (SHUTTER_W * 0.5 + 0.15)), Vector3(0.6, SHUTTER_H, 0.3), box, false)
		var pn := _box(self, Vector3(x, SHUTTER_H * 0.5, z), Vector3(0.08, SHUTTER_H, SHUTTER_W), steel, false)
		pn.set_meta("y0", SHUTTER_H * 0.5)
		_panels.append(pn)


# -------------------------------------------------------------------- juno

func _build_juno() -> void:
	var body_script := load(ENEMY_BODY_PATH) as Script if ResourceLoader.exists(ENEMY_BODY_PATH) else null
	_poses = load(ENEMY_POSES_PATH) as Script if ResourceLoader.exists(ENEMY_POSES_PATH) else null
	if body_script == null or not body_script.can_instantiate() or _poses == null:
		return
	_juno = body_script.new()
	_juno.name = "Juno"
	add_child(_juno)
	if not _juno.load_model(JUNO_MODEL):
		_juno.queue_free()
		_juno = null


func _tick_juno(local: Vector3) -> void:
	if _juno == null:
		return
	var length := float(spec.get("length", 80.0))
	var line_x := float(spec.get("line_x", -18.0))
	var dt := 1.0 / 60.0
	if ticks == 1:
		_juno_z = minf(local.z - JUNO_LEAD, 0.0)
	# The line you're not on: the far walkway.
	var x := 0.0 if local.x < line_x * 0.5 else line_x
	var want := clampf(local.z - JUNO_LEAD, -length, 0.0)
	var step := clampf(want - _juno_z, -JUNO_TOP_SPEED * dt, 0.0)
	_juno_z += step
	var speed := -step / dt
	var y := 0.0
	if _juno_z <= -length + 0.5:
		# Off the end of the walkway and down into the store ahead.
		if not _juno_gone:
			_juno_gone = true
			_juno.set_meta("drop_tick", ticks)
			went.emit("juno_gone")
		var t := (ticks - int(_juno.get_meta("drop_tick", ticks))) * dt
		y = -0.5 * 20.0 * t * t
		_juno_z -= 6.0 * dt
		speed = 6.0
		_juno.visible = y > -JUNO_DROP
	else:
		_juno.visible = true
	# She faces on along the run (the model faces +Z: turn it round).
	_juno.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(x, y, _juno_z))
	_juno.step(speed, 1.5, dt)
	var lower: Dictionary = _poses.blend(_poses.stand(), _poses.legs(_juno.phase, clampf(speed / 4.0, 0.0, 2.0)), clampf(speed, 0.0, 1.0))
	var upper: Dictionary = _poses.stand()
	# Half way: two fingers off the brow, at you.
	var half := -length * 0.5
	if _juno_z < half and _juno_z > half - 10.0:
		upper = {"RightUpperArm": Vector3(-150, 0, -30), "RightLowerArm": Vector3(-110, 0, 0), "Head": Vector3(0, 60.0 * signf(-x if x != 0.0 else 1.0), 0)}
	_juno.show_pose(_poses.layer(lower, upper), dt)


# --------------------------------------------------------------- billboard

func _build_billboard() -> void:
	var w := float(spec.get("width", 9.0))
	var h := float(spec.get("height", 4.0))
	var frame := _mat(Color(0.16, 0.16, 0.17))
	_box(self, Vector3(0, 0, 0), Vector3(w + 0.4, h + 0.4, 0.3), frame, false)
	for k in [-1.0, 1.0]:
		# Hung from the ceiling on two cables.
		_box(self, Vector3(k * w * 0.35, h * 0.5 + 4.0, 0), Vector3(0.06, 8.0, 0.06), frame, false)
	_dark = _box(self, Vector3(0, 0, 0.16), Vector3(w, h, 0.02), _mat(Color(0.05, 0.06, 0.07)), false)
	_logo = _node(self, "WardLogo")
	_box(_logo, Vector3(0, 0, 0.17), Vector3(w, h, 0.02), _mat(Color(0.92, 0.94, 0.96), 1.6), false)
	_box(_logo, Vector3(0, -h * 0.18, 0.19), Vector3(w, h * 0.16, 0.02), _mat(Color(0.12, 0.35, 0.85), 2.0), false)
	var label := Label3D.new()
	label.text = "THE WARD"
	label.font_size = 220
	label.pixel_size = 0.01
	label.modulate = Color(0.12, 0.35, 0.85)
	label.outline_size = 0
	label.position = Vector3(0, h * 0.14, 0.2)
	_logo.add_child(label)
	var sub := Label3D.new()
	sub.text = "CLEAN WATER · ORDER · SAFETY"
	sub.font_size = 72
	sub.pixel_size = 0.01
	sub.modulate = Color(0.95, 0.96, 0.98)
	sub.outline_size = 0
	sub.position = Vector3(0, -h * 0.18, 0.21)
	_logo.add_child(sub)
	if spec.get("pole", true):
		var kit: Script = load(PROP_KIT)
		kit.call("place", self, "loudspeaker_pole", Transform3D(Basis(Vector3.UP, PI), Vector3(w * 0.5 + 1.5, -float(spec.get("hang", 6.0)), 0.5)), false)


# --------------------------------------------------------------------- tvs

func _build_tvs() -> void:
	var length := float(spec.get("length", 40.0))
	var shelf := _mat(Color(0.3, 0.24, 0.18))
	var casing := _mat(Color(0.1, 0.1, 0.11))
	_screen_mat = _mat(Color(0.04, 0.05, 0.05))
	_noise_mat = _mat(Color(0.8, 0.82, 0.85), 1.4)
	_noise_mat.albedo_texture = _noise_texture()
	_noise_mat.emission_texture = _noise_mat.albedo_texture
	_card_mat = _mat(Color(1, 1, 1), 1.8)
	_card_mat.albedo_texture = _bulb_texture()
	_card_mat.emission_texture = _card_mat.albedo_texture
	var wall := float(spec.get("wall_x", 5.3))
	for side: float in [-1.0, 1.0]:
		var x := side * wall
		# A run of shelving against each wall, 2 m tall.
		_box(self, Vector3(x + side * 0.1, 1.0, -length * 0.5), Vector3(0.8, 2.0, length), shelf, true)
		var z := -1.0
		var i := 0
		while z > -length + 1.0:
			for row in 2:
				var big := (i + row) % 3 == 0
				var size := Vector3(0.5, 0.75 if big else 0.5, 1.1 if big else 0.7)
				var at := Vector3(x - side * 0.05, 2.0 + row * 0.95 + size.y * 0.5, z)
				_box(self, at, size, casing, false)
				var screen := _box(self, at + Vector3(-side * 0.26, 0, 0), Vector3(0.02, size.y * 0.8, size.z * 0.85), _screen_mat, false)
				_screens.append(screen as MeshInstance3D)
			z -= TV_SPACING
			i += 1
	# A warm light that comes up with the screens.
	var lamp := OmniLight3D.new()
	lamp.name = "ScreenGlow"
	lamp.light_color = Color(0.85, 0.9, 1.0)
	lamp.omni_range = length * 0.6
	lamp.light_energy = 0.0
	lamp.position = Vector3(0, 3.0, -length * 0.5)
	add_child(lamp)
	_dark = lamp


func _set_screens(mat: Material) -> void:
	if _screens.is_empty():
		return
	for s: MeshInstance3D in _screens:
		s.material_override = _screen_mat if mat == null else mat
	if _dark is OmniLight3D:
		(_dark as OmniLight3D).light_energy = 0.0 if mat == null else 2.2


## Echo's test card: a hand-drawn light bulb, white on a dark screen.
static func _bulb_texture() -> ImageTexture:
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGB8)
	img.fill(Color(0.08, 0.09, 0.1))
	var c := Vector2(32, 26)
	for y in s:
		for x in s:
			var p := Vector2(x, y)
			var d := p.distance_to(c)
			# The glass: a ring, a little wobbly like a marker drawing.
			var ring := absf(d - 15.0 - sin(atan2(p.y - c.y, p.x - c.x) * 3.0) * 0.7) < 1.6 and y < 38
			# The neck and screw base.
			var neck := y >= 38 and y <= 50 and absf(x - 32) <= 7 and (absf(x - 32) >= 5.5 or (y - 38) % 4 < 2)
			# A filament zigzag inside.
			var fil := y >= 20 and y <= 30 and absf(float(x - 32) - (5.0 - absf(float((y - 20) % 6) - 3.0) * 2.0) * 0.6) < 1.0
			# Rays round it.
			var ang := atan2(p.y - c.y, p.x - c.x)
			var ray := d > 19.0 and d < 25.0 and fposmod(ang, PI / 4.0) < 0.12 and y < 40
			if ring or neck or fil or ray:
				img.set_pixel(x, y, Color(0.98, 0.96, 0.88))
	return ImageTexture.create_from_image(img)


static func _noise_texture() -> ImageTexture:
	var s := 32
	var img := Image.create(s, s, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	for y in s:
		for x in s:
			var v := rng.randf()
			img.set_pixel(x, y, Color(v, v, v))
	return ImageTexture.create_from_image(img)


# ----------------------------------------------------------------- helpers

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


## A box part; `solid` ones also stop you (a static body of their own).
func _box(parent: Node3D, center: Vector3, size: Vector3, mat: Material, solid: bool) -> Node3D:
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = mat
	mesh.position = center
	parent.add_child(mesh)
	if solid:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
		mesh.add_child(body)
	return mesh


static func _vec(a: Variant) -> Vector3:
	if a is Array and a.size() >= 3:
		return Vector3(a[0], a[1], a[2])
	return Vector3.ZERO
