extends CanvasLayer
## First-person speed lines: faint streaks at the screen edges that build
## up above run speed, colored like the motion trails.

const SHADER := preload("res://art/shaders/speed_lines.gdshader")
const MotionTrails := preload("res://art/fx/motion_trails.gd")

var player: Player
var _rect := ColorRect.new()
var _mat := ShaderMaterial.new()
var _level := 0.0


func setup(p: Player) -> void:
	player = p


func _ready() -> void:
	layer = -1
	_mat.shader = SHADER
	_rect.material = _mat
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)


func _process(delta: float) -> void:
	if player == null:
		return
	var speed := player.velocity.length()
	var run := player.tuning.run_speed
	var top := player.tuning.top_speed
	var target := clampf((speed - run) / maxf(top + 3.0 - run, 0.1), 0.0, 1.0)
	_level = lerpf(_level, target, 1.0 - exp(-5.0 * delta))
	var vp := get_viewport().get_visible_rect().size
	_mat.set_shader_parameter("intensity", _level)
	_mat.set_shader_parameter("aspect", vp.x / maxf(vp.y, 1.0))
	_mat.set_shader_parameter("tint", MotionTrails.speed_color(speed, run, top))
	visible = _level > 0.01 and player.camera.current
