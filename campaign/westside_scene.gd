extends Node3D
## Westside's set pieces (Stage 5: Storm Channels, The Rail Line), as
## {"set_piece": kind} pieces on a route roof. MissionBuilder loads this by
## path for the kinds in WESTSIDE_KINDS and MissionRun ticks it like the
## chase set pieces (campaign/set_piece.gd): same setup / reset / tick and
## `went` signal. Each fires once when you come within `radius` of its
## trigger and emits went(<its "id">) for the radio ("set_piece:<id>").
## The moving parts you can touch move in tick() (60 Hz, deterministic);
## waving arms, flashes and smoke are looks only.
##
## In the piece's own frame -Z is on along the run (the route turns it).
##
##   "floodlights"  Ward floodlight masts on both channel walls, already
##       on: "count" masts per side, "spacing" m apart, "x" across, standing
##       on the walls' top ("base" m up). Never fires.
##   "listeners"  people on the walkways over a channel ("people": [[x, y,
##       z, "wave" | "pot" | "watch"]]): they wave, one bangs a pot. Fires
##       when you run in below them.
##   "sluice"  a sluice gate across the channel, shut. Fired, a listener on
##       the walkway hauls it open by its wheel and waves you through; once
##       you're SLUICE_PAST m beyond it the Ward shut it again behind you
##       (back on the near side, it opens for you again).
##   "ward_water"  a Ward pumping station's clean water: a full tank behind
##       a fence on the right, a queue of empty jerry cans on this side.
##   "track_blast"  "length" m of rail deck ahead of `at`, standing over the
##       route's ramps down to the street and back up. Fired, a charge goes
##       off on it: the near and far ends hinge down onto the ramps and the
##       middle falls to the street in pieces.
##   "wagon"  a Static loco on the siding to the right shoves a goods wagon
##       through the points; it derails across the line at `at` and stays
##       there, propped on its bogies: slide under it (solid once it stops).
##   "junction"  a signal gantry over a fork's two lines ("spread" m apart,
##       the second on the right), both red. Fired, the left one turns green
##       GREEN_AT ticks later (during Echo's line); once you're JUNCTION_PAST
##       m on it emits went("junction_passed").

const FIGURE_MODEL := "res://enemies/models/raider.glb"
const ENEMY_BODY_PATH := "res://enemies/enemy_body.gd"
const ENEMY_POSES_PATH := "res://enemies/enemy_poses.gd"
const FIRE_SHADER_PATH := "res://campaign/fire.gdshader"
## Gear the listeners leave at home.
const GEAR := ["Rifle", "LongRifle", "ScrapShield", "Shield", "Helmet", "Armor", "Glow"]
## Their clothes: dusty civilians, not raiders.
const CLOTHES := [Color(0.62, 0.55, 0.46), Color(0.42, 0.48, 0.55), Color(0.55, 0.45, 0.40), Color(0.48, 0.52, 0.42)]

const SLUICE_W := 12.0
const SLUICE_H := 4.4
## How high the gate lifts (its bottom ends up this high).
const SLUICE_LIFT := 4.6
const SLUICE_TICKS := 50
const SLUICE_PAST := 10.0
const FALL_TICKS := 60
const WAGON_TICKS := 100
## The wagon at rest: across the line, propped on its bogies.
const WAGON_LEN := 10.0
const WAGON_W := 3.0
const WAGON_UNDER := 1.3
const WAGON_TOP := 4.2
const WAGON_REST_YAW := 72.0
const SIDING_X := 8.5
const GREEN_AT := 80
const JUNCTION_PAST := 60.0

var kind := "floodlights"
var spec := {}
var trigger := Vector3.ZERO
var radius := 10.0
var fired := false
var ticks := 0
signal went(kind: String)

var _id := ""
var _gate: AnimatableBody3D
var _gate_y := 0.0
var _closing := false
var _people: Array[Node3D] = []
var _poses: Script
var _parts: Array[Node3D] = []
var _rest: Array[Transform3D] = []
var _wagon: Node3D
var _wagon_body: StaticBody3D
var _loco: Node3D
var _signals: Array[MeshInstance3D] = []
var _passed := false
var _fx: Node3D
var _fx_time := -1.0
var _flash: OmniLight3D
var _t := 0.0


