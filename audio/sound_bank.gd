class_name SoundBank
extends RefCounted
## Movement and world sounds, synthesised in code (no audio files, so nothing
## to license). Each sound is built from the same few pieces real foley is:
## a low thump for weight, filtered noise for grit and cloth, and a few
## decaying sine partials for anything that rings (metal, glass). Every sound
## has several seeded variations so repeats don't sound like a loop.
##
## Surfaces: &"concrete", &"asphalt" (gritty) and &"metal" (hollow, ringing).

const RATE := 44100
const SURFACES: Array[StringName] = [&"concrete", &"asphalt", &"metal"]


static func wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


## Frequency of a MIDI note (69 = A 440). Kept here as well as in MusicSynth
## so the two scripts don't depend on each other.
static func midi_hz(note: float) -> float:
	return 440.0 * pow(2.0, (note - 69.0) / 12.0)


## Soft clip, so layers can be loud together without harsh clipping.
static func sat(v: float) -> float:
	return v / (1.0 + absf(v))


static func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


static func _buffer(seconds: float) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(int(RATE * seconds))
	return s


## Fades the last few ms so a one-shot never ends on a click.
static func _fade_end(s: PackedFloat32Array, ms := 8.0) -> void:
	var k := mini(int(RATE * ms / 1000.0), s.size())
	for i in k:
		s[s.size() - 1 - i] *= float(i) / k


## Crossfades the tail into the head so a loop wraps without a seam.
static func _seamless(s: PackedFloat32Array, fade_seconds: float) -> PackedFloat32Array:
	var k := int(RATE * fade_seconds)
	var n := s.size() - k
	var out := s.slice(0, n)
	for i in k:
		var a := float(i) / k
		out[i] = out[i] * a + s[n + i] * (1.0 - a)
	return out


static func _peak(s: PackedFloat32Array, peak: float) -> void:
	var m := 0.0
	for v in s:
		m = maxf(m, absf(v))
	if m > 0.0:
		var g := peak / m
		for i in s.size():
			s[i] *= g


## Adds a short body thud: a falling sine plus dark noise.
static func _thud(s: PackedFloat32Array, at: float, gain: float, hz: float, decay: float, rng: RandomNumberGenerator) -> void:
	var start := int(at * RATE)
	var phase := 0.0
	var lp := 0.0
	for i in range(start, s.size()):
		var t := float(i - start) / RATE
		var env := exp(-t * decay)
		if env < 0.001:
			break
		phase += TAU * (hz + hz * 1.4 * exp(-t * 60.0)) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.08
		s[i] += (sin(phase) * 0.8 + lp * 1.6) * env * gain


## Adds filtered noise with a fast attack: grit, scuffs, cloth.
## `bright` 0..1 sets the filter (0 dark, 1 hissy).
static func _noise(s: PackedFloat32Array, at: float, length: float, gain: float, bright: float, decay: float, rng: RandomNumberGenerator, attack := 0.002) -> void:
	var start := int(at * RATE)
	var end := mini(s.size(), start + int(length * RATE))
	var a := lerpf(0.03, 0.9, bright)
	var lp := 0.0
	var lp2 := 0.0
	for i in range(start, end):
		var t := float(i - start) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * a
		lp2 += (lp - lp2) * a
		var v := lp - lp2 * (1.0 - bright) * 0.5 if bright > 0.5 else lp2
		s[i] += v * gain * exp(-t * decay) * smoothstep(0.0, attack, t)


## Adds ringing partials (metal, glass).
static func _ring(s: PackedFloat32Array, at: float, freqs: Array, gain: float, decay: float) -> void:
	var start := int(at * RATE)
	for k in freqs.size():
		var f: float = freqs[k]
		var d := decay * (1.0 + 0.5 * k)
		var g := gain / (1.0 + k * 0.6)
		for i in range(start, s.size()):
			var t := float(i - start) / RATE
			var env := exp(-t * d)
			if env < 0.001:
				break
			s[i] += sin(TAU * f * t) * env * g


# ---------------------------------------------------------------- feet

