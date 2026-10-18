extends RefCounted
## The city round a mission's course. Every bit of ground the course doesn't
## use (and no base map covers) is built over with ruined buildings that
## stand well clear above the course, so a run is a street or a canyon of
## roofs with no way out of it: fall off a roof's side and you fall into a
## slot between walls, never out into open city. Next to the course the
## blocks are solid; further out they are bigger blocks with narrow streets
## between them, so the skyline reads as a city from the high roofs.
##
## Streets on the course get pavements with kerbs, lamp posts, dumpsters,
## wrecks and rubble, and faded road lines; the ground under gaps between
## roofs gets rubble, wrecks and the odd fire, so looking down shows a city
## floor rather than a plain slab.
##
## Works on a grid of CELL m squares over the mission's floor: the course's
## areas (roofs, gaps, streets, ramps, corners and every piece) are drawn on
## it, then the free cells are merged into building boxes block by block.
## Same mission, same city (seeded by the mission id).
##
## Loaded by path (no class_name).

const CELL := 2.0
## A city block is BLOCK x BLOCK cells (16 m); far from the course blocks
## join up BIG x BIG (48 m) with streets between them.
const BLOCK := 8
const BIG := 3
## Room between the course and the first buildings: a slot beside roofs
## (so each roof reads as its own building; fall in and you're out), wider
## beside streets (a pavement).
const ROOF_MARGIN := 1.5
const STREET_MARGIN := 3.5
const PIECE_MARGIN := 0.4
## How far a roof's height reaches into the city: buildings this close stand
## at least CLEAR above it (a climb is 3 m, so nobody gets up them).
const NEAR := 16.0
const CLEAR := 9.0
## Lower than this, an area is a street (the floor is at 0).
const STREET_TOP := 0.5

const F_COURSE := 1  # on the course or its margin
const F_INNER := 2  # inside a course area proper
const F_SOLID := 4  # inside a roof, box or other solid piece
const F_BASE := 8  # the base map's ground

const STREET_PROPS := ["dumpster", "car_wreck", "debris_pile", "tire_stack", "barrel_rust", "street_sign", "crate_stack", "lamp", "lamp"]
const GROUND_PROPS := ["debris_pile", "car_wreck", "debris_pile", "tire_stack", "barrel_rust", "dumpster"]
const SKYLINE_PROPS := ["water_tank", "antenna_mast", "billboard", "water_tank"]


## An area of the course: center (x, z), half size (across, along), yaw (as
## a leg or piece yaw: along runs toward (sin yaw, cos yaw)), roof height.
static func area(c: Vector2, half: Vector2, yaw: float, top: float, margin: float, solid := false) -> Dictionary:
	return {"c": c, "h": half, "yaw": yaw, "top": top, "margin": margin, "solid": solid}


## Adds the city to mission.pieces round the course `lanes` (areas from the
## route) and every piece already in the mission, over `ground` (x, z).
static func build(mission: Dictionary, lanes: Array, ground: Rect2, seed_text: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text + ":city")
	var areas: Array = lanes.duplicate()
	areas.append_array(_piece_areas(mission.pieces))
	var g := {
		"o": ground.position, "nx": ceili(ground.size.x / CELL), "nz": ceili(ground.size.y / CELL),
	}
	var n: int = g.nx * g.nz
	var flags := PackedByteArray()
	flags.resize(n)
	var near := PackedFloat32Array()
	near.resize(n)
	near.fill(-1e6)
	var top := PackedFloat32Array()
	top.resize(n)
	top.fill(-1e6)
	g.flags = flags
	g.near = near
	g.top = top
	for a: Dictionary in areas:
		_draw(g, a)
	_exclude_base(g, mission)
	_open(g, mission)
	var base_y := 0.0
	for l: Dictionary in lanes:
		base_y += float(l.top)
	base_y = base_y / maxf(1.0, lanes.size())
	_blocks(g, mission, rng, base_y)
	_horizon(mission, rng, ground, base_y, g.get("base", Rect2()))
	_streets(g, mission, rng, lanes)
	_ground(g, mission, rng)


