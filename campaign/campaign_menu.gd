extends Control
## The campaign screen: every mission of "Dead Air" by act, with its story
## beat, what it teaches, your best result, and Play. Missions that aren't
## built yet are listed so the whole story is visible.

const ORANGE := Color(0.96, 0.45, 0.12)
const INK := Color(0.93, 0.9, 0.84)
const DIM := Color(0.6, 0.57, 0.52)

var selected := 0

var _list: VBoxContainer
var _title: Label
var _place: Label
var _beat: Label
var _teaches: Label
var _best: Label
var _play: Button
var _runner: Button
var _buttons: Array[Button] = []


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.065, 0.06)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	add_child(margin)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 40)
	margin.add_child(cols)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(520, 0)
	cols.add_child(left)
	left.add_child(_text("DEAD AIR", 56, ORANGE))
	left.add_child(_text("Parker races across Port Calder to the broadcast tower, live on the Host's show.", 18, DIM, true))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	left.add_child(bottom)
	_runner = _button("", _toggle_runner)
	bottom.add_child(_runner)
	bottom.add_child(_button("Free play", func() -> void: get_tree().change_scene_to_file("res://levels/sandbox.tscn")))

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 14)
	cols.add_child(right)
	_title = _text("", 40, INK)
	right.add_child(_title)
	_place = _text("", 20, ORANGE)
	right.add_child(_place)
	_beat = _text("", 24, INK, true)
	right.add_child(_beat)
	_teaches = _text("", 19, DIM, true)
	right.add_child(_teaches)
	_best = _text("", 20, INK, true)
	right.add_child(_best)
	_play = _button("Play", func() -> void: Campaign.play(get_tree(), selected))
	_play.custom_minimum_size = Vector2(240, 56)
	right.add_child(_play)

	_fill_list()
	selected = clampi(Campaign.current, 0, Campaign.mission_count() - 1)
	_select(selected)
	_buttons[selected].grab_focus.call_deferred()


func _fill_list() -> void:
	var all := Campaign.missions()
	var act := ""
	for i in all.size():
		var m: Dictionary = all[i]
		if m.act != act:
			act = m.act
			var h := _text(act.to_upper(), 18, ORANGE)
			_list.add_child(h)
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 40)
		b.add_theme_font_size_override("font_size", 20)
		var mark := "✓ " if Campaign.is_complete(i) else ("   " if Campaign.is_built(i) else "· ")
		b.text = "%s%s  %s%s" % [mark, _number(m, i), m.title, "" if Campaign.is_built(i) else "   (coming later)"]
		if not Campaign.is_unlocked(i):
			b.add_theme_color_override("font_color", DIM)
		b.focus_entered.connect(_select.bind(i))
		b.pressed.connect(func() -> void:
			if Campaign.is_unlocked(i):
				Campaign.play(get_tree(), i))
		_list.add_child(b)
		_buttons.append(b)


func _select(i: int) -> void:
	selected = i
	var m := Campaign.entry(i)
	_title.text = "%s  %s" % [_number(m, i).strip_edges(), m.get("title", "")]
	_place.text = "%s  ·  %s" % [m.get("act", ""), m.get("place", "")]
	_beat.text = m.get("beat", "")
	_teaches.text = "New moves: %s\nEnemies and shooting: %s" % [m.get("moves", ""), m.get("enemies", "")]
	var best := Campaign.best(i)
	if not Campaign.is_built(i):
		_best.text = "Not built yet. Its story beat is here so the whole campaign reads in order."
	elif best.is_empty():
		_best.text = "Not played yet."
	else:
		var tapes: Array = best.get("tapes", [])
		_best.text = "Best time %s   ·   best score %d   ·   tapes found %d" % [
			CourseTimer.format_time(best.ticks / float(Engine.physics_ticks_per_second)), best.score, tapes.size()]
	_play.disabled = not Campaign.is_unlocked(i)
	_play.text = "Play" if Campaign.is_unlocked(i) else ("Coming later" if not Campaign.is_built(i) else "Locked")
	_refresh_runner()


func _toggle_runner() -> void:
	if not Campaign.echo_unlocked():
		return
	Campaign.set_runner("parker" if Campaign.runner_for(-1) == "echo" else "echo")
	_refresh_runner()


func _refresh_runner() -> void:
	if not Campaign.echo_unlocked():
		_runner.text = "Runner: Parker  (beat Signal Out to unlock Echo)"
		_runner.disabled = true
	else:
		_runner.disabled = false
		_runner.text = "Runner: %s" % Campaign.runner_for(-1).capitalize()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file("res://levels/sandbox.tscn")


func _text(t: String, size: int, color: Color, wrap := false) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _button(t: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(0, 44)
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(on_press)
	return b


## A mission's number in the list: its "label" ("1-1", stage and level)
## when it has one.
static func _number(m: Dictionary, i: int) -> String:
	return String(m["label"]) if m.has("label") else "%2d" % int(m.get("number", i))
