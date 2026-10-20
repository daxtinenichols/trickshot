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

const City := preload("res://campaign/city.gd")
const Atlas := preload("res://campaign/atlas.gd")
const PROP_KIT := "res://art/props/prop_kit.gd"

## Roof width; the running lane is its middle.
const WIDTH := 12.0
## Wallrun panels stand just outside the roof edge.
const WALL_X := 6.5
## How far apart the two lines of a fork run (center to center).
const FORK_SPREAD := WIDTH + 6.0
## Length of the wide roof where a fork splits or joins.
const PLAZA := 28.0
## A bridge deck's thickness and the distance between its piers.
const BRIDGE_DECK := 1.0
const BRIDGE_SPAN := 30.0
## Clutter that sits at roof edges, out of the lane.
const CLUTTER := ["ac_unit", "vent_stack", "satellite_dish", "generator", "barrel_rust",
	"crate_wood", "tire_stack", "crate_stack", "antenna_mast", "loudspeaker_pole"]
## Piece fields that hold a position.
const POINT_KEYS := ["box", "building", "mark", "window", "ramp", "to", "from", "tape", "at", "fire", "spawn",
	"bank", "quarter_pipe", "loop", "door", "doors", "target", "trigger"]
## Pieces that turn with their leg (they take a yaw).
const TURNING_KEYS := ["box", "building", "prop", "row", "mark", "window", "bank", "quarter_pipe", "loop", "door",
	"doors", "figure", "set_piece"]
## Ways through a wall across the run. Glass to jump through: a pane from
## a sill at vault height to well over head height, so a jump at any point
## of its arc goes through standing up.
const GLASS_WIDTH := 3.0
const GLASS_SILL := 0.8
const GLASS_TOP := 3.4
## Where the bot jumps for the glass (meters before the wall).
const GLASS_JUMP := 3.5
## A hole to slide through: too low to run through (the slide is 1 m tall).
const HOLE_WIDTH := 2.4
const HOLE_TOP := 1.3
## Double doors to kick: the opening, and where the bot kicks (the kick
## reaches 2 m from the eye).
const DOORS_WIDTH := 2.2
const DOORS_TOP := 2.2
const KICK_AT := 1.9
## A balustrade along a void indoors ("open" on an interior roof).
const RAIL_H := 1.1
## A wall across an open roof is this tall; indoors it meets the ceiling.
const OUTDOOR_WALL := 3.5
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
		"rng": RandomNumberGenerator.new(), "lowest": INF, "roof_end": 6.0, "lanes": [], "clutter": mission.get("clutter", CLUTTER),
		# Legs: the frame each stretch between corners is laid out in.
		"legs": [{"o": origin.origin, "yaw": origin.yaw, "z0": 0.0, "start": 6.0}],
		"leg": 0, "dx": 0.0, "fork": null, "forks": [], "ledges": [],
		"chalk": mission.get("chalk", false),
		"roof_look": mission.get("roof_look", "FACADE"),
		# The walls of interiors ("interior_look": a mall's plastered
		# concourses want NEUTRAL, a warehouse the default).
		"wall_look": mission.get("interior_look", "FACADE"),
		# The roof being laid out: its width and how high its ceiling is
		# (0 outdoors).
		"roof_w": WIDTH, "inside": 0.0,
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
	var ground := bounds.grow(70.0)
	if not mission.has("no_floor"):
		var top := -0.02 if mission.has("base") else 0.0
		pieces.push_front({"box": [ground.get_center().x, top - 0.5, ground.get_center().y], "size": [ground.size.x, 1, ground.size.y], "kind": "FLOOR"})
	if mission.get("skyline", true) != false:
		var atlas: bool = mission.get("atlas", false)
		if atlas:
			Atlas.before_city(mission, ground)
		var first: int = mission.pieces.size()
		var lanes := _lane_areas(st)
		City.build(mission, lanes, ground, String(mission.get("id", "route")))
		_clear_streets(st, mission, first)
		if atlas:
			Atlas.after_city(mission, first, ground, bounds, lanes)
	if not mission.has("fail_y"):
		mission.fail_y = st.lowest - 5.5 if st.lowest > 6.0 else -20.0
	if mission.get("skyline", true) != false:
		_pits(st, mission)
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

## "trick": "flip" | "front" | "spin" on a gap or wallrun: the bot does it
## in the air after the jump it just took.
static func _trick(st: Dictionary, seg: Dictionary) -> void:
	if seg.has("trick"):
		st.bot.append([float(st.bot[-1][0]) - 0.01, String(seg.trick), NAN])


