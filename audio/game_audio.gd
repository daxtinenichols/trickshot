extends Node
## Autoload "GameAudio": the music and every movement and world sound.
##
## It only listens. It follows the newest Player and ComboTracker added to
## the tree, reads their signals and public state, and plays sounds; it never
## changes anything the simulation reads, so runs stay deterministic with
## sound on or off. (The gun's own sounds belong to the art's GunLook.)
##
## - Footsteps speed up with pace and change with the ground (concrete,
##   gritty asphalt, ringing metal), and run along the wall on a wallrun.
## - Jumps, landings graded by how hard you hit, slides, rolls, vaults,
##   mantles, kicks, doors, glass, wall bonks and flips each have a
##   sound; wind rises with speed.
## - Music: an eight-bar loop whose layers come in as a combo grows (drums
##   and bass when a combo starts, percussion at 3 tricks, the lead at 5).
##   Bails cut it back; banking a combo rings out.
## - Dead Air: the run goes out live on a raider warlord's radio show. With
##   no combo running the music plays "on air", band-limited with a crackle
##   under it; a combo opens it up to full sound. Combo milestones get a
##   broadcast jingle, and play_radio() puts a voice line on the radio,
##   keyed with static, with the music ducked under it (RadioFeed voices
##   each line it shows; clips come from audio/voice_lines.gd).
## - Slow-mo muffles and deepens everything, matching the vignette.
##
## Buses: Master > Music, SFX and Radio. set_music_volume()/set_sfx_volume()
## take 0..1.

# Loaded by path, not by class name: an autoload that names a class the
# editor hasn't registered yet (fresh files, before a project reload) fails
# to parse and takes the game down with it.
const Synth := preload("res://audio/music_synth.gd")
const Bank := preload("res://audio/sound_bank.gd")

const VARIATIONS := 6
const POOL_SIZE := 20
const WORLD_POOL_SIZE := 8

## Combo size (distinct tricks) at which each music layer comes in. The pad
## always plays; drums play quietly with no combo running.
const LAYER_FROM := {
	Synth.Layer.DRUMS: 1, Synth.Layer.BASS: 1,
	Synth.Layer.PERC: 3, Synth.Layer.LEAD: 5,
}
const IDLE_DRUMS := 0.5
## Bump to force a rebuild of everyone's cached sounds.
const CACHE_VERSION := "1"
## Combo sizes that get a radio jingle (levels 1, 2, 3).
const MILESTONES := [3, 5, 8]

var enabled := true
var cache_path := "user://audio_cache.bin"
var music_volume := 0.7
var sfx_volume := 1.0

var player: Player
var combo: ComboTracker
## The most recent sounds played, newest last (for tests and debugging).
var heard: Array[String] = []

## Sound streams by name; lists hold the variations. Empty until built.
var sounds := {}
var sounds_ready := false
## Music layers, once rendered (in the background, at startup).
var music_ready := false
var music: Array[AudioStreamPlayer] = []
## Where each music layer is heading and where it is (0..1).
var layer_target := PackedFloat32Array()
var layer_gain := PackedFloat32Array()

## 0 = normal time, 1 = slow-mo at its floor. Drives the muffling.
var slowed := 0.0
var _was_slow := false

