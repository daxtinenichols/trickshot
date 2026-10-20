extends "res://levels/sandbox.gd"
## A campaign mission: the sandbox's player, HUD and menu on the layout of
## the mission being played (Campaign.current), plus the mission's rules
## (MissionRun), the radio and the mission HUD.
##
## Losing restarts the level: a short fade with what happened ("DOWN",
## "FELL", "CAUGHT"), then a fresh copy of this scene replaces this one.
## Reloading leaves nothing behind (kicked doors, broken glass, enemies,
## set pieces, the radio's once-only lines, score, combo, Flow, health),
## which resetting each system in place could miss.
##
## The first time you play a level it holds you at the start (free look,
## no moving) while its opening lines are said, then lets you go. After a
## restart, or on a level finished before, the opening is skipped.

signal restarted(fresh: Node)

const HURT_OVERLAY_SCRIPT := preload("res://enemies/hurt_overlay.gd")
## The longest the results card waits for the radio to finish (seconds).
const STORY_WAIT_MAX := 90.0
## Physics ticks the loss fade lasts before the restart (about 1 s), and
## the quicker one for Backspace / the menu's Restart.
const LOSS_TICKS := 60
const RESTART_TICKS := 15
const LOSS_TEXT := {"fall": "FELL", "caught": "CAUGHT", "down": "DOWN"}

var run: MissionRun
var radio: RadioFeed
var mission_hud: MissionHud
## The results waiting for the radio: {result, next, waited}.
var _results := {}
## Set before adding to the tree: the spawn the run starts from (0, or a
## dev practice start), so a lost practice run restarts where it began.
var start_zone := 0
## Attempts before this one (shown on the results).
var restarts := 0

var _fade_layer: CanvasLayer
var _fade: ColorRect
var _fade_label: Label
var _fade_ticks := 0
var _fade_total := 0
var _restarting := false
## The empty input holding you still while the opening plays (null when
## free).
var _hold: InputFrame
var _hold_layer: CanvasLayer
var _hold_label: Label


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
	run.restarts = restarts
	run.lost.connect(_on_lost)
	var health := player.get_node_or_null("PlayerHealth")
	if health != null:
		# Enemies are here: show damage like the sandbox arena does.
		var overlay: CanvasLayer = HURT_OVERLAY_SCRIPT.new()
		add_child(overlay)
		overlay.setup(health)
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
	_build_fade()
	radio.skip_opening = restarts > 0 or start_zone > 0 or index >= 0 and Campaign.is_complete(index)
	run.begin()
	if radio.opening_playing():
		_hold_still()
	if start_zone > 0:
		go_to_zone(start_zone)
	if restarts == 0:
		hud.show_toast(b.mission.get("title", ""), 3.0)
	menu.add_action("Restart level", restart)


func _on_completed(result: Dictionary) -> void:
	var index := run.mission_index
	var has_next := index >= 0 and index + 1 < Campaign.mission_count() and Campaign.is_unlocked(index + 1)
	# The ending is seen, not read over a menu: you keep control while the
	# level's last story lines play, then the results card comes up.
	_results = {"result": result, "next": has_next, "waited": 0.0}


func _process(delta: float) -> void:
	if _hold != null:
		_hold_label.text = "ON AIR  %d" % ceili(radio.opening_left())
	if radio != null and run != null:
		# Set pieces timed to the radio (a bridge blows after its line).
		var on_air: String = radio.current.get("line", "")
		for sp: Node3D in run.builder.set_pieces:
			if sp.has_method("hear"):
				sp.hear(on_air)
	if _results.is_empty():
		return
	_results.waited += delta
	if _results.waited < STORY_WAIT_MAX and (radio != null and radio.busy() or _set_piece_busy()):
		return
	var r := _results
	_results = {}
	# Then hand the mouse to the results card.
	player.use_device_input = false
	player.scripted_input = InputFrame.new()
	if DisplayServer.get_name() != "headless":
		player.capture_mouse(false)
	mission_hud.show_results(r.result, run.mission.get("title", "Mission complete"), r.next)


