extends Node3D
## A scripted moment in a chase mission (Signal Out): it fires once when you
## come within `radius` of its trigger point, and resets when you go back to
## a checkpoint. MissionBuilder makes one per {"set_piece": kind} piece
## (loaded by path) and MissionRun ticks them in its physics tick, so the
## parts you can touch are deterministic; flames, smoke and flashes are
## looks only.
##
## Kinds:
##   "debris"  a burning steel beam crashes down across the run at `at` and
##             stays there as an obstacle: "as": "hurdle" (vault it) or
##             "slide" (propped on rubble, slide under it). Solid only once
##             it has landed.
##   "host"    the Host cuts through the building and drops in `gap` m
##             behind you (Pursuer.close_in), if he was further back.
##   "blast"   an explosion beside the run at `at`: flash, fireball, smoke,
##             flying debris; leaves a fire.
##   "mast"    a lattice radio mast standing at `at` topples over toward
##             `fall_yaw` (degrees) and crashes.
##   "skybridge" (Skybridge, m09c) a glass security gate across the bridge
##             at `at`, Echo right behind it, and the `span` m of bridge
##             from the gate to the tower door. Fired at the gate: two Ward
##             troopers come out of the tower, walk her back in, the door
##             shuts, the charge goes and the span drops. Emits went(
##             "skybridge") at the gate, "skybridge_blast" when it blows and
##             "skybridge_down" once it has fallen (the mission's last
##             objective waits for that). The gate never opens.
##   "bridge_collapse" (Glass District) a bridge the route built with
##             "breaks" (local z, behind to ahead along -Z: route.gd turns
##             its m-along-the-roof into these) blows and falls `drop` m
##             into the river bed. It takes whatever stands on the deck
##             between the first and last break when it goes (deck pieces,
##             girders, railings, wrecks, marks), blows the piers inside,
##             and drops each span: the first hinges on its near pier and
##             the last on its far pier, so they end up as ramps down into
##             the bed; the ones between fall flat ("hinges": "both",
##             "near", "far" or "none" says which ends hinge). Anyone on it
##             falls with it. "on": "complete" fires it on that mission event instead of
##             the trigger; the charge goes when the radio has finished the
##             "cue" line (MissionLevel tells it what's on air; if the line
##             was over before it fired, it goes straight away), or
##             "blast_after" s after it fired, whichever is first. Emits
##             went("bridge_collapse") when it fires, "bridge_collapse_blast"
##             when it blows and "bridge_collapse_down" once it has landed.
## Fields: "trigger" [x, y, z], "radius", "yaw" (the run's heading, from the
## route), "on" (a mission event that fires it instead of the trigger), and
## the kind's own.

const FIRE_SHADER_PATH := "res://campaign/fire.gdshader"
## Ticks a falling beam takes to land (60 Hz).
const FALL_TICKS := 34
const FALL_HEIGHT := 11.0
## Ticks a mast takes to go over.
const MAST_TICKS := 150
## The skybridge scene (60 Hz ticks from reaching the gate), timed to the
## radio: the troopers come out while Echo talks, take her on Vell's
## "Take her across", and the bridge blows after her last line.
const SKY_DOOR_OPEN := 180
const SKY_WALK_OUT := 200
const SKY_GRAB := 612
const SKY_DRAG := 650
const SKY_DOOR_SHUT := 1060
const SKY_BLAST := 1140
const SKY_FALL_TICKS := 150
const SKY_DOWN := 1320
## A collapsing bridge: ticks from the blast for the spans to come down,
## the angle the middle spans tip by as they fall (radians), and the most
## a span sinks into the river bed when it lands.
const BRIDGE_FALL_TICKS := 84
const BRIDGE_TIP := 0.12
const BRIDGE_SINK := 0.6
## Ticks after the cue line ends before the charge goes.
const BRIDGE_CUE_DELAY := 12
const TROOPER_MODEL := "res://enemies/models/soldier.glb"
const ENEMY_BODY_PATH := "res://enemies/enemy_body.gd"
const ENEMY_POSES_PATH := "res://enemies/enemy_poses.gd"
const FIGURE_PATH := "res://art/characters/runner/runner_figure.gd"
## Where Echo stands behind the glass, and the troopers either side of her
## when they take her (local: -Z is on toward the tower).
const ECHO_SPOT := Vector3(0, 0, -1.1)
const GUARD_SPOTS := [Vector3(-0.75, 0, -1.7), Vector3(0.75, 0, -1.7)]

var kind := "debris"
var spec := {}
var trigger := Vector3.ZERO
var radius := 7.0
var fired := false
## Physics ticks since it fired.
var ticks := 0
## Emitted when it fires (MissionRun turns it into a mission event).
signal went(kind: String)

