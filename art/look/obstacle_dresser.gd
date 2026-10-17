extends RefCounted
## Dresses graybox obstacles as part of the ruined city, so a vault reads as
## a concrete barrier or a crate stack and a wallrun wall as a sheet-metal
## hoarding, instead of a yellow or blue box. Visual only: the body, its
## collision box and its "kind" are untouched, and every dress fills the
## same box (detail sticks out a few centimeters at most), so what you see is
## what you hit.
##
## The look stays consistent so it can still be read at speed:
##   corrugated sheet metal / billboards = run along it (WALLRUN)
##   concrete, brick, crates, rails, sandbags = vault, mantle, climb (PARKOUR)
##   pipes and girders at head height = slide under (thin PARKOUR bars)
##   bent sheet metal = slide down (SLIDE)
##   escalators (a map asks for them) = steps over a ramp you run or slide on
##   poured concrete channel walls = banks you run along (SURFACE)
##   riveted scrap-steel track with rims and ribs = loops and quarter pipes
##   concrete ramps with kerbs = steep ramps you run up
##
## ArtLook calls dress() for every PARKOUR, WALLRUN, SLIDE and SURFACE body
## that has no "look" meta of its own, and for bodies whose "look" asks for a
## whole building (see ArtLook.LOOK_DRESSES: "TOWER" is the broadcast tower). A map can pick the style with the body meta
## "dress" (one of STYLES, or "none" to keep the plain box). Otherwise the
## style comes from the box's shape, and the variant from a hash of where it
## stands, so it's the same every run. Loaded by path (no class_name).

## Every style dress() knows.
const STYLES := ["barrier", "brick", "rail", "sandbags", "pipe", "crates", "planter",
	"brick_wall", "concrete_wall", "hoarding", "billboard", "container", "sheet", "escalator",
	"channel", "track", "ramp", "broadcast_tower"]

## Paints, muted so nothing shouts. Hoardings keep a faded blue-green and
## crates and rails a little color, so the language still reads.
const CONCRETE := Color(0.57, 0.54, 0.50)
const CONCRETE_DARK := Color(0.46, 0.44, 0.41)
const BRICK := Color(0.42, 0.24, 0.19)
const MORTAR := Color(0.66, 0.62, 0.55)
const TIMBER := Color(0.56, 0.42, 0.29)
const SACK := Color(0.58, 0.51, 0.38)
const STEEL := Color(0.42, 0.40, 0.37)
const HOARDING_PAINTS := [Color(0.33, 0.47, 0.50), Color(0.40, 0.46, 0.40), Color(0.52, 0.44, 0.34), Color(0.36, 0.40, 0.48)]
const CONTAINER_PAINTS := [Color(0.55, 0.27, 0.20), Color(0.24, 0.38, 0.46), Color(0.38, 0.44, 0.30)]
const HAZARD := Color(0.70, 0.30, 0.22)
## Runnable curves: one paint per kind of piece (not per piece), so a loop or
## a bank built from dozens of strips reads as one structure.
const TRACK_PAINT := Color(0.40, 0.44, 0.42)
const CHANNEL := Color(0.52, 0.50, 0.47)
## The broadcast tower: raw concrete, a rusted scaffold, red and white
## aviation paint up top.
const TOWER_CONCRETE := Color(0.50, 0.48, 0.45)
const AVIATION_RED := Color(0.62, 0.20, 0.16)
const AVIATION_WHITE := Color(0.80, 0.77, 0.70)
const POSTER_PAINTS := [Color(0.78, 0.70, 0.52), Color(0.62, 0.30, 0.25), Color(0.30, 0.42, 0.52), Color(0.74, 0.58, 0.30)]


