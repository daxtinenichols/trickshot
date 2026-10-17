extends Node
## Registers every input action in code so bindings live in one readable place.
## Keyboard + mouse and gamepad are both bound.

## Events made in code default to device 0. -1 matches any controller, which
## matters when the pad isn't device 0 (wireless receivers, Steam Input).
const ALL_DEVICES := -1

const KEYS := {
	"move_forward": [KEY_W],
	"move_back": [KEY_S],
	"move_left": [KEY_A],
	"move_right": [KEY_D],
	"jump": [KEY_SPACE],
	"crouch": [KEY_CTRL, KEY_C],
	"prone": [KEY_Z],
	"kick": [KEY_F],
	"boost": [KEY_SHIFT],
	"lean_left": [KEY_Q],
	"lean_right": [KEY_E],
	"reload": [KEY_R],
	"fire_mode": [KEY_B, KEY_V],
	"reset": [KEY_BACKSPACE],
	"pause": [KEY_ESCAPE],
	"debug_hud": [KEY_F1],
	"debug_tuning": [KEY_F2],
	"debug_slowmo": [KEY_F3],
	"debug_trail": [KEY_F4],
	"toggle_corner_cam": [KEY_F12],
	"zone_1": [KEY_1],
	"zone_2": [KEY_2],
	"zone_3": [KEY_3],
	"zone_4": [KEY_4],
	"zone_5": [KEY_5],
	"zone_6": [KEY_6],
	"zone_7": [KEY_7],
	"zone_8": [KEY_8],
	"zone_9": [KEY_9],
	"zone_10": [KEY_0],
	"zone_11": [KEY_MINUS],
}

const MOUSE_BUTTONS := {
	"fire": [MOUSE_BUTTON_LEFT],
	"aim": [MOUSE_BUTTON_RIGHT],
}

const PAD_BUTTONS := {
	"jump": [JOY_BUTTON_A],
	"crouch": [JOY_BUTTON_B],
	"prone": [JOY_BUTTON_DPAD_DOWN],
	"kick": [JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_RIGHT_STICK],
	"reload": [JOY_BUTTON_X],
	"fire_mode": [JOY_BUTTON_Y],
	"reset": [JOY_BUTTON_BACK],
	"boost": [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_LEFT_STICK],
	"lean_left": [JOY_BUTTON_DPAD_LEFT],
	"lean_right": [JOY_BUTTON_DPAD_RIGHT],
	"pause": [JOY_BUTTON_START],
}

const PAD_AXES := {
	"move_forward": [JOY_AXIS_LEFT_Y, -1.0],
	"move_back": [JOY_AXIS_LEFT_Y, 1.0],
	"move_left": [JOY_AXIS_LEFT_X, -1.0],
	"move_right": [JOY_AXIS_LEFT_X, 1.0],
	"fire": [JOY_AXIS_TRIGGER_RIGHT, 1.0],
	"aim": [JOY_AXIS_TRIGGER_LEFT, 1.0],
}


## Last input seen from each controller (device -> "A", "Left stick up"...),
## for the controller test in Settings and the log.
var pad_activity := {}


func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # the test works in the pause menu
	register_actions()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


func _ready() -> void:
	var pads := Input.get_connected_joypads()
	print("Controllers at start: %d" % pads.size())
	for d in pads:
		print("  device %d: %s (guid %s)" % [d, Input.get_joy_name(d), Input.get_joy_guid(d)])


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.is_pressed():
		_note_pad(event.device, GameSettings.event_label(event))
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5:
		_note_pad(event.device, GameSettings.event_label(event))


func _note_pad(device: int, what: String) -> void:
	if not pad_activity.has(device):
		print("Controller %d first input: %s" % [device, what])
	pad_activity[device] = what


# A method (not a lambda) and disconnected on exit: a lambda left connected
# to the Input singleton aborts the engine on shutdown.
func _exit_tree() -> void:
	Input.joy_connection_changed.disconnect(_on_joy_connection_changed)


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	print("Controller %d %s: %s" % [device, "connected" if connected else "disconnected", Input.get_joy_name(device)])
	if not connected:
		pad_activity.erase(device)


## Right-stick look, from whichever connected controller is pushing it most.
static func look_stick() -> Vector2:
	var best := Vector2.ZERO
	for d in Input.get_connected_joypads():
		var v := Vector2(Input.get_joy_axis(d, JOY_AXIS_RIGHT_X), Input.get_joy_axis(d, JOY_AXIS_RIGHT_Y))
		if v.length() > best.length():
			best = v
	return best


## "Xbox 360 Controller (device 0)" lines for the settings screen.
static func controller_names() -> Array[String]:
	var out: Array[String] = []
	for d in Input.get_connected_joypads():
		out.append("%s (device %d)" % [pad_name(Input.get_joy_name(d)), d])
	return out


## Steam Input's stand-in controllers report names like "#controller_xbox360".
static func is_steam_virtual(joy_name: String) -> bool:
	return joy_name.begins_with("#controller") or joy_name.containsn("steam virtual")


static func pad_name(joy_name: String) -> String:
	if joy_name.begins_with("#controller_"):
		return "Steam Input controller (%s)" % joy_name.trim_prefix("#controller_")
	return joy_name if joy_name != "" else "Controller"


## (Re)creates every action with its default bindings.
static func register_actions() -> void:
	for table: Dictionary in [KEYS, MOUSE_BUTTONS, PAD_BUTTONS, PAD_AXES]:
		for action: String in table:
			if InputMap.has_action(action):
				InputMap.action_erase_events(action)
	for action: String in KEYS:
		_ensure(action)
		for key: Key in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
	for action: String in MOUSE_BUTTONS:
		_ensure(action)
		for button: MouseButton in MOUSE_BUTTONS[action]:
			var ev := InputEventMouseButton.new()
			ev.button_index = button
			InputMap.action_add_event(action, ev)
	for action: String in PAD_BUTTONS:
		_ensure(action)
		for button: JoyButton in PAD_BUTTONS[action]:
			var ev := InputEventJoypadButton.new()
			ev.device = ALL_DEVICES
			ev.button_index = button
			InputMap.action_add_event(action, ev)
	for action: String in PAD_AXES:
		_ensure(action)
		var ev := InputEventJoypadMotion.new()
		ev.device = ALL_DEVICES
		ev.axis = PAD_AXES[action][0]
		ev.axis_value = PAD_AXES[action][1]
		InputMap.action_add_event(action, ev)


static func _ensure(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