# ---------------------------------------------------------------- the grid

static func _piece_areas(pieces: Array) -> Array:
	var out: Array = []
	for p: Dictionary in pieces:
		var yaw := deg_to_rad(float(p.get("yaw", 0.0)))
		if p.has("building"):
			var c: Array = p.building
			out.append(area(Vector2(c[0], c[2]), Vector2(p.size[0], p.size[1]) * 0.5, yaw, float(c[1]), PIECE_MARGIN, true))
		elif p.has("slab"):
			var r := Rect2(p.slab[0][0], p.slab[0][1], 0, 0)
			for a: Array in p.slab:
				r = r.expand(Vector2(a[0], a[1]))
			out.append(area(r.get_center(), r.size * 0.5, 0.0, float(p.get("top", 6.0)), PIECE_MARGIN, true))
		elif p.has("box"):
			if p.get("kind", "") == "FLOOR":
				continue
			var c: Array = p.box
			var s: Array = p.get("size", [1, 1, 1])
			out.append(area(Vector2(c[0], c[2]), Vector2(s[0], s[2]) * 0.5, yaw, float(c[1]) + float(s[1]) * 0.5, PIECE_MARGIN, true))
		elif p.has("ramp"):
			var a := Vector2(p.ramp[0], p.ramp[2])
			var b := Vector2(p.to[0], p.to[2])
			var d := b - a
			out.append(area((a + b) * 0.5, Vector2(float(p.get("width", 6.0)) * 0.5, d.length() * 0.5), atan2(d.x, d.y),
				maxf(p.ramp[1], p.to[1]), PIECE_MARGIN, true))
		elif p.has("row"):
			var a := Vector2(p.from[0], p.from[2])
			var b := Vector2(p.to[0], p.to[2])
			var d := b - a
			out.append(area((a + b) * 0.5, Vector2(1.0, d.length() * 0.5 + 1.0), atan2(d.x, d.y), float(p.from[1]) + 1.0, PIECE_MARGIN))
		else:
			for k: String in ["loop", "quarter_pipe", "bank", "door", "doors", "window", "target"]:
				if p.has(k):
					var c: Array = p[k]
					out.append(area(Vector2(c[0], c[2]), Vector2(8, 8), 0.0, float(c[1]) + 4.0, PIECE_MARGIN))
	return out


static func _index(g: Dictionary, i: int, j: int) -> int:
	return j * int(g.nx) + i


## The world (x, z) center of cell i, j.
static func _cell(g: Dictionary, i: int, j: int) -> Vector2:
	return g.o + Vector2((i + 0.5) * CELL, (j + 0.5) * CELL)


## Calls fn(index, inside) for every cell an area reaches, grown by `grow`.
## `inside` is true when the cell's center is in the area proper.
static func _each(g: Dictionary, a: Dictionary, grow: float, fn: Callable) -> void:
	var c: Vector2 = a.c
	var h: Vector2 = a.h
	var cs := cos(float(a.yaw))
	var sn := sin(float(a.yaw))
	# A cell touches the area when its center is within half a cell of it
	# (measured across the area's turned axes).
	var pad := CELL * 0.5 * (absf(cs) + absf(sn))
	var hx := h.x + grow + pad
	var hz := h.y + grow + pad
	var ex := absf(cs) * hx + absf(sn) * hz
	var ez := absf(sn) * hx + absf(cs) * hz
	var i0 := maxi(0, floori((c.x - ex - g.o.x) / CELL))
	var i1 := mini(int(g.nx) - 1, floori((c.x + ex - g.o.x) / CELL))
	var j0 := maxi(0, floori((c.y - ez - g.o.y) / CELL))
	var j1 := mini(int(g.nz) - 1, floori((c.y + ez - g.o.y) / CELL))
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var p := _cell(g, i, j) - c
			# Into the area's frame: x across, z along.
			var lx := p.x * cs - p.y * sn
			var lz := p.x * sn + p.y * cs
			if absf(lx) <= hx and absf(lz) <= hz:
				fn.call(_index(g, i, j), absf(lx) <= h.x and absf(lz) <= h.y)


