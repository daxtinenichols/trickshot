class_name PauseMenu
extends CanvasLayer
## Esc / Start menu: moves list, settings (sensitivity, FOV, invert, volume)
## and custom controls. Pauses the game while open.

signal opened
signal closed

var player: Player
var is_open := false

var _root: Control
var _tabs: TabContainer
var _moves_box: VBoxContainer
var _controls_grid: GridContainer
var _controls_note: Label
var _value_rows := {}
## Rebinding in progress: [action, pad] or empty.
var _waiting: Array = []
var _bind_buttons := {}


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.visible = false
	Settings.changed.connect(_refresh)


func setup(p: Player) -> void:
	player = p
	Settings.apply_to(p)


func open(tab := -1) -> void:
	is_open = true
	_root.visible = true
	if tab >= 0:
		_tabs.current_tab = tab
	_refresh()
	get_tree().paused = true
	if player:
		player.capture_mouse(false)
	_tabs.get_tab_bar().grab_focus()
	opened.emit()


func close() -> void:
	is_open = false
	_waiting.clear()
	_root.visible = false
	get_tree().paused = false
	if player and player.use_device_input and DisplayServer.get_name() != "headless":
		player.capture_mouse(true)
	closed.emit()


func _input(event: InputEvent) -> void:
	if _waiting.is_empty() or not event.is_pressed() or event.is_echo():
		return
	get_viewport().set_input_as_handled()
	if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		_waiting.clear()
		_refresh()
		return
	var action: String = _waiting[0]
	var pad: bool = _waiting[1]
	if not GameSettings.is_bindable(event, pad):
		return
	_waiting.clear()
	var stolen := Settings.rebind(action, event)
	_controls_note.text = ""
	if not stolen.is_empty():
		var names: Array[String] = []
		for a in stolen:
			names.append(_action_name(a))
		_controls_note.text = "Moved from: %s (now unbound there)" % ", ".join(names)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		if is_open:
			close()
		else:
			open()


# ---------------------------------------------------------------- build

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 120
	panel.offset_right = -120
	panel.offset_top = 70
	panel.offset_bottom = -70
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.11, 0.97)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	_root.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	var header := HBoxContainer.new()
	col.add_child(header)
	var title := Label.new()
	title.text = "TRICKSHOT · SANDBOX"
	title.add_theme_font_size_override("font_size", 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var resume := Button.new()
	resume.text = "Resume (Esc)"
	resume.pressed.connect(close)
	header.add_child(resume)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_tabs)
	_tabs.add_child(_build_moves())
	_tabs.add_child(_build_settings())
	_tabs.add_child(_build_controls())


func _scroll(tab_name: String) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.name = tab_name
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	return sc


func _build_moves() -> Control:
	var sc := _scroll("Moves")
	_moves_box = VBoxContainer.new()
	_moves_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_moves_box.add_theme_constant_override("separation", 10)
	sc.add_child(_moves_box)
	return sc


func _fill_moves() -> void:
	for c in _moves_box.get_children():
		c.queue_free()
	var intro := Label.new()
	intro.text = "Every move is easy to do. Doing it precisely gets you more out of it. The HUD grades each move OK / GOOD / PERFECT."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.modulate = Color(1, 1, 1, 0.7)
	_moves_box.add_child(intro)
	for m: Array in MovesGuide.MOVES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		var name_l := Label.new()
		name_l.text = m[0]
		name_l.custom_minimum_size = Vector2(170, 0)
		name_l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		name_l.add_theme_font_size_override("font_size", 18)
		row.add_child(name_l)
		var text := Label.new()
		text.text = MovesGuide.describe(m[1]) + ("\n" + MovesGuide.describe(m[2]) if m[2] != "" else "")
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		_moves_box.add_child(row)


