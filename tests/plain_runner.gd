extends RefCounted
## The plain-runner check, for any route level that opts in with
## "plain_runner": true (tests/test_speed_gates.gd runs them). A plain
## runner follows the level's bot line at base speed with no tricks (no
## slides, rolls or kicks, no Flow) and never shoots. Dropped in just
## before each speed gate and each encounter after the tutorial, it must
## fail there (go down, fall, or miss the gate onto the lower ledge),
## while the level's own trick-line bot gets through.
##
## Sections come from the expanded mission: gates (the take-off chalk
## line SpeedGate tags with "gate") and encounter areas, as distances
## along the route (the bot's frame).

## The take-off chalk line sits this far before a gate's edge.
const EDGE_MARK := 0.35
## Where bots take off for a gate: right at the edge (a gate is sized for
## that; route.gd's usual 1.2 m early jump would come up short).
const GATE_TAKEOFF := 0.1
## Pieces further than this across the route are on a fork's other line.
const OFF_LINE := 9.0


## Moves the bot's jump for each gate to the edge, in place. (Until
## route.gd reads a gap's "takeoff" itself.)
static func fix_gate_takeoffs(mission: Dictionary) -> void:
	var legs: Array = mission.get("route_legs", [])
	for p: Dictionary in mission.get("pieces", []):
		if not (p.has("gate") and p.has("mark")):
			continue
		var a: Array = p.mark
		var edge := along(Vector3(a[0], a[1], a[2]), legs) - EDGE_MARK
		for key: String in ["bot", "bot_alt"]:
			for s: Array in mission.get(key, []):
				if s[1] == "jump" and absf(float(s[0]) - (edge + 1.2)) < 0.05:
					s[0] = edge + GATE_TAKEOFF


## The bot steps a plain runner keeps: the moves the line can't be passed
## without (jumps, slides under bars, door kicks) and lane changes, but no
## optional rolls (and on a "bot_steady" level no flips or 360s either: a
## trick in the air is harder to hit). It still earns nothing for them
## (make_plain).
static func plain_steps(bot: Array, no_tricks := false) -> Array:
	var out: Array = []
	for s: Array in bot:
		if no_tricks and s[1] in ["flip", "front", "spin"]:
			continue
		if s[1] != "roll":
			out.append(s)
		elif not is_nan(float(s[2])):
			out.append([s[0], "", s[2]])
	return out


## No combo speed and no style: base top speed only.
static func make_plain(player: Player) -> void:
	player.flow_source = func() -> float: return 0.0
	player.combo_source = func() -> int: return 0


## A world point as distance along the route (legs as in route_legs:
## [origin x, origin z, yaw, z0]).
static func along(pos: Vector3, legs: Array) -> float:
	return _local(pos, legs).y


## A world point's offset across the route (right +).
static func across(pos: Vector3, legs: Array) -> float:
	return _local(pos, legs).x


## (across, along) in the frame of the leg the point is on (leg_index).
static func _local(pos: Vector3, legs: Array) -> Vector2:
	var i := leg_index(pos, legs)
	if i < 0:
		return Vector2(pos.x, pos.z)
	var l: Array = legs[i]
	var v := Basis(Vector3.UP, -float(l[2])) * Vector3(pos.x - l[0], 0.0, pos.z - l[1])
	return Vector2(v.x, v.z + float(l[3]))


## The route's heading (yaw) on the leg a point is on.
static func heading(pos: Vector3, legs: Array) -> float:
	var i := leg_index(pos, legs)
	return float(legs[i][2]) if i >= 0 else 0.0


## Which leg a point is on, or -1 with no legs: of the legs whose stretch
## of the route it lies beside, the nearest across (the last leg if none).
## (A route can double back, so the latest leg in reach isn't always the one.)
static func leg_index(pos: Vector3, legs: Array) -> int:
	if legs.is_empty():
		return -1
	var best := legs.size() - 1
	var best_x := INF
	for i in legs.size():
		var l: Array = legs[i]
		var v := Basis(Vector3.UP, -float(l[2])) * Vector3(pos.x - l[0], 0.0, pos.z - l[1])
		var z := v.z + float(l[3])
		var start := INF if i == 0 else float(l[3]) + 0.5
		var end := -INF if i == legs.size() - 1 else float(legs[i + 1][3]) - 0.5
		if z <= start and z >= end and absf(v.x) < best_x:
			best = i
			best_x = absf(v.x)
	return best


## [start, end, label] along the route for every gate and encounter,
## nearest first. A gate runs from 20 m before its edge to 6 m past the
## far side; an encounter is its area, or its "route_span" [from, to]
## along the route when it spans corners (4-2's Juno, up three legs of the
## car park). An unarmed one (only the Host's camera drones filming you) is
## no fight, so it isn't a section.
static func sections(mission: Dictionary) -> Array:
	var legs: Array = mission.get("route_legs", [])
	var out: Array = []
	for p: Dictionary in mission.get("pieces", []):
		# Only the main line's: a fork's other line (a high path) isn't
		# where the bot or the plain runner run.
		var on: Variant = p.get("mark", p.area.at if p.has("encounter") else null)
		if p.has("route_span") and armed(p):
			out.append([float(p.route_span[0]), float(p.route_span[1]), "encounter %s" % p.encounter])
			continue
		if on is Array and absf(across(Vector3(on[0], on[1], on[2]), legs)) > OFF_LINE:
			continue
		if p.has("gate") and p.has("mark"):
			var a: Array = p.mark
			if absf(across(Vector3(a[0], a[1], a[2]), legs)) > 3.0:
				continue  # on the other line of a fork: the trick line never meets it
			var edge := along(Vector3(a[0], a[1], a[2]), legs) - EDGE_MARK
			out.append([edge + 20.0, edge - float(p.get("gap", 15.0)) - 6.0, "tier %d gate" % int(p.gate)])
		elif p.has("encounter") and armed(p):
			var c: Array = p.area.at
			var mid := along(Vector3(c[0], c[1], c[2]), legs)
			var half := float(maxf(p.area.size[0], p.area.size[2])) * 0.5
			out.append([mid + half, mid - half, "encounter %s" % p.encounter])
	out.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	return out


## True if an expanded encounter piece has anyone who shoots or bites.
static func armed(encounter: Dictionary) -> bool:
	if not encounter.get("raiders", []).is_empty() or not encounter.get("mutants", []).is_empty():
		return true
	for e: Dictionary in encounter.get("enemies", []):
		if String(e.get("type", "raider")) != "camera_drone":
			return true
	return false