var _beam: Node3D
var _beam_body: StaticBody3D
var _rest := Transform3D.IDENTITY
var _start := Transform3D.IDENTITY
var _flash: OmniLight3D
var _fx: Node3D
var _mast: Node3D
var _fx_time := -1.0
var _landed := false
var _span: Node3D
var _door: Node3D
var _doorway: Node3D
var _echo: Node3D
var _guards: Array[Node3D] = []
var _poses: Script
## The bridge: ticks since it fired when the charge goes (-1 until set),
## whether the cue line has been on air, the spans [{nodes: [[node,
## local transform]], hinge: Vector3, len, mode}] and the blown piers.
var _blast_tick := -1
var _cue_on := false
var _cue_done := false
var _spans: Array = []
var _blown: Array[Node3D] = []
var _bridge_down := false


func setup(p: Dictionary) -> void:
	kind = String(p.set_piece)
	spec = p
	trigger = _vec(p.get("trigger", p.get("at", [0, 0, 0])))
	radius = float(p.get("radius", 7.0))
	position = _vec(p.get("at", [0, 0, 0]))
	rotation.y = deg_to_rad(float(p.get("yaw", 0.0)))
	match kind:
		"debris":
			_build_beam()
		"mast":
			_build_mast()
		"skybridge":
			_build_skybridge()
	reset()


## Back to before it fired (you went back to a checkpoint).
func reset() -> void:
	fired = false
	ticks = 0
	_landed = false
	_fx_time = -1.0
	if _beam != null:
		_beam.visible = false
		_beam.transform = _start
		_set_solid(false)
	if _mast != null:
		_mast.rotation = Vector3.ZERO
	if _span != null:
		_span.transform = Transform3D.IDENTITY
		_span.visible = true
		_door.position.x = 0.0
		_doorway.visible = false
		if _echo != null:
			_echo.transform = Transform3D(Basis.IDENTITY, ECHO_SPOT)
			_echo.visible = true
			_echo.set("walk_speed", 0.0)
		for i in _guards.size():
			_guards[i].visible = false
			_guards[i].transform = _guard_start(i)
	_reset_bridge()
	if _fx != null:
		_fx.queue_free()
		_fx = null
	if _flash != null:
		_flash.light_energy = 0.0


## One physics tick: fires when you reach the trigger, then plays out.
## `run` is the MissionRun (for the pursuer).
func tick(player_pos: Vector3, run: Node) -> void:
	if not fired:
		if not spec.has("on") and player_pos.distance_to(trigger) <= radius:
			_fire(run)
		return
	ticks += 1
	match kind:
		"debris":
			if _landed:
				return
			var t := clampf(float(ticks) / FALL_TICKS, 0.0, 1.0)
			# Falling under gravity: slow, then fast; one end hits first.
			var k := t * t
			_beam.transform = _start.interpolate_with(_rest, k)
			if t >= 1.0:
				_landed = true
				_beam.transform = _rest
				_set_solid(true)
				_burst(Vector3(0, 0.6, 0), 0.8, false)
				_sound("debris", Vector3.ZERO, 6.0)
				_sound("door_bang", Vector3.ZERO, 2.0)
		"mast":
			var t := clampf(float(ticks) / MAST_TICKS, 0.0, 1.0)
			_mast.rotation = Vector3(-deg_to_rad(86.0) * t * t * t, 0, 0)
			if ticks == MAST_TICKS:
				var tip := _mast.global_transform * Vector3(0, float(spec.get("height", 26.0)) * 0.7, 0)
				_burst(to_local(tip), 2.2, true)
				_sound("debris", to_local(tip), 8.0)
				_sound("door_bang", to_local(tip), 6.0)
		"skybridge":
			_skybridge_tick()
		"bridge_collapse":
			_bridge_tick()


## A mission event happened (MissionRun): fires it if it waits for that one.
func on_event(event_name: String, run: Node) -> void:
	if not fired and String(spec.get("on", "")) == event_name:
		_fire(run)


## True from firing until it has finished playing out (the results card
## waits for it).
func busy() -> bool:
	return fired and kind == "bridge_collapse" and not _bridge_down


## What the radio has on air now ("" for nothing). A bridge's charge goes
## once its cue line has been and gone. Timing only: what falls and when is
## still counted in physics ticks.
func hear(line: String) -> void:
	if _blast_tick >= 0 or not spec.has("cue"):
		return
	if line == String(spec.cue):
		_cue_on = true
	elif _cue_on:
		# (Heard before it fired, too: then it goes as soon as it fires.)
		_cue_on = false
		_cue_done = true
	if fired and _cue_done:
		_blast_tick = ticks + BRIDGE_CUE_DELAY


func _fire(run: Node) -> void:
	fired = true
	ticks = 0
	match kind:
		"skybridge", "bridge_collapse":
			pass
		"debris":
			_beam.visible = true
			_sound("whoosh", Vector3(0, 6, 0), 2.0)
		"host":
			var p: Node = run.get("pursuer") if run != null else null
			if p == null or not p.close_in(float(spec.get("gap", 9.0))):
				return
			var at: Vector3 = to_local((p as Node3D).global_position)
			_burst(at + Vector3(0, 0.5, 0), 0.9, false)
			_sound("door_bang", at, 6.0)
			_sound("debris", at, 4.0)
		"blast":
			_burst(Vector3(0, 1.0, 0), float(spec.get("size", 1.6)), true)
			_sound("door_bang", Vector3.ZERO, 8.0)
			_sound("debris", Vector3.ZERO, 6.0)
		"mast":
			_sound("debris", Vector3(0, 4, 0), 2.0)
	went.emit(kind)


