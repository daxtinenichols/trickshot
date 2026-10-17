class_name MapPieces
extends RefCounted
## Extra runnable shapes for the maps, built from SurfaceShapes pieces (same
## {transform, size, flow, face} dictionaries, so SandboxBuilder._surface()
## places them and the player runs on them with the usual surface rules).


## SurfaceShapes always run toward -Z; this turns a shape by `yaw` about the
## vertical axis through `pivot`.
static func turned(pieces: Array[Dictionary], pivot: Vector3, yaw: float) -> Array[Dictionary]:
	if is_zero_approx(yaw):
		return pieces
	var r := Basis(Vector3.UP, yaw)
	var xf := Transform3D(r, pivot) * Transform3D(Basis.IDENTITY, -pivot)
	var out: Array[Dictionary] = []
	for p in pieces:
		out.append({
			"transform": xf * (p.transform as Transform3D),
			"size": p.size,
			"flow": r * (p.flow as Vector3),
			"face": r * (p.face as Vector3),
		})
	return out


## A sideways ramp (a bank): a quarter-pipe curve that rises to one side of
## the way you run, so you run along it tilted, like a wallrun on a slope.
## `start` is where its flat edge begins on the ground; it runs `length` m
## toward -Z and rises toward +X (side = 1) or -X (side = -1). Steepness and
## size are the quarter pipe's: radius, max angle, straight part.
static func bank(start: Vector3, length: float, side: float, radius := 3.0, max_angle_deg := 65.0, straight := 1.0) -> Array[Dictionary]:
	# Build the curve rising toward -Z with its width along X, centred on the
	# run's midline, then turn it so it rises sideways.
	var mid := start + Vector3(0, 0, -length * 0.5)
	var pieces := SurfaceShapes.quarter_pipe(mid, radius, max_angle_deg, straight, length)
	var out := turned(pieces, mid, -PI * 0.5 * signf(side))
	# The track runs along the bank, not up it.
	for p in out:
		p.flow = Vector3(0, 0, -1)
	return out


## A banked curve round the outside of a turn, built from short bank
## strips, so you can carve a corner at speed instead of slowing for it.
## `center` is the turn's center; the bank's flat edge runs round it at
## `inner` m, from heading `yaw0` to heading `yaw1` (yaw 0 runs toward -Z,
## +PI/2 toward -X: a left turn has yaw1 > yaw0). It rises away from the
## center. Each strip's flow follows the curve.
static func banked_turn(center: Vector3, inner: float, yaw0: float, yaw1: float, segments := 8, radius := 3.0, max_angle_deg := 60.0, straight := 1.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var left := yaw1 > yaw0
	var side := 1.0 if left else -1.0
	var d := (yaw1 - yaw0) / segments
	# Strips overlap a little at the outer edge so the curve has no gaps.
	var length := 2.0 * (inner + bank_reach(radius, max_angle_deg, straight)) * tan(absf(d) * 0.5) + 0.05
	for i in segments:
		var yaw := yaw0 + d * (i + 0.5)
		var right := Vector3(cos(yaw), 0, -sin(yaw))
		var at := center + right * side * inner
		var strip := bank(Vector3(0, 0, length * 0.5), length, side, radius, max_angle_deg, straight)
		var xf := Transform3D(Basis(Vector3.UP, yaw), at)
		for p in strip:
			out.append({
				"transform": xf * (p.transform as Transform3D),
				"size": p.size,
				"flow": xf.basis * (p.flow as Vector3),
				"face": xf.basis * (p.face as Vector3),
			})
	return out


## How far a bank reaches sideways from its start (for placing it).
static func bank_reach(radius := 3.0, max_angle_deg := 65.0, straight := 1.0) -> float:
	var a := deg_to_rad(max_angle_deg)
	return radius * sin(a) + straight * cos(a)


## A ring of tall ruined buildings closing a map's edges, so nothing can run,
## jump or wallrun off the world. `center` and `size` (x, z) are the play
## floor's footprint; the buildings stand just outside it, their inner faces
## on its edges, in blocks of `block` m with heights between `min_height`
## and `max_height` (fixed per block, so the skyline is the same every run).
## `open_far` leaves the -Z side open, for a map that something else (a
## campaign mission) carries on past. Returns {transform, size} boxes; give
## them the "FACADE" look.
static func perimeter(center: Vector3, size: Vector2, min_height := 18.0, max_height := 30.0, block := 16.0, depth := 10.0, open_far := false) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var half := size * 0.5
	# Each side runs past both corners by `depth`, so the corners are closed.
	var sides := [
		[Vector3(center.x, 0, center.z - half.y - depth * 0.5), Vector3.RIGHT, size.x + depth * 2.0],
		[Vector3(center.x, 0, center.z + half.y + depth * 0.5), Vector3.RIGHT, size.x + depth * 2.0],
		[Vector3(center.x - half.x - depth * 0.5, 0, center.z), Vector3.BACK, size.y],
		[Vector3(center.x + half.x + depth * 0.5, 0, center.z), Vector3.BACK, size.y],
	]
	var n := 0
	if open_far:
		sides.remove_at(0)
	for side: Array in sides:
		var mid: Vector3 = side[0]
		var along: Vector3 = side[1]
		var length: float = side[2]
		var count := maxi(1, ceili(length / block))
		var step := length / count
		for i in count:
			var h := lerpf(min_height, max_height, fposmod(sin(float(n) * 12.9898) * 43758.5453, 1.0))
			n += 1
			var c := mid + along * (-length * 0.5 + step * (i + 0.5)) + Vector3(0, h * 0.5, 0)
			# A hair longer than the step so neighbours overlap: no seam to
			# slip a ray (or a player) through.
			var s := Vector3(step + 0.05, h, depth) if along == Vector3.RIGHT else Vector3(depth, h, step + 0.05)
			out.append({"transform": Transform3D(Basis.IDENTITY, c), "size": s})
	return out
