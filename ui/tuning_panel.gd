class_name TuningPanel
extends CanvasLayer
## Live sliders for every value in the player's MovementTuning (F2).
## Changes apply instantly. "Save" keeps them for next launch (user://);
## when running from the editor, "Save as project defaults" writes them into
## res://player/default_tuning.tres so they can be committed.

const USER_PATH := "user://tuning.tres"
const DEFAULTS_PATH := "res://player/default_tuning.tres"

var player: Player
var _panel: PanelContainer
var _list: VBoxContainer
var _status: Label
var _rows := {}

## Tuning fields that are really player preferences (Esc menu > Settings).
## Hidden here, and never baked into project defaults.
const PLAYER_SETTINGS := [&"mouse_sensitivity", &"gamepad_look_speed", &"base_fov"]
var _mouse_was_captured := false


func _ready() -> void:
	layer = 20
	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_panel.offset_left = -460
	_panel.offset_right = -10
	_panel.offset_top = 10
	_panel.offset_bottom = -10
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.1, 0.92)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.visible = false
	add_child(_panel)

	var outer := VBoxContainer.new()
	_panel.add_child(outer)
	var title := Label.new()
	title.text = "Movement tuning (F2 to close)"
	title.add_theme_font_size_override("font_size", 20)
	outer.add_child(title)

	var buttons := HBoxContainer.new()
	outer.add_child(buttons)
	_button(buttons, "Save", _save_user)
	_button(buttons, "Reset", _reset)
	if OS.has_feature("editor"):
		_button(buttons, "Save as project defaults", _save_defaults)
	_status = Label.new()
	_status.modulate = Color(1, 1, 1, 0.7)
	outer.add_child(_status)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)


func setup(p: Player) -> void:
	player = p
	if ResourceLoader.exists(USER_PATH):
		var saved := ResourceLoader.load(USER_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as MovementTuning
		if saved != null:
			copy_tuning(saved, player.tuning)
			Settings.apply_to(player)
			_status.text = "Loaded your saved tuning."
	_build_rows()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_tuning"):
		_panel.visible = not _panel.visible
		if _panel.visible:
			_mouse_was_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			_refresh()
		elif _mouse_was_captured:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Copies every script property from one tuning resource to another.
static func copy_tuning(from: MovementTuning, to: MovementTuning) -> void:
	for prop in from.get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			to.set(prop.name, from.get(prop.name))


func _build_rows() -> void:
	for c in _list.get_children():
		c.queue_free()
	_rows.clear()
	for prop in player.tuning.get_property_list():
		if prop.usage & PROPERTY_USAGE_CATEGORY or prop.usage & PROPERTY_USAGE_GROUP:
			if prop.usage & PROPERTY_USAGE_GROUP and not (prop.usage & PROPERTY_USAGE_CATEGORY):
				var header := Label.new()
				header.text = prop.name
				header.add_theme_font_size_override("font_size", 16)
				header.add_theme_color_override("font_color", Color(1, 0.8, 0.35))
				_list.add_child(header)
			continue
		if not (prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		if prop.name in PLAYER_SETTINGS:
			continue  # set per player in the Esc menu
		match prop.type:
			TYPE_FLOAT, TYPE_INT:
				_add_slider(prop)
			TYPE_BOOL:
				_add_check(prop)


func _add_slider(prop: Dictionary) -> void:
	var row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = String(prop.name).replace("_", " ")
	name_label.custom_minimum_size = Vector2(190, 0)
	name_label.clip_text = true
	row.add_child(name_label)
	var slider := HSlider.new()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var parts: PackedStringArray = String(prop.hint_string).split(",")
	if prop.hint == PROPERTY_HINT_RANGE and parts.size() >= 2:
		slider.min_value = float(parts[0])
		slider.max_value = float(parts[1])
		slider.step = float(parts[2]) if parts.size() >= 3 else 0.01
	else:
		slider.min_value = 0.0
		slider.max_value = 100.0
		slider.step = 0.01
	row.add_child(slider)
	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(60, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	var pname: String = prop.name
	slider.value = player.tuning.get(pname)
	value_label.text = _fmt(slider.value)
	slider.value_changed.connect(func(v: float) -> void:
		player.tuning.set(pname, v)
		value_label.text = _fmt(v))
	_rows[pname] = slider
	_list.add_child(row)


func _add_check(prop: Dictionary) -> void:
	var check := CheckBox.new()
	var pname: String = prop.name
	check.text = pname.replace("_", " ")
	check.button_pressed = player.tuning.get(pname)
	check.toggled.connect(func(on: bool) -> void: player.tuning.set(pname, on))
	_rows[pname] = check
	_list.add_child(check)


func _refresh() -> void:
	for pname: String in _rows:
		var c: Control = _rows[pname]
		if c is HSlider:
			(c as HSlider).set_value_no_signal(player.tuning.get(pname))
			var row := c.get_parent()
			(row.get_child(2) as Label).text = _fmt(player.tuning.get(pname))
		elif c is CheckBox:
			(c as CheckBox).set_pressed_no_signal(player.tuning.get(pname))


func _fmt(v: float) -> String:
	return ("%.4f" % v).rstrip("0").rstrip(".")


func _button(parent: Node, text: String, fn: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(fn)
	parent.add_child(b)


func _save_user() -> void:
	var err := ResourceSaver.save(player.tuning.duplicate(), USER_PATH)
	_status.text = "Saved for next launch." if err == OK else "Save failed (error %d)." % err


func _save_defaults() -> void:
	var copy: MovementTuning = player.tuning.duplicate()
	var fresh := MovementTuning.new()
	for pname: StringName in PLAYER_SETTINGS:
		copy.set(pname, fresh.get(pname))
	var err := ResourceSaver.save(copy, DEFAULTS_PATH)
	_status.text = "Wrote project defaults; commit player/default_tuning.tres." if err == OK else "Save failed (error %d)." % err


func _reset() -> void:
	copy_tuning(MovementTuning.new(), player.tuning)
	Settings.apply_to(player)
	if ResourceLoader.exists(USER_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(USER_PATH))
	_refresh()
	_status.text = "Reset to code defaults (saved tuning cleared)."
