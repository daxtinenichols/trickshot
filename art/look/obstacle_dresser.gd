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
##
## ArtLook calls dress() for every PARKOUR, WALLRUN and SLIDE body that has no
## "look" meta of its own. A map can pick the style with the body meta
## "dress" (one of STYLES, or "none" to keep the plain box). Otherwise the
## style comes from the box's shape, and the variant from a hash of where it
## stands, so it's the same every run. Loaded by path (no class_name).

## Every style dress() knows.
const STYLES := ["barrier", "brick", "rail", "sandbags", "pipe", "crates", "planter",
	"brick_wall", "concrete_wall", "hoarding", "billboard", "container", "sheet"]

## Paints, muted so nothing shouts. Hoardings keep a faded blue-green and
## crates and rails a little color, so the language still reads.
const CONCRETE := Color(0.57, 0.54, 0.50)
const CONCRETE_DARK := Color(0.46, 0.44, 0.41)
const BRICK := Color(0.50, 0.32, 0.26)
const MORTAR := Color(0.66, 0.62, 0.55)
const TIMBER := Color(0.56, 0.42, 0.29)
const SACK := Color(0.58, 0.51, 0.38)
const STEEL := Color(0.42, 0.40, 0.37)
const HOARDING_PAINTS := [Color(0.33, 0.47, 0.50), Color(0.40, 0.46, 0.40), Color(0.52, 0.44, 0.34), Color(0.36, 0.40, 0.48)]
const CONTAINER_PAINTS := [Color(0.55, 0.27, 0.20), Color(0.24, 0.38, 0.46), Color(0.38, 0.44, 0.30)]
const HAZARD := Color(0.70, 0.30, 0.22)
const POSTER_PAINTS := [Color(0.78, 0.70, 0.52), Color(0.62, 0.30, 0.25), Color(0.30, 0.42, 0.52), Color(0.74, 0.58, 0.30)]


## Dresses `body` (a SandboxBuilder box: a StaticBody3D with a BoxShape3D
## and the graybox mesh `core`). `look` is ArtLook, for its materials.
## Returns the node it added (a child of the body), or null if it left the
## box as it was. May hide `core`; the caller restores it.
static func dress(body: Node3D, core: MeshInstance3D, look: Object) -> Node3D:
	var size := _box_size(body)
	if size == Vector3.ZERO:
		return null
	var kind: String = body.get_meta("kind", "")
	var style: String = body.get_meta("dress", "")
	if style == "none":
		return null
	if style == "" or not STYLES.has(style):
		style = pick_style(kind, size, body.global_position)
	if style == "":
		return null
	var root := Node3D.new()
	root.name = "Dress"
	var d := _Dress.new(root, core, look, size, _hash(body.global_position))
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
