@tool
class_name RooftopCourseBuilder
extends SandboxBuilder
## "Rooftops": a timed obstacle course across the roofs of the city, about
## 950 m. It heads -Z, turns left along a row of roofs, then right and on
## toward -Z again, so you carve two wide corners at speed.
##
## Leg 1 (toward -Z) teaches one thing per roof and the next mixes it in:
## hurdles and a slide bar, a gap, a door and a window, a wallrun across a
## wide gap, a climb up to a higher roof, a big drop to roll out of, an
## optional loop, a long sprint, a field of rooftop plant and a climb, then
## a window wall and the first corner, with a banked curve round its outside.
## Leg 2 (toward -X) splits: a high line up a slab and along a narrow roof
## with a wallrun gap, or a low line down onto the roofs below and a climb
## back up. They meet at the second corner (banked too).
## Leg 3 (toward -Z) steps up three roofs, forks again over a wide gap (a
## wallrun on the left or a girder on the right), slides down to a wide roof
## with an optional loop, and jumps a last gap to the finish.
##
## Falling to the street sends you back to the last checkpoint (CourseTimer).
## Sizes come from the movement numbers: 1.6 m jump apex, ~9 m running jump
## at speed, ~10-13 m wallruns, 3 m climb + mantle, 1.5 m mantle.

const PropKit := preload("res://art/props/prop_kit.gd")

## Leg 1's roofs: top height, z start, z end (z runs negative), width. The
## first 200 m are also the campaign's Dawn Run, so they stay put.
const ROOFS := [
	[10.0, 0.0, -40.0, 12.0],    # R1 start: hurdles, slide bar
	[10.0, -44.0, -72.0, 12.0],  # R2: door and window wall
	[10.0, -84.0, -104.0, 12.0], # R3: after the wallrun gap
	[13.0, -104.0, -124.0, 12.0],# R4: 3 m higher, climb up to it
	[4.0, -128.0, -172.0, 20.0], # R5: 9 m drop, loop
	[4.0, -178.0, -240.0, 12.0], # R6: rooftop sprint
	[4.0, -246.0, -300.0, 14.0], # R7: AC field
	[7.0, -300.0, -386.0, 20.0], # R8: climb up to it, window wall, first corner
]

## The three legs: each authors its roofs in its own frame, running toward
## local -Z with local +X on the runner's right. Leg 2 runs toward world -X
## along z = LEG2_Z; leg 3 toward world -Z along x = LEG3_X.
const LEG2_Z := -369.0
const LEG3_X := -198.0
const LEG2 := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, 0, LEG2_Z))
const LEG3 := Transform3D(Basis.IDENTITY, Vector3(LEG3_X, 0, 0))
## The corners: centers and the radius of the racing line round them.
const TURN1_CENTER := Vector3(-17.0, 7.0, -352.0)
const TURN1_RADIUS := 17.0
const TURN2_CENTER := Vector3(-180.0, 7.0, -387.0)
const TURN2_RADIUS := 18.0

## The racing line through the whole course (lane center), for the timer's
## progress and the test bot: points in order, the corners as arcs.
static func path() -> PackedVector3Array:
	var pts := PackedVector3Array()
	pts.append(Vector3(0, 0, 0))
	pts.append(Vector3(0, 0, TURN1_CENTER.z))
	for i in range(1, 12):
		var a := PI * 0.5 * i / 12.0
		pts.append(Vector3(TURN1_CENTER.x + TURN1_RADIUS * cos(a), 0, TURN1_CENTER.z - TURN1_RADIUS * sin(a)))
	pts.append(Vector3(TURN1_CENTER.x, 0, LEG2_Z))
	pts.append(Vector3(TURN2_CENTER.x, 0, LEG2_Z))
	for i in range(1, 12):
		var a := PI * 0.5 * i / 12.0
		pts.append(Vector3(TURN2_CENTER.x - TURN2_RADIUS * sin(a), 0, TURN2_CENTER.z + TURN2_RADIUS * cos(a)))
	pts.append(Vector3(LEG3_X, 0, TURN2_CENTER.z))
	pts.append(Vector3(LEG3_X, 0, -800))
	return pts

