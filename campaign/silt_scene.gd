extends Node3D
## Stage 3's set pieces (the Silt and the Drain): {"set_piece": kind, "at":
## [x, y, z], ...} on a route roof. MissionBuilder loads this by path for
## the kinds in SILT_KINDS, and MissionRun ticks it like the chase set
## pieces (campaign/set_piece.gd): same setup / reset / tick and `went`
## signal. Local frame: -Z is on along the run, +X to the right.
##
##   "silt_wreck"   (3-1's start, `at` on the stub of the blown Calder Way
##       bridge) what's left of the bridge: the snapped deck tilted down
##       into the dust (the route's ramp is its top), rebar and girders at
##       the break, the pier it broke over, the far stub hanging off its
##       last pier on the west bank, fires on the deck and dust still
##       coming off it. Chunks keep dropping off the break while it
##       settles. went("wreck") as you start.
##   "relay_box"    one of Echo's relays: a lamppost with a homemade box,
##       an aerial and a blinking green light, an orange Line mark on it.
##       went("relay") once it's in sight ahead (its trigger).
##   "hollows_cage" the Static's pen at the foot of the flood wall: bars
##       on three sides and a gate facing the run. At the trigger the
##       gate goes up (chained from the bank top) and the pack inside
##       pours out: went("cage"). The bars are solid.
##   "ring_pipe"    the broken ring-main joint round the drain's running
##       loop: a concrete pipe shell, `radius_m` round, looks only.
##
## Visual apart from the cage's bars and gate. Loaded by path (no
## class_name).

## Ticks the cage gate takes to go up (60 Hz).
const GATE_TICKS := 40
## Seconds between chunks falling off the bridge's break while it settles.
const CHUNK_EVERY := 2.6

var kind := "silt_wreck"
var spec := {}
var trigger := Vector3.ZERO
var radius := 10.0
var fired := false
var ticks := 0
signal went(kind: String)

var _gate: Node3D
var _gate_shape: CollisionShape3D
var _light: OmniLight3D
var _lamp: MeshInstance3D
var _chunks: Array[Node3D] = []
var _dust: CPUParticles3D
var _time := 0.0


func setup(p: Dictionary) -> void:
	kind = String(p.set_piece)
	spec = p
	position = _vec(p.get("at", [0, 0, 0]))
	rotation.y = deg_to_rad(float(p.get("yaw", 0.0)))
	trigger = _vec(p.get("trigger", p.get("at", [0, 0, 0])))
	radius = float(p.get("radius", 10.0))
	match kind:
		"silt_wreck":
			_build_wreck()
		"relay_box":
			_build_relay()
		"hollows_cage":
			_build_cage()
		"ring_pipe":
			_build_ring()
	reset()


func reset() -> void:
	fired = false
	ticks = 0
	if _gate != null:
		_gate.position.y = 0.0
		_gate_shape.disabled = false


func tick(player_pos: Vector3, _run: Node) -> void:
	if not fired:
		if kind != "ring_pipe" and player_pos.distance_to(trigger) <= radius:
			fired = true
			ticks = 0
			match kind:
				"silt_wreck":
					went.emit("wreck")
				"relay_box":
					went.emit("relay")
				"hollows_cage":
					_sound("door_bang", Vector3(0, 1.5, 0), 4.0)
					went.emit("cage")
		return
	ticks += 1
	if kind == "hollows_cage":
		var t := clampf(float(ticks) / GATE_TICKS, 0.0, 1.0)
		_gate.position.y = 2.6 * (1.0 - (1.0 - t) * (1.0 - t))
		# Up past head height: the pack (and you) can get through.
		_gate_shape.disabled = t > 0.6


