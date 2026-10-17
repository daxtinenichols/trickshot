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
##              to play when you reach a spot.
##   "chatter": reactions to how you play, by event ("bail", "combo",
##              "fall", "kill", "headshot", "caught", "tape"): lists of
##              {"who", "line"}, used in turn, never more than one every few
##              seconds and never over a story line.
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
	"vell": ["COMMANDER VELL", Color(0.78, 0.86, 0.95)],
}
## Seconds between two chatter lines.
const CHATTER_COOLDOWN := 7.0
## A queue this long drops chatter.
const MAX_QUEUE := 4

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
var _chatter_next := {}
var _chatter_ready_at := 0.0
var _shown_for := 0.0
var _show_time := 0.0
var _last_msec := 0

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
	var story_found := false
	for i in _story.size():
		var s: Dictionary = _story[i]
		if s.get("on", "") == event_name and not _played.has(i):
			_played[i] = true
			say(s.get("who", "mags"), s.get("line", ""))
			story_found = true
	if not story_found and _chatter.has(event_name):
		_chat(event_name)


## Queues a line.
func say(who: String, line: String) -> void:
	if line == "":
		return
	queue.append({"who": who, "line": line})


func _chat(event_name: String) -> void:
	if queue.size() > 0 or not current.is_empty() or _now() < _chatter_ready_at:
		return
	var pool: Array = _chatter[event_name]
	if pool.is_empty():
		return
	var i: int = _chatter_next.get(event_name, 0)
	_chatter_next[event_name] = (i + 1) % pool.size()
	var c: Dictionary = pool[i]
	_chatter_ready_at = _now() + CHATTER_COOLDOWN
	say(c.get("who", "host"), c.get("line", ""))


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


## Moves the radio on by `dt` real seconds (also used by tests).
func advance(dt: float) -> void:
	if run != null and player != null:
		_check_triggers()
	if not current.is_empty():
		_shown_for += dt
		if _shown_for >= _show_time:
			current = {}
	if current.is_empty() and not queue.is_empty():
		_show(queue.pop_front())
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
			say(s.get("who", "mags"), s.get("line", ""))
		elif s.has("at") and MissionRun.inside(s, pos):
			_played[i] = true
			say(s.get("who", "mags"), s.get("line", ""))


func _show(l: Dictionary) -> void:
	current = l
	history.append(l)
	_shown_for = 0.0
	_show_time = duration(l.line)
	var voice := Voices.stream_for(l.who, l.line)
	if voice != null:
		_show_time = maxf(_show_time, voice.get_length() + 0.35)
		var audio := get_node_or_null(^"/root/GameAudio")
		if audio != null:
			# Echo's coded messages break up as they slip through.
			audio.play_radio(voice, 0.0, l.who == "echo")


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
	_who.add_theme_color_override("font_color", spk[1])
	_text.text = current.line
	# Fade out over the last half second.
	_panel.modulate.a = clampf((_show_time - _shown_for) * 2.0, 0.0, 1.0)
