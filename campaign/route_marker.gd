extends Control
## The way on: a small orange courier mark on screen over the next point of
## the mission's "guide" line, with how far it is. Off screen (or behind
## you) it sits on the edge of the screen pointing the way to turn.
##
## The guide is a list of [x, y, z] points along the main line, one at each
## turn, door, ramp and bridge, ending at the mission's goal. The mark
## heads for the first point not yet passed: you pass a point by getting
## near it or by running on along the line after it, so a shortcut or the
## high line moves it on too. Presentation only: nothing here changes the
## simulation. Loaded by path from MissionHud (no class_name).

const ORANGE := Color(0.96, 0.45, 0.12)
## Within this of a point (meters, height counted triple) it's passed.
const REACH := 4.0
## How many points ahead the runner can be found on the line.
const WINDOW := 4
## A jump this far in one frame is a respawn: find the runner again on the
## whole line.
const TELEPORT := 8.0
## The mark floats this high over the point (about chest height).
const LIFT := 1.4
## Edge of the screen the off-screen mark keeps from (pixels).
const MARGIN := 46.0

var points: Array[Vector3] = []
## Index of the point the mark is on (points.size() once all are passed).
var target := 0
var player: Node3D
## Hidden when false (the Settings switch, or no guide).
var enabled := true

var _last_pos := Vector3.INF


func setup(guide: Array, p: Node3D) -> void:
	points.clear()
	for g: Array in guide:
		points.append(Vector3(g[0], g[1], g[2]))
	player = p
	target = 0
	_last_pos = Vector3.INF


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if player == null or points.is_empty():
		visible = false
		return
	var pos := player.global_position
	if _last_pos == Vector3.INF:
		target = advance(points, 0, pos)
	elif pos.distance_to(_last_pos) > TELEPORT:
		target = find(points, pos)
	else:
		target = advance(points, target, pos)
	_last_pos = pos
	queue_redraw()


## Distance from `p` to the segment a-b, with height counted three times
## over so stacked floors (the car park's laps) stay apart.
static func _segment_distance(a: Vector3, b: Vector3, p: Vector3) -> float:
	var s := Vector3(1.0, 3.0, 1.0)
	a *= s
	b *= s
	p *= s
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func _point_distance(a: Vector3, p: Vector3) -> float:
	return _segment_distance(a, a, p)


## The point to head for from `pos`, having been heading for `from`: moves
## on past points you reach, and to the end of any later stretch of the
## line you're running on (a few points ahead at most).
static func advance(pts: Array[Vector3], from: int, pos: Vector3) -> int:
	var t := from
	if t >= pts.size():
		return t
	# On a later stretch than the one ending at t: the stretch k -> k+1.
	var here := _segment_distance(pts[t - 1], pts[t], pos) if t > 0 else _point_distance(pts[0], pos)
	var best := -1
	var best_d := minf(here, 6.0)
	for k in range(t, mini(t + WINDOW, pts.size() - 1)):
		var d := _segment_distance(pts[k], pts[k + 1], pos)
		if d < best_d:
			best_d = d
			best = k
	if best >= 0:
		t = best + 1
	while t < pts.size() and _point_distance(pts[t], pos) < REACH:
		t += 1
	return t


## The point to head for from `pos` anywhere on the line (after a respawn).
static func find(pts: Array[Vector3], pos: Vector3) -> int:
	if pts.size() < 2:
		return 0 if pts.is_empty() or _point_distance(pts[0], pos) >= REACH else 1
	var best := 0
	var best_d := INF
	for k in pts.size() - 1:
		var d := _segment_distance(pts[k], pts[k + 1], pos)
		if d < best_d:
			best_d = d
			best = k
	return advance(pts, best + 1, pos)


func _draw() -> void:
	if not enabled or target >= points.size() or player == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var world := points[target] + Vector3(0, LIFT, 0)
	var size := get_viewport_rect().size
	var center := size * 0.5
	var dist := player.global_position.distance_to(points[target])
	var on_screen := not cam.is_position_behind(world)
	var at := cam.unproject_position(world) if on_screen else Vector2.ZERO
	var rect := Rect2(Vector2(MARGIN, MARGIN), size - Vector2(MARGIN, MARGIN) * 2.0)
	if on_screen and rect.has_point(at):
		_mark(at, dist)
		return
	# Off screen: on the edge, pointing the way to turn.
	var local := cam.global_transform.affine_inverse() * world
	var dir := Vector2(local.x, -local.y)
	if local.z > 0.0 and absf(dir.x) < 0.001:
		dir.x = 1.0
	if dir.length() < 0.001:
		dir = Vector2(0, 1)
	dir = dir.normalized()
	var half := rect.size * 0.5
	var k := minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
	var edge := center + dir * k
	_arrow(edge, dir, dist)


## The mark: an orange diamond, its distance under it.
func _mark(at: Vector2, dist: float) -> void:
	var r := 13.0
	var a := clampf((dist - 2.0) / 4.0, 0.25, 1.0)
	var pts := PackedVector2Array([at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0)])
	draw_colored_polygon(pts, Color(ORANGE, 0.9 * a))
	pts.append(pts[0])
	draw_polyline(pts, Color(0, 0, 0, 0.8 * a), 2.0, true)
	_distance(at + Vector2(0, r + 18.0), dist, a)


## An arrow on the edge of the screen pointing along `dir`.
func _arrow(at: Vector2, dir: Vector2, dist: float) -> void:
	var side := Vector2(-dir.y, dir.x)
	var tip := at + dir * 14.0
	var pts := PackedVector2Array([tip, at - dir * 8.0 + side * 12.0, at - dir * 2.0, at - dir * 8.0 - side * 12.0])
	draw_colored_polygon(pts, Color(ORANGE, 0.95))
	pts.append(pts[0])
	draw_polyline(pts, Color(0, 0, 0, 0.8), 2.0, true)
	_distance(at - dir * 30.0 + Vector2(0, 6), dist, 1.0)


func _distance(at: Vector2, dist: float, alpha: float) -> void:
	var font := get_theme_default_font()
	var text := "%d m" % roundi(dist)
	var fs := 16
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := at - Vector2(w * 0.5, 0)
	draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.85 * alpha))
	draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.9, 0.75, alpha))