func _set_solid(on: bool) -> void:
	if _beam_body == null:
		return
	for c in _beam_body.get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).disabled = not on


# ---------------------------------------------------------------- builds

## The beam (and, for "slide", the rubble it lands on), laid across the
## run. It starts high above, tipped, and hidden.
func _build_beam() -> void:
	var slide: bool = spec.get("as", "hurdle") == "slide"
	var width := float(spec.get("width", 12.0))
	_beam = Node3D.new()
	_beam.name = "Beam"
	add_child(_beam)
	_beam_body = StaticBody3D.new()
	_beam_body.collision_layer = 1
	_beam_body.collision_mask = 0
	_beam_body.set_meta("kind", "PARKOUR")
	_beam.add_child(_beam_body)
	var steel := _steel()
	# A rolled-steel I-beam: web and two flanges, glowing hot at the ends.
	var y := 1.35 if slide else 0.62
	var h := 0.5 if slide else 0.7
	_part(_beam_body, Vector3(0, y, 0), Vector3(width, h, 0.6), steel, true)
	_part(_beam_body, Vector3(0, y + h * 0.5 - 0.05, 0), Vector3(width, 0.1, 0.7), steel, false)
	_part(_beam_body, Vector3(0, y - h * 0.5 + 0.05, 0), Vector3(width, 0.1, 0.7), steel, false)
	var hot := StandardMaterial3D.new()
	hot.albedo_color = Color(0.3, 0.08, 0.03)
	hot.emission_enabled = true
	hot.emission = Color(1.0, 0.35, 0.08)
	hot.emission_energy_multiplier = 2.5
	for side: float in [-1.0, 1.0]:
		_part(_beam_body, Vector3(side * (width * 0.5 - 0.3), y, 0), Vector3(0.62, h + 0.02, 0.62), hot, false)
		_flames(_beam, Vector3(side * (width * 0.5 - 0.8), y + h * 0.5, 0), 1.3, 3)
	_flames(_beam, Vector3(1.2, y + h * 0.5, 0), 0.9, 2)
	if slide:
		# Rubble piles at the edges hold it up.
		var rubble := StandardMaterial3D.new()
		rubble.albedo_color = Color(0.36, 0.33, 0.3)
		for side: float in [-1.0, 1.0]:
			_part(_beam_body, Vector3(side * (width * 0.5 - 0.4), 0.55, 0), Vector3(0.9, 1.1, 1.2), rubble, true)
			_part(_beam_body, Vector3(side * (width * 0.5 - 1.1), 0.3, 0.3), Vector3(0.8, 0.6, 0.9), rubble, false)
	_rest = Transform3D.IDENTITY
	_start = Transform3D(Basis(Vector3.BACK, deg_to_rad(float(spec.get("tilt", 38.0)))) * Basis(Vector3.UP, 0.3), Vector3(0, FALL_HEIGHT, 1.5))
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.45, 0.15)
	light.omni_range = 7.0
	light.light_energy = 1.6
	light.position = Vector3(0, y + 1.0, 0)
	_beam.add_child(light)


## A lattice radio mast: four legs, cross braces every few meters, red
## aviation lights. Its base pivots at the origin; it falls along -Z.
func _build_mast() -> void:
	var height := float(spec.get("height", 26.0))
	var base := float(spec.get("base", 3.0))
	# Turned toward where it falls (relative to the run).
	var holder := Node3D.new()
	holder.rotation.y = deg_to_rad(float(spec.get("fall_yaw", 0.0)))
	add_child(holder)
	_mast = Node3D.new()
	_mast.name = "Mast"
	holder.add_child(_mast)
	var steel := _steel()
	steel.albedo_color = Color(0.32, 0.12, 0.08)
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.82, 0.8, 0.76)
	var segs := int(height / 3.0)
	for i in segs:
		var y0 := i * 3.0
		var w0 := lerpf(base, base * 0.25, float(i) / segs)
		var w1 := lerpf(base, base * 0.25, float(i + 1) / segs)
		var mat := white if i % 4 >= 2 else steel
		for cx: float in [-1.0, 1.0]:
			for cz: float in [-1.0, 1.0]:
				var a := Vector3(cx * w0 * 0.5, y0, cz * w0 * 0.5)
				var b := Vector3(cx * w1 * 0.5, y0 + 3.0, cz * w1 * 0.5)
				_strut(_mast, a, b, 0.14, mat)
		for side in 4:
			var ang := side * PI * 0.5
			var r := Basis(Vector3.UP, ang)
			_strut(_mast, r * Vector3(-w0 * 0.5, y0, w0 * 0.5), r * Vector3(w1 * 0.5, y0 + 3.0, w1 * 0.5), 0.07, steel)
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(1, 0.1, 0.05)
	red.emission_enabled = true
	red.emission = Color(1, 0.1, 0.05)
	red.emission_energy_multiplier = 5.0
	for y: float in [height * 0.5, height]:
		var lamp := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.3
		sm.height = 0.6
		lamp.mesh = sm
		lamp.material_override = red
		lamp.position = Vector3(0, y, 0)
		_mast.add_child(lamp)
	var light := OmniLight3D.new()
	light.light_color = Color(1, 0.15, 0.08)
	light.omni_range = 12.0
	light.light_energy = 2.0
	light.position = Vector3(0, height, 0)
	_mast.add_child(light)
	_flames(self, Vector3(0, 0.1, 0), 2.4, 4)


