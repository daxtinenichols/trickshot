extends RefCounted
## Long missions from a list of route segments instead of hand-placed boxes.
## A mission's "route" is laid out end to end from its start: roofs, gaps,
## wallrun gaps, drops, ramps, street stretches, corners that turn the run
## left or right, and forks where the route splits into two lines that join
## up again, with features on each roof (hurdles, slide bars, wall hops,
## enemies, tapes, checkpoints, radio lines). expand() turns it into
## ordinary pieces, checkpoints and radio lines, plus "bot" steps the tests
## use to run it, so a 900 m mission stays a short, readable file. Format
## in docs/missions.md ("Routes").
##
## Segments are laid out in a running frame: x across the run (right +),
## z along it (decreasing as you go, so -z is the distance run). Each
## corner starts a new leg, a frame turned 45 or 90 degrees about the
## corner's center; at the end every piece is moved from its leg's frame
## into the world. On a leg at 45 degrees to the grid, roofs are turned
## boxes and checkpoints turned regions (`area_yaw`); enemy areas stay
## axis-aligned boxes around their turned area.
##
## Loaded by path (no class_name).

## Roof width; the running lane is its middle.
const WIDTH := 12.0
## Wallrun panels stand just outside the roof edge.
const WALL_X := 6.5
## How far apart the two lines of a fork run (center to center).
const FORK_SPREAD := WIDTH + 6.0
## Length of the wide roof where a fork splits or joins.
const PLAZA := 28.0
## Clutter that sits at roof edges, out of the lane.
const CLUTTER := ["ac_unit", "vent_stack", "satellite_dish", "generator", "barrel_rust",
	"crate_wood", "tire_stack", "crate_stack", "antenna_mast", "loudspeaker_pole"]
## Piece fields that hold a position.
const POINT_KEYS := ["box", "building", "mark", "window", "ramp", "to", "from", "tape", "at", "fire", "spawn",
	"bank", "quarter_pipe", "loop", "door", "target"]
## Pieces that turn with their leg (they take a yaw).
const TURNING_KEYS := ["box", "building", "prop", "row", "mark", "window", "bank", "quarter_pipe", "loop", "door"]
## Enemy types that fight from behind cover: the route puts sandbags in
## front of them (any enemy can say "cover": true or false instead).
const COVER_TYPES := ["raider", "trooper", "marksman"]
## Enemy types that keep to their patch (leashed like mutants).
const LEASHED_TYPES := ["mutant", "crawler", "leaper", "brute"]


## Expands mission["route"] in place. Returns the mission.
static func expand(mission: Dictionary) -> Dictionary:
	var route: Array = mission.get("route", [])
	if route.is_empty():
		return mission
	var origin := _origin(mission)
	var st := {
		"z": 6.0,
		"y": float(mission.get("start", {}).get("at", [0, origin.origin.y, 0])[1]),
		"out": [], "checkpoints": [], "radio": [], "bot": [],
		"rng": RandomNumberGenerator.new(), "lowest": INF, "roof_end": 6.0, "heights": [], "clutter": mission.get("clutter", CLUTTER),
		# Legs: the frame each stretch between corners is laid out in.
		"legs": [{"o": origin.origin, "yaw": origin.yaw, "z0": 0.0, "start": 6.0}],
		"leg": 0, "dx": 0.0, "fork": null, "forks": [],
		"chalk": mission.get("chalk", false),
		"roof_look": mission.get("roof_look", "FACADE"),
	}
	if mission.has("route_origin") or mission.get("route_from", "") == "base_exit":
		st.y = origin.origin.y
	st.rng.seed = hash(String(mission.get("id", "route")))
	for seg: Dictionary in route:
		_segment(st, seg)
	if st.fork != null:
		push_error("Route: a fork never joins (add {\"join\": true})")
		_join(st, {})
	st.legs[-1].end = st.z
	# Everything to world space.
	var pieces: Array = mission.get("pieces", [])
	for e: Array in st.out:
		pieces.append(_place(st, e[0], e[1], e[2]))
	mission.pieces = pieces
	# Route checkpoints come first in order along the route; extra
	# hand-written ones (if any) follow, unless the route carries on from
	# the base map's exit: then the base's come first.
	var after_base: bool = mission.get("route_from", "") == "base_exit"
	var cps: Array = mission.get("checkpoints", []).duplicate() if after_base else []
	for e: Array in st.checkpoints:
		var c: Dictionary = _place(st, e[0], e[1], e[2])
		_turn_region(c, st.legs[e[1]].yaw)
		c.yaw = rad_to_deg(st.legs[e[1]].yaw)
		cps.append(c)
	if not after_base:
		cps.append_array(mission.get("checkpoints", []))
	mission.checkpoints = cps
	var radio: Array = mission.get("radio", [])
	for e: Array in st.radio:
		radio.append(_place(st, e[0], e[1], e[2]))
	mission.radio = radio
	# Bot steps in route order (by distance run). A NAN lane keeps the
	# current lane.
	var bot: Array = st.bot
	bot.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	mission.bot = bot
	if not st.forks.is_empty():
		mission.bot_alt = _alt_bot(bot, st.forks)
	var legs: Array = []
	for l: Dictionary in st.legs:
		legs.append([l.o.x, l.o.z, l.yaw, l.z0])
	mission.route_legs = legs
	var last: int = st.legs.size() - 1
	var end := _world(st, last, 0.0, st.z, st.y)
	mission.route_end = [end.x, end.y, end.z]
	mission.route_end_yaw = rad_to_deg(st.legs[last].yaw)
	mission.route_length = -st.z
	var bounds := _bounds(pieces, st)
	# A street under the whole route (just under the base map's ground,
	# when there is one, so the two never flicker), and the city around it.
	if not mission.has("no_floor"):
		var r := bounds.grow(70.0)
		var top := -0.02 if mission.has("base") else 0.0
		pieces.push_front({"box": [r.get_center().x, top - 0.5, r.get_center().y], "size": [r.size.x, 1, r.size.y], "kind": "FLOOR"})
	_skyline(st, mission)
	if not mission.has("fail_y"):
		mission.fail_y = st.lowest - 5.5 if st.lowest > 6.0 else -20.0
	# "at": "end" or "@Checkpoint name" in objectives and radio lines.
	for list: Array in [mission.get("objectives", []), mission.radio]:
		for o: Dictionary in list:
			if o.get("at", null) is String:
				_resolve(o, mission, st)
	return mission


