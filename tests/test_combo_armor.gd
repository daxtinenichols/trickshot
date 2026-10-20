extends TestCase
## Combo armor: enemy shots land less often the faster and wilder you move
## (enemies/combo_armor.gd), and the HUD warns when you're an easy target.

const ComboArmor := preload("res://enemies/combo_armor.gd")

var w: TestWorld


func before_each() -> void:
	w = TestWorld.new()
	tree.root.add_child(w)
	ComboArmor.enabled = true


func after_each() -> void:
	ComboArmor.enabled = true
	w.queue_free()
	await tree.process_frame


func _player() -> Player:
	w.add_floor()
	var p := w.spawn_player(Vector3(0, 0.05, 0))
	PlayerHealth.ensure(p)
	await w.step(10)
	return p


func _at_speed(p: Player, v: float) -> void:
	p.velocity = Vector3(0, 0, -v)


func test_exposure_falls_with_speed() -> void:
	var p := await _player()
	_at_speed(p, 0.0)
	check(is_equal_approx(ComboArmor.exposure(p), 1.5), "standing still: 1.5 (%.2f)" % ComboArmor.exposure(p))
	_at_speed(p, p.tuning.top_speed)
	check(is_equal_approx(ComboArmor.exposure(p), 0.7), "top speed: 0.7 (%.2f)" % ComboArmor.exposure(p))
	_at_speed(p, 18.0)
	check(is_equal_approx(ComboArmor.exposure(p), 0.4), "15 m/s and up: 0.4 (%.2f)" % ComboArmor.exposure(p))
	_at_speed(p, 9.0)
	var mid := ComboArmor.exposure(p)
	check(mid < 1.5 and mid > 0.7, "in between at 9 m/s (%.2f)" % mid)


func test_tricks_and_combos_lower_exposure() -> void:
	var p := await _player()
	_at_speed(p, p.tuning.top_speed)
	var base := ComboArmor.exposure(p)
	p.state = Player.State.SLIDE
	check(is_equal_approx(ComboArmor.exposure(p), base * 0.6), "sliding x0.6 (%.3f)" % ComboArmor.exposure(p))
	p.state = Player.State.WALLRUN
	check(is_equal_approx(ComboArmor.exposure(p), base * 0.6), "wallrunning x0.6")
	p.state = Player.State.GROUND
	p.combo_source = func() -> int: return 1
	check(is_equal_approx(ComboArmor.exposure(p), base), "a 1x combo isn't armor yet")
	p.combo_source = func() -> int: return 2
	check(is_equal_approx(ComboArmor.exposure(p), base * 0.85), "a 2x combo x0.85")


func test_a_flip_in_progress_is_tricking() -> void:
	var p := await _player()
	await w.press(InputFrame.make(Vector2(0, 1), true))
	await w.step(4)
	check(p.state == Player.State.AIR and not p.is_tricking_in_air(), "a plain jump is no trick")
	p._air_pitch = -PI * 0.5
	check(p.is_tricking_in_air(), "half way round a backflip is")


func _hit_rate(p: Player, n := 2000) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var hits := 0
	var dir := Vector3(0, 0, 1)
	var from := EnemyMath.player_chest(p) - dir * 15.0
	for i in n:
		if ComboArmor.shot_dir(dir, from, p, rng).is_equal_approx(dir):
			hits += 1
	return float(hits) / n


func test_slow_targets_get_hit_fast_ones_mostly_dont() -> void:
	var p := await _player()
	_at_speed(p, 0.0)
	var still := _hit_rate(p)
	check(still > 0.99, "a still target is always hit (%.2f)" % still)
	_at_speed(p, p.tuning.top_speed)
	var plain := _hit_rate(p)
	check(absf(plain - 0.49) < 0.04, "a plain line at top speed: about 1 in 2 (%.2f)" % plain)
	_at_speed(p, 15.0)
	p.state = Player.State.WALLRUN
	p.combo_source = func() -> int: return 3
	var fast := _hit_rate(p)
	check(fast < 0.1, "fast, tricking and in a combo: under 1 in 10 (%.2f)" % fast)


func test_misses_pass_close_but_clear() -> void:
	var p := await _player()
	_at_speed(p, 18.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var chest := EnemyMath.player_chest(p)
	var from := chest + Vector3(4, 1, 15)
	var dir := (chest - from).normalized()
	var misses := 0
	var closest := INF
	var farthest := 0.0
	var below := false
	for i in 400:
		var d := ComboArmor.shot_dir(dir, from, p, rng)
		if d.is_equal_approx(dir):
			continue
		misses += 1
		var miss := EnemyMath.point_segment_distance(chest, from, from + d * 40.0)
		closest = minf(closest, miss)
		farthest = maxf(farthest, miss)
		var at := from + d * from.distance_to(chest)
		below = below or at.y < chest.y - 0.05
	check(misses > 200, "most shots at a fast target miss (%d of 400)" % misses)
	check(closest > 0.8 and farthest < 1.7, "misses pass 0.9-1.6 m off the chest (%.2f..%.2f)" % [closest, farthest])
	check(not below, "never into the floor at your feet")


func test_a_raider_misses_a_fast_target_more() -> void:
	# The same raider, the same seed: a still target vs one that's marked
	# fast and tricking (velocity pinned each tick so the aim and lead
	# don't change: only the armor roll does).
	var hurt := []
	for fast: bool in [false, true]:
		var p := await _player()
		var r := Raider.new()
		r.position = Vector3(0, 0, -15)
		r.seed_value = 11
		w.add_child(r)
		r.activate(p)
		if fast:
			p.combo_source = func() -> int: return 3
		var health := PlayerHealth.of(p)
		health.can_die = false
		health.regen_rate = 0.0
		var taken := [0.0]
		health.damaged.connect(func(a: float, _f: Vector3, _k: StringName) -> void: taken[0] += a)
		for i in 60 * 20:
			if fast:
				p.state = Player.State.WALLRUN
				p.velocity = Vector3(0, 0, -15.0)
				p.global_position = Vector3(0, 0.05, 0)
			await w.step(1)
		hurt.append([taken[0], r.shots_fired])
		w.queue_free()
		await tree.process_frame
		w = TestWorld.new()
		tree.root.add_child(w)
	check(hurt[0][1] >= 6 and hurt[1][1] >= 6, "both drew plenty of shots (%s)" % [hurt])
	check(hurt[1][0] < hurt[0][0] * 0.4, "the fast target takes far less (%s)" % [hurt])


func test_hud_warns_only_when_aimed_at_and_exposed() -> void:
	var p := await _player()
	var overlay: Node = preload("res://enemies/hurt_overlay.gd").new()
	w.add_child(overlay)
	overlay.setup(PlayerHealth.of(p))
	check(overlay.exposed_warning() == 0.0, "nobody aiming: no warning")
	var r := Raider.new()
	r.position = Vector3(0, 0, -15)
	w.add_child(r)
	r.activate(p)
	var ok := await w.step_until(func() -> bool: return r.is_aiming(), 300)
	check(ok, "the raider takes aim")
	_at_speed(p, 0.0)
	check(overlay.exposed_warning() > 0.9, "standing in its sights: full warning (%.2f)" % overlay.exposed_warning())
	_at_speed(p, 14.0)
	check(overlay.exposed_warning() == 0.0, "fast: no warning (%.2f)" % overlay.exposed_warning())
