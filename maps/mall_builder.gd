@tool
class_name MallBuilder
extends SandboxBuilder
## "Ruined Mall": a two-floor shopping mall gone to ruin. Free roam, no set
## route, built for flow and for fights (raiders and mutants will move in
## later; targets stand in for them for now).
##
##   north (z -90)  ┌─────────── FOOD COURT ───────────┐  roof caved in,
##                  │ kiosks, tables   debris ramp ▲   │  ramp up to the
##                  ├──── back mezzanine (upper) ──────┤  mezzanine
##     west shops   │ ║  hanging billboards (zigzag) ║ │   east shops
##     (2 floors)   │ ║════════ bridge ══════════════║ │   (2 floors),
##                  │ ║      dry fountain    ↗       ║ │   collapsed walkway
##                  │ ║ ↗ escalators      ↙          ║ │   and a wallrun wall
##                  ├──── front mezzanine (upper) ─────┤
##   south (z 10)   └──────────── entrance ────────────┘
##                       parking lot, wrecks
##
## The middle is a two-storey atrium (x -11..11, z -10..-70) under a broken
## skylight. Upper walkways run along both sides and round the front and
## back; escalators, the bridge and the debris ramp tie the floors together.
## Sizes come from the movement numbers: 1 m blocks vault, 1.5 m mantle, 3 m
## climbs, 1.1 m gaps slide.

const PropKit := preload("res://art/props/prop_kit.gd")

const HALF_W := 30.0  # inside, wall to wall
const FRONT_Z := 10.0
const BACK_Z := -90.0
const UPPER_Y := 6.0  # top of the upper floor
const ROOF_Y := 12.5  # underside of the roof
const ATRIUM_X := 11.0
const ATRIUM_FRONT := -10.0
const ATRIUM_BACK := -70.0
const MEZZ_BACK := -74.0  # back mezzanine edge, over the food court
const SHOP_X := 20.0  # shop fronts
const SHOP_LEN := 12.0
const ESCALATOR_X := 6.0
const ESCALATOR_W := 2.4
## Everything outside: the lot, the ground round the building and the ring of
## ruined buildings that closes the map.
const GROUND_CENTER := Vector3(0, 0, -195)
const GROUND_SIZE := Vector2(120, 530)
## The east walkway's collapsed stretch (z range).
const HOLE := Vector2(-38.0, -46.0)

const SHOP_NAMES := [
	"SCRAPPY'S", "MEGA BUY", "ECHO BOUTIQUE", "FRESH MART", "SPORT ZONE",
	"PAGES", "TOYLAND", "ARCADE", "PHARMACY", "KICKS", "TECH HUT", "DINER",
]
const SIGN_COLORS := [
	Color(0.62, 0.22, 0.20), Color(0.18, 0.36, 0.56), Color(0.70, 0.52, 0.16),
	Color(0.22, 0.46, 0.34), Color(0.50, 0.26, 0.50), Color(0.66, 0.36, 0.18),
]
## The north wing: a long two-floor concourse (central void, walkways and
## shops both sides), then the department store, then the loading dock and
## the service road out.
const WING_HALF := 24.0
const WING_FRONT := -90.0
const VOID_X := 7.0  # the concourse void, x -7..7
const WING_SHOP_X := 14.0  # wing shop fronts
const STORE_Z := -340.0  # concourse ends, store begins
const STORE_DECK := Vector2(-340.0, -385.0)  # store upper floor (z range)
const DOCK_Z := -400.0
const DOCK_BACK := -430.0
const ROAD_END := -460.0
## Upper walkway holes in the wing (z ranges), under wallrun hoardings.
const WING_HOLES := [[-1.0, Vector2(-181.0, -193.0)], [1.0, Vector2(-205.0, -217.0)]]
const BRIDGES := [-150.0, -230.0, -310.0]

## Where a run through the mall starts and ends (spawns[0] is ENTRY). The
## campaign reads these by path; past EXIT the road is left open for it.
const ENTRY := Transform3D(Basis.IDENTITY, Vector3(0, 0, 26))
const EXIT := Transform3D(Basis.IDENTITY, Vector3(0, 0, -438))
## The department store on its own: in on the ground floor, out on its roof.
const ANCHOR_ENTRY := Transform3D(Basis.IDENTITY, Vector3(0, 0, -345))
const ANCHOR_EXIT := Transform3D(Basis.IDENTITY, Vector3(0, ROOF_Y + 0.5, -395))

## Leave the far (-Z) edge open so a mission can carry on down the road.
## Set before the builder enters the tree.
@export var open_exit := false

## The front is painted render, the sides and back bare concrete blocks.
const FRONT_PAINT := Color(0.72, 0.64, 0.52)
const WARM := Color(1.0, 0.72, 0.42)
const COOL := Color(0.72, 0.86, 1.0)


func build() -> void:
	if _root != null:
		_root.queue_free()
	_root = Node3D.new()
	_root.name = "Generated"
	add_child(_root)
	spawns.clear()
	zone_names.clear()

	_spawn(Vector3(0, 0, 26), "1 · ENTRANCE")
	_spawn(Vector3(0, 0, -12), "2 · ATRIUM")
	_spawn(Vector3(-16, UPPER_Y, -14), "3 · UPPER FLOOR")
	_spawn(Vector3(0, 0, -45), "4 · BILLBOARDS")
	_spawn(Vector3(0, 0, -72), "5 · FOOD COURT")
	_spawn(Vector3(16, UPPER_Y, -14), "6 · COLLAPSE")
	_spawn(Vector3(0, 0, -96), "7 · CONCOURSE")
	_spawn(ANCHOR_ENTRY.origin, "8 · DEPARTMENT STORE")
	_spawn(Vector3(0, 0, -405), "9 · LOADING DOCK")

	_parking_lot()
	_shell()
	_upper_floor()
	_escalators()
	_atrium()
	_corridors()
	for side: float in [-1.0, 1.0]:
		for i in 5:
			var upper_east_gap := side > 0.0 and (i == 1 or i == 2 or i == 3)
			_shop(side, 0.0, ATRIUM_FRONT - i * SHOP_LEN, i + (0 if side < 0.0 else 5), true, SHOP_X, HALF_W, i == 4)
			if not upper_east_gap:
				_shop(side, UPPER_Y, ATRIUM_FRONT - i * SHOP_LEN, i + (2 if side < 0.0 else 7), false, SHOP_X, HALF_W, i == 4)
	_collapse()
	_food_court()
	_wing()
	_store()
	_dock()
	_roof()
	_targets()


# ---------------------------------------------------------------- outside

