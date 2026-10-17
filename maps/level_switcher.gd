extends Node
## Autoload "Levels": F11 cycles through the playable levels (F5-F8 belong
## to the Godot editor, which uses them to run, pause and stop the game).

const LEVELS := [
	["res://levels/sandbox.tscn", "Sandbox"],
	["res://maps/rooftops.tscn", "Rooftops"],
	["res://maps/combo_park.tscn", "Combo Park"],
	["res://campaign/campaign.tscn", "Campaign"],
]
const ACTION := "next_level"


func _ready() -> void:
	# Registered as an action so the rebind menu treats F11 as reserved.
	if not InputMap.has_action(ACTION):
		InputMap.add_action(ACTION)
		var k := InputEventKey.new()
		k.physical_keycode = KEY_F11
		InputMap.action_add_event(ACTION, k)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION) and not event.is_echo():
		get_viewport().set_input_as_handled()
		next()


## Index of the running level in LEVELS, or -1.
func current_index() -> int:
	var scene := get_tree().current_scene
	if scene == null:
		return -1
	for i in LEVELS.size():
		if LEVELS[i][0] == scene.scene_file_path:
			return i
	return -1


func next() -> void:
	go_to((current_index() + 1) % LEVELS.size())


func go_to(index: int) -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(LEVELS[index][0])
