extends Node
## Autoload "SlowMo": scroll the wheel down (D-pad down on a controller) to
## slow time, down to 10%; up to speed it back up, never past normal speed.
## F3 toggles 30%. A vignette
## darkens the screen edges while time is slowed.
##
## The simulation always ticks 1/60 s. Slow motion runs those ticks less
## often (fewer physics ticks per second, with time_scale stretching each one
## back to 1/60 s), so a run in slow motion plays out exactly as it would at
## full speed. The player smooths the view between ticks.

const TICKS := 60
const STEP := 0.1
const MIN_SPEED := 0.1
const DEBUG_SPEED := 0.3

## 1 = normal speed.
var speed := 1.0
## The speed last applied to the engine.
var applied := 1.0

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
	label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.08))
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(label)
	set_speed(1.0)


func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed:
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			set_speed(speed - STEP)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			set_speed(speed + STEP)
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("slow_down"):
		set_speed(speed - STEP)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("speed_up"):
		set_speed(speed + STEP)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_slowmo") and not event.is_echo():
		set_speed(DEBUG_SPEED if speed >= 1.0 else 1.0)
		get_viewport().set_input_as_handled()


## Sets the speed of time, clamped to 10%..100% in 1/60 steps (whole ticks
## per second).
func set_speed(s: float) -> void:
	speed = _snap(s)
	_apply()


static func _snap(s: float) -> float:
	return clampi(roundi(s * TICKS), roundi(MIN_SPEED * TICKS), TICKS) / float(TICKS)


func _apply() -> void:
	applied = speed
	Engine.physics_ticks_per_second = roundi(speed * TICKS)
	Engine.time_scale = speed
	var slowed := 1.0 - speed
	vignette.visible = slowed > 0.0
	(vignette.material as ShaderMaterial).set_shader_parameter("strength", 0.35 + 0.55 * slowed / (1.0 - MIN_SPEED))
	label.visible = slowed > 0.0
	label.text = "SLOW-MO %d%%" % roundi(speed * 100.0)


func _process(_delta: float) -> void:
	# Something else put time back (changing level resets time_scale to 1):
	# follow it so the tick rate matches.
	if not is_equal_approx(Engine.time_scale, applied):
		set_speed(Engine.time_scale)