func _parking_lot() -> void:
	var lot := _part(Vector3(0, -0.5, 30), Vector3(80, 1, 40), Kind.FLOOR)
	lot.set_meta("look", "FLOOR")
	_label("Glass breaks if you hit it fast", Vector3(0, 3.0, 17), 0.8)
	# Faded bay lines.
	for x in range(-36, 37, 4):
		if absi(x) > 4:
			_floor_mark(Vector3(x, 0, 38), Vector2(0.15, 5), Color(0.78, 0.74, 0.62))
	# Wrecks to mantle and run over, and the junk round the doors.
	var wrecks := [
		[Vector3(-9, 0, 30), 0.3], [Vector3(-16, 0, 22), -0.2], [Vector3(10, 0, 33), 1.4],
		[Vector3(17, 0, 21), 0.1], [Vector3(-24, 0, 36), 1.6], [Vector3(26, 0, 40), -0.4],
	]
	for w: Array in wrecks:
		_prop("car_wreck", w[0], w[1])
	_prop("dumpster", Vector3(-12, 0, 11.5), PI)
	_prop("dumpster", Vector3(-15, 0, 12.2), PI + 0.25)
	_prop("tire_stack", Vector3(13, 0, 12), 0.0)
	_prop("tire_stack", Vector3(13.8, 0, 12.6), 0.6)
	for x: float in [-6.5, 6.5]:
		_prop("barricade_jersey", Vector3(x, 0, 15), PI * 0.5 * signf(x) * 0.3)
	_prop("loudspeaker_pole", Vector3(8, 0, 13), PI)
	# Ground around the building, low concrete kerbs round the lot, and the
	# ruined town all round so there is no running off the world.
	_part(Vector3(0, -0.52, GROUND_CENTER.z), Vector3(GROUND_SIZE.x, 1, GROUND_SIZE.y), Kind.FLOOR)
	# Tall enough that nothing reachable (the roofs are 13 m) clears it.
	for piece in MapPieces.perimeter(GROUND_CENTER, GROUND_SIZE, 26.0, 36.0, 16.0, 10.0, open_exit):
		var t: Transform3D = piece.transform
		_part_basis(t.origin, piece.size, t.basis, Kind.NEUTRAL, "FACADE")
	for x: float in [-40.0, 40.0]:
		_part(Vector3(x, 0.5, -25), Vector3(0.6, 1, 150), Kind.PARKOUR, "NEUTRAL")
	for z: float in [-100.0, 50.0]:
		_part(Vector3(0, 0.5, z), Vector3(80, 1, 0.6), Kind.PARKOUR, "NEUTRAL")
	# Dead lamp posts.
	for p: Vector3 in [Vector3(-14, 0, 40), Vector3(14, 0, 40), Vector3(-30, 0, 18), Vector3(30, 0, 18)]:
		_part(p + Vector3(0, 3.5, 0), Vector3(0.3, 7, 0.3), Kind.NEUTRAL, "RUST")
		_part(p + Vector3(0, 7.0, 0.6), Vector3(0.4, 0.2, 1.4), Kind.NEUTRAL, "RUST")


# ---------------------------------------------------------------- building

## Floor, outer walls (concrete inside, ruined facade outside) and the
## entrance with its glass doors.
func _shell() -> void:
	var mall_floor := _part(Vector3(0, -0.5, (FRONT_Z + BACK_Z) * 0.5), Vector3(HALF_W * 2, 1, FRONT_Z - BACK_Z), Kind.FLOOR, "TILE")
	mall_floor.name = "MallFloor"
	var h := ROOF_Y + 0.5
	var depth := FRONT_Z - BACK_Z
	var mid_z := (FRONT_Z + BACK_Z) * 0.5
	for side: float in [-1.0, 1.0]:
		_part(Vector3(side * (HALF_W + 0.35), h * 0.5, mid_z), Vector3(0.7, h, depth + 1.4), Kind.NEUTRAL)
		_part(Vector3(side * (HALF_W + 0.85), h * 0.5, mid_z), Vector3(0.3, h, depth + 2.0), Kind.NEUTRAL, "FACADE")
	# North wall, open in the middle into the north wing.
	for side: float in [-1.0, 1.0]:
		_part(Vector3(side * (12.0 + HALF_W + 0.7) * 0.5, h * 0.5, BACK_Z - 0.35), Vector3(HALF_W + 0.7 - 12.0, h, 0.7), Kind.NEUTRAL)
		_part(Vector3(side * (WING_HALF + 0.7 + HALF_W + 1.0) * 0.5, h * 0.5, BACK_Z - 0.85), Vector3(HALF_W + 1.0 - WING_HALF - 0.7, h, 0.3), Kind.NEUTRAL, "FACADE")
	# South wall with the entrance (12 m wide, 5 m tall).
	for side: float in [-1.0, 1.0]:
		var cx := side * (6.0 + (HALF_W + 1.0 - 6.0) * 0.5)
		var w := HALF_W + 1.0 - 6.0
		_part(Vector3(cx, h * 0.5, FRONT_Z - 0.35), Vector3(w, h, 0.7), Kind.NEUTRAL)
		_part(Vector3(cx, h * 0.5, FRONT_Z + 0.15), Vector3(w, h, 0.3), Kind.NEUTRAL, "PARKOUR", FRONT_PAINT)
	_part(Vector3(0, 5 + (h - 5) * 0.5, FRONT_Z - 0.2), Vector3(12, h - 5, 1.0), Kind.NEUTRAL, "PARKOUR", FRONT_PAINT)
	# Door frame: glass in the outer bays, the middle ones long gone.
	_part(Vector3(0, 4.2, FRONT_Z - 0.2), Vector3(12, 1.6, 0.4), Kind.NEUTRAL, "RUST")
	for x: float in [-3.0, 3.0]:
		_part(Vector3(x, 1.7, FRONT_Z - 0.2), Vector3(0.25, 3.4, 0.4), Kind.NEUTRAL, "RUST")
	for x: float in [-4.5, 4.5]:
		_glass(Vector3(x, 0, FRONT_Z - 0.2), Vector2(2.75, 3.4), 0.0)
	_sign_band(Vector3(0, 7.5, FRONT_Z + 0.45), Vector3(16, 2.2, 0.3), 0.0, "RIVERSIDE MALL", Color(0.58, 0.22, 0.2), 2.6)


## Upper floor slabs (top at UPPER_Y): front and back mezzanines and the side
## walkways, leaving the atrium open and the east walkway's collapsed hole.
func _upper_floor() -> void:
	var y := UPPER_Y - 0.25
	var walk_w := HALF_W - ATRIUM_X
	var walk_cx := ATRIUM_X + walk_w * 0.5
	_slab(Vector3(0, y, -7), Vector3(HALF_W * 2, 0.5, 6))
	_slab(Vector3(0, y, (ATRIUM_BACK + MEZZ_BACK) * 0.5), Vector3(HALF_W * 2, 0.5, ATRIUM_BACK - MEZZ_BACK))
	_slab(Vector3(-walk_cx, y, -40), Vector3(walk_w, 0.5, 60))
	# East: walkway in two pieces either side of the hole; the strip behind
	# the wallrun wall stays (it is the shops' ceiling).
	var a := ATRIUM_FRONT - HOLE.x
	_slab(Vector3(walk_cx, y, (ATRIUM_FRONT + HOLE.x) * 0.5), Vector3(walk_w, 0.5, a))
	_slab(Vector3(walk_cx, y, (HOLE.y + ATRIUM_BACK) * 0.5), Vector3(walk_w, 0.5, HOLE.y - ATRIUM_BACK))
	_slab(Vector3((SHOP_X + HALF_W) * 0.5, y, (HOLE.x + HOLE.y) * 0.5), Vector3(HALF_W - SHOP_X, 0.5, HOLE.x - HOLE.y))
	# Bridge across the atrium.
	_slab(Vector3(0, y, -50), Vector3(ATRIUM_X * 2, 0.5, 4))
	# Railings (1 m: vault them, or wallrun their faces... briefly).
	var ry := UPPER_Y + 0.5
	for seg: Vector2 in [Vector2(-10, -30), Vector2(-34, -48), Vector2(-52, -70)]:
		_rail_z(-ATRIUM_X - 0.1, seg, ry)
	for seg: Vector2 in [Vector2(-16, HOLE.x), Vector2(-52, -70)]:
		_rail_z(ATRIUM_X + 0.1, seg, ry)
	_rail_x(ATRIUM_FRONT + 0.1, Vector2(-ATRIUM_X, ESCALATOR_X - ESCALATOR_W * 0.5), ry)
	_rail_x(ATRIUM_BACK - 0.1, Vector2(-ATRIUM_X, ATRIUM_X), ry)
	# Gap at x -3..3 for the catwalk over the food court to the north wing.
	_rail_x(MEZZ_BACK + 0.1, Vector2(-HALF_W, -3.0), ry)
	_rail_x(MEZZ_BACK + 0.1, Vector2(3.0, 11.5), ry)
	_rail_x(MEZZ_BACK + 0.1, Vector2(16.5, HALF_W), ry)
	for z: float in [-48.1, -51.9]:
		_rail_x(z, Vector2(-ATRIUM_X, ATRIUM_X), ry)
	# Columns at the atrium edge, floor to roof.
	for side: float in [-1.0, 1.0]:
		for z: float in [-14.0, -26.0, -40.0, -58.0, -68.0]:
			_part(Vector3(side * (ATRIUM_X + 1.0), ROOF_Y * 0.5, z), Vector3(1, ROOF_Y, 1), Kind.NEUTRAL)
	# Ceiling lights over the walkways (a few still on).
	for z: float in [-20.0, -44.0, -64.0]:
		_lamp(Vector3(-15.5, ROOF_Y - 0.8, z), COOL, 0.9)
	_lamp(Vector3(15.5, ROOF_Y - 0.8, -24.0), COOL, 0.9)


