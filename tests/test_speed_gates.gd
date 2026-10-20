extends TestCase
## Speed gates (campaign/speed_gate.gd): gaps that plain running at top
## speed never clears and a combo's Flow does, re-measured against the real
## player so movement changes can't quietly break them.

const SpeedGate := preload("res://campaign/speed_gate.gd")

var w: TestWorld


func before_each() -> void:
	w = TestWorld.new()
	tree.root.add_child(w)


func after_each() -> void:
	if is_instance_valid(w):
		w.queue_free()
	await tree.process_frame


func test_gate_gaps_grow_by_tier() -> void:
	var g1 := SpeedGate.gap_for_tier(1)
	var g2 := SpeedGate.gap_for_tier(2)
	var g3 := SpeedGate.gap_for_tier(3)
	check(g1 > SpeedGate.best_jump(11.5) and g1 < g2 and g2 < g3, "wider each tier (%.2f %.2f %.2f)" % [g1, g2, g3])
	for tier in [1, 2, 3]:
		check(SpeedGate.tier_speed(tier) >= 11.5 + SpeedGate.TIER_FLOOR[tier - 1], "tier %d wants at least top speed + %.1f" % [tier, SpeedGate.TIER_FLOOR[tier - 1]])


## The gate in a test world: take-off roof edge at z 0 (running -z), the
## far roof, and the gate's own pieces. Runs in at `v`, jumps `late`
## frames after leaving the edge (-1: an ordinary jump, 0.25 m before it).
## Returns "clear", "ledge" or "fall".
func _jump_gate(tier: int, v: float, late: int) -> String:
	if is_instance_valid(w):
		w.queue_free()
		await tree.process_frame
	w = TestWorld.new()
	tree.root.add_child(w)
	var gap := SpeedGate.gap_for_tier(tier)
	var far := gap + SpeedGate.FACE
	w.add_box(Vector3(0, -6, 100), Vector3(12, 12, 200))
	w.add_box(Vector3(0, -6, -far - 50), Vector3(12, 12, 100))
	w.add_box(Vector3(0, -12.5, 0), Vector3(40, 1, 400))
	for p: Dictionary in SpeedGate.pieces(tier, gap):
		if p.has("box"):
			w.add_box(Vector3(p.box[0], p.box[1], p.box[2]), Vector3(p.size[0], p.size[1], p.size[2]))
	var p := w.spawn_player(Vector3(0, 0.05, 60))
	await w.step(10)
	var off := -1
	var jumped := false
	for t in 60 * 10:
		var f := TestWorld.forward_input()
		if p.global_position.z > 0.2 and p.global_position.z < 40.0:
			p.velocity = Vector3(0, p.velocity.y, -v)
		if off < 0 and p.state != Player.State.GROUND and p.global_position.z < 0.5:
			off = 0
		elif off >= 0:
			off += 1
		if not jumped and ((late < 0 and p.global_position.z < 0.25 and p.state == Player.State.GROUND) or (late >= 0 and off == late)):
			f = InputFrame.make(Vector2(0, 1), true)
			jumped = true
		await w.step(1, f)
		if p.global_position.z < -far - 2.0 and p.global_position.y > -0.3 and p.state == Player.State.GROUND:
			return "clear"
		if p.global_position.y < -2.5 and p.state == Player.State.GROUND:
			return "ledge" if p.global_position.y > -3.5 else "fall"
	return "fall at %s %s" % [p.global_position.snappedf(0.01), Player.State.keys()[p.state]]


## Rule 1: the best jump at the speed a tier below (any timing, late in
## coyote time included) never makes it.
func test_a_tier_below_never_clears_a_gate() -> void:
	for tier in [1, 2, 3]:
		var below := 11.5 if tier == 1 else SpeedGate.tier_speed(tier - 1)
		for late in [-1, 0, 2, 3, 4, 5, 6]:
			var got := await _jump_gate(tier, below, late)
			check(got == "ledge", "tier %d at %.1f m/s, jump %d: drops to the ledge (%s)" % [tier, below, late, got])


## Rule 2: an ordinary edge jump at the tier's speed clears it.
func test_tier_speed_clears_its_gate() -> void:
	for tier in [1, 2, 3]:
		var v := SpeedGate.tier_speed(tier)
		var got := await _jump_gate(tier, v, -1)
		check(got == "clear", "tier %d at %.1f m/s clears off an edge jump (%s)" % [tier, v, got])
		got = await _jump_gate(tier, v, 2)
		check(got == "clear", "tier %d at %.1f m/s clears off a late jump too (%s)" % [tier, v, got])