## The gate, Echo, her guards, the span to the tower and the tower door.
## The gate is solid all the way up (nothing gets past it); the rest is
## looks, except the span's deck, which drops.
func _build_skybridge() -> void:
	var span := float(spec.get("span", 22.0))
	var width := float(spec.get("width", 12.0))
	var steel := _steel()
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.62, 0.78, 0.82, 0.22)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	glass.metallic = 0.3
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	# The gate: a frame, a security-glass wall, a header, and above it an
	# invisible wall so it can't be climbed.
	var gate := StaticBody3D.new()
	gate.name = "Gate"
	gate.collision_mask = 0
	gate.set_meta("kind", "NEUTRAL")
	add_child(gate)
	# Glass and posts stand a hair inside the bottom rail, not flush with it.
	_part(gate, Vector3(0, 1.72, 0), Vector3(width - 0.4, 3.36, 0.12), glass, false)
	for x: float in [-width * 0.5 + 0.2, -1.6, 1.6, width * 0.5 - 0.2]:
		_part(gate, Vector3(x, 1.851, 0), Vector3(0.18, 3.698, 0.24), steel, false)
	_part(gate, Vector3(0, 3.7, 0), Vector3(width, 0.4, 0.3), steel, false)
	_part(gate, Vector3(0, 0.06, 0), Vector3(width, 0.12, 0.3), steel, false)
	var wall := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(width, 9.0, 0.3)
	wall.shape = wall_box
	wall.position = Vector3(0, 4.5, 0)
	gate.add_child(wall)
	var notice := Label3D.new()
	notice.text = "WARD SECURITY - NO ENTRY"
	notice.font_size = 64
	notice.pixel_size = 0.004
	notice.modulate = Color(0.95, 0.85, 0.3)
	notice.position = Vector3(0, 3.7, 0.17)
	add_child(notice)
	# The span from the gate to the tower: deck, girders, glass sides and
	# roof frames, all one piece so it falls together.
	_span = Node3D.new()
	_span.name = "Span"
	add_child(_span)
	var deck := StandardMaterial3D.new()
	deck.albedo_color = Color(0.42, 0.4, 0.37)
	deck.roughness = 0.9
	_part(_span, Vector3(0, -0.6, -span * 0.5 - 0.15), Vector3(width, 1.2, span - 0.3), deck, false)
	for side: float in [-1.0, 1.0]:
		_part(_span, Vector3(side * (width * 0.5 - 0.8), -1.8, -span * 0.5), Vector3(0.6, 1.2, span), steel, false)
		_part(_span, Vector3(side * (width * 0.5 - 0.1), 0.45, -span * 0.5), Vector3(0.2, 0.9, span), steel, false)
		_part(_span, Vector3(side * (width * 0.5 - 0.1), 2.05, -span * 0.5), Vector3(0.08, 2.3, span), glass, false)
	var d := 4.0
	while d < span:
		_part(_span, Vector3(0, 3.4, -d), Vector3(width - 0.4, 0.3, 0.3), steel, false)
		d += 8.0
	# The tower door in the facade at the far end: a dark doorway behind a
	# steel panel that slides aside.
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.02, 0.02, 0.025)
	dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_doorway = Node3D.new()
	add_child(_doorway)
	_part(_doorway, Vector3(0, 1.4, -span + 0.06), Vector3(2.4, 2.8, 0.04), dark, false)
	var frame := Node3D.new()
	add_child(frame)
	_part(frame, Vector3(-1.35, 1.5, -span + 0.12), Vector3(0.3, 3.0, 0.2), steel, false)
	_part(frame, Vector3(1.35, 1.5, -span + 0.12), Vector3(0.3, 3.0, 0.2), steel, false)
	_part(frame, Vector3(0, 3.05, -span + 0.12), Vector3(3.0, 0.3, 0.2), steel, false)
	_door = Node3D.new()
	_door.name = "Door"
	add_child(_door)
	var panel := _steel()
	panel.albedo_color = Color(0.3, 0.32, 0.3)
	_part(_door, Vector3(0, 1.4, -span + 0.1), Vector3(2.4, 2.8, 0.08), panel, false)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.25, 0.1)
	lamp.light_energy = 1.2
	lamp.omni_range = 5.0
	lamp.position = Vector3(0, 3.4, -span + 0.6)
	add_child(lamp)
	# Echo behind the glass, and the two troopers who come for her.
	var figure := load(FIGURE_PATH) as Script if ResourceLoader.exists(FIGURE_PATH) else null
	if figure != null and figure.can_instantiate():
		_echo = figure.new()
		_echo.name = "Echo"
		_echo.set("runner", "echo")
		_echo.set("pose_name", String(spec.get("pose", "idle")))
		add_child(_echo)
	var body_script := load(ENEMY_BODY_PATH) as Script if ResourceLoader.exists(ENEMY_BODY_PATH) else null
	_poses = load(ENEMY_POSES_PATH) as Script if ResourceLoader.exists(ENEMY_POSES_PATH) else null
	if body_script != null and body_script.can_instantiate() and _poses != null:
		for i in 2:
			var b: Node3D = body_script.new()
			b.name = "Guard%d" % i
			add_child(b)
			if not b.load_model(TROOPER_MODEL):
				b.queue_free()
				_guards.clear()
				break
			b.show_part("Shield", false)
			b.show_part("LongRifle", false)
			_guards.append(b)