## Where the route's first leg starts: `route_origin` {"at", "yaw"}, the
## base map's EXIT with `"route_from": "base_exit"`, else the world origin.
static func _origin(mission: Dictionary) -> Dictionary:
	if mission.get("route_from", "") == "base_exit" and mission.has("base"):
		var script: Script = load(mission.base)
		var xf: Variant = script.get_script_constant_map().get("EXIT", null) if script != null else null
		if xf is Transform3D:
			# Spawns face -Z at yaw 0, like legs: the yaw of the exit's facing.
			var fwd: Vector3 = -(xf as Transform3D).basis.z
			return {"origin": (xf as Transform3D).origin, "yaw": _eighth(atan2(-fwd.x, -fwd.z))}
		push_error("Route: base %s has no EXIT" % mission.base)
	var o: Dictionary = mission.get("route_origin", {})
	var at: Array = o.get("at", [0, 0, 0])
	return {"origin": Vector3(at[0], at[1], at[2]), "yaw": _eighth(deg_to_rad(float(o.get("yaw", 0.0))))}


## Snaps a yaw to the nearest eighth of a turn (45 degrees).
static func _eighth(yaw: float) -> float:
	return roundf(yaw / (PI * 0.25)) * PI * 0.25


## True when yaw is a whole number of quarter turns (the leg is square to
## the grid).
static func _square(yaw: float) -> bool:
	return absf(yaw / (PI * 0.5) - roundf(yaw / (PI * 0.5))) < 0.01


static func _resolve(o: Dictionary, mission: Dictionary, st: Dictionary) -> void:
	var ref: String = o.at
	if ref == "end":
		var last: int = st.legs.size() - 1
		var e := _world(st, last, 0.0, st.z + 4.0, st.y + 2.0)
		o.at = [e.x, e.y, e.z]
		if not o.has("size") and not o.has("radius"):
			o.size = [WIDTH + 2.0, 8.0, 8.0]
			_turn_region(o, st.legs[last].yaw)
		return
	for c: Dictionary in mission.checkpoints:
		if "@" + String(c.get("name", "")) == ref:
			o.at = c.at
			if not o.has("size") and not o.has("radius"):
				o.size = c.size
				if c.has("area_yaw"):
					o.area_yaw = c.area_yaw
			return
	push_error("Route: unknown place %s" % ref)
	o.at = [0, -1000, 0]


# ---------------------------------------------------------------- frames

## A point in a leg's frame (x across, z along) in the world.
static func _world(st: Dictionary, leg: int, x: float, z: float, y: float) -> Vector3:
	var l: Dictionary = st.legs[leg]
	var v := Basis(Vector3.UP, l.yaw) * Vector3(x, 0.0, z - l.z0)
	return Vector3(l.o.x + v.x, y, l.o.z + v.z)


