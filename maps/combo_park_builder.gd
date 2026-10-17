@tool
class_name ComboParkBuilder
extends SandboxBuilder
## "Combo Park": one open yard where every feature is a few steps from the
## next, so you can keep a combo going for as long as you like. No set route.
##
##           north: wallrun zigzag over a red pit
##   west:   ┌──────────────────────┐   east:
##   half-   │      ramp ▲          │   loop
##   pipe    │  ◄ ramp TOWER ramp ► │   runway
##           │   pillars, targets   │
##           │ breach wall  hurdles │
##           └──────────────────────┘
##                    south: spawn
##
## Long blue walls run along the west and east edges, so there is always a
## wall to ride back toward the middle. Sizes come from the movement numbers:
## 1.5 m steps mantle, 3 m faces climb, 1 m blocks vault, 1.1 m bars slide.

const HALF := 66.0  # the first yard is 132 x 132 m
## The long park north of the yard: canal, wall alley, rollers, a curved
## overpass, out at EXIT. The high road runs above the east side.
const FAR_Z := -570.0
const FLOOR_CENTER := Vector3(0, 0, (HALF + FAR_Z) * 0.5)
const FLOOR_SIZE := Vector2(HALF * 2, HALF - FAR_Z)
## The ground inside the ring of buildings (x, z): a campaign city keeps off it.
const FOOTPRINT := Rect2(FLOOR_CENTER.x - FLOOR_SIZE.x * 0.5, FLOOR_CENTER.z - FLOOR_SIZE.y * 0.5, FLOOR_SIZE.x, FLOOR_SIZE.y)
## Where a run starts and ends (spawns[0] is ENTRY). The campaign reads these
## by path and carries on past EXIT.
const ENTRY := Transform3D(Basis.IDENTITY, Vector3(0, 0, 30))
const EXIT := Transform3D(Basis.IDENTITY, Vector3(-46, 0, -548))
## The overpass: its deck height, the curve's center and the radius of the
## line along its middle. It turns 45 degrees left.
const DECK_Y := 6.0
const CURVE_CENTER := Vector3(-36, 0, -470)
const CURVE_RADIUS := 36.0
const CURVE_ANGLE := PI * 0.25

## Leave the far (-Z) edge open so a mission can carry on past it. Set
## before the builder enters the tree.
@export var open_exit := false
## Sideways ramps: curve radius and how steep they get (degrees).
const BANK_RADIUS := 3.0
const BANK_ANGLE := 60.0
const BANK_STEEP_ANGLE := 75.0


func build() -> void:
	if _root != null:
		_root.queue_free()
	_root = Node3D.new()
	_root.name = "Generated"
	add_child(_root)
	spawns.clear()
	zone_names.clear()

	_box(Vector3(FLOOR_CENTER.x, -0.5, FLOOR_CENTER.z), Vector3(FLOOR_SIZE.x, 1, FLOOR_SIZE.y), Kind.FLOOR)
	_spawn(ENTRY.origin, "1 · COMBO PARK")
	_label("Chain different moves without stopping. Combos bank when you land", Vector3(0, 3.2, 26), 0.9)
	_tower()
	_half_pipe(Vector3(-30, 0, 0))
	_loop_runway(Vector3(30, 0, 0))
	_wall_zigzag(Vector3(0, 0, -26))
	_hurdle_field(Vector3(12, 0, 34))
	_breach_wall(Vector3(-20, 0, 26))
	_banks(Vector3(-34, 0, 0))
	_stepping_stones()
	_edges()
	_canal(-78.0, -200.0)
	_wall_alley(-206.0, -296.0)
	_rollers(-304.0, 6)
	_high_road()
	_overpass()
	_boundary()
	_targets()


# ---------------------------------------------------------------- features