static func _segment(st: Dictionary, seg: Dictionary) -> void:
	if seg.has("roof"):
		_roof(st, seg)
	elif seg.has("gap"):
		# A running jump: take off "takeoff" m before the edge (1.2 by default).
		st.bot.append([st.z + float(seg.get("takeoff", 1.2)), "jump", NAN])
		_trick(st, seg)
		if seg.get("roll", false):
			st.bot.append([st.z, "roll", NAN])
		_lane(st, st.z, st.z - float(seg.gap), WIDTH)
		if seg.has("interior"):
			# Indoors: walls and ceiling carry on over the hole in the floor.
			var h := float(seg.interior)
			var gz: float = st.z - float(seg.gap) * 0.5
			_add(st, {"box": [0, st.y + h + 0.25, gz], "size": [WIDTH + 1.0, 0.5, float(seg.gap)], "kind": "NEUTRAL", "look": "RUST"})
			for side: float in [-1.0, 1.0]:
				_add(st, {"box": [side * (WIDTH * 0.5 + 0.25), st.y + h * 0.5, gz], "size": [0.5, h, float(seg.gap)], "kind": "NEUTRAL", "look": st.wall_look})
		if seg.has("gate") and seg.get("lower", "ledge") != "fall":
			# A speed gate's miss lands on its ledge, not in a pit.
			st.ledges.append([st.leg, st.dx, st.z, st.z - float(seg.gap)])
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
		_lane(st, st.z, st.z - length, WIDTH)
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
			# 2 cm proud of the wall and just inside its top and sides, so
			# the two looks never share a plane (they flickered).
			_add(st, {"box": [0, st.y + (rise - 0.02) * 0.5, st.z - 0.13], "size": [WIDTH - 0.04, rise - 0.02, 0.3], "kind": "PARKOUR"})
			st.bot.append([st.z + 1.8, "jump", NAN])
		var drop: float = st.y - float(seg.y)
		if drop >= 3.5 and not st.bot.is_empty() and st.bot[-1][1] == "jump":
			# A big drop onto this roof: roll out of it.
			st.bot.append([st.z, "roll", NAN])
		st.y = float(seg.y)
	var z0: float = st.z
	var w: float = seg.get("width", WIDTH)
	if seg.get("bridge", false):
		_bridge(st, z0, length, w, float(seg.get("beyond", 0.0)))
	elif st.y > 0.5 and seg.get("building", true):
		# ("building": false: a roof of something already there, like an
		# atlas landmark the level runs over.)
		_add(st, {"building": [0, st.y, z0 - length * 0.5], "size": [w, length], "look": seg.get("look", st.roof_look)})
	# (At street level, y 0, the street itself is the floor.)
	_lane(st, z0, z0 - length, w)
	_set_low(st, st.y)
	st.roof_w = w
	# Indoors (walls and a ceiling this high): from "interior", or
	# "indoors" when the mission builds its own walls and ceiling.
	st.inside = float(seg.get("interior", seg.get("indoors", 0.0)))
	if seg.has("interior"):
		_interior(st, z0, length, w, float(seg.interior), float(seg.get("open", 0.0)))
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
	if not seg.get("bare", false) and not seg.get("bridge", false):
		_clutter(st, z0, length, busy)
	st.inside = 0.0
	st.roof_w = WIDTH
	st.z = z0 - length
	st.roof_end = st.z


## A bridge deck instead of a building: a concrete slab on piers with
## steel girders under its edges and railings along them. `beyond` m more
## of the span carry on past the segment's end (the far side of the bridge,
## seen but not run).
static func _bridge(st: Dictionary, z0: float, length: float, w: float, beyond: float) -> void:
	var y: float = st.y
	var total := length + beyond
	var mid := z0 - total * 0.5
	_add(st, {"box": [0, y - BRIDGE_DECK * 0.5, mid], "size": [w, BRIDGE_DECK, total], "kind": "NEUTRAL", "footprint": true})
	for side: float in [-1.0, 1.0]:
		_add(st, {"box": [side * (w * 0.5 - 0.8), y - BRIDGE_DECK - 0.6, mid], "size": [0.6, 1.2, total], "kind": "NEUTRAL", "look": "RUST"})
		var x := side * (w * 0.5 - 0.3)
		_add(st, {"row": "railing", "from": [x, y, z0 - 1.0], "to": [x, y, z0 - total + 1.0],
			"count": maxi(int(total / 2.0), 2), "yaw": 90.0})
	# Piers every BRIDGE_SPAN m down to the street.
	var d := BRIDGE_SPAN * 0.5
	while d < total:
		_add(st, {"box": [0, (y - BRIDGE_DECK - 1.2) * 0.5, z0 - d], "size": [w * 0.5, y - BRIDGE_DECK - 1.2, 2.4], "kind": "NEUTRAL"})
		d += BRIDGE_SPAN