func _build_settings() -> Control:
	var sc := _scroll("Settings")
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	sc.add_child(box)
	_slider_row(box, "mouse_sensitivity", "Mouse sensitivity", 0.1, 5.0, 0.05, "%.2fx")
	_slider_row(box, "ads_sensitivity", "Aim-down-sights sensitivity", 0.3, 2.0, 0.05, "%.2fx")
	_slider_row(box, "gamepad_look_speed", "Controller look speed", 1.0, 8.0, 0.1, "%.1f")
	_slider_row(box, "fov", "Field of view", 70.0, 110.0, 1.0, "%.0f°")
	_slider_row(box, "volume", "Volume", 0.0, 1.0, 0.05, "%.0f%%", 100.0)
	var inv := CheckButton.new()
	inv.text = "Invert look up/down"
	inv.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	inv.toggled.connect(func(on: bool) -> void: _set_value("invert_y", on))
	box.add_child(inv)
	_value_rows["invert_y"] = inv
	var reset := Button.new()
	reset.text = "Reset settings"
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	reset.pressed.connect(func() -> void:
		Settings.reset_values()
		_apply_and_save())
	box.add_child(reset)
	return sc


func _slider_row(parent: Node, key: String, label: String, lo: float, hi: float, step: float, fmt: String, display_scale := 1.0) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(260, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size = Vector2(320, 0)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(s)
	var v := Label.new()
	v.custom_minimum_size = Vector2(70, 0)
	row.add_child(v)
	s.value_changed.connect(func(x: float) -> void:
		v.text = fmt % (x * display_scale)
		_set_value(key, x))
	parent.add_child(row)
	_value_rows[key] = s


func _set_value(key: String, value: Variant) -> void:
	if Settings.get(key) == value:
		return
	Settings.set(key, value)
	_apply_and_save()


func _apply_and_save() -> void:
	if player:
		Settings.apply_to(player)
	Settings.save_settings()
	_refresh()


func _build_controls() -> Control:
	var sc := _scroll("Controls")
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	sc.add_child(box)
	var hint := Label.new()
	hint.text = "Click a binding, then press the new key, mouse button or controller button. Esc cancels."
	hint.modulate = Color(1, 1, 1, 0.7)
	box.add_child(hint)
	_controls_grid = GridContainer.new()
	_controls_grid.columns = 3
	_controls_grid.add_theme_constant_override("h_separation", 14)
	_controls_grid.add_theme_constant_override("v_separation", 6)
	box.add_child(_controls_grid)
	for h in ["Action", "Keyboard / mouse", "Controller"]:
		var l := Label.new()
		l.text = h
		l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		_controls_grid.add_child(l)
	for pair: Array in GameSettings.REBINDABLE:
		var action: String = pair[0]
		var l := Label.new()
		l.text = pair[1]
		l.custom_minimum_size = Vector2(240, 0)
		_controls_grid.add_child(l)
		for pad in [false, true]:
			var b := Button.new()
			b.custom_minimum_size = Vector2(200, 0)
			b.pressed.connect(func() -> void:
				_waiting = [action, pad]
				_controls_note.text = ""
				_refresh())
			_controls_grid.add_child(b)
			_bind_buttons["%s/%s" % [action, pad]] = b
	_controls_note = Label.new()
	_controls_note.add_theme_color_override("font_color", Color(1.0, 0.6, 0.4))
	box.add_child(_controls_note)
	var reset := Button.new()
	reset.text = "Reset controls to defaults"
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	reset.pressed.connect(func() -> void:
		Settings.reset_bindings()
		_controls_note.text = "")
	box.add_child(reset)
	return sc


func _refresh() -> void:
	for key: String in _value_rows:
		var c: Control = _value_rows[key]
		if c is HSlider:
			(c as HSlider).set_value_no_signal(Settings.get(key))
			(c as HSlider).value_changed.emit((c as HSlider).value)
		elif c is CheckButton:
			(c as CheckButton).set_pressed_no_signal(Settings.get(key))
	for pair: Array in GameSettings.REBINDABLE:
		var action: String = pair[0]
		for pad in [false, true]:
			var b: Button = _bind_buttons["%s/%s" % [action, pad]]
			var waiting: bool = not _waiting.is_empty() and _waiting[0] == action and _waiting[1] == pad
			b.text = ("Press a %s..." % ("button" if pad else "key")) if waiting else GameSettings.event_label(GameSettings.slot_event(action, pad))
	_fill_moves()


func _action_name(action: String) -> String:
	for pair: Array in GameSettings.REBINDABLE:
		if pair[0] == action:
			return pair[1]
	return action
