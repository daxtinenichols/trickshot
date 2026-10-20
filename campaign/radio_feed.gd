class_name RadioFeed
extends CanvasLayer
## The radio: subtitled lines from Mags in your ear, the Host on the
## broadcast, and Echo's coded messages, shown low in the middle of the
## screen. The mission's data says what is said and when:
##
##   "radio":   story lines, each played once when its trigger happens:
##              {"on": "start" | "go" | "objective:N" | "done:N" |
##                     "checkpoint:N" | "complete" | "time:SECONDS" | ...,
##               "who": "mags", "line": "..."}
##              or {"at": [x, y, z], "radius": 6, "who": ..., "line": ...}
##              to play when you reach a spot. "cue": true marks a line
##              that tells you the way ("Escalator, your left"): it goes
##              to the front of the queue, so it's heard while it helps.
##              A line for a place (an "at" line, or one on reaching a
##              checkpoint) that waits in the queue longer than
##              STALE_AFTER is dropped: you've run on, and a line about the
##              food court on the far walkway only confuses. Lines queued
##              together (a conversation) wait for each other, and a
##              story beat that must be heard says "keep": true.
##              "fx": "tape" plays a line as an old reel (Calder Radio,
##              twenty years ago): a thinner, warbling band.
##   "chatter": reactions to how you play, by event ("bail", "combo",
##              "fall", "kill", "headshot", "caught", "tape"): lists of
##              {"who", "line"}, dealt out in a shuffled order (every line
##              once before any comes round again, kept across retries, and
##              never one of the last few lines heard), never more than one
##              every few seconds and never over a story line.
##
## Lines queue and never stop the game. Each line is spoken over the radio
## when it has a voice clip (audio/voice_lines.gd) and stays up until it
## has been said. Presentation only: nothing here changes the simulation.

const Voices := preload("res://audio/voice_lines.gd")

const SPEAKERS := {
	"host": ["THE HOST", Color(1.0, 0.36, 0.3)],
	"mags": ["MAGS", Color(1.0, 0.72, 0.3)],
	"echo": ["ECHO", Color(0.45, 0.9, 1.0)],
	"parker": ["PARKER", Color(0.92, 0.92, 0.88)],
	"juno": ["JUNO", Color(0.75, 0.6, 1.0)],
	"vell": ["COMMANDER VELL", Color(0.72, 0.84, 1.0)],
}
## Seconds between two chatter lines.
const CHATTER_COOLDOWN := 7.0
## A queue this long drops chatter.
const MAX_QUEUE := 4
## Seconds a line for a place can wait in the queue before it's dropped.
const STALE_AFTER := 12.0
## Chatter skips any of this many lines heard last, if it can.
const RECENT_LINES := 6

## Chatter not dealt yet this round, by "<mission id>/<event>": indices into
## the pool. Static so a retry carries on where the last attempt left off
## instead of starting the same lines over.
static var _bags := {}
## The last lines heard (story and chatter), newest last.
static var _recent: Array[String] = []
## Presentation only: its own random numbers, nothing from the sim.
static var _rng := RandomNumberGenerator.new()

var run: MissionRun
var player: Node3D
## Lines waiting: [{who, line}].
var queue: Array[Dictionary] = []
## Every line shown so far, oldest first (for tests and a future log).
var history: Array[Dictionary] = []
var current := {}

var _story: Array = []
var _played := {}
var _chatter := {}
var _chatter_ready_at := 0.0
## Mission events seen so far (chatter with "after" waits for its event).
var _seen := {}
var _shown_for := 0.0
var _show_time := 0.0
var _last_msec := 0
## Radio time (advance's dt summed), for how long lines have waited.
var _clock := 0.0

var _panel: PanelContainer
var _who: Label
var _text: Label


func setup(r: MissionRun, p: Node3D) -> void:
	run = r
	player = p
	_story = r.mission.get("radio", [])
	_chatter = r.mission.get("chatter", {})
	r.event.connect(notify)
	_last_msec = Time.get_ticks_msec()


