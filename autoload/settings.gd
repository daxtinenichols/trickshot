class_name GameSettings
extends Node
## Player settings (sensitivity, FOV, invert, volume) and custom key/button
## bindings. Saved to user://settings.cfg. Autoloaded as `Settings`.
##
## Each rebindable action has two slots: keyboard/mouse and controller.

signal changed

const PATH := "user://settings.cfg"

## Actions players can rebind, in menu order, with display names.
const REBINDABLE := [
	["move_forward", "Move forward"],
	["move_back", "Move back"],
	["move_left", "Move left"],
	["move_right", "Move right"],
	["jump", "Jump / vault / climb"],
	["crouch", "Crouch / slide / roll"],
	["kick", "Kick"],
	["steer", "Steer with the mouse (hold)"],
	["lean_left", "Lean left / quick turn / side flip"],
	["lean_right", "Lean right / quick turn / side flip"],
	["fire", "Fire"],
	["aim", "Aim down sights"],
	["reload", "Reload"],
	["fire_mode", "Semi / full auto"],
	["slow_mo", "Slow motion"],
	["reset", "Respawn"],
]

const DEFAULT_MOUSE_SENS := 0.0025

## Multiplier on the default mouse sensitivity (1 = default).
var mouse_sensitivity := 1.0
## Look speed while aiming down sights, relative to hip fire (1 = matched).
var ads_sensitivity := 1.0
var gamepad_look_speed := 3.2
var invert_y := false
## The third-person camera turns with flips and rolls (ChaseCamera reads it).
var camera_follow_flips := false
## Aim help, 0 (off) to 1: shots bend onto nearby heads and bodies, and
## controller look slows over targets.
var aim_assist := 0.5
var fov := 85.0
var volume := 0.8
## action -> {"kbm": event dict or null, "pad": event dict or null}.
## Only actions the player changed are stored; the rest use the defaults.
var custom_bindings := {}
## Saved binding names from older versions -> the action they are now.
const RENAMED_ACTIONS := {"boost": "steer"}
## Where settings are saved (tests point this somewhere else).
var save_path := PATH


func _ready() -> void:
	load_settings()


# ---------------------------------------------------------------- values

func apply_to(p: Player) -> void:
	p.tuning.mouse_sensitivity = DEFAULT_MOUSE_SENS * mouse_sensitivity
	p.tuning.gamepad_look_speed = gamepad_look_speed
	p.tuning.base_fov = fov
	p.invert_y = invert_y
	p.ads_sensitivity = ads_sensitivity
	if p.weapon is Pistol:
		(p.weapon as Pistol).aim_assist = aim_assist
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(volume, 0.0001)))


func reset_values() -> void:
	mouse_sensitivity = 1.0
	ads_sensitivity = 1.0
	gamepad_look_speed = 3.2
	invert_y = false
	camera_follow_flips = false
	aim_assist = 0.5
	fov = 85.0
	volume = 0.8
	changed.emit()


# ---------------------------------------------------------------- bindings

static func is_pad_event(ev: InputEvent) -> bool:
	return ev is InputEventJoypadButton or ev is InputEventJoypadMotion


static func is_bindable(ev: InputEvent, pad: bool) -> bool:
	if pad:
		if ev is InputEventJoypadMotion:
			return absf((ev as InputEventJoypadMotion).axis_value) >= 0.5
		return ev is InputEventJoypadButton and not _is_reserved(_normalize(ev))
	if ev is InputEventKey:
		return not _is_reserved(_normalize(ev))
	if ev is InputEventMouseButton:
		# Wheel "presses" arrive and release in one frame; held actions miss them.
		var b := (ev as InputEventMouseButton).button_index
		return b not in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]
	return false


## Inputs owned by actions players can't rebind (menu, zones, debug keys).
static func _is_reserved(ev: InputEvent) -> bool:
	var rebindable := {}
	for pair: Array in REBINDABLE:
		rebindable[pair[0]] = true
	for action in InputMap.get_actions():
		if rebindable.has(String(action)) or String(action).begins_with("ui_"):
			continue
		for existing in InputMap.action_get_events(action):
			if _same_input(existing, ev):
				return true
	return false


## The event in an action's keyboard/mouse or controller slot (or null).
static func slot_event(action: String, pad: bool) -> InputEvent:
	for ev in InputMap.action_get_events(action):
		if is_pad_event(ev) == pad:
			return ev
	return null


