extends "res://campaign/set_piece.gd"
## The end of Signal Out (Stage 7): the Host follows Echo into the Silt.
##
## A steel girder lies across the Silt's channel from bank to bank, `span` m,
## half sunk in the dust, its two halves resting on a wreck in the middle.
## A pack of Hollows lies still in the dust beside it. The girder sags under
## Echo but holds. Once she is over (the trigger, on the far bank) the set
## piece takes the Host off the chase (Pursuer.scripted): he runs on along
## the girder, the far half tears off the bank under him and he goes into
## the dust. The Hollows rise and close over him while Echo's camera drone
## films it (a live feed in the corner of the screen, so it's seen wherever
## she looks); his mic squeals and cuts.
##
## Events (MissionRun makes each "set_piece:<name>"): "silt_girder" when she
## steps onto the girder (the Host's last line), "silt_fall" when she's over,
## "silt_break" when it gives under him, "silt_down" once the dust has him
## (the mission's last objective waits for that).
##
## Local frame: the girder starts at the origin on the near bank and runs
## toward -Z; x across. "channel" [x0, z0, x1, z1] (world, the same as the
## mission's "floor_cut") is the stretch of riverbed the level shows: dust
## over it and concrete edges along both banks.
##
## Loaded by path from MissionBuilder (no class_name).

const SoundBank := preload("res://audio/sound_bank.gd")
const MUTANT_MODEL := "res://enemies/models/mutant.glb"
const DRONE_MODEL := "res://enemies/models/drone.glb"

## The dust's surface under the girder's top (at 0, level with the banks'
## embankments, 1 m over the street): just under street level.
const DUST_Y := -1.4
## The girder's walking surface: wide enough to sprint, not to wander.
const DECK_WIDTH := 2.0
const DECK_THICK := 0.3
## How far the middle sags with Echo on it, and the gap over the wreck it
## sags onto.
const SAG := 0.22
## How far past the middle (along the far half) the Host gets before it goes.
const BREAK_PAST_MIDDLE := 8.0
## His run along the girder, m/s, and the fall.
const HOST_SPEED := 10.5
const GRAVITY := 18.0
## Ticks (60 Hz) from the break: the far half swings down, the Hollows rise,
## close in and pull him under, the mic goes.
const SWING_TICKS := 22
const RISE_AT := 18
const REACH_AT := 70
const SINK_FROM := 40
const SINK_TICKS := 150
const GONE_AT := 196
const SQUEAL_AT := 140
const CUT_AT := 214
const DOWN_AT := 240
## How far the far half tips when it goes (its bank end ends up under).
const SWING_DEG := 7.0
## Where the Hollows lie, local (x, z), and which way they face (degrees).
const HOLLOWS := [[-4.2, -38.0, 30.0], [3.6, -44.0, -60.0], [-6.5, -50.0, 120.0], [5.8, -53.0, 200.0],
	[-2.8, -58.0, 260.0], [7.2, -40.0, 80.0]]

var _length := 64.0
var _west: Node3D
var _east: Node3D
var _east_body: StaticBody3D
var _hollows: Array[Node3D] = []
var _hollow_bodies: Array[Node3D] = []
var _drone: Node3D
var _feed: CanvasLayer
var _feed_cam: Camera3D
var _feed_time := -1.0
var _pursuer: Node3D
var _on_girder := false
var _broken := false
var _break_tick := -1
var _down := false
## The Host while the set piece has him: local position, velocity.
var _host := Vector3.ZERO
var _host_vel := Vector3.ZERO
var _landed_at := Vector3.ZERO
var _squeal: AudioStreamPlayer


func setup(p: Dictionary) -> void:
	_length = float(p.get("span", 64.0))
	super.setup(p)
	kind = "silt_fall"
	_build()
	reset()


func reset() -> void:
	super.reset()
	_on_girder = false
	_broken = false
	_break_tick = -1
	_down = false
	_feed_time = -1.0
	if _pursuer != null and is_instance_valid(_pursuer):
		_pursuer.set("scripted", false)
	_pursuer = null
	if _west == null:
		return
	_west.transform = Transform3D.IDENTITY
	_east.transform = Transform3D(Basis.IDENTITY, Vector3(0, 0, -_length * 0.5))
	_set_east_solid(true)
	for i in _hollows.size():
		_lie(i)
	if _feed != null:
		_feed.visible = false
	if _squeal != null:
		_squeal.stop()


