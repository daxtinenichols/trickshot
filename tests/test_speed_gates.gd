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
	check(g1 > SpeedGate.BEST_AT_TOP and g1 < g2 and g2 < g3, "wider each tier (%.2f %.2f %.2f)" % [g1, g2, g3])
	check(is_equal_approx(SpeedGate.tier_speed(2), 14.5), "tier 2 wants top speed + 3")


## The gate in a test world: take-off roof edge at z 0 (running -z), the
## far roof, and the gate's own pieces. Runs in at `v`, jumps `late`
## frames after leaving the edge (-1: 0.1 m before it). Returns "clear",
## "ledge" or "fall".
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
		if not jumped and ((late < 0 and p.global_position.z < 0.1 and p.state == Player.State.GROUND) or (late >= 0 and off == late)):
			f = InputFrame.make(Vector2(0, 1), true)
			jumped = true
		await w.step(1, f)
		if p.global_position.z < -far - 2.0 and p.global_position.y > -0.3 and p.state == Player.State.GROUND:
			return "clear"
		if p.global_position.y < -2.5 and p.state == Player.State.GROUND:
			return "ledge" if p.global_position.y > -3.5 else "fall"
	return "fall at %s %s" % [p.global_position.snappedf(0.01), Player.State.keys()[p.state]]


func test_top_speed_never_clears_a_gate() -> void:
	for tier in [1, 2, 3]:
		for late in [-1, 0, 2, 4, 5, 6]:
			var got := await _jump_gate(tier, 11.5, late)
			check(got == "ledge", "tier %d at top speed, jump %d: drops to the ledge (%s)" % [tier, late, got])


func test_tier_speed_clears_its_gate() -> void:
	for tier in [1, 2, 3]:
		# Tier 1 also wants a jump right at the edge (its gap is set by the
		# best jump at top speed, which is wider than an edge jump at 13).
		var v := SpeedGate.tier_speed(tier) + (0.3 if tier == 1 else 0.0)
		var got := await _jump_gate(tier, v, -1)
		check(got == "clear", "tier %d at %.1f m/s clears (%s)" % [tier, v, got])
		got = await _jump_gate(tier, v, 3)
		check(got == "clear", "tier %d at %.1f m/s clears off a late jump too (%s)" % [tier, v, got])


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
