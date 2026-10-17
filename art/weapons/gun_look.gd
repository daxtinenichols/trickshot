class_name GunLook
extends Node3D
## The art look of the player's gun: the scrap pistol model in first person
## and in the runner's right hand, plus everything a shot looks and sounds
## like (muzzle flash, light, smoke, slide blowback, ejected casings, tracer,
## sparks, dust, bullet holes, layered gunshot audio).
##
## Reads the Pistol only through its public hooks (view_model, the `shot`
## signal, ammo, muzzle_transform) and turns its builtin test visuals off
## while attached; they come back when this is removed (F9 graybox look).
## Nothing here feeds back into gameplay.

const MODEL := preload("res://art/weapons/scrap_pistol.glb")
const TOON_SHADER := preload("res://art/shaders/toon.gdshader")
const FLASH_SHADER := preload("res://art/shaders/muzzle_flash.gdshader")
## By path, not class_name, so this works before the editor registers it.
const Audio := preload("res://art/fx/gun_audio.gd")

## The gun in the runner's right hand, relative to the hand bone (its +Y
## runs along the fingers, -X out of the back of the hand): barrel along the
## hand, top of the gun on the thumb side, grip in the palm.
const HAND_GRIP := Transform3D(Basis(Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(0, -1, 0)), Vector3(-0.035, 0.12, -0.01))
## How far the slide travels back when it cycles, and how long the flash lasts.
const SLIDE_TRAVEL := 0.03
const FLASH_TIME := 0.05
const TRACER_SPEED := 600.0
const TRACER_LENGTH := 7.0
const MAX_HOLES := 48
const MAX_CASINGS := 24
## Where casings leave the gun (the ejection port), in view_model space.
const PORT_LOCAL := Vector3(0.012, 0.05, -0.005)

var pistol: Pistol
var body: RunnerBody

var fp_model: Node3D
var held_model: Node3D
var _slides: Array[Node3D] = []
var _slide_back := 0.0
var _flashes: Array[Node3D] = []
var _flash_mats: Array[ShaderMaterial] = []
var _flash_life := 0.0
var _light: OmniLight3D
var _shot_players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _shot_sounds: Array[AudioStreamWAV] = []
var _casing_sounds: Array[AudioStreamWAV] = []
var _impact_sounds: Array[AudioStreamWAV] = []
var _tracers: Array = []  # [MeshInstance3D, from, to, travelled]
var _casings: Array = []  # [MeshInstance3D, velocity, spin axis, age, floor y, bounced]
var _holes: Array[Decal] = []
var _rng := RandomNumberGenerator.new()
var _toon: ShaderMaterial
var _tracer_mat: StandardMaterial3D
var _brass: StandardMaterial3D
var _hole_tex: ImageTexture
var _dust_mat: StandardMaterial3D
var _spark_mat: StandardMaterial3D
var _chip_mat: StandardMaterial3D


func setup(p: Pistol, runner: RunnerBody = null) -> void:
	pistol = p
	body = runner
	_rng.seed = 4242
	top_level = true
	_build_materials()
	_build_sounds()
	# First person: on the pistol's view layer, moved by its aim/recoil.
	fp_model = _instance_gun(Pistol.VIEW_LAYER)
	pistol.view_model.add_child(fp_model)
	_add_flash(fp_model, Pistol.VIEW_LAYER)
	# Third person: in the runner's hand, on the body's layer.
	if body:
		var hand := BoneAttachment3D.new()
		hand.name = "GunHand"
		hand.bone_name = "RightHand"
		body.skeleton.add_child(hand)
		held_model = _instance_gun(RunnerBody.LAYER)
		held_model.transform = HAND_GRIP
		hand.add_child(held_model)
		_add_flash(held_model, RunnerBody.LAYER)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.72, 0.38)
	_light.omni_range = 4.5
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	add_child(_light)
	pistol.builtin_visuals = false
	pistol.shot.connect(_on_shot)
	pistol.reloaded.connect(_on_reloaded)