func tick(player_pos: Vector3, run: Node) -> void:
	var local := to_local(player_pos)
	if not _on_girder and local.z < -0.5 and local.z > -_length and absf(local.x) < DECK_WIDTH and local.y > -0.6:
		_on_girder = true
		went.emit("silt_girder")
	if not _broken:
		_sag(local)
	if not fired:
		var over := local.z < -_length - 1.0 and local.z > -_length - 30.0 and absf(local.x) < 12.0 and absf(local.y) < 4.0
		if player_pos.distance_to(trigger) <= radius or over:
			_fire(run)
		return
	ticks += 1
	_host_tick()
	if _broken:
		_after_break()


func _fire(run: Node) -> void:
	fired = true
	ticks = 0
	_pursuer = run.get("pursuer") if run != null else null
	if _pursuer != null:
		_pursuer.set("scripted", true)
		_host = to_local(_pursuer.global_position)
		_host_vel = Vector3.ZERO
	_show_feed(true)
	went.emit("silt_fall")


# ---------------------------------------------------------------- the Host

## Runs him on along the girder until he's well onto the far half, then the
## fall: forward and down into the dust, where he sinks.
func _host_tick() -> void:
	var dt := 1.0 / 60.0
	if not _broken:
		var break_z := -_length * 0.5 - BREAK_PAST_MIDDLE
		var target := Vector3(0.0, _deck_y(_host.z), minf(_host.z, 0.0) - HOST_SPEED * dt)
		var before := _host
		_host = _host.move_toward(target, HOST_SPEED * dt)
		_host.y = _deck_y(_host.z) if _host.z < 0.0 else _host.y
		_host_vel = (_host - before) / dt
		if _host.z <= break_z or ticks > 60 * 8:
			_break()
	else:
		var k := ticks - _break_tick
		if _host.y > DUST_Y + 0.05:
			_host_vel.y -= GRAVITY * dt
			_host += _host_vel * dt
			if _host.y <= DUST_Y:
				_host.y = DUST_Y
				_landed_at = _host
				_host_vel = Vector3.ZERO
				_burst(_host + Vector3(0, 0.3, 0), 1.3, false)
				_sound("debris", _host, 6.0)
		elif k >= SINK_FROM:
			var t := clampf(float(k - SINK_FROM) / SINK_TICKS, 0.0, 1.0)
			_host.y = DUST_Y - 2.4 * t * t
		# Flailing (the body reads a fall from a steep drop) until he's under.
		if _host.y <= DUST_Y + 0.05:
			_host_vel = Vector3(0, -9.0, 0)
	if _pursuer != null:
		_pursuer.set("pos", to_global(_host))
		_pursuer.global_position = to_global(_host)
		_pursuer.set("velocity", global_basis * _host_vel)
		_pursuer.set("lunging", false)
		_pursuer.set("cutting", false)
		var face := global_basis * Vector3(0, 0, -1)
		_pursuer.global_basis = Basis.looking_at(face, Vector3.UP)
		_pursuer.visible = not (_broken and ticks - _break_tick >= GONE_AT)


func _break() -> void:
	_broken = true
	_break_tick = ticks
	_set_east_solid(false)
	_host_vel = Vector3(0, 0.5, -3.0)
	_burst(Vector3(0, 0.2, -_length), 1.6, false)
	_sound("door_bang", Vector3(0, 0, -_length), 8.0)
	_sound("debris", Vector3(0, 0, -_length * 0.75), 8.0)
	went.emit("silt_break")