## The guards wait just inside the tower door, facing out along the span.
func _guard_start(i: int) -> Transform3D:
	var span := float(spec.get("span", 22.0))
	return Transform3D(Basis(Vector3.UP, PI), Vector3(GUARD_SPOTS[i].x * 1.2, 0, -span - 0.6))


func _skybridge_tick() -> void:
	var span := float(spec.get("span", 22.0))
	var dt := 1.0 / 60.0
	var door_x := 0.0
	if ticks >= SKY_DOOR_OPEN and ticks < SKY_DOOR_SHUT:
		door_x = clampf(float(ticks - SKY_DOOR_OPEN) / 36.0, 0.0, 1.0)
	elif ticks >= SKY_DOOR_SHUT:
		door_x = 1.0 - clampf(float(ticks - SKY_DOOR_SHUT) / 36.0, 0.0, 1.0)
	_door.position.x = door_x * 2.5
	_doorway.visible = door_x > 0.0
	if ticks == SKY_DOOR_OPEN or ticks == SKY_DOOR_SHUT + 30:
		_sound("door_bang", Vector3(0, 1.5, -span), 3.0 if ticks == SKY_DOOR_OPEN else 6.0)
	# Out along the span to her, then back in with her between them.
	var out_k := clampf(float(ticks - SKY_WALK_OUT) / float(SKY_GRAB - SKY_WALK_OUT), 0.0, 1.0)
	var back_k := clampf(float(ticks - SKY_DRAG) / float(SKY_DOOR_SHUT - 20 - SKY_DRAG), 0.0, 1.0)
	var inside_z := -span - 1.2
	for i in _guards.size():
		var g := _guards[i]
		var spot: Vector3 = GUARD_SPOTS[i]
		var start := _guard_start(i).origin
		var pos: Vector3
		var facing := PI
		var speed := 0.0
		if ticks < SKY_WALK_OUT:
			pos = start
		elif ticks < SKY_GRAB:
			pos = start.lerp(spot, out_k)
			speed = start.distance_to(spot) / (float(SKY_GRAB - SKY_WALK_OUT) * dt)
		elif ticks < SKY_DRAG:
			pos = spot
		else:
			pos = spot.lerp(Vector3(spot.x * 0.7, 0, inside_z - 0.6), back_k)
			facing = 0.0
			speed = 0.0 if back_k >= 1.0 else spot.distance_to(Vector3(spot.x, 0, inside_z)) / (float(SKY_DOOR_SHUT - 20 - SKY_DRAG) * dt)
		g.visible = ticks >= SKY_DOOR_OPEN + 10 and pos.z > -span - 0.4
		g.transform = Transform3D(Basis(Vector3.UP, facing), pos)
		_pose_guard(g, speed, dt, ticks >= SKY_GRAB and ticks < SKY_DRAG + 30)
	if _echo != null:
		if ticks < SKY_GRAB:
			_echo.transform = Transform3D(Basis.IDENTITY, ECHO_SPOT)
		elif ticks < SKY_DRAG:
			# Spun round by the arms.
			var k := float(ticks - SKY_GRAB) / float(SKY_DRAG - SKY_GRAB)
			_echo.transform = Transform3D(Basis(Vector3.UP, PI * k), ECHO_SPOT)
		else:
			var pos := ECHO_SPOT.lerp(Vector3(0, 0, inside_z), back_k)
			_echo.transform = Transform3D(Basis(Vector3.UP, PI), pos)
			_echo.visible = pos.z > -span - 0.4
		_echo.set("walk_speed", 3.0 if ticks >= SKY_DRAG and back_k < 1.0 else 0.0)
	if ticks == SKY_BLAST:
		_burst(Vector3(0, 0.5, -span * 0.5), 2.6, true)
		_burst_extra(Vector3(0, -0.4, -1.2))
		_sound("door_bang", Vector3(0, 0, -span * 0.5), 10.0)
		_sound("debris", Vector3(0, 0, -span * 0.5), 8.0)
		went.emit("skybridge_blast")
	if ticks > SKY_BLAST:
		# Snapped at both ends, it drops away tipping toward the tower.
		var t := float(ticks - SKY_BLAST) * dt
		var k := clampf(float(ticks - SKY_BLAST) / SKY_FALL_TICKS, 0.0, 1.0)
		_span.transform = Transform3D(Basis(Vector3.RIGHT, -0.35 * k) * Basis(Vector3.FORWARD, 0.12 * k), Vector3(0, -4.9 * t * t, -0.8 * t))
		_span.visible = ticks < SKY_BLAST + SKY_FALL_TICKS
	if ticks == SKY_DOWN:
		went.emit("skybridge_down")


