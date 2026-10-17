extends RefCounted
## Long missions from a list of route segments instead of hand-placed boxes.
## A mission's "route" is laid out end to end toward -Z from its start:
## roofs, gaps, wallrun gaps, drops, ramps and street stretches, with
## features on each roof (hurdles, slide bars, wall hops, enemies, tapes,
## checkpoints, radio lines). expand() turns it into ordinary pieces,
## checkpoints and radio lines, plus "bot" steps the tests use to run it,
## so a 900 m mission stays a short, readable file. Format in
## docs/missions.md ("Routes").
##
## Loaded by path (no class_name).

## Roof width; the running lane is its middle.
const WIDTH := 12.0
## Wallrun panels stand just outside the roof edge.
const WALL_X := 6.5
## Clutter that sits at roof edges, out of the lane.
const CLUTTER := ["ac_unit", "vent_stack", "satellite_dish", "generator", "barrel_rust",
	"crate_wood", "tire_stack", "crate_stack", "antenna_mast", "loudspeaker_pole"]


## Expands mission["route"] in place. Returns the mission.
static func expand(mission: Dictionary) -> Dictionary:
	var route: Array = mission.get("route", [])
	if route.is_empty():
		return mission
	var st := {
		"z": 6.0,
		"y": float(mission.get("start", {}).get("at", [0, 8, 0])[1]),
		"pieces": [], "checkpoints": [], "radio": [], "bot": [],
		"rng": RandomNumberGenerator.new(), "lowest": INF, "roof_end": 6.0, "heights": [], "clutter": mission.get("clutter", CLUTTER),
	}
	st.rng.seed = hash(String(mission.get("id", "route")))
	for seg: Dictionary in route:
		_segment(st, seg)
	var pieces: Array = mission.get("pieces", [])
	pieces.append_array(st.pieces)
	mission.pieces = pieces
	# Route checkpoints come first in order along the route; extra
	# hand-written ones (if any) follow.
	var cps: Array = st.checkpoints
	cps.append_array(mission.get("checkpoints", []))
	mission.checkpoints = cps
	var radio: Array = mission.get("radio", [])
	radio.append_array(st.radio)
	mission.radio = radio
	# Bot steps in route order. A NAN lane keeps the current lane.
	var bot: Array = st.bot
	bot.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	mission.bot = bot
	mission.route_end = [0.0, st.y, st.z]
	mission.route_length = -st.z
	# A street under the whole route, and the city on both sides.
	if not mission.has("no_floor"):
		var length: float = -st.z + 40.0
		pieces.push_front({"box": [0, -0.5, st.z * 0.5], "size": [160, 1, length], "kind": "FLOOR"})
	_skyline(st, mission)
	if not mission.has("fail_y"):
		mission.fail_y = st.lowest - 5.5 if st.lowest > 6.0 else -20.0
	# "at": "end" or "@Checkpoint name" in objectives and radio lines.
	for list: Array in [mission.get("objectives", []), mission.radio]:
		for o: Dictionary in list:
			if o.get("at", null) is String:
				_resolve(o, mission)
	return mission


static func _resolve(o: Dictionary, mission: Dictionary) -> void:
	var ref: String = o.at
	if ref == "end":
		var e: Array = mission.route_end
		o.at = [0.0, e[1] + 2.0, e[2] + 4.0]
		if not o.has("size") and not o.has("radius"):
			o.size = [WIDTH + 2.0, 8.0, 8.0]
		return
	for c: Dictionary in mission.checkpoints:
		if "@" + String(c.get("name", "")) == ref:
			o.at = c.at
			if not o.has("size") and not o.has("radius"):
				o.size = c.size
			return
	push_error("Route: unknown place %s" % ref)
	o.at = [0, -1000, 0]


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
	elif seg.has("street"):
		var length: float = seg.street
		st.y = 0.0
		_set_low(st, 0.0)
		st.z -= length
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
			st.pieces.append({"box": [0, st.y + rise * 0.5, st.z - 0.15], "size": [WIDTH, rise, 0.3], "kind": "PARKOUR"})
			st.bot.append([st.z + 1.8, "jump", NAN])
		var drop: float = st.y - float(seg.y)
		if drop >= 3.5 and not st.bot.is_empty() and st.bot[-1][1] == "jump":
			# A big drop onto this roof: roll out of it.
			st.bot.append([st.z, "roll", NAN])
		st.y = float(seg.y)
	var z0: float = st.z
	var w: float = seg.get("width", WIDTH)
	if st.y > 0.5:
		st.pieces.append({"building": [0, st.y, z0 - length * 0.5], "size": [w, length], "look": seg.get("look", "FACADE")})
	# (At street level, y 0, the street itself is the floor.)
	st.heights.append([z0, z0 - length, st.y])
	_set_low(st, st.y)
	var busy: Array = []
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