## One footfall. Heel and toe a few ms apart; grit on asphalt, a hollow
## clang on metal.
static func footstep(surface: StringName, variation: int) -> AudioStreamWAV:
	var rng := _rng(1000 + variation * 37 + SURFACES.find(surface) * 7001)
	var s := _buffer(0.22)
	var toe := rng.randf_range(0.018, 0.03)
	match surface:
		&"metal":
			_thud(s, 0.0, 0.5, rng.randf_range(70.0, 85.0), 30.0, rng)
			var base := rng.randf_range(380.0, 460.0)
			_ring(s, 0.0, [base, base * 2.31, base * 3.9, base * 5.2], 0.16, 26.0)
			_noise(s, toe, 0.06, 0.25, 0.8, 70.0, rng)
		&"asphalt":
			_thud(s, 0.0, 0.55, rng.randf_range(62.0, 75.0), 38.0, rng)
			_noise(s, 0.0, 0.16, 0.5, 0.75, 26.0, rng)
			for k in 5:  # small stones under the shoe
				_noise(s, rng.randf_range(0.01, 0.09), 0.006, rng.randf_range(0.2, 0.45), 1.0, 300.0, rng, 0.0005)
		_:
			_thud(s, 0.0, 0.6, rng.randf_range(65.0, 80.0), 40.0, rng)
			_noise(s, 0.0, 0.1, 0.35, 0.6, 40.0, rng)
			_noise(s, toe, 0.08, 0.25, 0.7, 50.0, rng)
	_peak(s, 0.85)
	_fade_end(s)
	return wav(s)


## Hitting the ground. Heavier ones sound lower and longer; hard landings
## get a scatter of debris on top (see debris()).
static func landing(surface: StringName, variation: int) -> AudioStreamWAV:
	var rng := _rng(2000 + variation * 53 + SURFACES.find(surface) * 7001)
	var s := _buffer(0.45)
	_thud(s, 0.0, 1.0, rng.randf_range(48.0, 58.0), 13.0, rng)
	_thud(s, rng.randf_range(0.012, 0.022), 0.6, rng.randf_range(70.0, 85.0), 22.0, rng)
	_noise(s, 0.0, 0.3, 0.45, 0.55, 14.0, rng)
	if surface == &"metal":
		var base := rng.randf_range(160.0, 210.0)
		_ring(s, 0.0, [base, base * 2.76, base * 5.4, base * 8.9], 0.25, 9.0)
	elif surface == &"asphalt":
		_noise(s, 0.01, 0.25, 0.35, 0.85, 18.0, rng)
	_peak(s, 0.9)
	_fade_end(s)
	return wav(s)


## Gravel and grit kicked up by a hard landing or a crash.
static func debris(variation: int) -> AudioStreamWAV:
	var rng := _rng(2500 + variation * 19)
	var s := _buffer(0.7)
	for k in 26:
		var at := rng.randf_range(0.0, 0.45) * rng.randf()
		_noise(s, at, 0.02, rng.randf_range(0.15, 0.5), rng.randf_range(0.7, 1.0), rng.randf_range(80.0, 200.0), rng, 0.0005)
	_noise(s, 0.0, 0.6, 0.3, 0.4, 7.0, rng, 0.01)
	_peak(s, 0.8)
	_fade_end(s)
	return wav(s)


## Pushing off: a shoe scuff and a little cloth.
static func jump(variation: int) -> AudioStreamWAV:
	var rng := _rng(3000 + variation * 61)
	var s := _buffer(0.3)
	_thud(s, 0.0, 0.35, rng.randf_range(80.0, 95.0), 45.0, rng)
	_noise(s, 0.0, 0.08, 0.6, 0.85, 45.0, rng)
	_noise(s, 0.03, 0.25, 0.35, 0.35, 12.0, rng, 0.04)
	_peak(s, 0.8)
	_fade_end(s)
	return wav(s)


