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

	_parking_lot()
	_shell()
	_upper_floor()
	_escalators()
	_atrium()
	_corridors()
	for side: float in [-1.0, 1.0]:
		for i in 5:
			var upper_east_gap := side > 0.0 and (i == 1 or i == 2 or i == 3)
			_shop(side, 0.0, ATRIUM_FRONT - i * SHOP_LEN, i + (0 if side < 0.0 else 5), true)
			if not upper_east_gap:
				_shop(side, UPPER_Y, ATRIUM_FRONT - i * SHOP_LEN, i + (2 if side < 0.0 else 7), false)
	_collapse()
	_food_court()
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
	# Wrecks to vault and mantle (1.6 m tall: mantle the body, run the roof).
	var wrecks := [
		[Vector3(-9, 0, 30), 0.3, 0], [Vector3(-16, 0, 22), -0.2, 1], [Vector3(10, 0, 33), 1.4, 2],
		[Vector3(17, 0, 21), 0.1, 3], [Vector3(-24, 0, 36), 1.6, 4], [Vector3(26, 0, 40), -0.4, 5],
	]
	for w: Array in wrecks:
		_wreck(w[0], w[1], SIGN_COLORS[w[2]])
	# Dead lamp posts.
	# Ground around the building, and low concrete barriers all round.
	_part(Vector3(0, -0.52, -45), Vector3(80, 1, 110), Kind.FLOOR)
	for x: float in [-40.0, 40.0]:
		_part(Vector3(x, 0.5, -25), Vector3(0.6, 1, 150), Kind.PARKOUR, "NEUTRAL")
	for z: float in [-100.0, 50.0]:
		_part(Vector3(0, 0.5, z), Vector3(80, 1, 0.6), Kind.PARKOUR, "NEUTRAL")
	for p: Vector3 in [Vector3(-14, 0, 40), Vector3(14, 0, 40), Vector3(-30, 0, 18), Vector3(30, 0, 18)]:
		_part(p + Vector3(0, 3.5, 0), Vector3(0.3, 7, 0.3), Kind.NEUTRAL, "RUST")
		_part(p + Vector3(0, 7.0, 0.6), Vector3(0.4, 0.2, 1.4), Kind.NEUTRAL, "RUST")


func _wreck(at: Vector3, yaw: float, paint: Color) -> void:
	var b := Basis(Vector3.UP, yaw)
	_part_basis(at + Vector3(0, 0.55, 0), Vector3(1.8, 0.8, 4.3), b, Kind.NEUTRAL, "RUST", paint.darkened(0.25))
	_part_basis(at + Vector3(0, 1.25, 0) + b * Vector3(0, 0, 0.3), Vector3(1.6, 0.6, 2.2), b, Kind.NEUTRAL, "RUST", paint.darkened(0.4))


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
	_part(Vector3(0, h * 0.5, BACK_Z - 0.35), Vector3(HALF_W * 2 + 1.4, h, 0.7), Kind.NEUTRAL)
	_part(Vector3(0, h * 0.5, BACK_Z - 0.85), Vector3(HALF_W * 2 + 2.0, h, 0.3), Kind.NEUTRAL, "FACADE")
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
	_rail_x(MEZZ_BACK + 0.1, Vector2(-HALF_W, 11.5), ry)
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


## Ground-floor corridors under the walkways: carts to vault, a fallen sign
## to slide under, overhead lights.
func _corridors() -> void:
	var cx := (ATRIUM_X + SHOP_X) * 0.5 + 0.5
	for s: float in [-1.0, 1.0]:
		for z: float in [-22.0, -58.0]:
			_part(Vector3(s * cx, 0.5, z), Vector3(1.4, 1, 2.6), Kind.PARKOUR, "RUST")
		# Fallen sign resting on rubble: slide under (1.1 m clear).
		_part(Vector3(s * cx, 1.35, -34), Vector3(7, 0.5, 0.8), Kind.PARKOUR, "SIGN", SIGN_COLORS[4])
		_part(Vector3(s * (cx - 3.4), 0.55, -34), Vector3(0.6, 1.1, 0.8), Kind.NEUTRAL)
		_part(Vector3(s * (cx + 3.4), 0.55, -34), Vector3(0.6, 1.1, 0.8), Kind.NEUTRAL)
		for z: float in [-16.0, -46.0, -64.0]:
			_lamp(Vector3(s * cx, UPPER_Y - 1.3, z), COOL if z != -46.0 else WARM, 0.8)


## One 12 m shop front on side (-1 west, +1 east) from z0 back: pillars,
## glass bays (ground floor) or empty frames (upper), a doorway, a sign band
## and an interior with a counter and shelves. Some still have power.
func _shop(side: float, base: float, z0: float, index: int, glass: bool) -> void:
	var x := side * SHOP_X
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
	var depth := HALF_W - SHOP_X
	var wx := side * (SHOP_X + depth * 0.5)
	_part(Vector3(wx, base + h * 0.5, z0 - 0.15), Vector3(depth, h, 0.3), Kind.NEUTRAL)
	if z0 - SHOP_LEN <= ATRIUM_BACK + 0.1:
		_part(Vector3(wx, base + h * 0.5, z0 - SHOP_LEN + 0.15), Vector3(depth, h, 0.3), Kind.NEUTRAL)
	# Inside: a counter to vault, shelves along the back to mantle.
	_part(Vector3(side * (SHOP_X + 5), base + 0.5, z0 - 6), Vector3(1, 1, 5), Kind.PARKOUR, "RUST", color.darkened(0.3))
	_part(Vector3(side * (HALF_W - 0.6), base + 0.9, z0 - 6), Vector3(1.2, 1.8, 9), Kind.NEUTRAL, "RUST")
	if index % 3 != 1:
		_lamp(Vector3(side * (SHOP_X + 5), base + h - 0.6, z0 - 6), WARM, 1.4 if index % 2 == 0 else 0.7)


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
	for p: Vector3 in [Vector3(walk_cx + 2, 0.3, mid - 2), Vector3(walk_cx - 3, 0.25, mid + 2.5)]:
		_part(p, Vector3(1.2, 0.6 if p.x > walk_cx else 0.5, 1.0), Kind.NEUTRAL)
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
	for p: Vector3 in [Vector3(6, 0.4, -79), Vector3(-2, 0.3, -88), Vector3(9, 0.35, -88.5)]:
		_part_basis(p, Vector3(1.4, 0.8, 1.1), Basis(Vector3.UP, p.x * 0.3), Kind.NEUTRAL)
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
