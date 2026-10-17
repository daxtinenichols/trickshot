class_name HitMarker
extends Control
## Crosshair hit confirmation: a white X for body hits, a bigger yellow X for
## headshots, red on a kill. Fades fast so rapid hits stay readable.

var _alpha := 0.0
var _color := Color.WHITE
var _size := 10.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_CENTER)


func show_hit(headshot: bool, kill: bool) -> void:
	_alpha = 1.0
	_size = 15.0 if headshot or kill else 10.0
	if kill:
		_color = Color(1.0, 0.3, 0.25)
	elif headshot:
		_color = Color(1.0, 0.85, 0.2)
	else:
		_color = Color.WHITE
	queue_redraw()


func _process(delta: float) -> void:
	if _alpha <= 0.0:
		return
	_alpha = maxf(_alpha - delta * 4.0, 0.0)
	queue_redraw()


func _draw() -> void:
	if _alpha <= 0.0:
		return
	var c := _color
	c.a = _alpha
	var inner := 5.0
	for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var dir := d.normalized()
		draw_line(dir * inner, dir * (inner + _size), Color(0, 0, 0, c.a * 0.6), 4.0, true)
		draw_line(dir * inner, dir * (inner + _size), c, 2.0, true)