## Headless runs (tests, CI) have no audio device, and the dummy mixer
## never frees a playback, so nothing actually starts there: sounds are only
## logged and loops only track their levels.
var _headless := DisplayServer.get_name() == "headless"
var _pool: Array[AudioStreamPlayer] = []
var _world_pool: Array[AudioStreamPlayer3D] = []
var _next := 0
var _next_world := 0
var _wind_low: AudioStreamPlayer
var _wind_high: AudioStreamPlayer
var _slide: AudioStreamPlayer
var _slide_surface := &""
var _slide_gain := 0.0
var _step_phase := 0.0
var _footsteps := 0
## A landing waits for the end of the tick, to know whether it turned into a
## roll (which softens it).
var _pending_fall := -1.0
var _pending_roll := false
var _bail_duck := 0.0
var _music_task := -1
var _music_streams: Array = []
var _lowpass: AudioEffectLowPassFilter
## The music's "on air" filter: 1 = through the radio, 0 = full sound.
var on_air := 1.0
var _air_hp: AudioEffectHighPassFilter
var _air_lp: AudioEffectLowPassFilter
var _crackle: AudioStreamPlayer
var _radio: AudioStreamPlayer
var _radio_bus := -1
var _tape_bus := -1
var _milestone := 0
var _voice_duck := 0.0
var _reverb: AudioEffectReverb
var _music_bus := -1
var _sfx_bus := -1
## Window/door state last seen, so breaking and opening are heard however
## they happen (kicked, shot, run through).
var _broken := {}
var _open := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_pool.append(p)
	for i in WORLD_POOL_SIZE:
		var p := AudioStreamPlayer3D.new()
		p.bus = &"SFX"
		p.unit_size = 6.0
		p.max_distance = 80.0
		add_child(p)
		_world_pool.append(p)
	_wind_low = _loop()
	_wind_high = _loop()
	_slide = _loop()
	_crackle = _loop()
	_crackle.bus = &"Radio"
	_radio = AudioStreamPlayer.new()
	_radio.bus = &"Radio"
	add_child(_radio)
	layer_target.resize(Synth.Layer.size())
	layer_gain.resize(Synth.Layer.size())
	get_tree().node_added.connect(_on_node_added)
	if _headless:
		# Tests need the sounds straight away, and render music themselves.
		_set_sounds(build_sounds())
	else:
		_music_task = WorkerThreadPool.add_task(_load_or_build, false, "Build game audio")


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
	if _music_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_music_task)
		_music_task = -1
	# Let go of every stream and playback, so quitting mid-sound leaks nothing.
	for c in get_children():
		if c is AudioStreamPlayer or c is AudioStreamPlayer3D:
			c.stop()
			c.stream = null
	sounds.clear()
	_music_streams.clear()


func _setup_buses() -> void:
	_lowpass = AudioEffectLowPassFilter.new()
	_lowpass.cutoff_hz = 20000.0
	_lowpass.resonance = 0.6
	AudioServer.add_bus_effect(0, _lowpass)
	_music_bus = _ensure_bus(&"Music")
	_sfx_bus = _ensure_bus(&"SFX")
	_air_hp = AudioEffectHighPassFilter.new()
	_air_hp.cutoff_hz = 380.0
	_air_lp = AudioEffectLowPassFilter.new()
	_air_lp.cutoff_hz = 3200.0
	AudioServer.add_bus_effect(_music_bus, _air_hp)
	AudioServer.add_bus_effect(_music_bus, _air_lp)
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = -1.0
	AudioServer.add_bus_effect(_music_bus, limiter)
	# The radio: a narrow, slightly overdriven band.
	_radio_bus = _ensure_bus(&"Radio")
	var hp := AudioEffectHighPassFilter.new()
	hp.cutoff_hz = 450.0
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 3000.0
	var drive := AudioEffectDistortion.new()
	drive.mode = AudioEffectDistortion.MODE_OVERDRIVE
	drive.drive = 0.35
	drive.post_gain = -4.0
	for fx: AudioEffect in [hp, lp, drive]:
		AudioServer.add_bus_effect(_radio_bus, fx)
	# Old tapes (RadioFeed "fx": "tape"): a narrower band, more hiss and
	# drive, and a slow wobble like a stretched reel.
	_tape_bus = _ensure_bus(&"RadioTape")
	var thp := AudioEffectHighPassFilter.new()
	thp.cutoff_hz = 700.0
	var tlp := AudioEffectLowPassFilter.new()
	tlp.cutoff_hz = 2300.0
	var tdrive := AudioEffectDistortion.new()
	tdrive.mode = AudioEffectDistortion.MODE_OVERDRIVE
	tdrive.drive = 0.5
	tdrive.post_gain = -5.0
	var wow := AudioEffectChorus.new()
	wow.voice_count = 1
	wow.dry = 0.4
	wow.wet = 0.6
	wow.set_voice_rate_hz(0, 0.6)
	wow.set_voice_depth_ms(0, 3.0)
	for fx: AudioEffect in [thp, tlp, tdrive, wow]:
		AudioServer.add_bus_effect(_tape_bus, fx)
	_reverb = AudioEffectReverb.new()
	_reverb.room_size = 0.7
	_reverb.damping = 0.6
	_reverb.dry = 1.0
	_reverb.wet = 0.0
	AudioServer.add_bus_effect(_sfx_bus, _reverb)
	set_music_volume(music_volume)
	set_sfx_volume(sfx_volume)