## Walls and a roof over a roof's whole length, `height` m up: the inside
## of a building (a warehouse, an office floor). Gaps in the roof every
## 10 m are skylights. `open` 1 (right) or -1 (left) leaves that wall out
## for a balustrade over a void (a mall atrium the mission builds itself).
static func _interior(st: Dictionary, z0: float, length: float, w: float, height: float, open := 0.0) -> void:
	var y: float = st.y
	for side: float in [-1.0, 1.0]:
		if side == open:
			_add(st, {"box": [side * (w * 0.5 - 0.6), y + RAIL_H * 0.5, z0 - length * 0.5], "size": [0.2, RAIL_H, length], "kind": "NEUTRAL", "look": "RUST"})
			continue
		_add(st, {"box": [side * (w * 0.5 + 0.25), y + height * 0.5, z0 - length * 0.5], "size": [0.5, height, length], "kind": "NEUTRAL", "look": st.wall_look})
	var d := 0.0
	while d < length - 0.5:
		var l := minf(8.0, length - d)
		_add(st, {"box": [0, y + height + 0.25, z0 - d - l * 0.5], "size": [w + 1.0, 0.5, l], "kind": "NEUTRAL", "look": "RUST"})
		d += 10.0


## Records a stretch of the course (z from, to; width w; x across) on the
## current leg and line at the current height, for the city to keep clear.
static func _lane(st: Dictionary, from_z: float, to_z: float, w: float, x := 0.0, dx: float = NAN, low: float = NAN) -> void:
	st.lanes.append([st.leg, (st.dx if is_nan(dx) else dx) + x, from_z, to_z, w, st.y, st.y if is_nan(low) else low])


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
	# The near edge of a corner that isn't square (where the last roof
	# ends) and its far edge (where the next one starts), turned by the
	# corner.
	var h := maxf(WIDTH, size) * 0.5
	var b := Basis(Vector3.UP, turn)
	var far_c := Vector3(0, 0, pivot) + b * Vector3(0, 0, -size * 0.5)
	var far_r := b * Vector3(h, 0, 0)
	var quad := [[-h, z0], [h, z0], [far_c.x + far_r.x, far_c.z + far_r.z], [far_c.x - far_r.x, far_c.z - far_r.z]]
	var square := is_equal_approx(angle, PI * 0.5)
	if st.y > 0.5:
		if square:
			_add(st, {"building": [0, st.y, pivot], "size": [size, size], "look": seg.get("look", st.roof_look)})
		else:
			_add(st, {"slab": quad, "top": st.y, "look": seg.get("look", st.roof_look)})
	_lane(st, z0, z0 - size, maxf(WIDTH, size))
	if not square:
		# The city fits the corner's own outline, not a square round it.
		st.lanes[-1].append(quad)
	_set_low(st, st.y)
	if seg.has("interior"):
		_corner_interior(st, quad, pivot, turn, h, float(seg.interior), square, left)
	# The bot heads for the middle of the corner; it turns there.
	st.bot.append([z0 + 6.0, "", 0.0])
	var o := _world(st, st.leg, 0.0, pivot, 0.0)
	st.legs[st.leg].end = pivot
	st.legs.append({"o": o, "yaw": wrapf(st.legs[st.leg].yaw + turn, -PI, PI), "z0": pivot, "start": pivot})
	st.leg += 1
	st.z = z0 - size
	st.roof_end = st.z