## Dresses `body` (a SandboxBuilder box: a StaticBody3D with a BoxShape3D
## and the graybox mesh `core`). `look` is ArtLook, for its materials.
## Returns the node it added (a child of the body), or null if it left the
## box as it was. May hide `core`; the caller restores it.
static func dress(body: Node3D, core: MeshInstance3D, look: Object, forced := "") -> Node3D:
	var size := _box_size(body)
	if size == Vector3.ZERO:
		return null
	var kind: String = body.get_meta("kind", "")
	var style: String = forced if forced != "" else body.get_meta("dress", "")
	if style == "none":
		return null
	if style == "" or not STYLES.has(style):
		if kind == "SURFACE":
			style = surface_style(body, size)
		else:
			style = pick_style(kind, size, body.global_position)
	if style == "":
		return null
	var root := Node3D.new()
	root.name = "Dress"
	var d := _Dress.new(root, core, look, size, _hash(body.global_position))
	d.body = body
	match style:
		"barrier": d.barrier()
		"brick": d.brick_low()
		"rail": d.rail()
		"sandbags": d.sandbags()
		"pipe": d.pipe()
		"crates": d.crates()
		"planter": d.planter()
		"brick_wall": d.brick_wall()
		"concrete_wall": d.concrete_wall()
		"hoarding": d.hoarding()
		"billboard": d.billboard()
		"container": d.container()
		"sheet": d.sheet()
		"escalator": d.escalator()
		"channel": d.channel()
		"track": d.track()
		"ramp": d.ramp()
		"broadcast_tower": d.broadcast_tower()
	root.set_meta("style", style)
	body.add_child(root)
	return root


## The style a box of this kind and size gets when the map doesn't say.
static func pick_style(kind: String, size: Vector3, at: Vector3) -> String:
	var h := _hash(at)
	var thin := minf(size.x, size.z)
	var long := maxf(size.x, size.z)
	match kind:
		"WALLRUN":
			if size.y >= 6.0 and h < 0.35:
				return "billboard"
			if size.y <= 3.2 and long <= 13.0 and h > 0.75:
				return "container"
			return "hoarding"
		"SLIDE":
			return "sheet"
		"PARKOUR":
			if size.y <= 0.65 and thin <= 0.8:
				return "pipe"
			if size.y <= 1.4 and thin <= 0.8:
				return ["barrier", "brick", "rail", "sandbags"][int(h * 4.0) % 4]
			if size.y <= 1.8:
				if long <= 6.5 and thin >= 0.9 and h < 0.55:
					return "crates"
				return "planter" if h < 0.8 else "brick"
			return "brick_wall" if h < 0.6 else "concrete_wall"
	return ""


## Runnable surfaces (SurfaceShapes pieces): a bank strip runs along its
## long side (its "flow" lies along the box's x), a loop or quarter pipe
## strip runs along z and is thin, a steep ramp is a thick slab.
static func surface_style(body: Node3D, size: Vector3) -> String:
	var flow: Vector3 = body.get_meta("flow", Vector3.ZERO)
	var local := body.global_basis.orthonormalized().inverse() * flow
	if absf(local.x) > absf(local.z):
		return "channel"
	if size.y >= 0.8:
		return "ramp"
	return "track"


static func _box_size(body: Node) -> Vector3:
	for c in body.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
			return ((c as CollisionShape3D).shape as BoxShape3D).size
	return Vector3.ZERO


static func _hash(p: Vector3) -> float:
	var v := sin(snappedf(p.x, 0.1) * 12.9898 + snappedf(p.y, 0.1) * 4.1414 + snappedf(p.z, 0.1) * 78.233) * 43758.5453
	return v - floorf(v)


