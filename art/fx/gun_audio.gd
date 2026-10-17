class_name GunAudio
extends RefCounted
## Procedural gun sounds for the scrap pistol (no audio files to license).
##
## A shot is layered the way real recordings are: a sharp supersonic crack,
## a noisy blast body, a low chest thump, the slide's metallic clack a beat
## later, and a dusty tail with a slap echo off nearby walls. Several
## variations are made so rapid fire doesn't sound like a loop.

const RATE := 44100


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


## Soft clip, so the layers can be loud together without harsh clipping.
static func _sat(v: float) -> float:
	return v / (1.0 + absf(v))


static func gunshot(variation: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 101 + variation * 7919
	var len := 0.62
	var n := int(RATE * len)
	var s := PackedFloat32Array()
	s.resize(n)
	var thump_hz := rng.randf_range(52.0, 62.0)
	var clack_at := rng.randf_range(0.028, 0.036)
	var clack_hz := [rng.randf_range(2600.0, 3000.0), rng.randf_range(4100.0, 4600.0), rng.randf_range(6400.0, 7000.0)]
	var echo_at := rng.randf_range(0.085, 0.11)
	# One-pole filter states.
	var lp_body := 0.0
	var lp_tail := 0.0
	var hp_prev_in := 0.0
	var hp_out := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var white := rng.randf_range(-1.0, 1.0)
		# Crack: a few ms of bright, high-passed noise.
		hp_out = 0.6 * (hp_out + white - hp_prev_in)
		hp_prev_in = white
		var crack := hp_out * exp(-t * 520.0) * 1.6
		# Blast body: lower noise, fast decay.
		lp_body += (white - lp_body) * 0.22
		var body := lp_body * exp(-t * 34.0) * 2.4
		# Thump: a falling sine for weight.
		var hz := thump_hz + 90.0 * exp(-t * 40.0)
		phase += TAU * hz / RATE
		var thump := sin(phase) * exp(-t * 16.0) * 0.9
		# Slide clack.
		var clack := 0.0
		if t > clack_at:
			var tc := t - clack_at
			for k in clack_hz.size():
				clack += sin(TAU * clack_hz[k] * tc) * exp(-tc * (90.0 + 40.0 * k)) * (0.16 / (k + 1))
		# Tail: dark rumble, plus a slap echo of the body off nearby walls.
		lp_tail += (white - lp_tail) * 0.04
		var tail := lp_tail * exp(-t * 6.5) * 1.3 * smoothstep(0.0, 0.03, t)
		var echo := 0.0
		if t > echo_at:
			var te := t - echo_at
			echo = lp_tail * exp(-te * 30.0) * 1.1
		s[i] = _sat((crack + body + thump + clack + tail + echo) * 0.9) * 0.95
	# Fade the last bit so the tail never clicks.
	for i in range(n - 400, n):
		s[i] *= float(n - i) / 400.0
	return _wav(s)


## A spent case bouncing on concrete: two quick bright tinks.
static func casing(variation: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 33 + variation * 131
	var n := int(RATE * 0.32)
	var s := PackedFloat32Array()
	s.resize(n)
	var f1 := rng.randf_range(5200.0, 6400.0)
	var f2 := f1 * rng.randf_range(1.48, 1.56)
	var bounce := rng.randf_range(0.09, 0.14)
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for hit: Array in [[0.0, 1.0], [bounce, 0.45], [bounce * 1.6, 0.18]]:
			var th: float = t - hit[0]
			if th >= 0.0:
				v += (sin(TAU * f1 * th) + 0.6 * sin(TAU * f2 * th)) * exp(-th * 55.0) * hit[1]
		s[i] = v * 0.12
	return _wav(s)


## Bullet hitting concrete or metal: a short crunchy snap.
static func impact(variation: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77 + variation * 17
	var n := int(RATE * 0.12)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var white := rng.randf_range(-1.0, 1.0)
		lp += (white - lp) * 0.35
		var grit := (white - lp) * exp(-t * 80.0)
		var knock := sin(TAU * 180.0 * t) * exp(-t * 45.0) * 0.4
		s[i] = (grit * 0.5 + lp * exp(-t * 50.0) * 0.6 + knock) * 0.5
	return _wav(s)