## Two escalators in the atrium, opposite ways: west runs up toward the back
## onto a landing, east runs up toward the front onto the front mezzanine.
func _escalators() -> void:
	var x := ESCALATOR_X
	var hw := ESCALATOR_W * 0.5
	# West: bottom z -16, top z -30, landing behind it joins the walkway.
	_escalator(Vector3(-x, UPPER_Y, -30), Vector3(-x, 0, -16))
	_slab(Vector3(-(ATRIUM_X + x - hw) * 0.5, UPPER_Y - 0.25, -32), Vector3(ATRIUM_X - x + hw, 0.5, 4))
	_rail_x(-33.9, Vector2(-ATRIUM_X, -x + hw), UPPER_Y + 0.5)
	_rail_z(-x + hw - 0.1, Vector2(-30, -34), UPPER_Y + 0.5)
	_rail_x(-30.1, Vector2(-ATRIUM_X, -x - hw), UPPER_Y + 0.5)
	# East: bottom z -30, top z -16, landing up to the front mezzanine.
	_escalator(Vector3(x, UPPER_Y, -16), Vector3(x, 0, -30))
	_slab(Vector3((ATRIUM_X + x - hw) * 0.5, UPPER_Y - 0.25, -13), Vector3(ATRIUM_X - x + hw, 0.5, 6))
	_rail_z(x - hw + 0.1, Vector2(-10, -16), UPPER_Y + 0.5)
	_rail_x(-15.9, Vector2(x + hw, ATRIUM_X), UPPER_Y + 0.5)
	_label("Run up the escalators", Vector3(-x, 2.8, -14), 0.8)


func _escalator(top: Vector3, bottom: Vector3) -> void:
	_ramp(top, bottom, ESCALATOR_W, Kind.SLIDE)
	_last().set_meta("look", "RUST")
	var hw := ESCALATOR_W * 0.5 + 0.12
	for s: float in [-1.0, 1.0]:
		var off := Vector3(s * hw, 0.5, 0)
		_beam(bottom + off, top + off, Vector2(0.18, 1.0), Kind.NEUTRAL, "RUST")
	# Truss under the top end.
	var under := top.lerp(bottom, 0.2)
	_part(Vector3(under.x, (under.y - 1.0) * 0.5, under.z), Vector3(1.2, under.y - 1.0, 1.2), Kind.NEUTRAL, "RUST")


## The atrium floor: a dry fountain, benches and planters, and three
## billboards hanging from the roof to wallrun zigzag between.
func _atrium() -> void:
	# Fountain: 0.8 m basin walls (vault in, vault out), 1.5 m plinth.
	var f := Vector3(0, 0, -38)
	for s: float in [-1.0, 1.0]:
		_part(f + Vector3(s * 3.0, 0.4, 0), Vector3(0.4, 0.8, 6.4), Kind.PARKOUR, "NEUTRAL")
		_part(f + Vector3(0, 0.4, s * 3.0), Vector3(6.4, 0.8, 0.4), Kind.PARKOUR, "NEUTRAL")
	_part(f + Vector3(0, 0.75, 0), Vector3(1.6, 1.5, 1.6), Kind.PARKOUR)
	_part(f + Vector3(0, 2.25, 0), Vector3(0.5, 1.5, 0.5), Kind.NEUTRAL, "RUST")
	# Benches and planters.
	for s: float in [-1.0, 1.0]:
		_part(Vector3(s * 2.5, 0.25, -24), Vector3(0.8, 0.5, 3), Kind.PARKOUR, "RUST")
		_part(Vector3(s * 8.5, 0.5, -38), Vector3(2, 1, 6), Kind.PARKOUR, "NEUTRAL")
	# Billboards: blue, hung on cables from the roof. 9 m apart like the
	# combo park zigzag, alternating sides.
	var boards := [[1.0, -48.0], [-1.0, -57.0], [1.0, -66.0]]
	for b: Array in boards:
		var x: float = b[0] * 3.5
		var z: float = b[1]
		var board := _part(Vector3(x, 3.3, z), Vector3(0.3, 3.4, 8), Kind.WALLRUN)
		board.set_meta("look_color", SIGN_COLORS[1])
		board.set_meta("look", "SIGN")
		for dz: float in [-3.5, 3.5]:
			_cable(Vector3(x, 5.0, z + dz), Vector3(x, ROOF_Y, z + dz))
	_label("Wallrun the billboards, side to side", Vector3(0, 3.6, -42), 0.8)


## Ground-floor corridors under the walkways: crates to vault, a fallen sign
## to slide under, overhead lights.
func _corridors() -> void:
	var cx := (ATRIUM_X + SHOP_X) * 0.5 + 0.5
	for s: float in [-1.0, 1.0]:
		for z: float in [-22.0, -58.0]:
			_prop("crate_wood", Vector3(s * cx, 0, z), 0.2 * s)
			_prop("crate_wood", Vector3(s * cx, 0, z - 1.1), -0.1 * s)
		_prop("barrel_rust", Vector3(s * (cx + 2.5), 0, -27), 0.0)
		_prop("barrel_rust", Vector3(s * (cx + 2.9), 0, -27.6), 1.0)
		# Fallen sign resting on rubble: slide under (1.1 m clear).
		_part(Vector3(s * cx, 1.35, -34), Vector3(7, 0.5, 0.8), Kind.PARKOUR, "SIGN", SIGN_COLORS[4])
		_part(Vector3(s * (cx - 3.4), 0.55, -34), Vector3(0.6, 1.1, 0.8), Kind.NEUTRAL)
		_part(Vector3(s * (cx + 3.4), 0.55, -34), Vector3(0.6, 1.1, 0.8), Kind.NEUTRAL)
		for z: float in [-16.0, -46.0, -64.0]:
			_lamp(Vector3(s * cx, UPPER_Y - 1.3, z), COOL if z != -46.0 else WARM, 0.8)


