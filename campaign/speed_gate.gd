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
## Tiers want this speed at take-off (Flow: +0.5 m/s per distinct trick,
## flips count double):
##   1 = top speed + 1.5, 2 = + 3.0, 3 = + 4.5.
## A gap is the farthest a jump at the edge carries at its tier's speed,
## and never less than the best jump at base top speed (taken late off the
## edge in coyote time, which carries ~1.3 m further) plus a margin, so
## plain running never makes it. tests/test_speed_gates.gd re-measures
## both against the real player, so a movement change that breaks the
## table fails there.
##
## Loaded by path (no class_name).

## Measured on playtest-3 (top speed 11.5, landing level with take-off,
## mantle catches included): take-off speed -> widest gap cleared with a
## jump 0.25 m before the edge.
const EDGE_JUMP := [[11.5, 12.50], [12.25, 13.14], [13.0, 13.98], [14.5, 15.53], [16.0, 17.18], [17.5, 18.69]]
## The widest gap cleared at base top speed with the best possible timing.
const BEST_AT_TOP := 13.84
## How much wider than that every gate is.
const TOP_MARGIN := 0.3
## Extra take-off speed each tier wants.
const TIER_SPEED := 1.5
## The climb face in front of the landing roof (the gap is measured to it).
const FACE := 0.3
## How far below the roofs a missed jump lands.
const LEDGE_DROP := 3.0
const CHALK := "#ece8dc"
## A route roof's width (route.gd WIDTH).
const WIDTH := 12.0
## Run-up tricks, as distances before the edge.
const RUNUP := [{"hurdles": true, "before": 46.0}, {"slide": true, "before": 32.0}, {"hop": true, "side": -1, "before": 18.0}]


static func tier_speed(tier: int, top_speed := 11.5) -> float:
	return top_speed + TIER_SPEED * clampi(tier, 1, 3)


## The widest gap a jump at the edge clears at take-off speed `v`.
static func edge_jump(v: float) -> float:
	if v <= EDGE_JUMP[0][0]:
		return EDGE_JUMP[0][1]
	for i in range(1, EDGE_JUMP.size()):
		if v <= EDGE_JUMP[i][0]:
			var a: Array = EDGE_JUMP[i - 1]
			var b: Array = EDGE_JUMP[i]
			return lerpf(a[1], b[1], (v - a[0]) / (b[0] - a[0]))
	var a2: Array = EDGE_JUMP[-2]
	var b2: Array = EDGE_JUMP[-1]
	return b2[1] + (v - b2[0]) * (b2[1] - a2[1]) / (b2[0] - a2[0])


## The gap (edge to the climb face) for a tier.
static func gap_for_tier(tier: int) -> float:
	return snappedf(maxf(BEST_AT_TOP + TOP_MARGIN, edge_jump(tier_speed(tier))), 0.01)


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