# ---------------------------------------------------------------- bridge

func _bridge_tick() -> void:
	var latest := int(float(spec.get("blast_after", 6.0)) * 60.0)
	if _blast_tick < 0 and ticks >= latest:
		_blast_tick = ticks
	if _blast_tick < 0 or ticks < _blast_tick:
		return
	var since := ticks - _blast_tick
	if since == 0:
		_bridge_blast()
	if _bridge_down:
		return
	var k := clampf(float(since) / BRIDGE_FALL_TICKS, 0.0, 1.0)
	var drop := float(spec.get("drop", 8.0))
	for span: Dictionary in _spans:
		var xf := _span_xf(span, k, drop)
		for pair: Array in span.nodes:
			var n: Node3D = pair[0]
			if is_instance_valid(n):
				n.global_transform = global_transform * xf * pair[1]
	if since == BRIDGE_FALL_TICKS:
		_bridge_down = true
		for span: Dictionary in _spans:
			# Where it hits the bed: the free end, or the middle of a flat one.
			var reach := float(span.len) * (0.5 if span.mode == "drop" else 1.0)
			var land: Vector3 = span.hinge + Vector3(0, -drop + 1.0, -reach * float(span.dir))
			_burst_at(land, 2.4)
			_sound("debris", land, 9.0)
		went.emit("bridge_collapse_down")


## Where a span is `k` (0..1) of the way down, as a transform of its nodes
## from where they stood (local to the set piece).
func _span_xf(span: Dictionary, k: float, drop: float) -> Transform3D:
	var hinge: Vector3 = span.hinge
	var length: float = span.len
	# Falling under gravity: slow, then fast.
	var g := k * k
	var fall := drop - 1.0
	if span.mode == "drop":
		# Both ends gone: it drops, tipping a little toward its far end.
		var tip := BRIDGE_TIP * g * float(span.dir)
		var down := (fall + BRIDGE_SINK) * g
		var center := hinge + Vector3(0, -0.5, -length * 0.5 * float(span.dir))
		var rot := Transform3D(Basis(Vector3.RIGHT, -tip), Vector3.ZERO)
		return Transform3D(Basis.IDENTITY, center + Vector3(0, -down, 0)) * rot * Transform3D(Basis.IDENTITY, -center)
	# Hinged at one end: the free end swings down onto the bed. `dir` is
	# +1 when the span runs on ahead of its hinge (-Z), -1 when it lies
	# behind it.
	var angle := asin(clampf((fall + BRIDGE_SINK) / length, 0.0, 1.0)) * g
	var pivot := hinge + Vector3(0, -1.0, 0)
	var basis := Basis(Vector3.RIGHT, -angle * float(span.dir))
	return Transform3D(Basis.IDENTITY, pivot) * Transform3D(basis, Vector3.ZERO) * Transform3D(Basis.IDENTITY, -pivot)


## The charge goes: picks up what stands on the deck, blows the piers
## between the end piers and sets each span falling.
func _bridge_blast() -> void:
	_spans.clear()
	_blown.clear()
	var breaks: Array = spec.get("breaks", [])
	if breaks.size() < 2:
		push_warning("SetPiece: a bridge_collapse needs two or more breaks")
		_bridge_down = true
		return
	var cuts: Array[float] = []
	for b: Variant in breaks:
		cuts.append(float(b))
	cuts.sort()
	cuts.reverse()  # behind first, then on ahead (local -Z)
	var drop := float(spec.get("drop", 8.0))
	var half := float(spec.get("width", 12.0)) * 0.5 + 1.0
	var count := cuts.size() - 1
	var hinges := String(spec.get("hinges", "both"))
	for i in count:
		var mode := "drop"
		var dir := 1.0
		var hinge := Vector3(0, 0, cuts[i])
		if i == 0 and hinges in ["both", "near"]:
			mode = "hinge"
		elif i == count - 1 and hinges in ["both", "far"]:
			mode = "hinge"
			dir = -1.0
			hinge = Vector3(0, 0, cuts[i + 1])
		_spans.append({"nodes": [], "hinge": hinge, "len": cuts[i] - cuts[i + 1], "mode": mode, "dir": dir})
	var parent := get_parent()
	if parent != null:
		for c: Node in parent.get_children():
			var n := c as Node3D
			if n == null or n == self or n is CharacterBody3D or n is RigidBody3D or n.name.begins_with("SetPiece"):
				continue
			var at := to_local(n.global_position)
			if absf(at.x) > half or at.y < -drop + 0.4 or at.y > 4.0:
				continue
			if at.z >= cuts[0] - 0.05 or at.z <= cuts[-1] + 0.05:
				continue
			if at.y < -2.5:
				# A pier: the ones between the end piers go.
				if at.z < cuts[0] - 1.5 and at.z > cuts[-1] + 1.5:
					_blown.append(n)
				continue
			for i in count:
				if at.z < cuts[i] and at.z >= cuts[i + 1]:
					_spans[i].nodes.append([n, global_transform.affine_inverse() * n.global_transform])
					break
	for n in _blown:
		n.visible = false
		_solid(n, false)
	# Charges at every break between the ends; the biggest under the middle.
	for i in range(1, cuts.size() - 1):
		_burst_at(Vector3(0, -1.0, cuts[i]), 2.6 if i == 1 else 1.8, i == 1)
		_sound("door_bang", Vector3(0, -1.0, cuts[i]), 10.0)
		_sound("debris", Vector3(0, -1.0, cuts[i]), 8.0)
	went.emit("bridge_collapse_blast")