## One 12 m shop front on side (-1 west, +1 east) from z0 back: pillars,
## glass bays (ground floor) or empty frames (upper), a doorway, a sign band
## and an interior with a counter and shelves. Some still have power.
func _shop(side: float, base: float, z0: float, index: int, glass: bool, front := SHOP_X, back := HALF_W, last := false) -> void:
	var x := side * front
	var h := (UPPER_Y - 0.5) if base == 0.0 else (ROOF_Y - UPPER_Y)
	var yaw := -side * PI * 0.5  # signs and glass face the corridor
	var wall := Vector3(x + side * 0.2, base, 0)
	var head := 3.2
	# Pillars at both ends.
	for dz: float in [-0.5, -SHOP_LEN + 0.5]:
		_part(wall + Vector3(0, h * 0.5, z0 + dz), Vector3(0.4, h, 1), Kind.NEUTRAL)
	# Header over the whole front.
	_part(wall + Vector3(0, head + (h - head) * 0.5, z0 - SHOP_LEN * 0.5), Vector3(0.4, h - head, SHOP_LEN - 2), Kind.NEUTRAL)
	# Glass bays either side of a 3 m doorway (z0-6..z0-9).
	for bay: Vector2 in [Vector2(-1, -6), Vector2(-9, -11)]:
		var span := bay.x - bay.y
		var mid := z0 + (bay.x + bay.y) * 0.5
		_part(wall + Vector3(0, 0.2, mid), Vector3(0.4, 0.4, span), Kind.NEUTRAL)
		if glass:
			_glass(Vector3(x + side * 0.2, base + 0.4, mid), Vector2(span, head - 0.4), yaw)
	var shop_name: String = SHOP_NAMES[index % SHOP_NAMES.size()]
	var color: Color = SIGN_COLORS[index % SIGN_COLORS.size()]
	_sign_band(Vector3(x - side * 0.15, base + 3.9, z0 - SHOP_LEN * 0.5), Vector3(0.3, 1.0, SHOP_LEN - 3), yaw, shop_name, color, 1.4)
	# Dividing wall at the front end of each shop (and the last one's back).
	var depth := back - front
	var wx := side * (front + depth * 0.5)
	_part(Vector3(wx, base + h * 0.5, z0 - 0.15), Vector3(depth, h, 0.3), Kind.NEUTRAL)
	if last:
		_part(Vector3(wx, base + h * 0.5, z0 - SHOP_LEN + 0.15), Vector3(depth, h, 0.3), Kind.NEUTRAL)
	# Inside: a counter to vault, shelves along the back to mantle.
	_part(Vector3(side * (front + 5), base + 0.5, z0 - 6), Vector3(1, 1, 5), Kind.PARKOUR, "RUST", color.darkened(0.3))
	_part(Vector3(side * (back - 0.6), base + 0.9, z0 - 6), Vector3(1.2, 1.8, 9), Kind.NEUTRAL, "RUST")
	if index % 3 != 1:
		_lamp(Vector3(side * (front + 5), base + h - 0.6, z0 - 6), WARM, 1.4 if index % 2 == 0 else 0.7)


## The east walkway's caved-in stretch: a blue wall to wallrun across the
## gap, and the broken slab hanging into it.
func _collapse() -> void:
	var wz := Vector2(ATRIUM_FRONT - SHOP_LEN, ATRIUM_FRONT - SHOP_LEN * 4)
	var span := wz.x - wz.y
	var wall := _part(Vector3(SHOP_X + 0.2, UPPER_Y + (ROOF_Y - UPPER_Y) * 0.5, (wz.x + wz.y) * 0.5), Vector3(0.4, ROOF_Y - UPPER_Y, span), Kind.WALLRUN)
	wall.set_meta("look", "WALLRUN")
	# Torn slab edges hanging down into the hole.
	var mid := (HOLE.x + HOLE.y) * 0.5
	var walk_cx := (ATRIUM_X + SHOP_X) * 0.5
	_part_basis(Vector3(walk_cx, UPPER_Y - 1.1, HOLE.x - 0.9), Vector3(SHOP_X - ATRIUM_X - 1, 0.4, 2.2), Basis(Vector3.RIGHT, -0.9), Kind.NEUTRAL)
	_part_basis(Vector3(walk_cx - 1, 1.4, mid), Vector3(5, 0.4, 3.2), Basis(Vector3.FORWARD, 0.5), Kind.NEUTRAL)
	_prop("debris_pile", Vector3(walk_cx + 2, 0, mid - 2), 0.4)
	_prop("debris_pile", Vector3(walk_cx - 3, 0, mid + 2.5), 2.1)
	_floor_mark(Vector3(walk_cx, UPPER_Y, HOLE.x + 1.0), Vector2(SHOP_X - ATRIUM_X, 0.3), Color(0.85, 0.65, 0.2))
	_label("Floor's gone: wallrun the blue wall", Vector3(walk_cx, UPPER_Y + 3.2, HOLE.x + 6), 0.8)


## Food court under the caved-in back roof: tables to vault, kiosks to mantle
## and run over, fallen roof chunks, and a debris ramp up to the mezzanine.
func _food_court() -> void:
	_ramp(Vector3(14, UPPER_Y, MEZZ_BACK), Vector3(14, 0, -87), 5.0, Kind.NEUTRAL)
	_label("Debris ramp to the upper floor", Vector3(14, 2.5, -84), 0.8)
	for x: float in [-24.0, -17.0, -10.0]:
		for z: float in [-78.0, -84.0]:
			_part(Vector3(x, 0.375, z), Vector3(1.6, 0.75, 1.6), Kind.PARKOUR, "RUST", SIGN_COLORS[3])
			for d: float in [-1.4, 1.4]:
				_part(Vector3(x + d, 0.22, z), Vector3(0.5, 0.45, 1.4), Kind.NEUTRAL, "RUST")
	# Kiosks: 2.6 m (jump and mantle), with counters to vault onto them.
	_part(Vector3(-20, 1.3, -88), Vector3(9, 2.6, 3), Kind.NEUTRAL)
	_part(Vector3(-20, 0.5, -86.1), Vector3(9, 1, 0.8), Kind.PARKOUR, "RUST", SIGN_COLORS[0])
	_sign_band(Vector3(-20, 2.1, -86.4), Vector3(8, 0.9, 0.2), 0.0, "NOODLE BAR", SIGN_COLORS[0], 1.3)
	_part(Vector3(25, 1.3, -82), Vector3(3, 2.6, 8), Kind.NEUTRAL)
	_part(Vector3(23.1, 0.5, -82), Vector3(0.8, 1, 8), Kind.PARKOUR, "RUST", SIGN_COLORS[2])
	_sign_band(Vector3(23.4, 2.1, -82), Vector3(0.2, 0.9, 7), -PI * 0.5, "BURGER BARN", SIGN_COLORS[2], 1.3)
	# Fallen roof: tilted slabs to run up, and rubble.
	_part_basis(Vector3(2, 1.2, -84), Vector3(7, 0.5, 6), Basis(Vector3.RIGHT, 0.35) * Basis(Vector3.UP, 0.3), Kind.NEUTRAL)
	_part_basis(Vector3(-6, 0.9, -80), Vector3(4, 0.5, 5), Basis(Vector3.FORWARD, -0.4), Kind.NEUTRAL)
	for p: Vector3 in [Vector3(6, 0, -79), Vector3(-2, 0, -88), Vector3(8.5, 0, -88.5)]:
		_prop("debris_pile", p, p.x * 0.3)
	# A raider camp on the back mezzanine, overlooking the court: cover to
	# fight from, a generator and radio still running.
	_prop("sandbag_wall", Vector3(-6, UPPER_Y, -73.3), 0.0)
	_prop("sandbag_wall", Vector3(-20, UPPER_Y, -73.3), 0.0)
	_prop("barricade_scrap", Vector3(22, UPPER_Y, -72), 0.0)
	_prop("generator", Vector3(-26, UPPER_Y, -72), PI * 0.5)
	_prop("radio_set", Vector3(-24, UPPER_Y, -71), 0.4)
	_prop("tarp_shelter", Vector3(-26, 0, -80), PI * 0.5)
	_prop("dumpster", Vector3(27.5, 0, -88), PI * 0.5)
	for s: float in [-1.0, 1.0]:
		_part(Vector3(s * 8, 0.5, -75.5), Vector3(2.5, 1, 1.5), Kind.PARKOUR, "NEUTRAL")
	_lamp(Vector3(-20, 4.5, -84), WARM, 1.2)
	_lamp(Vector3(24, 4.5, -82), WARM, 0.8)