func setup(p: Dictionary) -> void:
	kind = String(p.set_piece)
	spec = p
	_id = String(p.get("id", kind))
	position = _vec(p.get("at", [0, 0, 0]))
	rotation.y = deg_to_rad(float(p.get("yaw", 0.0)))
	trigger = _vec(p.get("trigger", [0, -1000, 0]))
	radius = float(p.get("radius", 10.0))
	match kind:
		"floodlights":
			_build_floodlights()
		"listeners":
			_build_listeners()
		"sluice":
			_build_sluice()
		"ward_water":
			_build_ward_water()
		"track_blast":
			_build_deck()
		"wagon":
			_build_wagon()
		"junction":
			_build_junction()
	reset()


func reset() -> void:
	fired = false
	ticks = 0
	_passed = false
	_closing = false
	match kind:
		"sluice":
			_set_gate(0.0)
		"track_blast":
			for i in _parts.size():
				_parts[i].transform = _rest[i]
				_set_solid(_parts[i], false)
			if _fx != null:
				_fx.queue_free()
				_fx = null
			_fx_time = -1.0
		"wagon":
			_place_wagon(0.0)
			_wagon_body.process_mode = Node.PROCESS_MODE_DISABLED
			_wagon_body.get_child(0).disabled = true
		"junction":
			_light(0, false)


func tick(player_pos: Vector3, _run: Node) -> void:
	if not fired:
		if kind != "floodlights" and player_pos.distance_to(trigger) <= radius:
			fired = true
			ticks = 0
			_fire()
		return
	ticks += 1
	var local := to_local(player_pos)
	match kind:
		"sluice":
			# Open while you're short of it (or under it); the Ward shut it
			# once you're well past.
			var want := 0.0 if local.z < -SLUICE_PAST else 1.0
			_closing = want == 0.0
			var step := 1.0 / SLUICE_TICKS
			_set_gate(move_toward(_gate_y, want, step if want > _gate_y else step * 0.6))
		"track_blast":
			var k := clampf(float(ticks) / FALL_TICKS, 0.0, 1.0)
			_drop_deck(k * k)
			if ticks == FALL_TICKS:
				_sound("debris", Vector3(0, -8, -_length() * 0.5), 8.0)
				for i in range(2, _parts.size()):
					_set_solid(_parts[i], true)
		"wagon":
			var k := clampf(float(ticks) / WAGON_TICKS, 0.0, 1.0)
			_place_wagon(k)
			if ticks == WAGON_TICKS:
				_wagon_body.process_mode = Node.PROCESS_MODE_INHERIT
				_wagon_body.get_child(0).disabled = false
				_sound("door_bang", Vector3(0, 2, 0), 6.0)
		"junction":
			if ticks == GREEN_AT:
				_light(0, true)
			if not _passed and local.z < -JUNCTION_PAST:
				_passed = true
				went.emit("junction_passed")


func _fire() -> void:
	match kind:
		"track_blast":
			_burst(Vector3(0, 0.5, -_length() * 0.5))
			_sound("debris", Vector3(0, 0, -_length() * 0.5), 10.0)
			_sound("door_bang", Vector3(0, 0, -_length() * 0.5), 10.0)
		"sluice":
			_sound("door_close", Vector3(0, 2, 0), 4.0)
		"wagon":
			_sound("whoosh", Vector3(SIDING_X, 2, 20), 2.0)
	went.emit(_id)


func _process(delta: float) -> void:
	_t += delta
	if not _people.is_empty() and _poses != null:
		_pose_people(delta)
	if _fx != null and _fx_time >= 0.0:
		_fx_time += delta
		if _flash != null:
			_flash.light_energy = maxf(0.0, 12.0 * (1.0 - _fx_time / 0.7))
		var ball := _fx.get_node_or_null("Ball") as Node3D
		if ball != null:
			ball.scale = Vector3.ONE * lerpf(1.0, 9.0, clampf(_fx_time / 0.3, 0.0, 1.0))
			ball.visible = _fx_time < 0.8
	if kind == "sluice" and _people.size() > 0:
		pass