## Two-tier tower in the middle: steps to mantle up, a climb face to the top
## tier, green slide ramps down three sides, kick-off pillars at the corners.
func _tower() -> void:
	# Tier 1: 14 x 14, 3 m up. Tier 2: 6 x 6 on top, 6 m up.
	_box(Vector3(0, 1.5, 0), Vector3(14, 3, 14), Kind.NEUTRAL)
	_box(Vector3(0, 4.5, -2), Vector3(6, 3, 6), Kind.PARKOUR)
	# South steps: 1.5 m, then 1.5 m more to the tier.
	_box(Vector3(0, 0.75, 9), Vector3(6, 1.5, 4), Kind.PARKOUR)
	_label("Mantle up, climb the yellow face, slide down the green", Vector3(0, 4.6, 11.5), 0.8)
	# Slide ramps down: north, east and west.
	_slope(Vector3(0, 3, -7), Vector3(0, 0, -19), 8.0, Kind.SLIDE)
	_slope(Vector3(7, 3, 0), Vector3(19, 0, 0), 6.0, Kind.SLIDE)
	_slope(Vector3(-7, 3, 0), Vector3(-19, 0, 0), 6.0, Kind.SLIDE)
	# Kick-off pillars on the corners.
	for x: float in [-12.0, 12.0]:
		for z: float in [-12.0, 12.0]:
			_box(Vector3(x, 4, z), Vector3(1.2, 8, 1.2), Kind.NEUTRAL)
	_label("Drop off the top: flip, spin or roll the landing", Vector3(0, 8.5, -2), 0.8)


## Two quarter pipes facing each other across a short flat: ride up one,
## flip or spin at the top, land back on it, cross to the other.
func _half_pipe(c: Vector3) -> void:
	_spawn(c + Vector3(0, 0, 0), "2 · HALF-PIPE")
	var radius := 4.5
	var angle := 85.0
	var straight := 1.5
	var gap := 5.0
	_surface(MapPieces.turned(SurfaceShapes.quarter_pipe(c + Vector3(0, 0, -gap), radius, angle, straight, 12.0), c + Vector3(0, 0, -gap), 0.0))
	_surface(MapPieces.turned(SurfaceShapes.quarter_pipe(c + Vector3(0, 0, gap), radius, angle, straight, 12.0), c + Vector3(0, 0, gap), PI))
	var h := SurfaceShapes.quarter_pipe_height(radius, angle, straight)
	_label("HALF-PIPE: run up, flip at the top, land on the ramp", c + Vector3(0, h + 1.5, -gap - 4.0), 0.9)


## A long straight to build top speed, then a loop. You come out to its right.
func _loop_runway(c: Vector3) -> void:
	_spawn(c + Vector3(-4, 0, 40), "3 · LOOP RUNWAY")
	_floor_mark(c + Vector3(-4, 0, 8), Vector2(3.5, 64), Color(0.62, 0.42, 0.28))
	_surface(SurfaceShapes.loop(c + Vector3(-4, 0, -28), 4.5, 3.5, 5.5))
	_label("LOOP: full speed from the far end", c + Vector3(-4, 10.5, -28), 1.0)
	# A launch ramp past the loop for air tricks.
	var q := c + Vector3(-1, 0, -44)
	_surface(SurfaceShapes.quarter_pipe(q, 3.5, 80.0, 0.0, 6.0))


## Blue panels alternating left and right over a red floor: wallrun, hop to
## the next, don't touch red. Beside it, two parallel walls 5 m apart.
func _wall_zigzag(o: Vector3) -> void:
	_spawn(o + Vector3(0, 0, 4), "4 · WALL ZIGZAG")
	_label("Wall to wall without touching the red", o + Vector3(0, 3.5, -2), 0.8)
	for i in 4:
		var side := -1.0 if i % 2 == 0 else 1.0
		_box(o + Vector3(side * 3.0, 3.5, -8.0 - i * 9.0), Vector3(1, 7, 8), Kind.WALLRUN)
	_floor_mark(o + Vector3(0, 0, -21.5), Vector2(5, 37), Color(0.85, 0.3, 0.25))
	# Parallel corridor to the west for wall-to-wall jumps.
	_box(o + Vector3(-15, 3, -18), Vector3(1, 6, 26), Kind.WALLRUN)
	_box(o + Vector3(-10, 3, -18), Vector3(1, 6, 26), Kind.WALLRUN)