## Walls and a ceiling `height` m up over a corner indoors: the outside of
## the bend is walled (the far side and the side turned away from), the
## ceiling a box turned half way round the bend, wide enough to meet the
## walls of the roofs either side.
static func _corner_interior(st: Dictionary, quad: Array, pivot: float, turn: float, h: float, height: float, square: bool, left: bool) -> void:
	var y: float = st.y
	var top := y + height + 0.25
	var walls: Array = []
	if square:
		var s := 1.0 if left else -1.0
		walls.append([[-h, pivot - h], [h, pivot - h]])
		walls.append([[s * h, pivot + h], [s * h, pivot - h]])
	else:
		# The outer edge of the bend and the short inner one.
		var outer := 0 if left else 1
		walls.append([quad[outer], quad[3 - outer]])
		walls.append([quad[1 - outer], quad[2 + outer]])
	for wl: Array in walls:
		var a := Vector2(wl[0][0], wl[0][1])
		var b := Vector2(wl[1][0], wl[1][1])
		var n := (b - a).orthogonal().normalized() * 0.25
		# Push each wall out of the floor's edge, away from its middle.
		var mid := (a + b) * 0.5
		if (mid + n - Vector2(0, pivot)).length() < (mid - Vector2(0, pivot)).length():
			n = -n
		var c := mid + n
		if (b - a).length() > 0.5:
			_add(st, {"box": [c.x, y + height * 0.5, c.y], "size": [0.5, height, (b - a).length() + 0.5],
				"yaw": rad_to_deg(atan2(b.x - a.x, b.y - a.y)), "kind": "NEUTRAL", "look": st.wall_look})
	_add(st, {"box": [0, top, pivot], "size": [h * 2.0 + 4.0, 0.5, h * 2.0 + 4.0],
		"yaw": rad_to_deg(turn * 0.5), "kind": "NEUTRAL", "look": "RUST"})


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
	st.hall = float(seg.get("interior", 0.0))
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
	st.hall = 0.0


## A plain roof on one line of a fork from z `from` to `to`, so both lines
## reach the join together.
static func _filler(st: Dictionary, from: float, to: float, dx: float) -> void:
	if st.y > 0.5:
		st.out.append([{"building": [0, st.y, (from + to) * 0.5], "size": [WIDTH, from - to], "look": st.roof_look}, st.leg, dx])
	var hall: float = st.get("hall", 0.0)
	if hall > 0.0:
		st.out.append([{"box": [0, st.y + hall + 0.25, (from + to) * 0.5], "size": [WIDTH + 1.0, 0.5, from - to], "kind": "NEUTRAL", "look": "RUST"}, st.leg, dx])
	_lane(st, from, to, WIDTH, 0.0, dx)


## A roof wide enough for both lines of a fork.
static func _plaza(st: Dictionary, off: float, length: float) -> void:
	var z0: float = st.z
	if st.y > 0.5:
		_add(st, {"building": [off * 0.5, st.y, z0 - length * 0.5], "size": [absf(off) + WIDTH, length], "look": st.roof_look})
	var hall: float = st.get("hall", 0.0)
	if hall > 0.0:
		# A fork indoors ("interior" on the fork): walls round the wide
		# floor and a ceiling over it.
		var w := absf(off) + WIDTH
		for side: float in [-1.0, 1.0]:
			_add(st, {"box": [off * 0.5 + side * (w * 0.5 + 0.25), st.y + hall * 0.5, z0 - length * 0.5], "size": [0.5, hall, length], "kind": "NEUTRAL", "look": st.wall_look})
		_add(st, {"box": [off * 0.5, st.y + hall + 0.25, z0 - length * 0.5], "size": [w + 1.0, 0.5, length], "kind": "NEUTRAL", "look": "RUST"})
	_lane(st, z0, z0 - length, absf(off) + WIDTH, off * 0.5)
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
		var hurdle: String = f.hurdles if f.hurdles is String else "barricade_jersey"
		# Wall to wall; pieces too wide to sit side by side step back and
		# forth instead of running into each other.
		var size: Vector3 = load(PROP_KIT).size_of(hurdle)
		var n := clampi(ceili(12.0 / size.x - 0.01), 2, 8)
		var step := (12.0 - size.x) / (n - 1)
		for i in n:
			var stagger := 0.0 if step >= size.x - 0.01 else (size.z + 0.05 if i % 2 == 1 else 0.0)
			_add(st, {"prop": hurdle, "at": [-6.0 + size.x * 0.5 + step * i, y, z - stagger]})
		# "lead": how far before them the bot jumps (further when it's fast).
		st.bot.append([z + float(f.get("lead", 1.6)), "jump", NAN])
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
		# A hair over the city's road lines, which it would flicker with.
		_add(st, {"mark": [0, y + 0.003, z - 8.5], "size": [5, 18], "color": "#d94c40"})
		st.bot.append([z + 8.0, "", 0.0])
		return [d - 2.0, d + 20.0]
	if f.has("glass"):
		# Glass to jump through, in a wall across the room. Indoors only:
		# glass belongs in a building (an office partition, a storefront).
		var gx: float = f.glass
		if st.inside <= 0.0:
			push_warning("Route: glass at %s m is on an open roof; give the roof an \"interior\"" % d)
		_cross_wall(st, z, gx, GLASS_WIDTH, GLASS_SILL, GLASS_TOP, f.get("look", "TILE"))
		_add(st, {"window": [gx, y + GLASS_SILL, z], "size": [GLASS_WIDTH, GLASS_TOP - GLASS_SILL]})
		st.bot.append([z + 16.0, "", gx])
		st.bot.append([z + GLASS_JUMP, "jump", gx])
		st.bot.append([z - 5.0, "", 0.0])
		return [d - 4.0, d + 16.0]
	if f.has("door"):
		# Double doors in a wall across the room: kick one and both swing
		# open away from you. No slowing down if you kick in time.
		var dx: float = f.door
		if f.has("glass"):
			# And a window beside them in the same wall: kick the door or
			# jump the glass.
			_cross_wall2(st, z, [[dx, DOORS_WIDTH, 0.0, DOORS_TOP], [float(f.glass), GLASS_WIDTH, GLASS_SILL, GLASS_TOP]], f.get("look", "FACADE"))
			_add(st, {"window": [float(f.glass), y + GLASS_SILL, z], "size": [GLASS_WIDTH, GLASS_TOP - GLASS_SILL]})
		else:
			_cross_wall(st, z, dx, DOORS_WIDTH, 0.0, DOORS_TOP, f.get("look", "FACADE"))
		_add(st, {"doors": [dx, y, z]})
		st.bot.append([z + 16.0, "", dx])
		st.bot.append([z + KICK_AT, "kick", dx])
		st.bot.append([z - 5.0, "", 0.0])
		return [d - 4.0, d + 16.0]
	if f.has("hole") or f.has("window"):
		# A gap to slide through, as something that belongs where it is
		# (see _hole). "window" is the old name.
		var hx: float = f.get("hole", f.get("window", 0.0))
		var style: String = f.get("style", "broken" if st.inside > 0.0 else "fence")
		_hole(st, z, hx, style)
		st.bot.append([z + 16.0, "", hx])
		st.bot.append([z + 3.0, "crouch", hx])
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
	if f.has("set_piece"):
		return _set_piece(st, f, d, z, z0, y)
	if f.has("lane"):
		# Where the bot should run from here (the player can go anywhere).
		st.bot.append([z, "", float(f.lane)])
		return [d, d]
	push_warning("Route: unknown feature %s" % f)
	return [d, d]


