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
##              for a spot. A spot's lines, and "checkpoint:N" lines,
##              start early, by your speed, so they've been said as you
##              get there (LEAD). "cue": true marks a line that tells you
##              the way ("Escalator, your left"): it goes ahead of the
##              lines waiting, so it's heard while it helps.
##              "must": true marks a line the story needs (the Story
##              director's "Must play" lists): it is never dropped and
##              goes ahead of everything else waiting. Any other line that
##              waits in the queue longer than STALE_AFTER is dropped:
##              you've run on, and a line about the food court on the far
##              walkway only confuses. Lines queued together (a
##              conversation) wait for each other. The opening ("start")
##              and the ending ("complete") are never dropped: the level
##              holds you for the first and the results card waits for the
##              second. ("keep": true is the old name for "must".)
##              "fx": "tape" plays a line as an old reel (Calder Radio,
##              twenty years ago): a thinner, warbling band.
##   "chatter": reactions to how you play, by event ("bail", "combo",
##              "fall", "kill", "headshot", "caught", "tape"): lists of
##              {"who", "line"}, dealt out in a shuffled order (every line
##              once before any comes round again, kept across retries, and
##              never one of the last few lines heard), never more than one
##              every few seconds and never over a story line.
##
## Lines queue and are never cut off. Each line is spoken over the radio
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
## Seconds a line that isn't a "must" can wait in the queue before it's
## dropped: any later and it's about somewhere you've already run past.
const STALE_AFTER := 4.0
## Chatter skips any of this many lines heard last, if it can.
const RECENT_LINES := 6
## Seconds a spot's line starts ahead of its clip, so it has been said a
## moment before you get there.
const LEAD := 0.5
## The slowest speed (m/s) a lead is worked out at: standing near a spot
## shouldn't make its lines wait until you're on it.
const LEAD_MIN_SPEED := 7.5

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
## Every story line queued, oldest first, with when it was queued
## ("queued_at"), shown ("shown_at", "ends_at") or dropped ("dropped"):
## the pacing test reads it.
var story_log: Array[Dictionary] = []
var current := {}
## Set before the mission begins when the opening has been heard (a
## restart, or a level finished before): its "start" lines are skipped.
var skip_opening := false
## Tests: move on with the physics ticks instead of real time.
var sim_clock := false

var _story: Array = []
var _played := {}
var _chatter := {}
var _chatter_ready_at := 0.0
## Mission events seen so far (chatter with "after" waits for its event).
var _seen := {}
var _last_queued := -1
var _last_queued_at := -1.0
## Seconds each spot's (or checkpoint's) lines take, by trigger key.
var _lead_for := {}
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
			story_found = true
			if event_name == "start" and skip_opening:
				continue
			_say_story(s, event_name)
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


## True for a line the story needs: never dropped, heard before the rest.
static func is_must(s: Dictionary) -> bool:
	return bool(s.get("must", s.get("keep", false)))


func _say_story(s: Dictionary, on: String) -> void:
	var never_stale := is_must(s) or on in ["start", "complete"]
	var l := say(s.get("who", "mags"), s.get("line", ""), s.get("cue", false), not never_stale, s.get("fx", ""), is_must(s), on)
	if not l.is_empty():
		story_log.append(l)


## Queues a line. A `must` line (the story) goes ahead of everything
## waiting but other must lines; a cue (the way on) ahead of the rest. A
## `local` line is dropped if it waits too long. Lines queued at the same
## moment (a conversation) stay together, in order.
func say(who: String, line: String, cue := false, local := false, fx := "", must := false, on := "") -> Dictionary:
	if line == "":
		return {}
	var l := {"who": who, "line": line, "queued_at": _clock, "on": on}
	if fx != "":
		l["fx"] = fx
	if must:
		l["must"] = true
	if cue:
		l["cue"] = true
	var at := queue.size()
	var prev := {}
	if on != "" and _last_queued_at == _clock and _last_queued >= 0 and _last_queued < queue.size() \
			and queue[_last_queued].queued_at == _clock and queue[_last_queued].get("on", "") == on:
		# The next line of a conversation: right after the line before.
		at = _last_queued + 1
		prev = queue[_last_queued]
	else:
		at = 0
		while at < queue.size() and _rank(queue[at]) <= _rank(l):
			at += 1
		if at == queue.size() and at > 0 and queue.back().queued_at == _clock:
			prev = queue.back()
	# When it's due: now, or for a conversation's next line, once the
	# lines before it have been said.
	l["due"] = _clock
	if not prev.is_empty():
		l["due"] = float(prev.get("due", prev.queued_at)) + clip_length(prev.who, prev.line)
	if local:
		l["stale_at"] = float(l.due) + STALE_AFTER
	queue.insert(at, l)
	_last_queued = at
	_last_queued_at = _clock
	return l


## Queue order: must lines, then cues, then everything else.
static func _rank(l: Dictionary) -> int:
	return 0 if l.get("must", false) else 1 if l.get("cue", false) else 2


## How long a line is up: its clip (and a breath), or reading time.
static func clip_length(who: String, line: String) -> float:
	var t := duration(line)
	var voice := Voices.stream_for(who, line)
	if voice != null:
		t = maxf(t, voice.get_length() + 0.35)
	return t