## Hands on an edge or wall (vaults, mantles, wallrun starts, climbing).
static func hand_plant(variation: int) -> AudioStreamWAV:
	var rng := _rng(4000 + variation * 29)
	var s := _buffer(0.16)
	_noise(s, 0.0, 0.03, 1.0, 0.95, 120.0, rng, 0.0004)
	_thud(s, 0.0, 0.4, rng.randf_range(110.0, 140.0), 50.0, rng)
	_noise(s, 0.01, 0.12, 0.3, 0.7, 35.0, rng)
	_peak(s, 0.8)
	_fade_end(s)
	return wav(s)


## Air and cloth moving fast: flips, spins, dives, vaults, kicks that miss.
static func whoosh(variation: int, length := 0.4) -> AudioStreamWAV:
	var rng := _rng(5000 + variation * 43)
	var s := _buffer(length)
	var lp := 0.0
	var lp2 := 0.0
	var bp := 0.0
	var peak_at := rng.randf_range(0.35, 0.5)
	for i in s.size():
		var u := float(i) / s.size()
		# The filter opens then closes as the limb passes.
		var swell := sin(PI * pow(u, peak_at / 0.5 * 0.7))
		var a := lerpf(0.015, 0.16, swell)
		lp += (rng.randf_range(-1.0, 1.0) - lp) * a
		lp2 += (lp - lp2) * a
		bp = lp - lp2
		s[i] = (lp2 * 0.6 + bp * 0.8) * swell * swell
	_peak(s, 0.7)
	_fade_end(s)
	return wav(s)


## Tucking into a roll: two shoulder/back thuds and a cloth tumble.
static func roll(variation: int) -> AudioStreamWAV:
	var rng := _rng(6000 + variation * 71)
	var s := _buffer(0.6)
	_thud(s, 0.0, 0.55, rng.randf_range(70.0, 82.0), 20.0, rng)
	_thud(s, rng.randf_range(0.17, 0.22), 0.4, rng.randf_range(60.0, 72.0), 24.0, rng)
	_noise(s, 0.0, 0.5, 0.45, 0.4, 5.0, rng, 0.03)
	_noise(s, 0.02, 0.45, 0.2, 0.8, 9.0, rng, 0.02)
	_peak(s, 0.8)
	_fade_end(s, 30.0)
	return wav(s)


## Running into a wall or crashing on a landing.
static func bonk(variation: int) -> AudioStreamWAV:
	var rng := _rng(6500 + variation * 13)
	var s := _buffer(0.4)
	_thud(s, 0.0, 1.0, rng.randf_range(55.0, 65.0), 18.0, rng)
	_noise(s, 0.0, 0.2, 0.5, 0.5, 22.0, rng)
	_ring(s, 0.0, [rng.randf_range(220.0, 260.0), 610.0], 0.08, 18.0)
	_peak(s, 0.9)
	_fade_end(s)
	return wav(s)


# ---------------------------------------------------------------- loops

## Sliding on your hip: a rough scrape. Loops.
static func slide_loop(surface: StringName) -> AudioStreamWAV:
	var rng := _rng(7000 + SURFACES.find(surface))
	var s := _buffer(2.2)
	var lp := 0.0
	var lp2 := 0.0
	var a := 0.55 if surface == &"metal" else 0.3
	for i in s.size():
		var t := float(i) / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * a
		lp2 += (lp - lp2) * 0.04
		# Uneven ground makes the grind pulse.
		var rough := 0.7 + 0.3 * sin(TAU * 7.3 * t + sin(TAU * 1.1 * t) * 2.0)
		s[i] = ((lp - lp2) * 0.9 + lp2 * 1.2) * rough
	if surface == &"metal":
		var base := 290.0
		for k in 3:
			var f: float = base * [1.0, 2.6, 4.1][k]
			for i in s.size():
				var t := float(i) / RATE
				s[i] += sin(TAU * f * t) * 0.05 * (0.6 + 0.4 * sin(TAU * 0.9 * t + k))
	_peak(s, 0.8)
	return wav(_seamless(s, 0.2), true)


