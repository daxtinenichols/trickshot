class_name HurtOverlay
extends CanvasLayer
## Shows the player's health while it matters: a red edge flash when you
## get hit, a marker pointing at whoever hit you, and a health bar that
## appears while you're hurt. Also a faint pulsing red edge while an enemy
## is aiming at you and you're easy to hit (slow, no tricks: combo armor
## is low). Reads PlayerHealth, the player and enemies' aim; visual only.

const ComboArmor := preload("res://enemies/combo_armor.gd")
## Exposure where the warning starts, and where it's at full strength.
const EXPOSED_FROM := 0.75
const EXPOSED_FULL := 1.3

const MARKER_TIME := 1.4
const VIGNETTE_SHADER := """
shader_type canvas_item;
uniform float strength = 0.0;
void fragment() {
	vec2 p = UV - 0.5;
	float edge = smoothstep(0.4, 0.85, length(p * vec2(1.0, 0.8)) * 1.35);
	COLOR = vec4(0.75, 0.04, 0.02, edge * strength);
}
"""

var health: PlayerHealth
var _vignette: ColorRect
var _draw_layer: Control
var _flash := 0.0
var _markers: Array[Dictionary] = []  # {from, time}
var _bar_alpha := 0.0
var _exposed := 0.0
var _pulse := 0.0


func setup(h: PlayerHealth) -> void:
	health = h
	h.damaged.connect(_on_damaged)
	h.died.connect(_on_died)


func _exit_tree() -> void:
	if health and is_instance_valid(health):
		if health.damaged.is_connected(_on_damaged):
			health.damaged.disconnect(_on_damaged)
		if health.died.is_connected(_on_died):
			health.died.disconnect(_on_died)


func _ready() -> void:
	layer = 5
	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	var s := Shader.new()
	s.code = VIGNETTE_SHADER
	m.shader = s
	_vignette.material = m
	add_child(_vignette)
	_draw_layer = Control.new()
	_draw_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw_layer.draw.connect(_draw_markers)
	add_child(_draw_layer)


func _on_damaged(amount: float, from: Vector3, _kind: StringName) -> void:
	_flash = minf(_flash + 0.35 + amount / 60.0, 1.0)
	_markers.append({"from": from, "time": MARKER_TIME})
	if _markers.size() > 6:
		_markers.pop_front()


func _on_died() -> void:
	_flash = 1.0
	_markers.clear()


func _process(delta: float) -> void:
	if health == null:
		return
	_flash = move_toward(_flash, 0.0, delta * 2.0)
	var low := 1.0 - health.fraction()
	_exposed = move_toward(_exposed, exposed_warning(), delta * 3.0)
	_pulse = fmod(_pulse + delta * 2.2, TAU)
	var strength := maxf(maxf(_flash * 0.6, low * low * 0.45), _exposed * (0.22 + 0.08 * sin(_pulse)))
	(_vignette.material as ShaderMaterial).set_shader_parameter("strength", strength)
	_vignette.visible = strength > 0.01
	for i in range(_markers.size() - 1, -1, -1):
		_markers[i].time -= delta
		if _markers[i].time <= 0.0:
			_markers.remove_at(i)
	var want := 1.0 if health.fraction() < 0.999 else 0.0
	_bar_alpha = move_toward(_bar_alpha, want, delta * 3.0)
	_draw_layer.queue_redraw()


## 0..1: how strongly to warn that you're exposed. Only while an enemy
## that can see you is aiming at you.
func exposed_warning() -> float:
	var p: Node = health.player if health else null
	if p == null or not p.is_inside_tree():
		return 0.0
	var aimed := false
	for e: Node in p.get_tree().get_nodes_in_group("enemies"):
		if e.has_method("is_aiming") and e.is_aiming() and not e.is_dead and e.player == p:
			aimed = true
			break
	if not aimed:
		return 0.0
	return clampf((ComboArmor.exposure(p) - EXPOSED_FROM) / (EXPOSED_FULL - EXPOSED_FROM), 0.0, 1.0)


func _draw_markers() -> void:
	var size := _draw_layer.size
	var center := size * 0.5
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	if cam:
		for m in _markers:
			var local: Vector3 = cam.global_transform.affine_inverse() * (m.from as Vector3)
			var a := atan2(local.x, -local.z)  # 0 = straight ahead (top)
			var dir := Vector2(sin(a), -cos(a))
			var side := Vector2(-dir.y, dir.x)
			var r := minf(size.x, size.y) * 0.2
			var alpha: float = clampf(m.time / MARKER_TIME, 0.0, 1.0)
			var tip := center + dir * (r + 34.0)
			var pts := PackedVector2Array([tip, center + dir * r + side * 30.0, center + dir * (r + 10.0), center + dir * r - side * 30.0])
			_draw_layer.draw_colored_polygon(pts, Color(1.0, 0.15, 0.08, 0.85 * alpha))
	if _bar_alpha > 0.01:
		var w := 260.0
		var pos := Vector2(28.0, size.y - 86.0)
		_draw_layer.draw_rect(Rect2(pos - Vector2(3, 3), Vector2(w + 6, 18)), Color(0.04, 0.04, 0.06, 0.6 * _bar_alpha))
		var frac := health.fraction()
		var col := Color(1.0, 0.3, 0.2) if frac < 0.35 else Color(0.95, 0.92, 0.85)
		col.a = _bar_alpha
		_draw_layer.draw_rect(Rect2(pos, Vector2(w * frac, 12)), col)