func _ready() -> void:
	layer = 6
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


## A mission event happened: queue the story lines it triggers, or a
## chatter reaction if the radio is free.
func notify(event_name: String) -> void:
	_seen[event_name] = true
	var story_found := false
	for i in _story.size():
		var s: Dictionary = _story[i]
		if s.get("on", "") == event_name and not _played.has(i) and _allowed(s):
			_played[i] = true
			say(s.get("who", "mags"), s.get("line", ""), s.get("cue", false), event_name.begins_with("checkpoint:") and not s.get("keep", false), s.get("fx", ""))
			story_found = true
	if not story_found and _chatter.has(event_name):
		_chat(event_name)


## A line with "if": "<mission id>.<key>=<value>" plays only when that
## story choice was saved (e.g. the ending's line for a spared Juno).
static func _allowed(s: Dictionary) -> bool:
	if not s.has("if"):
		return true
	var cond: PackedStringArray = String(s["if"]).split("=")
	var key: PackedStringArray = cond[0].split(".")
	return cond.size() == 2 and key.size() == 2 and Campaign.choice(key[0], key[1]) == cond[1]


## Queues a line; a cue (the way on) goes ahead of the lines waiting. A
## `local` line (about where you are) is dropped if it waits too long.
func say(who: String, line: String, cue := false, local := false, fx := "") -> void:
	if line == "":
		return
	var l := {"who": who, "line": line, "queued_at": _clock}
	if fx != "":
		l["fx"] = fx
	if local:
		l["stale_at"] = _clock + STALE_AFTER
		# The next line of a conversation queued at the same moment can
		# wait as long as the lines before it take.
		if not queue.is_empty() and queue.back().get("queued_at", -1.0) == _clock and queue.back().has("stale_at"):
			l["stale_at"] = float(queue.back().stale_at) + duration(queue.back().line) + 2.0
	if cue:
		# After any cue already waiting, ahead of everything else.
		l["cue"] = true
		var at := 0
		while at < queue.size() and queue[at].get("cue", false):
			at += 1
		queue.insert(at, l)
	else:
		queue.append(l)


func _chat(event_name: String) -> void:
	if queue.size() > 0 or not current.is_empty() or _now() < _chatter_ready_at:
		return
	var pool: Array = _chatter[event_name]
	if pool.is_empty():
		return
	var c := _deal(event_name, pool)
	if c.is_empty():
		return
	_chatter_ready_at = _now() + CHATTER_COOLDOWN
	say(c.get("who", "host"), c.get("line", ""))


## The next chatter line for `event_name`: the first line left in this
## round's shuffled bag whose "after" event (if any) has happened, e.g. Echo
## only once she's on open air, preferring one not heard lately. Lines still
## waiting on their event stay in the bag for later.
func _deal(event_name: String, pool: Array) -> Dictionary:
	var key := "%s/%s" % [run.mission.get("id", "") if run != null else "", event_name]
	var bag: Array = (_bags.get(key, []) as Array).filter(func(i: int) -> bool: return i < pool.size())
	for attempt in 2:
		var pick := -1
		# Not heard lately if possible, else at least not the last line.
		for strict in [2, 1, 0]:
			for j in bag.size():
				var l: Dictionary = pool[bag[j]]
				if l.has("after") and not _seen.has(String(l.after)):
					continue
				var said := String(l.get("line", ""))
				if strict == 2 and said in _recent:
					continue
				if strict == 1 and not _recent.is_empty() and said == _recent.back():
					continue
				pick = j
				break
			if pick >= 0:
				break
		if pick >= 0:
			var c: Dictionary = pool[bag[pick]]
			bag.remove_at(pick)
			_bags[key] = bag
			return c
		# Nothing playable left this round: deal the pool again, keeping
		# the lines still waiting on their event where they are.
		var order := range(pool.size())
		for i in range(order.size() - 1, 0, -1):
			var j := _rng.randi_range(0, i)
			var t: int = order[i]
			order[i] = order[j]
			order[j] = t
		for i: int in order:
			if not i in bag:
				bag.append(i)
	_bags[key] = bag
	return {}