static func _draw(g: Dictionary, a: Dictionary) -> void:
	var flags: PackedByteArray = g.flags
	var near: PackedFloat32Array = g.near
	var top: PackedFloat32Array = g.top
	var t: float = a.top
	var solid: bool = a.solid
	_each(g, a, float(a.margin), func(k: int, inside: bool) -> void:
		var f := flags[k] | F_COURSE
		if inside:
			f |= F_INNER
			if solid:
				f |= F_SOLID
		flags[k] = f
		top[k] = maxf(top[k], t))
	_each(g, a, NEAR, func(k: int, _inside: bool) -> void:
		near[k] = maxf(near[k], t))


## The base map's own ground (with its ring of buildings round the sides; its
## far side is open for the route, so the city closes that).
static func _exclude_base(g: Dictionary, mission: Dictionary) -> void:
	if not mission.has("base"):
		return
	var script: Script = load(mission.base)
	var r: Variant = script.get_script_constant_map().get("FOOTPRINT", null) if script != null else null
	if not r is Rect2:
		return
	var rect: Rect2 = r
	rect = rect.grow_individual(10.0, 0.0, 10.0, 10.0)
	g.base = rect
	var flags: PackedByteArray = g.flags
	for j in int(g.nz):
		for i in int(g.nx):
			if rect.has_point(_cell(g, i, j)):
				var k := _index(g, i, j)
				flags[k] = flags[k] | F_BASE


## "city_open": [[x0, z0, x1, z1], ...] is ground the city leaves open,
## such as the hollow a spiral course climbs round (nothing is reachable
## across it, and building it up would hide the course). It gets rubble
## like the ground under gaps.
static func _open(g: Dictionary, mission: Dictionary) -> void:
	var flags: PackedByteArray = g.flags
	var top: PackedFloat32Array = g.top
	for r: Array in mission.get("city_open", []):
		var rect := Rect2(Vector2(r[0], r[1]), Vector2.ZERO).expand(Vector2(r[2], r[3]))
		for j in int(g.nz):
			for i in int(g.nx):
				var k := _index(g, i, j)
				if flags[k] == 0 and rect.has_point(_cell(g, i, j)):
					flags[k] = F_COURSE
					top[k] = 1000.0


# ---------------------------------------------------------------- buildings

static func _free(g: Dictionary, i: int, j: int) -> bool:
	return i >= 0 and j >= 0 and i < int(g.nx) and j < int(g.nz) and (g.flags as PackedByteArray)[_index(g, i, j)] == 0


