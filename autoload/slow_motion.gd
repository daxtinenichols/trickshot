extends Node
## Autoload "SlowMo": click the mouse wheel (D-pad down on a controller) and
## time eases down to 40% for a few seconds, then the ability cools down
## before you can use it again. Click again to end it early. F3 is a debug
## toggle with no time limit or cooldown. A vignette darkens the screen
## edges while time is slowed.
##
## The simulation always ticks 1/60 s. Slow motion runs those ticks less
## often (fewer physics ticks per second, with time_scale stretching each one
## back to 1/60 s), so a run in slow motion plays out exactly as it would at
## full speed. The player smooths the view between ticks.

const TICKS := 60
const MIN_SPEED := 0.4

## How long a slow-mo lasts and how long it then takes to be ready again,
## in real seconds (the pause menu stops both clocks).
var duration := 3.0
var cooldown := 6.0
## Real seconds to ease into slow motion and back out of it.
var ease_in := 0.15
var ease_out := 0.3

## 1 = normal speed. Eases toward 40% and back, in whole ticks per second.
var speed := 1.0
## The speed last applied to the engine.
var applied := 1.0
var _smooth := 1.0
var _active_left := 0.0
var _cooldown_left := 0.0
var _debug := false

var vignette: ColorRect
var label: Label

const VIGNETTE_SHADER := """
shader_type canvas_item;
uniform float strength = 0.0;
void fragment() {
	vec2 p = UV - 0.5;
	p.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float edge = smoothstep(0.3, 0.9, length(p));
	COLOR = vec4(0.02, 0.03, 0.08, edge * strength);
}
"""


func _ready() -> void:
	var layer := CanvasLayer.new()
	# Over the 3D view and its speed lines, under the HUDs and corner view.
	layer.layer = 7
	add_child(layer)
	vignette = ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = VIGNETTE_SHADER
	vignette.material = mat
	layer.add_child(vignette)
	label = Label.new()
	label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.position.y = 60.0  # under the score
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.08))
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(label)
	reset()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("slow_mo") and not event.is_echo():
		trigger()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_slowmo") and not event.is_echo():
		_debug = not _debug
		_draw()
		get_viewport().set_input_as_handled()


## Starts a slow-mo if it's ready, or ends the one running (which starts the
## cooldown).
func trigger() -> void:
	if _active_left > 0.0:
		_active_left = 0.0
		_cooldown_left = cooldown
	elif _cooldown_left <= 0.0:
		_active_left = duration
	_draw()


func is_active() -> bool:
	return _active_left > 0.0 or _debug


## 0 = ready, 1 = just used.
func cooldown_left() -> float:
	return _cooldown_left / maxf(cooldown, 0.01)


## Back to normal speed straight away, ready to use.
func reset() -> void:
	_active_left = 0.0
	_cooldown_left = 0.0
	_debug = false
	set_speed(1.0)


## Sets the speed of time right now (no easing), clamped to 40%..100% in
## whole ticks per second.
func set_speed(s: float) -> void:
	_smooth = clampf(s, MIN_SPEED, 1.0)
	_apply(_snap(_smooth))


static func _snap(s: float) -> float:
	return clampi(roundi(s * TICKS), roundi(MIN_SPEED * TICKS), TICKS) / float(TICKS)


func _apply(s: float) -> void:
	speed = s
	applied = s
	Engine.physics_ticks_per_second = roundi(s * TICKS)
	Engine.time_scale = s
	_draw()


## Vignette (follows the eased speed) and the readout.
func _draw() -> void:
	var slowed := (1.0 - _smooth) / (1.0 - MIN_SPEED)
	vignette.visible = slowed > 0.0
	(vignette.material as ShaderMaterial).set_shader_parameter("strength", 0.6 * slowed)
	if is_active():
		label.visible = true
		label.text = "SLOW-MO"
		label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	elif _cooldown_left > 0.0:
		label.visible = true
		label.text = "slow-mo in %d" % ceili(_cooldown_left)
		label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0, 0.45))
	else:
		label.visible = false


func _process(delta: float) -> void:
	# Something else put time back (changing level resets time_scale to 1):
	# follow it so the tick rate matches.
	if not is_equal_approx(Engine.time_scale, applied):
		reset()
		return
	var real := delta / maxf(Engine.time_scale, 0.01)
	if _active_left > 0.0:
		_active_left -= real
		if _active_left <= 0.0:
			_active_left = 0.0
			_cooldown_left = cooldown
	elif _cooldown_left > 0.0:
		_cooldown_left = maxf(_cooldown_left - real, 0.0)
	# Ease toward where time is headed, one whole tick rate at a time.
	var want := MIN_SPEED if is_active() else 1.0
	var rate := (1.0 - MIN_SPEED) / maxf(ease_in if want < _smooth else ease_out, 0.001)
	_smooth = move_toward(_smooth, want, rate * real)
	var s := _snap(_smooth)
	if s != speed:
		_apply(s)
	else:
		_draw()
