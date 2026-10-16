class_name ComboHud
extends CanvasLayer
## Score and the running combo: "1,240 x 5", the tricks in it, the time left
## before it banks, and the shot damage it gives. Flashes on bank and bail.

const SHOT_NAMES := {
	&"hit": "HIT",
	&"headshot": "HEADSHOT",
	&"air_shot": "AIR SHOT",
	&"long_shot": "LONG SHOT",
	&"slide_shot": "SLIDE SHOT",
	&"wallrun_shot": "WALLRUN SHOT",
	&"flip_shot": "FLIP SHOT",
	&"spin_shot": "SPIN SHOT",
	&"kill": "KILL",
	&"combo_kill": "COMBO KILL",
}

var tracker: ComboTracker

var _root: Control
var _score: Label
var _combo: Label
var _list: Label
var _bar: ProgressBar
var _damage: Label
var _flash: Label
var _flash_time := 0.0


static func trick_label(trick_name: StringName) -> String:
	if SHOT_NAMES.has(trick_name):
		return SHOT_NAMES[trick_name]
	return DebugHud.TRICK_NAMES.get(trick_name, String(trick_name).to_upper())


## "SLIDE + WALLRUN + BACKFLIP x2", newest last, at most `max_items`.
static func combo_list_text(entries: Array[Dictionary], max_items := 6) -> String:
	var parts: Array[String] = []
	for e in entries:
		var s := trick_label(e.name)
		if e.count > 1:
			s += " x%d" % e.count
		parts.append(s)
	if parts.size() > max_items:
		parts = parts.slice(parts.size() - max_items)
		parts.push_front("...")
	return "  +  ".join(parts)


static func with_commas(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


func _ready() -> void:
	layer = 9
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_score = _make_label(24, Control.PRESET_CENTER_TOP, Vector2(-400, 16), 800)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	box.position = Vector2(-450, -230)
	box.custom_minimum_size = Vector2(900, 0)
	box.alignment = BoxContainer.ALIGNMENT_END
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(box)
	_combo = _styled(Label.new(), 44)
	box.add_child(_combo)
	_list = _styled(Label.new(), 18)
	_list.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_list)
	_bar = ProgressBar.new()
	_bar.max_value = 1.0
	_bar.step = 0.001
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(240, 6)
	_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_bar)
	_damage = _styled(Label.new(), 15)
	_damage.modulate = Color(1, 1, 1, 0.75)
	box.add_child(_damage)

	_flash = _make_label(34, Control.PRESET_CENTER, Vector2(-300, -150), 600)


func setup(t: ComboTracker) -> void:
	tracker = t
	t.banked.connect(func(_pts: int, _mult: int, total: int) -> void:
		_show_flash("+%s" % with_commas(total), Color(0.45, 1.0, 0.55)))
	t.bailed.connect(func(lost: int, _reason: StringName) -> void:
		_show_flash("BAILED  -%s" % with_commas(lost), Color(1.0, 0.35, 0.3)))


func _process(delta: float) -> void:
	_flash_time -= delta
	_flash.modulate.a = clampf(_flash_time / 0.4, 0.0, 1.0)
	if tracker == null:
		return
	_score.text = "SCORE %s     BEST COMBO %s" % [with_commas(tracker.score), with_commas(tracker.best_combo)]
	var active := tracker.is_active()
	_combo.visible = active
	_list.visible = active
	_bar.visible = active
	_damage.visible = active
	if not active:
		return
	_combo.text = "%s  x%d" % [with_commas(roundi(tracker.combo_points)), tracker.multiplier()]
	_list.text = combo_list_text(tracker.entries)
	_bar.value = clampf(tracker.time_left / tracker.bank_after, 0.0, 1.0)
	_damage.text = "shot damage x%.1f" % tracker.damage_multiplier()


func _show_flash(text: String, color: Color) -> void:
	_flash.text = text
	_flash.add_theme_color_override("font_color", color)
	_flash_time = 1.4


func _make_label(font_size: int, preset: Control.LayoutPreset, pos: Vector2, width: float) -> Label:
	var l := _styled(Label.new(), font_size)
	l.set_anchors_preset(preset)
	l.position = pos
	l.custom_minimum_size = Vector2(width, 0)
	_root.add_child(l)
	return l


func _styled(l: Label, font_size: int) -> Label:
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 7)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
