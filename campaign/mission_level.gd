extends "res://levels/sandbox.gd"
## A campaign mission: the sandbox's player, HUD and menu on the layout of
## the mission being played (Campaign.current), plus the mission's rules
## (MissionRun), the radio and the mission HUD.

var run: MissionRun
var radio: RadioFeed
var mission_hud: MissionHud


func _ready() -> void:
	super()
	var b := builder as MissionBuilder
	var index := Campaign.index_of_file(b.resolved_path())
	# Which runner: art can swap the model by this meta ("parker"/"echo").
	player.set_meta("runner", Campaign.runner_for(index) if index >= 0 else "parker")
	run = MissionRun.new()
	run.name = "MissionRun"
	add_child(run)
	run.setup(player, b, combo, index)
	radio = RadioFeed.new()
	add_child(radio)
	radio.setup(run, player)
	mission_hud = MissionHud.new()
	add_child(mission_hud)
	mission_hud.setup(run)
	mission_hud.next_pressed.connect(_next)
	mission_hud.retry_pressed.connect(_retry)
	mission_hud.menu_pressed.connect(func() -> void: Campaign.open_menu(get_tree()))
	run.completed.connect(_on_completed)
	run.begin()
	hud.show_toast(b.mission.get("title", ""), 3.0)


func _on_completed(result: Dictionary) -> void:
	var index := run.mission_index
	var has_next := index >= 0 and index + 1 < Campaign.mission_count() and Campaign.is_unlocked(index + 1)
	# Let the last radio line land, then hand the mouse to the results card.
	player.use_device_input = false
	player.scripted_input = InputFrame.new()
	if DisplayServer.get_name() != "headless":
		player.capture_mouse(false)
	mission_hud.show_results(result, run.mission.get("title", "Mission complete"), has_next)


func _next() -> void:
	Campaign.play(get_tree(), run.mission_index + 1)


func _retry() -> void:
	if run.mission_index >= 0:
		Campaign.play(get_tree(), run.mission_index)
	else:
		get_tree().reload_current_scene()