## Size [x, y, z] of the axis-aligned box around a box turned by yaw
## (exact on legs square to the grid).
static func _turn_size(size: Array, yaw: float) -> Array:
	var c := absf(cos(yaw))
	var s := absf(sin(yaw))
	return [snappedf(c * size[0] + s * size[2], 0.001), size[1], snappedf(s * size[0] + c * size[2], 0.001)]


## Turns a region ({"at", "size"} in its leg's frame) with its leg: square
## legs swap the size; diagonal ones keep it and set `area_yaw` (degrees),
## which MissionRun.inside() reads.
static func _turn_region(r: Dictionary, yaw: float) -> void:
	if _square(yaw):
		r.size = _turn_size(r.size, yaw)
	else:
		r.area_yaw = rad_to_deg(yaw)


## A copy of a piece (or checkpoint, radio line, enemy) moved from its
## leg's frame, shifted `dx` across, into the world.
static func _place(st: Dictionary, p: Dictionary, leg: int, dx: float) -> Dictionary:
	var out := p.duplicate(true)
	var yaw: float = st.legs[leg].yaw
	for k: String in POINT_KEYS:
		var a: Variant = out.get(k, null)
		if a is Array and a.size() >= 3:
			var w := _world(st, leg, float(a[0]) + dx, float(a[2]), float(a[1]))
			out[k] = [w.x, w.y, w.z]
	if out.has("slab"):
		var pts: Array = []
		for a: Array in out.slab:
			var w := _world(st, leg, float(a[0]) + dx, float(a[1]), 0.0)
			pts.append([w.x, w.z])
		out.slab = pts
	if yaw != 0.0:
		for k: String in TURNING_KEYS:
			if out.has(k):
				out.yaw = float(out.get("yaw", 0.0)) + rad_to_deg(yaw)
				break
	if out.has("encounter"):
		var area: Dictionary = out.area
		var c: Array = area.at
		var w := _world(st, leg, float(c[0]) + dx, float(c[2]), float(c[1]))
		area.at = [w.x, w.y, w.z]
		area.size = _turn_size(area.size, yaw)
		for list: String in ["raiders", "mutants", "cover", "enemies"]:
			for e: Dictionary in out.get(list, []):
				var a: Array = e.at
				var we := _world(st, leg, float(a[0]) + dx, float(a[2]), float(a[1]))
				e.at = [we.x, we.y, we.z]
				e.yaw = float(e.get("yaw", 0.0)) + rad_to_deg(yaw)
	return out


## Adds a piece in the current leg's frame (and fork line).
static func _add(st: Dictionary, p: Dictionary) -> void:
	st.out.append([p, st.leg, st.dx])


# ---------------------------------------------------------------- segments

static func _segment(st: Dictionary, seg: Dictionary) -> void:
	if seg.has("roof"):
		_roof(st, seg)
	elif seg.has("gap"):
		# A running jump: take off just before the edge.
		st.bot.append([st.z + 1.2, "jump", NAN])
		if seg.get("roll", false):
			st.bot.append([st.z, "roll", NAN])
		st.z -= float(seg.gap)
	elif seg.has("wallrun"):
		_wallrun_gap(st, seg)
	elif seg.has("ramp_down") or seg.has("ramp_up"):
		_ramp(st, seg)
	elif seg.has("skip"):
		# Ground the base map already covers (its roof runs on past EXIT).
		st.z -= float(seg.skip)
		st.roof_end = st.z
		# No city drawn over the base's own.
		st.legs[st.leg].start = st.z
	elif seg.has("street"):
		var length: float = seg.street
		st.y = 0.0
		_set_low(st, 0.0)
		st.z -= length
	elif seg.has("turn"):
		_turn(st, seg)
	elif seg.has("fork"):
		_fork(st, seg)
	elif seg.has("join"):
		_join(st, seg)
	else:
		push_warning("Route: unknown segment %s" % seg)


