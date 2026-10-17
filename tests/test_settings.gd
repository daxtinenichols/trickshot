extends TestCase
## Settings and custom controls: rebinding, conflicts, save/load, reset,
## applying to the player, and the pause menu.

const TEST_PATH := "user://test_settings.cfg"
const SANDBOX := preload("res://levels/sandbox.tscn")


func before_each() -> void:
	Settings.save_path = TEST_PATH
	Settings.custom_bindings.clear()
	Settings.reset_values()
	InputSetup.register_actions()
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


func after_each() -> void:
	Settings.reset_bindings()
	Settings.reset_values()
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	Settings.save_path = GameSettings.PATH
	tree.paused = false
	await tree.process_frame


func _key(code: Key) -> InputEventKey:
	var k := InputEventKey.new()
	k.physical_keycode = code
	k.pressed = true
	return k


func _pad(button: JoyButton) -> InputEventJoypadButton:
	var b := InputEventJoypadButton.new()
	b.button_index = button
	b.pressed = true
	return b


func test_default_slots() -> void:
	check(GameSettings.event_label(GameSettings.slot_event("jump", false)) == "Space", "jump is Space")
	check(GameSettings.event_label(GameSettings.slot_event("jump", true)) == "A", "jump is A")
	check(GameSettings.event_label(GameSettings.slot_event("fire", false)) == "Left mouse", "fire is left mouse")
	check(GameSettings.event_label(GameSettings.slot_event("fire", true)) == "RT", "fire is RT")
	check(GameSettings.event_label(GameSettings.slot_event("quick_turn", false)) == "Shift", "quick turn is Shift")
	check(GameSettings.event_label(GameSettings.slot_event("lean_left", false)) == "Q", "lean left is Q")
	check(GameSettings.event_label(GameSettings.slot_event("lean_right", true)) == "D-pad right", "lean right is D-pad right (%s)" % GameSettings.event_label(GameSettings.slot_event("lean_right", true)))
	check(GameSettings.event_label(GameSettings.slot_event("quick_turn", true)) == "LB", "quick turn is LB")


func test_rebind_replaces_slot_only() -> void:
	Settings.rebind("jump", _key(KEY_J))
	check(InputMap.action_has_event("jump", _key(KEY_J)), "J now jumps")
	check(not InputMap.action_has_event("jump", _key(KEY_SPACE)), "Space no longer jumps")
	check(GameSettings.slot_event("jump", true) != null, "controller binding untouched")


func test_rebind_takes_key_from_other_action() -> void:
	var stolen := Settings.rebind("jump", _key(KEY_F))
	check(stolen.size() == 1 and stolen[0] == "kick", "kick loses F (got %s)" % [stolen])
	check(GameSettings.slot_event("kick", false) == null, "kick keyboard slot is empty")
	check(InputMap.action_has_event("jump", _key(KEY_F)), "F jumps")


func test_rebind_controller_button() -> void:
	Settings.rebind("kick", _pad(JOY_BUTTON_Y))
	check(GameSettings.event_label(GameSettings.slot_event("kick", true)) == "Y", "kick on Y")
	check(GameSettings.slot_event("fire_mode", true) == null, "fire mode lost Y")
	check(GameSettings.event_label(GameSettings.slot_event("kick", false)) == "F", "keyboard kick untouched")


func test_bindings_and_values_survive_save_and_load() -> void:
	Settings.rebind("crouch", _key(KEY_X))
	Settings.mouse_sensitivity = 1.7
	Settings.invert_y = true
	Settings.fov = 100.0
	Settings.save_settings()
	# Wipe to defaults, then load from disk.
	InputSetup.register_actions()
	Settings.reset_values()
	check(not InputMap.action_has_event("crouch", _key(KEY_X)), "defaults restored before load")
	Settings.load_settings()
	check(InputMap.action_has_event("crouch", _key(KEY_X)), "crouch on X after load")
	check_near(Settings.mouse_sensitivity, 1.7, 0.001, "mouse sensitivity loaded")
	check(Settings.invert_y, "invert loaded")
	check_near(Settings.fov, 100.0, 0.001, "fov loaded")


func test_reset_bindings() -> void:
	Settings.rebind("jump", _key(KEY_J))
	Settings.reset_bindings()
	check(InputMap.action_has_event("jump", _key(KEY_SPACE)), "Space jumps again")
	check(InputMap.action_get_events("jump").size() == 2, "no duplicate bindings (%d)" % InputMap.action_get_events("jump").size())
	check(InputMap.action_has_event("debug_hud", _key(KEY_F1)), "non-rebindable actions still bound")


func test_escape_cannot_be_bound() -> void:
	check(not GameSettings.is_bindable(_key(KEY_ESCAPE), false), "Esc is reserved for the menu")
	check(GameSettings.is_bindable(_key(KEY_E), false), "E is fine")
	check(not GameSettings.is_bindable(_key(KEY_E), true), "a key can't go in the controller slot")


func test_apply_to_player() -> void:
	var w := TestWorld.new()
	tree.root.add_child(w)
	w.add_floor()
	var p := w.spawn_player(Vector3(0, 0.05, 0))
	Settings.mouse_sensitivity = 2.0
	Settings.fov = 95.0
	Settings.invert_y = true
	Settings.ads_sensitivity = 0.5
	Settings.apply_to(p)
	check_near(p.tuning.mouse_sensitivity, GameSettings.DEFAULT_MOUSE_SENS * 2.0, 0.00001, "mouse sensitivity applied")
	check_near(p.tuning.base_fov, 95.0, 0.001, "fov applied")
	check(p.invert_y, "invert applied")
	p.aim_zoom = 1.0
	var full := p.aim_sensitivity_scale()
	Settings.ads_sensitivity = 1.0
	Settings.apply_to(p)
	check_near(full, p.aim_sensitivity_scale() * 0.5, 0.0001, "ADS sensitivity scales aimed look speed")
	w.queue_free()