# ---------------------------------------------------------------- floodlights

func _build_floodlights() -> void:
	var count := int(spec.get("count", 3))
	var spacing := float(spec.get("spacing", 30.0))
	var x := float(spec.get("x", 7.0))
	var base := float(spec.get("base", 5.0))
	var steel := _mat(Color(0.3, 0.31, 0.32))
	var lamp := _mat(Color(0.85, 0.92, 1.0), 4.0)
	for i in count:
		for side: float in [-1.0, 1.0]:
			var z := -i * spacing - (spacing * 0.5 if side > 0.0 else 0.0)
			_box(self, Vector3(side * x, base + 4.0, z), Vector3(0.25, 8.0, 0.25), steel, false)
			_box(self, Vector3(side * (x - 0.9), base + 8.0, z), Vector3(1.8, 0.18, 0.18), steel, false)
			var head := _box(self, Vector3(side * (x - 1.8), base + 7.8, z), Vector3(1.1, 0.45, 0.7), lamp, false)
			head.rotation.z = side * deg_to_rad(25.0)
			if i % 2 == 0 and DisplayServer.get_name() != "headless":
				var spot := SpotLight3D.new()
				spot.light_color = Color(0.85, 0.92, 1.0)
				spot.light_energy = 5.0
				spot.spot_range = 22.0
				spot.spot_angle = 38.0
				spot.position = Vector3(side * (x - 1.8), base + 7.4, z)
				spot.rotation = Vector3(deg_to_rad(-90.0), 0, 0)
				spot.rotate_object_local(Vector3.RIGHT, 0.0)
				spot.rotation.z = side * deg_to_rad(-25.0)
				add_child(spot)


# ---------------------------------------------------------------- listeners

func _build_listeners() -> void:
	# Fresh orange Line arrows chalked down the channel walls, pointing on.
	for a: Array in spec.get("arrows", []):
		_arrow(Vector3(a[0], a[1], a[2]))
	for p: Array in spec.get("people", []):
		var at := Vector3(p[0], p[1], p[2])
		var b := _person(at, 1.0 if at.x < 0.0 else -1.0, _people.size())
		if b != null:
			b.set_meta("act", String(p[3]) if p.size() > 3 else "watch")
			if b.get_meta("act") == "pot":
				var pot := MeshInstance3D.new()
				var cyl := CylinderMesh.new()
				cyl.top_radius = 0.16
				cyl.bottom_radius = 0.14
				cyl.height = 0.16
				pot.mesh = cyl
				pot.material_override = _mat(Color(0.55, 0.56, 0.58))
				pot.name = "Pot"
				pot.position = Vector3(-0.1, 1.22, -0.38)
				b.add_child(pot)


## A civilian on a walkway at `at`, facing the channel (`face` +1: toward
## +X). Returns the posed body, or null without a model.
func _person(at: Vector3, face: float, i: int) -> Node3D:
	if Engine.is_editor_hint():
		return null
	var body_script := load(ENEMY_BODY_PATH) as Script if ResourceLoader.exists(ENEMY_BODY_PATH) else null
	_poses = load(ENEMY_POSES_PATH) as Script if ResourceLoader.exists(ENEMY_POSES_PATH) else null
	if body_script == null or not body_script.can_instantiate() or _poses == null:
		return null
	var b: Node3D = body_script.new()
	b.name = "Listener%d" % i
	add_child(b)
	if not b.load_model(FIGURE_MODEL):
		b.queue_free()
		return null
	for part: String in GEAR:
		b.show_part(part, false)
	b.tint(CLOTHES[i % CLOTHES.size()])
	b.position = at
	# Bodies face -Z: turn to face the channel, a little back up the run.
	b.rotation.y = -face * deg_to_rad(90.0 - 25.0)
	b.snap_pose(_poses.stand())
	_people.append(b)
	return b


