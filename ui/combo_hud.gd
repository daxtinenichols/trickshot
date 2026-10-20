class_name ComboHud
extends CanvasLayer
## Score and the running combo: "1,240 x 5", the tricks in it, the time left
## before it banks, and the shot damage it gives (shown whenever it's above
## 1x) with the cruise speed its flow adds. Each trick pops up as you
## do it ("+300 BACKFLIP  PERFECT"). All of it sits in the top-right corner. When a combo ends, a card shows the whole chain
## (ending in the kill, if a kill finished it), then the points go into the
## score. Bails flash red.

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
	&"feed_cut": "CUT THE FEED",
	&"kick_kill": "KICK KILL",
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
var _pops: VBoxContainer
var _card: VBoxContainer
var _card_title: Label
var _card_chain: Label
var _card_math: Label
var _card_total: Label
var _card_time := 0.0
## Score shown, counting up to the real one once a card has shown its total.
var _shown_score := 0.0

const CARD_TIME := 3.2
## When the card's total appears (and the score starts counting up).
const CARD_TOTAL_AT := 0.6
const POP_TIME := 1.1
## The column in the top-right corner: width and distance from the edges.
const WIDTH := 420.0
const MARGIN := 20.0


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

	# Everything stacks in one right-aligned column in the top-right corner,
	# medium sized, clear of the crosshair: score, the running combo, bails,
	# trick pop-ups, then the card when a combo ends.
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	column.position = Vector2(-MARGIN - WIDTH, MARGIN)
	column.custom_minimum_size = Vector2(WIDTH, 0)
	column.add_theme_constant_override("separation", 2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(column)

	_score = _styled(Label.new(), 17)
	_score.modulate = Color(1, 1, 1, 0.85)
	column.add_child(_score)
	_combo = _styled(Label.new(), 32)
	column.add_child(_combo)
	_list = _styled(Label.new(), 15)
	_list.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_list)
	_bar = ProgressBar.new()
	_bar.max_value = 1.0
	_bar.step = 0.001
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(200, 5)
	_bar.size_flags_horizontal = Control.SIZE_SHRINK_END
	column.add_child(_bar)
	_damage = _styled(Label.new(), 17)
	_damage.add_theme_color_override("font_color", Color(1.0, 0.72, 0.45))
	column.add_child(_damage)

	_flash = _styled(Label.new(), 24)
	column.add_child(_flash)

	# Trick pop-ups, newest at the bottom.
	_pops = VBoxContainer.new()
	_pops.add_theme_constant_override("separation", 0)
	_pops.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_pops)

	# Combo-finished card.
	_card = VBoxContainer.new()
	_card.add_theme_constant_override("separation", 0)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.visible = false
	column.add_child(_card)
	_card_title = _styled(Label.new(), 28)
	_card.add_child(_card_title)
	_card_chain = _styled(Label.new(), 15)
	_card_chain.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card.add_child(_card_chain)
	_card_math = _styled(Label.new(), 18)
	_card.add_child(_card_math)
	_card_total = _styled(Label.new(), 30)
	_card.add_child(_card_total)


func setup(t: ComboTracker) -> void:
	tracker = t
	_shown_score = t.score
	t.added.connect(_on_added)
	if t.player:
		t.player.trick.connect(func(trick_name: StringName, info: Dictionary) -> void:
			if trick_name == &"flip_kick":
				_pop(flip_kick_text(info.get("boost", 0.0)), Color(0.55, 0.9, 1.0)))
	t.finished.connect(show_card)
	t.bailed.connect(func(lost: int, _reason: StringName) -> void:
		_show_flash("BAILED  -%s" % with_commas(lost), Color(1.0, 0.35, 0.3)))


## Title for a finished combo: a kill finish says so.
static func card_title(summary: Dictionary) -> String:
	if summary.reason == &"kill":
		return "COMBO KILL" if summary.multiplier > 1 else "KILL"
	return "COMBO" if summary.multiplier > 1 else "NICE"


## The chain shown on the card: every trick, in order, "x2" for repeats.
static func card_chain(entries: Array) -> String:
	var parts: Array[String] = []
	for e: Dictionary in entries:
		var s := trick_label(e.name)
		if e.count > 1:
			s += " x%d" % e.count
		parts.append(s)
	return "  +  ".join(parts)