## Staggered 1 m blocks to vault and 1.1 m bars to slide under, in rows.
func _hurdle_field(o: Vector3) -> void:
	_spawn(o + Vector3(0, 0, 18), "5 · HURDLE FIELD")
	_label("Vault the yellow, slide under the bars", o + Vector3(0, 3.2, 14), 0.8)
	for row in 4:
		var z := o.z + 8.0 - row * 7.0
		if row == 2:
			# Slide bars on posts.
			_box(Vector3(o.x, 1.35, z), Vector3(14, 0.5, 0.6), Kind.PARKOUR)
			for x: float in [-7.2, 7.2]:
				_box(Vector3(o.x + x, 0.55, z), Vector3(0.4, 1.1, 0.6), Kind.NEUTRAL)
			continue
		var shift := 2.5 if row % 2 == 0 else -2.5
		for i in 3:
			_box(Vector3(o.x + shift + (i - 1) * 6.0, 0.5, z), Vector3(3, 1, 0.6), Kind.PARKOUR)


## A wall with a door to kick, a window to slide through and one to smash.
func _breach_wall(o: Vector3) -> void:
	var z := o.z
	_box(Vector3(o.x - 5.6, 1.5, z), Vector3(2.8, 3.0, 0.3), Kind.NEUTRAL)   # x -7..-4.2
	_door(Vector3(o.x - 4.2, 0, z))                                          # -4.2..-3.1
	_box(Vector3(o.x - 3.65, 2.6, z), Vector3(1.1, 0.8, 0.3), Kind.NEUTRAL)
	_box(Vector3(o.x - 2.1, 1.5, z), Vector3(2.0, 3.0, 0.3), Kind.NEUTRAL)   # -3.1..-1.1
	_window(Vector3(o.x, 0.0, z), Vector2(2.2, 1.4))                         # -1.1..1.1, slide under
	_box(Vector3(o.x, 2.2, z), Vector3(2.2, 1.6, 0.3), Kind.NEUTRAL)
	_box(Vector3(o.x + 2.1, 1.5, z), Vector3(2.0, 3.0, 0.3), Kind.NEUTRAL)   # 1.1..3.1
	_window(Vector3(o.x + 4.2, 1.0, z), Vector2(2.2, 1.4))                   # 3.1..5.3, sill 1 m
	_box(Vector3(o.x + 4.2, 0.5, z), Vector3(2.2, 1.0, 0.3), Kind.PARKOUR)
	_box(Vector3(o.x + 4.2, 2.7, z), Vector3(2.2, 0.6, 0.3), Kind.NEUTRAL)
	_box(Vector3(o.x + 6.15, 1.5, z), Vector3(1.7, 3.0, 0.3), Kind.NEUTRAL)  # 5.3..7
	_label("Kick (F) · slide (Ctrl) · smash at speed", Vector3(o.x, 3.5, z + 0.4), 0.8)


## Sideways ramps along the west side: run along them tilted, like a
## wallrun on a slope. The gentle one first, then a steep one further on.
func _banks(c: Vector3) -> void:
	_spawn(c + Vector3(3, 0, 46), "6 · BANKED RAMPS")
	_label("Sideways ramps: run along them at speed", c + Vector3(0, 4.5, 44), 0.8)
	_surface(MapPieces.bank(c + Vector3(0, 0, 44), 28.0, -1.0, BANK_RADIUS, BANK_ANGLE, 1.0))
	# Steeper and taller, beside the half-pipe and on toward the zigzag.
	_surface(MapPieces.bank(c + Vector3(0, 0, -12), 26.0, -1.0, BANK_RADIUS, BANK_STEEP_ANGLE, 2.0))


## Long blue walls down the west and east sides, close enough to use.
func _edges() -> void:
	for x: float in [-42.0, 42.0]:
		_box(Vector3(x, 3, 0), Vector3(1, 6, 84), Kind.WALLRUN)