func _after_break() -> void:
	var k := ticks - _break_tick
	var dt := 1.0 / 60.0
	# The far half: its bank end tears off and it tips down about the wreck.
	var t := clampf(float(k) / SWING_TICKS, 0.0, 1.0)
	_east.transform = Transform3D(Basis(Vector3.RIGHT, -deg_to_rad(SWING_DEG) * t * t), Vector3(0, -SAG, -_length * 0.5))
	# The Hollows: up out of the dust, in on him, over him.
	for i in _hollows.size():
		var h := _hollows[i]
		var b := _hollow_bodies[i]
		if k < RISE_AT:
			continue
		var home: Array = HOLLOWS[i]
		var start := Vector3(home[0], DUST_Y - 0.2, home[1])
		# Around him, close: a ring that tightens as he goes under.
		var ring := lerpf(1.6, 0.7, clampf(float(k - REACH_AT) / 90.0, 0.0, 1.0))
		var spot := _landed_at + Basis(Vector3.UP, TAU * float(i) / _hollows.size()) * Vector3(0, 0, ring)
		var u := clampf(float(k - RISE_AT) / float(REACH_AT - RISE_AT), 0.0, 1.0)
		var at := start.lerp(Vector3(spot.x, DUST_Y - 0.15, spot.z), u * u * (3.0 - 2.0 * u))
		if k > GONE_AT - 30:
			at.y = DUST_Y - 0.15 - 0.9 * clampf(float(k - GONE_AT + 30) / 60.0, 0.0, 1.0)
		var last := h.position
		h.position = at
		var flat := Vector3(spot.x - at.x, 0, spot.z - at.z)
		if flat.length() > 0.05:
			h.basis = Basis.looking_at(flat.normalized(), Vector3.UP)
		var speed := (at - last).length() / dt
		if b == null or not b.has_method("show_pose") or _poses == null:
			continue
		b.set("grounded", true)
		b.step(speed, 2.2, dt)
		var pose: Dictionary
		if u < 1.0:
			pose = _poses.lope(b.phase, clampf(speed / 4.0, 0.3, 1.0))
		else:
			pose = _poses.swipe(sin(float(k + i * 13) * 0.35))
		b.show_pose(pose, dt, 10.0)
	if k == SQUEAL_AT:
		_play_squeal()
	if k == CUT_AT:
		if _squeal != null:
			_squeal.stop()
		_sound("radio_key", Vector3(0, 2, -_length), 4.0)
	if k >= DOWN_AT and not _down:
		_down = true
		went.emit("silt_down")


## The middle sags with Echo on the girder (most at the middle), and
## springs back once she's off.
func _sag(local: Vector3) -> void:
	var w := 0.0
	if local.z < 0.0 and local.z > -_length and absf(local.x) < DECK_WIDTH + 1.0 and local.y > -0.6:
		w = 1.0 - absf(local.z + _length * 0.5) / (_length * 0.5)
	var d := SAG * clampf(w * 1.6, 0.0, 1.0)
	var a := atan2(d, _length * 0.5)
	_west.transform = Transform3D(Basis(Vector3.RIGHT, -a), Vector3.ZERO)
	_east.transform = Transform3D(Basis(Vector3.RIGHT, a), Vector3(0, -d, -_length * 0.5))


## The girder's top at z (with the sag as it stands).
func _deck_y(z: float) -> float:
	var half := _length * 0.5
	var drop := -_east.position.y if _east != null else 0.0
	return -drop * (1.0 - absf(z + half) / half)


# ---------------------------------------------------------------- looks

func _build() -> void:
	var rust := _steel()
	rust.albedo_color = Color(0.34, 0.2, 0.13)
	_west = _half("GirderWest", rust, false)
	_east = _half("GirderEast", rust, true)
	# The wreck the halves rest on, sunk in the dust: a container on its side.
	var wreck := StandardMaterial3D.new()
	wreck.albedo_color = Color(0.22, 0.27, 0.3)
	wreck.roughness = 0.85
	var w := Node3D.new()
	w.name = "Wreck"
	w.position = Vector3(0.4, DUST_Y - 0.6, -_length * 0.5)
	w.rotation = Vector3(0.08, 0.5, 0.12)
	add_child(w)
	_part(w, Vector3(0, 0, 0), Vector3(2.6, 1.4, 6.0), wreck, false)
	_channel()
	_build_hollows()
	_build_drone()
	_build_feed()


## One half of the girder (I-beam: top flange you run on, web, bottom
## flange), pivoting at its near end.
func _half(node_name: String, mat: Material, far: bool) -> Node3D:
	var half := _length * 0.5
	var n := Node3D.new()
	n.name = node_name
	add_child(n)
	var body := StaticBody3D.new()
	body.name = "Deck"
	body.collision_mask = 0
	body.set_meta("kind", "NEUTRAL")
	n.add_child(body)
	var mid := -half * 0.5
	_part(body, Vector3(0, -DECK_THICK * 0.5, mid), Vector3(DECK_WIDTH, DECK_THICK, half - 0.1), mat, true)
	_part(n, Vector3(0, -DECK_THICK - 0.5, mid), Vector3(0.3, 1.0, half - 0.1), mat, false)
	_part(n, Vector3(0, -DECK_THICK - 1.1, mid), Vector3(1.4, 0.2, half - 0.1), mat, false)
	# Rivet plates every few meters, so speed reads.
	var d := 2.0
	while d < half:
		_part(n, Vector3(0, -DECK_THICK - 0.5, -d), Vector3(0.5, 0.9, 0.12), mat, false)
		d += 4.0
	if far:
		_east_body = body
	return n