## Puts `ev` in the action's slot, replacing what was there. Another action
## already using the same input loses it, so one input never does two things.
## Returns the actions that lost the input.
func rebind(action: String, ev: InputEvent) -> Array[String]:
	var pad := is_pad_event(ev)
	var clean := _normalize(ev)
	var stolen: Array[String] = []
	for pair: Array in REBINDABLE:
		var other: String = pair[0]
		if other == action:
			continue
		for existing in InputMap.action_get_events(other):
			if _same_input(existing, clean):
				InputMap.action_erase_event(other, existing)
				_store(other)
				stolen.append(other)
	_set_slot(action, pad, clean)
	_store(action)
	save_settings()
	changed.emit()
	return stolen


func reset_bindings() -> void:
	custom_bindings.clear()
	for pair: Array in REBINDABLE:
		InputMap.action_erase_events(pair[0])
	InputSetup.register_actions()
	save_settings()
	changed.emit()


## Short display name for an event: "Space", "Mouse 1", "A", "RT"...
static func event_label(ev: InputEvent) -> String:
	if ev == null:
		return "—"
	if ev is InputEventKey:
		var k := ev as InputEventKey
		var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
		return OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(code) if DisplayServer.get_name() != "headless" else code)
	if ev is InputEventMouseButton:
		match (ev as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT: return "Left mouse"
			MOUSE_BUTTON_RIGHT: return "Right mouse"
			MOUSE_BUTTON_MIDDLE: return "Middle mouse"
			MOUSE_BUTTON_WHEEL_UP: return "Wheel up"
			MOUSE_BUTTON_WHEEL_DOWN: return "Wheel down"
			MOUSE_BUTTON_XBUTTON1: return "Mouse 4"
			MOUSE_BUTTON_XBUTTON2: return "Mouse 5"
		return "Mouse %d" % (ev as InputEventMouseButton).button_index
	if ev is InputEventJoypadButton:
		const NAMES := {
			JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
			JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
			JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
			JOY_BUTTON_BACK: "Back", JOY_BUTTON_START: "Start",
			JOY_BUTTON_DPAD_UP: "D-pad up", JOY_BUTTON_DPAD_DOWN: "D-pad down",
			JOY_BUTTON_DPAD_LEFT: "D-pad left", JOY_BUTTON_DPAD_RIGHT: "D-pad right",
		}
		return NAMES.get((ev as InputEventJoypadButton).button_index, "Button %d" % (ev as InputEventJoypadButton).button_index)
	if ev is InputEventJoypadMotion:
		var m := ev as InputEventJoypadMotion
		var positive := m.axis_value > 0.0
		match m.axis:
			JOY_AXIS_TRIGGER_LEFT: return "LT"
			JOY_AXIS_TRIGGER_RIGHT: return "RT"
			JOY_AXIS_LEFT_X: return "Left stick " + ("right" if positive else "left")
			JOY_AXIS_LEFT_Y: return "Left stick " + ("down" if positive else "up")
			JOY_AXIS_RIGHT_X: return "Right stick " + ("right" if positive else "left")
			JOY_AXIS_RIGHT_Y: return "Right stick " + ("down" if positive else "up")
		return "Axis %d" % m.axis
	return ev.as_text()


func _set_slot(action: String, pad: bool, ev: InputEvent) -> void:
	for existing in InputMap.action_get_events(action):
		if is_pad_event(existing) == pad:
			InputMap.action_erase_event(action, existing)
	if ev != null:
		InputMap.action_add_event(action, ev)


func _store(action: String) -> void:
	custom_bindings[action] = {
		"kbm": encode_event(slot_event(action, false)),
		"pad": encode_event(slot_event(action, true)),
	}


static func _normalize(ev: InputEvent) -> InputEvent:
	if ev is InputEventKey:
		var k := InputEventKey.new()
		var src := ev as InputEventKey
		k.physical_keycode = src.physical_keycode if src.physical_keycode != KEY_NONE else src.keycode
		return k
	if ev is InputEventMouseButton:
		var mb := InputEventMouseButton.new()
		mb.button_index = (ev as InputEventMouseButton).button_index
		return mb
	if ev is InputEventJoypadButton:
		var jb := InputEventJoypadButton.new()
		jb.device = InputSetup.ALL_DEVICES
		jb.button_index = (ev as InputEventJoypadButton).button_index
		return jb
	if ev is InputEventJoypadMotion:
		var jm := InputEventJoypadMotion.new()
		jm.device = InputSetup.ALL_DEVICES
		jm.axis = (ev as InputEventJoypadMotion).axis
		jm.axis_value = signf((ev as InputEventJoypadMotion).axis_value)
		return jm
	return ev


static func _same_input(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		return (a as InputEventKey).physical_keycode == (b as InputEventKey).physical_keycode
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return (a as InputEventMouseButton).button_index == (b as InputEventMouseButton).button_index
	if a is InputEventJoypadButton and b is InputEventJoypadButton:
		return (a as InputEventJoypadButton).button_index == (b as InputEventJoypadButton).button_index
	if a is InputEventJoypadMotion and b is InputEventJoypadMotion:
		var ma := a as InputEventJoypadMotion
		var mb := b as InputEventJoypadMotion
		return ma.axis == mb.axis and signf(ma.axis_value) == signf(mb.axis_value)
	return false


static func encode_event(ev: InputEvent) -> Variant:
	if ev is InputEventKey:
		return {"type": "key", "code": int((ev as InputEventKey).physical_keycode)}
	if ev is InputEventMouseButton:
		return {"type": "mouse", "button": int((ev as InputEventMouseButton).button_index)}
	if ev is InputEventJoypadButton:
		return {"type": "joy_button", "button": int((ev as InputEventJoypadButton).button_index)}
	if ev is InputEventJoypadMotion:
		return {"type": "joy_axis", "axis": int((ev as InputEventJoypadMotion).axis), "value": signf((ev as InputEventJoypadMotion).axis_value)}
	return null


static func decode_event(d: Variant) -> InputEvent:
	if not (d is Dictionary):
		return null
	match d.get("type", ""):
		"key":
			var k := InputEventKey.new()
			k.physical_keycode = int(d.code) as Key
			return k
		"mouse":
			var mb := InputEventMouseButton.new()
			mb.button_index = int(d.button) as MouseButton
			return mb
		"joy_button":
			var jb := InputEventJoypadButton.new()
			jb.device = InputSetup.ALL_DEVICES
			jb.button_index = int(d.button) as JoyButton
			return jb
		"joy_axis":
			var jm := InputEventJoypadMotion.new()
			jm.device = InputSetup.ALL_DEVICES
			jm.axis = int(d.axis) as JoyAxis
			jm.axis_value = float(d.value)
			return jm
	return null


# ---------------------------------------------------------------- save / load

func save_settings(path := "") -> void:
	path = path if path != "" else save_path
	var cfg := ConfigFile.new()
	cfg.set_value("look", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("look", "ads_sensitivity", ads_sensitivity)
	cfg.set_value("look", "gamepad_look_speed", gamepad_look_speed)
	cfg.set_value("look", "invert_y", invert_y)
	cfg.set_value("look", "camera_follow_flips", camera_follow_flips)
	cfg.set_value("look", "aim_assist", aim_assist)
	cfg.set_value("look", "fov", fov)
	cfg.set_value("audio", "volume", volume)
	for action: String in custom_bindings:
		cfg.set_value("bindings", action, custom_bindings[action])
	cfg.save(path)


func load_settings(path := "") -> void:
	path = path if path != "" else save_path
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	mouse_sensitivity = cfg.get_value("look", "mouse_sensitivity", mouse_sensitivity)
	ads_sensitivity = cfg.get_value("look", "ads_sensitivity", ads_sensitivity)
	gamepad_look_speed = cfg.get_value("look", "gamepad_look_speed", gamepad_look_speed)
	invert_y = cfg.get_value("look", "invert_y", invert_y)
	camera_follow_flips = cfg.get_value("look", "camera_follow_flips", camera_follow_flips)
	aim_assist = cfg.get_value("look", "aim_assist", aim_assist)
	fov = cfg.get_value("look", "fov", fov)
	volume = cfg.get_value("audio", "volume", volume)
	custom_bindings.clear()
	if cfg.has_section("bindings"):
		for saved in cfg.get_section_keys("bindings"):
			# Shift's action was renamed from boost (the boost was removed).
			var action: String = RENAMED_ACTIONS.get(saved, saved)
			if not InputMap.has_action(action):
				continue
			var slots: Dictionary = cfg.get_value("bindings", saved, {})
			custom_bindings[action] = slots
			_set_slot(action, false, decode_event(slots.get("kbm")))
			_set_slot(action, true, decode_event(slots.get("pad")))
		_free_taken_defaults()
	changed.emit()


## After loading custom bindings: an action still on its default loses any
## input a custom binding took, so one input never does two things (a save
## from before an action existed can't know to take it away).
func _free_taken_defaults() -> void:
	for pair: Array in REBINDABLE:
		var other: String = pair[0]
		if custom_bindings.has(other):
			continue
		for existing in InputMap.action_get_events(other):
			if _taken_by_custom(existing):
				InputMap.action_erase_event(other, existing)


func _taken_by_custom(ev: InputEvent) -> bool:
	for action: String in custom_bindings:
		for mine in InputMap.action_get_events(action):
			if _same_input(ev, mine):
				return true
	return false