func show_card(summary: Dictionary) -> void:
	var kill: bool = summary.reason == &"kill"
	_card_title.text = card_title(summary)
	_card_title.add_theme_color_override("font_color", Color(1.0, 0.42, 0.3) if kill else Color(0.45, 1.0, 0.55))
	_card_chain.text = card_chain(summary.entries)
	_card_math.text = "%s  x%d" % [with_commas(summary.points), summary.multiplier]
	_card_total.text = "+%s" % with_commas(summary.total)
	_card_total.add_theme_color_override("font_color", Color(1.0, 0.86, 0.35))
	_card_total.visible = false
	_card_time = CARD_TIME
	_card.visible = true
	_card.modulate.a = 1.0


## "DAMAGE x1.6   FLOW +2.0 m/s", or "" when neither is worth showing.
static func damage_text(damage: float, flow: float) -> String:
	var parts: Array[String] = []
	if damage >= 1.05:
		parts.append("DAMAGE x%.1f" % damage)
	if flow >= 0.05:
		parts.append("FLOW +%.1f m/s" % flow)
	return "   ".join(parts)


static func flip_kick_text(boost: float) -> String:
	return "+%.1f m/s  FLIP KICK" % boost


func _on_added(trick_name: StringName, points: int) -> void:
	var text := "+%s  %s" % [with_commas(points), trick_label(trick_name)]
	if tracker and tracker.last_quality >= 0.0:
		text += "  " + DebugHud.quality_grade(tracker.last_quality)
	var shot := SHOT_NAMES.has(trick_name)
	_pop(text, Color(1.0, 0.6, 0.4) if shot else Color(1.0, 0.93, 0.62))


func _pop(text: String, color: Color) -> void:
	var l := _styled(Label.new(), 22)
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.set_meta("age", 0.0)
	l.pivot_offset = Vector2(WIDTH, 14)
	_pops.add_child(l)
	while _pops.get_child_count() > 3:
		var old := _pops.get_child(0)
		_pops.remove_child(old)
		old.queue_free()


func _process(frame_delta: float) -> void:
	# Real time, so slow motion doesn't stretch the HUD.
	var delta := frame_delta / maxf(Engine.time_scale, 0.01)
	_flash_time -= delta
	_flash.modulate.a = clampf(_flash_time / 0.4, 0.0, 1.0)
	_flash.visible = _flash_time > 0.0
	for child in _pops.get_children():
		var l := child as Label
		var age: float = l.get_meta("age") + delta
		l.set_meta("age", age)
		# Pop in big, settle, then fade.
		l.scale = Vector2.ONE * lerpf(1.35, 1.0, clampf(age / 0.12, 0.0, 1.0))
		l.modulate.a = clampf((POP_TIME - age) / 0.3, 0.0, 1.0)
		if age > POP_TIME:
			l.queue_free()
	if _card.visible:
		_card_time -= delta
		_card_total.visible = CARD_TIME - _card_time >= CARD_TOTAL_AT
		_card.modulate.a = clampf(_card_time / 0.5, 0.0, 1.0)
		if _card_time <= 0.0:
			_card.visible = false
	if tracker == null:
		return
	# The score counts up once the card has shown what was earned.
	var counting := not _card.visible or _card_total.visible
	if counting and _shown_score < tracker.score:
		_shown_score = minf(_shown_score + maxf((tracker.score - _shown_score) * 8.0, 2000.0) * delta, tracker.score)
	elif tracker.score < _shown_score:
		_shown_score = tracker.score
	_score.text = "SCORE %s   BEST COMBO %s" % [with_commas(roundi(_shown_score)), with_commas(tracker.best_combo)]
	var active := tracker.is_active()
	_combo.visible = active
	_list.visible = active
	_bar.visible = active
	# Damage counts your speed too, so it can show with no combo running.
	_damage.text = damage_text(tracker.damage_multiplier(), tracker.flow())
	_damage.visible = _damage.text != ""
	if not active:
		return
	_combo.text = "%s  x%d" % [with_commas(roundi(tracker.combo_points)), tracker.multiplier()]
	_list.text = combo_list_text(tracker.entries)
	_bar.value = clampf(tracker.time_left / tracker.bank_after, 0.0, 1.0)


func _show_flash(text: String, color: Color) -> void:
	_flash.text = text
	_flash.add_theme_color_override("font_color", color)
	_flash_time = 1.4


func _styled(l: Label, font_size: int) -> Label:
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 5)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