## A roof `length` m long from the cursor, optionally at a new height, with
## its features at distances from the roof's start.
static func _roof(st: Dictionary, seg: Dictionary) -> void:
	var length: float = seg.roof
	if seg.has("y"):
		var rise: float = float(seg.y) - st.y
		if rise > 0.5 and is_equal_approx(st.z, st.roof_end):
			# Straight on from a lower roof: a yellow face to climb (3 m max).
			_add(st, {"box": [0, st.y + rise * 0.5, st.z - 0.15], "size": [WIDTH, rise, 0.3], "kind": "PARKOUR"})
			st.bot.append([st.z + 1.8, "jump", NAN])
		var drop: float = st.y - float(seg.y)
		if drop >= 3.5 and not st.bot.is_empty() and st.bot[-1][1] == "jump":
			# A big drop onto this roof: roll out of it.
			st.bot.append([st.z, "roll", NAN])
		st.y = float(seg.y)
	var z0: float = st.z
	var w: float = seg.get("width", WIDTH)
	if st.y > 0.5:
		_add(st, {"building": [0, st.y, z0 - length * 0.5], "size": [w, length], "look": seg.get("look", st.roof_look)})
	# (At street level, y 0, the street itself is the floor.)
	_height(st, z0, z0 - length)
	_set_low(st, st.y)
	if seg.has("interior"):
		_interior(st, z0, length, w, float(seg.interior))
	var busy: Array = []
	if st.chalk:
		# Courier chalk where each roof starts: orange on the main line,
		# faded on the other line of a fork.
		if st.dx == 0.0:
			_add(st, {"prop": "chalk_arrow", "at": [0, st.y, z0 - 2.5]})
		else:
			_add(st, {"mark": [0, st.y, z0 - 2.5], "size": [1.0, 1.8], "color": "#9a7a62"})
	var after_wallrun: bool = st.get("after_wallrun", false)
	st.after_wallrun = false
	if after_wallrun:
		busy.append([0.0, 14.0])
	for f: Dictionary in seg.get("do", []):
		busy.append(_feature(st, f, z0))
	if not seg.get("bare", false):
		_clutter(st, z0, length, busy)
	st.z = z0 - length
	st.roof_end = st.z


## Walls and a roof over a roof's whole length, `height` m up: the inside
## of a building (a warehouse, an office floor). Gaps in the roof every
## 10 m are skylights.
static func _interior(st: Dictionary, z0: float, length: float, w: float, height: float) -> void:
	var y: float = st.y
	for side: float in [-1.0, 1.0]:
		_add(st, {"box": [side * (w * 0.5 + 0.25), y + height * 0.5, z0 - length * 0.5], "size": [0.5, height, length], "kind": "NEUTRAL", "look": "FACADE"})
	var d := 0.0
	while d < length - 0.5:
		var l := minf(8.0, length - d)
		_add(st, {"box": [0, y + height + 0.25, z0 - d - l * 0.5], "size": [w + 1.0, 0.5, l], "kind": "NEUTRAL", "look": "RUST"})
		d += 10.0


static func _height(st: Dictionary, from_z: float, to_z: float) -> void:
	st.heights.append([from_z, to_z, st.y, st.leg])


static func _set_low(st: Dictionary, y: float) -> void:
	st.lowest = minf(st.lowest, y)


## A corner where the run turns left or right by `angle` degrees (90 or
## 45): a roof `size` m long. A 90 degree corner is a square roof; any
## other is a slab joining the roof before it to the one after, with
## straight outer edges. Everything after it is laid out in a new leg
## turned about the corner's center.
static func _turn(st: Dictionary, seg: Dictionary) -> void:
	if st.fork != null:
		push_error("Route: no corners inside a fork")
		return
	var size: float = seg.get("size", 20.0)
	var dir: Variant = seg.turn
	var left: bool = dir == "left" if dir is String else float(dir) > 0.0
	var angle := deg_to_rad(clampf(float(seg.get("angle", 90.0)), 15.0, 90.0))
	var z0: float = st.z
	var pivot := z0 - size * 0.5
	var turn := angle if left else -angle
	if st.y > 0.5:
		if is_equal_approx(angle, PI * 0.5):
			_add(st, {"building": [0, st.y, pivot], "size": [size, size], "look": seg.get("look", st.roof_look)})
		else:
			# The near edge of the corner (where the last roof ends) and its
			# far edge (where the next one starts), turned by the corner.
			var h := maxf(WIDTH, size) * 0.5
			var b := Basis(Vector3.UP, turn)
			var far_c := Vector3(0, 0, pivot) + b * Vector3(0, 0, -size * 0.5)
			var far_r := b * Vector3(h, 0, 0)
			_add(st, {"slab": [[-h, z0], [h, z0], [far_c.x + far_r.x, far_c.z + far_r.z], [far_c.x - far_r.x, far_c.z - far_r.z]],
				"top": st.y, "look": seg.get("look", st.roof_look)})
	_height(st, z0, z0 - size)
	_set_low(st, st.y)
	# The bot heads for the middle of the corner; it turns there.
	st.bot.append([z0 + 6.0, "", 0.0])
	var o := _world(st, st.leg, 0.0, pivot, 0.0)
	st.legs[st.leg].end = pivot
	st.legs.append({"o": o, "yaw": wrapf(st.legs[st.leg].yaw + turn, -PI, PI), "z0": pivot, "start": pivot})
	st.leg += 1
	st.z = z0 - size
	st.roof_end = st.z