func _pose_people(delta: float) -> void:
	var stand: Dictionary = _poses.stand()
	for i in _people.size():
		var b := _people[i]
		if not is_instance_valid(b):
			continue
		b.show_pose(stand, delta)
		var act: String = b.get_meta("act", "watch")
		var t := _t * 1.0 + i * 0.7
		match act:
			"wave":
				var sway := sin(t * 7.0) * 0.22
				b.reach("Right", Vector3(0.32 + sway, 2.05, -0.1), Vector3(0.9, 1.4, 0.2))
			"pot":
				b.reach("Left", Vector3(-0.1, 1.2, -0.4), Vector3(-0.8, 1.0, 0.1))
				b.reach("Right", Vector3(0.05, 1.32 + absf(sin(t * 8.0)) * 0.22, -0.38), Vector3(0.8, 1.0, 0.1))
			"crank":
				# Hauling the sluice wheel round (only once it's fired).
				var a := t * 5.0 if fired and ticks < SLUICE_TICKS + 20 else 0.0
				var c := Vector3(0.0, 1.15, -0.55)
				b.reach("Right", c + Vector3(0.25 * cos(a), 0.25 * sin(a), 0), Vector3(0.8, 1.0, 0.1))
				b.reach("Left", c - Vector3(0.25 * cos(a), 0.25 * sin(a), 0), Vector3(-0.8, 1.0, 0.1))
				if fired and ticks >= SLUICE_TICKS + 20:
					b.reach("Right", Vector3(0.32 + sin(t * 7.0) * 0.22, 2.05, -0.1), Vector3(0.9, 1.4, 0.2))


## A courier chalk arrow on the channel wall at `at` (x < 0: the left
## wall), pointing on along the run. Same shape as MissionBuilder's chalk.
func _arrow(at: Vector3) -> void:
	var side := -1.0 if at.x < 0.0 else 1.0
	var size := 2.4
	var shape: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(-0.11, -0.5), Vector2(0.11, -0.5), Vector2(0.11, 0.12), Vector2(-0.11, 0.12)]),
		PackedVector2Array([Vector2(-0.36, 0.08), Vector2(0.36, 0.08), Vector2(0.0, 0.5)]),
	]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for poly in shape:
		var pts: Array[Vector3] = []
		for v in poly:
			# Pointing +Y in the wall's plane, turned to point on (-Z).
			var r := v.rotated(PI * 0.5 * side) * size
			pts.append(Vector3(0.0, r.y, r.x * side))
		for i in range(1, pts.size() - 1):
			st.set_normal(Vector3(-side, 0, 0))
			st.add_vertex(pts[0])
			st.add_vertex(pts[i])
			st.add_vertex(pts[i + 1])
	var mesh := MeshInstance3D.new()
	mesh.name = "Chalk"
	mesh.mesh = st.commit()
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.98, 0.5, 0.14, 0.92)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.98, 0.42, 0.1)
	mat.emission_energy_multiplier = 0.6
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = mat
	mesh.position = Vector3(at.x - side * 0.04, at.y, at.z)
	add_child(mesh)


# ---------------------------------------------------------------- sluice

func _build_sluice() -> void:
	var concrete := _mat(Color(0.52, 0.5, 0.47))
	var steel := _mat(Color(0.36, 0.33, 0.3))
	var top := SLUICE_LIFT + SLUICE_H + 0.3
	for side: float in [-1.0, 1.0]:
		_box(self, Vector3(side * 6.3, top * 0.5, 0), Vector3(0.6, top, 1.2), concrete, true)
	_box(self, Vector3(0, top + 0.4, 0), Vector3(15.2, 0.8, 1.4), concrete, false)
	_box(self, Vector3(0, top + 0.4, 0), Vector3(15.2, 0.8, 1.4), concrete, false)
	_gate = AnimatableBody3D.new()
	_gate.sync_to_physics = false
	_gate.set_meta("kind", "NEUTRAL")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(SLUICE_W, SLUICE_H, 0.4)
	shape.shape = box
	_gate.add_child(shape)
	add_child(_gate)
	_box(_gate, Vector3.ZERO, Vector3(SLUICE_W, SLUICE_H, 0.4), steel, false)
	for i in 5:
		_box(_gate, Vector3(-4.8 + i * 2.4, 0, 0.25), Vector3(0.22, SLUICE_H, 0.12), _mat(Color(0.28, 0.25, 0.22)), false)
	var label := Label3D.new()
	label.text = "WARD WATER AUTHORITY\nSLUICE 2  KEEP CLOSED"
	label.font_size = 64
	label.pixel_size = 0.01
	label.modulate = Color(0.9, 0.9, 0.85)
	label.position = Vector3(0, 0.6, 0.33)
	_gate.add_child(label)
	# The wheel on the walkway, and the listener who hauls it.
	var wheel := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.3
	torus.outer_radius = 0.38
	wheel.mesh = torus
	wheel.material_override = _mat(Color(0.7, 0.2, 0.12))
	wheel.position = Vector3(-7.4, 5.0 + 1.15, 1.25)
	wheel.rotation.x = deg_to_rad(90.0)
	add_child(wheel)
	_box(self, Vector3(-7.4, 5.55, 1.0), Vector3(0.14, 1.1, 0.14), steel, false)
	var man := _person(Vector3(-7.4, 5.0, 1.85), 0.0, 3)
	if man != null:
		man.rotation.y = 0.0
		man.set_meta("act", "crank")
	_build_listeners()