func _ensure_bus(bus_name: StringName) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		idx = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, &"Master")
	return idx


func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	AudioServer.set_bus_volume_db(_music_bus, linear_to_db(maxf(music_volume, 0.0001)))
	AudioServer.set_bus_mute(_music_bus, music_volume <= 0.0)


func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	for bus in [_sfx_bus, _radio_bus, _tape_bus]:
		if bus >= 0:
			AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(sfx_volume, 0.0001)))
			AudioServer.set_bus_mute(bus, sfx_volume <= 0.0)


## Every sound effect, by name (lists hold the variations). Pure, so it can
## run on a worker thread.
static func build_sounds() -> Dictionary:
	var out := {}
	for surface in Bank.SURFACES:
		out["step_%s" % surface] = _variations(func(v: int) -> AudioStreamWAV: return Bank.footstep(surface, v))
		out["land_%s" % surface] = _variations(func(v: int) -> AudioStreamWAV: return Bank.landing(surface, v), 3)
	out.debris = _variations(Bank.debris, 3)
	out.jump = _variations(Bank.jump, 4)
	out.hand = _variations(Bank.hand_plant, 4)
	out.whoosh = _variations(func(v: int) -> AudioStreamWAV: return Bank.whoosh(v), 4)
	out.roll = _variations(Bank.roll, 3)
	out.bonk = _variations(Bank.bonk, 2)
	out.kick = _variations(Bank.kick_hit, 3)
	out.door_bang = _variations(Bank.door_bang, 2)
	out.door_close = _variations(Bank.door_close, 2)
	out.glass = _variations(Bank.glass, 3)
	out.slow_down = [Bank.slow_mo(true)]
	out.slow_up = [Bank.slow_mo(false)]
	out.bank = [Bank.bank_chime(false)]
	out.bank_big = [Bank.bank_chime(true)]
	out.bail = [Bank.bail_sting()]
	out.radio_key = _variations(func(v: int) -> AudioStreamWAV: return Bank.radio_static(false, v), 3)
	out.radio_crackle = Bank.radio_static(true)
	for level in MILESTONES.size():
		out["sting_%d" % (level + 1)] = [Bank.radio_sting(level + 1)]
	out.wind_low = Bank.wind_loop(false)
	out.wind_high = Bank.wind_loop(true)
	out.slide_concrete = Bank.slide_loop(&"concrete")
	out.slide_asphalt = Bank.slide_loop(&"asphalt")
	out.slide_metal = Bank.slide_loop(&"metal")
	return out


static func _variations(make: Callable, count := VARIATIONS) -> Array:
	var out := []
	for v in count:
		out.append(make.call(v))
	return out


func _loop() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = &"SFX"
	p.volume_db = -80.0
	add_child(p)
	return p


# ---------------------------------------------------------------- loading

## Synthesising everything takes a few seconds, so it runs on a worker
## thread and is cached in user:// for the next launch. The game starts
## straight away; sounds and then the music fade in when ready. The cache is
## keyed on the synth code, so changing a sound rebuilds it.
func _load_or_build() -> void:
	var key := cache_key()
	var cached := _read_cache(key)
	var bank: Dictionary = cached.get("sounds", {})
	if bank.is_empty():
		bank = build_sounds()
	_set_sounds.call_deferred(bank)
	var layers: Array = cached.get("music", [])
	if layers.size() != Synth.Layer.size():
		layers = []
		for layer in Synth.Layer.values():
			layers.append(Synth.render(layer))
	_music_streams = layers
	_start_music.call_deferred()
	if cached.is_empty():
		_write_cache(key, bank, layers)