func _reset_bridge() -> void:
	for span: Dictionary in _spans:
		for pair: Array in span.nodes:
			var n: Node3D = pair[0]
			if is_instance_valid(n):
				n.global_transform = global_transform * pair[1]
	for n in _blown:
		if is_instance_valid(n):
			n.visible = true
			_solid(n, true)
	_spans.clear()
	_blown.clear()
	_blast_tick = -1
	_cue_on = false
	_bridge_down = false
	for c in get_children():
		if c.has_meta("bridge_fx"):
			c.queue_free()


func _solid(n: Node, on: bool) -> void:
	for c in n.get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).set_deferred("disabled", not on)


## A burst that stays with the others (a bridge has several going at once).
func _burst_at(at: Vector3, size: float, fireball := false) -> void:
	var keep := _fx
	var keep_time := _fx_time
	_fx = null
	_burst(at, size, fireball)
	var mine := _fx
	if mine != null:
		mine.set_meta("bridge_fx", true)
	if keep != null or not fireball:
		_fx = keep
		_fx_time = keep_time
	elif mine != null:
		# Keep the fireball's flash and swell going.
		_fx = mine


## A second, smaller burst right at the gate: the charge on this side.
func _burst_extra(at: Vector3) -> void:
	var keep := _fx
	var keep_time := _fx_time
	_fx = null
	_burst(at, 1.2, false)
	var mine := _fx
	_fx = keep
	_fx_time = keep_time
	if mine != null:
		mine.name = "GateBurst"


func _pose_guard(g: Node3D, speed: float, dt: float, holding: bool) -> void:
	if not g.has_method("show_pose") or _poses == null:
		return
	g.step(speed, 1.5, dt)
	var lower: Dictionary = _poses.blend(_poses.stand(), _poses.legs(g.phase, speed / 4.0), clampf(speed, 0.0, 1.0))
	var upper: Dictionary = _poses.low_ready()
	g.show_pose(_poses.layer(lower, upper), dt)
	var chest: Vector3 = g.global_transform.affine_inverse() * g.bone_position("UpperChest") if g.is_inside_tree() else Vector3(0, 1.3, 0)
	var xf: Transform3D = _poses.rifle_xf(chest, Vector3.FORWARD, 0.0, 0.0, g.phase)
	g.hold("Rifle", xf)
	g.reach("Right", xf * Vector3(0, -0.035, 0.02), _poses.RIGHT_POLE)
	if not holding:
		g.reach("Left", xf * Vector3(0, -0.01, -0.3), _poses.LEFT_POLE)


# ---------------------------------------------------------------- looks

func _process(delta: float) -> void:
	if _fx == null or _fx_time < 0.0:
		return
	_fx_time += delta
	if _flash != null:
		_flash.light_energy = maxf(0.0, 9.0 * (1.0 - _fx_time / 0.6))
	var ball: Node3D = _fx.get_node_or_null("Ball")
	if ball != null:
		var s := clampf(_fx_time / 0.25, 0.0, 1.0)
		ball.scale = Vector3.ONE * lerpf(0.2, 1.0, s) * float(_fx.get_meta("size", 1.0)) * 2.2
		ball.visible = _fx_time < 0.7
		var m := ball.get_child(0) as MeshInstance3D
		if m != null:
			(m.material_override as StandardMaterial3D).albedo_color.a = clampf(1.0 - _fx_time / 0.7, 0.0, 1.0)