func _set_gate(open: float) -> void:
	_gate_y = open
	_gate.position = Vector3(0, SLUICE_H * 0.5 + SLUICE_LIFT * open, 0)


# ---------------------------------------------------------------- ward water

func _build_ward_water() -> void:
	var tank := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 2.8
	cyl.bottom_radius = 2.8
	cyl.height = 7.0
	tank.mesh = cyl
	tank.material_override = _mat(Color(0.82, 0.84, 0.86))
	tank.position = Vector3(9.0, 3.5, -12.0)
	add_child(tank)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var c := CylinderShape3D.new()
	c.radius = 2.8
	c.height = 7.0
	shape.shape = c
	body.add_child(shape)
	tank.add_child(body)
	# A sight glass up its side, full to the top with clean water.
	_box(self, Vector3(6.25, 3.4, -12.0), Vector3(0.12, 5.6, 0.5), _mat(Color(0.35, 0.7, 0.95), 1.4), false)
	_box(self, Vector3(9.0, 7.1, -12.0), Vector3(1.2, 0.3, 1.2), _mat(Color(0.5, 0.5, 0.52)), false)
	var sign := Label3D.new()
	sign.text = "WARD WATER\nPOTABLE  RESERVE 3\nAUTHORISED ONLY"
	sign.font_size = 72
	sign.pixel_size = 0.012
	sign.modulate = Color(0.12, 0.2, 0.32)
	sign.position = Vector3(6.15, 4.0, -9.0)
	sign.rotation.y = deg_to_rad(-90.0)
	add_child(sign)
	# The fence between it and you.
	var kit: Script = load("res://art/props/prop_kit.gd")
	var w: float = kit.call("size_of", "fence_chainlink").x
	var z := -1.0
	while z > -24.0:
		kit.call("place", self, "fence_chainlink", Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), Vector3(5.6, 0, z - w * 0.5)), true)
		z -= w
	# Empty jerry cans queued along the fence on your side.
	var cans := [Color(0.62, 0.16, 0.12), Color(0.24, 0.36, 0.22), Color(0.66, 0.5, 0.18), Color(0.2, 0.3, 0.45)]
	for i in 18:
		var can := _box(self, Vector3(4.7 + (0.08 if i % 3 == 1 else 0.0), 0.24, -2.0 - i * 1.1), Vector3(0.18, 0.48, 0.36), _mat(cans[i % cans.size()]), false)
		can.rotation.y = deg_to_rad(float((i * 37) % 23) - 11.0)


# ---------------------------------------------------------------- track blast

func _length() -> float:
	return float(spec.get("length", 60.0))


