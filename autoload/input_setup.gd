extends Node
## Registers every input action in code so bindings live in one readable place.
## Keyboard + mouse and gamepad are both bound.

const KEYS := {
	"move_forward": [KEY_W],
	"move_back": [KEY_S],
	"move_left": [KEY_A],
	"move_right": [KEY_D],
	"jump": [KEY_SPACE],
	"crouch": [KEY_CTRL, KEY_C, KEY_SHIFT],
	"kick": [KEY_F, KEY_Q],
	"reset": [KEY_R],
	"toggle_mouse": [KEY_ESCAPE],
	"debug_hud": [KEY_F1],
	"debug_tuning": [KEY_F2],
	"debug_slowmo": [KEY_F3],
	"debug_trail": [KEY_F4],
	"zone_1": [KEY_1],
	"zone_2": [KEY_2],
	"zone_3": [KEY_3],
	"zone_4": [KEY_4],
	"zone_5": [KEY_5],
	"zone_6": [KEY_6],
	"zone_7": [KEY_7],
	"zone_8": [KEY_8],
}

const MOUSE_BUTTONS := {
	"kick": [MOUSE_BUTTON_RIGHT],
}

const PAD_BUTTONS := {
	"jump": [JOY_BUTTON_A],
	"crouch": [JOY_BUTTON_B, JOY_BUTTON_RIGHT_STICK],
	"kick": [JOY_BUTTON_X, JOY_BUTTON_RIGHT_SHOULDER],
	"reset": [JOY_BUTTON_BACK],
}

const PAD_AXES := {
	"move_forward": [JOY_AXIS_LEFT_Y, -1.0],
	"move_back": [JOY_AXIS_LEFT_Y, 1.0],
	"move_left": [JOY_AXIS_LEFT_X, -1.0],
	"move_right": [JOY_AXIS_LEFT_X, 1.0],
}


func _enter_tree() -> void:
	register_actions()


static func register_actions() -> void:
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
			ev.button_index = button
			InputMap.action_add_event(action, ev)
	for action: String in PAD_AXES:
		_ensure(action)
		var ev := InputEventJoypadMotion.new()
		ev.axis = PAD_AXES[action][0]
		ev.axis_value = PAD_AXES[action][1]
		InputMap.action_add_event(action, ev)


static func _ensure(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
