class_name Sfx
extends RefCounted
## Tiny procedural sounds so the prototype has feedback without audio assets.

const RATE := 22050


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


## Sharp crack with a low thump.
static func gunshot() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var n := int(RATE * 0.16)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0) * exp(-t * 38.0)
		var thump := sin(TAU * 95.0 * t) * exp(-t * 22.0)
		s[i] = noise * 0.7 + thump * 0.6
	return _wav(s)


## Hit confirm: a short tick. Headshots ring higher with a second note.
static func hit_tick(headshot: bool) -> AudioStreamWAV:
	var n := int(RATE * (0.14 if headshot else 0.06))
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var v := sin(TAU * (1500.0 if headshot else 900.0) * t) * exp(-t * (22.0 if headshot else 60.0))
		if headshot:
			v += 0.5 * sin(TAU * 2250.0 * t) * exp(-t * 30.0)
		s[i] = v * 0.45
	return _wav(s)


static func dry_fire() -> AudioStreamWAV:
	var n := int(RATE * 0.03)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		s[i] = sin(TAU * 2400.0 * t) * exp(-t * 150.0) * 0.3
	return _wav(s)
