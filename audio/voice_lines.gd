extends RefCounted
## Finds the spoken clip for a line of dialogue. Load by path:
##   const Voices := preload("res://audio/voice_lines.gd")
##
## Clips live in audio/voices/<source>/<who>/<key>.ogg, where <key> is the
## first 12 hex digits of the md5 of the line's text, so changing a line's
## words simply leaves it silent (subtitles only) until it is voiced again.
## A recorded take in recorded/ wins over the synthetic one in tts/; both
## are made and named by audio/tools/make_voices.py (see script.csv).

const ROOT := "res://audio/voices/"
const SOURCES := ["recorded", "tts"]


static func key(line: String) -> String:
	return line.md5_text().substr(0, 12)


## The clip for `who` saying `line`, or null if it hasn't been voiced.
static func stream_for(who: String, line: String) -> AudioStream:
	if who == "" or line == "":
		return null
	for source: String in SOURCES:
		var path := "%s%s/%s/%s.ogg" % [ROOT, source, who, key(line)]
		if ResourceLoader.exists(path):
			return load(path) as AudioStream
	return null