## Wind past the ears. `high` is the hiss that comes in at top speed; the
## other is the low rumble. Loops.
static func wind_loop(high: bool) -> AudioStreamWAV:
	var rng := _rng(8000 + int(high))
	var s := _buffer(4.4)
	var lp := 0.0
	var lp2 := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var gust := 0.75 + 0.25 * sin(TAU * 0.23 * t) * sin(TAU * 0.71 * t + 1.3)
		var a := (0.25 if high else 0.02) * (0.8 + 0.4 * gust)
		lp += (rng.randf_range(-1.0, 1.0) - lp) * a
		lp2 += (lp - lp2) * a
		s[i] = ((lp - lp2 * 0.7) if high else lp2) * gust
	_peak(s, 0.7)
	return wav(_seamless(s, 0.4), true)


# ---------------------------------------------------------------- world

## A kick landing on something solid.
static func kick_hit(variation: int) -> AudioStreamWAV:
	var rng := _rng(9000 + variation * 11)
	var s := _buffer(0.35)
	_thud(s, 0.0, 1.0, rng.randf_range(75.0, 90.0), 22.0, rng)
	_noise(s, 0.0, 0.12, 0.6, 0.8, 40.0, rng, 0.0005)
	_peak(s, 0.9)
	_fade_end(s)
	return wav(s)


## A scrap-metal door slamming open: a crash, a rattle, a hinge squeal.
static func door_bang(variation: int) -> AudioStreamWAV:
	var rng := _rng(9500 + variation * 23)
	var s := _buffer(1.0)
	_thud(s, 0.0, 1.0, rng.randf_range(58.0, 68.0), 10.0, rng)
	_noise(s, 0.0, 0.3, 0.6, 0.7, 14.0, rng, 0.0005)
	var base := rng.randf_range(140.0, 180.0)
	_ring(s, 0.0, [base, base * 2.37, base * 3.83, base * 6.1], 0.35, 6.0)
	for k in 6:  # loose panel rattling
		var at := 0.08 + k * rng.randf_range(0.05, 0.08)
		_ring(s, at, [base * 3.1, base * 5.7], 0.12 * exp(-k * 0.4), 40.0)
	var squeal_hz := rng.randf_range(900.0, 1100.0)
	for i in range(int(0.05 * RATE), int(0.45 * RATE)):
		var t := float(i) / RATE - 0.05
		s[i] += sin(TAU * squeal_hz * t * (1.0 + 0.15 * t) + sin(TAU * 31.0 * t) * 0.6) * 0.05 * sin(PI * t / 0.4)
	_peak(s, 0.9)
	_fade_end(s, 40.0)
	return wav(s)


## The door swinging shut again.
static func door_close(variation: int) -> AudioStreamWAV:
	var rng := _rng(9700 + variation * 5)
	var s := _buffer(0.5)
	_thud(s, 0.0, 0.7, rng.randf_range(80.0, 95.0), 20.0, rng)
	_ring(s, 0.0, [330.0, 780.0, 1290.0], 0.12, 16.0)
	_peak(s, 0.6)
	_fade_end(s)
	return wav(s)


## A pane of glass breaking: the crack, the burst, then shards tinkling down.
static func glass(variation: int) -> AudioStreamWAV:
	var rng := _rng(9900 + variation * 47)
	var s := _buffer(1.5)
	_noise(s, 0.0, 0.25, 1.0, 0.95, 18.0, rng, 0.0003)
	_thud(s, 0.0, 0.35, 120.0, 30.0, rng)
	for k in 40:
		var at := pow(rng.randf(), 1.6) * 1.1
		var f := rng.randf_range(2200.0, 7800.0)
		_ring(s, at, [f, f * rng.randf_range(1.4, 1.7)], rng.randf_range(0.05, 0.2) * exp(-at * 1.5), rng.randf_range(40.0, 90.0))
	_peak(s, 0.9)
	_fade_end(s, 40.0)
	return wav(s)