static func _blocks(g: Dictionary, mission: Dictionary, rng: RandomNumberGenerator, base_y: float) -> void:
	var nbx := ceili(float(g.nx) / BLOCK)
	var nbz := ceili(float(g.nz) / BLOCK)
	# Per block: the highest roof near it (or none), and whether all of it is
	# free city far from the course.
	var high := PackedFloat32Array()
	high.resize(nbx * nbz)
	var far := PackedByteArray()
	far.resize(nbx * nbz)
	var near: PackedFloat32Array = g.near
	for bj in nbz:
		for bi in nbx:
			var h := -1e6
			var all_free := true
			for j in range(bj * BLOCK, bj * BLOCK + BLOCK):
				for i in range(bi * BLOCK, bi * BLOCK + BLOCK):
					if not _free(g, i, j):
						all_free = false
					elif i < int(g.nx) and j < int(g.nz):
						h = maxf(h, near[_index(g, i, j)])
			high[bj * nbx + bi] = h
			far[bj * nbx + bi] = 1 if all_free and h < -1e5 else 0
	var used := PackedByteArray()
	used.resize(nbx * nbz)
	# Big blocks far out, with a 4 m street round each.
	for gj in range(0, nbz - BIG + 1, BIG):
		for gi in range(0, nbx - BIG + 1, BIG):
			var whole := true
			for bj in range(gj, gj + BIG):
				for bi in range(gi, gi + BIG):
					if far[bj * nbx + bi] == 0:
						whole = false
			if not whole:
				continue
			for bj in range(gj, gj + BIG):
				for bi in range(gi, gi + BIG):
					used[bj * nbx + bi] = 1
			var size := CELL * BLOCK * BIG
			var c: Vector2 = g.o + Vector2(gi * CELL * BLOCK + size * 0.5, gj * CELL * BLOCK + size * 0.5)
			var h := _far_height(rng, base_y) + rng.randf_range(0.0, 12.0)
			_building(mission, rng, c, Vector2(size - 4.0, size - 4.0), h, true)
	for bj in nbz:
		for bi in nbx:
			var b := bj * nbx + bi
			if used[b] == 1:
				continue
			var h: float
			if high[b] > -1e5:
				# Mostly a few floors over the course, now and then a tower.
				var over := rng.randf_range(0.0, 10.0) if rng.randf() < 0.7 else rng.randf_range(12.0, 36.0)
				h = maxf(14.0, high[b] + CLEAR + over)
			else:
				h = _far_height(rng, base_y)
			for r: Rect2i in _rects(g, bi * BLOCK, bj * BLOCK):
				var c: Vector2 = g.o + (Vector2(r.position) + Vector2(r.size) * 0.5) * CELL
				var s := Vector2(r.size) * CELL
				if far[b] == 1:
					# A lone block out in the city: a slit of street round it.
					s -= Vector2(1.5, 1.5)
				_building(mission, rng, c, s, h, far[b] == 1)


## A band of big blocks just past the edge of the ground, so the city runs
## on to the haze when you look over the near rooftops.
## (Not over the base map, which can reach past the ground.)
static func _horizon(mission: Dictionary, rng: RandomNumberGenerator, ground: Rect2, base_y: float, base: Rect2) -> void:
	var size := CELL * BLOCK * BIG
	var outer := ground.grow(size)
	var spots: Array[Vector2] = []
	var x := outer.position.x
	while x < outer.end.x:
		for z: float in [outer.position.y + size * 0.5, outer.end.y - size * 0.5]:
			spots.append(Vector2(x + size * 0.5, z))
		x += size
	var z := ground.position.y
	while z < ground.end.y:
		for xx: float in [outer.position.x + size * 0.5, outer.end.x - size * 0.5]:
			spots.append(Vector2(xx, z + size * 0.5))
		z += size
	for c: Vector2 in spots:
		var s := Vector2(size - 6.0, size - 6.0)
		if base.has_area() and base.intersects(Rect2(c - s * 0.5, s)):
			continue
		_building(mission, rng, c, s, _far_height(rng, base_y) + 10.0, true)


static func _far_height(rng: RandomNumberGenerator, base_y: float) -> float:
	return maxf(12.0, base_y + rng.randf_range(-2.0, 34.0))


static func _building(mission: Dictionary, rng: RandomNumberGenerator, c: Vector2, s: Vector2, h: float, skyline: bool) -> void:
	h = snappedf(h, 0.5)
	var look := "BRICK" if rng.randf() < 0.18 else "FACADE"
	mission.pieces.append({"building": [snappedf(c.x, 0.01), h, snappedf(c.y, 0.01)], "size": [snappedf(s.x, 0.01), snappedf(s.y, 0.01)], "look": look, "city": true})
	if skyline and rng.randf() < 0.2 and minf(s.x, s.y) > 6.0:
		var prop: String = SKYLINE_PROPS[rng.randi() % SKYLINE_PROPS.size()]
		mission.pieces.append({"prop": prop, "at": [snappedf(c.x, 0.01), h, snappedf(c.y, 0.01)], "yaw": 90.0 * (rng.randi() % 4), "collide": false})