## Three spans of rail deck from here to `length` m on (top at the roof's
## height): the near span, the far span and the middle.
func _build_deck() -> void:
	var l := _length()
	var deck := _mat(Color(0.5, 0.48, 0.45))
	var rail := _mat(Color(0.32, 0.27, 0.23))
	var near := l * 0.3
	var far := l * 0.32
	var spans := [[0.0, near], [l - far, l], [near, l - far]]
	for i in spans.size():
		var a: float = spans[i][0]
		var b: float = spans[i][1]
		var hinge := Vector3(0, 0, -a if i != 1 else -b)
		var part := Node3D.new()
		part.name = "Span%d" % i
		part.position = hinge
		add_child(part)
		var mid := -(a + b) * 0.5 - hinge.z
		_box(part, Vector3(0, -0.5, mid), Vector3(12.0, 1.0, b - a), deck, i == 2)
		for x: float in [-0.75, 0.75]:
			_box(part, Vector3(x, 0.08, mid), Vector3(0.1, 0.16, b - a), rail, false)
		_box(part, Vector3(-5.6, 0.5, mid), Vector3(0.08, 1.0, b - a), rail, false)
		_box(part, Vector3(5.6, 0.5, mid), Vector3(0.08, 1.0, b - a), rail, false)
		_parts.append(part)
		_rest.append(part.transform)
	# The middle span breaks in two as it falls.
	var m := _parts[2]
	var half := (l - near - far) * 0.5
	var split := Node3D.new()
	split.name = "Span3"
	split.position = Vector3(0, 0, -near - half)
	add_child(split)
	m.get_child(0).queue_free()
	_box(m, Vector3(0, -0.5, -half * 0.5), Vector3(12.0, 1.0, half), deck, true)
	_box(split, Vector3(0, -0.5, -half * 0.5), Vector3(12.0, 1.0, half), deck, true)
	_parts.append(split)
	_rest.append(split.transform)


## Lays the spans along their fall, k 0 (intact) .. 1 (down).
func _drop_deck(k: float) -> void:
	var l := _length()
	var y := position.y
	var near := l * 0.3
	var far := l * 0.32
	# The ends hinge down onto the ramps (a hair under them).
	var down_a := atan2(y, float(spec.get("ramp_down", 18.0)))
	var up_a := atan2(y, float(spec.get("ramp_up", 20.0)))
	_parts[0].transform = _rest[0] * Transform3D(Basis(Vector3.RIGHT, -down_a * k), Vector3(0, -0.25 * k, 0))
	_parts[1].transform = _rest[1] * Transform3D(Basis(Vector3.RIGHT, up_a * k), Vector3(0, -0.25 * k, 0))
	# The middle falls to the street, its halves off to either side.
	var fall := (y - 0.6) * k
	_parts[2].transform = _rest[2] * Transform3D(Basis(Vector3.FORWARD, deg_to_rad(14.0) * k), Vector3(-4.8 * k, -fall, 0))
	_parts[3].transform = _rest[3] * Transform3D(Basis(Vector3.FORWARD, deg_to_rad(-12.0) * k), Vector3(4.8 * k, -fall, 0))
	if k > 0.0 and _parts.size() > 3:
		pass


# ---------------------------------------------------------------- wagon

