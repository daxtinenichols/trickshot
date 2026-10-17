class_name CourseTimer
extends CanvasLayer
## Times a run of the rooftop course: the clock starts when you cross the
## start line, checkpoints move your respawn forward, falling to the street
## puts you back at the last checkpoint (the clock keeps going), and crossing
## the finish line stops it and keeps your best time.
##
## Counts physics ticks, so a time is exact and the same on every machine.
## Only reads the player, apart from respawning it after a fall.

enum Phase { READY, RUNNING, FINISHED }

const BEST_PATH := "user://rooftops.cfg"

## Set false in tests so they never touch the saved best time.
static var persist := true
var phase := Phase.READY
var ticks := 0
## Index into the builder's spawns: 0 is the start, then each checkpoint.
var checkpoint := 0
## Started from a checkpoint (number keys), so it can't set a best time.
var practice := false
var best_ticks := 0
var falls := 0

var player: Player
var builder: RooftopCourseBuilder
var hud: DebugHud

var _label: Label
var _respawning := false


func setup(p: Player, b: RooftopCourseBuilder, h: DebugHud = null) -> void:
	player = p
	builder = b
	hud = h
	process_physics_priority = 10  # after the player's tick
	player.respawned.connect(_on_respawned)
	_load_best()
	_build_label()
	reset(0)


## Back to READY from spawn `index` (0 = start line).
func reset(index: int) -> void:
	phase = Phase.READY
	ticks = 0
	falls = 0
	checkpoint = index
	practice = index != 0
	_refresh()


func seconds() -> float:
	return ticks / float(Engine.physics_ticks_per_second)


static func format_time(t: float) -> String:
	return "%d:%05.2f" % [floori(t / 60.0), fmod(t, 60.0)]


func _physics_process(_delta: float) -> void:
	if player == null:
		return
	var pos := player.global_position
	if phase == Phase.RUNNING:
		ticks += 1
	if pos.y < RooftopCourseBuilder.FAIL_Y and phase != Phase.FINISHED:
		_fall()
		return
	if phase == Phase.READY and pos.z < RooftopCourseBuilder.START_Z and checkpoint == 0:
		phase = Phase.RUNNING
		_toast("GO!")
	if phase == Phase.RUNNING or practice:
		# Gates in order: the course turns, so each is a line across the
		# roof on its own heading, not a z.
		var cps: Array = RooftopCourseBuilder.CHECKPOINTS
		while checkpoint < cps.size() and RooftopCourseBuilder.past_gate(cps[checkpoint], pos):
			checkpoint += 1
			player.set_spawn(builder.checkpoint_spawn(checkpoint))
			if phase == Phase.RUNNING:
				_toast("Checkpoint: %s  %s" % [cps[checkpoint - 1][2], format_time(seconds())])
	if phase == Phase.RUNNING and checkpoint == RooftopCourseBuilder.CHECKPOINTS.size() \
			and RooftopCourseBuilder.past_gate(RooftopCourseBuilder.FINISH, pos):
		_finish()
	_refresh()


func _fall() -> void:
	falls += 1
	_respawning = true
	player.respawn(builder.checkpoint_spawn(checkpoint))
	_respawning = false
	_toast("Back to the checkpoint")


func _finish() -> void:
	phase = Phase.FINISHED
	var t := format_time(seconds())
	if practice:
		_toast("Finished %s (practice: start at 1 for a best time)" % t, 4.0)
	elif best_ticks == 0 or ticks < best_ticks:
		best_ticks = ticks
		_save_best()
		_toast("NEW BEST  %s" % t, 4.0)
	else:
		_toast("Finished  %s   best %s" % [t, format_time(best_ticks / float(Engine.physics_ticks_per_second))], 4.0)


func _on_respawned() -> void:
	if _respawning:
		return
	# A zone key or a reset: start over from whichever spawn it was.
	var index := 0
	var best := INF
	for i in builder.spawns.size():
		var d := builder.spawns[i].origin.distance_to(player.global_position)
		if d < best:
			best = d
			index = i
	reset(index)


func _toast(text: String, duration := 2.0) -> void:
	if hud != null:
		hud.show_toast(text, duration)


func _build_label() -> void:
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 40)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_label.add_theme_constant_override("outline_size", 10)
	_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_label.position = Vector2(-300, 24)
	_label.custom_minimum_size = Vector2(600, 0)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_label)


func _refresh() -> void:
	if _label == null:
		return
	var text := format_time(seconds())
	if practice:
		text += "   practice"
	elif best_ticks > 0:
		text += "   best " + format_time(best_ticks / float(Engine.physics_ticks_per_second))
	_label.text = text
	_label.modulate = Color(1, 0.9, 0.3) if phase == Phase.FINISHED else (Color(1, 1, 1) if phase == Phase.RUNNING else Color(0.75, 0.8, 0.9))


func _load_best() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	if cfg.load(BEST_PATH) == OK:
		best_ticks = int(cfg.get_value("rooftops", "best_ticks", 0))


func _save_best() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	cfg.load(BEST_PATH)
	cfg.set_value("rooftops", "best_ticks", best_ticks)
	cfg.save(BEST_PATH)