## Dust (and, for an explosion, a fireball, flash and flying chunks) at a
## local point.
func _burst(at: Vector3, size: float, fireball: bool) -> void:
	if _fx != null:
		_fx.queue_free()
	_fx = Node3D.new()
	_fx.name = "Burst"
	_fx.position = at
	_fx.set_meta("size", size)
	add_child(_fx)
	_fx_time = 0.0
	if DisplayServer.get_name() == "headless":
		return
	var dust := CPUParticles3D.new()
	dust.one_shot = true
	dust.explosiveness = 0.9
	dust.amount = int(24 * size)
	dust.lifetime = 2.2
	dust.direction = Vector3.UP
	dust.spread = 80.0
	dust.initial_velocity_min = 2.0 * size
	dust.initial_velocity_max = 5.0 * size
	dust.gravity = Vector3(0, -1.5, 0)
	dust.damping_min = 2.0
	dust.damping_max = 3.0
	dust.scale_amount_min = 0.8 * size
	dust.scale_amount_max = 1.8 * size
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	dust.mesh = quad
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.45, 0.4, 0.36, 0.55) if not fireball else Color(0.18, 0.16, 0.15, 0.7)
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dm.vertex_color_use_as_albedo = true
	dust.material_override = dm
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.9))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	dust.color_ramp = fade
	_fx.add_child(dust)
	dust.emitting = true
	var chunks := CPUParticles3D.new()
	chunks.one_shot = true
	chunks.explosiveness = 1.0
	chunks.amount = int(14 * size)
	chunks.lifetime = 1.6
	chunks.direction = Vector3.UP
	chunks.spread = 60.0
	chunks.initial_velocity_min = 4.0 * size
	chunks.initial_velocity_max = 9.0 * size
	chunks.gravity = Vector3(0, -14, 0)
	chunks.angular_velocity_min = -360
	chunks.angular_velocity_max = 360
	var cm := BoxMesh.new()
	cm.size = Vector3(0.18, 0.12, 0.22) * size
	chunks.mesh = cm
	var cmat := _steel()
	cmat.albedo_color = Color(0.3, 0.27, 0.25)
	chunks.material_override = cmat
	_fx.add_child(chunks)
	chunks.emitting = true
	if fireball:
		var ball := Node3D.new()
		ball.name = "Ball"
		_fx.add_child(ball)
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.5
		sm.height = 1.0
		mi.mesh = sm
		var fm := StandardMaterial3D.new()
		fm.albedo_color = Color(1.0, 0.55, 0.15, 1.0)
		fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fm.emission_enabled = true
		fm.emission = Color(1.0, 0.45, 0.1)
		fm.emission_energy_multiplier = 3.0
		mi.material_override = fm
		ball.add_child(mi)
		if _flash == null:
			_flash = OmniLight3D.new()
			_flash.light_color = Color(1.0, 0.55, 0.2)
			_flash.omni_range = 16.0 * size
			add_child(_flash)
		_flash.position = at + Vector3(0, 1.0, 0)
		_flash.light_energy = 9.0
		# It keeps burning.
		_flames(_fx, Vector3(0, -at.y + 0.05 if at.y < 2.0 else 0.0, 0), 1.4 * size, 4)


func _flames(parent: Node3D, at: Vector3, height: float, count: int) -> void:
	var shader: Shader = load(FIRE_SHADER_PATH) if ResourceLoader.exists(FIRE_SHADER_PATH) else null
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(spec.get("at", [0, 0, 0])) + count
	for i in count:
		var flame := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(1, 1)
		quad.center_offset = Vector3(0, 0.5, 0)
		flame.mesh = quad
		var h := height * rng.randf_range(0.6, 1.2)
		flame.scale = Vector3(h * rng.randf_range(0.5, 0.75), h, 1)
		flame.position = at + Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.4, 0.4))
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if shader != null:
			var m := ShaderMaterial.new()
			m.shader = shader
			m.set_shader_parameter("seed", rng.randf())
			m.set_shader_parameter("speed", rng.randf_range(1.3, 2.0))
			flame.material_override = m
		flame.add_to_group("mission_fire")
		parent.add_child(flame)


func _steel() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.26, 0.2, 0.17)
	m.roughness = 0.7
	m.metallic = 0.4
	return m


func _part(parent: Node3D, center: Vector3, size: Vector3, mat: Material, solid: bool) -> void:
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = mat
	mesh.position = center
	parent.add_child(mesh)
	if solid:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		shape.position = center
		parent.add_child(shape)


func _strut(parent: Node3D, a: Vector3, b: Vector3, thick: float, mat: Material) -> void:
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(thick, a.distance_to(b), thick)
	mesh.mesh = bm
	mesh.material_override = mat
	var up := (b - a).normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	mesh.transform = Transform3D(Basis(side, up, side.cross(up)).orthonormalized(), (a + b) * 0.5)
	parent.add_child(mesh)


func _sound(sound_name: String, at: Vector3, volume_db: float) -> void:
	var audio := get_node_or_null("/root/GameAudio")
	if audio != null and audio.has_method("play_at") and is_inside_tree():
		audio.play_at(sound_name, to_global(at), volume_db)


static func _vec(a: Variant) -> Vector3:
	if a is Array and a.size() >= 3:
		return Vector3(a[0], a[1], a[2])
	return Vector3.ZERO