## A fork: a wide roof where the route splits, then `fork` (a list of
## segments) runs as a second line beside the main one, `side` 1 right or
## -1 left, while the main route carries on. `{"join": true}` brings the
## two back together on another wide roof.
static func _fork(st: Dictionary, seg: Dictionary) -> void:
	if st.fork != null:
		push_error("Route: forks can't nest")
		return
	var off: float = float(seg.get("spread", FORK_SPREAD)) * float(seg.get("side", 1.0))
	var plaza: float = seg.get("plaza", PLAZA)
	var start: float = st.z
	_plaza(st, off, plaza)
	var split: float = st.z
	var main_y: float = st.y
	var main_bot: Array = st.bot
	st.bot = []
	st.dx = off
	for s: Dictionary in seg.fork:
		if s.has("turn") or s.has("fork") or s.has("join"):
			push_error("Route: no corners or forks inside a fork's line")
			continue
		if s.has("roof"):
			for f: Dictionary in s.get("do", []):
				if f.has("checkpoint"):
					push_error("Route: checkpoints go on the main line, not in a fork")
		_segment(st, s)
	var alt_bot: Array = []
	for b: Array in st.bot:
		alt_bot.append([b[0], b[1], b[2] + off if not is_nan(b[2]) else NAN])
	st.fork = {"start": start, "off": off, "plaza": plaza, "end": st.z, "y": st.y, "bot": alt_bot,
		"roof_end": st.roof_end}
	st.bot = main_bot
	st.dx = 0.0
	st.z = split
	st.y = main_y
	st.roof_end = split


static func _join(st: Dictionary, seg: Dictionary) -> void:
	var f: Variant = st.fork
	if f == null:
		push_error("Route: join without a fork")
		return
	if not is_equal_approx(st.y, f.y):
		push_error("Route: a fork's lines must end at the same height (%.1f and %.1f)" % [st.y, f.y])
	var end := minf(st.z, f.end)
	if st.z > end:
		_filler(st, st.z, end, 0.0)
	if f.end > end:
		var y: float = st.y
		st.y = f.y
		_filler(st, f.end, end, f.off)
		st.y = y
	st.z = end
	st.roof_end = end
	_plaza(st, f.off, seg.get("plaza", f.plaza))
	var alt: Array = f.bot
	# Over to the other line on the split roof, back on the join roof.
	alt.append([f.start - 2.0, "veer", f.off])
	alt.append([end - 2.0, "veer", 0.0])
	st.forks.append({"from": f.start, "to": end, "bot": alt})
	st.fork = null


## A plain roof on one line of a fork from z `from` to `to`, so both lines
## reach the join together.
static func _filler(st: Dictionary, from: float, to: float, dx: float) -> void:
	if st.y > 0.5:
		st.out.append([{"building": [0, st.y, (from + to) * 0.5], "size": [WIDTH, from - to], "look": st.roof_look}, st.leg, dx])
	_height(st, from, to)


## A roof wide enough for both lines of a fork.
static func _plaza(st: Dictionary, off: float, length: float) -> void:
	var z0: float = st.z
	if st.y > 0.5:
		_add(st, {"building": [off * 0.5, st.y, z0 - length * 0.5], "size": [absf(off) + WIDTH, length], "look": st.roof_look})
	_height(st, z0, z0 - length)
	_set_low(st, st.y)
	st.z = z0 - length
	st.roof_end = st.z


## The alternate bot run: the main steps, with each fork's stretch swapped
## for its other line.
static func _alt_bot(bot: Array, forks: Array) -> Array:
	var out: Array = []
	for b: Array in bot:
		var inside := false
		for f: Dictionary in forks:
			if b[0] < f.from and b[0] > f.to:
				inside = true
		if not inside:
			out.append(b)
	for f: Dictionary in forks:
		out.append_array(f.bot)
	out.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	return out