func _build_wagon() -> void:
	var rail := _mat(Color(0.32, 0.27, 0.23))
	# The siding and its points onto the line.
	for x: float in [SIDING_X - 0.75, SIDING_X + 0.75]:
		_box(self, Vector3(x, 0.08, 20.0), Vector3(0.1, 0.16, 40.0), rail, false)
	_wagon = Node3D.new()
	_wagon.name = "Wagon"
	add_child(_wagon)
	var brown := _mat(Color(0.42, 0.24, 0.16))
	var dark := _mat(Color(0.16, 0.15, 0.14))
	_box(_wagon, Vector3(0, (WAGON_UNDER + WAGON_TOP) * 0.5, 0), Vector3(WAGON_W, WAGON_TOP - WAGON_UNDER, WAGON_LEN), brown, false)
	for z: float in [-WAGON_LEN * 0.36, WAGON_LEN * 0.36]:
		_box(_wagon, Vector3(0, WAGON_UNDER * 0.5, z), Vector3(WAGON_W - 0.4, WAGON_UNDER, 1.6), dark, false)
	var paint := Label3D.new()
	paint.text = "STATIC"
	paint.font_size = 96
	paint.pixel_size = 0.014
	paint.modulate = Color(0.85, 0.15, 0.12)
	paint.position = Vector3(WAGON_W * 0.5 + 0.02, 2.8, 0)
	paint.rotation.y = deg_to_rad(90.0)
	_wagon.add_child(paint)
	# Solid at rest: the body over your head and the bogies either side.
	_wagon_body = StaticBody3D.new()
	_wagon_body.set_meta("kind", "NEUTRAL")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(WAGON_W, WAGON_TOP - WAGON_UNDER, WAGON_LEN)
	shape.shape = box
	shape.position = Vector3(0, (WAGON_UNDER + WAGON_TOP) * 0.5, 0)
	_wagon_body.add_child(shape)
	for z: float in [-WAGON_LEN * 0.36, WAGON_LEN * 0.36]:
		var s2 := CollisionShape3D.new()
		var b2 := BoxShape3D.new()
		b2.size = Vector3(WAGON_W - 0.4, WAGON_UNDER, 1.6)
		s2.shape = b2
		s2.position = Vector3(0, WAGON_UNDER * 0.5, z)
		_wagon_body.add_child(s2)
	_wagon.add_child(_wagon_body)
	_loco = Node3D.new()
	_loco.name = "Loco"
	add_child(_loco)
	_box(_loco, Vector3(0, 2.2, 0), Vector3(3.0, 3.6, 12.0), _mat(Color(0.2, 0.22, 0.24)), false)
	_box(_loco, Vector3(0, 4.4, 3.5), Vector3(2.6, 1.0, 3.0), _mat(Color(0.2, 0.22, 0.24)), false)
	_box(_loco, Vector3(0, 1.4, -6.05), Vector3(3.0, 0.5, 0.1), _mat(Color(0.95, 0.75, 0.1), 0.6), false)
	_box(_loco, Vector3(0, 3.2, -6.02), Vector3(0.5, 0.4, 0.08), _mat(Color(1.0, 0.85, 0.5), 3.0), false)


## Moves the wagon and loco along their shove, k 0 (waiting on the siding)
## .. 1 (across the line, loco stopped behind it).
func _place_wagon(k: float) -> void:
	var start := Vector3(SIDING_X, 0, 26.0)
	var points := Vector3(SIDING_X - 1.0, 0, 8.0)
	var rest := Vector3(0.6, 0, 0)
	var e := 1.0 - (1.0 - k) * (1.0 - k)
	var at: Vector3
	var yaw := 0.0
	if e < 0.5:
		at = start.lerp(points, e / 0.5)
	else:
		var s := (e - 0.5) / 0.5
		at = points.lerp(rest, s)
		yaw = WAGON_REST_YAW * s
	_wagon.position = at
	_wagon.rotation.y = deg_to_rad(yaw)
	# Tipped a little where it came off the rails.
	_wagon.rotation.z = deg_to_rad(4.0) * clampf((e - 0.5) * 2.0, 0.0, 1.0)
	_loco.position = Vector3(SIDING_X, 0, 26.0 + WAGON_LEN * 0.5 + 6.5 - (26.0 - 13.0) * minf(e / 0.6, 1.0))


# ---------------------------------------------------------------- junction

func _build_junction() -> void:
	var spread := float(spec.get("spread", 18.0))
	var steel := _mat(Color(0.3, 0.31, 0.32))
	var z := -16.0
	for x: float in [-6.6, spread + 6.6]:
		_box(self, Vector3(x, 4.0, z), Vector3(0.35, 8.0, 0.35), steel, false)
	_box(self, Vector3(spread * 0.5, 8.0, z), Vector3(spread + 13.6, 0.5, 0.5), steel, false)
	for x: float in [0.0, spread]:
		_box(self, Vector3(x, 6.9, z), Vector3(0.8, 1.8, 0.5), _mat(Color(0.08, 0.08, 0.08)), false)
		var red := _box(self, Vector3(x, 7.35, z + 0.27), Vector3(0.45, 0.45, 0.05), _mat(Color(1.0, 0.1, 0.06), 4.0), false) as MeshInstance3D
		var green := _box(self, Vector3(x, 6.55, z + 0.27), Vector3(0.45, 0.45, 0.05), _mat(Color(0.1, 1.0, 0.35), 4.0), false) as MeshInstance3D
		_signals.append(red)
		_signals.append(green)