func _exit_tree() -> void:
	if is_instance_valid(pistol):
		pistol.builtin_visuals = true
		if pistol.shot.is_connected(_on_shot):
			pistol.shot.disconnect(_on_shot)
			pistol.reloaded.disconnect(_on_reloaded)
	if is_instance_valid(fp_model):
		fp_model.queue_free()
	if is_instance_valid(held_model):
		held_model.get_parent().queue_free()


# ---------------------------------------------------------------- building

func _build_materials() -> void:
	_toon = ShaderMaterial.new()
	_toon.shader = TOON_SHADER
	_toon.set_shader_parameter("base_color", Color.WHITE)
	_toon.set_shader_parameter("use_vertex_color", true)
	_toon.set_shader_parameter("rim_strength", 0.6)
	_tracer_mat = StandardMaterial3D.new()
	_tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_tracer_mat.albedo_color = Color(1.0, 0.8, 0.45)
	_tracer_mat.vertex_color_use_as_albedo = true
	_brass = StandardMaterial3D.new()
	_brass.albedo_color = Color(0.85, 0.62, 0.28)
	_brass.metallic = 0.8
	_brass.roughness = 0.35
	_spark_mat = StandardMaterial3D.new()
	_spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_spark_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_spark_mat.vertex_color_use_as_albedo = true
	_chip_mat = StandardMaterial3D.new()
	_chip_mat.albedo_color = Color(0.32, 0.29, 0.25)
	_chip_mat.vertex_color_use_as_albedo = true
	_dust_mat = StandardMaterial3D.new()
	_dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dust_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_dust_mat.vertex_color_use_as_albedo = true
	_dust_mat.albedo_texture = _puff_texture()
	_hole_tex = _hole_texture()


func _build_sounds() -> void:
	for i in 4:
		_shot_sounds.append(Audio.gunshot(i))
	for i in 3:
		_casing_sounds.append(Audio.casing(i))
		_impact_sounds.append(Audio.impact(i))
	for i in 3:
		var a := AudioStreamPlayer.new()
		a.volume_db = -3.0
		add_child(a)
		_shot_players.append(a)


func _instance_gun(layer: int) -> Node3D:
	var gun: Node3D = MODEL.instantiate()
	for mi: MeshInstance3D in gun.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = _toon
		mi.layers = layer
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if layer == Pistol.VIEW_LAYER else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if mi.name.begins_with("Slide"):
			_slides.append(mi)
			mi.set_meta("rest_z", mi.position.z)
	return gun


## A star (down the barrel) and two crossed petals (from the side) at the
## muzzle. Hidden until a shot.
func _add_flash(gun: Node3D, layer: int) -> void:
	var root := Node3D.new()
	root.position = Pistol.MUZZLE_LOCAL
	root.visible = false
	gun.add_child(root)
	_flashes.append(root)
	if _flash_mats.is_empty():
		for shape in 2:
			var m := ShaderMaterial.new()
			m.shader = FLASH_SHADER
			m.set_shader_parameter("shape", shape)
			_flash_mats.append(m)
	var star := MeshInstance3D.new()
	var sq := QuadMesh.new()
	sq.size = Vector2(0.15, 0.15)
	star.mesh = sq
	star.material_override = _flash_mats[0]
	star.name = "Star"
	root.add_child(star)
	for i in 2:
		var petal := MeshInstance3D.new()
		var pq := QuadMesh.new()
		pq.size = Vector2(0.11, 0.24)
		petal.mesh = pq
		petal.material_override = _flash_mats[1]
		# Quad's -Y (UV v = 1) along the barrel (-Z), the near end at the muzzle.
		petal.transform = Transform3D(Basis(Vector3.BACK, PI * 0.5 * i) * Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, -0.12))
		root.add_child(petal)
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		mi.layers = layer
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _make_smoke() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 6
	p.lifetime = 0.9
	p.explosiveness = 0.9
	p.local_coords = false
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.09)
	q.material = _dust_mat
	p.mesh = q
	p.direction = Vector3(0, 0, -1)
	p.spread = 25.0
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 1.2
	p.gravity = Vector3(0, 0.35, 0)
	p.damping_min = 1.5
	p.damping_max = 2.5
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.4
	p.scale_amount_curve = _curve([Vector2(0, 0.6), Vector2(1, 2.4)])
	p.color_ramp = _ramp(Color(0.86, 0.82, 0.76, 0.5), Color(0.8, 0.76, 0.7, 0.0))
	return p