## Roof slab with a long skylight over the atrium (the glass is gone, the
## frame isn't) and a caved-in hole over the food court.
func _roof() -> void:
	var y := ROOF_Y + 0.25
	var sky := Vector4(-9, 9, -14, -66)  # x0, x1, z0, z1
	_roof_slab(Vector3(0, y, (FRONT_Z + sky.z) * 0.5), Vector3(HALF_W * 2, 0.5, FRONT_Z - sky.z))
	for s: float in [-1.0, 1.0]:
		_roof_slab(Vector3(s * (HALF_W + 9) * 0.5, y, (sky.z - 76) * 0.5), Vector3(HALF_W - 9, 0.5, sky.z + 76))
	_roof_slab(Vector3(0, y, (sky.w - 76) * 0.5), Vector3(18, 0.5, sky.w + 76))
	_roof_slab(Vector3(-18, y, (-76 + BACK_Z) * 0.5), Vector3(24, 0.5, -76 - BACK_Z))
	_roof_slab(Vector3(27, y, (-76 + BACK_Z) * 0.5), Vector3(6, 0.5, -76 - BACK_Z))
	# Skylight frame.
	var z := sky.z - 4.0
	while z > sky.w:
		_part(Vector3(0, ROOF_Y + 0.2, z), Vector3(18, 0.4, 0.3), Kind.NEUTRAL, "RUST")
		z -= 6.0
	for x: float in [-3.0, 3.0]:
		_part(Vector3(x, ROOF_Y + 0.2, (sky.z + sky.w) * 0.5), Vector3(0.3, 0.4, sky.z - sky.w), Kind.NEUTRAL, "RUST")
	# Broken roof hanging into the food court.
	_part_basis(Vector3(-3, ROOF_Y - 1.5, -80), Vector3(5, 0.4, 7), Basis(Vector3.FORWARD, 0.7), Kind.NEUTRAL)
	_part_basis(Vector3(21, ROOF_Y - 1.2, -79), Vector3(5, 0.4, 5), Basis(Vector3.FORWARD, -0.6), Kind.NEUTRAL)


# ---------------------------------------------------------------- north wing