static func _set_low(st: Dictionary, y: float) -> void:
	st.lowest = minf(st.lowest, y)


## A feature on the roof starting at z0. Returns its busy range [from, to]
## in meters from the roof start, so clutter keeps out of it.
static func _feature(st: Dictionary, f: Dictionary, z0: float) -> Array:
	var d: float = f.get("at", 0.0)
	var z := z0 - d
	var y: float = st.y
	if f.has("hurdles"):
		st.pieces.append({"row": f.get("hurdles", "barricade_jersey") if f.hurdles is String else "barricade_jersey",
			"from": [-5, y, z], "to": [5, y, z], "count": 6})
		st.bot.append([z + 1.6, "jump", NAN])
		return [d - 4.0, d + 3.0]
	if f.has("slide"):
		# A bar 1.1 m up: slide under it. Needs a run-up on the ground.
		st.pieces.append({"box": [0, y + 1.35, z], "size": [WIDTH, 0.5, 0.6], "kind": "PARKOUR"})
		st.pieces.append({"box": [-5.8, y + 0.55, z], "size": [0.4, 1.1, 0.6], "kind": "NEUTRAL"})
		st.pieces.append({"box": [5.8, y + 0.55, z], "size": [0.4, 1.1, 0.6], "kind": "NEUTRAL"})
		st.bot.append([z + 4.5, "crouch", NAN])
		return [d - 6.0, d + 3.0]
	if f.has("hop"):
		# Two short walls on alternate sides: wallrun one, jump to the next.
		var side: float = f.get("side", -1.0)
		st.pieces.append({"box": [side * 3.0, y + 3.0, z - 4.0], "size": [1, 6, 8], "kind": "WALLRUN"})
		st.pieces.append({"box": [-side * 3.0, y + 3.0, z - 13.0], "size": [1, 6, 8], "kind": "WALLRUN"})
		st.pieces.append({"mark": [0, y, z - 8.5], "size": [5, 18], "color": "#d94c40"})
		st.bot.append([z + 8.0, "", 0.0])
		return [d - 2.0, d + 20.0]
	if f.has("window"):
		# A wall across the roof with a low window to slide through at x.
		var wx: float = f.window
		var half := WIDTH * 0.5
		var lo := wx - 1.1
		var hi := wx + 1.1
		st.pieces.append({"box": [(-half + lo) * 0.5, y + 1.5, z], "size": [lo + half, 3.0, 0.3], "kind": "NEUTRAL"})
		st.pieces.append({"box": [(hi + half) * 0.5, y + 1.5, z], "size": [half - hi, 3.0, 0.3], "kind": "NEUTRAL"})
		st.pieces.append({"window": [wx, y, z], "size": [2.2, 1.4]})
		st.pieces.append({"box": [wx, y + 2.2, z], "size": [2.2, 1.6, 0.3], "kind": "NEUTRAL"})
		st.bot.append([z + 16.0, "", wx])
		st.bot.append([z + 3.0, "crouch", wx])
		st.bot.append([z - 5.0, "", 0.0])
		return [d - 4.0, d + 16.0]
	if f.has("checkpoint"):
		st.checkpoints.append({"name": f.checkpoint, "at": [0, y, z], "size": [WIDTH + 2.0, 8, 4],
			"objective": f.get("objective", 0)})
		return [d - 1.0, d + 1.0]
	if f.has("encounter"):
		var raiders: Array = []
		var cover: Array = []
		for r: Array in f.get("raiders", []):
			var rz := z - float(r[1])
			raiders.append({"at": [r[0], y, rz], "yaw": 180, "wake": r[2] if r.size() > 2 else 0.0})
			cover.append({"at": [r[0], y, rz + 3.0], "length": 2.0})
			st.pieces.append({"prop": "sandbag_wall", "at": [r[0], y, rz + 3.0]})
			if absf(float(r[0])) < 2.5:
				# Sandbags in the lane: vault them.
				st.bot.append([rz + 4.6, "jump", NAN])
		var mutants: Array = []
		for m: Array in f.get("mutants", []):
			mutants.append({"at": [m[0], y, z - float(m[1])], "yaw": 180, "leash_radius": 14, "aggro_radius": 12})
		var length: float = f.get("length", 40.0)
		st.pieces.append({"encounter": f.encounter, "area": {"at": [0, y + 4.0, z - length * 0.5], "size": [WIDTH, 10, length]},
			"raiders": raiders, "mutants": mutants, "cover": cover})
		return [d, d + length]
	if f.has("tape"):
		var x: float = f.get("x", 4.6)
		st.pieces.append({"tape": [x, y + float(f.get("height", 0.0)), z], "id": f.tape})
		return [d - 2.0, d + 2.0]
	if f.has("radio"):
		var line: Dictionary = (f.radio as Dictionary).duplicate()
		line.at = [0, y, z]
		line.radius = f.get("radius", 7.0)
		st.radio.append(line)
		return [d, d]
	if f.has("prop"):
		st.pieces.append({"prop": f.prop, "at": [f.get("x", 0.0), y, z], "yaw": f.get("yaw", 0.0)})
		return [d - 2.0, d + 2.0]
	if f.has("label"):
		st.pieces.append({"label": f.label, "at": [0, y + 3.0, z], "size": f.get("size", 0.8)})
		return [d, d]
	if f.has("mark"):
		st.pieces.append({"mark": [0, y, z], "size": [WIDTH, 0.8], "color": f.mark})
		return [d, d]
	if f.has("lane"):
		# Where the bot should run from here (the player can go anywhere).
		st.bot.append([z, "", float(f.lane)])
		return [d, d]
	push_warning("Route: unknown feature %s" % f)
	return [d, d]