## Forgets what chatter has been dealt and heard (tests).
static func reset_chatter() -> void:
	_bags.clear()
	_recent.clear()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## How long a line stays up: long enough to read, short enough to keep up.
static func duration(line: String) -> float:
	return clampf(1.4 + line.length() * 0.045, 2.0, 7.0)


func _process(_delta: float) -> void:
	# Real time, so slow motion doesn't hold lines up.
	var msec := Time.get_ticks_msec()
	var dt := (msec - _last_msec) / 1000.0
	_last_msec = msec
	advance(dt)


## True while a line is up or waiting (the results card waits for it).
func busy() -> bool:
	return not current.is_empty() or not queue.is_empty()


## Moves the radio on by `dt` real seconds (also used by tests).
func advance(dt: float) -> void:
	_clock += dt
	if run != null and player != null:
		_check_triggers()
	if not current.is_empty():
		_shown_for += dt
		if _shown_for >= _show_time:
			current = {}
	while current.is_empty() and not queue.is_empty():
		var l: Dictionary = queue.pop_front()
		if _clock <= float(l.get("stale_at", INF)):
			_show(l)
	_refresh()


func _check_triggers() -> void:
	var pos := player.global_position
	var t := run.seconds()
	for i in _story.size():
		if _played.has(i):
			continue
		var s: Dictionary = _story[i]
		var on: String = s.get("on", "")
		if on.begins_with("time:") and run.phase == MissionRun.Phase.RUNNING and t >= on.substr(5).to_float():
			_played[i] = true
			say(s.get("who", "mags"), s.get("line", ""), s.get("cue", false), false, s.get("fx", ""))
		elif s.has("at") and MissionRun.inside(s, pos):
			_played[i] = true
			say(s.get("who", "mags"), s.get("line", ""), s.get("cue", false), not s.get("keep", false), s.get("fx", ""))


func _show(l: Dictionary) -> void:
	current = l
	history.append(l)
	_recent.append(String(l.line))
	if _recent.size() > RECENT_LINES:
		_recent.pop_front()
	_shown_for = 0.0
	_show_time = duration(l.line)
	var voice := Voices.stream_for(l.who, l.line)
	if voice != null:
		_show_time = maxf(_show_time, voice.get_length() + 0.35)
		var audio := get_node_or_null(^"/root/GameAudio")
		if audio != null:
			# Echo's coded messages break up as they slip through.
			audio.play_radio(voice, 0.0, l.who == "echo", String(l.get("fx", "")))


func _exit_tree() -> void:
	var audio := get_node_or_null(^"/root/GameAudio")
	if audio != null and not current.is_empty():
		audio.stop_radio()


func _build() -> void:
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.06, 0.72)
	sb.border_color = Color(0.96, 0.45, 0.12, 0.9)
	sb.border_width_left = 4
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 10
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_right = 6
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.custom_minimum_size = Vector2(760, 0)
	_panel.position = Vector2(-380, -110)
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_panel.add_child(box)
	_who = Label.new()
	_who.add_theme_font_size_override("font_size", 18)
	box.add_child(_who)
	_text = Label.new()
	_text.add_theme_font_size_override("font_size", 24)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(728, 0)
	box.add_child(_text)
	_panel.visible = false


func _refresh() -> void:
	if _panel == null:
		return
	_panel.visible = not current.is_empty()
	if current.is_empty():
		return
	var spk: Array = SPEAKERS.get(current.who, [String(current.who).to_upper(), Color.WHITE])
	_who.text = "◉ " + spk[0] if current.who == "host" else spk[0]
	if current.get("fx", "") == "tape":
		_who.text = spk[0] + "  ·  OLD TAPE"
	_who.add_theme_color_override("font_color", spk[1])
	_text.text = current.line
	# Fade out over the last half second.
	_panel.modulate.a = clampf((_show_time - _shown_for) * 2.0, 0.0, 1.0)
