class_name SpeedGraph
extends Control
## Scrolling graph of horizontal speed over the last few seconds, with guide
## lines at run speed and top speed.

const SECONDS := 5.0
const MAX_SPEED := 20.0

var player: Player
var _samples: PackedFloat32Array = []
var _states: PackedInt32Array = []


func _ready() -> void:
	custom_minimum_size = Vector2(320, 90)


func _physics_process(_delta: float) -> void:
	if player == null:
		return
	_samples.append(player.horizontal_speed())
	_states.append(player.state)
	var keep := int(SECONDS * Engine.physics_ticks_per_second)
	if _samples.size() > keep:
		_samples = _samples.slice(_samples.size() - keep)
		_states = _states.slice(_states.size() - keep)
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0, 0, 0, 0.45))
	if player == null:
		return
	var keep := SECONDS * Engine.physics_ticks_per_second
	_hline(player.tuning.run_speed, Color(1, 1, 1, 0.25), "run")
	_hline(player.tuning.top_speed, Color(1, 0.8, 0.3, 0.35), "top")
	if _samples.size() < 2:
		return
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for i in _samples.size():
		var x := size.x * (1.0 - float(_samples.size() - 1 - i) / keep)
		var y := size.y * (1.0 - clampf(_samples[i] / MAX_SPEED, 0.0, 1.0))
		pts.append(Vector2(x, y))
		cols.append(DebugHud.state_color(_states[i]))
	draw_polyline_colors(pts, cols, 2.0)


func _hline(speed: float, color: Color, text: String) -> void:
	var y := size.y * (1.0 - speed / MAX_SPEED)
	draw_line(Vector2(0, y), Vector2(size.x, y), color, 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(4, y - 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)