## True while a line of the opening ("start") is up or waiting.
func opening_playing() -> bool:
	if current.get("on", "") == "start":
		return true
	return queue.any(func(l: Dictionary) -> bool: return l.get("on", "") == "start")


## Seconds of opening still to be said.
func opening_left() -> float:
	var t := 0.0
	if current.get("on", "") == "start":
		t += maxf(_show_time - _shown_for, 0.0)
	for l: Dictionary in queue:
		if l.get("on", "") == "start":
			t += clip_length(l.who, l.line)
	return t


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
	if not sim_clock:
		advance(dt)


func _physics_process(delta: float) -> void:
	if sim_clock:
		advance(delta)


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
		_last_queued -= 1
		if _clock <= float(l.get("stale_at", INF)):
			_show(l)
		else:
			l["dropped"] = _clock
	_refresh()


func _check_triggers() -> void:
	var pos := player.global_position
	var t := run.seconds()
	var vel: Vector3 = player.get("velocity") if player.get("velocity") != null else Vector3.ZERO
	var cps: Array = run.mission.get("checkpoints", [])
	for i in _story.size():
		if _played.has(i):
			continue
		var s: Dictionary = _story[i]
		var on: String = s.get("on", "")
		if on.begins_with("time:"):
			if run.phase == MissionRun.Phase.RUNNING and t >= on.substr(5).to_float():
				_played[i] = true
				_say_story(s, on)
		elif s.has("at"):
			if MissionRun.inside(s, pos) or _coming_up(s, "at:%s" % str(s.at), pos, vel):
				_played[i] = true
				_say_story(s, "at")
		elif on.begins_with("checkpoint:") and run.phase == MissionRun.Phase.RUNNING:
			var n := on.substr(11).to_int()
			if n >= run.checkpoint and n < cps.size() and _coming_up(cps[n], on, pos, vel):
				# Said on the way in, so it's over as you get there; the
				# checkpoint itself then finds it played.
				_played[i] = true
				_say_story(s, on)


## True when the spot `region` is close enough, at your speed, that lines
## for it (all of them under `key`, a conversation) should start now to
## finish as you get there.
func _coming_up(region: Dictionary, key: String, pos: Vector3, vel: Vector3) -> bool:
	var flat := Vector3(vel.x, 0.0, vel.z)
	var speed := flat.length()
	if speed < 1.0:
		return false
	var at := MissionBuilder.vec(region.get("at", [0, 0, 0]))
	if absf(at.y - pos.y) > 12.0:
		return false
	var reach: float = region.get("radius", 6.0)
	if region.has("size"):
		var half := MissionBuilder.vec(region.size) * 0.5
		reach = minf(half.x, half.z)
	var dist := -1.0
	var legs: Array = run.mission.get("route_legs", [])
	if not legs.is_empty():
		dist = route_progress(legs, at) - route_progress(legs, pos)
		if dist < 0.0 or Vector2(at.x - pos.x, at.z - pos.z).length() > dist + 40.0:
			return false
	else:
		var to := Vector3(at.x - pos.x, 0.0, at.z - pos.z)
		dist = to.length()
		# Heading for it, not running away from a spot behind you.
		if to.normalized().dot(flat / speed) < 0.5:
			return false
	dist -= reach
	return dist / maxf(speed, LEAD_MIN_SPEED) <= _lead(key)


## Seconds the lines for trigger `key` take to say, plus LEAD.
func _lead(key: String) -> float:
	if _lead_for.has(key):
		return _lead_for[key]
	var t := LEAD
	for s: Dictionary in _story:
		var k: String = "at:%s" % str(s.at) if s.has("at") else String(s.get("on", ""))
		if k == key and _allowed(s):
			t += clip_length(s.get("who", "mags"), s.get("line", ""))
	_lead_for[key] = t
	return t


## How far along a route (from Route: [origin x, origin z, yaw, z0] per
## leg) the point `pos` is, in metres: the leg it's on is the one whose
## stretch holds it and that it's nearest across.
static func route_progress(legs: Array, pos: Vector3) -> float:
	var best := INF
	var progress := 0.0
	for i in legs.size():
		var l: Array = legs[i]
		var v := Basis(Vector3.UP, -float(l[2])) * Vector3(pos.x - float(l[0]), 0.0, pos.z - float(l[1]))
		var along := -(v.z + float(l[3]))
		var from := -float(l[3])
		var to := -float(legs[i + 1][3]) if i + 1 < legs.size() else INF
		var off := absf(v.x)
		if along < from:
			off += from - along
		elif along > to:
			off += along - to
		if off < best:
			best = off
			progress = clampf(along, from, to)
	return progress


func _show(l: Dictionary) -> void:
	current = l
	history.append(l)
	_recent.append(String(l.line))
	if _recent.size() > RECENT_LINES:
		_recent.pop_front()
	_shown_for = 0.0
	l["shown_at"] = _clock
	_show_time = duration(l.line)
	var voice := Voices.stream_for(l.who, l.line)
	if voice != null:
		_show_time = maxf(_show_time, voice.get_length() + 0.35)
		var audio := get_node_or_null(^"/root/GameAudio")
		if audio != null:
			# Echo's coded messages break up as they slip through.
			audio.play_radio(voice, 0.0, l.who == "echo", String(l.get("fx", "")))
	l["ends_at"] = _clock + _show_time


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