## Ruined buildings all round the yard, so there is no running off the world.
## The long park: a 120 m canal (two sideways ramps facing each other) to
## carve down at speed, side features to peel off to.
func _canal(z0: float, z1: float) -> void:
	_spawn(Vector3(0, 0, z0 + 4.0), "7 · CANAL")
	_label("The canal: ride the sides, never stop", Vector3(0, 3.5, z0), 0.9)
	var length := z0 - z1
	_surface(MapPieces.bank(Vector3(-5, 0, z0), length, -1.0, 3.0, 65.0, 1.0))
	_surface(MapPieces.bank(Vector3(5, 0, z0), length, 1.0, 3.0, 65.0, 1.0))
	# Kick-off pillars and slide bars along the canal floor, off the middle.
	for i in 5:
		var z := z0 - 18.0 - i * 22.0
		if i % 2 == 0:
			_box(Vector3(0, 1.35, z), Vector3(10, 0.5, 0.6), Kind.PARKOUR)
		else:
			_box(Vector3(2.5 * (1 if i % 4 == 1 else -1), 0.5, z), Vector3(3, 1, 0.8), Kind.PARKOUR)
	# Off to the sides: long blue walls and a green slide tower.
	for x: float in [-24.0, 24.0]:
		_box(Vector3(x, 3, (z0 + z1) * 0.5), Vector3(1, 6, length - 20.0), Kind.WALLRUN)
	_box(Vector3(40, 3, -150), Vector3(10, 6, 10), Kind.NEUTRAL)
	_box(Vector3(40, 0.75, -142), Vector3(4, 1.5, 6), Kind.PARKOUR)
	_box(Vector3(40, 2.25, -144), Vector3(4, 1.5, 2), Kind.PARKOUR)
	_slope(Vector3(40, 6, -155), Vector3(40, 0, -175), 6.0, Kind.SLIDE)
	_slope(Vector3(35, 6, -150), Vector3(20, 0, -150), 6.0, Kind.SLIDE)


## Eight blue walls alternating sides (wall to wall without touching the
## ground), and a long parallel pair to the west for wall-to-wall jumps.
func _wall_alley(z0: float, z1: float) -> void:
	_spawn(Vector3(0, 0, z0 + 1.0), "8 · WALL ALLEY")
	_label("Wall to wall, all the way down", Vector3(0, 3.5, z0 - 2.0), 0.9)
	for i in 8:
		var side := -1.0 if i % 2 == 0 else 1.0
		_box(Vector3(side * 3.0, 3.5, z0 - 10.0 - i * 9.0), Vector3(1, 7, 8), Kind.WALLRUN)
	_floor_mark(Vector3(0, 0, (z0 + z1) * 0.5 - 4.0), Vector2(5, z0 - z1 - 6.0), Color(0.85, 0.3, 0.25))
	for x: float in [-22.0, -16.0]:
		_box(Vector3(x, 3, (z0 + z1) * 0.5), Vector3(1, 6, z0 - z1), Kind.WALLRUN)
	# East: a run of mantle blocks rising and falling.
	for i in 6:
		var h := 1.5 * float(1 + mini(i, 5 - i))
		_box(Vector3(20, h * 0.5, z0 - 8.0 - i * 4.0), Vector3(4, h, 4), Kind.PARKOUR)


## Green rollers: rise and fall in a line, to pump (slide down each back for
## speed). Clear lanes either side.
func _rollers(z0: float, count: int) -> void:
	_spawn(Vector3(0, 0, z0 + 4.0), "9 · ROLLERS")
	_label("Rollers: slide down the backs", Vector3(0, 4.0, z0 + 1.0), 0.9)
	var z := z0 - 2.0
	for i in count:
		var top := 1.8
		_slope(Vector3(0, top, z - 5.0), Vector3(0, 0, z), 10.0, Kind.SLIDE)
		_box(Vector3(0, top * 0.5, z - 6.0), Vector3(10, top, 2), Kind.SLIDE)
		_slope(Vector3(0, top, z - 7.0), Vector3(0, 0, z - 12.0), 10.0, Kind.SLIDE)
		z -= 14.0
	# Kick pillars along the outside lanes, and a last vault line.
	for x: float in [-12.0, 12.0]:
		for i in 4:
			_box(Vector3(x, 3, z0 - 10.0 - i * 20.0), Vector3(1.2, 6, 1.2), Kind.NEUTRAL)
	_box(Vector3(0, 0.5, z - 6.0), Vector3(14, 1, 0.8), Kind.PARKOUR)