## Signal `i` (0 the left line) green or red.
func _light(i: int, green: bool) -> void:
	for j in _signals.size():
		var on := (j % 2 == 0) != green if j / 2 == i else j % 2 == 0
		_signals[j].visible = on


# ---------------------------------------------------------------- bits

func _burst(at: Vector3) -> void:
	if _fx != null:
		_fx.queue_free()
	_fx = Node3D.new()
	_fx.name = "Burst"
	_fx.position = at
	add_child(_fx)
	_fx_time = 0.0
	if DisplayServer.get_name() == "headless":
		return
	var ball := Node3D.new()
	ball.name = "Ball"
	_fx.add_child(ball)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	mi.mesh = sm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(1.0, 0.55, 0.15)
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.emission_enabled = true
	fm.emission = Color(1.0, 0.45, 0.1)
	fm.emission_energy_multiplier = 3.0
	mi.material_override = fm
	ball.add_child(mi)
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.55, 0.2)
	_flash.omni_range = 40.0
	_flash.light_energy = 12.0
	_fx.add_child(_flash)
	var smoke := CPUParticles3D.new()
	smoke.one_shot = false
	smoke.amount = 40
	smoke.lifetime = 5.0
	smoke.direction = Vector3.UP
	smoke.spread = 25.0
	smoke.initial_velocity_min = 2.0
	smoke.initial_velocity_max = 4.0
	smoke.gravity = Vector3(0, 0.4, 0)
	smoke.scale_amount_min = 2.0
	smoke.scale_amount_max = 4.5
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	smoke.emission_box_extents = Vector3(5, 0.5, 8)
	var quad := QuadMesh.new()
	smoke.mesh = quad
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.16, 0.15, 0.14, 0.6)
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dm.vertex_color_use_as_albedo = true
	smoke.material_override = dm
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.8))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	smoke.color_ramp = fade
	_fx.add_child(smoke)
	var chunks := CPUParticles3D.new()
	chunks.one_shot = true
	chunks.explosiveness = 1.0
	chunks.amount = 40
	chunks.lifetime = 2.0
	chunks.direction = Vector3.UP
	chunks.spread = 70.0
	chunks.initial_velocity_min = 8.0
	chunks.initial_velocity_max = 16.0
	chunks.gravity = Vector3(0, -14, 0)
	var cm := BoxMesh.new()
	cm.size = Vector3(0.4, 0.25, 0.5)
	chunks.mesh = cm
	chunks.material_override = _mat(Color(0.3, 0.27, 0.25))
	_fx.add_child(chunks)
	chunks.emitting = true
	smoke.emitting = true
	_flames(_fx, Vector3(-3.0, -0.4, 4.0), 2.2, 3)
	_flames(_fx, Vector3(3.5, -0.4, -6.0), 1.8, 3)


func _flames(parent: Node3D, at: Vector3, height: float, count: int) -> void:
	var shader: Shader = load(FIRE_SHADER_PATH) if ResourceLoader.exists(FIRE_SHADER_PATH) else null
	for i in count:
		var flame := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.center_offset = Vector3(0, 0.5, 0)
		flame.mesh = quad
		var h := height * (0.7 + 0.2 * i)
		flame.scale = Vector3(h * 0.6, h, 1)
		flame.position = at + Vector3(-0.6 + 0.6 * i, 0, 0.3 * i)
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if shader != null:
			var m := ShaderMaterial.new()
			m.shader = shader
			m.set_shader_parameter("seed", 0.17 * i + at.x * 0.01)
			m.set_shader_parameter("speed", 1.5 + 0.2 * i)
			flame.material_override = m
		flame.add_to_group("mission_fire")
		parent.add_child(flame)


func _set_solid(n: Node, on: bool) -> void:
	for b: Node in n.find_children("*", "StaticBody3D", true, false):
		b.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
		for s: Node in b.get_children():
			if s is CollisionShape3D:
				(s as CollisionShape3D).disabled = not on


func _sound(sound_name: String, at: Vector3, volume_db: float) -> void:
	var audio := get_node_or_null("/root/GameAudio")
	if audio != null and audio.has_method("play_at") and is_inside_tree():
		audio.play_at(sound_name, to_global(at), volume_db)


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
		body.set_meta("kind", "NEUTRAL")
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