## Looks only: the relay's blink and the wreck's falling chunks.
func _process(delta: float) -> void:
	_time += delta
	if _light != null:
		var on := fmod(_time, 1.2) < 0.25
		_light.light_energy = 1.6 if on else 0.0
		(_lamp.material_override as StandardMaterial3D).emission_energy_multiplier = 4.0 if on else 0.2
	for i in _chunks.size():
		var c := _chunks[i]
		var t := fmod(_time + i * CHUNK_EVERY / _chunks.size(), CHUNK_EVERY) / CHUNK_EVERY * 1.6
		var start: Vector3 = c.get_meta("from")
		c.visible = t < 1.0
		c.position = start + Vector3(0, -9.0 * t * t, 0)
		c.rotation = Vector3(t * 3.0, t * 2.0, 0)


# ---------------------------------------------------------------- builds

## The wreck, from the stub `at` (on the deck, 6 m from where it starts):
## the deck snapped 4 m on, at local z -4, and tilts down 8 m over 24 m.
func _build_wreck() -> void:
	var concrete := _mat(Color(0.52, 0.49, 0.45))
	var dark := _mat(Color(0.2, 0.18, 0.16))
	var steel := _mat(Color(0.3, 0.22, 0.17))
	var y := -position.y  # street (and the Silt's dust) in local terms
	# The break: rebar and a torn girder end sticking out of the stub.
	for i in 9:
		var x := -5.6 + i * 1.4
		_box(self, Vector3(x, -0.5, -4.6 - (i % 3) * 0.25), Vector3(0.06, 0.06, 1.4 + (i % 2) * 0.8), steel, false)
	for side: float in [-1.0, 1.0]:
		_box(self, Vector3(side * 5.2, -1.4, -5.4), Vector3(0.6, 1.2, 2.6), steel, false)
	# Under the tilted deck: the girders it fell with, and the pier it
	# broke over (world x 1776, 14 m on), cracked off below the deck.
	var slope := atan2(8.0, 24.0)
	for side: float in [-1.0, 1.0]:
		var g := Node3D.new()
		g.position = Vector3(side * 5.2, -1.6, -4.0)
		g.rotation.x = -slope
		add_child(g)
		_box(g, Vector3(0, 0, -12.0), Vector3(0.6, 1.2, 24.0), steel, false)
	_box(self, Vector3(0, y + 2.1, -14.0), Vector3(6.0, 4.2, 2.4), concrete, false)
	_box(self, Vector3(1.0, y + 4.35, -14.0), Vector3(4.0, 0.3, 2.0), dark, false)
	# The middle pier went: its stump and the rubble round it, off the
	# corner where the run turns north.
	_box(self, Vector3(-16.0, y + 0.6, -38.0), Vector3(3.0, 1.2, 3.4), concrete, false)
	_rubble(Vector3(-14.5, y, -30.0), 7, concrete)
	_rubble(Vector3(-15.5, y, -47.0), 6, dark)
	# The far stub, still on its pier on the west bank (world x 1732 to
	# 1708), its broken end hanging into the bed.
	_box(self, Vector3(0, y + 3.6, -58.0), Vector3(6.0, 7.2, 2.4), concrete, false)
	_box(self, Vector3(0, y + 7.6, -70.0), Vector3(14.0, 0.8, 24.0), concrete, false)
	var hang := Node3D.new()
	hang.position = Vector3(0, y + 7.6, -58.0)
	hang.rotation.x = deg_to_rad(38.0)
	add_child(hang)
	_box(hang, Vector3(0, 0, 4.0), Vector3(14.0, 0.8, 8.0), concrete, false)
	for i in 7:
		_box(hang, Vector3(-4.8 + i * 1.6, -0.2, 8.6), Vector3(0.06, 0.06, 1.6), steel, false)
	# Fires on the deck and in the wreckage, and the dust it threw up.
	for at: Vector3 in [Vector3(-3.0, -2.0, -12.0), Vector3(8.5, y + 0.3, -20.0), Vector3(-2.0, y + 7.9, -62.0)]:
		var fire := OmniLight3D.new()
		fire.position = at + Vector3(0, 1.0, 0)
		fire.light_color = Color(1.0, 0.55, 0.22)
		fire.light_energy = 2.2
		fire.omni_range = 9.0
		add_child(fire)
		_box(self, at + Vector3(0, 0.3, 0), Vector3(0.9, 0.6, 0.9), _mat(Color(1.0, 0.45, 0.12), 3.0), false)
	_dust = CPUParticles3D.new()
	_dust.position = Vector3(0, y + 1.0, -26.0)
	_dust.amount = 40
	_dust.lifetime = 7.0
	_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_dust.emission_box_extents = Vector3(9, 0.5, 8)
	_dust.direction = Vector3(0.3, 1, 0)
	_dust.spread = 25.0
	_dust.gravity = Vector3(0.4, 0.5, 0)
	_dust.initial_velocity_min = 0.6
	_dust.initial_velocity_max = 1.6
	_dust.scale_amount_min = 3.0
	_dust.scale_amount_max = 7.0
	_dust.mesh = _puff(Color(0.62, 0.55, 0.44, 0.35))
	add_child(_dust)
	# Chunks still dropping off the break while it settles.
	for i in 3:
		var c := _box(self, Vector3.ZERO, Vector3(0.5 + i * 0.15, 0.35, 0.45), concrete, false)
		c.set_meta("from", Vector3(-3.0 + i * 3.0, -1.2, -4.8))
		_chunks.append(c)