static func cache_key() -> String:
	var parts := [CACHE_VERSION]
	for path in ["res://audio/sound_bank.gd", "res://audio/music_synth.gd", "res://audio/game_audio.gd"]:
		parts.append(FileAccess.get_md5(path))
	return ":".join(parts)


static func _pack(stream: AudioStreamWAV) -> Array:
	return [stream.data, stream.loop_mode == AudioStreamWAV.LOOP_FORWARD]


static func _unpack(a: Array) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = Bank.RATE
	w.data = a[0]
	if a[1]:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = w.data.size() / 2
	return w


func _write_cache(key: String, bank: Dictionary, layers: Array) -> void:
	var packed := {}
	for sound_name: String in bank:
		var entry: Variant = bank[sound_name]
		packed[sound_name] = (entry as Array).map(_pack) if entry is Array else _pack(entry)
	var f := FileAccess.open(cache_path, FileAccess.WRITE)
	if f:
		f.store_var({"key": key, "sounds": packed, "music": layers.map(_pack)})


func _read_cache(key: String) -> Dictionary:
	if not FileAccess.file_exists(cache_path):
		return {}
	var f := FileAccess.open(cache_path, FileAccess.READ)
	var d: Variant = f.get_var() if f else null
	if not (d is Dictionary) or d.get("key") != key:
		return {}
	var bank := {}
	for sound_name: String in d.sounds:
		var entry: Array = d.sounds[sound_name]
		bank[sound_name] = entry.map(_unpack) if entry.size() > 0 and entry[0] is Array else _unpack(entry)
	return {"sounds": bank, "music": (d.music as Array).map(_unpack)}


func _set_sounds(bank: Dictionary) -> void:
	sounds = bank
	_wind_low.stream = sounds.wind_low
	_wind_high.stream = sounds.wind_high
	_slide.stream = sounds["slide_%s" % _slide_surface] if _slide_surface != &"" else sounds.slide_concrete
	_crackle.stream = sounds.radio_crackle
	sounds_ready = true


# ---------------------------------------------------------------- music

func _start_music() -> void:
	if not is_inside_tree() or music_ready:
		return
	print_verbose("GameAudio: music ready")
	for stream: AudioStream in _music_streams:
		var p := AudioStreamPlayer.new()
		p.bus = &"Music"
		p.stream = stream
		p.volume_db = -80.0
		add_child(p)
		music.append(p)
	# Start together so the layers stay in lockstep.
	for p in music:
		if not _headless:
			p.play()
	music_ready = true