## The high road: a line of low roofs above the east side, from the yard to
## the rollers, so the long park has a second way through, up off the ground.
## A slab up, hurdles and a pipe, a gap, crates, a climb, a wallrun gap,
## hurdles, and a slide ramp back down.
func _high_road() -> void:
	var x := HIGH_ROAD_X
	_label("THE HIGH ROAD", Vector3(x, 3.5, -66), 1.2)
	_slope(Vector3(x, 4, -84), Vector3(x, 0, -70), 8.0, Kind.NEUTRAL).set_meta("look", "RUST")
	_deck(x - 4.0, x + 4.0, -84.0, -130.0, 4.0)
	_box(Vector3(x, 4.5, -96), Vector3(8, 1.0, 0.4), Kind.PARKOUR)
	_box(Vector3(x, 5.35, -110), Vector3(8, 0.5, 0.6), Kind.PARKOUR)
	for px: float in [x - 3.8, x + 3.8]:
		_box(Vector3(px, 4.55, -110), Vector3(0.4, 1.1, 0.6), Kind.NEUTRAL)
	_deck(x - 4.0, x + 4.0, -136.0, -180.0, 4.0)
	_box(Vector3(x, 4.5, -150), Vector3(8, 1.0, 1.4), Kind.PARKOUR).set_meta("dress", "crates")
	_box(Vector3(x, 5.5, -179.85), Vector3(8, 3.0, 0.3), Kind.PARKOUR)
	_label("Climb", Vector3(x, 8.6, -174), 0.8)
	_deck(x - 6.0, x + 6.0, -180.0, -230.0, 7.0)
	_box(Vector3(x, 7.5, -195), Vector3(12, 1.0, 0.4), Kind.PARKOUR)
	_box(Vector3(x - 5.8, 7.4, -224), Vector3(0.4, 0.8, 8.0), Kind.NEUTRAL)
	_label("Wallrun the right wall", Vector3(x, 10, -222), 0.8)
	_box(Vector3(x + 6.5, 9.5, -236), Vector3(1.0, 9.0, 18.0), Kind.WALLRUN)
	_deck(x - 6.0, x + 6.0, -242.0, -290.0, 7.0)
	for z: float in [-256.0, -270.0]:
		_box(Vector3(x, 7.5, z), Vector3(12, 1.0, 0.4), Kind.PARKOUR)
	_slope(Vector3(x, 7, -290), Vector3(x, 0, -314), 8.0, Kind.SLIDE)
	_label("Slide down", Vector3(x, 10, -286), 0.8)


## A broken highway overpass past the rollers: a ramp up, a deck that curves
## 45 degrees left over pillars, barriers to vault, a collapsed gap, and a
## fallen slab to slide down to the exit. Underneath, the pillars make a
## slalom on the ground for anyone who'd rather stay low.
func _overpass() -> void:
	_spawn(Vector3(0, 0, -414), "10 · OVERPASS")
	_label("The overpass: up the ramp, round the bend, mind the gap", Vector3(0, 3.5, -417), 0.9)
	_slope(Vector3(0, DECK_Y, -450), Vector3(0, 0, -420), 10.0, Kind.NEUTRAL)
	_viaduct(Transform3D(Basis.IDENTITY, Vector3(0, 0, -460)), 20.0)
	_barrier(Transform3D(Basis.IDENTITY, Vector3(0, 0, -460)))
	# The bend: short straight pieces round the curve, a barrier halfway.
	var n := 9
	var d := CURVE_ANGLE / n
	var outer := CURVE_RADIUS + 5.0
	var length := 2.0 * outer * tan(d * 0.5) + 0.1
	for i in n:
		_viaduct(curve_at((i + 0.5) * d), length)
	_barrier(curve_at(CURVE_ANGLE * 0.5))
	# Past the bend, straight on its new heading: a piece, the gap, a piece.
	var end := curve_at(CURVE_ANGLE)
	var fwd := -end.basis.z
	_viaduct(end.translated(fwd * 5.0), 10.0)
	var far := end.translated(fwd * (10.0 + GAP + 7.0))
	_viaduct(far, 14.0)
	_label("Gap: jump it", end.origin + fwd * 6.0 + Vector3(0, DECK_Y + 2.5, 0), 0.8)
	var top := far.origin + fwd * 7.0 + Vector3(0, DECK_Y, 0)
	_slope(top, top + fwd * 20.0 - Vector3(0, DECK_Y, 0), 10.0, Kind.SLIDE)
	_label("EXIT", EXIT.origin + Vector3(0, 4.0, 0), 1.6)


## Where the overpass's middle line is, `angle` round its bend, facing along it.
static func curve_at(angle: float) -> Transform3D:
	var right := Vector3(cos(angle), 0, -sin(angle))
	return Transform3D(Basis(Vector3.UP, angle), CURVE_CENTER + right * CURVE_RADIUS)


