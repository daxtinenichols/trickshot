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

const HALF := 66.0  # yard is 132 x 132 m
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

	_box(Vector3(0, -0.5, 0), Vector3(HALF * 2, 1, HALF * 2), Kind.FLOOR)
	_spawn(Vector3(0, 0, 30), "1 · COMBO PARK")
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
	_floor_mark(c + Vector3(-4, 0, 8), Vector2(3.5, 64), Color(0.55, 0.45, 0.8))
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


## A wall with a door to kick, a window to dive through and one to smash.
func _breach_wall(o: Vector3) -> void:
	var z := o.z
	_box(Vector3(o.x - 5.6, 1.5, z), Vector3(2.8, 3.0, 0.3), Kind.NEUTRAL)   # x -7..-4.2
	_door(Vector3(o.x - 4.2, 0, z))                                          # -4.2..-3.1
	_box(Vector3(o.x - 3.65, 2.6, z), Vector3(1.1, 0.8, 0.3), Kind.NEUTRAL)
	_box(Vector3(o.x - 2.1, 1.5, z), Vector3(2.0, 3.0, 0.3), Kind.NEUTRAL)   # -3.1..-1.1
	_window(Vector3(o.x, 0.2, z), Vector2(2.2, 1.2))                         # -1.1..1.1
	_box(Vector3(o.x, 0.1, z), Vector3(2.2, 0.2, 0.3), Kind.NEUTRAL)
	_box(Vector3(o.x, 2.2, z), Vector3(2.2, 1.6, 0.3), Kind.NEUTRAL)
	_box(Vector3(o.x + 2.1, 1.5, z), Vector3(2.0, 3.0, 0.3), Kind.NEUTRAL)   # 1.1..3.1
	_window(Vector3(o.x + 4.2, 1.0, z), Vector2(2.2, 1.4))                   # 3.1..5.3, sill 1 m
	_box(Vector3(o.x + 4.2, 0.5, z), Vector3(2.2, 1.0, 0.3), Kind.PARKOUR)
	_box(Vector3(o.x + 4.2, 2.7, z), Vector3(2.2, 0.6, 0.3), Kind.NEUTRAL)
	_box(Vector3(o.x + 6.15, 1.5, z), Vector3(1.7, 3.0, 0.3), Kind.NEUTRAL)  # 5.3..7
	_label("Kick (F) · dive (Z) · smash at speed", Vector3(o.x, 3.5, z + 0.4), 0.8)


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
	_target(Vector3(0, 6, -2), ShootingTarget.Motion.STATIC)
	_target(Vector3(-12, 0, -24), ShootingTarget.Motion.STRAFE, 4.0, 4.0)
	_target(Vector3(14, 0, -22), ShootingTarget.Motion.CIRCLE, 4.0, 3.0)
	_target(Vector3(-30, 0, -16), ShootingTarget.Motion.BOB, 1.0, 1.2)
	_target(Vector3(36, 0, -10), ShootingTarget.Motion.STRAFE, 3.0, 5.0)
	_target(Vector3(8, 0, 6), ShootingTarget.Motion.STATIC)
	_target(Vector3(-22, 0, 22), ShootingTarget.Motion.STATIC)


# ---------------------------------------------------------------- helpers

## A flat ramp from `top` down to `bottom` in any direction.
func _slope(top: Vector3, bottom: Vector3, width: float, kind: Kind) -> void:
	var f := (bottom - top).normalized()
	var x := Vector3.UP.cross(f).normalized()
	var y := f.cross(x).normalized()
	var basis := Basis(x, y, f)
	_box_basis((top + bottom) * 0.5 - y * 0.5, Vector3(width, 1, top.distance_to(bottom)), basis, kind)