## A chase set piece (campaign/set_piece.gd) at `at` m along the roof, `x`
## across (`up` above it), fired when you reach `trigger` m along it: {"set_piece":
## "debris", "as": "slide"}, "host" ("gap"), "blast" ("size") or "mast"
## ("height", "fall_yaw"). A fallen beam is an obstacle, so the bot slides
## under or jumps it.
static func _set_piece(st: Dictionary, f: Dictionary, d: float, z: float, z0: float, y: float) -> Array:
	var sp := {}
	for k: String in f:
		if k not in ["at", "trigger", "x", "up", "trigger_x"]:
			sp[k] = f[k]
	sp.at = [float(f.get("x", 0.0)), y + float(f.get("up", 0.0)), z]
	sp.trigger = [float(f.get("trigger_x", 0.0)), y + 1.0, z0 - float(f.get("trigger", d - 26.0))]
	_add(st, sp)
	if f.set_piece == "debris":
		if f.get("as", "hurdle") == "slide":
			st.bot.append([z + 4.5, "crouch", NAN])
			return [d - 6.0, d + 3.0]
		st.bot.append([z + 1.6, "jump", NAN])
		return [d - 4.0, d + 3.0]
	if f.set_piece == "mast":
		return [d - 3.0, d + 3.0]
	return [d, d]


## A wall across the roof at z with an opening at x, `width` wide, from
## `lo` to `hi` m up (whatever fills it is the caller's). Indoors it meets
## the ceiling; on an open roof it is OUTDOOR_WALL tall. Returns the piece
## over the opening.
static func _cross_wall(st: Dictionary, z: float, x: float, width: float, lo: float, hi: float, look: String) -> Dictionary:
	var y: float = st.y
	var h: float = st.inside if st.inside > 0.0 else OUTDOOR_WALL
	var half: float = st.roof_w * 0.5
	var a := x - width * 0.5
	var b := x + width * 0.5
	_add(st, {"box": [(-half + a) * 0.5, y + h * 0.5, z], "size": [a + half, h, 0.3], "kind": "NEUTRAL", "look": look})
	_add(st, {"box": [(b + half) * 0.5, y + h * 0.5, z], "size": [half - b, h, 0.3], "kind": "NEUTRAL", "look": look})
	if lo > 0.01:
		_add(st, {"box": [x, y + lo * 0.5, z], "size": [width, lo, 0.3], "kind": "NEUTRAL", "look": look})
	var over := {"box": [x, y + (hi + h) * 0.5, z], "size": [width, h - hi, 0.3], "kind": "NEUTRAL", "look": look}
	_add(st, over)
	return over


