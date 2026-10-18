extends RefCounted
## Speed gates: gaps you can't clear at base top speed, only with the extra
## speed a varied combo's Flow gives you. A mission route asks for one with
## a segment {"gate": {"tier": 1}} straight after a roof; prepare() turns it
## into an ordinary {"gap"} before the route is laid out, sized from the
## measured jump distance (below), and dresses it:
##   * chalk on the take-off roof: a line at the edge and one dash per tier
##     before it, an arrow at the start of the run-up, a line on the far
##     side where you land;
##   * trick chances in the run-up (hurdles, a slide bar, a wall hop),
##     unless the gate says "tricks": false or the roof already has
##     features in its last 60 m;
##   * a lower route: miss and you drop LEDGE_DROP m onto a ledge under the
##     gap and climb a yellow face back up, slow and in the open. With
##     "lower": "fall" there is no ledge and a miss is a fall.
## The landing roof must be at the take-off height (the table assumes it).
##
## Sized by two rules (Game design lead, 2026-10-18):
##   1. the best jump at the speed one tier below (base top speed for
##      tier 1), taken late off the edge in coyote time, misses by at
##      least MISS_BELOW;
##   2. an ordinary jump at the edge at the tier's speed clears with
##      SPARE to spare.
## A tier's speed is the lowest that satisfies both, and at least top
## speed + TIER_FLOOR (Flow: +0.5 m/s per distinct trick, flips double).
## Coyote time carries a late jump ~1.5 m further than an edge jump, so
## the tiers end up about 2.2 m/s apart: 13.7, 15.8, 18.6 m/s at take-off
## with today's movement. tests/test_speed_gates.gd re-measures both rules
## against the real player, so a movement change that breaks the table
## fails there.
##
## Loaded by path (no class_name).

## Measured on playtest-3 (top speed 11.5, landing level with take-off,
## mantle catches included): take-off speed, the widest gap an ordinary
## edge jump clears (0.25 m before the edge), and the widest the best late
## (coyote) jump clears.
const JUMPS := [[11.5, 12.50, 13.84], [13.0, 13.99, 15.47], [13.5, 14.46, 15.97], [14.5, 15.54, 17.19],
	[15.0, 16.17, 17.62], [16.0, 17.19, 18.75], [16.5, 17.60, 19.49], [17.5, 18.71, 20.42], [18.0, 19.16, 21.22]]
## Rule 1 and rule 2 margins (m).
const MISS_BELOW := 0.5
const SPARE := 0.3
## The least extra take-off speed each tier wants over top speed.
const TIER_FLOOR := [2.0, 3.5, 5.0]
## The climb face in front of the landing roof (the gap is measured to it).
const FACE := 0.3
## How far below the roofs a missed jump lands.
const LEDGE_DROP := 3.0
const CHALK := "#ece8dc"
## A route roof's width (route.gd WIDTH).
const WIDTH := 12.0
## Run-up tricks, as distances before the edge.
const RUNUP := [{"hurdles": true, "before": 46.0}, {"slide": true, "before": 32.0}, {"hop": true, "side": -1, "before": 18.0}]


## The take-off speed a tier wants (see the rules at the top).
static func tier_speed(tier: int, top_speed := 11.5) -> float:
	var below := top_speed
	var v := top_speed
	for t in range(1, clampi(tier, 1, 3) + 1):
		v = maxf(top_speed + TIER_FLOOR[t - 1], below)
		while edge_jump(v) - SPARE < best_jump(below) + MISS_BELOW:
			v += 0.1
		v = snappedf(v, 0.1)
		below = v
	return v


## The widest gap an ordinary edge jump clears at take-off speed `v`.
static func edge_jump(v: float) -> float:
	return _lookup(v, 1)


## The widest gap the best late jump clears at take-off speed `v`.
static func best_jump(v: float) -> float:
	return _lookup(v, 2)


static func _lookup(v: float, col: int) -> float:
	var i := 1
	while i < JUMPS.size() - 1 and v > JUMPS[i][0]:
		i += 1
	var a: Array = JUMPS[i - 1]
	var b: Array = JUMPS[i]
	return a[col] + (v - a[0]) * (b[col] - a[col]) / (b[0] - a[0])