## How loud each layer should be (0..1) for a combo of `tricks` distinct
## tricks.
static func layer_targets(tricks: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(Synth.Layer.size())
	out[Synth.Layer.PAD] = 1.0
	for layer: int in LAYER_FROM:
		out[layer] = 1.0 if tricks >= LAYER_FROM[layer] else 0.0
	if tricks <= 0:
		out[Synth.Layer.DRUMS] = IDLE_DRUMS
	return out


## Puts a sound (a voice line) out on the warlord's radio: keyed on and off
## with static, with the music ducked under it. `interference` breaks it up
## with extra bursts of static, for Echo's coded messages slipping through.
func play_radio(stream: AudioStream, volume_db := 0.0, interference := false, fx := "") -> void:
	if not enabled or stream == null:
		return
	_on_radio_done()
	# An old tape: thinner and wobblier than the live radio.
	_radio.bus = &"RadioTape" if fx == "tape" else &"Radio"
	if interference:
		for k in 3:
			get_tree().create_timer(randf_range(0.2, maxf(stream.get_length(), 0.3)), true, false, true).timeout.connect(_on_radio_done)
	_radio.stream = stream
	_radio.volume_db = volume_db
	if not _headless:
		_radio.play()
	_voice_duck = stream.get_length() + 0.3
	if not _radio.finished.is_connected(_on_radio_done):
		_radio.finished.connect(_on_radio_done)


## Cuts the radio voice off (the mission it belonged to has gone).
func stop_radio() -> void:
	if _radio != null and _radio.playing:
		_radio.stop()
		_voice_duck = 0.0


## A voice shouted out in the world by `node` (a raider's taunt), following
## it around. Skipped while that node is still mid-line.
func play_voice_on(node: Node3D, stream: AudioStream, volume_db := 0.0) -> void:
	if not enabled or stream == null or node == null or not node.is_inside_tree():
		return
	var old := node.get_node_or_null(^"Voice") as AudioStreamPlayer3D
	if old != null and old.playing:
		return
	if old != null:
		old.free()
	var p := AudioStreamPlayer3D.new()
	p.name = &"Voice"
	p.stream = stream
	p.volume_db = volume_db
	p.unit_size = 10.0
	p.position = Vector3(0, 1.6, 0)
	p.bus = &"SFX"
	node.add_child(p)
	p.finished.connect(p.queue_free)
	if not _headless:
		p.play()


func _on_radio_done() -> void:
	var p := play("radio_key", -12.0)
	if p:
		p.bus = &"Radio"


## 1 with no combo (the music is "on air"), easing to 0 as one runs.
static func on_air_target(tricks: int) -> float:
	return 1.0 if tricks <= 0 else 0.0


func _update_music(real_delta: float) -> void:
	var tricks := combo.multiplier() if is_instance_valid(combo) else 0
	layer_target = layer_targets(tricks)
	# Milestone jingles, once each per combo.
	if tricks < _milestone_floor():
		_milestone = 0
	while _milestone < MILESTONES.size() and tricks >= MILESTONES[_milestone]:
		_milestone += 1
		var p := play("sting_%d" % _milestone, -8.0)
		if p:
			p.bus = &"Radio"
	var air_want := on_air_target(tricks)
	on_air = move_toward(on_air, air_want, real_delta * (3.0 if air_want < on_air else 0.5))
	_air_hp.cutoff_hz = lerpf(10.0, 380.0, on_air)
	_air_lp.cutoff_hz = 20000.0 * pow(3200.0 / 20000.0, on_air)
	_crackle.volume_db = linear_to_db(maxf(on_air, 0.0001)) - 30.0
	if music_ready and on_air > 0.01 and _crackle.stream and not _crackle.playing and not _headless:
		_crackle.play()
	_voice_duck = maxf(_voice_duck - real_delta, 0.0)
	_bail_duck = maxf(_bail_duck - real_delta, 0.0)
	for i in layer_gain.size():
		var want := layer_target[i]
		if _bail_duck > 0.0 and i != Synth.Layer.PAD:
			want = 0.0
		# Layers come in fast and leave slowly.
		var rate := 2.5 if want > layer_gain[i] else 0.6
		layer_gain[i] = move_toward(layer_gain[i], want, rate * real_delta)
	if not music_ready:
		return
	var paused := get_tree().paused
	for i in music.size():
		music[i].volume_db = linear_to_db(maxf(layer_gain[i], 0.0001)) - (6.0 if paused else 0.0) - (8.0 if _voice_duck > 0.0 else 0.0)
		music[i].pitch_scale = lerpf(1.0, 0.82, slowed)


# ---------------------------------------------------------------- binding

func _on_node_added(node: Node) -> void:
	if node is Player:
		bind_player(node)
	elif node is ComboTracker:
		bind_combo(node)


func bind_player(p: Player) -> void:
	if is_instance_valid(player):
		player.state_changed.disconnect(_on_state_changed)
		player.landed.disconnect(_on_landed)
		player.trick.disconnect(_on_trick)
		player.respawned.disconnect(_on_respawned)
	player = p
	if p == null:
		return
	p.state_changed.connect(_on_state_changed)
	p.landed.connect(_on_landed)
	p.trick.connect(_on_trick)
	p.respawned.connect(_on_respawned)
	_step_phase = 0.0
	_broken.clear()
	_open.clear()


func bind_combo(c: ComboTracker) -> void:
	if is_instance_valid(combo):
		combo.bailed.disconnect(_on_bailed)
		combo.finished.disconnect(_on_finished)
	combo = c
	if c == null:
		return
	c.bailed.connect(_on_bailed)
	c.finished.connect(_on_finished)


# ---------------------------------------------------------------- playing

## Plays one variation of a sound. `pitch` is on top of a little random
## spread and the slow-mo drop.
func play(sound_name: String, volume_db := 0.0, pitch := 1.0) -> AudioStreamPlayer:
	if not enabled or not sounds.has(sound_name):
		return null
	_log(sound_name)
	var list: Array = sounds[sound_name]
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = list[randi() % list.size()]
	p.volume_db = volume_db
	p.pitch_scale = maxf(pitch * randf_range(0.95, 1.05) * lerpf(1.0, 0.72, slowed), 0.05)
	if not _headless:
		p.play()
	return p


func _log(sound_name: String) -> void:
	heard.append(sound_name)
	if heard.size() > 64:
		heard.remove_at(0)


## Plays a sound out in the world (glass, doors).
func play_at(sound_name: String, pos: Vector3, volume_db := 0.0) -> void:
	if not enabled or not sounds.has(sound_name):
		return
	_log(sound_name)
	var list: Array = sounds[sound_name]
	var p := _world_pool[_next_world]
	_next_world = (_next_world + 1) % _world_pool.size()
	p.stream = list[randi() % list.size()]
	p.volume_db = volume_db
	p.pitch_scale = randf_range(0.94, 1.06) * lerpf(1.0, 0.72, slowed)
	if p.is_inside_tree():
		p.global_position = pos
	if not _headless:
		p.play()


## What the ground (or wall) under a direction from the player is made of.
func surface_under(dir := Vector3.DOWN) -> StringName:
	if not is_instance_valid(player) or not player.is_inside_tree():
		return &"concrete"
	var from := player.global_position + Vector3.UP * 0.5
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 1.6, 1)
	q.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	return surface_of(hit.get("collider"))