## A wall across the roof at z with several openings [x, width, lo, hi]
## (left to right, not overlapping).
static func _cross_wall2(st: Dictionary, z: float, openings: Array, look: String) -> void:
	var y: float = st.y
	var h: float = st.inside if st.inside > 0.0 else OUTDOOR_WALL
	var half: float = st.roof_w * 0.5
	openings.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var left := -half
	for o: Array in openings:
		var a: float = float(o[0]) - float(o[1]) * 0.5
		var b: float = float(o[0]) + float(o[1]) * 0.5
		if a - left > 0.01:
			_add(st, {"box": [(left + a) * 0.5, y + h * 0.5, z], "size": [a - left, h, 0.3], "kind": "NEUTRAL", "look": look})
		if float(o[2]) > 0.01:
			_add(st, {"box": [o[0], y + float(o[2]) * 0.5, z], "size": [o[1], o[2], 0.3], "kind": "NEUTRAL", "look": look})
		_add(st, {"box": [o[0], y + (float(o[3]) + h) * 0.5, z], "size": [o[1], h - float(o[3]), 0.3], "kind": "NEUTRAL", "look": look})
		left = b
	if half - left > 0.01:
		_add(st, {"box": [(left + half) * 0.5, y + h * 0.5, z], "size": [half - left, h, 0.3], "kind": "NEUTRAL", "look": look})


