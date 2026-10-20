class_name EnemySfx
extends RefCounted
## Procedural placeholder sounds for enemies, like weapons/sfx.gd. Built
## once and shared.

const RATE := 22050

static var _cache := {}


static func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


static func get_sound(sound: StringName) -> AudioStreamWAV:
	if not _cache.has(sound):
		match sound:
			&"lock":
				_cache[sound] = _lock()
			&"raider_shot":
				_cache[sound] = _raider_shot()
			&"growl":
				_cache[sound] = _growl()
			&"swipe":
				_cache[sound] = _swipe()
			&"drone_shot":
				_cache[sound] = _crack(41, 0.12, 2400.0, 40.0)
			&"soldier_shot":
				_cache[sound] = _crack(43, 0.2, 900.0, 22.0)
			&"crash":
				_cache[sound] = _crash()
			&"clank":
				_cache[sound] = _clank()
			_:
				return null
	return _cache[sound]


## The raider's aim locking on: two rising beeps, the "move now" cue.
static func _lock() -> AudioStreamWAV:
	var n := int(RATE * 0.2)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var f := 1300.0 if t < 0.09 else 1750.0
		var local := fmod(t, 0.1)
		s[i] = sin(TAU * f * t) * (1.0 - local / 0.1) * 0.35
	return _wav(s)


## Lower and rougher than the player's pistol, so you can tell them apart.
static func _raider_shot() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var n := int(RATE * 0.25)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0) * exp(-t * 24.0)
		var thump := sin(TAU * 70.0 * t) * exp(-t * 16.0)
		s[i] = noise * 0.6 + thump * 0.7
	return _wav(s)


## A mutant winding up a leap.
static func _growl() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var n := int(RATE * 0.45)
	var s := PackedFloat32Array()
	s.resize(n)
	var smooth := 0.0
	for i in n:
		var t := float(i) / RATE
		smooth = lerpf(smooth, rng.randf_range(-1.0, 1.0), 0.08)
		var env := minf(t / 0.08, 1.0) * exp(-maxf(t - 0.25, 0.0) * 12.0)
		s[i] = (smooth * 2.2 + sin(TAU * (90.0 + 40.0 * t) * t) * 0.4) * env * 0.6
	return _wav(s)


static func _swipe() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var n := int(RATE * 0.18)
	var s := PackedFloat32Array()
	s.resize(n)
	var smooth := 0.0
	for i in n:
		var t := float(i) / RATE
		smooth = lerpf(smooth, rng.randf_range(-1.0, 1.0), 0.35)
		s[i] = smooth * sin(PI * t / 0.18) * 0.8
	return _wav(s)


## A short, tight shot: noise burst with a ringing tone (`tone` Hz).
static func _crack(seed_value: int, length: float, tone: float, decay: float) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var n := int(RATE * length)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0) * exp(-t * decay * 1.4)
		var ring := sin(TAU * tone * t) * exp(-t * decay)
		var thump := sin(TAU * 110.0 * t) * exp(-t * 30.0)
		s[i] = noise * 0.55 + ring * 0.25 + thump * 0.5
	return _wav(s)


## A drone hitting the ground: a crunch and rattling metal.
static func _crash() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 53
	var n := int(RATE * 0.6)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var rattle := rng.randf_range(-1.0, 1.0) * exp(-t * 7.0) * (0.6 + 0.4 * sin(TAU * 23.0 * t))
		var ping := (sin(TAU * 1830.0 * t) + sin(TAU * 2610.0 * t)) * exp(-t * 9.0) * 0.2
		s[i] = rattle * 0.7 + ping + sin(TAU * 60.0 * t) * exp(-t * 20.0) * 0.6
	return _wav(s)


## A bullet glancing off a riot shield.
static func _clank() -> AudioStreamWAV:
	var n := int(RATE * 0.3)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		s[i] = (sin(TAU * 1240.0 * t) * 0.5 + sin(TAU * 1970.0 * t) * 0.3 + sin(TAU * 3110.0 * t) * 0.2) * exp(-t * 14.0) * 0.6
	return _wav(s)


## Plays a sound at a node (3D, so you can hear where it came from).
static func play_at(node: Node3D, sound: StringName, volume_db := 0.0) -> void:
	if node == null or not node.is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = get_sound(sound)
	p.volume_db = volume_db
	p.unit_size = 8.0
	node.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