func test_pause_menu_pauses_and_rebinds() -> void:
	var level: Node3D = SANDBOX.instantiate()
	tree.root.add_child(level)
	var player: Player = level.get_node("Player")
	player.use_device_input = false
	await tree.process_frame
	var menu: PauseMenu = level.menu
	menu.open(2)
	check(tree.paused, "menu pauses the game")
	# Click the jump keyboard slot, then press K.
	menu._bind_buttons["jump/false"].pressed.emit()
	check(menu._bind_buttons["jump/false"].text.begins_with("Press"), "slot waits for a key")
	menu._input(_key(KEY_K))
	check(InputMap.action_has_event("jump", _key(KEY_K)), "K bound to jump through the menu")
	check(menu._bind_buttons["jump/false"].text == "K", "slot shows K")
	menu.close()
	check(not tree.paused, "closing resumes")
	level.queue_free()
	await tree.process_frame


func test_moves_list_names_current_bindings() -> void:
	var text := MovesGuide.describe("{jump} to jump, {prone} to dive")
	check(text == "Space / A to jump, Z / D-pad down to dive", "placeholders filled (%s)" % text)
	Settings.rebind("jump", _key(KEY_J))
	check(MovesGuide.describe("{jump}").begins_with("J"), "follows rebinding")


func test_menu_and_debug_inputs_are_reserved() -> void:
	check(not GameSettings.is_bindable(_pad(JOY_BUTTON_START), true), "Start opens the menu")
	check(not GameSettings.is_bindable(_key(KEY_F1), false), "F1 is the HUD toggle")
	check(not GameSettings.is_bindable(_key(KEY_1), false), "1 is a zone key")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	check(not GameSettings.is_bindable(wheel, false), "mouse wheel can't be held")
	var m4 := InputEventMouseButton.new()
	m4.button_index = MOUSE_BUTTON_XBUTTON1
	m4.pressed = true
	check(GameSettings.is_bindable(m4, false), "mouse 4 is fine")


func test_escape_and_start_open_the_menu_for_real() -> void:
	var level: Node3D = SANDBOX.instantiate()
	tree.root.add_child(level)
	var player: Player = level.get_node("Player")
	player.use_device_input = false
	await tree.process_frame
	var menu: PauseMenu = level.menu
	var esc := _key(KEY_ESCAPE)
	tree.root.push_input(esc)
	await tree.process_frame
	check(menu.is_open and tree.paused, "Esc opens the pause menu")
	var up := _key(KEY_ESCAPE)
	up.pressed = false
	tree.root.push_input(up)
	tree.root.push_input(_key(KEY_ESCAPE))
	await tree.process_frame
	check(not menu.is_open and not tree.paused, "Esc again closes it")
	# A controller that isn't device 0 (wireless receivers, Steam Input).
	var start := _pad(JOY_BUTTON_START)
	start.device = 3
	tree.root.push_input(start)
	await tree.process_frame
	check(menu.is_open, "Start on any controller opens it")
	menu.close()
	level.queue_free()
	await tree.process_frame


func test_settings_tab_lists_controllers() -> void:
	check(PauseMenu.pads_text([]).begins_with("Controllers: none detected"), "says when none are found")
	check(PauseMenu.pads_text(["Xbox 360 Controller (device 0)"] as Array[String]) == "Controllers: Xbox 360 Controller (device 0)", "names the pad")
	var silent := PauseMenu.pads_detail([0], {0: "#controller_xbox360"}, {})
	check(silent.contains("Steam Input controller (xbox360) (device 0): no input yet"), "names Steam's stand-in pad and says it's silent")
	check(silent.contains("Disable Steam Input"), "explains how to turn Steam Input off")
	var live := PauseMenu.pads_detail([1], {1: "Xbox 360 Controller"}, {1: "A"})
	check(live.contains("Xbox 360 Controller (device 1): working, last input: A"), "shows the last button pressed")
	check(not live.contains("Disable Steam Input"), "no Steam hint when the pad works")


func test_menu_has_map_buttons() -> void:
	var level: Node = load("res://levels/sandbox.tscn").instantiate()
	tree.root.add_child(level)
	await tree.process_frame
	var names: Array[String] = []
	for b in level.menu.find_children("*", "Button", true, false):
		names.append((b as Button).text)
	for m in ["Sandbox", "Rooftops", "Combo Park"]:
		check(m in names, "menu has a %s button" % m)
	level.queue_free()
	await tree.process_frame


func test_controller_test_records_input() -> void:
	InputSetup.pad_activity.clear()
	var a := _pad(JOY_BUTTON_A)
	a.device = 2
	Input.parse_input_event(a)
	await tree.process_frame
	check(InputSetup.pad_activity.get(2, "") == "A", "a button press on controller 2 is recorded (got %s)" % str(InputSetup.pad_activity))
	InputSetup.pad_activity.clear()


func test_controller_bindings_match_any_device() -> void:
	for action: String in ["jump", "pause", "lean_left"]:
		for e in InputMap.action_get_events(action):
			if e is InputEventJoypadButton or e is InputEventJoypadMotion:
				check(e.device == InputSetup.ALL_DEVICES, "%s pad binding works on every controller" % action)
	var a := _pad(JOY_BUTTON_A)
	a.device = 2
	check(InputMap.event_is_action(a, "jump"), "A on controller 2 jumps")