## A gap HOLE_TOP high to slide through at x, in one of these styles:
##   indoors: "broken" (a hole knocked through a brick wall), "shutter"
##     (a roll-up shutter jammed part way down a loading door)
##   outdoors: "fence" (a raider hoarding across the roof with its bottom
##     sheet torn out), "duct" (a big air duct across the roof on legs),
##     "wagon" (a derailed goods wagon lying across the tracks)
## The piece over the gap carries meta "opening" (the style) for shots.
static func _hole(st: Dictionary, z: float, x: float, style: String) -> void:
	var y: float = st.y
	var half: float = st.roof_w * 0.5
	var tag := {"opening": style, "floor": y}
	match style:
		"shutter":
			# A loading door 3.4 m wide in a concrete wall, its shutter down
			# to HOLE_TOP, with the roller box over it.
			var over := _cross_wall(st, z, x, 3.4, 0.0, 3.0, "FACADE")
			over.meta = tag
			_add(st, {"box": [x, y + (HOLE_TOP + 3.0) * 0.5, z - 0.22], "size": [3.4, 3.0 - HOLE_TOP, 0.08], "kind": "NEUTRAL", "look": "CORRUGATED"})
			_add(st, {"box": [x, y + 3.0 - 0.2, z - 0.35], "size": [3.6, 0.4, 0.4], "kind": "NEUTRAL", "look": "RUST"})
			_add(st, {"box": [x, y + HOLE_TOP + 0.05, z - 0.22], "size": [3.4, 0.1, 0.14], "kind": "NEUTRAL", "look": "RUST"})
		"duct":
			# Square sheet-metal duct on legs, end to end across the roof,
			# with a leg either side of the gap so it reads as the way under.
			_add(st, {"box": [0, y + HOLE_TOP + 0.55, z], "size": [half * 2.0, 1.1, 1.3], "kind": "NEUTRAL", "look": "CORRUGATED", "meta": tag})
			for lx: float in [x - HOLE_WIDTH * 0.5 - 0.15, x + HOLE_WIDTH * 0.5 + 0.15]:
				if absf(lx) < half - 1.4:
					_add(st, {"box": [lx, y + HOLE_TOP * 0.5, z], "size": [0.25, HOLE_TOP, 0.9], "kind": "NEUTRAL", "look": "RUST"})
			# It comes up out of the roof at the end away from the gap, on a
			# leg at the other.
			var riser := -1.0 if x > 0.0 else 1.0
			_add(st, {"box": [riser * (half - 0.65), y + 1.2, z], "size": [1.3, 2.4, 1.3], "kind": "NEUTRAL", "look": "RUST"})
			_add(st, {"box": [-riser * (half - 0.4), y + HOLE_TOP * 0.5, z], "size": [0.25, HOLE_TOP, 0.25], "kind": "NEUTRAL", "look": "RUST"})
		"wagon":
			# A goods wagon on its side across the line, its body held off
			# the deck by the bogies at its ends.
			_add(st, {"box": [0, y + HOLE_TOP + 1.4, z], "size": [half * 2.0 + 1.0, 2.8, 2.9], "kind": "NEUTRAL", "look": "CORRUGATED", "meta": tag})
			# Its chassis along the bottom edge.
			_add(st, {"box": [0, y + HOLE_TOP + 0.15, z + 1.2], "size": [half * 2.0 + 1.0, 0.3, 0.5], "kind": "NEUTRAL", "look": "RUST"})
			for side: float in [-1.0, 1.0]:
				var bx := side * (half - 0.4)
				if absf(bx - x) > HOLE_WIDTH * 0.5 + 0.6:
					_add(st, {"box": [bx, y + HOLE_TOP * 0.5, z], "size": [1.6, HOLE_TOP, 2.2], "kind": "NEUTRAL", "look": "RUST"})
		"fence":
			# Corrugated sheets on posts, the bottom of one sheet pried off.
			var over := _cross_wall(st, z, x, HOLE_WIDTH, 0.0, HOLE_TOP, "CORRUGATED")
			over.meta = tag
			for px: float in [-half + 0.1, x - HOLE_WIDTH * 0.5 - 0.1, x + HOLE_WIDTH * 0.5 + 0.1, half - 0.1]:
				_add(st, {"box": [px, y + OUTDOOR_WALL * 0.5 + 0.1, z + 0.2], "size": [0.14, OUTDOOR_WALL + 0.2, 0.14], "kind": "NEUTRAL", "look": "RUST"})
			# The torn-off sheet, propped against the fence beside the gap.
			_add(st, {"box": [x - HOLE_WIDTH * 0.5 - 0.8, y + 0.6, z + 0.3], "size": [1.2, 1.2, 0.05], "kind": "NEUTRAL", "look": "CORRUGATED", "yaw": 8.0})
		_:
			# "broken": a brick wall with a hole knocked through at the
			# floor, ragged at the top.
			var over := _cross_wall(st, z, x, HOLE_WIDTH, 0.0, HOLE_TOP, "BRICK")
			over.meta = tag
			# (Bricks hanging into it leave at least 1.1 m to slide under.)
			for k: Array in [[-0.95, 0.5, 0.18], [0.9, 0.6, 0.2], [0.05, 0.5, 0.1]]:
				_add(st, {"box": [x + k[0], y + HOLE_TOP - k[2] * 0.5, z], "size": [k[1], k[2], 0.32], "kind": "NEUTRAL", "look": "BRICK"})
			# Rubble kicked through to the far side, out of the slide.
			for k: Array in [[-1.7, -0.9], [1.9, -1.4], [-2.2, 0.8]]:
				_add(st, {"box": [x + k[0], y + 0.15, z + k[1]], "size": [0.7, 0.3, 0.5], "kind": "NEUTRAL", "look": "BRICK", "yaw": k[0] * 20.0})


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
		# "elevation": stands that many m over the roof (a balcony, a catwalk).
		var e := {"type": type, "at": [ex, y + float(spec.get("elevation", 0.0)), ez], "yaw": 180, "wake": spec.get("wake", 0.0)}
		for k: String in spec:
			if k not in ["type", "x", "d", "wake", "height", "cover", "elevation"]:
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
	for k: String in ["hear_shots", "hearing_radius", "max_aiming", "wake_distance"]:
		if f.has(k):
			piece[k] = f[k]
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
	_trick(st, seg)
	st.bot.append([edge - gap - 4.0, "", 0.0])
	st.after_wallrun = true
	_lane(st, edge, edge - gap, WIDTH)
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
	if seg.has("interior"):
		# Indoors (an escalator hall): walls up both sides to a ceiling
		# `interior` m over the top of the ramp.
		var top: float = top_y + float(seg.interior)
		for side: float in [-1.0, 1.0]:
			_add(st, {"box": [side * (WIDTH * 0.5 + 0.25), (bottom_y + top) * 0.5, st.z - length * 0.5], "size": [0.5, top - bottom_y, length], "kind": "NEUTRAL", "look": st.wall_look})
		_add(st, {"box": [0, top + 0.25, st.z - length * 0.5], "size": [WIDTH + 1.0, 0.5, length], "kind": "NEUTRAL", "look": "RUST"})
	st.y = maxf(top_y, bottom_y)
	_lane(st, st.z, st.z - length, WIDTH, 0.0, NAN, minf(top_y, bottom_y))
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
		elif p.has("box") and p.get("footprint", false):
			# A box the city keeps clear of, like a bridge deck.
			var s: Array = _turn_size(p.size, deg_to_rad(float(p.get("yaw", 0.0))))
			var c: Array = p.box
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
	return r


