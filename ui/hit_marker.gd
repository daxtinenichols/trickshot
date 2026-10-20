class_name HitMarker
extends Control
## Crosshair hit confirmation: a white X for body hits, a bigger, thicker
## yellow X for headshots, and a red X with an expanding ring on a kill. Each
## one pops in large and snaps down, and fades fast so rapid hits stay
## readable.

var _alpha := 0.0
var _pop := 0.0
var _fade := 4.0
var _ring := -1.0
var _color := Color.WHITE
var _size := 10.0
var _width := 2.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_CENTER)


func show_hit(headshot: bool, kill: bool) -> void:
	_alpha = 1.0
	_pop = 1.0
	_size = 16.0 if headshot or kill else 10.0
	_width = 3.0 if headshot or kill else 2.0
	_fade = 2.2 if kill else (3.0 if headshot else 4.5)
	if kill:
		_color = Color(1.0, 0.3, 0.25)
		_ring = 0.0
	elif headshot:
		_color = Color(1.0, 0.85, 0.2)
	else:
		_color = Color.WHITE
	queue_redraw()


## How big the marker is drawn right now (1 = its resting size).
func pop_scale() -> float:
	return 1.0 + 0.7 * _pop


func is_showing() -> bool:
	return _alpha > 0.0


func _process(frame_delta: float) -> void:
	# Real time, so slow motion doesn't stretch the HUD.
	var delta := frame_delta / maxf(Engine.time_scale, 0.01)
	if _alpha <= 0.0 and _ring < 0.0:
		return
	_alpha = maxf(_alpha - delta * _fade, 0.0)
	_pop *= exp(-delta * 22.0)
	if _ring >= 0.0:
		_ring += delta * 3.0
		if _ring >= 1.0:
			_ring = -1.0
	queue_redraw()


func _draw() -> void:
	if _alpha > 0.0:
		var c := _color
		c.a = _alpha
		var inner := 5.0 * pop_scale()
		var outer := inner + _size * pop_scale()
		for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var dir := d.normalized()
			draw_line(dir * inner, dir * outer, Color(0, 0, 0, c.a * 0.6), _width + 2.0, true)
			draw_line(dir * inner, dir * outer, c, _width, true)
	if _ring >= 0.0:
		var rc := Color(1.0, 0.3, 0.25, (1.0 - _ring) * 0.8)
		draw_arc(Vector2.ZERO, 14.0 + _ring * 30.0, 0.0, TAU, 40, rc, 2.5, true)
