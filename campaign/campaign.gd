class_name Campaign
extends RefCounted
## The "Dead Air" campaign: which missions exist (campaign/campaign.json),
## which one is being played, and the player's progress (best times and
## scores, tapes found, Echo unlocked), saved in user://campaign.cfg.
##
## A mission is a data file in campaign/missions/ (see docs/missions.md):
## its layout, checkpoints, objectives and radio lines. Missions without a
## file yet are listed with their story beat and marked as coming later.

const INDEX_PATH := "res://campaign/campaign.json"
const MISSION_SCENE := "res://campaign/mission.tscn"
const MENU_SCENE := "res://campaign/campaign.tscn"
const SAVE_PATH := "user://campaign.cfg"
const Route := preload("res://campaign/route.gd")

## Set false in tests so they never touch the player's save.
static var persist := true
## Index into missions() of the mission to play (or being played).
static var current := 0
## Unlock every built mission (testing). Locked missions still play from
## the editor.
static var unlock_all := true

static var _index := {}
static var _save: ConfigFile


## Acts and missions from campaign.json: [{title, missions: [...]}, ...].
static func acts() -> Array:
	return index().get("acts", [])


static func index() -> Dictionary:
	if _index.is_empty():
		var f := FileAccess.open(INDEX_PATH, FileAccess.READ)
		if f != null:
			var data: Variant = JSON.parse_string(f.get_as_text())
			if data is Dictionary:
				_index = data
	return _index


## Every mission in order, each with its act title added as "act".
static func missions() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for act: Dictionary in acts():
		for m: Dictionary in act.get("missions", []):
			var entry := m.duplicate()
			entry["act"] = act.get("title", "")
			out.append(entry)
	return out


static func mission_count() -> int:
	return missions().size()


static func entry(i: int) -> Dictionary:
	var all := missions()
	return all[i] if i >= 0 and i < all.size() else {}


## True when mission i has a data file to play.
static func is_built(i: int) -> bool:
	var file: String = entry(i).get("file", "")
	return file != "" and FileAccess.file_exists(file)


## The parsed data file of mission i ({} if it isn't built yet).
static func load_mission(i: int) -> Dictionary:
	return load_mission_file(entry(i).get("file", ""))


static func load_mission_file(path: String) -> Dictionary:
	if path == "" or not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var data: Variant = JSON.parse_string(f.get_as_text())
	if not (data is Dictionary):
		push_error("Campaign: %s is not valid mission JSON" % path)
		return {}
	return Route.expand(data)


## The mission index whose data file is `path`, or -1.
static func index_of_file(path: String) -> int:
	var all := missions()
	for i in all.size():
		if all[i].get("file", "") == path:
			return i
	return -1


# ---------------------------------------------------------------- progress

static func save() -> ConfigFile:
	if _save == null:
		_save = ConfigFile.new()
		if persist:
			_save.load(SAVE_PATH)
	return _save


static func reset_progress() -> void:
	_save = ConfigFile.new()
	_write()


static func is_complete(i: int) -> bool:
	return save().get_value(_id(i), "done", false)


## Mission i can be played: it is built and it's the first one or the one
## before it is complete (or everything is unlocked for testing).
static func is_unlocked(i: int) -> bool:
	if not is_built(i):
		return false
	return unlock_all or i == 0 or is_complete(i - 1)


## The best result saved for mission i: {ticks, score, best_combo, tapes}.
static func best(i: int) -> Dictionary:
	var s := save()
	var id := _id(i)
	if not s.has_section(id):
		return {}
	return {
		"ticks": s.get_value(id, "best_ticks", 0),
		"score": s.get_value(id, "best_score", 0),
		"best_combo": s.get_value(id, "best_combo", 0),
		"tapes": s.get_value(id, "tapes", []),
	}


## Records a finished run of mission i. Returns which records it broke:
## {"time": bool, "score": bool}.
static func record(i: int, result: Dictionary) -> Dictionary:
	var s := save()
	var id := _id(i)
	var broke := {"time": false, "score": false}
	var ticks: int = result.get("ticks", 0)
	var best_ticks: int = s.get_value(id, "best_ticks", 0)
	if ticks > 0 and (best_ticks == 0 or ticks < best_ticks):
		s.set_value(id, "best_ticks", ticks)
		broke.time = true
	var score: int = result.get("score", 0)
	if score > s.get_value(id, "best_score", 0):
		s.set_value(id, "best_score", score)
		broke.score = true
	s.set_value(id, "best_combo", maxi(result.get("best_combo", 0), s.get_value(id, "best_combo", 0)))
	var tapes: Array = s.get_value(id, "tapes", [])
	for t: String in result.get("tapes", []):
		if not t in tapes:
			tapes.append(t)
	s.set_value(id, "tapes", tapes)
	s.set_value(id, "done", true)
	if entry(i).get("unlocks", "") == "echo":
		s.set_value("runners", "echo", true)
	_write()
	return broke


## Saves a story choice made in mission i (e.g. "fate" = "spared" when
## Juno is spared in m07), for later missions' radio to branch on.
static func set_choice(i: int, key: String, value: String) -> void:
	save().set_value(_id(i), key, value)
	_write()


## A story choice saved by mission `mission_id`, or "" if it wasn't made.
static func choice(mission_id: String, key: String) -> String:
	return str(save().get_value(mission_id, key, ""))


static func echo_unlocked() -> bool:
	return save().get_value("runners", "echo", false)


## Who runs mission i: the mission's own runner ("echo" in the finale),
## else the player's pick (Echo once unlocked), else Parker.
static func runner_for(i: int) -> String:
	var forced: String = load_mission(i).get("runner", "")
	if forced != "":
		return forced
	var pick: String = save().get_value("runners", "pick", "parker")
	return pick if pick != "echo" or echo_unlocked() else "parker"


static func set_runner(runner_name: String) -> void:
	save().set_value("runners", "pick", runner_name)
	_write()


static func _id(i: int) -> String:
	return entry(i).get("id", "mission_%d" % i)


static func _write() -> void:
	if persist and _save != null:
		_save.save(SAVE_PATH)


# ---------------------------------------------------------------- scenes

## Plays mission i (changes scene).
static func play(tree: SceneTree, i: int) -> void:
	current = i
	tree.paused = false
	Engine.time_scale = 1.0
	tree.change_scene_to_file(MISSION_SCENE)


static func open_menu(tree: SceneTree) -> void:
	tree.paused = false
	Engine.time_scale = 1.0
	tree.change_scene_to_file(MENU_SCENE)
