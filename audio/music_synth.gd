class_name MusicSynth
extends RefCounted
## The driving wasteland loop, synthesised in code (no samples to license).
## Eight bars in E minor at 124 BPM, rendered as separate layers of the same
## length so they play in lockstep and GameAudio can fade them in as a combo
## grows:
##   PAD    dark detuned chords and a drone (always on)
##   DRUMS  four-on-the-floor kick and off-beat hats
##   BASS   distorted eighth-note bass
##   PERC   snare, sixteenth hats and scrap-metal clanks
##   LEAD   a gritty pentatonic riff with echo
## Chords: Em | Em | C | C | Am | Am | B | B.

enum Layer { PAD, DRUMS, BASS, PERC, LEAD }

const RATE := 44100
const BPM := 124.0
const BARS := 8
const BEAT := 60.0 / BPM
const BAR := BEAT * 4.0

## Chord per bar as MIDI notes (root first).
const CHORDS := [
	[52, 55, 59], [52, 55, 59], [48, 52, 55], [48, 52, 55],
	[45, 48, 52], [45, 48, 52], [47, 51, 54], [47, 51, 54],
]
## Bass, per eighth note, in semitones above the chord root (an octave down).
const BASS_PATTERN := [0, 0, 12, 0, 0, 0, 12, 7]
## The lead riff for each pair of bars, per eighth note (-1 = rest).
const RIFFS := [
	[76, -1, 79, -1, 81, 83, -1, 81, 79, -1, 76, -1, 74, 76, -1, -1],
	[76, -1, 79, -1, 81, 83, -1, 84, 83, -1, 79, -1, 76, 79, -1, -1],
	[81, -1, 84, -1, 83, 81, -1, 79, 76, -1, 79, -1, 81, -1, -1, -1],
	[78, -1, 75, -1, 78, 83, -1, 81, 78, -1, 75, -1, 71, -1, -1, -1],
]
## Peak level each layer is normalised to.
const LEVELS := {
	Layer.PAD: 0.32, Layer.DRUMS: 0.55, Layer.BASS: 0.42, Layer.PERC: 0.36, Layer.LEAD: 0.3,
}


static func midi_hz(note: float) -> float:
	return 440.0 * pow(2.0, (note - 69.0) / 12.0)


static func length_seconds(bars := BARS) -> float:
	return BAR * bars