## The gap (edge to the climb face) for a tier.
static func gap_for_tier(tier: int) -> float:
	return snappedf(edge_jump(tier_speed(tier)) - SPARE, 0.01)


## The gate's own pieces, in the take-off roof's frame: x across, y up from
## the roof, z from its edge (negative is across the gap). `gap` as from
## gap_for_tier().
static func pieces(tier: int, gap: float, lower := "ledge") -> Array:
	var out: Array = []
	# Chalk: a line at the edge, a dash per tier before it.
	# ("gate" and "gap" tag it for tests/plain_runner.gd.)
	out.append({"mark": [0, 0, 0.35], "size": [WIDTH - 1.0, 0.25], "color": CHALK, "gate": tier, "gap": gap})
	for i in clampi(tier, 1, 3):
		out.append({"mark": [0, 0, 1.3 + i * 0.8], "size": [1.6, 0.3], "color": CHALK})
	# The climb face: the far roof's front, 3 m of yellow to climb from the
	# ledge (it stands proud of the building, so the gap ends at it).
	out.append({"box": [0, -LEDGE_DROP * 0.5, -gap - FACE * 0.5], "size": [WIDTH, LEDGE_DROP, FACE], "kind": "PARKOUR"})
	if lower != "fall":
		out.append({"box": [0, -LEDGE_DROP - 0.5, -gap * 0.5], "size": [WIDTH, 1.0, gap], "kind": "NEUTRAL"})
	return out


## Turns every {"gate"} segment in mission["route"] (forks included) into
## a sized gap with its dressing. Call before Route.expand(). Returns the
## mission.
static func prepare(mission: Dictionary) -> Dictionary:
	if mission.has("route"):
		mission.route = _prepare_list(mission.route)
	return mission


static func _prepare_list(route: Array) -> Array:
	var out: Array = []
	for i in route.size():
		var seg: Dictionary = route[i]
		if seg.has("fork"):
			seg = seg.duplicate()
			seg.fork = _prepare_list(seg.fork)
		if not seg.has("gate"):
			out.append(seg)
			continue
		var gate: Dictionary = seg.gate if seg.gate is Dictionary else {"tier": int(seg.gate)}
		var tier := clampi(int(gate.get("tier", 1)), 1, 3)
		var gap := gap_for_tier(tier)
		if out.is_empty() or not (out[-1] as Dictionary).has("roof"):
			push_error("SpeedGate: a gate must follow a roof (%s)" % [seg])
			out.append({"gap": gap + FACE})
			continue
		var roof: Dictionary = (out[-1] as Dictionary).duplicate(true)
		var length := float(roof.roof)
		var feats: Array = roof.get("do", [])
		for p: Dictionary in pieces(tier, gap, String(gate.get("lower", "ledge"))):
			feats.append({"piece": p, "at": length, "length": 0.0})
		feats.append({"piece": {"prop": "chalk_arrow", "at": [0, 0, 0]}, "at": maxf(length - 56.0, 2.0), "length": 0.0})
		if gate.get("tricks", true) and not _busy_before_edge(feats, length, 60.0):
			for t: Dictionary in RUNUP:
				if float(t.before) + 4.0 > length:
					continue
				var f := t.duplicate()
				f.erase("before")
				f.at = length - float(t.before)
				feats.append(f)
		roof["do"] = feats
		out[-1] = roof
		out.append({"gap": gap + FACE, "takeoff": 0.1, "gate": tier})
		# The far side: chalk where you land.
		if i + 1 < route.size() and (route[i + 1] as Dictionary).has("roof"):
			var next: Dictionary = (route[i + 1] as Dictionary).duplicate(true)
			route[i + 1] = next
			var nf: Array = next.get("do", [])
			nf.append({"piece": {"mark": [0, 0, -1.2], "size": [WIDTH - 1.0, 0.25], "color": CHALK}, "at": 0.0, "length": 0.0})
			next["do"] = nf
	return out


## Does the roof already have features in its last `reach` m?
static func _busy_before_edge(feats: Array, length: float, reach: float) -> bool:
	for f: Dictionary in feats:
		if f.has("piece"):
			continue
		if float(f.get("at", 0.0)) > length - reach:
			return true
	return false