## A lamppost by the run (`at` at its foot) with Echo's relay on it.
func _build_relay() -> void:
	var pole := _mat(Color(0.25, 0.25, 0.24))
	var box := _mat(Color(0.32, 0.36, 0.3))
	_box(self, Vector3(0, 3.2, 0), Vector3(0.18, 6.4, 0.18), pole, false)
	_box(self, Vector3(-0.9, 6.3, 0), Vector3(1.8, 0.12, 0.12), pole, false)
	_box(self, Vector3(-1.7, 6.15, 0), Vector3(0.5, 0.18, 0.3), _mat(Color(0.4, 0.38, 0.32)), false)
	# The relay: a box strapped to the post, an aerial, cable down it.
	_box(self, Vector3(-0.24, 3.4, 0), Vector3(0.3, 0.46, 0.38), box, false)
	_box(self, Vector3(-0.24, 3.4, 0), Vector3(0.32, 0.06, 0.4), _mat(Color(0.86, 0.45, 0.13), 0.6), false)
	_box(self, Vector3(-0.2, 4.3, 0.1), Vector3(0.03, 1.4, 0.03), pole, false)
	_box(self, Vector3(-0.1, 2.0, 0), Vector3(0.03, 2.4, 0.03), _mat(Color(0.1, 0.1, 0.1)), false)
	# The Line's mark: orange chalk on the post at eye height.
	_box(self, Vector3(0, 1.7, 0), Vector3(0.2, 0.5, 0.2), _mat(Color(0.96, 0.45, 0.12), 0.8), false)
	_lamp = _box(self, Vector3(-0.41, 3.52, 0), Vector3(0.05, 0.07, 0.07), _mat(Color(0.3, 1.0, 0.4), 4.0), false)
	_light = OmniLight3D.new()
	_light.position = Vector3(-0.6, 3.5, 0)
	_light.light_color = Color(0.35, 1.0, 0.45)
	_light.omni_range = 3.0
	add_child(_light)


## The pen: 4 m across the run (local x -2..2) and 8 m along it, the gate
## on the run's side (-X).
func _build_cage() -> void:
	var bars := _mat(Color(0.28, 0.22, 0.18))
	var body := StaticBody3D.new()
	add_child(body)
	for z: float in [4.0, -4.0]:
		_bars(self, body, Vector3(0, 1.5, z), Vector3(4.0, 3.0, 0.1), true, bars)
	_bars(self, body, Vector3(2.0, 1.5, 0), Vector3(0.1, 3.0, 8.0), false, bars)
	_box(self, Vector3(0, 3.05, 0), Vector3(4.2, 0.1, 8.2), bars, false)
	_gate = Node3D.new()
	add_child(_gate)
	var gate_body := StaticBody3D.new()
	_gate.add_child(gate_body)
	_bars(_gate, gate_body, Vector3(-2.0, 1.5, 0), Vector3(0.1, 3.0, 8.0), false, bars)
	_gate_shape = gate_body.get_child(0) as CollisionShape3D
	# The chain up to the bank top, where the Static haul on it.
	_box(_gate, Vector3(-2.0, 5.0, 0), Vector3(0.05, 4.0, 0.05), bars, false)
	# Straw and bones on the floor.
	_box(self, Vector3(0.4, 0.03, 0), Vector3(3.2, 0.05, 7.0), _mat(Color(0.45, 0.38, 0.24)), false)