## Where the run starts (z) and each checkpoint gate: where it stands, the
## heading you cross it on (yaw, 0 = toward -Z) and its name. The last gate
## is the finish line. Each checkpoint has a spawn just past its gate.
const START_Z := -6.0
const CHECKPOINTS := [
	[Vector3(0, 10, -45), 0.0, "Door and window"],
	[Vector3(0, 10, -85), 0.0, "Climb"],
	[Vector3(0, 4, -129), 0.0, "Drop and loop"],
	[Vector3(0, 4, -179), 0.0, "Rooftop sprint"],
	[Vector3(0, 7, -301), 0.0, "First corner"],
	[Vector3(-12, 7, LEG2_Z), PI * 0.5, "High line or low line"],
	[Vector3(LEG3_X, 7, -399), 0.0, "Step up"],
	[Vector3(LEG3_X, 10, -495), 0.0, "The fork"],
	[Vector3(LEG3_X, 10, -575), 0.0, "Slide down"],
]
const FINISH := [Vector3(LEG3_X, 4, -740), 0.0, "Finish"]
const FINISH_Z := -740.0
## Where a run starts and ends (spawns[0] is ENTRY). The campaign reads these
## by path and carries on past EXIT, still heading -Z.
const ENTRY := Transform3D(Basis.IDENTITY, Vector3(0, 10, -2))
const EXIT := Transform3D(Basis.IDENTITY, Vector3(LEG3_X, 4, -772))
## The street below, closed all round by tall buildings.
const STREET_CENTER := Vector3(-105, 0, -395)
const STREET_SIZE := Vector2(290, 830)

## Leave the far (-Z) edge open so a mission can carry on past it. Set
## before the builder enters the tree.
@export var open_exit := false
## Below this height you're in the street: back to the last checkpoint.
const FAIL_Y := 2.5

## The frame the section being built is authored in (see LEG2, LEG3).
var _xf := Transform3D.IDENTITY
## Every roof's footprint (x, z), so the skyline keeps clear of the course.
var _footprints: Array[Rect2] = []


func build() -> void:
	if _root != null:
		_root.queue_free()
	_root = Node3D.new()
	_root.name = "Generated"
	add_child(_root)
	spawns.clear()
	zone_names.clear()
	_footprints.clear()
	_xf = Transform3D.IDENTITY

	# The street, far below.
	_box(Vector3(STREET_CENTER.x, -0.5, STREET_CENTER.z), Vector3(STREET_SIZE.x, 1, STREET_SIZE.y), Kind.FLOOR)
	for piece in MapPieces.perimeter(STREET_CENTER, STREET_SIZE, 18.0, 30.0, 16.0, 10.0, open_exit):
		var t: Transform3D = piece.transform
		_box_basis(t.origin, piece.size, t.basis, Kind.NEUTRAL).set_meta("look", "FACADE")
	for r: Array in ROOFS:
		_roof(r[0], r[1], r[2], -r[3] * 0.5, r[3] * 0.5)

	_spawn_at(ENTRY.origin, "1 · START")
	_label("ROOFTOPS: reach the finish as fast as you can", Vector3(0, 14.2, -6), 1.3)
	_line(START_Z, 10.0, Color(0.3, 0.9, 0.45))
	_section_hurdles()
	_section_breach()
	_section_wallrun_gap()
	_section_climb()
	_section_drop()
	_section_sprint()
	_section_first_corner()
	_xf = LEG2
	_section_split()
	_xf = LEG3
	_section_step_up()
	_section_fork()
	_section_slide_down()
	_section_finish()
	_xf = Transform3D.IDENTITY
	_skyline()


## Spawn points for the number keys: start, then each checkpoint.
func checkpoint_spawn(i: int) -> Transform3D:
	return spawns[clampi(i, 0, spawns.size() - 1)]


