class_name SurfaceShapes
extends RefCounted
## Geometry for runnable surfaces (steep ramps, quarter pipes, loops), as
## lists of box pieces: {"transform": Transform3D, "size": Vector3,
## "flow": Vector3, "face": Vector3}. The box's top face (+Y, "face") is the
## running surface; "flow" is the direction the track runs, which gently
## guides you along it. Bodies get both as metas and join the "runnable"
## group.
##
## Shapes start at `origin` (on the ground) and run toward -Z.

const THICKNESS := 0.4


## A quarter pipe: curves up from flat to `max_angle_deg`, then keeps going
## straight at that angle for `straight` meters. Top lip height is returned
## by quarter_pipe_height().
static func quarter_pipe(origin: Vector3, radius: float, max_angle_deg: float, straight: float, width: float, pieces := 14) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var a_max := deg_to_rad(max_angle_deg)
	var step := a_max / pieces
	for i in pieces:
		var a := step * (i + 0.5)
		var p := origin + Vector3(0.0, radius - radius * cos(a), -radius * sin(a))
		var n := Vector3(0.0, cos(a), sin(a))
		var t := Vector3(0.0, sin(a), -cos(a))
		out.append(_piece(p, n, t, width, radius * step * 1.12))
	if straight > 0.0:
		var p0 := origin + Vector3(0.0, radius - radius * cos(a_max), -radius * sin(a_max))
		var n := Vector3(0.0, cos(a_max), sin(a_max))
		var t := Vector3(0.0, sin(a_max), -cos(a_max))
		out.append(_piece(p0 + t * straight * 0.5, n, t, width, straight + 0.1))
	return out


static func quarter_pipe_height(radius: float, max_angle_deg: float, straight: float) -> float:
	var a := deg_to_rad(max_angle_deg)
	return radius - radius * cos(a) + straight * sin(a)


## A loop you run through upside down. It drifts sideways by `side_shift`
## (toward +X), mostly over the top, so you come out beside where you went
## in: the exit is at origin + (side_shift, 0, 0), heading -Z like the entry.
static func loop(origin: Vector3, radius: float, width: float, side_shift: float, pieces := 40) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var k := side_shift / TAU
	var step := TAU / pieces
	for i in pieces:
		var a := step * (i + 0.5)
		var p := origin + Vector3(k * (a - sin(a)), radius - radius * cos(a), -radius * sin(a))
		var n := Vector3(0.0, cos(a), sin(a))
		var d := Vector3(k * (1.0 - cos(a)), radius * sin(a), -radius * cos(a))
		out.append(_piece(p, n, d.normalized(), width, d.length() * step * 1.12))
	return out


## One box whose top face passes through `p` with normal `n`, long along `t`.
static func _piece(p: Vector3, n: Vector3, t: Vector3, width: float, length: float) -> Dictionary:
	var z := -t.normalized()
	var y := n.normalized()
	var x := y.cross(z).normalized()
	var basis := Basis(x, y, z)
	return {
		"transform": Transform3D(basis, p - y * THICKNESS * 0.5),
		"size": Vector3(width, THICKNESS, length),
		"flow": t.normalized(),
		"face": y,
	}
