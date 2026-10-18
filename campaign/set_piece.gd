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
## Fields: "trigger" [x, y, z], "radius", "yaw" (the run's heading, from the
## route), and the kind's own.

const FIRE_SHADER_PATH := "res://campaign/fire.gdshader"
## Ticks a falling beam takes to land (60 Hz).
const FALL_TICKS := 34
const FALL_HEIGHT := 11.0
## Ticks a mast takes to go over.
const MAST_TICKS := 150

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
	if _fx != null:
		_fx.queue_free()
		_fx = null
	if _flash != null:
		_flash.light_energy = 0.0


## One physics tick: fires when you reach the trigger, then plays out.
## `run` is the MissionRun (for the pursuer).
func tick(player_pos: Vector3, run: Node) -> void:
	if not fired:
		if player_pos.distance_to(trigger) <= radius:
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


func _fire(run: Node) -> void:
	fired = true
	ticks = 0
	match kind:
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