## A feature on the roof starting at z0. Returns its busy range [from, to]
## in meters from the roof start, so clutter keeps out of it.
static func _feature(st: Dictionary, f: Dictionary, z0: float) -> Array:
	var d: float = f.get("at", 0.0)
	var z := z0 - d
	var y: float = st.y
	if f.has("hurdles"):
		_add(st, {"row": f.get("hurdles", "barricade_jersey") if f.hurdles is String else "barricade_jersey",
			"from": [-5, y, z], "to": [5, y, z], "count": 6})
		st.bot.append([z + 1.6, "jump", NAN])
		return [d - 4.0, d + 3.0]
	if f.has("slide"):
		# A bar 1.1 m up: slide under it. Needs a run-up on the ground.
		_add(st, {"box": [0, y + 1.35, z], "size": [WIDTH, 0.5, 0.6], "kind": "PARKOUR"})
		_add(st, {"box": [-5.8, y + 0.55, z], "size": [0.4, 1.1, 0.6], "kind": "NEUTRAL"})
		_add(st, {"box": [5.8, y + 0.55, z], "size": [0.4, 1.1, 0.6], "kind": "NEUTRAL"})
		st.bot.append([z + 4.5, "crouch", NAN])
		return [d - 6.0, d + 3.0]
	if f.has("hop"):
		# Two short walls on alternate sides: wallrun one, jump to the next.
		var side: float = f.get("side", -1.0)
		_add(st, {"box": [side * 3.0, y + 3.0, z - 4.0], "size": [1, 6, 8], "kind": "WALLRUN"})
		_add(st, {"box": [-side * 3.0, y + 3.0, z - 13.0], "size": [1, 6, 8], "kind": "WALLRUN"})
		_add(st, {"mark": [0, y, z - 8.5], "size": [5, 18], "color": "#d94c40"})
		st.bot.append([z + 8.0, "", 0.0])
		return [d - 2.0, d + 20.0]
	if f.has("window"):
		# A wall across the roof with a low window to slide through at x.
		var wx: float = f.window
		var half := WIDTH * 0.5
		var lo := wx - 1.1
		var hi := wx + 1.1
		_add(st, {"box": [(-half + lo) * 0.5, y + 1.5, z], "size": [lo + half, 3.0, 0.3], "kind": "NEUTRAL"})
		_add(st, {"box": [(hi + half) * 0.5, y + 1.5, z], "size": [half - hi, 3.0, 0.3], "kind": "NEUTRAL"})
		_add(st, {"window": [wx, y, z], "size": [2.2, 1.4]})
		_add(st, {"box": [wx, y + 2.2, z], "size": [2.2, 1.6, 0.3], "kind": "NEUTRAL"})
		st.bot.append([z + 16.0, "", wx])
		st.bot.append([z + 3.0, "crouch", wx])
		st.bot.append([z - 5.0, "", 0.0])
		return [d - 4.0, d + 16.0]
	if f.has("checkpoint"):
		st.checkpoints.append([{"name": f.checkpoint, "at": [0, y, z], "size": [WIDTH + 2.0, 8, 4],
			"objective": f.get("objective", 0)}, st.leg, st.dx])
		return [d - 1.0, d + 1.0]
	if f.has("encounter"):
		return _encounter(st, f, d, z, y)
	if f.has("tape"):
		var x: float = f.get("x", 4.6)
		_add(st, {"tape": [x, y + float(f.get("height", 0.0)), z], "id": f.tape})
		return [d - 2.0, d + 2.0]
	if f.has("radio"):
		var line: Dictionary = (f.radio as Dictionary).duplicate()
		line.at = [0, y, z]
		line.radius = f.get("radius", 7.0)
		st.radio.append([line, st.leg, st.dx])
		return [d, d]
	if f.has("prop"):
		_add(st, {"prop": f.prop, "at": [f.get("x", 0.0), y, z], "yaw": f.get("yaw", 0.0)})
		return [d - 2.0, d + 2.0]
	if f.has("label"):
		_add(st, {"label": f.label, "at": [0, y + 3.0, z], "size": f.get("size", 0.8)})
		return [d, d]
	if f.has("mark"):
		_add(st, {"mark": [0, y, z], "size": [WIDTH, 0.8], "color": f.mark})
		return [d, d]
	if f.has("piece"):
		# Any mission piece in the roof's frame: x across, y up from the
		# roof, z from this spot (negative is further along the run).
		var piece: Dictionary = (f.piece as Dictionary).duplicate(true)
		for k: String in POINT_KEYS:
			var a: Variant = piece.get(k, null)
			if a is Array and a.size() >= 3:
				piece[k] = [float(a[0]), y + float(a[1]), z + float(a[2])]
		_add(st, piece)
		var reach: float = f.get("length", 6.0)
		return [d - 2.0, d + reach]
	if f.has("lane"):
		# Where the bot should run from here (the player can go anywhere).
		st.bot.append([z, "", float(f.lane)])
		return [d, d]
	push_warning("Route: unknown feature %s" % f)
	return [d, d]


