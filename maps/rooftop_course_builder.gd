@tool
class_name RooftopCourseBuilder
extends SandboxBuilder
## "Rooftops": a timed obstacle course across a row of rooftops, run toward
## -Z. Each roof teaches one thing and the next one mixes it in: hurdles and a
## slide bar, a gap, a door and a window, a wallrun across a wide gap, a wall
## climb up to a higher roof, a big drop to roll out of, an optional loop, and
## a last gap past a kick-off pillar to the finish.
##
## Falling to the street sends you back to the last checkpoint (CourseTimer).
## Sizes come from the movement numbers: 1.6 m jump apex, ~9 m running jump
## at top speed, ~10-13 m wallruns, 3 m climb + mantle.

## Roof top height, z start, z end (z runs negative), width.
const ROOFS := [
	[10.0, 0.0, -40.0, 12.0],    # R1 start: hurdles, slide bar
	[10.0, -44.0, -72.0, 12.0],  # R2: door and window wall
	[10.0, -84.0, -104.0, 12.0], # R3: after the wallrun gap
	[13.0, -104.0, -124.0, 12.0],# R4: 3 m higher, climb up to it
	[4.0, -128.0, -172.0, 20.0], # R5: 9 m drop, loop
	[4.0, -178.0, -200.0, 12.0], # R6: finish
]

## Where each part starts (z) and its name, in order. The first is the
## start line; the last is the finish line. Checkpoints are in between.
const START_Z := -6.0
const CHECKPOINTS := [
	[-45.0, "Door and window"],
	[-85.0, "Climb"],
	[-129.0, "Drop and loop"],
]
const FINISH_Z := -186.0
## Below this height you're in the street: back to the last checkpoint.
const FAIL_Y := 2.5


func build() -> void:
	if _root != null:
		_root.queue_free()
	_root = Node3D.new()
	_root.name = "Generated"
	add_child(_root)
	spawns.clear()
	zone_names.clear()

	# The street, far below.
	_box(Vector3(0, -0.5, -100), Vector3(160, 1, 320), Kind.FLOOR)
	for r: Array in ROOFS:
		_roof(r[0], r[1], r[2], r[3])

	_spawn_at(Vector3(0, 10, -2), "1 · START")
	_label("ROOFTOPS: reach the finish as fast as you can", Vector3(0, 14.2, -6), 1.3)
	_line(START_Z, 10.0, Color(0.3, 0.9, 0.45))
	_section_hurdles()
	_section_breach()
	_section_wallrun_gap()
	_section_climb()
	_section_drop()
	_section_finish()
	_skyline()


## Spawn points for the number keys: start, then each checkpoint.
func checkpoint_spawn(i: int) -> Transform3D:
	return spawns[clampi(i, 0, spawns.size() - 1)]


# ---------------------------------------------------------------- sections

func _section_hurdles() -> void:
	_label("Jump hurdles to vault them", Vector3(0, 13, -12), 0.8)
	for z: float in [-14.0, -21.0]:
		_box(Vector3(0, 10.5, z), Vector3(12, 1.0, 0.4), Kind.PARKOUR)
	# Slide bar: 1.1 m clearance, crouch height is 1.0.
	_label("Slide under", Vector3(0, 13, -29), 0.8)
	_box(Vector3(0, 11.35, -31), Vector3(12, 0.5, 0.6), Kind.PARKOUR)
	for x: float in [-5.8, 5.8]:
		_box(Vector3(x, 10.55, -31), Vector3(0.4, 1.1, 0.6), Kind.NEUTRAL)
	_label("Jump the gap", Vector3(0, 13, -38), 0.8)


func _section_breach() -> void:
	_spawn_at(Vector3(0, 10, -46), "2 · DOOR AND WINDOW")
	var z := -58.0
	var y := 10.0
	# Wall across the roof: door on the left half, low window on the right.
	_box(Vector3(-4.1, y + 1.5, z), Vector3(3.8, 3.0, 0.3), Kind.NEUTRAL)   # x -6..-2.2
	_door(Vector3(-2.2, y, z))                                              # panel x -2.2..-1.1
	_box(Vector3(-1.65, y + 2.6, z), Vector3(1.1, 0.8, 0.3), Kind.NEUTRAL)  # over the door
	_box(Vector3(0.55, y + 1.5, z), Vector3(3.3, 3.0, 0.3), Kind.NEUTRAL)   # x -1.1..2.2
	_window(Vector3(3.3, y + 0.2, z), Vector2(2.2, 1.2))                    # x 2.2..4.4
	_box(Vector3(3.3, y + 0.1, z), Vector3(2.2, 0.2, 0.3), Kind.NEUTRAL)    # sill
	_box(Vector3(3.3, y + 2.2, z), Vector3(2.2, 1.6, 0.3), Kind.NEUTRAL)    # over the window
	_box(Vector3(5.2, y + 1.5, z), Vector3(1.6, 3.0, 0.3), Kind.NEUTRAL)    # x 4.4..6
	_label("Kick the door (F) or dive through the window (Z)", Vector3(0, y + 3.6, z + 0.4), 0.8)
	_label("Wallrun the blue wall across the gap", Vector3(0, y + 3, -68), 0.8)