## The north wing: a 250 m two-floor concourse under one long skylight. The
## middle stays clear on the ground for a flat-out run; walkways, bridges,
## escalators and blue hoardings (with the walkway gone beneath two of them)
## make the line up top. A catwalk over the food court joins the upper floors.
func _wing() -> void:
	var h := ROOF_Y + 0.5
	var z0 := WING_FRONT
	var z1 := DOCK_BACK
	var mid := (z0 + z1) * 0.5
	var length := z0 - z1
	_part(Vector3(0, -0.5, mid), Vector3(WING_HALF * 2, 1, length), Kind.FLOOR, "TILE")
	for side: float in [-1.0, 1.0]:
		_part(Vector3(side * (WING_HALF + 0.35), h * 0.5, mid), Vector3(0.7, h, length), Kind.NEUTRAL)
		_part(Vector3(side * (WING_HALF + 0.85), h * 0.5, mid), Vector3(0.3, h, length), Kind.NEUTRAL, "FACADE")
	# Catwalk from the back mezzanine over the food court.
	_slab(Vector3(0, UPPER_Y - 0.25, (MEZZ_BACK + z0) * 0.5), Vector3(6, 0.5, MEZZ_BACK - z0))
	_part(Vector3(0, UPPER_Y - 3.0, (MEZZ_BACK + z0) * 0.5), Vector3(0.6, 5.5, 0.6), Kind.NEUTRAL, "RUST")
	for x: float in [-3.1, 3.1]:
		_rail_z(x, Vector2(MEZZ_BACK, z0), UPPER_Y + 0.5)
	# Front mezzanine across the wing, then walkways down both sides.
	var front := z0 - 7.0
	_slab(Vector3(0, UPPER_Y - 0.25, (z0 + front) * 0.5), Vector3(WING_HALF * 2, 0.5, z0 - front))
	_rail_x(front + 0.1, Vector2(-VOID_X, VOID_X), UPPER_Y + 0.5)
	var walk_w := WING_HALF - VOID_X
	var walk_cx := VOID_X + walk_w * 0.5
	for side: float in [-1.0, 1.0]:
		var cuts: Array[Vector2] = []
		for hole: Array in WING_HOLES:
			if hole[0] == side:
				cuts.append(hole[1])
		var a := front
		for cut: Vector2 in cuts + [Vector2(STORE_Z, STORE_Z)]:
			_slab(Vector3(side * walk_cx, UPPER_Y - 0.25, (a + cut.x) * 0.5), Vector3(walk_w, 0.5, a - cut.x))
			# The shops behind a hole keep their floor.
			if cut.x != cut.y:
				_slab(Vector3(side * (WING_SHOP_X + WING_HALF) * 0.5, UPPER_Y - 0.25, (cut.x + cut.y) * 0.5), Vector3(WING_HALF - WING_SHOP_X, 0.5, cut.x - cut.y))
				_floor_mark(Vector3(side * (VOID_X + WING_SHOP_X) * 0.5, UPPER_Y, cut.x + 0.6), Vector2(WING_SHOP_X - VOID_X, 0.3), Color(0.85, 0.65, 0.2))
			a = cut.y
		# Rails along the void, with gaps at bridges, holes and the landings.
		var gaps: Array[Vector2] = cuts.duplicate()
		for bz: float in BRIDGES:
			gaps.append(Vector2(bz, bz - 4.0))
		gaps.append(Vector2(-124.0, -128.0) if side < 0.0 else Vector2(-276.0, -280.0))
		gaps.sort_custom(func(p: Vector2, q: Vector2) -> bool: return p.x > q.x)
		a = front
		for g: Vector2 in gaps + [Vector2(STORE_Z, STORE_Z)]:
			if a - g.x > 0.5:
				_rail_z(side * (VOID_X + 0.1), Vector2(a, g.x), UPPER_Y + 0.5)
			a = g.y
		# Columns at the void edge, floor to roof.
		var z := front - 6.0
		while z > STORE_Z + 4.0:
			var in_gap := false
			for g: Vector2 in gaps:
				if z < g.x + 1.0 and z > g.y - 1.0:
					in_gap = true
			if not in_gap:
				_part(Vector3(side * (VOID_X + 1.0), ROOF_Y * 0.5, z), Vector3(1, ROOF_Y, 1), Kind.NEUTRAL)
			z -= 16.0
	# Bridges across the void.
	for bz: float in BRIDGES:
		_slab(Vector3(0, UPPER_Y - 0.25, bz - 2.0), Vector3(VOID_X * 2, 0.5, 4))
		for rz: float in [bz - 0.1, bz - 3.9]:
			_rail_x(rz, Vector2(-VOID_X, VOID_X), UPPER_Y + 0.5)
	# Escalators: west up early, east up late (both toward -Z).
	_escalator(Vector3(-4.5, UPPER_Y, -124), Vector3(-4.5, 0, -110))
	_slab(Vector3(-5.15, UPPER_Y - 0.25, -126), Vector3(3.7, 0.5, 4))
	_rail_x(-127.9, Vector2(-VOID_X, -3.3), UPPER_Y + 0.5)
	_rail_z(-3.4, Vector2(-124, -128), UPPER_Y + 0.5)
	_escalator(Vector3(4.5, UPPER_Y, -276), Vector3(4.5, 0, -262))
	_slab(Vector3(5.15, UPPER_Y - 0.25, -278), Vector3(3.7, 0.5, 4))
	_rail_x(-279.9, Vector2(3.3, VOID_X), UPPER_Y + 0.5)
	_rail_z(3.4, Vector2(-276, -280), UPPER_Y + 0.5)
	# Shops both sides, both floors; every fourth bay is boarded up with a
	# blue hoarding to wallrun (the walkway holes sit under two of them).
	var bays := int((front - STORE_Z) / SHOP_LEN)
	for side: float in [-1.0, 1.0]:
		for k in bays:
			var bz := front - k * SHOP_LEN
			var hoard := k % 4 == (3 if side < 0.0 else 1)
			for base: float in [0.0, UPPER_Y]:
				if hoard:
					var hh := (UPPER_Y - 0.5) if base == 0.0 else (ROOF_Y - UPPER_Y)
					_part(Vector3(side * (WING_SHOP_X + 0.2), base + hh * 0.5, bz - SHOP_LEN * 0.5), Vector3(0.4, hh, SHOP_LEN), Kind.WALLRUN)
				else:
					_shop(side, base, bz, k + (3 if base > 0.0 else 0) + (6 if side > 0.0 else 0), base == 0.0, WING_SHOP_X, WING_HALF, k == bays - 1)
		# Close off the strip between the last bay and the store.
		var end := front - bays * SHOP_LEN
		if end - STORE_Z > 0.1:
			_part(Vector3(side * (WING_SHOP_X + WING_HALF) * 0.5, (ROOF_Y) * 0.5, (end + STORE_Z) * 0.5), Vector3(WING_HALF - WING_SHOP_X, ROOF_Y, end - STORE_Z), Kind.NEUTRAL)
	# The ground concourse: a clear middle lane, kiosks and planters to the
	# sides, crates and benches under the walkways, lights.
	var kiosks := [[-4.0, -145.0], [4.0, -190.0], [-4.0, -240.0], [4.0, -300.0]]
	for k: Array in kiosks:
		var kx: float = k[0]
		var kz: float = k[1]
		_part(Vector3(kx, 1.2, kz), Vector3(2.4, 2.4, 5), Kind.NEUTRAL)
		_part(Vector3(kx - signf(kx) * 1.6, 0.5, kz), Vector3(0.8, 1, 5), Kind.PARKOUR, "RUST", SIGN_COLORS[int(-kz) % SIGN_COLORS.size()])
	for pz: float in [-165.0, -215.0, -325.0]:
		for side: float in [-1.0, 1.0]:
			_prop("planter_tub", Vector3(side * 5.6, 0, pz), 0.0)
			_prop("planter_tub", Vector3(side * 5.6, 0, pz - 1.4), 0.5)
	var corridor_x := (VOID_X + WING_SHOP_X) * 0.5 + 0.5
	for side: float in [-1.0, 1.0]:
		var z := front - 14.0
		var i := 0
		while z > STORE_Z + 10.0:
			match i % 3:
				0:
					_prop("crate_wood", Vector3(side * corridor_x, 0, z), 0.3 * side)
				1:
					_part(Vector3(side * corridor_x, 0.25, z), Vector3(0.8, 0.5, 3), Kind.PARKOUR, "RUST")
				2:
					_prop("barrel_rust", Vector3(side * (corridor_x + 1.5), 0, z), 0.0)
			if i % 2 == 0:
				_lamp(Vector3(side * corridor_x, UPPER_Y - 1.3, z - 6.0), COOL if i % 4 == 0 else WARM, 0.8)
			z -= 22.0
			i += 1
	# Roof: one long skylight over the void, slabs either side.
	var y := ROOF_Y + 0.25
	_roof_slab(Vector3(0, y, (z0 + front) * 0.5), Vector3(WING_HALF * 2, 0.5, z0 - front))
	for side: float in [-1.0, 1.0]:
		_roof_slab(Vector3(side * (5.0 + WING_HALF) * 0.5, y, (front + STORE_Z) * 0.5), Vector3(WING_HALF - 5.0, 0.5, front - STORE_Z))
	var rz := front - 3.0
	while rz > STORE_Z:
		_part(Vector3(0, ROOF_Y + 0.2, rz), Vector3(10, 0.4, 0.3), Kind.NEUTRAL, "RUST")
		rz -= 6.0
	_part(Vector3(0, ROOF_Y + 0.2, (front + STORE_Z) * 0.5), Vector3(0.3, 0.4, front - STORE_Z), Kind.NEUTRAL, "RUST")
	_label("Long concourse: keep your speed", Vector3(0, 3.4, front - 4.0), 0.9)
	if not Engine.is_editor_hint():
		_target(Vector3(-10.5, UPPER_Y, -160), ShootingTarget.Motion.STRAFE, 2.0, 3.0)
		_target(Vector3(10.5, UPPER_Y, -250), ShootingTarget.Motion.STATIC)
		_target(Vector3(0, UPPER_Y, -232), ShootingTarget.Motion.STRAFE, 5.0, 4.0)
		_target(Vector3(-4.0, 2.4, -240), ShootingTarget.Motion.STATIC)
		_target(Vector3(4.0, 2.4, -300), ShootingTarget.Motion.BOB)