## A gap too wide to jump, with a wallrun panel along it. Approach on that
## side, jump at the edge, run the wall across.
static func _wallrun_gap(st: Dictionary, seg: Dictionary) -> void:
	var gap: float = seg.wallrun
	var side: float = seg.get("side", 1.0)
	var edge: float = st.z
	var y: float = st.y
	st.pieces.append({"box": [side * WALL_X, y + 2.5, edge - gap * 0.5], "size": [1, 9, gap + 6.0], "kind": "WALLRUN"})
	# A low lip on the far side so nobody runs off it by mistake.
	st.pieces.append({"box": [-side * 5.8, y + 0.4, edge + 4.0], "size": [0.4, 0.8, 8], "kind": "NEUTRAL"})
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
	st.pieces.append({"ramp": [0, top_y, top_z], "to": [0, bottom_y, bottom_z], "width": seg.get("width", 6.0),
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
			st.pieces.append({"prop": prop, "at": [side * rng.randf_range(4.7, 5.2), st.y, z0 - d], "yaw": rng.randf_range(0.0, 360.0)})
			side = -side
		d += rng.randf_range(10.0, 15.0)


## The city around the route: buildings both sides, out of the way.
static func _skyline(st: Dictionary, mission: Dictionary) -> void:
	if mission.get("skyline", true) == false:
		return
	var rng: RandomNumberGenerator = st.rng
	for side: float in [-1.0, 1.0]:
		var z := 10.0
		while z > st.z - 20.0:
			var depth := rng.randf_range(12.0, 22.0)
			var wid := rng.randf_range(10.0, 16.0)
			var x := side * (16.0 + wid * 0.5 + rng.randf_range(0.0, 10.0))
			var h := maxf(4.0, _height_at(st, z - depth * 0.5) + rng.randf_range(-6.0, 18.0))
			mission.pieces.append({"building": [x, h, z - depth * 0.5], "size": [wid, depth]})
			if rng.randf() < 0.15:
				mission.pieces.append({"prop": "billboard" if rng.randf() < 0.5 else "antenna_mast", "at": [x, h, z - depth * 0.5], "yaw": -90.0 * side})
			z -= depth + rng.randf_range(2.0, 14.0)


static func _height_at(st: Dictionary, z: float) -> float:
	var y: float = st.y
	for r: Array in st.heights:
		if z <= r[0] + 20.0:
			y = r[2]
		if z >= r[1] - 20.0 and z <= r[0] + 20.0:
			return r[2]
	return y
