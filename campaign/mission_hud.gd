class_name MissionHud
extends CanvasLayer
## Mission readouts: the clock, the active objective and any open bonus
## goals at the top, the gap
## to the Host in a chase, the route mark over the way on (missions with a
## "guide"), and the results card at the end with Next, Retry and Campaign
## buttons.

signal next_pressed
signal retry_pressed
signal menu_pressed

const ORANGE := Color(0.96, 0.45, 0.12)
const RouteMarker := preload("res://campaign/route_marker.gd")

var run: MissionRun

var _clock: Label
var _objective: Label
var _bonus: Label
var _chase: Label
var _results: PanelContainer
var _results_body: VBoxContainer
var _next_button: Button
var marker: RouteMarker


func setup(r: MissionRun) -> void:
	run = r
	marker.setup(r.mission.get("guide", []), r.player)


func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	marker = RouteMarker.new()
	marker.name = "RouteMarker"
	add_child(marker)
	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.position = Vector2(-400, 18)
	top.custom_minimum_size = Vector2(800, 0)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	_clock = _label(40)
	top.add_child(_clock)
	_objective = _label(22)
	_objective.add_theme_color_override("font_color", Color(1.0, 0.86, 0.6))
	top.add_child(_objective)
	_bonus = _label(18)
	_bonus.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
	top.add_child(_bonus)
	_chase = _label(26)
	_chase.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
	top.add_child(_chase)
	_build_results()


func _label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 9)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _process(_delta: float) -> void:
	if run == null:
		return
	_clock.get_parent().visible = not _results.visible
	var settings := get_node_or_null(^"/root/Settings")
	marker.enabled = not _results.visible and run.phase != MissionRun.Phase.COMPLETE \
			and (settings == null or bool(settings.get("route_marker")))
	var t := CourseTimer.format_time(run.seconds())
	if run.practice:
		t += "   practice"
	elif run.par_seconds() > 0.0:
		t += "   par " + CourseTimer.format_time(run.par_seconds())
	_clock.text = t
	_clock.modulate = Color(1, 1, 1) if run.phase == MissionRun.Phase.RUNNING else Color(0.75, 0.8, 0.9)
	var obj := run.objective_text()
	if run.total_tapes() > 0:
		obj += "      tapes %d / %d" % [run.tapes_found.size(), run.total_tapes()]
	_objective.text = obj
	_bonus.text = run.bonus_text()
	var p := run.pursuer
	if p != null and p.visible and p.gap < INF:
		_chase.text = "%s  %d m" % [p.display_name, roundi(p.gap)]
		_chase.modulate.a = 1.0 if p.gap < 15.0 or Engine.get_physics_frames() % 60 < 45 else 0.6
	elif p != null and run.phase == MissionRun.Phase.RUNNING:
		_chase.text = "%s is coming" % p.display_name
	else:
		_chase.text = ""


## Shows the results card for `result` (from MissionRun.completed).
func show_results(result: Dictionary, title: String, has_next: bool) -> void:
	for c in _results_body.get_children():
		c.queue_free()
	var head := _label(36)
	head.text = title.to_upper()
	head.add_theme_color_override("font_color", ORANGE)
	_results_body.add_child(head)
	var records: Dictionary = result.get("records", {})
	var lines := [
		"Time  %s%s" % [CourseTimer.format_time(result.seconds), "   NEW BEST" if records.get("time", false) else ""],
		"Score  %d%s" % [result.score, "   NEW BEST" if records.get("score", false) else ""],
		"Best combo  %d" % result.best_combo,
	]
	if result.par_seconds > 0.0:
		lines.append("Par  %s  %s" % [CourseTimer.format_time(result.par_seconds), "beaten" if result.seconds <= result.par_seconds else "not yet"])
	if result.get("total_bonuses", 0) > 0:
		lines.append("Bonus goals  %d / %d   +%d" % [result.bonuses, result.total_bonuses, result.bonuses * MissionRun.BONUS_POINTS])
	if result.total_tapes > 0:
		lines.append("Tapes  %d / %d" % [result.tapes.size(), result.total_tapes])
	if result.falls > 0 or result.catches > 0:
		lines.append("Falls  %d%s" % [result.falls, ("    Caught  %d" % result.catches) if result.catches > 0 else ""])
	if result.practice:
		lines.append("Practice run: start from 1 to save a time")
	for line: String in lines:
		var l := _label(24)
		l.text = line
		_results_body.add_child(l)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 14)
	_results_body.add_child(buttons)
	_next_button = _button("Next mission" if has_next else "Campaign", next_pressed if has_next else menu_pressed)
	buttons.add_child(_next_button)
	buttons.add_child(_button("Retry", retry_pressed))
	if has_next:
		buttons.add_child(_button("Campaign", menu_pressed))
	_results.visible = true
	_next_button.grab_focus.call_deferred()


func results_visible() -> bool:
	return _results.visible


func _button(text: String, sig: Signal) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(180, 48)
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(func() -> void: sig.emit())
	return b


func _build_results() -> void:
	_results = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.055, 0.05, 0.9)
	sb.border_color = ORANGE
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(28)
	_results.add_theme_stylebox_override("panel", sb)
	_results.set_anchors_preset(Control.PRESET_CENTER)
	_results.custom_minimum_size = Vector2(620, 0)
	_results.position = Vector2(-310, -300)
	add_child(_results)
	_results_body = VBoxContainer.new()
	_results_body.add_theme_constant_override("separation", 8)
	_results.add_child(_results_body)
	_results.visible = false