## Builds one dress in the body's local space: x, y, z are the box's axes,
## centered on it. "Along" is the box's long horizontal axis.
class _Dress:
	var root: Node3D
	var body: Node3D
	var core: MeshInstance3D
	var look: Object
	var s: Vector3
	var h: float
	## Unit vector of the long horizontal axis, and the thin one.
	var along: Vector3
	var across: Vector3
	var long: float
	var thin: float

	func _init(r: Node3D, c: MeshInstance3D, l: Object, size: Vector3, hash_: float) -> void:
		root = r
		core = c
		look = l
		s = size
		h = hash_
		if size.x >= size.z:
			along = Vector3.RIGHT
			across = Vector3.BACK
		else:
			along = Vector3.BACK
			across = Vector3.RIGHT
		long = maxf(size.x, size.z)
		thin = minf(size.x, size.z)

	func mat(kind: String, color := Color.TRANSPARENT) -> Material:
		return look.wasteland_material(kind, color)

	## A box from local center and size given as (along, up, across).
	func box(center: Vector3, size: Vector3, m: Material) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = along.abs() * size.x + Vector3.UP * size.y + across.abs() * size.z
		mi.mesh = bm
		mi.position = along * center.x + Vector3.UP * center.y + across * center.z
		mi.material_override = m
		root.add_child(mi)
		return mi

	## A cylinder lying along the long axis (or standing, if `upright`).
	func cyl(center: Vector3, radius: float, length: float, m: Material, upright := false) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = radius
		cm.bottom_radius = radius
		cm.height = length
		cm.radial_segments = 10
		cm.rings = 1
		mi.mesh = cm
		mi.position = along * center.x + Vector3.UP * center.y + across * center.z
		if not upright:
			mi.basis = Basis(across, PI * 0.5) if along == Vector3.RIGHT else Basis(Vector3.RIGHT, PI * 0.5)
		mi.material_override = m
		root.add_child(mi)
		return mi

	func core_as(kind: String, color := Color.TRANSPARENT) -> void:
		core.material_override = mat(kind, color)

	func hide_core() -> void:
		core.visible = false

	## Positions along the long axis every `step` m, centered.
	func spots(step: float, margin := 0.0) -> Array[float]:
		var out: Array[float] = []
		var usable := long - margin * 2.0
		var n := maxi(1, floori(usable / step) + 1)
		var gap := usable / maxf(n - 1, 1)
		for i in n:
			out.append(-usable * 0.5 + gap * i if n > 1 else 0.0)
		return out

	func top() -> float:
		return s.y * 0.5

	func bottom() -> float:
		return -s.y * 0.5

	# ------------------------------------------------------------ PARKOUR

	## Precast concrete barriers, 3 m sections with a gap of shadow between
	## them and a worn hazard band.
	func barrier() -> void:
		hide_core()
		var n := maxi(1, roundi(long / 3.0))
		var seg := long / n
		var concrete := mat("NEUTRAL", CONCRETE)
		var band := mat("SIGN", HAZARD.lerp(CONCRETE, 0.35))
		for i in n:
			var x := -long * 0.5 + seg * (i + 0.5)
			# Wide foot, narrower top, like a jersey barrier.
			var foot := s.y * 0.3
			box(Vector3(x, bottom() + foot * 0.5, 0), Vector3(seg - 0.04, foot, thin), concrete)
			box(Vector3(x, bottom() + foot + (s.y - foot) * 0.5, 0), Vector3(seg - 0.04, s.y - foot, thin * 0.62), concrete)
			if (i + int(h * 10.0)) % 2 == 0:
				box(Vector3(x, top() - 0.12, 0), Vector3(seg * 0.6, 0.1, thin * 0.62 + 0.02), band)

	## A low brick wall with a concrete coping on top.
	func brick_low() -> void:
		core_as("BRICK", BRICK)
		box(Vector3(0, top() - 0.04, 0), Vector3(long + 0.04, 0.08, thin + 0.06), mat("NEUTRAL", CONCRETE))
		# A brick pier every 3 m.
		for x in spots(3.0, 0.2):
			box(Vector3(x, 0, 0), Vector3(0.36, s.y, thin + 0.04), mat("BRICK", BRICK.darkened(0.08)))

	## A steel guard rail: posts and rails in front of a sheet panel.
	func rail() -> void:
		core_as("CORRUGATED", STEEL.lerp(HOARDING_PAINTS[int(h * 4.0) % 4], 0.5))
		var paint := mat("WALLRUN", STEEL.lerp(HOARDING_PAINTS[int(h * 7.0) % 4], 0.3))
		for x in spots(2.0, 0.08):
			box(Vector3(x, 0, 0), Vector3(0.1, s.y, thin + 0.05), paint)
		box(Vector3(0, top() - 0.05, 0), Vector3(long, 0.1, thin + 0.06), paint)
		box(Vector3(0, top() - s.y * 0.45, 0), Vector3(long, 0.12, thin + 0.04), paint)

	## Rows of sandbags, staggered.
	func sandbags() -> void:
		hide_core()
		var rows := maxi(2, roundi(s.y / 0.22))
		var rh := s.y / rows
		var bag := 0.62
		var sack := mat("NEUTRAL", SACK)
		var sack_dark := mat("NEUTRAL", SACK.darkened(0.15))
		for r in rows:
			var off := 0.0 if r % 2 == 0 else bag * 0.5
			var x := -long * 0.5 - off
			var i := 0
			while x < long * 0.5:
				var x0 := maxf(x, -long * 0.5)
				var x1 := minf(x + bag, long * 0.5)
				if x1 - x0 > 0.05:
					var m := sack if (i + r) % 3 != 0 else sack_dark
					box(Vector3((x0 + x1) * 0.5, bottom() + rh * (r + 0.5), 0), Vector3(x1 - x0 - 0.03, rh - 0.02, thin), m)
				x += bag
				i += 1

	## A rusted pipe or girder hung at head height, with straps.
	func pipe() -> void:
		hide_core()
		var r := minf(s.y, thin) * 0.5
		var rust := mat("RUST")
		if h < 0.5:
			cyl(Vector3.ZERO, r, long, rust)
			for x in spots(2.5, 0.3):
				cyl(Vector3(x, 0, 0), r + 0.025, 0.08, mat("NEUTRAL", STEEL))
		else:
			# An I-beam: flanges top and bottom, web between.
			var f := s.y * 0.18
			box(Vector3(0, top() - f * 0.5, 0), Vector3(long, f, thin), rust)
			box(Vector3(0, bottom() + f * 0.5, 0), Vector3(long, f, thin), rust)
			box(Vector3.ZERO, Vector3(long, s.y - f * 2.0, thin * 0.25), rust)

	## A stack of wooden crates filling the block.
	func crates() -> void:
		hide_core()
		var cols := maxi(1, roundi(long / 1.1))
		var deep := maxi(1, roundi(thin / 1.1))
		var layers := maxi(1, roundi(s.y / 0.9))
		var cw := long / cols
		var cd := thin / deep
		var ch := s.y / layers
		var wood := mat("WOOD", TIMBER)
		var wood2 := mat("WOOD", TIMBER.darkened(0.18))
		var frame := mat("WOOD", TIMBER.darkened(0.35))
		for l in layers:
			for i in cols:
				for j in deep:
					var c := Vector3(-long * 0.5 + cw * (i + 0.5), bottom() + ch * (l + 0.5), -thin * 0.5 + cd * (j + 0.5))
					box(c, Vector3(cw - 0.03, ch - 0.02, cd - 0.03), wood if (i + j + l) % 2 == 0 else wood2)
					# Edge battens on the faces you see.
					box(c + Vector3(0, ch * 0.5 - 0.05, 0), Vector3(cw - 0.01, 0.08, cd), frame)
					box(c - Vector3(0, ch * 0.5 - 0.05, 0), Vector3(cw - 0.01, 0.08, cd), frame)

	## A concrete planter or ledge with a coping lip and some dead growth.
	func planter() -> void:
		core_as("NEUTRAL", CONCRETE_DARK)
		box(Vector3(0, top() - 0.05, 0), Vector3(long + 0.06, 0.1, thin + 0.06), mat("NEUTRAL", CONCRETE))
		box(Vector3(0, bottom() + 0.08, 0), Vector3(long + 0.04, 0.16, thin + 0.04), mat("NEUTRAL", CONCRETE_DARK.darkened(0.15)))

	## A climbable brick wall: coping, a drainpipe, a sign or two.
	func brick_wall() -> void:
		core_as("BRICK", BRICK.lerp(MORTAR, h * 0.3))
		box(Vector3(0, top() - 0.08, 0), Vector3(long + 0.06, 0.16, thin + 0.08), mat("NEUTRAL", CONCRETE))
		_drainpipe()

	func concrete_wall() -> void:
		core_as("NEUTRAL", CONCRETE.darkened(0.06))
		# Panel seams and a lip on top.
		for x in spots(3.0, 1.5):
			box(Vector3(x, 0, 0), Vector3(0.05, s.y - 0.02, thin + 0.02), mat("NEUTRAL", CONCRETE_DARK))
		box(Vector3(0, top() - 0.08, 0), Vector3(long + 0.06, 0.16, thin + 0.08), mat("NEUTRAL", CONCRETE))
		_drainpipe()

	func _drainpipe() -> void:
		if long < 2.0:
			return
		var x := (h - 0.5) * (long - 1.0)
		var side := 1.0 if h > 0.5 else -1.0
		cyl(Vector3(x, 0, side * (thin * 0.5 + 0.06)), 0.05, s.y, mat("RUST"), true)

	# ------------------------------------------------------------ WALLRUN

	## A sheet-metal hoarding on posts, in faded paint gone to rust.
	func hoarding() -> void:
		var paint: Color = HOARDING_PAINTS[int(h * 4.0) % 4]
		core_as("CORRUGATED", paint)
		var post := mat("RUST")
		# The end posts cover the wall's ends, so you never see the sheet's
		# edge as a 1 m thick slab.
		for x in spots(3.0, 0.07):
			box(Vector3(x, 0, 0), Vector3(0.16, s.y, thin + 0.06), post)
		box(Vector3(0, top() - 0.06, 0), Vector3(long, 0.12, thin + 0.08), post)
		# Torn posters on the lower half, some of the way along.
		_posters(paint)

	## A billboard: a framed panel of posters on a steel frame.
	func billboard() -> void:
		var paint: Color = HOARDING_PAINTS[int(h * 4.0) % 4].lerp(CONCRETE, 0.3)
		core_as("CORRUGATED", paint)
		var frame := mat("RUST")
		box(Vector3(0, top() - 0.1, 0), Vector3(long + 0.1, 0.2, thin + 0.1), frame)
		box(Vector3(0, bottom() + 0.1, 0), Vector3(long + 0.1, 0.2, thin + 0.1), frame)
		for x in [-long * 0.5, long * 0.5]:
			box(Vector3(x, 0, 0), Vector3(0.2, s.y, thin + 0.1), frame)
		# One big faded ad high up on each face.
		var ad: Color = POSTER_PAINTS[int(h * 11.0) % 4]
		for side in [-1.0, 1.0]:
			box(Vector3(0, s.y * 0.15, side * (thin * 0.5 + 0.015)), Vector3(long * 0.8, s.y * 0.5, 0.02), mat("SIGN", ad))
		_posters(paint)

	## The side of a shipping container lying on the roof.
	func container() -> void:
		var paint: Color = CONTAINER_PAINTS[int(h * 3.0) % 3]
		core_as("CORRUGATED", paint)
		var frame := mat("WALLRUN", paint.darkened(0.25))
		for y in [top() - 0.08, bottom() + 0.08]:
			box(Vector3(0, y, 0), Vector3(long, 0.16, thin + 0.04), frame)
		for x in [-long * 0.5 + 0.07, long * 0.5 - 0.07]:
			box(Vector3(x, 0, 0), Vector3(0.16, s.y, thin + 0.04), frame)

	func _posters(base: Color) -> void:
		if long < 3.0:
			return
		var n := int(h * 5.0) % 3 + 1
		for i in n:
			var x := (fposmod(h * (i + 1) * 3.7, 1.0) - 0.5) * (long - 2.0)
			var y := bottom() + minf(1.6, s.y * 0.4)
			var c: Color = POSTER_PAINTS[(i + int(h * 9.0)) % 4].lerp(base, 0.3)
			var side := 1.0 if (i + int(h * 2.0)) % 2 == 0 else -1.0
			box(Vector3(x, y, side * (thin * 0.5 + 0.012)), Vector3(0.9, 1.2, 0.02), mat("SIGN", c))

	# ------------------------------------------------------------ SLIDE

	## A slab of bent sheet metal laid down a slope.
	func sheet() -> void:
		core_as("CORRUGATED", STEEL.lerp(HOARDING_PAINTS[0], 0.3))
		var edge := mat("RUST")
		for z in [-s.x * 0.5, s.x * 0.5]:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.08, s.y + 0.04, s.z)
			mi.mesh = bm
			mi.position = Vector3(z, 0, 0)
			mi.material_override = edge
			root.add_child(mi)

	## A stopped escalator: horizontal steps down the ramp, their noses on
	## its slope (so feet never sink into them), and a sloped underside.
	## Built in world space, since the ramp's own frame is tilted.
	func escalator() -> void:
		hide_core()
		root.top_level = true
		root.transform = Transform3D.IDENTITY
		var bt := body.global_transform
		var along := bt.basis.z.normalized()
		var up := bt.basis.y.normalized()
		var a := bt.origin + along * s.z * 0.5 + up * s.y * 0.5
		var b := bt.origin - along * s.z * 0.5 + up * s.y * 0.5
		var low := a if a.y < b.y else b
		var high := b if a.y < b.y else a
		var flat := Vector3(high.x - low.x, 0, high.z - low.z)
		var run := flat.length()
		var rise := high.y - low.y
		if run < 0.1:
			return
		var dir := flat / run
		var across := dir.cross(Vector3.UP).normalized()
		var basis := Basis(across, Vector3.UP, -dir)
		var n := maxi(1, roundi(rise / 0.2))
		var step := run / n
		var tread := mat("CORRUGATED", STEEL)
		for i in n:
			var y := low.y + rise * i / n
			var c := low + dir * (step * (i + 0.5))
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(s.x, 0.3, step - 0.01)
			mi.mesh = bm
			mi.transform = Transform3D(basis, Vector3(c.x, y - 0.15, c.z))
			mi.material_override = tread
			root.add_child(mi)
		var under := MeshInstance3D.new()
		var ub := BoxMesh.new()
		ub.size = Vector3(s.x, 0.25, s.z)
		under.mesh = ub
		under.transform = Transform3D(bt.basis, bt.origin - up * 0.3)
		under.material_override = mat("RUST")
		root.add_child(under)

	# ------------------------------------------------------------ SURFACE
	# These boxes are tilted (their y is the running surface's normal), so
	# details are placed in the box's own axes, not along/across.

	## A plain box in the body's own axes.
	func raw(center: Vector3, size: Vector3, m: Material) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.position = center
		mi.material_override = m
		root.add_child(mi)
		return mi

	## A strip of a bank: a section of a poured concrete storm-channel wall,
	## with expansion joints across it every 4 m. Every strip of a bank has
	## the same length and center line, so the joints line up up the curve.
	func channel() -> void:
		core_as("NEUTRAL", CHANNEL)
		var joint := mat("NEUTRAL", CONCRETE_DARK.darkened(0.2))
		var n := maxi(1, floori(s.x / 4.0))
		for i in range(1, n):
			var x := -s.x * 0.5 + s.x * i / n
			raw(Vector3(x, 0, 0), Vector3(0.06, s.y + 0.02, s.z + 0.01), joint)

	## A strip of a loop or quarter pipe: a riveted steel deck plate over a
	## rusted rib, with a rim along each edge, like a ride welded together
	## from scrap.
	func track() -> void:
		core_as("WALLRUN", TRACK_PAINT)
		var rust := mat("RUST")
		for x in [-s.x * 0.5 + 0.05, s.x * 0.5 - 0.05]:
			raw(Vector3(x, 0.04, 0), Vector3(0.1, s.y + 0.08, s.z + 0.02), rust)
		# A rib under the plate, and one more at the far end of long strips.
		var ribs := [0.0] if s.z < 1.6 else [-s.z * 0.5 + 0.1, s.z * 0.5 - 0.1]
		for z in ribs:
			raw(Vector3(0, -s.y * 0.5 - 0.09, z), Vector3(s.x + 0.16, 0.18, 0.14), rust)

	## A steep concrete ramp with a kerb along each side.
	func ramp() -> void:
		core_as("NEUTRAL", CONCRETE.darkened(0.04))
		var kerb := mat("NEUTRAL", CONCRETE_DARK)
		for x in [-s.x * 0.5 + 0.15, s.x * 0.5 - 0.15]:
			raw(Vector3(x, 0.05, 0), Vector3(0.3, s.y + 0.1, s.z), kerb)

	# ------------------------------------------------------------ BUILDINGS

	## The broadcast tower (look "TOWER"): a raw concrete block wrapped in a
	## rusted scaffold, ledges where the floors are, cable runs down the
	## corners, red and white aviation paint at the top and a lattice mast
	## with warning lights on the roof. The scaffold stays inside the
	## building's box, so you can't run into anything you can't see; only
	## the mast stands above the roof, where nobody can reach.
	func broadcast_tower() -> void:
		hide_core()
		var shell := 1.2
		var w := s.x - shell * 2.0
		var d := s.z - shell * 2.0
		var y0 := bottom()
		# Raw concrete with deep vertical fins and a ledge at every floor,
		# so it reads apart from the window-grid blocks around it.
		raw(Vector3.ZERO, Vector3(w, s.y, d), mat("NEUTRAL", TOWER_CONCRETE))
		var fin := mat("NEUTRAL", TOWER_CONCRETE.lightened(0.08))
		var slot := mat("NEUTRAL", Color(0.20, 0.19, 0.18))
		for face in [[Vector3.RIGHT, Vector3.BACK, w, d], [Vector3.BACK, Vector3.RIGHT, d, w]]:
			var nrm: Vector3 = face[0]
			var run: Vector3 = face[1]
			var depth: float = face[2]
			var span: float = face[3]
			var n := maxi(2, roundi(span / 5.0))
			for i in n + 1:
				var t := -span * 0.5 + span * i / n
				for sgn in [-1.0, 1.0]:
					raw(nrm * sgn * (depth * 0.5 + 0.2) + run * t, nrm.abs() * 0.4 + run.abs() * 0.7 + Vector3.UP * s.y, fin)
					if i < n:
						# A dark window slot down the middle of each bay.
						raw(nrm * sgn * (depth * 0.5 + 0.01) + run * (t + span / n * 0.5) + Vector3.UP * 2.0,
							nrm.abs() * 0.04 + run.abs() * (span / n * 0.35) + Vector3.UP * (s.y - 14.0), slot)
		var ledge := mat("NEUTRAL", CONCRETE_DARK)
		var y := 6.0
		while y < s.y - 8.0:
			raw(Vector3(0, y0 + y, 0), Vector3(w + 0.9, 0.5, d + 0.9), ledge)
			y += 6.0
		var bands := 4
		for i in bands:
			var c := AVIATION_RED if i % 2 == 0 else AVIATION_WHITE
			raw(Vector3(0, top() - 1.0 - 1.6 * i, 0), Vector3(w + 0.1, 1.6, d + 0.1), mat("SIGN", c))
		raw(Vector3(0, top() + 0.6, 0), Vector3(w + 0.4, 1.2, d + 0.4), ledge)
		_scaffold(w, d, shell)
		_cables(w, d)
		_mast()

	## A tubular scaffold on every face, in the outer shell of the box: poles
	## every 3 m, ledgers every 2 m, plank decks every 6 m, and braces.
	## Faces alternate how high it reaches, like work stopped at different
	## floors.
	func _scaffold(w: float, d: float, shell: float) -> void:
		var steel := mat("RUST")
		var plank := mat("WOOD", TIMBER.darkened(0.1))
		var faces := [
			[Vector3.RIGHT, Vector3.BACK, w * 0.5 + shell * 0.5, d],
			[Vector3.LEFT, Vector3.FORWARD, w * 0.5 + shell * 0.5, d],
			[Vector3.BACK, Vector3.LEFT, d * 0.5 + shell * 0.5, w],
			[Vector3.FORWARD, Vector3.RIGHT, d * 0.5 + shell * 0.5, w],
		]
		for fi in faces.size():
			var normal: Vector3 = faces[fi][0]
			var run: Vector3 = faces[fi][1]
			var out: float = faces[fi][2]
			var span: float = faces[fi][3]
			var reach := s.y * (0.92 if (fi + int(h * 4.0)) % 2 == 0 else 0.62)
			var y0 := bottom()
			var mid := y0 + reach * 0.5
			var n := maxi(2, roundi(span / 3.0))
			for i in n + 1:
				var t := -span * 0.5 + span * i / n
				for o in [-0.4, 0.4]:
					_pole(normal * (out + o) + run * t + Vector3.UP * mid, Vector3.UP, reach, 0.07, steel)
			var y := 2.0
			while y <= reach:
				for o in [-0.4, 0.4]:
					_pole(normal * (out + o) + Vector3.UP * (y0 + y), run, span, 0.05, steel)
				if int(y) % 6 == 0:
					raw(normal * out + Vector3.UP * (y0 + y - 0.1), (run.abs() * span + normal.abs() * 0.9 + Vector3.UP * 0.06), plank)
				y += 2.0
			# Weathered sheeting hung over some bays, two floors high.
			var sheet_paints := [HOARDING_PAINTS[0], HOARDING_PAINTS[2], CONCRETE]
			for i in n:
				var k := fposmod(h * 13.0 + fi * 0.37 + i * 0.61, 1.0)
				if k < 0.3:
					var top_y := clampf(fposmod(k * 97.0, 1.0) * reach, 14.0, reach - 2.0)
					raw(normal * (out + 0.5) + run * (-span * 0.5 + span * (i + 0.5) / n) + Vector3.UP * (y0 + top_y - 6.0),
						run.abs() * (span / n - 0.2) + normal.abs() * 0.04 + Vector3.UP * 12.0,
						mat("CORRUGATED", sheet_paints[i % 3]))
			# A brace across every other bay, zigzagging up the face.
			var bay := span / n
			var level := 0
			y = 0.0
			while y + 6.0 <= reach:
				for i in range(level % 2, n, 2):
					var a := normal * (out + 0.45) + run * (-span * 0.5 + bay * i) + Vector3.UP * (y0 + y)
					var b := normal * (out + 0.45) + run * (-span * 0.5 + bay * (i + 1)) + Vector3.UP * (y0 + y + 6.0)
					_pole((a + b) * 0.5, (b - a).normalized(), a.distance_to(b), 0.05, steel)
				level += 1
				y += 6.0

	## Bundles of black cable down two corners.
	func _cables(w: float, d: float) -> void:
		var cable := mat("NEUTRAL", Color(0.16, 0.15, 0.14))
		for corner in [Vector3(w * 0.5 + 0.25, 0, d * 0.5 + 0.25), Vector3(-w * 0.5 - 0.25, 0, -d * 0.5 - 0.25)]:
			for k in 3:
				var off := Vector3(0.18 * k, 0, -0.12 * k) if corner.x > 0 else Vector3(-0.12 * k, 0, 0.18 * k)
				_pole(corner + off, Vector3.UP, s.y, 0.07, cable)

	## A tapering four-legged lattice mast on the roof, cross-braced, with red
	## warning lights at the top and halfway.
	func _mast() -> void:
		var red := mat("SIGN", AVIATION_RED)
		var white := mat("SIGN", AVIATION_WHITE)
		var steel := red
		var height := minf(60.0, s.y * 0.8)
		var base := minf(8.0, minf(s.x, s.z) * 0.3)
		var y0 := top() + 1.2
		var legs: Array[Vector3] = []
		for c in [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]:
			legs.append(Vector3(c.x, 0, c.y))
		var tip := 0.6
		# A transmitter hut at the mast's foot.
		raw(Vector3(base * 0.5 + 4.0, y0 + 1.6, 0), Vector3(6, 3.2, 5), mat("CORRUGATED", STEEL))
		for l in legs:
			var a := l * base * 0.5 + Vector3.UP * y0
			var b := l * tip * 0.5 + Vector3.UP * (y0 + height)
			_pole((a + b) * 0.5, (b - a).normalized(), a.distance_to(b), 0.25, red)
		var rings := maxi(3, roundi(height / 5.0))
		for r in rings:
			var t := float(r) / rings
			var t2 := float(r + 1) / rings
			var half := lerpf(base, tip, t) * 0.5
			var half2 := lerpf(base, tip, t2) * 0.5
			steel = red if (r / 2) % 2 == 0 else white
			for i in 4:
				var a := legs[i] * half + Vector3.UP * (y0 + height * t)
				var b := legs[(i + 1) % 4] * half + Vector3.UP * (y0 + height * t)
				var c := legs[(i + 1) % 4] * half2 + Vector3.UP * (y0 + height * t2)
				_pole((a + b) * 0.5, (b - a).normalized(), a.distance_to(b), 0.12, steel)
				_pole((a + c) * 0.5, (c - a).normalized(), a.distance_to(c), 0.09, steel)
		var light := StandardMaterial3D.new()
		light.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		light.albedo_color = Color(1.0, 0.25, 0.15)
		light.emission_enabled = true
		light.emission = Color(1.0, 0.2, 0.1)
		light.emission_energy_multiplier = 3.0
		for y in [y0 + height + 0.4, y0 + height * 0.5]:
			var mi := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.5
			sm.height = 1.0
			mi.mesh = sm
			mi.position = Vector3.UP * y
			mi.material_override = light
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mi)

	## A cylinder from its center along `axis`.
	func _pole(center: Vector3, axis: Vector3, length: float, radius: float, m: Material) -> void:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = radius
		cm.bottom_radius = radius
		cm.height = length
		cm.radial_segments = 6
		cm.rings = 1
		mi.mesh = cm
		var up := axis.normalized()
		var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
		mi.basis = Basis(side, up, side.cross(up))
		mi.position = center
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if radius < 0.1 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		root.add_child(mi)