## True once `pos` is past gate `gate` ([at, yaw, name]): in front of it on
## its heading, beside it (not off on another leg) and near its height.
static func past_gate(gate: Array, pos: Vector3) -> bool:
	var at: Vector3 = gate[0]
	var yaw: float = gate[1]
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var d := pos - at
	return d.dot(fwd) >= 0.0 and d.dot(fwd) < 40.0 and absf(d.dot(right)) < 26.0 and absf(d.y) < 12.0


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
	_window(Vector3(3.3, y, z), Vector2(2.2, 1.4))                          # x 2.2..4.4, slide under
	_box(Vector3(3.3, y + 2.2, z), Vector3(2.2, 1.6, 0.3), Kind.NEUTRAL)    # over the window
	_box(Vector3(5.2, y + 1.5, z), Vector3(1.6, 3.0, 0.3), Kind.NEUTRAL)    # x 4.4..6
	_label("Kick the door (F) or slide through the window (Ctrl)", Vector3(0, y + 3.6, z + 0.4), 0.8)
	_label("Wallrun the wall across the gap", Vector3(0, y + 3, -68), 0.8)


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
	# Up top: a low window to slide through in a short wall, and the edge.
	var z := -114.0
	var y := 13.0
	_box(Vector3(-3.4, y + 1.5, z), Vector3(5.2, 3.0, 0.3), Kind.NEUTRAL)   # x -6..-0.8
	_window(Vector3(0.3, y, z), Vector2(2.2, 1.4))                          # x -0.8..1.4, slide under
	_box(Vector3(0.3, y + 2.2, z), Vector3(2.2, 1.6, 0.3), Kind.NEUTRAL)
	_box(Vector3(3.7, y + 1.5, z), Vector3(4.6, 3.0, 0.3), Kind.NEUTRAL)    # x 1.4..6
	_label("Slide through it (Ctrl)", Vector3(0.3, y + 3.6, z + 0.4), 0.8)
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


## R6-R7: a long flat sprint to build speed (hurdles and a slide bar keep the
## combo going), a gap, then a field of rooftop plant either side of a clear
## lane, ending at a climb face.
func _section_sprint() -> void:
	_spawn_at(Vector3(0, 4, -181), "5 · ROOFTOP SPRINT")
	_label("Long straight: build your speed", Vector3(0, 7.5, -186), 0.9)
	for z: float in [-200.0, -215.0]:
		_box(Vector3(0, 4.5, z), Vector3(12, 1.0, 0.4), Kind.PARKOUR)
	_box(Vector3(0, 5.35, -228), Vector3(12, 0.5, 0.6), Kind.PARKOUR)
	for x: float in [-5.8, 5.8]:
		_box(Vector3(x, 4.55, -228), Vector3(0.4, 1.1, 0.6), Kind.NEUTRAL)
	_label("Jump the gap", Vector3(0, 7, -236), 0.8)
	# R7: plant either side of the lane, a vault row, the climb face.
	for i in 5:
		var z := -252.0 - i * 9.0
		var side := -1.0 if i % 2 == 0 else 1.0
		_prop("ac_unit", Vector3(side * 4.5, 4, z), PI * 0.5 * side)
		_prop("vent_stack", Vector3(-side * 5.5, 4, z - 3.0), 0.0)
	_box(Vector3(0, 4.5, -262), Vector3(14, 1.0, 0.4), Kind.PARKOUR)
	_box(Vector3(0, 5.5, -299.85), Vector3(14, 3.0, 0.3), Kind.PARKOUR)
	_label("Climb", Vector3(0, 8.8, -296), 0.8)


## R8: a window wall, then the first corner: a wide roof that turns left,
## with a banked curve round its outside to carve at speed.
func _section_first_corner() -> void:
	_spawn_at(Vector3(0, 7, -303), "6 · FIRST CORNER")
	var z := -315.0
	var y := 7.0
	_box(Vector3(-5.4, y + 1.5, z), Vector3(9.2, 3.0, 0.3), Kind.NEUTRAL)   # x -10..-0.8
	_window(Vector3(0.3, y, z), Vector2(2.2, 1.4))
	_box(Vector3(0.3, y + 2.2, z), Vector3(2.2, 1.6, 0.3), Kind.NEUTRAL)
	_box(Vector3(5.7, y + 1.5, z), Vector3(8.6, 3.0, 0.3), Kind.NEUTRAL)    # x 1.4..10
	_label("Slide through", Vector3(0.3, y + 3.6, z + 0.4), 0.8)
	# A long run-up, then the corner. Keep wide: the banked curve is
	# round the outside, the racing line inside it.
	_box(Vector3(0, 7.5, -330), Vector3(20, 1.0, 0.4), Kind.PARKOUR)
	_label("Corner: turn left. Ride the bank round the outside to keep your speed", Vector3(0, 10.5, -338), 0.8)
	_surface(MapPieces.banked_turn(TURN1_CENTER, TURN1_RADIUS + 5.0, 0.0, PI * 0.5, 9, 3.0, 55.0, 1.0))
	# Rooftop plant on the inside of the corner.
	_prop("water_tank", Vector3(-8.0, 7, -302.5), 0.0)
	_prop("ac_unit", Vector3(-8.2, 7, -340), PI * 0.5)
	_prop("vent_stack", Vector3(8.6, 7, -304), 0.0)