func _section_wallrun_gap() -> void:
	# 12 m gap (R2 ends -72, R3 starts -84): too far to jump, easy along
	# the wall on the right.
	_box(Vector3(6.5, 12.5, -78.0), Vector3(1.0, 9.0, 18.0), Kind.WALLRUN)
	# Low parapet on the left so you know which side to use.
	_box(Vector3(-5.8, 10.4, -68.0), Vector3(0.4, 0.8, 8.0), Kind.NEUTRAL)


func _section_climb() -> void:
	_spawn_at(Vector3(0, 10, -86), "3 · CLIMB")
	# R4's front face (z -104) is 3 m above R3: a yellow face to climb.
	_box(Vector3(0, 11.5, -103.85), Vector3(12, 3.0, 0.3), Kind.PARKOUR)
	_label("Run straight at the wall and jump to climb it", Vector3(0, 13.8, -100), 0.8)
	# Hurdle on the way so it isn't just running.
	_box(Vector3(0, 10.5, -92), Vector3(12, 1.0, 0.4), Kind.PARKOUR)
	# Up top: a dive window in a short wall, and the edge.
	var z := -114.0
	var y := 13.0
	_box(Vector3(-3.4, y + 1.5, z), Vector3(5.2, 3.0, 0.3), Kind.NEUTRAL)   # x -6..-0.8
	_window(Vector3(0.3, y + 0.2, z), Vector2(2.2, 1.2))                    # x -0.8..1.4
	_box(Vector3(0.3, y + 0.1, z), Vector3(2.2, 0.2, 0.3), Kind.NEUTRAL)
	_box(Vector3(0.3, y + 2.2, z), Vector3(2.2, 1.6, 0.3), Kind.NEUTRAL)
	_box(Vector3(3.7, y + 1.5, z), Vector3(4.6, 3.0, 0.3), Kind.NEUTRAL)    # x 1.4..6
	_label("Dive through (Z), or smash it at full speed", Vector3(0.3, y + 3.6, z + 0.4), 0.8)
	_label("9 m drop: press crouch just before you land to roll", Vector3(0, y + 2.5, -121), 0.8)


func _section_drop() -> void:
	_spawn_at(Vector3(0, 4, -131), "4 · DROP AND LOOP")
	# Left lane: a loop for style (needs a full-speed run-up). It comes out
	# 5.5 m to the right, still clear of the straight line from the window.
	_surface(SurfaceShapes.loop(Vector3(-8.0, 4.0, -150), 4.5, 3.5, 5.5))
	_label("LOOP (optional)", Vector3(-8.0, 14.5, -150), 1.0)
	# Right edge: a sideways ramp to ride out of the landing.
	_surface(MapPieces.bank(Vector3(6.5, 4.0, -130), 10.0, 1.0, 3.0, 60.0, 1.0))
	# Right lane, straight on from the window: hurdles to keep the combo going.
	for z: float in [-142.0, -152.0, -162.0]:
		_box(Vector3(3.75, 4.45, z), Vector3(9.5, 0.9, 0.4), Kind.PARKOUR)
	_label("Jump the gap: kick (F) off the pillar for extra distance", Vector3(0, 7, -168), 0.8)
	# Kick-off pillar in the 6 m gap.
	_box(Vector3(0, 3.5, -175), Vector3(1.2, 7.0, 1.2), Kind.NEUTRAL)


func _section_finish() -> void:
	_line(FINISH_Z, 4.0, Color(1.0, 0.85, 0.2))
	_label("FINISH", Vector3(0, 8.2, FINISH_Z), 1.8)
	# Shooting gallery past the finish line for a victory lap.
	_target(Vector3(-3, 4, -196), ShootingTarget.Motion.STATIC)
	_target(Vector3(3, 4, -196), ShootingTarget.Motion.STRAFE, 2.5, 3.0)


## A few tall blocks around the course so it reads as a city, not a void.
func _skyline() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 18:
		var side := -1.0 if i % 2 == 0 else 1.0
		var z := -10.0 - i * 11.0
		var h := rng.randf_range(14.0, 34.0)
		var w := rng.randf_range(8.0, 14.0)
		var b := _box(Vector3(side * rng.randf_range(20.0, 30.0), h * 0.5, z), Vector3(w, h, rng.randf_range(8.0, 12.0)), Kind.NEUTRAL)
		b.set_meta("look", "FACADE")


# ---------------------------------------------------------------- helpers

## A building whose roof is part of the course; its sides look like a ruined
## facade (the art look reads the "look" meta; gameplay only sees NEUTRAL).
func _roof(top: float, z0: float, z1: float, width: float) -> void:
	var b := _box(Vector3(0, top * 0.5, (z0 + z1) * 0.5), Vector3(width, top, absf(z1 - z0)), Kind.NEUTRAL)
	b.set_meta("look", "FACADE")


## Start and finish lines: a colored stripe across the roof.
func _line(z: float, y: float, color: Color) -> void:
	_floor_mark(Vector3(0, y, z), Vector2(12, 0.8), color)


func _spawn_at(pos: Vector3, title: String) -> void:
	spawns.append(Transform3D(Basis.IDENTITY, pos))
	zone_names.append(title)