static func surface_of(collider: Object) -> StringName:
	if collider == null:
		return &"concrete"
	var kind := ""
	if collider.has_meta("look"):
		kind = str(collider.get_meta("look"))
	elif collider.has_meta("kind"):
		kind = str(collider.get_meta("kind"))
	if kind in ["WALLRUN", "SLIDE", "SURFACE"] or (collider is Node and (collider as Node).is_in_group("runnable")):
		return &"metal"
	if kind == "FLOOR":
		return &"asphalt"
	return &"concrete"


## Footsteps per second at a running speed (m/s): a jog's cadence up to a
## flat-out sprint's.
static func step_rate(speed: float, top_speed: float) -> float:
	return lerpf(2.0, 4.6, clampf((speed - 1.0) / maxf(top_speed * 1.3 - 1.0, 0.1), 0.0, 1.0))


## Landing loudness (dB) and pitch from how fast you hit the ground.
static func landing_grade(fall_speed: float, rolled: bool) -> Vector2:
	var k := clampf((fall_speed - 2.0) / 16.0, 0.0, 1.0)
	var db := lerpf(-20.0, 0.0, k) - (6.0 if rolled else 0.0)
	return Vector2(db, lerpf(1.15, 0.75, k))


# ---------------------------------------------------------------- events

func _on_state_changed(from: Player.State, to: Player.State) -> void:
	var S := Player.State
	match to:
		S.AIR:
			if from in [S.GROUND, S.CROUCH, S.SLIDE, S.ROLL, S.SURFACE] and player.velocity.y > 2.0:
				play("jump", -6.0)
				play("whoosh", -16.0, 1.2)
		S.SLIDE:
			play("whoosh", -12.0, 0.8)
			_start_slide()
		S.WALLRUN:
			play("hand", -8.0)
			play("step_metal", -8.0)
			_step_phase = 0.5
		S.WALLCLIMB:
			play("hand", -6.0)
		S.VAULT:
			play("hand", -4.0)
			play("whoosh", -10.0, 1.1)
		S.MANTLE:
			play("hand", -3.0, 0.9)
		S.ROLL:
			_pending_roll = true
			play("roll", -4.0)
		S.STUN:
			play("bonk", -3.0)
	if to in [S.GROUND, S.SURFACE] and from != S.SLIDE:
		_step_phase = 0.35  # first step lands a beat after touching down