## Leg 2 (toward -X; this frame's +X is the runner's right, toward -Z). The
## roof splits: on the right a slab up to a high narrow roof with a wallrun
## gap; on the left two hurdles, a drop to the low roofs, a pipe to slide
## under, vaults and a climb back up. They meet at the second corner.
func _section_split() -> void:
	# The corner roof's own leg, full width, then the two lines.
	_roof(7.0, -10.0, -60.0, -17.0, 17.0)
	_fspawn(Vector3(0, 7, -14), "7 · HIGH LINE OR LOW LINE")
	_fbox(Vector3(0, 7.5, -26), Vector3(14, 1.0, 0.4), Kind.PARKOUR)
	_flabel("Split: high line on the right, low line on the left", Vector3(0, 10.3, -32), 0.9)

	# High line: a fallen slab up 3 m, a narrow roof, a wallrun gap.
	_framp(Vector3(8, 10, -60), Vector3(8, 7, -44), 10.0, Kind.NEUTRAL).set_meta("look", "RUST")
	_roof(10.0, -60.0, -100.0, 2.0, 14.0)
	_fbox(Vector3(8, 10.45, -76), Vector3(12, 0.9, 0.4), Kind.PARKOUR)
	_fbox(Vector3(14.5, 12.5, -106.0), Vector3(1.0, 9.0, 18.0), Kind.WALLRUN)
	_fbox(Vector3(2.4, 10.4, -94.0), Vector3(0.4, 0.8, 8.0), Kind.NEUTRAL)
	_flabel("High line: wallrun the right wall", Vector3(8, 13.5, -90), 0.8)
	_roof(10.0, -112.0, -160.0, 2.0, 14.0)
	_fbox(Vector3(8, 11.35, -128), Vector3(12, 0.5, 0.6), Kind.PARKOUR)
	for x: float in [2.2, 13.8]:
		_fbox(Vector3(x, 10.55, -128), Vector3(0.4, 1.1, 0.6), Kind.NEUTRAL)
	_flabel("Drop to the corner", Vector3(8, 13, -152), 0.8)

	# Low line: hurdles, a gap down to the low roofs, plant, a climb.
	_roof(7.0, -60.0, -90.0, -17.0, -3.0)
	for z: float in [-66.0, -78.0]:
		_fbox(Vector3(-10, 7.5, z), Vector3(14, 1.0, 0.4), Kind.PARKOUR)
	_flabel("Low line: drop and roll", Vector3(-10, 10, -86), 0.8)
	_roof(4.0, -96.0, -160.0, -17.0, -3.0)
	# Room to roll out of the landing before the pipe.
	_fbox(Vector3(-10, 5.35, -118), Vector3(14, 0.5, 0.6), Kind.PARKOUR)
	for x: float in [-16.8, -3.2]:
		_fbox(Vector3(x, 4.55, -118), Vector3(0.4, 1.1, 0.6), Kind.NEUTRAL)
	for z: float in [-132.0, -144.0]:
		_fbox(Vector3(-10, 4.5, z), Vector3(14, 1.0, 0.4), Kind.PARKOUR)
	_fprop("ac_unit", Vector3(-15.5, 4.0, -153), PI * 0.5)
	_fprop("vent_stack", Vector3(-4.6, 4.0, -125), 0.0)
	# The second corner's roof is 3 m up: its face is the climb.
	_fbox(Vector3(-10, 5.5, -159.85), Vector3(14, 3.0, 0.3), Kind.PARKOUR)
	_flabel("Climb", Vector3(-10, 8.6, -154), 0.8)

	# The second corner: a big roof, the bank round its outside (left).
	_xf = Transform3D.IDENTITY
	_roof(7.0, -350.0, -410.0, -216.0, -160.0)
	_surface(MapPieces.banked_turn(TURN2_CENTER, TURN2_RADIUS + 5.0, PI * 0.5, 0.0, 9, 3.0, 55.0, 1.0))
	_label("Corner: turn right", Vector3(-168, 10.5, -372), 0.8)
	_prop("water_tank", Vector3(-213, 7, -406), 0.0)
	_prop("satellite_dish", Vector3(-163, 7, -406), PI)
	_xf = LEG3