## The free cells of one block as rectangles (cell coordinates): runs along
## each row, joined with identical runs in the rows after.
static func _rects(g: Dictionary, i0: int, j0: int, test := Callable()) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	var open: Dictionary = {}  # Vector2i(start, end) -> Rect2i being grown
	for j in range(j0, j0 + BLOCK + 1):
		var runs: Array[Vector2i] = []
		if j < j0 + BLOCK:
			var i := i0
			while i < i0 + BLOCK:
				if _ok(g, i, j, test):
					var s := i
					while i < i0 + BLOCK and _ok(g, i, j, test):
						i += 1
					runs.append(Vector2i(s, i))
				else:
					i += 1
		var next: Dictionary = {}
		for run: Vector2i in runs:
			if open.has(run):
				var r: Rect2i = open[run]
				r.size.y += 1
				next[run] = r
				open.erase(run)
			else:
				next[run] = Rect2i(run.x, j, run.y - run.x, 1)
		for r: Rect2i in open.values():
			out.append(r)
		open = next
	return out


static func _ok(g: Dictionary, i: int, j: int, test: Callable) -> bool:
	if test.is_valid():
		return i < int(g.nx) and j < int(g.nz) and test.call(i, j)
	return _free(g, i, j)


# ---------------------------------------------------------------- streets

## A street cell: course margin at street level, outside every course area.
static func _pavement(g: Dictionary, i: int, j: int) -> bool:
	var k := _index(g, i, j)
	var f: int = (g.flags as PackedByteArray)[k]
	return f & (F_COURSE | F_INNER | F_BASE) == F_COURSE and (g.top as PackedFloat32Array)[k] <= STREET_TOP


static func _streets(g: Dictionary, mission: Dictionary, rng: RandomNumberGenerator, lanes: Array) -> void:
	var test := func(i: int, j: int) -> bool: return _pavement(g, i, j)
	for bj in ceili(float(g.nz) / BLOCK):
		for bi in ceili(float(g.nx) / BLOCK):
			for r: Rect2i in _rects(g, bi * BLOCK, bj * BLOCK, test):
				var c: Vector2 = g.o + (Vector2(r.position) + Vector2(r.size) * 0.5) * CELL
				var s := Vector2(r.size) * CELL
				# Pavement with a kerb: a step you run up without noticing.
				mission.pieces.append({"box": [snappedf(c.x, 0.01), 0.08, snappedf(c.y, 0.01)], "size": [s.x, 0.16, s.y], "kind": "NEUTRAL", "look": "TILE", "city": true})
				# Street furniture down the middle of long strips.
				var along_x := s.x > s.y
				var length := maxf(s.x, s.y)
				if minf(s.x, s.y) < 1.9 or length < 6.0:
					continue
				var d := rng.randf_range(1.0, 4.0)
				while d < length - 1.0:
					var at := c + (Vector2(d - length * 0.5, 0) if along_x else Vector2(0, d - length * 0.5))
					_street_prop(mission, rng, at, along_x, minf(s.x, s.y))
					d += rng.randf_range(9.0, 16.0)
	# Faded road lines and stains down the middle of the course's streets
	# (not where its streets are something else: "road_lines": false).
	if mission.get("road_lines", true) == false:
		return
	for l: Dictionary in lanes:
		if float(l.top) > STREET_TOP or l.h.y < 8.0:
			continue
		var fwd := Vector2(sin(float(l.yaw)), cos(float(l.yaw)))
		var right := Vector2(cos(float(l.yaw)), -sin(float(l.yaw)))
		var d := -float(l.h.y) + 4.0
		while d < float(l.h.y) - 4.0:
			var p: Vector2 = l.c + fwd * d
			mission.pieces.append({"mark": [snappedf(p.x, 0.01), 0.0, snappedf(p.y, 0.01)], "size": [0.25, 3.0], "color": "#c9bd9a", "yaw": rad_to_deg(float(l.yaw)), "city": true})
			if rng.randf() < 0.12:
				var q: Vector2 = p + right * rng.randf_range(-4.0, 4.0)
				mission.pieces.append({"mark": [snappedf(q.x, 0.01), 0.0, snappedf(q.y, 0.01)], "size": [rng.randf_range(1.5, 3.0), rng.randf_range(1.0, 2.2)], "color": "#4a4038", "yaw": rng.randf_range(0.0, 180.0), "city": true})
			d += 9.0