## Enemies on a roof: raiders behind sandbags, mutants on their patch, and
## any other kind by type ("troopers" behind sandbags like raiders,
## "drones" hovering `height` m up; MissionBuilder spawns each type it has
## a script for).
static func _encounter(st: Dictionary, f: Dictionary, d: float, z: float, y: float) -> Array:
	var raiders: Array = []
	var cover: Array = []
	var others: Array = []
	for kind: String in ["raiders", "troopers"]:
		for r: Array in f.get(kind, []):
			var rz := z - float(r[1])
			var e := {"at": [r[0], y, rz], "yaw": 180, "wake": r[2] if r.size() > 2 else 0.0}
			if kind == "raiders":
				raiders.append(e)
			else:
				e.type = "trooper"
				others.append(e)
			cover.append({"at": [r[0], y, rz + 3.0], "length": 2.0})
			_add(st, {"prop": "sandbag_wall", "at": [r[0], y, rz + 3.0]})
			if absf(float(r[0])) < 2.5:
				# Sandbags in the lane: vault them.
				st.bot.append([rz + 4.6, "jump", NAN])
	var mutants: Array = []
	for m: Array in f.get("mutants", []):
		mutants.append({"at": [m[0], y, z - float(m[1])], "yaw": 180, "leash_radius": 14, "aggro_radius": 12})
	for dr: Array in f.get("drones", []):
		others.append({"type": "drone", "at": [dr[0], y, z - float(dr[1])], "yaw": 180,
			"hover_height": float(dr[2]) if dr.size() > 2 else 4.0})
	# Any type: {"type", "x", "d", "wake", "height"} plus enemy settings.
	for spec: Dictionary in f.get("enemies", []):
		var type: String = spec.get("type", "raider")
		var ez := z - float(spec.get("d", 0.0))
		var ex: float = spec.get("x", 0.0)
		var e := {"type": type, "at": [ex, y, ez], "yaw": 180, "wake": spec.get("wake", 0.0)}
		for k: String in spec:
			if k not in ["type", "x", "d", "wake", "height", "cover"]:
				e[k] = spec[k]
		if type.ends_with("drone"):
			e.hover_height = float(spec.get("height", 4.0))
		if type in LEASHED_TYPES:
			if not e.has("leash_radius"):
				e.leash_radius = 14
			if not e.has("aggro_radius"):
				e.aggro_radius = 12
		if spec.get("cover", type in COVER_TYPES):
			cover.append({"at": [ex, y, ez + 3.0], "length": 2.0})
			_add(st, {"prop": "sandbag_wall", "at": [ex, y, ez + 3.0]})
			if absf(ex) < 2.5:
				st.bot.append([ez + 4.6, "jump", NAN])
		others.append(e)
	var length: float = f.get("length", 40.0)
	var piece := {"encounter": f.encounter, "area": {"at": [0, y + 4.0, z - length * 0.5], "size": [WIDTH, 10, length]},
		"raiders": raiders, "mutants": mutants, "cover": cover}
	if not others.is_empty():
		piece.enemies = others
	_add(st, piece)
	return [d, d + length]


## A gap too wide to jump, with a wallrun panel along it. Approach on that
## side, jump at the edge, run the wall across.
static func _wallrun_gap(st: Dictionary, seg: Dictionary) -> void:
	var gap: float = seg.wallrun
	var side: float = seg.get("side", 1.0)
	var edge: float = st.z
	var y: float = st.y
	_add(st, {"box": [side * WALL_X, y + 2.5, edge - gap * 0.5], "size": [1, 9, gap + 6.0], "kind": "WALLRUN"})
	# A low lip on the far side so nobody runs off it by mistake.
	_add(st, {"box": [-side * 5.8, y + 0.4, edge + 4.0], "size": [0.4, 0.8, 8], "kind": "NEUTRAL"})
	st.bot.append([edge + 24.0, "", side * 3.3])
	st.bot.append([edge + 10.0, "", side * 5.4])
	st.bot.append([edge + 0.7, "jump", side * 7.0])
	st.bot.append([edge - gap - 4.0, "", 0.0])
	st.after_wallrun = true
	st.z = edge - gap


## A ramp from this level down (or up) to the next: `{"ramp_down": to_y,
## "length": 24}`. Down is a slide ramp: crouch onto it for speed.
static func _ramp(st: Dictionary, seg: Dictionary) -> void:
	var down := seg.has("ramp_down")
	var to_y: float = seg.ramp_down if down else seg.ramp_up
	var length: float = seg.get("length", absf(st.y - to_y) * 2.4)
	var top_y: float = st.y if down else to_y
	var bottom_y: float = to_y if down else st.y
	var top_z: float = st.z if down else st.z - length
	var bottom_z: float = st.z - length if down else st.z
	_add(st, {"ramp": [0, top_y, top_z], "to": [0, bottom_y, bottom_z], "width": seg.get("width", 6.0),
		"kind": "SLIDE" if down else "SURFACE"})
	st.y = to_y
	_set_low(st, minf(top_y, bottom_y))
	st.z -= length