## The department store anchor: an open hall with racks to slide under and
## tables to vault, an upper sales floor over most of it, stockroom shelving
## to mantle up from the back, a slide down into the dock, and a roof access
## (shelving up through a hatch) for the fight on the roof.
func _store() -> void:
	var h := ROOF_Y + 0.5
	# Front wall: the void runs straight in through a full-height arch; the
	# walkways come in through wide doorways.
	for side: float in [-1.0, 1.0]:
		var cx := side * (VOID_X + WING_HALF) * 0.5
		_part(Vector3(cx, (UPPER_Y - 0.5) * 0.5, STORE_Z + 0.3), Vector3(WING_HALF - VOID_X, UPPER_Y - 0.5, 0.6), Kind.NEUTRAL)
		for seg: Vector2 in [Vector2(VOID_X, 10.0), Vector2(20.0, WING_HALF)]:
			_part(Vector3(side * (seg.x + seg.y) * 0.5, UPPER_Y + (h - UPPER_Y) * 0.5, STORE_Z + 0.3), Vector3(seg.y - seg.x, h - UPPER_Y, 0.6), Kind.NEUTRAL)
		_part(Vector3(side * 15.0, UPPER_Y + 3.2 + (h - UPPER_Y - 3.2) * 0.5, STORE_Z + 0.3), Vector3(10, h - UPPER_Y - 3.2, 0.6), Kind.NEUTRAL)
	_sign_band(Vector3(0, UPPER_Y + 3.5, STORE_Z + 0.7), Vector3(13, 1.6, 0.3), 0.0, "HARGROVE & SONS", SIGN_COLORS[1], 2.0)
	# Upper sales floor, open at the front edge onto the void and at the back.
	_slab(Vector3(0, UPPER_Y - 0.25, (STORE_DECK.x + STORE_DECK.y) * 0.5), Vector3(WING_HALF * 2, 0.5, STORE_DECK.x - STORE_DECK.y))
	_rail_x(STORE_DECK.y + 0.1, Vector2(-17.0, -5.0), UPPER_Y + 0.5)
	_rail_x(STORE_DECK.y + 0.1, Vector2(5.0, 16.0), UPPER_Y + 0.5)
	for x: float in [-18.0, -8.0, 8.0, 18.0]:
		for z: float in [-352.0, -372.0]:
			_part(Vector3(x, (UPPER_Y - 0.5) * 0.5, z), Vector3(0.8, UPPER_Y - 0.5, 0.8), Kind.NEUTRAL)
	# Ground floor: rack rows (1.1 m under the bar: slide) and display tables.
	for row in 4:
		var z := -350.0 - row * 9.0
		for side: float in [-1.0, 1.0]:
			var cx := side * (5.0 + 6.0 * float(row % 2))
			if row % 2 == 0:
				_part(Vector3(cx, 1.35, z), Vector3(5, 0.3, 0.3), Kind.PARKOUR, "RUST")
				for dx: float in [-2.3, 2.3]:
					_part(Vector3(cx + dx, 0.6, z), Vector3(0.2, 1.2, 0.6), Kind.NEUTRAL, "RUST")
			else:
				_part(Vector3(cx, 0.45, z), Vector3(3, 0.9, 1.6), Kind.PARKOUR, "SIGN", SIGN_COLORS[row])
	# Upper floor: mannequin plinths and long display cases.
	for p: Vector3 in [Vector3(-10, 0, -350), Vector3(10, 0, -358), Vector3(-6, 0, -366), Vector3(12, 0, -376)]:
		_part(Vector3(p.x, UPPER_Y + 0.4, p.z), Vector3(2, 0.8, 2), Kind.PARKOUR)
	_part(Vector3(-18, UPPER_Y + 0.5, -362), Vector3(1.5, 1, 14), Kind.PARKOUR, "RUST")
	# Slide from the sales floor's back edge down through the dock doors.
	_ramp(Vector3(0, UPPER_Y, STORE_DECK.y), Vector3(0, 0, DOCK_Z + 0.5), 8.0, Kind.SLIDE)
	_label("Slide down to the dock", Vector3(0, UPPER_Y + 2.5, STORE_DECK.y + 3.0), 0.8)
	# Stockroom shelving at the back: 1.5 m steps up to the sales floor.
	for i in 3:
		var top := 1.5 * (i + 1)
		_part(Vector3(-20, top * 0.5, -395.0 + i * 4.0), Vector3(6, top, 4), Kind.PARKOUR, "RUST")
	_label("Mantle up the shelving", Vector3(-20, 6.5, -394), 0.8)
	# Roof access: shelving up under a hatch; from the top step, mantle out
	# onto the roof ahead.
	for i in 4:
		var top := 1.5 * (i + 1)
		_part(Vector3(14, UPPER_Y + top * 0.5, -361.0 - i * 2.0), Vector3(4, top, 2), Kind.PARKOUR, "RUST")
	_label("ROOF ACCESS", Vector3(14, UPPER_Y + 3.0, -357.0), 1.0)
	# Roof over store and dock, with the hatch at x 12..16, z -368..-360.
	var y := ROOF_Y + 0.25
	_roof_slab(Vector3(0, y, (STORE_Z - 360.0) * 0.5), Vector3(WING_HALF * 2, 0.5, STORE_Z + 360.0))
	_roof_slab(Vector3(0, y, (-368.0 + DOCK_BACK) * 0.5), Vector3(WING_HALF * 2, 0.5, -368.0 - DOCK_BACK))
	_roof_slab(Vector3((-WING_HALF + 12.0) * 0.5, y, -364.0), Vector3(WING_HALF + 12.0, 0.5, 8))
	_roof_slab(Vector3((16.0 + WING_HALF) * 0.5, y, -364.0), Vector3(WING_HALF - 16.0, 0.5, 8))
	# The roof: plant and cover for a fight up there.
	var ry := ROOF_Y + 0.5
	for p: Array in [[Vector3(-12, ry, -350), 0.0, "ac_unit"], [Vector3(-14, ry, -352), 0.0, "ac_unit"], [Vector3(6, ry, -386), PI, "ac_unit"],
			[Vector3(-4, ry, -372), 0.0, "vent_stack"], [Vector3(18, ry, -392), 0.0, "vent_stack"], [Vector3(-18, ry, -398), 0.6, "satellite_dish"],
			[Vector3(0, ry, -412), 0.0, "water_tank"], [Vector3(10, ry, -355), 0.0, "sandbag_wall"], [Vector3(-8, ry, -390), 1.57, "sandbag_wall"]]:
		_prop(p[2], p[0], p[1])
	_lamp(Vector3(0, UPPER_Y - 0.8, -360), WARM, 1.4)
	_lamp(Vector3(-14, ROOF_Y - 0.8, -360), WARM, 1.0)
	_lamp(Vector3(14, ROOF_Y - 0.8, -380), COOL, 1.0)
	if not Engine.is_editor_hint():
		_target(Vector3(10, UPPER_Y + 0.8, -358), ShootingTarget.Motion.STATIC)
		_target(Vector3(-16, 0, -377), ShootingTarget.Motion.STRAFE, 2.0, 3.0)