static func _street_prop(mission: Dictionary, rng: RandomNumberGenerator, at: Vector2, along_x: bool, width: float) -> void:
	var kind: String = STREET_PROPS[rng.randi() % STREET_PROPS.size()]
	if kind == "car_wreck" and width < 2.4:
		kind = "debris_pile"
	var y := 0.16
	if kind == "lamp":
		# A dead street lamp: pole and arm.
		mission.pieces.append({"box": [snappedf(at.x, 0.01), y + 3.5, snappedf(at.y, 0.01)], "size": [0.25, 7.0, 0.25], "kind": "NEUTRAL", "look": "RUST", "city": true})
		mission.pieces.append({"box": [snappedf(at.x, 0.01), y + 6.9, snappedf(at.y, 0.01)], "size": [0.35, 0.2, 0.35], "kind": "NEUTRAL", "look": "RUST", "city": true})
		return
	# Cars park along the kerb.
	var yaw := (90.0 if along_x else 0.0) + (180.0 if rng.randf() < 0.5 else 0.0)
	if kind != "car_wreck":
		yaw = rng.randf_range(0.0, 360.0)
	mission.pieces.append({"prop": kind, "at": [snappedf(at.x, 0.01), y, snappedf(at.y, 0.01)], "yaw": snappedf(yaw, 0.1), "city": true})
	if kind == "car_wreck" and rng.randf() < 0.25:
		mission.pieces.append({"fire": [snappedf(at.x, 0.01), y + 1.0, snappedf(at.y, 0.01)], "size": [1.2, 1.2, 1.6], "city": true})


## The ground under the roofs' gaps and in the slots beside them: rubble,
## wrecks and the odd fire, one at most per block.
static func _ground(g: Dictionary, mission: Dictionary, rng: RandomNumberGenerator) -> void:
	var flags: PackedByteArray = g.flags
	var top: PackedFloat32Array = g.top
	for bj in ceili(float(g.nz) / BLOCK):
		for bi in ceili(float(g.nx) / BLOCK):
			if rng.randf() > 0.55:
				continue
			var i := bi * BLOCK + rng.randi() % BLOCK
			var j := bj * BLOCK + rng.randi() % BLOCK
			if i >= int(g.nx) or j >= int(g.nz):
				continue
			var k := _index(g, i, j)
			if flags[k] & (F_COURSE | F_SOLID | F_BASE) != F_COURSE or top[k] <= STREET_TOP:
				continue
			# Only where there's room (not a thin slot by a wall).
			var room := true
			for dj in [-1, 0, 1]:
				for di in [-1, 0, 1]:
					var ii: int = i + di
					var jj: int = j + dj
					if ii < 0 or jj < 0 or ii >= int(g.nx) or jj >= int(g.nz) or flags[_index(g, ii, jj)] & (F_COURSE | F_SOLID) != F_COURSE:
						room = false
			if not room:
				continue
			var at := _cell(g, i, j)
			var kind: String = GROUND_PROPS[rng.randi() % GROUND_PROPS.size()]
			mission.pieces.append({"prop": kind, "at": [snappedf(at.x, 0.01), 0.0, snappedf(at.y, 0.01)], "yaw": snappedf(rng.randf_range(0.0, 360.0), 0.1), "city": true})
			if rng.randf() < 0.2:
				mission.pieces.append({"fire": [snappedf(at.x, 0.01), 0.6, snappedf(at.y, 0.01)], "size": [1.4, 1.4, 1.4], "city": true})