## Edge clutter on a roof: a prop every ~12 m, alternating sides, never in
## the last stretch before the edge (run-ups) or near a feature.
static func _clutter(st: Dictionary, z0: float, length: float, busy: Array) -> void:
	var rng: RandomNumberGenerator = st.rng
	var d := 8.0
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	while d < length - 26.0:
		var free := true
		for b: Array in busy:
			if d > b[0] - 5.0 and d < b[1] + 5.0:
				free = false
		if free:
			var list: Array = st.clutter
			var prop: String = list[rng.randi() % list.size()]
			_add(st, {"prop": prop, "at": [side * rng.randf_range(4.7, 5.2), st.y, z0 - d], "yaw": rng.randf_range(0.0, 360.0)})
			side = -side
		d += rng.randf_range(10.0, 15.0)


# ---------------------------------------------------------------- the city

## World rectangles (x, z) the route's roofs and ramps cover. The street and
## skyline are fitted around them.
static func _footprints(pieces: Array) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for p: Dictionary in pieces:
		if p.has("building"):
			var s: Array = _turn_size([p.size[0], 0, p.size[1]], deg_to_rad(float(p.get("yaw", 0.0))))
			var c: Array = p.building
			out.append(Rect2(c[0] - s[0] * 0.5, c[2] - s[2] * 0.5, s[0], s[2]))
		elif p.has("slab"):
			var r := Rect2(p.slab[0][0], p.slab[0][1], 0, 0)
			for a: Array in p.slab:
				r = r.expand(Vector2(a[0], a[1]))
			out.append(r)
		elif p.has("ramp"):
			var r := Rect2(p.ramp[0], p.ramp[2], 0, 0).expand(Vector2(p.to[0], p.to[2]))
			out.append(r.grow(3.0))
	return out


static func _bounds(pieces: Array, st: Dictionary) -> Rect2:
	var o: Vector3 = st.legs[0].o
	var r := Rect2(o.x, o.z, 0, 0)
	for f: Rect2 in _footprints(pieces):
		r = r.merge(f)
	# Street-level stretches have no roofs: the run itself counts too.
	for i in st.legs.size():
		var l: Dictionary = st.legs[i]
		for z: float in [l.start, l.get("end", st.z)]:
			var w := _world(st, i, 0.0, z, 0.0)
			r = r.expand(Vector2(w.x, w.z))
	st.footprints = _footprints(pieces)
	return r


## The city around the route: buildings along both sides of every leg,
## kept clear of the route itself (corners and forks included).
static func _skyline(st: Dictionary, mission: Dictionary) -> void:
	if mission.get("skyline", true) == false:
		return
	var rng: RandomNumberGenerator = st.rng
	var taken: Array[Rect2] = []
	for f: Rect2 in st.footprints:
		taken.append(f.grow(3.0))
	for leg in st.legs.size():
		var l: Dictionary = st.legs[leg]
		var from: float = l.start + (4.0 if leg == 0 and not mission.has("base") else 0.0)
		var to: float = l.end - (20.0 if leg == st.legs.size() - 1 else 0.0)
		for side: float in [-1.0, 1.0]:
			var z := from
			while z > to:
				var depth := rng.randf_range(12.0, 22.0)
				var wid := rng.randf_range(10.0, 16.0)
				var x := side * (16.0 + wid * 0.5 + rng.randf_range(0.0, 10.0))
				var h := maxf(4.0, _height_at(st, leg, z - depth * 0.5) + rng.randf_range(-6.0, 18.0))
				var c := _world(st, leg, x, z - depth * 0.5, h)
				var s: Array = _turn_size([wid, 0, depth], l.yaw)
				var rect := Rect2(c.x - s[0] * 0.5, c.z - s[2] * 0.5, s[0], s[2])
				var clear := true
				for t: Rect2 in taken:
					if t.intersects(rect):
						clear = false
						break
				if clear:
					taken.append(rect)
					mission.pieces.append({"building": [c.x, h, c.z], "size": [wid, depth], "yaw": rad_to_deg(l.yaw)})
					if rng.randf() < 0.15:
						mission.pieces.append({"prop": "billboard" if rng.randf() < 0.5 else "antenna_mast", "at": [c.x, h, c.z], "yaw": -90.0 * side + rad_to_deg(l.yaw)})
				z -= depth + rng.randf_range(2.0, 14.0)


static func _height_at(st: Dictionary, leg: int, z: float) -> float:
	var y: float = st.y
	for r: Array in st.heights:
		if r[3] != leg:
			continue
		if z <= r[0] + 20.0:
			y = r[2]
		if z >= r[1] - 20.0 and z <= r[0] + 20.0:
			return r[2]
	return y