## Length of the gap in the overpass, past the bend.
const GAP := 7.0
## The high road's middle line (x).
const HIGH_ROAD_X := 56.0


## One piece of overpass deck, `length` long, centered on `at` (ground
## level, facing along the road), on a pillar.
func _viaduct(at: Transform3D, length: float) -> void:
	_box_basis(at * Vector3(0, DECK_Y - 0.5, 0), Vector3(10, 1, length), at.basis, Kind.NEUTRAL)
	_box_basis(at * Vector3(0, (DECK_Y - 1.0) * 0.5, 0), Vector3(1.6, DECK_Y - 1.0, 1.6), at.basis, Kind.NEUTRAL)


## A concrete barrier across the overpass's middle lanes.
func _barrier(at: Transform3D) -> void:
	_box_basis(at * Vector3(0, DECK_Y + 0.5, 0), Vector3(6, 1.0, 0.5), at.basis, Kind.PARKOUR).set_meta("dress", "barrier")


## A low building whose roof is part of the high road.
func _deck(x0: float, x1: float, z0: float, z1: float, top: float) -> void:
	_box(Vector3((x0 + x1) * 0.5, top * 0.5, (z0 + z1) * 0.5), Vector3(x1 - x0, top, absf(z1 - z0)), Kind.NEUTRAL).set_meta("look", "FACADE")


func _boundary() -> void:
	for piece in MapPieces.perimeter(FLOOR_CENTER, FLOOR_SIZE, 18.0, 30.0, 16.0, 10.0, open_exit):
		var t: Transform3D = piece.transform
		_box_basis(t.origin, piece.size, t.basis, Kind.NEUTRAL).set_meta("look", "FACADE")


## Small pieces between the big features, so there is always something to
## vault, mantle or wallrun on the way from one to the next.
func _stepping_stones() -> void:
	for x: float in [-20.0, 20.0]:
		# 1.5 m blocks to mantle and jump off.
		for z: float in [-18.0, 10.0]:
			_box(Vector3(x, 0.75, z), Vector3(4, 1.5, 4), Kind.PARKOUR)
		# Short blue fins to wallrun past.
		_box(Vector3(x, 2, -30), Vector3(1, 4, 8), Kind.WALLRUN)
	_box(Vector3(36, 2, 30), Vector3(1, 4, 8), Kind.WALLRUN)
	# Low benches to vault on the tower's south lawn.
	for x: float in [-6.0, 6.0]:
		_box(Vector3(x, 0.5, 17), Vector3(3, 1, 0.8), Kind.PARKOUR)


func _targets() -> void:
	_target(Vector3(-19, 0, -120), ShootingTarget.Motion.STRAFE, 2.0, 3.0)
	_target(Vector3(40, 6, -150), ShootingTarget.Motion.STATIC)
	_target(Vector3(10, 0, -250), ShootingTarget.Motion.BOB)
	_target(Vector3(-19, 0, -270), ShootingTarget.Motion.STATIC)
	_target(Vector3(0, 0, -390), ShootingTarget.Motion.STRAFE, 6.0, 4.0)
	_target(Vector3(0, 6, -2), ShootingTarget.Motion.STATIC)
	_target(Vector3(-12, 0, -24), ShootingTarget.Motion.STRAFE, 4.0, 4.0)
	_target(Vector3(14, 0, -22), ShootingTarget.Motion.CIRCLE, 4.0, 3.0)
	_target(Vector3(-30, 0, -16), ShootingTarget.Motion.BOB, 1.0, 1.2)
	_target(Vector3(36, 0, -10), ShootingTarget.Motion.STRAFE, 3.0, 5.0)
	_target(Vector3(8, 0, 6), ShootingTarget.Motion.STATIC)
	_target(Vector3(-22, 0, 22), ShootingTarget.Motion.STATIC)


# ---------------------------------------------------------------- helpers

## A flat ramp from `top` down to `bottom` in any direction.
func _slope(top: Vector3, bottom: Vector3, width: float, kind: Kind) -> StaticBody3D:
	var f := (bottom - top).normalized()
	var x := Vector3.UP.cross(f).normalized()
	var y := f.cross(x).normalized()
	var basis := Basis(x, y, f)
	return _box_basis((top + bottom) * 0.5 - y * 0.5, Vector3(width, 1, top.distance_to(bottom)), basis, kind)