# ---------------------------------------------------------------- shots

func _on_shot(muzzle: Vector3, end: Vector3, result: Dictionary) -> void:
	_flash_life = 1.0
	_light.light_energy = 6.0
	_light.global_position = muzzle
	var seed := _rng.randf() * 100.0
	for m in _flash_mats:
		m.set_shader_parameter("seed", seed)
	var roll := _rng.randf() * TAU
	for f in _flashes:
		f.visible = true
		f.rotation.z = roll
		f.scale = Vector3.ONE * _rng.randf_range(0.85, 1.15)
	_slide_back = 1.0
	# A fresh puff per shot (restarting one emitter flashes old particles).
	var smoke := _make_smoke()
	add_child(smoke)
	smoke.global_transform = pistol.muzzle_transform()
	smoke.emitting = true
	smoke.finished.connect(smoke.queue_free)
	_play_shot()
	_spawn_tracer(muzzle, end)
	_eject_casing()
	if not result.is_empty():
		_impact(result)


func _on_reloaded() -> void:
	_slide_back = 1.0  # released from lock: it slams home


func _play_shot() -> void:
	var a := _shot_players[_next_player]
	_next_player = (_next_player + 1) % _shot_players.size()
	a.stream = _shot_sounds[_rng.randi() % _shot_sounds.size()]
	# Slow motion drops the pitch: shots boom in bullet time.
	a.pitch_scale = _rng.randf_range(0.95, 1.05) * clampf(Engine.time_scale, 0.45, 1.0)
	a.play()


func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	if from.distance_to(to) < 0.5:
		return
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.022, 0.022, 1.0)
	m.mesh = box
	m.material_override = _tracer_mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	m.visible = false
	_tracers.append([m, from, to, 0.0])


func _eject_casing() -> void:
	if _casings.size() >= MAX_CASINGS:
		var old: Array = _casings.pop_front()
		old[0].queue_free()
	var vm := pistol.view_model.global_transform
	var cam := pistol.camera.global_transform.basis if pistol.camera else vm.basis
	var m := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.0045
	c.bottom_radius = 0.0045
	c.height = 0.019
	c.radial_segments = 8
	c.rings = 1
	m.mesh = c
	m.material_override = _brass
	add_child(m)
	m.global_transform = Transform3D(cam * Basis(Vector3.BACK, PI * 0.5), vm * PORT_LOCAL)
	var vel := cam.x * _rng.randf_range(1.6, 2.6) + cam.y * _rng.randf_range(1.4, 2.4) + cam.z * 0.4
	if pistol.player:
		vel += pistol.player.velocity
	var floor_y := pistol.player.global_position.y if pistol.player and pistol.player.is_on_floor() else -INF
	var axis := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized()
	_casings.append([m, vel, axis, 0.0, floor_y, false])


