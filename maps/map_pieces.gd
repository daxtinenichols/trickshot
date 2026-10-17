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


## How far a bank reaches sideways from its start (for placing it).
static func bank_reach(radius := 3.0, max_angle_deg := 65.0, straight := 1.0) -> float:
	var a := deg_to_rad(max_angle_deg)
	return radius * sin(a) + straight * cos(a)