## With streets on the route, falls only count below the street, so a fall
## off a high roof into the slot beside it would leave you stuck down
## there: "pits" makes anywhere below `y` (1.2 m, or under the lowest
## roof) off the streets (and the base
## map's ground) count as a fall too. MissionRun reads it.
static func _pits(st: Dictionary, mission: Dictionary) -> void:
	var fail: float = mission.get("fail_y", -50.0)
	var streets: Array = []
	var high := false
	# Below every roof: a floor at 1 m (inside a warehouse) is no pit.
	var pit_y := 1.2
	for l: Array in st.lanes:
		if float(l[6]) > City.STREET_TOP:
			high = true
			pit_y = minf(pit_y, float(l[6]) - 0.4)
			continue
		var leg: int = l[0]
		var c := _world(st, leg, l[1], (float(l[2]) + float(l[3])) * 0.5, 0.0)
		var r := {"at": [c.x, 0.0, c.z], "size": [float(l[4]) + City.STREET_MARGIN * 2.0, 6.0, absf(float(l[2]) - float(l[3])) + City.STREET_MARGIN * 2.0]}
		_turn_region(r, st.legs[leg].yaw)
		streets.append(r)
	for l: Array in st.ledges:
		var c := _world(st, l[0], l[1], (float(l[2]) + float(l[3])) * 0.5, 0.0)
		var r := {"at": [c.x, 0.0, c.z], "size": [WIDTH, 6.0, absf(float(l[2]) - float(l[3]))]}
		_turn_region(r, st.legs[l[0]].yaw)
		streets.append(r)
	if not high or fail > 0.0:
		return
	if mission.has("base"):
		var script: Script = load(mission.base)
		var f: Variant = script.get_script_constant_map().get("FOOTPRINT", null) if script != null else null
		if f is Rect2:
			var rect: Rect2 = f
			streets.append({"at": [rect.get_center().x, 0.0, rect.get_center().y], "size": [rect.size.x, 6.0, rect.size.y]})
	mission.pits = {"y": pit_y, "streets": streets}


## Takes the city's rubble, wrecks and fires (pieces from `first` on) off
## the streets the course runs along: a piece high over a street (a dummy
## on a container stack) reads to the city as a gap with ground under it.
static func _clear_streets(st: Dictionary, mission: Dictionary, first: int) -> void:
	var streets: Array = []
	for l: Array in st.lanes:
		if float(l[5]) <= City.STREET_TOP:
			streets.append(l)
	if streets.is_empty():
		return
	var kept: Array = mission.pieces.slice(0, first)
	for i in range(first, mission.pieces.size()):
		var p: Dictionary = mission.pieces[i]
		var at: Variant = p.get("at", p.get("fire", null)) if (p.has("prop") or p.has("fire")) else null
		if at is Array and _on_street(st, streets, Vector2(at[0], at[2])):
			continue
		kept.append(p)
	mission.pieces = kept


static func _on_street(st: Dictionary, streets: Array, p: Vector2) -> bool:
	for l: Array in streets:
		var leg: Dictionary = st.legs[int(l[0])]
		# Into the leg's frame: x across, z along.
		var v := Basis(Vector3.UP, -float(leg.yaw)) * Vector3(p.x - leg.o.x, 0.0, p.y - leg.o.z)
		var z := v.z + float(leg.z0)
		if absf(v.x - float(l[1])) <= float(l[4]) * 0.5 and z <= maxf(l[2], l[3]) and z >= minf(l[2], l[3]):
			return true
	return false


## The course's stretches as areas in the world, for the city.
static func _lane_areas(st: Dictionary) -> Array:
	var out: Array = []
	for l: Array in st.lanes:
		var leg: int = l[0]
		var c := _world(st, leg, l[1], (float(l[2]) + float(l[3])) * 0.5, 0.0)
		var top: float = l[5]
		var a := City.area(Vector2(c.x, c.z), Vector2(float(l[4]) * 0.5, absf(float(l[2]) - float(l[3])) * 0.5),
			st.legs[leg].yaw, top, City.STREET_MARGIN if top <= City.STREET_TOP else City.ROOF_MARGIN)
		if l.size() > 7:
			# An outline [[x, z], ...] in the leg's frame.
			var poly: Array = []
			for q: Array in l[7]:
				var w := _world(st, leg, q[0], q[1], 0.0)
				poly.append(Vector2(w.x, w.z))
			a.poly = poly
		out.append(a)
	return out
