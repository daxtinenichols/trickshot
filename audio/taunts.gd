extends RefCounted
## What enemies shout when they hit you, by faction (the Static's raiders
## and the Ward's troopers never share lines). Load by path:
##   const Taunts := preload("res://audio/taunts.gd")
##
## The lines live in audio/voices/taunts.json. Each faction's lines are
## dealt out in a shuffled order shared by every enemy of that faction, so
## a line only comes round again after all the others, and never twice in a
## row. Presentation only: its own random numbers, nothing from the sim.

const PATH := "res://audio/voices/taunts.json"

static var _data := {}
static var _bags := {}
static var _last := {}
static var _rng := RandomNumberGenerator.new()


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary:
			_data = parsed
	return _data


## Every faction's lines: {faction: {"voices": [...], "lines": [...]}}.
static func factions() -> Dictionary:
	var out := {}
	for k: String in data():
		if not k.begins_with("_"):
			out[k] = data()[k]
	return out


## The next line for an enemy of `faction`, with the voice `seed_value`
## gives it: {"who", "line"}, or empty if the faction has no lines.
static func next(faction: String, seed_value: int) -> Dictionary:
	var f: Dictionary = data().get(faction, data().get("static", {}))
	var lines: Array = f.get("lines", [])
	var voices: Array = f.get("voices", [])
	if lines.is_empty() or voices.is_empty():
		return {}
	var bag: Array = _bags.get(faction, [])
	if bag.is_empty():
		bag = lines.duplicate()
		for i in range(bag.size() - 1, 0, -1):
			var j := _rng.randi_range(0, i)
			var t: Variant = bag[i]
			bag[i] = bag[j]
			bag[j] = t
		# A fresh deal never opens with the line that closed the last one.
		if bag.size() > 1 and bag[0] == _last.get(faction, ""):
			bag.push_back(bag.pop_front())
	var line: String = bag.pop_front()
	_bags[faction] = bag
	_last[faction] = line
	return {"who": voices[absi(seed_value) % voices.size()], "line": line}


## Starts every faction on a fresh deal (tests).
static func reset() -> void:
	_bags.clear()
	_last.clear()