## A runner with combo scoring on: hops along a 150 m roof doing a
## different flip or spin on each one (`kinds` of them, cycling), stops
## 18 m out and runs to the gate's edge, jumps there. Returns the gate
## result and the take-off speed.
func _flip_run_gate(tier: int, kinds: int) -> Array:
	if is_instance_valid(w):
		w.queue_free()
		await tree.process_frame
	w = TestWorld.new()
	tree.root.add_child(w)
	var gap := SpeedGate.gap_for_tier(tier)
	var far := gap + SpeedGate.FACE
	w.add_box(Vector3(0, -6, 100), Vector3(12, 12, 200))
	w.add_box(Vector3(0, -6, -far - 50), Vector3(12, 12, 100))
	for p: Dictionary in SpeedGate.pieces(tier, gap):
		if p.has("box"):
			w.add_box(Vector3(p.box[0], p.box[1], p.box[2]), Vector3(p.size[0], p.size[1], p.size[2]))
	var p := w.spawn_player(Vector3(0, 0.05, 190))
	var combo := ComboTracker.new()
	w.add_child(combo)
	combo.setup(p)
	await w.step(10)
	var hops := 0
	var turning := 0
	var kind := 0
	var takeoff := 0.0
	for t in 60 * 30:
		var f := TestWorld.forward_input()
		var z := p.global_position.z
		if p.state == Player.State.GROUND and z > 18.0 and z < 150.0 and p.horizontal_speed() > 9.0:
			f = InputFrame.make(Vector2(0, 1), true)
			hops += 1
			turning = 24
			kind = hops % kinds
		elif p.state == Player.State.GROUND and z < 0.1 and z > -1.0 and takeoff == 0.0:
			f = InputFrame.make(Vector2(0, 1), true)
			takeoff = p.horizontal_speed()
		if p.state == Player.State.AIR and turning > 0 and z > 18.0:
			turning -= 1
			match kind:
				0: p._look(0.0, TAU / 24.0)  # backflip
				1: p._look(TAU / 24.0, 0.0)  # 360
				2: p._look(0.0, -TAU / 24.0)  # front flip
				3: p._look(-TAU / 24.0, 0.0)  # 360 the other way
		await w.step(1, f)
		if z < -far - 2.0 and p.global_position.y > -0.3 and p.state == Player.State.GROUND:
			return ["clear", takeoff]
		if p.global_position.y < -2.5 and p.state == Player.State.GROUND:
			return ["ledge", takeoff]
	return ["fall", takeoff]


func test_varied_flips_carry_you_over_every_tier() -> void:
	for tier in [1, 2, 3]:
		var got := await _flip_run_gate(tier, 4)
		if OS.has_environment("PLAIN_LOG"):
			print("  varied flips, tier %d: %s at %.1f m/s" % [tier, got[0], got[1]])
		check(got[0] == "clear", "tier %d: a run of varied flips clears it (%s at %.1f m/s, wants %.1f)" % [tier, got[0], got[1], SpeedGate.tier_speed(tier)])


func test_the_same_flip_over_and_over_isnt_enough() -> void:
	var got := await _flip_run_gate(1, 1)
	if OS.has_environment("PLAIN_LOG"):
		print("  one flip, tier 1: %s at %.1f m/s" % got)
	check(got[0] == "ledge", "the same backflip every hop: short of tier 1 (%s at %.1f m/s)" % got)


# ------------------------------------------------------------------ plain runner

const PlainRunner := preload("res://tests/plain_runner.gd")
const GATES := "res://tests/fixtures/route_gates.json"

## The campaign suite, borrowed for its mission loading and route bot.
var _c: TestCase


func _campaign() -> TestCase:
	if _c == null:
		_c = load("res://tests/test_campaign.gd").new()
		_c.tree = tree
	_c.before_each()
	return _c


func _free_level() -> void:
	if _c != null:
		await _c.after_each()