func _on_landed(fall_speed: float) -> void:
	_pending_fall = maxf(_pending_fall, fall_speed)


func _resolve_landing() -> void:
	if _pending_fall < 0.0:
		return
	var fall := _pending_fall
	var rolled := _pending_roll
	_pending_fall = -1.0
	_pending_roll = false
	if fall < 1.0:
		return
	var g := landing_grade(fall, rolled)
	play("land_%s" % surface_under(), g.x, g.y)
	if fall > 9.0 and not rolled:
		play("debris", g.x - 4.0)


func _on_trick(trick_name: StringName, info: Dictionary) -> void:
	match trick_name:
		&"wall_jump", &"wall_hop", &"kick_off", &"slide_jump":
			play("jump", -5.0, 1.05)
			play("whoosh", -12.0, 1.15)
		&"hop":
			play("jump", -8.0, 1.1)
		&"backflip", &"frontflip", &"sideflip":
			play("whoosh", -9.0, 0.9 + 0.02 * float(info.get("speed", 0.0)))
		&"kick":
			play("kick", -3.0)
		&"kick_miss":
			play("whoosh", -9.0, 1.3)
		&"wall_impact":
			play("bonk", lerpf(-12.0, -2.0, clampf(float(info.get("speed", 0.0)) / 12.0, 0.0, 1.0)))
		&"crash":
			play("debris", -6.0)
		_:
			if String(trick_name).begins_with("spin_"):
				play("whoosh", -11.0, 1.2)


func _on_respawned() -> void:
	_slide_gain = 0.0
	_slide.stop()
	_pending_fall = -1.0
	_pending_roll = false
	_step_phase = 0.0
	play("whoosh", -14.0, 0.7)


func _on_bailed(_points: int, reason: StringName) -> void:
	if reason == &"respawn":
		return
	_bail_duck = 0.6
	play("bail", -8.0)


func _on_finished(summary: Dictionary) -> void:
	# A banked combo rings out, brighter the bigger it was; a kill gets the
	# full chord.
	var tricks := int(summary.get("multiplier", 1))
	var kill: bool = summary.get("reason", &"") == &"kill"
	play("bank_big" if kill or tricks >= 4 else "bank", -6.0 if kill else -10.0)


func _start_slide() -> void:
	var surface := surface_under()
	if surface != _slide_surface:
		_slide_surface = surface
		_slide.stream = sounds.get("slide_%s" % surface)
	if _slide.stream and not _slide.playing and not _headless:
		_slide.play(randf() * 1.5)


# ---------------------------------------------------------------- tick