## The concrete shell of a broken ring-main joint round the loop: a pipe
## lying across the run, broken open at the bottom where you run in and
## out of the loop (looks only).
func _build_ring() -> void:
	var r := float(spec.get("radius_m", 5.3))
	var m := _mat(Color(0.5, 0.48, 0.44))
	var collar := _mat(Color(0.42, 0.4, 0.37))
	var center := Vector3(0, 4.5, 0)
	var n := 22
	var from := deg_to_rad(75.0)
	var to := deg_to_rad(285.0)
	var step := (to - from) / n
	for i in n:
		var a := from + step * (i + 0.5)
		var seg := Node3D.new()
		seg.position = center
		seg.rotation.x = a
		add_child(seg)
		_box(seg, Vector3(0, -r - 0.2, 0), Vector3(5.0, 0.4, r * step + 0.08), m, false)
		for x: float in [-2.6, 2.6]:
			_box(seg, Vector3(x, -r - 0.3, 0), Vector3(0.5, 0.7, r * step + 0.1), collar, false)
	# Broken ends of the shell, lying in the dust either side.
	_box(self, Vector3(0.6, 0.35, 5.6), Vector3(3.6, 0.7, 1.4), m, false).rotation.y = 0.3
	_box(self, Vector3(-0.8, 0.3, -5.8), Vector3(3.0, 0.6, 1.2), m, false).rotation.y = -0.4
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 8.0, 0)
	lamp.light_color = Color(1.0, 0.8, 0.55)
	lamp.light_energy = 1.4
	lamp.omni_range = 12.0
	add_child(lamp)


# ---------------------------------------------------------------- helpers

## A wall of bars `size` (thin along x or z), one collision box for it.
func _bars(parent: Node3D, body: StaticBody3D, center: Vector3, size: Vector3, across: bool, mat: Material) -> void:
	var long := size.x if across else size.z
	var n := int(long / 0.3)
	for i in n + 1:
		var o := -long * 0.5 + long * i / n
		var at := center + (Vector3(o, 0, 0) if across else Vector3(0, 0, o))
		_box(parent, at, Vector3(0.06, size.y, 0.06), mat, false)
	for h: float in [0.2, size.y - 0.1]:
		_box(parent, Vector3(center.x, h, center.z), Vector3(size.x if across else 0.1, 0.08, 0.1 if across else size.z), mat, false)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = center
	body.add_child(shape)


func _rubble(at: Vector3, n: int, mat: Material) -> void:
	for i in n:
		var a := i * 2.4
		var s := 0.5 + fmod(i * 0.37, 0.8)
		_box(self, at + Vector3(cos(a) * (1.0 + i * 0.3), s * 0.4, sin(a) * (1.0 + i * 0.25)), Vector3(s * 1.4, s * 0.8, s), mat, false).rotation.y = a


func _puff(c: Color) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var sm := StandardMaterial3D.new()
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = c
	quad.material = sm
	return quad


func _mat(c: Color, glow := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	return m


func _box(parent: Node3D, center: Vector3, size: Vector3, mat: Material, _solid: bool) -> Node3D:
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = mat
	mesh.position = center
	parent.add_child(mesh)
	return mesh


func _sound(sound_name: String, at: Vector3, volume_db: float) -> void:
	var audio := get_node_or_null("/root/GameAudio")
	if audio != null and audio.has_method("play_at") and is_inside_tree():
		audio.play_at(sound_name, to_global(at), volume_db)


static func _vec(a: Variant) -> Vector3:
	if a is Array and a.size() >= 3:
		return Vector3(a[0], a[1], a[2])
	return Vector3.ZERO