func _impact(result: Dictionary) -> void:
	var pos: Vector3 = result.position
	var n: Vector3 = result.normal
	var collider: Object = result.get("collider")
	var is_target := collider != null and (collider.has_meta("target") or collider.has_meta("zone"))
	_burst(pos, n, 14, 0.22, Vector2(4.0, 9.0), _spark_mat, Vector3(0.012, 0.09, 0.012), Color(1.0, 0.8, 0.4), Color(1.0, 0.35, 0.1), true)
	if is_target:
		return
	_burst(pos, n, 7, 0.7, Vector2(0.6, 1.6), _dust_mat, Vector3(0.22, 0.22, 0), Color(0.80, 0.72, 0.60, 0.8), Color(0.80, 0.72, 0.60, 0.0), false)
	_burst(pos, n, 6, 0.8, Vector2(1.5, 3.5), _chip_mat, Vector3(0.02, 0.02, 0.02), Color(0.4, 0.37, 0.33), Color(0.4, 0.37, 0.33), false)
	if collider is StaticBody3D:
		_bullet_hole(pos, n)
	var s := AudioStreamPlayer3D.new()
	s.stream = _impact_sounds[_rng.randi() % _impact_sounds.size()]
	s.unit_size = 4.0
	s.volume_db = -4.0
	s.pitch_scale = _rng.randf_range(0.9, 1.1)
	add_child(s)
	s.global_position = pos
	s.play()
	s.finished.connect(s.queue_free)


func _burst(pos: Vector3, n: Vector3, amount: int, life: float, speed: Vector2, mat: Material,
		size: Vector3, from: Color, to: Color, stretch: bool) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 1.0
	p.local_coords = false
	p.randomness = 0.5
	if size.z == 0.0:
		var q := QuadMesh.new()
		q.size = Vector2(size.x, size.y)
		q.material = mat
		p.mesh = q
		p.scale_amount_curve = _curve([Vector2(0, 0.5), Vector2(1, 2.2)])
		p.damping_min = 3.0
		p.damping_max = 5.0
		p.gravity = Vector3(0, 0.4, 0)
	else:
		var b := BoxMesh.new()
		b.size = size
		b.material = mat
		p.mesh = b
		p.gravity = Vector3(0, -12.0, 0)
	p.particle_flag_align_y = stretch
	p.direction = Vector3.UP
	p.spread = 55.0
	p.initial_velocity_min = speed.x
	p.initial_velocity_max = speed.y
	p.color_ramp = _ramp(from, to)
	add_child(p)
	# Emit along the surface normal.
	var up := n if n.length() > 0.5 else Vector3.UP
	var side := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	p.global_transform = Transform3D(Basis(side, up, side.cross(up)).orthonormalized(), pos + up * 0.02)
	p.emitting = true
	p.finished.connect(p.queue_free)


func _bullet_hole(pos: Vector3, n: Vector3) -> void:
	if _holes.size() >= MAX_HOLES:
		var old: Decal = _holes.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var d := Decal.new()
	d.size = Vector3(0.16, 0.08, 0.16)
	d.texture_albedo = _hole_tex
	d.albedo_mix = 1.0
	d.upper_fade = 0.0
	d.lower_fade = 0.0
	add_child(d)
	# Decals project along their -Y: point it into the surface.
	var up := n.normalized()
	var side := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	var b := Basis(side, up, side.cross(up)).orthonormalized() * Basis(Vector3.UP, _rng.randf() * TAU)
	d.global_transform = Transform3D(b, pos)
	d.scale = Vector3.ONE * _rng.randf_range(0.8, 1.2)
	_holes.append(d)


# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	if pistol == null:
		return
	# Flash: one or two frames, shrinking and cooling.
	if _flash_life > 0.0:
		_flash_life = maxf(_flash_life - delta / FLASH_TIME, 0.0)
		for m in _flash_mats:
			m.set_shader_parameter("life", _flash_life)
		if _flash_life <= 0.0:
			for f in _flashes:
				f.visible = false
	_light.light_energy = move_toward(_light.light_energy, 0.0, delta * 110.0)
	# Slide: blown back by the shot, springs home; locks back on empty.
	_slide_back = maxf(_slide_back - delta * 22.0, 0.0)
	var back := 1.0 if pistol.ammo == 0 else _slide_back
	for s in _slides:
		if is_instance_valid(s):
			s.position.z = s.get_meta("rest_z") + SLIDE_TRAVEL * smoothstep(0.0, 1.0, back)
	_update_tracers(delta)
	_update_casings(delta)