## Leg 3 (toward -Z again). Hurdles, then three roofs that step up 1.5 m
## each: mantle them without breaking stride.
func _section_step_up() -> void:
	_fspawn(Vector3(0, 7, -403), "8 · STEP UP")
	_roof(7.0, -410.0, -470.0, -8.0, 8.0)
	for z: float in [-425.0, -440.0]:
		_fbox(Vector3(0, 7.5, z), Vector3(16, 1.0, 0.4), Kind.PARKOUR)
	_flabel("Step up: jump into each ledge to mantle it", Vector3(0, 10.5, -455), 0.8)
	_roof(8.5, -470.0, -490.0, -8.0, 8.0)
	_fbox(Vector3(0, 7.75, -469.85), Vector3(16, 1.5, 0.3), Kind.PARKOUR)
	_roof(10.0, -490.0, -560.0, -10.0, 10.0)
	_fbox(Vector3(0, 9.25, -489.85), Vector3(16, 1.5, 0.3), Kind.PARKOUR)


## The fork over a 12 m gap: a wallrun wall on the left, or a girder on the
## right to keep straight on.
func _section_fork() -> void:
	_fspawn(Vector3(0, 10, -498), "9 · THE FORK")
	_fbox(Vector3(0, 10.5, -512), Vector3(20, 1.0, 0.4), Kind.PARKOUR)
	_fprop("ac_unit", Vector3(8.5, 10, -530), PI * 0.5)
	_fprop("vent_stack", Vector3(-8.8, 10, -536), 0.0)
	_flabel("Wallrun the left wall, or take the girder on the right", Vector3(0, 13.2, -546), 0.8)
	_fbox(Vector3(-10.5, 12.5, -566.0), Vector3(1.0, 9.0, 18.0), Kind.WALLRUN)
	_fbox(Vector3(5.0, 9.75, -566.0), Vector3(1.2, 0.5, 13.0), Kind.NEUTRAL).set_meta("look", "RUST")
	_roof(10.0, -572.0, -616.0, -10.0, 10.0)


## R16-R17: hurdles, a slide ramp down 6 m, a wide roof with an optional loop
## on the right and hurdles, and a last gap with a kick-off pillar.
func _section_slide_down() -> void:
	_fspawn(Vector3(0, 10, -578), "10 · SLIDE DOWN")
	_fbox(Vector3(0, 10.5, -592), Vector3(20, 1.0, 0.4), Kind.PARKOUR)
	_framp(Vector3(0, 10, -616), Vector3(0, 4, -640), 8.0, Kind.SLIDE)
	_flabel("Slide down (Ctrl) to keep your speed", Vector3(0, 13, -608), 0.8)
	_roof(4.0, -640.0, -700.0, -10.0, 14.0)
	# The loop comes out 5.5 m to its right, still on the roof.
	_fsurface(SurfaceShapes.loop(Vector3(4.0, 4.0, -666), 4.5, 3.5, 5.5))
	_flabel("LOOP (optional)", Vector3(4.0, 14.5, -666), 1.0)
	for hz: float in [-656.0, -674.0, -688.0]:
		_fbox(Vector3(-4.0, 4.45, hz), Vector3(9.0, 0.9, 0.4), Kind.PARKOUR)
	_fbox(Vector3(0, 3.5, -703), Vector3(1.2, 7.0, 1.2), Kind.NEUTRAL)
	_flabel("Last gap", Vector3(0, 7, -694), 0.8)


func _section_finish() -> void:
	_roof(4.0, -706.0, -790.0, -8.0, 8.0)
	_floor_mark(_xf * Vector3(0, 4, FINISH_Z), Vector2(16, 0.8), Color(1.0, 0.85, 0.2))
	_flabel("FINISH", Vector3(0, 8.2, FINISH_Z), 1.8)
	# Shooting gallery past the finish line for a victory lap.
	_target(_xf * Vector3(-3, 4, -752), ShootingTarget.Motion.STATIC)
	_target(_xf * Vector3(3, 4, -752), ShootingTarget.Motion.STRAFE, 2.5, 3.0)


