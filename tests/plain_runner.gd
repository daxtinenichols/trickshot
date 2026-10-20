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
## optional rolls. It still earns nothing for them (make_plain).
static func plain_steps(bot: Array) -> Array:
	var out: Array = []
	for s: Array in bot:
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
	if legs.is_empty():
		return pos.z
	return _on_leg(pos, legs).y


## A world point's offset across the route (right +).
static func across(pos: Vector3, legs: Array) -> float:
	if legs.is_empty():
		return pos.x
	return _on_leg(pos, legs).x


## (across, along) on the leg the point is on: of the legs whose stretch
## (from its corner to the next) it lies along, the one it's nearest across.
## A route that winds back on itself (a mall circling its atrium) puts a
## point "past the start" of several legs; the stretch tells them apart.
static func _on_leg(pos: Vector3, legs: Array) -> Vector2:
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


## Which leg a point is on (see _on_leg), or -1 with no legs.
static func leg_index(pos: Vector3, legs: Array) -> int:
	var best := -1
	var best_x := INF
	var fallback := -1
	for i in legs.size():
		var l: Array = legs[i]
		var v := Basis(Vector3.UP, -float(l[2])) * Vector3(pos.x - l[0], 0.0, pos.z - l[1])
		var z := v.z + float(l[3])
		var started := i == 0 or z <= float(l[3]) + 0.5
		var ended := i + 1 < legs.size() and z < float(legs[i + 1][3]) - 0.5
		if started and not ended and absf(v.x) < best_x:
			best = i
			best_x = absf(v.x)
		if started and fallback < 0:
			fallback = i
	return best if best >= 0 else fallback


## [start, end, label] along the route for every gate and encounter,
## nearest first. A gate runs from 20 m before its edge to 6 m past the
## far side; an encounter is its area.
static func sections(mission: Dictionary) -> Array:
	var legs: Array = mission.get("route_legs", [])
	var out: Array = []
	for p: Dictionary in mission.get("pieces", []):
		if p.has("gate") and p.has("mark"):
			var a: Array = p.mark
			if absf(across(Vector3(a[0], a[1], a[2]), legs)) > 3.0:
				continue  # on the other line of a fork: the trick line never meets it
			var edge := along(Vector3(a[0], a[1], a[2]), legs) - EDGE_MARK
			out.append([edge + 20.0, edge - float(p.get("gap", 15.0)) - 6.0, "tier %d gate" % int(p.gate)])
		elif p.has("encounter"):
			var c: Array = p.area.at
			var mid := along(Vector3(c[0], c[1], c[2]), legs)
			var half := float(maxf(p.area.size[0], p.area.size[2])) * 0.5
			out.append([mid + half, mid - half, "encounter %s" % p.encounter])
	out.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	return out
