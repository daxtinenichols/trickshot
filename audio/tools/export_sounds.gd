extends SceneTree
## Writes every GameAudio sound, and the music at each combo stage, as WAV
## files so they can be auditioned outside the game:
##   godot --headless --path . -s res://audio/tools/export_sounds.gd -- <out_dir>
## Runs after the autoloads (deferred), so GameAudio's bank is built.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://sounds"
	DirAccess.make_dir_recursive_absolute(out)
	var audio: Node = root.get_node("/root/GameAudio")
	for sound_name: String in audio.sounds:
		var entry: Variant = audio.sounds[sound_name]
		var list: Array = entry if entry is Array else [entry]
		for i in list.size():
			(list[i] as AudioStreamWAV).save_to_wav("%s/%s_%d.wav" % [out, sound_name, i])
	var layers: Array[PackedFloat32Array] = []
	for layer in MusicSynth.Layer.values():
		var stream := MusicSynth.render(layer)
		stream.save_to_wav("%s/layer_%s.wav" % [out, MusicSynth.Layer.keys()[layer].to_lower()])
		layers.append(_decode(stream))
	# The music as a combo grows: idle, a combo running, 3 tricks, 5 tricks.
	for stage: int in [0, 1, 3, 5]:
		var gains: PackedFloat32Array = audio.layer_targets(stage)
		var mix := PackedFloat32Array()
		mix.resize(layers[0].size())
		for l in layers.size():
			var layer := layers[l]  # one copy, not one per sample
			var g := gains[l]
			for i in mix.size():
				mix[i] += layer[i] * g
		for i in mix.size():
			mix[i] = SoundBank.sat(mix[i] * 1.2)
		SoundBank.wav(mix).save_to_wav("%s/music_combo_%d.wav" % [out, stage])
	print("wrote sounds to ", out)
	quit()


static func _decode(w: AudioStreamWAV) -> PackedFloat32Array:
	var data := w.data  # the getter copies, so read it once
	var out := PackedFloat32Array()
	out.resize(data.size() / 2)
	for i in out.size():
		out[i] = data.decode_s16(i * 2) / 32767.0
	return out