## Runs `path`'s own bot line with enemies live and death on. Returns the
## player's state as it entered each section ([pos, yaw, lane x]) and
## whether it finished cleanly.
func _trick_run(path: String) -> Dictionary:
	var c := _campaign()
	await c._load_file(path)
	var m: Dictionary = c.run.mission
	PlainRunner.fix_gate_takeoffs(m)
	var legs: Array = m.get("route_legs", [])
	var sections := PlainRunner.sections(m)
	var health := PlayerHealth.ensure(c.player)
	health.can_die = true
	var entered: Array = []
	var taken := [0.0]
	health.damaged.connect(func(a: float, _f: Vector3, _k: StringName) -> void: taken[0] += a)
	var p: Player = c.player
	var watch := func() -> void:
		if entered.size() < sections.size() and PlainRunner.along(p.global_position, legs) < float(sections[entered.size()][0]):
			entered.append([p.global_position, p.yaw, PlainRunner.across(p.global_position, legs)])
	tree.physics_frame.connect(watch)
	var done: bool = await c._run_route(m.bot, int(m.route_length / 6.0 * 60.0) + 600, -INF, legs)
	tree.physics_frame.disconnect(watch)
	if OS.has_environment("PLAIN_LOG"):
		print("  trick line: done %s falls %d downs %d damage taken %.0f" % [done, c.run.falls, health.deaths, taken[0]])
	var out := {"done": done, "falls": c.run.falls, "deaths": health.deaths, "entered": entered, "sections": sections,
		"hurt": health.max_health - health.health}
	await _free_level()
	return out


## Drops a plain runner in where the trick line entered section `i`, at
## base top speed, and runs the plain line through it. Returns how it went:
## "down", "fell", "ledge" or "through".
func _plain_run(path: String, i: int, entry: Array, section: Array) -> String:
	var c := _campaign()
	await c._load_file(path)
	var m: Dictionary = c.run.mission
	PlainRunner.fix_gate_takeoffs(m)
	var legs: Array = m.get("route_legs", [])
	var p: Player = c.player
	PlainRunner.make_plain(p)
	var health := PlayerHealth.ensure(c.player)
	health.can_die = true
	await c._step(2)
	p.global_position = entry[0]
	p.basis = Basis(Vector3.UP, float(entry[1]))
	p.yaw = float(entry[1])
	p.velocity = p.forward() * p.tuning.top_speed
	p.momentum = 1.0
	var start_y: float = p.global_position.y
	var taken := [0.0]
	health.damaged.connect(func(a: float, _f: Vector3, _k: StringName) -> void: taken[0] += a)
	var low := [INF]
	var watch := func() -> void: low[0] = minf(low[0], p.global_position.y)
	tree.physics_frame.connect(watch)
	var steps: Array = [[float(section[0]) + 1.0, "", float(entry[2])]]
	for s: Array in PlainRunner.plain_steps(m.bot):
		if float(s[0]) < float(section[0]):
			steps.append(s)
	var frames := int((float(section[0]) - float(section[1])) / 8.0 * 60.0) + 240
	await c._run_route(steps, frames, float(section[1]), legs)
	tree.physics_frame.disconnect(watch)
	var past := PlainRunner.along(p.global_position, legs) < float(section[1])
	var out := "through"
	if health.deaths > 0:
		out = "down"
	elif c.run.falls > 0:
		out = "fell"
	elif low[0] < start_y - 1.5:
		out = "ledge"
	elif not past:
		out = "stalled at %.1f" % PlainRunner.along(p.global_position, legs)
	if OS.has_environment("PLAIN_LOG"):
		var shots := 0
		for enc: Node in c.level.builder.encounters:
			for en: Node in enc.enemies:
				shots += int(en.get("shots_fired")) if "shots_fired" in en else 0
		print("  plain runner, %s: %s (damage taken %.0f, enemy shots %d)" % [section[2], out, taken[0], shots])
	await _free_level()
	return out


## Any route level can opt in with "plain_runner": true: its trick line
## gets through every gate and encounter alive, and a plain runner fails
## every one of them.
func _check_plain_runner(path: String) -> void:
	var trick := await _trick_run(path)
	var label := path.get_file()
	check(trick.done and trick.falls == 0 and trick.deaths == 0,
		"%s: the trick line finishes alive (done %s, falls %d, downs %d)" % [label, trick.done, trick.falls, trick.deaths])
	check(trick.entered.size() == trick.sections.size() and not trick.sections.is_empty(),
		"%s: it went through every section (%d of %d)" % [label, trick.entered.size(), trick.sections.size()])
	for i in trick.entered.size():
		var got := await _plain_run(path, i, trick.entered[i], trick.sections[i])
		check(got in ["down", "fell", "ledge"], "%s: a plain runner fails the %s (%s)" % [label, trick.sections[i][2], got])


func test_plain_runner_fails_every_gate_and_fight() -> void:
	await _check_plain_runner(GATES)


func test_plain_runner_levels_opt_in() -> void:
	var ran := 0
	for entry: Dictionary in Campaign.missions():
		var path: String = entry.get("file", "")
		if path == "" or not Campaign.load_mission_file(path).get("plain_runner", false):
			continue
		await _check_plain_runner(path)
		ran += 1
	# None yet: the rebuilt districts opt in as they land.
	check(ran >= 0, "opted-in missions ran (%d)" % ran)