func _set_east_solid(on: bool) -> void:
	if _east_body == null:
		return
	for c: Node in _east_body.get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).set_deferred("disabled", not on)


## The riverbed the level shows: dust between the banks, concrete edges.
func _channel() -> void:
	var c: Array = spec.get("channel", [])
	if c.size() < 4:
		return
	var root := Node3D.new()
	root.name = "Channel"
	root.top_level = true
	add_child(root)
	root.transform = Transform3D.IDENTITY
	var x0 := float(c[0])
	var x1 := float(c[2])
	var z0 := float(c[1])
	var z1 := float(c[3])
	var dust := StandardMaterial3D.new()
	dust.albedo_color = Color(0.42, 0.35, 0.27)
	dust.roughness = 1.0
	# Drifts and ripples, so it reads as dust and not as a floor.
	var noise := FastNoiseLite.new()
	noise.frequency = 0.02
	noise.fractal_octaves = 4
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.seamless = true
	tex.width = 256
	tex.height = 256
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.72, 0.68, 0.62))
	ramp.set_color(1, Color(1.0, 0.97, 0.92))
	tex.color_ramp = ramp
	dust.albedo_texture = tex
	dust.uv1_scale = Vector3((x1 - x0) / 24.0, (z1 - z0) / 24.0, 1.0)
	var plane := MeshInstance3D.new()
	plane.name = "Dust"
	var pm := PlaneMesh.new()
	pm.size = Vector2(x1 - x0, z1 - z0)
	pm.subdivide_width = 24
	pm.subdivide_depth = 120
	plane.mesh = pm
	plane.material_override = dust
	var dust_y := position.y + DUST_Y
	plane.position = Vector3((x0 + x1) * 0.5, dust_y, (z0 + z1) * 0.5)
	root.add_child(plane)
	# Drifts and humps in the dust (and the Hollows' shapes among them).
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var hump := StandardMaterial3D.new()
	hump.albedo_color = Color(0.36, 0.3, 0.23)
	hump.roughness = 1.0
	for i in 70:
		var m := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = rng.randf_range(1.2, 3.5)
		sm.height = sm.radius * 2.0
		m.mesh = sm
		m.material_override = hump
		m.scale = Vector3(1.0, rng.randf_range(0.12, 0.25), rng.randf_range(1.0, 2.2))
		m.position = Vector3(rng.randf_range(x0 + 3.0, x1 - 3.0), dust_y, rng.randf_range(z0, z1))
		root.add_child(m)
	# The banks' concrete edges, flush with the street, down into the dust.
	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = Color(0.48, 0.47, 0.44)
	concrete.roughness = 0.95
	for x: float in [x0 + 0.3, x1 - 0.3]:
		_part(root, Vector3(x, -1.6, (z0 + z1) * 0.5), Vector3(0.6, 3.2, z1 - z0), concrete, false)


func _build_hollows() -> void:
	var body_script := load(ENEMY_BODY_PATH) as Script if ResourceLoader.exists(ENEMY_BODY_PATH) else null
	_poses = load(ENEMY_POSES_PATH) as Script if ResourceLoader.exists(ENEMY_POSES_PATH) else null
	for i in HOLLOWS.size():
		var h := Node3D.new()
		h.name = "Hollow%d" % i
		add_child(h)
		_hollows.append(h)
		var b: Node3D = null
		if body_script != null and body_script.can_instantiate():
			b = body_script.new()
			b.name = "Body"
			h.add_child(b)
			if b.load_model(MUTANT_MODEL):
				b.show_part("Armor", false)
			else:
				b.queue_free()
				b = null
		_hollow_bodies.append(b)
		_lie(i)


## A Hollow lying still in the dust, half under (laid flat like a dead
## enemy).
func _lie(i: int) -> void:
	var home: Array = HOLLOWS[i]
	var h := _hollows[i]
	h.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(float(home[2]))) * Basis(Vector3.RIGHT, -PI * 0.5),
		Vector3(home[0], DUST_Y + 0.05, home[1]))
	var b := _hollow_bodies[i]
	if b != null and _poses != null and b.has_method("snap_pose"):
		b.set("grounded", false)
		b.snap_pose(_poses.dead())