## Tall blocks all round the course so it reads as a city, not a void. They
## stand on a jittered grid and keep clear of every roof.
func _skyline() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var half := STREET_SIZE * 0.5 - Vector2(8, 8)
	var x := STREET_CENTER.x - half.x
	while x < STREET_CENTER.x + half.x:
		var z := STREET_CENTER.z - half.y
		while z < STREET_CENTER.z + half.y:
			var c := Vector2(x + rng.randf_range(-3, 3), z + rng.randf_range(-3, 3))
			var size := Vector2(rng.randf_range(8.0, 14.0), rng.randf_range(8.0, 12.0))
			var h := rng.randf_range(14.0, 36.0)
			var r := Rect2(c - size * 0.5, size)
			var clear := true
			for f in _footprints:
				if f.grow(9.0).intersects(r):
					clear = false
					break
			# Keep the street past the exit open for a mission's pieces.
			if open_exit and c.y < EXIT.origin.z + 20.0 and absf(c.x - EXIT.origin.x) < 40.0:
				clear = false
			if clear:
				_box(Vector3(c.x, h * 0.5, c.y), Vector3(size.x, h, size.y), Kind.NEUTRAL).set_meta("look", "FACADE")
			z += 22.0
		x += 22.0


# ---------------------------------------------------------------- helpers

## A building whose roof is part of the course, in the current frame: top
## height, z start and end, x from and to. Its sides look like a ruined
## facade (the art look reads the "look" meta; gameplay only sees NEUTRAL).
func _roof(top: float, z0: float, z1: float, x0: float, x1: float) -> void:
	var b := _fbox(Vector3((x0 + x1) * 0.5, top * 0.5, (z0 + z1) * 0.5), Vector3(x1 - x0, top, absf(z1 - z0)), Kind.NEUTRAL)
	b.set_meta("look", "FACADE")
	var a := _xf * Vector3(x0, 0, z0)
	var c := _xf * Vector3(x1, 0, z1)
	_footprints.append(Rect2(Vector2(minf(a.x, c.x), minf(a.z, c.z)), Vector2(absf(c.x - a.x), absf(c.z - a.z))))


## A box in the current frame.
func _fbox(center: Vector3, size: Vector3, kind: Kind) -> StaticBody3D:
	return _box_basis(_xf * center, size, _xf.basis, kind)


## A ramp in the current frame (see SandboxBuilder._ramp).
func _framp(top: Vector3, bottom: Vector3, width: float, kind: Kind) -> StaticBody3D:
	var run := bottom.z - top.z
	var rise := top.y - bottom.y
	var length := sqrt(run * run + rise * rise)
	var angle := atan2(rise, absf(run))
	var basis := Basis.from_euler(Vector3(-angle if run < 0.0 else angle, 0, 0))
	var mid := (top + bottom) * 0.5
	return _box_basis(_xf * (mid - basis.y * 0.5), Vector3(width, 1, length), _xf.basis * basis, kind)


## Runnable surface pieces authored in the current frame.
func _fsurface(pieces: Array[Dictionary]) -> void:
	var out: Array[Dictionary] = []
	for p in pieces:
		out.append({
			"transform": _xf * (p.transform as Transform3D),
			"size": p.size,
			"flow": _xf.basis * (p.flow as Vector3),
			"face": _xf.basis * (p.face as Vector3),
		})
	_surface(out)


func _flabel(text: String, pos: Vector3, size := 1.0) -> void:
	_label(text, _xf * pos, size)


func _fprop(prop_name: String, at: Vector3, yaw: float) -> void:
	PropKit.place(_root, prop_name, _xf * Transform3D(Basis(Vector3.UP, yaw), at))


## A spawn facing the current frame's way.
func _fspawn(pos: Vector3, title: String) -> void:
	spawns.append(Transform3D(_xf.basis, _xf * pos))
	zone_names.append(title)


## Start and finish lines: a colored stripe across the roof.
func _line(z: float, y: float, color: Color) -> void:
	_floor_mark(Vector3(0, y, z), Vector2(12, 0.8), color)


## A prop from the shared kit (art/props), loaded by path.
func _prop(prop_name: String, at: Vector3, yaw: float) -> void:
	PropKit.place(_root, prop_name, Transform3D(Basis(Vector3.UP, yaw), at))


func _spawn_at(pos: Vector3, title: String) -> void:
	spawns.append(Transform3D(Basis.IDENTITY, pos))
	zone_names.append(title)