func _update_tracers(delta: float) -> void:
	for i in range(_tracers.size() - 1, -1, -1):
		var t: Array = _tracers[i]
		var m: MeshInstance3D = t[0]
		var from: Vector3 = t[1]
		var to: Vector3 = t[2]
		var total := from.distance_to(to)
		t[3] += TRACER_SPEED * delta
		var head := minf(t[3], total)
		var tail := maxf(t[3] - TRACER_LENGTH, 0.0)
		if tail >= total:
			m.queue_free()
			_tracers.remove_at(i)
			continue
		var dir := (to - from) / total
		var a := from + dir * tail
		var b := from + dir * head
		var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
		m.global_transform = Transform3D(Basis.looking_at(dir, up).scaled(Vector3(1, 1, maxf(a.distance_to(b), 0.01))), (a + b) * 0.5)
		m.visible = true


func _update_casings(delta: float) -> void:
	for i in range(_casings.size() - 1, -1, -1):
		var c: Array = _casings[i]
		var m: MeshInstance3D = c[0]
		c[3] += delta
		if c[3] > 3.0:
			m.queue_free()
			_casings.remove_at(i)
			continue
		var vel: Vector3 = c[1]
		if vel == Vector3.ZERO:
			continue
		vel.y -= 9.8 * delta
		var p := m.global_position + vel * delta
		m.rotate(c[2], 18.0 * delta)
		if p.y < c[4] + 0.005:
			p.y = c[4] + 0.005
			_tink(p)
			if c[5]:
				vel = Vector3.ZERO
			else:
				vel = Vector3(vel.x * 0.4, -vel.y * 0.3, vel.z * 0.4)
				c[5] = true
		c[1] = vel
		m.global_position = p


func _tink(pos: Vector3) -> void:
	var s := AudioStreamPlayer3D.new()
	s.stream = _casing_sounds[_rng.randi() % _casing_sounds.size()]
	s.unit_size = 2.0
	s.volume_db = -10.0
	s.pitch_scale = _rng.randf_range(0.92, 1.08)
	add_child(s)
	s.global_position = pos
	s.play()
	s.finished.connect(s.queue_free)


# ---------------------------------------------------------------- textures

static func _curve(points: Array) -> Curve:
	var c := Curve.new()
	c.max_value = 3.0
	for p: Vector2 in points:
		c.add_point(p)
	return c


static func _ramp(a: Color, b: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, a)
	g.set_color(1, b)
	return g


## A hard-edged, two-tone dust puff (cel style, not a soft blur).
static func _puff_texture() -> ImageTexture:
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var p := Vector2(x + 0.5, y + 0.5) / s - Vector2(0.5, 0.5)
			var a := atan2(p.y, p.x)
			var r := p.length() / (0.42 + 0.05 * sin(a * 5.0) + 0.03 * sin(a * 9.0 + 1.0))
			var c := Color(1, 1, 1, 0)
			if r < 1.0:
				var shade := 1.0 if p.y < 0.08 - r * 0.1 else 0.82
				c = Color(shade, shade, shade, clampf((1.0 - r) * 12.0, 0.0, 1.0))
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


## Bullet hole: dark center, a chipped lighter ring and short cracks.
static func _hole_texture() -> ImageTexture:
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var cracks: Array[float] = []
	for i in 5:
		cracks.append(rng.randf() * TAU)
	for y in s:
		for x in s:
			var p := Vector2(x + 0.5, y + 0.5) / s - Vector2(0.5, 0.5)
			var r := p.length()
			var a := atan2(p.y, p.x)
			var c := Color(0, 0, 0, 0)
			var ring := 0.2 + 0.03 * sin(a * 7.0)
			if r < 0.09:
				c = Color(0.05, 0.045, 0.04, 1.0)
			elif r < ring:
				c = Color(0.25, 0.22, 0.19, 0.95)
			elif r < 0.46:
				for ca in cracks:
					var d := absf(wrapf(a - ca, -PI, PI)) * r
					if d < 0.012 * (1.0 - r * 1.8):
						c = Color(0.12, 0.11, 0.1, 0.9)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)