static func render(layer: Layer, bars := BARS) -> AudioStreamWAV:
	var n := int(length_seconds(bars) * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	match layer:
		Layer.PAD: _pad(s)
		Layer.DRUMS: _drums(s, bars)
		Layer.BASS: _bass(s)
		Layer.PERC: _perc(s, bars)
		Layer.LEAD: _lead(s)
	SoundBank._peak(s, LEVELS[layer])
	return SoundBank.wav(s, true)


static func _saw(phase: float) -> float:
	return 2.0 * (phase - floorf(phase)) - 1.0


static func _bar_at(t: float) -> int:
	return int(t / BAR) % BARS


# ---------------------------------------------------------------- layers

static func _pad(s: PackedFloat32Array) -> void:
	var rng := SoundBank._rng(20001)
	var phases := PackedFloat32Array()
	phases.resize(8)
	var lp := 0.0
	var lp2 := 0.0
	var dust := 0.0
	var drone := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var bar := _bar_at(t)
		var in_bar := fmod(t, BAR * 2.0)  # chords change every two bars
		var chord: Array = CHORDS[bar]
		var v := 0.0
		for k in 3:
			var hz := midi_hz(chord[k])
			phases[k * 2] += hz * 1.003 / RATE
			phases[k * 2 + 1] += hz * 0.997 / RATE
			v += _saw(phases[k * 2]) + _saw(phases[k * 2 + 1])
		# Slow swell into each chord, and a filter that breathes.
		var swell := smoothstep(0.0, 0.5, in_bar) * (0.85 + 0.15 * sin(TAU * t / BAR))
		var cut := 0.07 + 0.04 * sin(TAU * t / (BAR * 4.0))
		lp += (v * swell - lp) * cut
		lp2 += (lp - lp2) * cut
		# A low E drone and wind-like dust under it all.
		drone += midi_hz(28) / RATE
		dust += (rng.randf_range(-1.0, 1.0) - dust) * 0.04
		s[i] = lp2 * 0.3 + sin(TAU * drone) * 0.12 + dust * 0.35
	# Ease the drone's seam (the chords already restart from silence).
	var k := int(0.02 * RATE)
	for i in k:
		s[i] *= float(i) / k
		s[s.size() - 1 - i] *= float(i) / k


static func _kick(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(int(0.35 * RATE))
	var phase := 0.0
	for i in s.size():
		var t := float(i) / RATE
		phase += TAU * (48.0 + 140.0 * exp(-t * 35.0)) / RATE
		s[i] = SoundBank.sat(sin(phase) * exp(-t * 9.0) * 2.2) + rng.randf_range(-1.0, 1.0) * exp(-t * 300.0) * 0.3
	return s


static func _snare(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(int(0.3 * RATE))
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var w := rng.randf_range(-1.0, 1.0)
		lp += (w - lp) * 0.5
		s[i] = (w - lp) * exp(-t * 16.0) * 0.9 + sin(TAU * 190.0 * t) * exp(-t * 30.0) * 0.6
	return s


static func _hat(rng: RandomNumberGenerator, open: bool) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(int((0.22 if open else 0.06) * RATE))
	var prev := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var w := rng.randf_range(-1.0, 1.0)
		var hp := w - prev
		prev = w
		s[i] = hp * exp(-t * (14.0 if open else 70.0))
	return s


## A hit on scrap metal: inharmonic partials.
static func _clank(rng: RandomNumberGenerator, base: float) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(int(0.5 * RATE))
	SoundBank._ring(s, 0.0, [base, base * 2.41, base * 3.77, base * 5.93], 0.5, 9.0)
	SoundBank._noise(s, 0.0, 0.03, 0.5, 0.9, 120.0, rng, 0.0003)
	return s


static func _stamp(s: PackedFloat32Array, hit: PackedFloat32Array, at: float, gain: float) -> void:
	var start := int(at * RATE)
	for i in hit.size():
		# Wrap past the end so the loop seam carries the tail.
		s[(start + i) % s.size()] += hit[i] * gain


static func _drums(s: PackedFloat32Array, bars: int) -> void:
	var rng := SoundBank._rng(20002)
	var kick := _kick(rng)
	var hat := _hat(rng, true)
	for bar in bars:
		var t0 := bar * BAR
		for beat in 4:
			_stamp(s, kick, t0 + beat * BEAT, 1.0)
			_stamp(s, hat, t0 + beat * BEAT + BEAT * 0.5, 0.55 if beat % 2 == 0 else 0.7)
		if bar % 2 == 1:
			_stamp(s, kick, t0 + BEAT * 2.75, 0.6)  # push into the next bar


static func _perc(s: PackedFloat32Array, bars: int) -> void:
	var rng := SoundBank._rng(20003)
	var snare := _snare(rng)
	var hat := _hat(rng, false)
	var clank_hi := _clank(rng, 610.0)
	var clank_lo := _clank(rng, 233.0)
	for bar in bars:
		var t0 := bar * BAR
		_stamp(s, snare, t0 + BEAT, 1.0)
		_stamp(s, snare, t0 + BEAT * 3.0, 1.0)
		for k in 16:
			var accent := 0.9 if k % 4 == 2 else 0.55
			_stamp(s, hat, t0 + k * BEAT * 0.25 + rng.randf_range(0.0, 0.004), accent)
		_stamp(s, clank_hi, t0 + BEAT * 3.75, 0.35)
		if bar % 2 == 1:
			_stamp(s, clank_lo, t0 + BEAT * 1.5, 0.5)
			_stamp(s, snare, t0 + BEAT * 3.75, 0.45)


static func _bass(s: PackedFloat32Array) -> void:
	var phase := 0.0
	var sub := 0.0
	var lp := 0.0
	var eighth := BEAT * 0.5
	for i in s.size():
		var t := float(i) / RATE
		var bar := _bar_at(t)
		var step := int(fmod(t, BAR) / eighth)
		var in_note := fmod(t, eighth)
		var note: float = CHORDS[bar][0] - 12 + BASS_PATTERN[step]
		var hz := midi_hz(note)
		phase += hz / RATE
		sub += hz * 0.5 / RATE
		var env := exp(-in_note * 6.0) * smoothstep(0.0, 0.004, in_note) * smoothstep(eighth, eighth - 0.01, in_note)
		var cut := 0.05 + 0.3 * exp(-in_note * 18.0)
		lp += (_saw(phase) - lp) * cut
		var v := SoundBank.sat(lp * 3.0) * 0.9 + sin(TAU * sub) * 0.35
		s[i] = v * (0.35 + 0.65 * env)
	# The oscillators restart at the loop point: dip through zero there.
	var k := int(0.003 * RATE)
	for i in k:
		s[i] *= float(i) / k
		s[s.size() - 1 - i] *= float(i) / k


static func _lead(s: PackedFloat32Array) -> void:
	var dry := PackedFloat32Array()
	dry.resize(s.size())
	var phase := 0.0
	var phase2 := 0.0
	var lp := 0.0
	var eighth := BEAT * 0.5
	var last_note := 64.0
	for i in s.size():
		var t := float(i) / RATE
		var bar := _bar_at(t)
		var riff: Array = RIFFS[(bar / 2) % RIFFS.size()]
		var step := int(fmod(t, BAR * 2.0) / eighth)
		var in_note := fmod(t, eighth)
		var note: int = riff[step]
		var on := note >= 0
		if on:
			last_note = note
		var hz := midi_hz(last_note)
		# A touch of vibrato and a detuned second voice.
		hz *= 1.0 + 0.004 * sin(TAU * 5.5 * t)
		phase += hz / RATE
		phase2 += hz * 1.006 / RATE
		var sq := (1.0 if fmod(phase, 1.0) < 0.42 else -1.0) * 0.6 + _saw(phase2) * 0.4
		var env := 0.0
		if on:
			env = exp(-in_note * 4.0) * smoothstep(0.0, 0.006, in_note)
		lp += (sq * env - lp) * 0.18
		dry[i] = SoundBank.sat(lp * 2.0)
	# Dotted-eighth echo, wrapping round the loop.
	var d := int(BEAT * 0.75 * RATE)
	for i in s.size():
		s[i] = dry[i] + dry[(i - d + s.size()) % s.size()] * 0.38 + dry[(i - 2 * d + 2 * s.size()) % s.size()] * 0.16