## Time slowing down (`down`) or catching back up: a deep tape-stop sweep.
static func slow_mo(down: bool) -> AudioStreamWAV:
	var rng := _rng(12000 + int(down))
	var s := _buffer(0.8)
	var phase := 0.0
	var lp := 0.0
	for i in s.size():
		var u := float(i) / s.size()
		var k := u if down else 1.0 - u
		var hz := lerpf(180.0, 38.0, k)
		phase += TAU * hz / RATE
		lp += (rng.randf_range(-1.0, 1.0) - lp) * lerpf(0.2, 0.02, k)
		var env := sin(PI * u) * (1.0 - u * 0.4)
		s[i] = (sin(phase) * 0.6 + sin(phase * 2.0) * 0.2 + lp * 0.8) * env
	_peak(s, 0.7)
	_fade_end(s)
	return wav(s)


# ---------------------------------------------------------------- combo

## A combo banked: struck scrap-metal chimes rising through E minor
## pentatonic. `big` adds the top notes and a longer ring.
static func bank_chime(big: bool) -> AudioStreamWAV:
	var rng := _rng(13000 + int(big))
	var s := _buffer(1.6 if big else 0.9)
	var notes := [64, 67, 71, 76, 79] if big else [64, 71, 76]
	for k in notes.size():
		var hz := midi_hz(notes[k])
		var at := k * 0.06
		_ring(s, at, [hz, hz * 2.0, hz * 2.98, hz * 4.1], 0.3, 4.0 if big else 6.0)
		_noise(s, at, 0.02, 0.15, 0.95, 150.0, rng, 0.0003)
	_peak(s, 0.7)
	_fade_end(s, 60.0)
	return wav(s)


## A combo lost: a detuned metal clunk sliding down.
static func bail_sting() -> AudioStreamWAV:
	var rng := _rng(13500)
	var s := _buffer(0.7)
	var phase := 0.0
	var phase2 := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var hz := 220.0 * pow(0.35, t / 0.6)
		phase += TAU * hz / RATE
		phase2 += TAU * hz * 1.06 / RATE
		s[i] = sat((sin(phase) + sin(phase2) * 0.8) * 1.5) * exp(-t * 4.0) * 0.6
	_thud(s, 0.0, 0.6, 60.0, 14.0, rng)
	_peak(s, 0.7)
	_fade_end(s, 30.0)
	return wav(s)


# ---------------------------------------------------------------- radio

## Radio crackle: pops and hiss. A loop for under the idle music, or a short
## burst for keying the mic on and off.
static func radio_static(loop: bool, variation := 0) -> AudioStreamWAV:
	var rng := _rng(14000 + variation * 3 + int(loop) * 101)
	var s := _buffer(3.0 if loop else 0.25)
	var lp := 0.0
	for i in s.size():
		var u := float(i) / s.size()
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.5
		var env := 1.0 if loop else sin(PI * u)
		s[i] = lp * 0.25 * env
	for k in (40 if loop else 8):
		_noise(s, rng.randf_range(0.0, s.size() / float(RATE) - 0.01), 0.004, rng.randf_range(0.3, 1.0), 1.0, 600.0, rng, 0.0002)
	_peak(s, 0.6)
	if loop:
		return wav(_seamless(s, 0.1), true)
	_fade_end(s)
	return wav(s)


## The warlord's show marking a combo milestone: a blast of static, then a
## two-tone broadcast jingle that climbs with `level` (1..3).
static func radio_sting(level: int) -> AudioStreamWAV:
	var rng := _rng(14500 + level)
	var s := _buffer(0.9)
	var lp := 0.0
	for i in int(0.08 * RATE):
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.6
		s[i] += lp * 0.5
	var base: int = [64, 67, 71][clampi(level - 1, 0, 2)]
	var notes := [base, base + 7, base + 12]
	for k in notes.size():
		var hz := midi_hz(notes[k])
		var start := int((0.08 + k * 0.11) * RATE)
		for i in range(start, mini(s.size(), start + int(0.32 * RATE))):
			var t := float(i - start) / RATE
			var sq := 1.0 if fmod(hz * t, 1.0) < 0.5 else -1.0
			s[i] += sq * 0.25 * exp(-t * 9.0) * smoothstep(0.0, 0.004, t)
	_peak(s, 0.7)
	_fade_end(s, 20.0)
	return wav(s)