func _set_piece_busy() -> bool:
	for sp: Node3D in run.builder.set_pieces:
		if sp.has_method("busy") and sp.busy():
			return true
	return false


func _next() -> void:
	Campaign.play(get_tree(), run.mission_index + 1)


func _retry() -> void:
	if run.mission_index >= 0:
		Campaign.play(get_tree(), run.mission_index)
	else:
		get_tree().reload_current_scene()


# ---------------------------------------------------------------- restart

func _on_lost(reason: String) -> void:
	# Hands off the controls while it fades, like the results card does.
	player.use_device_input = false
	player.scripted_input = InputFrame.new()
	Engine.time_scale = 1.0
	_fade_total = RESTART_TICKS if reason == "restart" else LOSS_TICKS
	_fade_ticks = 0
	_fade_label.text = LOSS_TEXT.get(reason, "")
	_fade_layer.visible = true


# ---------------------------------------------------------------- opening

func _hold_still() -> void:
	_hold = InputFrame.new()
	player.scripted_input = _hold
	_hold_layer = CanvasLayer.new()
	_hold_layer.layer = 7
	add_child(_hold_layer)
	_hold_label = Label.new()
	_hold_label.add_theme_font_size_override("font_size", 30)
	_hold_label.add_theme_color_override("font_color", Color(1.0, 0.36, 0.3))
	_hold_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_hold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hold_label.position = Vector2(-120, 90)
	_hold_label.custom_minimum_size = Vector2(240, 0)
	_hold_layer.add_child(_hold_label)


## The opening has been said: you're free to go.
func _release() -> void:
	# Tests (and the results card) may have taken the input over since.
	if player.scripted_input == _hold:
		player.scripted_input = null
	_hold = null
	_hold_layer.queue_free()
	hud.show_toast("GO", 1.0)


## True while the opening holds you at the start.
func holding() -> bool:
	return _hold != null


func _physics_process(_delta: float) -> void:
	if _hold != null and not radio.opening_playing():
		_release()
	if _fade_total <= 0 or _restarting:
		return
	_fade_ticks += 1
	var t := float(_fade_ticks) / _fade_total
	_fade.color.a = clampf(t * 1.4, 0.0, 1.0)
	_fade_label.modulate.a = clampf(t * 3.0, 0.0, 1.0)
	if _fade_ticks >= _fade_total:
		restart()


## Starts this mission again from its start (or the practice start): a
## fresh copy of the scene takes this one's place in the tree.
func restart() -> void:
	if _restarting:
		return
	_restarting = true
	var fresh: Node = load(scene_file_path).instantiate()
	(fresh.get_node("Builder") as MissionBuilder).mission_path = (builder as MissionBuilder).mission_path
	fresh.start_zone = run.start_index
	fresh.restarts = restarts + 1
	_swap.call_deferred(fresh)


func _swap(fresh: Node) -> void:
	var tree := get_tree()
	tree.paused = false
	Engine.time_scale = 1.0
	var parent := get_parent()
	var was_current := tree.current_scene == self
	# Out first, so the two levels never share the world for a frame.
	parent.remove_child(self)
	parent.add_child(fresh)
	if was_current:
		tree.current_scene = fresh
	restarted.emit(fresh)
	queue_free()


func _build_fade() -> void:
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 15
	_fade_layer.visible = false
	add_child(_fade_layer)
	_fade = ColorRect.new()
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color(0.03, 0.02, 0.02, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_layer.add_child(_fade)
	_fade_label = Label.new()
	_fade_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fade_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_fade_label.add_theme_font_size_override("font_size", 72)
	_fade_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.2))
	_fade_label.modulate.a = 0.0
	_fade_layer.add_child(_fade_label)