## Echo's camera drone over the far bank, watching the girder.
func _build_drone() -> void:
	_drone = Node3D.new()
	_drone.name = "EchoDrone"
	_drone.position = Vector3(3.5, 4.2, -_length - 5.0)
	add_child(_drone)
	var body_script := load(ENEMY_BODY_PATH) as Script if ResourceLoader.exists(ENEMY_BODY_PATH) else null
	if body_script != null and body_script.can_instantiate():
		var b: Node3D = body_script.new()
		b.name = "Body"
		_drone.add_child(b)
		if b.load_model(DRONE_MODEL):
			b.tint(Color(0.45, 0.9, 1.0))
		else:
			b.queue_free()
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(0.45, 0.9, 1.0)
	lamp.light_energy = 1.0
	lamp.omni_range = 3.0
	_drone.add_child(lamp)
	_drone.basis = Basis.looking_at(Vector3(0, 0, -_length * 0.6) - _drone.position, Vector3.UP)


## The drone's live feed, in the corner of the screen: you see him go
## whichever way you're looking.
func _build_feed() -> void:
	_feed = CanvasLayer.new()
	_feed.name = "EchoCam"
	_feed.layer = 4
	_feed.visible = false
	add_child(_feed)
	var vp := SubViewport.new()
	vp.name = "View"
	vp.size = Vector2i(480, 270)
	vp.render_target_update_mode = SubViewport.UPDATE_WHEN_PARENT_VISIBLE
	_feed.add_child(vp)
	_feed_cam = Camera3D.new()
	_feed_cam.fov = 48.0
	_feed_cam.far = 400.0
	vp.add_child(_feed_cam)
	var frame := ColorRect.new()
	frame.color = Color(0.05, 0.05, 0.06, 0.9)
	frame.anchor_left = 1.0
	frame.anchor_right = 1.0
	frame.offset_left = -508.0
	frame.offset_right = -20.0
	frame.offset_top = 20.0
	frame.offset_bottom = 318.0
	_feed.add_child(frame)
	var view := TextureRect.new()
	view.texture = vp.get_texture()
	view.position = Vector2(4, 24)
	view.size = Vector2(480, 270)
	frame.add_child(view)
	var label := Label.new()
	label.text = "ECHO CAM  ● LIVE"
	label.position = Vector2(8, 2)
	label.add_theme_color_override("font_color", Color(0.45, 0.9, 1.0))
	label.add_theme_font_size_override("font_size", 16)
	frame.add_child(label)


func _show_feed(on: bool) -> void:
	if _feed == null:
		return
	_feed.visible = on
	_feed_time = 0.0 if on else -1.0


func _process(delta: float) -> void:
	super._process(delta)
	if _feed == null or not _feed.visible or _feed_cam == null:
		return
	_feed_time += delta
	# The drone keeps him in frame (on the girder, then where he went in).
	var look := to_global(_host if fired else Vector3(0, 0, -_length * 0.5))
	var from := _drone.global_position if _drone != null else to_global(Vector3(3.5, 4.2, -_length - 5.0))
	if from.distance_to(look) > 2.0:
		# Just in front of the drone's own body.
		var eye := from + (look - from).normalized() * 1.2
		_feed_cam.look_at_from_position(eye, look + Vector3(0, -0.3, 0), Vector3.UP)
	if _drone != null and from.distance_to(look) > 0.5:
		_drone.look_at(look, Vector3.UP)
	# Off a few seconds after the dust has him.
	if _down:
		var f: ColorRect = _feed.get_child(1) as ColorRect
		if f != null:
			f.modulate.a = maxf(f.modulate.a - delta * 0.25, 0.0)
			if f.modulate.a <= 0.0:
				_feed.visible = false


## His mic feeding back: a howl that climbs, then the cut.
func _play_squeal() -> void:
	if _squeal == null:
		var s := PackedFloat32Array()
		s.resize(int(SoundBank.RATE * 1.3))
		var ph := 0.0
		for i in s.size():
			var t := float(i) / SoundBank.RATE
			var hz := 1700.0 + 1500.0 * (t / 1.3) + 40.0 * sin(TAU * 6.0 * t)
			ph += TAU * hz / SoundBank.RATE
			var amp := clampf(t / 0.9, 0.05, 1.0)
			s[i] = SoundBank.sat(sin(ph) * amp * 1.6 + 0.3 * sin(ph * 2.01) * amp) * 0.5
		_squeal = AudioStreamPlayer.new()
		_squeal.stream = SoundBank.wav(s)
		_squeal.bus = &"Radio"
		_squeal.volume_db = -6.0
		add_child(_squeal)
	if _squeal.is_inside_tree() and DisplayServer.get_name() != "headless":
		_squeal.play()