## The loading dock and the service road out. Past EXIT the road is kept
## clear (a mission carries on down it).
func _dock() -> void:
	var h := ROOF_Y + 0.5
	# Wall between store and dock, open in the middle (where the slide lands).
	for side: float in [-1.0, 1.0]:
		_part(Vector3(side * (6.0 + WING_HALF) * 0.5, h * 0.5, DOCK_Z), Vector3(WING_HALF - 6.0, h, 0.6), Kind.NEUTRAL)
	_part(Vector3(0, 5.0 + (UPPER_Y - 5.5) * 0.5 + 0.25, DOCK_Z), Vector3(12, 1.0, 0.6), Kind.NEUTRAL)
	_part(Vector3(0, UPPER_Y + (h - UPPER_Y) * 0.5, DOCK_Z), Vector3(12, h - UPPER_Y, 0.6), Kind.NEUTRAL)
	# Back wall: a big door in the middle, two bays over the platforms.
	var doors := [Vector2(-16, -10), Vector2(-6, 6), Vector2(10, 16)]
	var a := -WING_HALF - 0.7
	for d: Vector2 in doors + [Vector2(WING_HALF + 0.7, WING_HALF + 0.7)]:
		if d.x - a > 0.01:
			_part(Vector3((a + d.x) * 0.5, h * 0.5, DOCK_BACK - 0.35), Vector3(d.x - a, h, 0.7), Kind.NEUTRAL)
		if d.y - d.x > 0.01:
			_part(Vector3((d.x + d.y) * 0.5, 5.2 + (h - 5.2) * 0.5, DOCK_BACK - 0.35), Vector3(d.y - d.x, h - 5.2, 0.7), Kind.NEUTRAL)
		a = d.y
	_part(Vector3(0, 6.5, DOCK_BACK - 0.85), Vector3(16, 1.2, 0.3), Kind.NEUTRAL, "SIGN", SIGN_COLORS[2])
	# Loading platforms (1.2 m) either side, with stock still on them.
	for side: float in [-1.0, 1.0]:
		_part(Vector3(side * 15.0, 0.6, DOCK_BACK + 3.0), Vector3(14, 1.2, 6), Kind.PARKOUR, "NEUTRAL")
		_prop("crate_stack", Vector3(side * 19.0, 1.2, DOCK_BACK + 3.0), 0.2 * side)
		_prop("pallet", Vector3(side * 12.0, 1.2, DOCK_BACK + 2.5), 0.0)
	_prop("shipping_container", Vector3(-16, 0, -412), PI * 0.5)
	_prop("barrel_rust", Vector3(15, 0, -408), 0.0)
	_prop("barrel_rust", Vector3(15.7, 0, -408.6), 0.0)
	_lamp(Vector3(-10, ROOF_Y - 0.8, -415), COOL, 1.2)
	_lamp(Vector3(10, ROOF_Y - 0.8, -415), COOL, 1.2)
	_label("Out through the dock", Vector3(0, 6.2, -420), 0.9)
	# Service road: lines, a trailer and wrecks off to the sides, the middle
	# left open past the exit.
	for z in range(int(DOCK_BACK) - 4, int(ROAD_END), -6):
		_floor_mark(Vector3(0, 0, z), Vector2(0.25, 3), Color(0.82, 0.74, 0.5))
	_prop("car_wreck", Vector3(-20, 0, -440), 1.4)
	_prop("car_wreck", Vector3(22, 0, -452), -1.7)
	_prop("barricade_jersey", Vector3(-12, 0, -446), 0.2)
	_prop("barricade_jersey", Vector3(13, 0, -436), -0.3)
	_prop("dumpster", Vector3(-27, 0, -433), 0.0)


func _targets() -> void:
	if Engine.is_editor_hint():
		return
	_target(Vector3(-16, UPPER_Y, -50), ShootingTarget.Motion.STATIC)
	_target(Vector3(-25, UPPER_Y, -29.5), ShootingTarget.Motion.BOB)
	_target(Vector3(16, UPPER_Y, -62), ShootingTarget.Motion.STRAFE, 2.5, 3.0)
	_target(Vector3(12.6, UPPER_Y, -30), ShootingTarget.Motion.STATIC)
	_target(Vector3(23, 0, -38), ShootingTarget.Motion.STATIC)
	_target(Vector3(-23, 0, -62), ShootingTarget.Motion.BOB)
	_target(Vector3(0, 1.5, -38), ShootingTarget.Motion.STATIC)
	_target(Vector3(0, UPPER_Y, -50), ShootingTarget.Motion.STRAFE, 6.0, 4.0)
	_target(Vector3(-20, 2.6, -88), ShootingTarget.Motion.STATIC)
	_target(Vector3(0, UPPER_Y, -72), ShootingTarget.Motion.STRAFE, 8.0, 4.0)
	_target(Vector3(25, 2.6, -82), ShootingTarget.Motion.BOB)


# ---------------------------------------------------------------- helpers

## A box with an optional visual-only look ("TILE", "RUST", "SIGN"...) and
## paint color for the art pass. Gameplay never reads either.
func _part(center: Vector3, size: Vector3, kind: Kind, look := "", color := Color.TRANSPARENT) -> StaticBody3D:
	return _part_basis(center, size, Basis.IDENTITY, kind, look, color)


func _part_basis(center: Vector3, size: Vector3, basis: Basis, kind: Kind, look := "", color := Color.TRANSPARENT) -> StaticBody3D:
	var b := _box_basis(center, size, basis, kind)
	if look != "":
		b.set_meta("look", look)
	if color.a > 0.0:
		b.set_meta("look_color", color)
	return b


func _slab(center: Vector3, size: Vector3) -> void:
	_part(center, size, Kind.FLOOR, "TILE")


func _roof_slab(center: Vector3, size: Vector3) -> void:
	_part(center, size, Kind.NEUTRAL)


## A prop from the shared kit (art/props), bottom center at `at`, turned by
## yaw. Loaded by path, so a model the editor hasn't imported yet shows as
## gray boxes instead of breaking the map.
func _prop(prop_name: String, at: Vector3, yaw: float) -> Node3D:
	return PropKit.place(_root, prop_name, Transform3D(Basis(Vector3.UP, yaw), at))


## The body _ramp just made.
func _last() -> Node:
	return _root.get_child(_root.get_child_count() - 1)


## A 1 m railing along z at x, over z range seg (top at y + 0.5).
func _rail_z(x: float, seg: Vector2, y: float) -> void:
	_part(Vector3(x, y, (seg.x + seg.y) * 0.5), Vector3(0.15, 1, absf(seg.x - seg.y)), Kind.PARKOUR, "RUST")


func _rail_x(z: float, seg: Vector2, y: float) -> void:
	_part(Vector3((seg.x + seg.y) * 0.5, y, z), Vector3(absf(seg.x - seg.y), 1, 0.15), Kind.PARKOUR, "RUST")


## A beam from a to b with cross-section size (width, height).
func _beam(a: Vector3, b: Vector3, size: Vector2, kind: Kind, look := "") -> void:
	var f := (b - a).normalized()
	var x := Vector3.UP.cross(f).normalized()
	var y := f.cross(x).normalized()
	_part_basis((a + b) * 0.5, Vector3(size.x, size.y, a.distance_to(b)), Basis(x, y, f), kind, look)


## A hanging cable: visual only, so nothing snags on it.
func _cable(a: Vector3, b: Vector3) -> void:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, a.distance_to(b), 0.05)
	m.mesh = bm
	m.position = (a + b) * 0.5
	m.material_override = _material(Kind.NEUTRAL)
	_root.add_child(m)


## A breakable glass pane, turned by yaw (the pane spans its local X).
func _glass(bottom_center: Vector3, size: Vector2, yaw: float) -> void:
	if Engine.is_editor_hint():
		return
	var w: StaticBody3D = WINDOW_SCRIPT.new()
	w.size = size
	w.position = bottom_center
	w.rotation.y = yaw
	_root.add_child(w)


## A painted sign board with its name on the front (the face turned by yaw
## from +Z).
func _sign_band(center: Vector3, size: Vector3, yaw: float, text: String, color: Color, text_size: float) -> void:
	_part(center, size, Kind.NEUTRAL, "SIGN", color)
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.pixel_size = 0.004 * text_size
	l.outline_size = 10
	l.modulate = Color(0.96, 0.92, 0.82)
	l.outline_modulate = Color(0.1, 0.08, 0.06)
	var front := Basis(Vector3.UP, yaw) * Vector3.BACK
	var half := minf(size.x, size.z) * 0.5
	l.position = center + front * (half + 0.02)
	l.rotation.y = yaw
	_root.add_child(l)


## A ceiling light: a small fitting and a soft light without shadows.
func _lamp(pos: Vector3, color: Color, energy: float) -> void:
	_part(pos + Vector3(0, 0.15, 0), Vector3(1.2, 0.1, 0.4), Kind.NEUTRAL, "RUST")
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = 9.0
	light.shadow_enabled = false
	_root.add_child(light)
