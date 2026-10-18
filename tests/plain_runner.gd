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
	for i in range(legs.size() - 1, -1, -1):
		var l: Array = legs[i]
		var v := Basis(Vector3.UP, -float(l[2])) * Vector3(pos.x - l[0], 0.0, pos.z - l[1])
		var z := v.z + float(l[3])
		if i == 0 or z <= float(l[3]) + 0.5:
			return z
	return pos.z


## A world point's offset across the route (right +).
static func across(pos: Vector3, legs: Array) -> float:
	if legs.is_empty():
		return pos.x
	var z := along(pos, legs)
	for i in range(legs.size() - 1, -1, -1):
		var l: Array = legs[i]
		if i == 0 or z <= float(l[3]) + 0.5:
			return (Basis(Vector3.UP, -float(l[2])) * Vector3(pos.x - l[0], 0.0, pos.z - l[1])).x
	return pos.x


## [start, end, label] along the route for every gate and encounter,
## nearest first. A gate runs from 20 m before its edge to 6 m past the
## far side; an encounter is its area.
static func sections(mission: Dictionary) -> Array:
	var legs: Array = mission.get("route_legs", [])
	var out: Array = []
	for p: Dictionary in mission.get("pieces", []):
		if p.has("gate") and p.has("mark"):
			var a: Array = p.mark
			var edge := along(Vector3(a[0], a[1], a[2]), legs) - EDGE_MARK
			out.append([edge + 20.0, edge - float(p.get("gap", 15.0)) - 6.0, "tier %d gate" % int(p.gate)])
		elif p.has("encounter"):
			var c: Array = p.area.at
			var mid := along(Vector3(c[0], c[1], c[2]), legs)
			var half := float(maxf(p.area.size[0], p.area.size[2])) * 0.5
			out.append([mid + half, mid - half, "encounter %s" % p.encounter])
	out.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	return out