func _physics_process(delta: float) -> void:
	if not enabled or get_tree().paused or not is_instance_valid(player) or not player.is_inside_tree():
		return
	var S := Player.State
	var state := player.state
	var top := player.tuning.top_speed if player.tuning else 11.5
	var speed := player.horizontal_speed()
	match state:
		S.GROUND, S.CROUCH, S.SURFACE:
			if state == S.SURFACE:
				speed = player.velocity.length()
			if speed > 0.8:
				_step_phase += step_rate(speed, top) * delta * (0.8 if state == S.CROUCH else 1.0)
				if _step_phase >= 1.0:
					_step_phase -= 1.0
					var dir := -player.body_up() if state == S.SURFACE else Vector3.DOWN
					var vol := lerpf(-16.0, -5.0, clampf(speed / top, 0.0, 1.0)) - (6.0 if state == S.CROUCH else 0.0)
					play("step_%s" % surface_under(dir), vol)
					_footsteps += 1
		S.WALLRUN:
			_step_phase += step_rate(player.wallrun_speed(), top) * 1.1 * delta
			if _step_phase >= 1.0:
				_step_phase -= 1.0
				play("step_%s" % surface_under(-player.wall_normal()), -7.0, 1.05)
				_footsteps += 1
		S.WALLCLIMB:
			_step_phase += 3.6 * delta
			if _step_phase >= 1.0:
				_step_phase -= 1.0
				play("hand" if _footsteps % 2 == 0 else "step_%s" % surface_under(-player.wall_normal()), -9.0)
				_footsteps += 1
	_watch_world()


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.01)
	_resolve_landing()
	_update_slow_mo(real)
	_update_music(real)
	if not enabled or not is_instance_valid(player) or not player.is_inside_tree():
		_wind_low.volume_db = -80.0
		_wind_high.volume_db = -80.0
		_slide.volume_db = -80.0
		return
	var top := player.tuning.top_speed if player.tuning else 11.5
	var paused := get_tree().paused
	# Wind: a low rumble from a run, a hiss joining it toward top speed, more
	# of both in the air.
	var v := 0.0 if paused else player.velocity.length() / top
	var air := 3.0 if player.state == Player.State.AIR else 0.0
	_set_loop(_wind_low, clampf(v, 0.0, 1.6) * 0.55, -26.0 + air, lerpf(0.8, 1.3, clampf(v, 0.0, 1.5) / 1.5))
	_set_loop(_wind_high, clampf(v - 0.6, 0.0, 1.0), -30.0 + air, lerpf(0.9, 1.25, clampf(v - 0.6, 0.0, 1.0)))
	# Slide scrape follows speed; fades out quickly when you stand up.
	var sliding := not paused and player.is_sliding()
	var want := clampf(player.horizontal_speed() / top, 0.2, 1.2) if sliding else 0.0
	_slide_gain = move_toward(_slide_gain, want, real * (8.0 if want > _slide_gain else 4.0))
	_set_loop(_slide, _slide_gain, -10.0, lerpf(0.8, 1.2, clampf(_slide_gain, 0.0, 1.0)))
	if _slide_gain <= 0.0 and _slide.playing:
		_slide.stop()


func _set_loop(p: AudioStreamPlayer, gain: float, db: float, pitch: float) -> void:
	p.volume_db = linear_to_db(maxf(gain, 0.0001)) + db
	p.pitch_scale = maxf(pitch * lerpf(1.0, 0.75, slowed), 0.05)
	if gain > 0.001 and p.stream and not p.playing and p != _slide and not _headless:
		p.play(randf() * 2.0)


## Slow-mo: a low-pass on everything plus a little reverb, eased with time
## itself, and a deep sweep as it kicks in and lets go.
func _milestone_floor() -> int:
	return MILESTONES[_milestone - 1] if _milestone > 0 else 0


func _update_slow_mo(_real_delta: float) -> void:
	var slow_mo := get_node_or_null(^"/root/SlowMo")
	var s := 1.0
	if slow_mo:
		s = slow_mo.speed
	slowed = clampf((1.0 - s) / (1.0 - 0.4), 0.0, 1.0)
	var paused := get_tree().paused
	var muffle := maxf(slowed, 0.55 if paused else 0.0)
	_lowpass.cutoff_hz = 20000.0 * pow(1000.0 / 20000.0, muffle)
	_reverb.wet = 0.22 * slowed
	var is_slow: bool = slow_mo != null and slow_mo.is_active()
	if is_slow != _was_slow:
		_was_slow = is_slow
		play("slow_down" if is_slow else "slow_up", -6.0, 1.0 / lerpf(1.0, 0.72, slowed))


## Glass breaking and doors opening, however it happened.
func _watch_world() -> void:
	for w in get_tree().get_nodes_in_group("windows"):
		var broken: bool = w.get("is_broken") == true
		var id := w.get_instance_id()
		if broken and not _broken.get(id, false):
			play_at("glass", (w as Node3D).global_position + Vector3.UP * 0.6)
		_broken[id] = broken
	for d in get_tree().get_nodes_in_group("doors"):
		var open: bool = d.get("is_open") == true
		var id := d.get_instance_id()
		var was: bool = _open.get(id, open)
		if open and not was:
			play_at("door_bang", (d as Node3D).global_position + Vector3.UP * 1.1)
		elif was and not open:
			play_at("door_close", (d as Node3D).global_position + Vector3.UP * 1.1, -6.0)
		_open[id] = open
