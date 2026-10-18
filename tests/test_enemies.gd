extends TestCase
## Enemies: raiders (guns, cover, telegraphed shots) and mutants (rush,
## leap, swipe). Hit zones, kills feeding the combo, dodging by moving,
## kicks and headshot flinches, the encounter flow, player health, and
## determinism. Coordinates: the player faces -Z at yaw 0.

const SANDBOX := preload("res://levels/sandbox.tscn")

var w: TestWorld
var hits: Array[Dictionary] = []


func before_each() -> void:
	w = TestWorld.new()
	tree.root.add_child(w)
	hits.clear()


func after_each() -> void:
	w.queue_free()
	await tree.process_frame


func _setup(pos := Vector3(0, 0.05, 0), yaw := 0.0) -> Player:
	w.add_floor()
	var p := w.spawn_player(pos, yaw)
	PlayerHealth.ensure(p)
	(p.weapon as Pistol).hit.connect(func(info: Dictionary) -> void: hits.append(info))
	await w.step(10)
	return p


func _health() -> PlayerHealth:
	return PlayerHealth.of(w.player)


func _raider(pos: Vector3, active := true) -> Raider:
	var r := Raider.new()
	r.position = pos
	w.add_child(r)
	if active:
		r.activate(w.player)
	return r


func _mutant(pos: Vector3, active := true) -> Mutant:
	var m := Mutant.new()
	m.position = pos
	w.add_child(m)
	if active:
		m.activate(w.player)
	return m


func _encounter(size := Vector3(80, 20, 80), center := Vector3.ZERO) -> EnemyEncounter:
	var e := EnemyEncounter.new()
	w.add_child(e)
	e.bounds = AABB(center - size * 0.5, size)
	e.entry = Transform3D(Basis.IDENTITY, center + Vector3(0, 0.1, size.z * 0.5 + 5.0))
	e.setup(w.player)
	return e


## Turn the view to look at a point (yaw and pitch).
func _aim(point: Vector3) -> void:
	var p := w.player
	var eye := p.global_position + Vector3(0, p.head.position.y, 0)
	var d := point - eye
	p.yaw = atan2(-d.x, -d.z)
	p.pitch = atan2(d.y, Vector2(d.x, d.z).length())
	p.rotation = Vector3(0, p.yaw, 0)
	p.head.rotation = Vector3(p.pitch + p.view_kick().x, 0, 0)


func _shoot(point: Vector3) -> void:
	var gun := w.player.weapon as Pistol
	_aim(point)
	gun.trigger_pressed = true
	gun.trigger_held = true
	await w.step(1)
	gun.trigger_held = false
	# Let bloom and recoil settle so the next shot is exact too.
	await w.step(30)


func _bullets() -> int:
	var n := 0
	for c in w.get_children():
		if c is EnemyProjectile and not (c as EnemyProjectile).done:
			n += 1
	return n


# ------------------------------------------------------------------ math

func test_segment_distance() -> void:
	check_near(EnemyMath.segment_distance(Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(0, -1, 2), Vector3(0, 1, 2)), 2.0, 0.001, "crossing segments")
	check_near(EnemyMath.segment_distance(Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(3, 0, 0), Vector3(4, 0, 0)), 2.0, 0.001, "end to end")
	check_near(EnemyMath.point_segment_distance(Vector3(0, 5, 0), Vector3(0, 0, 0), Vector3(0, 2, 0)), 3.0, 0.001, "point past the end")
	check_near(EnemyMath.turn_yaw(0.0, 2.0, 0.5), 0.5, 0.001, "turns at most the step")
	check_near(EnemyMath.turn_yaw(3.0, -3.0, 1.0), 3.0 + (TAU - 6.0), 0.001, "turns the short way round")


# ------------------------------------------------------------------ hit zones and kills

func test_raider_head_and_body_zones() -> void:
	await _setup()
	var r := _raider(Vector3(0, 0, -12), false)
	await w.step(2)
	await _shoot(r.global_position + Vector3(0, 1.0, 0))
	check(hits.size() == 1 and hits[0].zone == &"body" and hits[0].target == r, "chest shot hits the body zone")
	await _shoot(r.head_position())
	check(hits.size() == 2 and hits[1].zone == &"head", "head shot hits the head zone")
	if hits.size() == 2:
		check(hits[1].damage > hits[0].damage * 2.0, "headshots hit much harder")
	check(not r.is_dead, "one head and one body shot don't kill (%.0f hp left)" % r.health)
	await _shoot(r.head_position())
	check(r.is_dead and hits.size() == 3 and hits[2].killed, "a second headshot kills")


func test_mutant_head_is_readable_and_forward() -> void:
	await _setup()
	var m := _mutant(Vector3(0, 0, -12), false)
	m.yaw = PI
	m.rotation.y = PI
	await w.step(2)
	# The hunched head sits ahead of the body, toward you.
	check((m.head_position() - m.global_position).dot(m.forward()) > 0.2, "head sits ahead of the body")
	await _shoot(m.head_position())
	check(hits.size() == 1 and hits[0].zone == &"head", "head zone hit")
	await _shoot(m.head_position())
	check(m.is_dead, "two headshots kill a mutant")


func test_kill_finishes_the_combo_on_the_kill() -> void:
	var c := ComboTracker.new()
	w.add_child(c)
	var p := await _setup()
	c.setup(p, p.weapon as Pistol)
	var summaries: Array[Dictionary] = []
	c.finished.connect(func(s: Dictionary) -> void: summaries.append(s))
	var r := _raider(Vector3(0, 0, -12), false)
	await w.step(2)
	await _shoot(r.head_position())
	c.on_trick(&"slide", {})  # keep a combo going between the shots
	await _shoot(r.head_position())
	check(r.is_dead, "raider down")
	check(summaries.size() >= 1 and summaries.back().reason == &"kill", "the kill banked the combo")
	if summaries.size() >= 1:
		check(summaries.back().entries.back().name == &"combo_kill", "the chain ends on the kill")


func test_dead_enemies_stop_blocking_shots() -> void:
	await _setup()
	var front := _raider(Vector3(0, 0, -10), false)
	var back := _raider(Vector3(0, 0, -18), false)
	await w.step(2)
	front.take_hit({"damage": 1000.0})
	await w.step(2)
	await _shoot(back.global_position + Vector3(0, 1.0, 0))
	check(hits.size() == 1 and hits[0].target == back, "shots pass through a body on the ground")


# ------------------------------------------------------------------ raiders

func test_raider_telegraphs_every_shot() -> void:
	await _setup()
	var r := _raider(Vector3(0, 0, -15))
	var aim_start := -1
	var lock_start := -1
	var fired_at := -1
	for i in 240:
		await w.step(1)
		if aim_start < 0 and r.is_aiming():
			aim_start = i
		if lock_start < 0 and r.is_locked():
			lock_start = i
		if fired_at < 0 and r.shots_fired > 0:
			fired_at = i
			break
	check(aim_start >= 0 and fired_at > 0, "the raider aimed and fired (aim %d, fire %d)" % [aim_start, fired_at])
	check(fired_at - aim_start >= roundi(r.windup * 60.0) - 1, "aims for the whole windup first (%d ticks)" % (fired_at - aim_start))
	check(fired_at - lock_start >= roundi(r.lock_time * 60.0) - 1, "the lock warns before the shot (%d ticks)" % (fired_at - lock_start))
	check(r.telegraph == 0.0, "telegraph clears after the shot")


func test_standing_still_gets_you_shot() -> void:
	await _setup()
	_raider(Vector3(0, 0, -15))
	await w.step(240)
	check(_health().health < _health().max_health, "a still target gets hit (%.0f hp)" % _health().health)


func test_circle_strafing_dodges_the_shots() -> void:
	await _setup(Vector3(0, 0.05, 0))
	var r := _raider(Vector3(0, 0, -15))
	var f := InputFrame.make(Vector2(1, 0))
	for i in 420:
		# Keep looking at the raider while running sideways around it.
		_aim(r.global_position + Vector3(0, 1.4, 0))
		await w.step(1, f)
	check(r.shots_fired >= 3, "the raider kept shooting (%d shots)" % r.shots_fired)
	check(_health().health >= _health().max_health - 0.01, "every shot missed a moving target (%.0f hp)" % _health().health)


func test_raider_backs_off_when_you_close_in() -> void:
	await _setup()
	var r := _raider(Vector3(0, 0, -4))
	var before := r.distance_to_player()
	await w.step(150)
	check(r.distance_to_player() > before + 3.0, "backed away (%.1f -> %.1f m)" % [before, r.distance_to_player()])


func test_raider_takes_cover_and_ducks_behind_it() -> void:
	await _setup()
	var e := _encounter()
	# A low wall 14 m ahead, the raider a little off to the side behind it.
	var wall := Vector3(0, 0, -14)
	w.add_box(wall + Vector3(0, 0.6, 0), Vector3(6, 1.2, 0.5))
	e.add_cover_wall(wall, 6, 0.5)
	var r := Raider.new()
	e.add_enemy(r, Transform3D(Basis.IDENTITY, Vector3(5, 0, -22)))
	await w.step(2)
	e.start()
	var ducked_head := INF
	var standing_head := -INF
	var reached := false
	for i in 600:
		await w.step(1)
		if r.state == Raider.State.HOLD and r.cover.size() > 0 and r.global_position.distance_to(r.cover.pos) < 0.6:
			reached = true
		if r.state == Raider.State.RELOAD and r.duck > 0.99:
			ducked_head = minf(ducked_head, r.head_position().y)
		if r.is_locked():
			standing_head = maxf(standing_head, r.head_position().y)
	check(reached, "reached a cover spot")
	check(r.cover.size() > 0 and r.cover.pos.z < wall.z, "the spot is on the far side of the wall")
	check(ducked_head < 1.2, "ducked behind the wall while reloading (head at %.2f m)" % ducked_head)
	check(standing_head > 1.5, "stands up to shoot (head at %.2f m)" % standing_head)


func test_headshot_flinch_cancels_the_shot() -> void:
	await _setup()
	var r := _raider(Vector3(0, 0, -12))
	r.max_health = 1000.0
	r.health = 1000.0
	var ok := await w.step_until(func() -> bool: return r.is_aiming() and r.state_time > 0.2, 200)
	check(ok, "raider started aiming")
	await _shoot(r.head_position())
	check(not r.is_aiming(), "the headshot interrupted the aim")
	check(r.shots_fired == 0, "the shot never went off")


func test_only_a_few_raiders_aim_at_once() -> void:
	await _setup()
	var e := _encounter()
	for i in 4:
		e.add_enemy(Raider.new(), Transform3D(Basis.IDENTITY, Vector3(-6 + i * 4, 0, -16)))
	await w.step(2)
	e.start()
	var most := 0
	for i in 300:
		await w.step(1)
		var n := 0
		for en in e.enemies:
			if (en as Raider).is_aiming():
				n += 1
		most = maxi(most, n)
	check(most == e.max_aiming, "at most %d aiming together (saw %d)" % [e.max_aiming, most])


# ------------------------------------------------------------------ mutants

func test_mutant_runs_down_a_standing_player() -> void:
	await _setup()
	var m := _mutant(Vector3(0, 0, -12))
	await w.step(300)
	check(_health().health < _health().max_health, "it caught you (%.0f hp)" % _health().health)
	check(m.leaps + m.swipes >= 1, "it attacked (%d leaps, %d swipes)" % [m.leaps, m.swipes])


func test_mutant_leap_telegraphs_and_leaves_it_winded() -> void:
	await _setup()
	var m := _mutant(Vector3(0, 0, -14))
	var ok := await w.step_until(func() -> bool: return m.state == Mutant.State.LEAP_WINDUP, 240)
	check(ok, "it wound up a leap")
	var windup_ticks := 0
	while m.state == Mutant.State.LEAP_WINDUP and windup_ticks < 120:
		await w.step(1)
		windup_ticks += 1
	check(windup_ticks >= roundi(m.leap_windup * 60.0) - 1, "the windup gives time to react (%d ticks)" % windup_ticks)
	ok = await w.step_until(func() -> bool: return m.is_winded(), 120)
	check(ok, "winded after landing")


func test_sidestep_dodges_the_leap() -> void:
	await _setup()
	var m := _mutant(Vector3(0, 0, -9))
	var ok := await w.step_until(func() -> bool: return m.state == Mutant.State.LEAP_WINDUP, 240)
	check(ok, "it wound up a leap")
	await w.step_until(func() -> bool: return m.state == Mutant.State.LEAP, 60)
	# It's in the air: run sideways.
	var before := _health().health
	await w.step_until(func() -> bool: return m.state != Mutant.State.LEAP, 120, InputFrame.make(Vector2(1, 0)))
	check(_health().health >= before, "the leap missed (%.0f -> %.0f hp)" % [before, _health().health])


func test_mutant_ignores_you_off_its_patch() -> void:
	await _setup()
	var m := _mutant(Vector3(0, 0, -30))
	await w.step(240)
	check(_health().health >= _health().max_health, "no damage from far away")
	check(m.global_position.distance_to(Vector3(0, 0, -30)) < 1.0, "stayed home (moved %.1f m)" % m.global_position.distance_to(Vector3(0, 0, -30)))


func test_mutant_gives_up_when_you_leave_its_patch() -> void:
	await _setup()
	var m := _mutant(Vector3(0, 0, -8))
	await w.step(20)
	check(m.state == Mutant.State.CHASE or m.state == Mutant.State.LEAP_WINDUP or m.state == Mutant.State.SWIPE_WINDUP, "it comes for you up close")
	# Teleport well off its patch: it stops and walks home.
	w.player.global_position = Vector3(0, 0.05, 30)
	var ok := await w.step_until(func() -> bool: return m.is_returning(), 120)
	check(ok, "gave up the chase")
	await w.step(600)
	check(m.global_position.distance_to(Vector3(0, 0, -8)) < 1.0, "walked back home")


func test_mutant_gives_up_a_long_chase() -> void:
	await _setup()
	var m := _mutant(Vector3(0, 0, -6))
	m.leash_radius = 500.0
	m.give_up_time = 3.0
	m.leap_max = 0.0  # chase and swipe only
	# Keep running away at full tilt, out of reach.
	var ok := await w.step_until(func() -> bool: return m.is_returning(), 360, InputFrame.make(Vector2(0, -1)))
	check(ok, "stopped chasing after a while")
	if ok:
		check(m.state_time < 0.1 and m.hits_landed == 0, "never caught you")


func test_kick_knocks_a_mutant_back_and_cancels_its_attack() -> void:
	await _setup()
	var m := _mutant(Vector3(0, 0, -1.6))
	await w.step_until(func() -> bool: return m.state == Mutant.State.SWIPE_WINDUP, 60)
	_aim(m.global_position + Vector3(0, 1.0, 0))
	var before := m.global_position.z
	await w.press(InputFrame.make(Vector2.ZERO, false, false, true))
	check(m.is_staggered(), "kicked into a stagger")
	check(m.state == Mutant.State.CHASE, "the swipe was cancelled")
	await w.step(10)
	check(m.global_position.z < before - 0.5, "knocked back (%.2f -> %.2f)" % [before, m.global_position.z])
	check(_health().health >= _health().max_health, "no damage taken")


func test_mutant_hops_low_cover() -> void:
	await _setup()
	w.add_box(Vector3(0, 0.6, -8), Vector3(10, 1.2, 0.5))
	var m := _mutant(Vector3(0, 0, -16))
	m.leap_max = 0.0  # chase only
	var ok := await w.step_until(func() -> bool: return m.global_position.z > -7.0, 300)
	check(ok, "got over the wall (at z %.1f)" % m.global_position.z)


# ------------------------------------------------------------------ player health

func test_health_regenerates_after_a_break() -> void:
	await _setup()
	var h := _health()
	h.take_damage(40.0, Vector3.ZERO)
	await w.step(60)
	check_near(h.health, 60.0, 0.01, "no regen right away")
	await w.step(roundi((h.regen_delay + 60.0 / h.regen_rate) * 60.0))
	check_near(h.health, h.max_health, 0.01, "back to full")


func test_going_down_respawns_and_bails_the_combo() -> void:
	var c := ComboTracker.new()
	w.add_child(c)
	var p := await _setup(Vector3(0, 0.05, 0))
	c.setup(p, p.weapon as Pistol)
	p.set_spawn(Transform3D(Basis.IDENTITY, Vector3(30, 0.1, 30)))
	c.on_trick(&"slide", {})
	var bails: Array[StringName] = []
	c.bailed.connect(func(_pts: int, reason: StringName) -> void: bails.append(reason))
	_health().take_damage(500.0, Vector3.ZERO)
	check(p.global_position.distance_to(Vector3(30, 0.1, 30)) < 0.5, "back at the spawn")
	check(_health().health == _health().max_health, "full health again")
	check(bails == [&"respawn"], "the combo was lost")


# ------------------------------------------------------------------ encounter

func test_encounter_waits_for_you_then_fights() -> void:
	await _setup(Vector3(0, 0.05, 30))
	var e := _encounter(Vector3(40, 20, 40))
	var r := Raider.new()
	e.add_enemy(r, Transform3D(Basis.IDENTITY, Vector3(0, 0, -10)))
	await w.step(120)
	check(e.phase == EnemyEncounter.Phase.WAITING and not r.active, "waits while you're outside")
	check(r.shots_fired == 0, "doesn't shoot from outside")
	w.player.global_position = Vector3(0, 0.05, 10)
	await w.step(2)
	check(e.phase == EnemyEncounter.Phase.ACTIVE and r.active, "starts when you step in")


func test_encounter_resets_when_you_go_down() -> void:
	await _setup(Vector3(0, 0.05, 10))
	var e := _encounter(Vector3(40, 20, 40))
	var r := Raider.new()
	var m := Mutant.new()
	e.add_enemy(r, Transform3D(Basis.IDENTITY, Vector3(-5, 0, -10)))
	e.add_enemy(m, Transform3D(Basis.IDENTITY, Vector3(5, 0, -10)))
	await w.step(90)
	check(e.phase == EnemyEncounter.Phase.ACTIVE, "fight on")
	m.take_hit({"damage": 1000.0})
	_health().take_damage(500.0, Vector3.ZERO)
	check(w.player.global_position.distance_to(e.entry.origin) < 0.5, "back at the arena entrance")
	check(not e.bounds.has_point(w.player.global_position), "the entrance is outside the fight")
	check(e.phase == EnemyEncounter.Phase.WAITING, "fight reset")
	check(not m.is_dead and m.health == m.max_health, "the dead come back")
	check(r.global_position.distance_to(Vector3(-5, 0, -10)) < 0.2 and not r.active, "everyone back at their spawn")


func test_encounter_clears_and_restarts() -> void:
	await _setup(Vector3(0, 0.05, 10))
	var e := _encounter(Vector3(40, 20, 40))
	e.restart_time = 1.0
	var r := Raider.new()
	e.add_enemy(r, Transform3D(Basis.IDENTITY, Vector3(0, 0, -10)))
	await w.step(5)
	r.take_hit({"damage": 1000.0})
	check(e.phase == EnemyEncounter.Phase.CLEARED, "cleared")
	await w.step(65)
	check(e.phase != EnemyEncounter.Phase.CLEARED and not r.is_dead, "restarted")


func test_mission_encounters_keep_the_dead_dead() -> void:
	await _setup(Vector3(0, 0.05, 10))
	var e := _encounter(Vector3(40, 20, 40))
	e.keep_dead = true
	var r := Raider.new()
	var m := Mutant.new()
	e.add_enemy(r, Transform3D(Basis.IDENTITY, Vector3(-5, 0, -10)))
	e.add_enemy(m, Transform3D(Basis.IDENTITY, Vector3(5, 0, -10)))
	await w.step(90)
	m.take_hit({"damage": 1000.0})
	_health().take_damage(500.0, Vector3.ZERO)
	check(e.phase == EnemyEncounter.Phase.WAITING, "fight reset")
	check(m.is_dead and not m.visible, "the killed mutant stays dead")
	check(not r.is_dead and r.global_position.distance_to(Vector3(-5, 0, -10)) < 0.2, "the raider went back to its spot")
	w.player.global_position = Vector3(0, 0.05, 10)
	await w.step(2)
	check(e.phase == EnemyEncounter.Phase.ACTIVE, "back in the fight")
	r.take_hit({"damage": 1000.0})
	check(e.phase == EnemyEncounter.Phase.CLEARED, "cleared")
	w.player.global_position = Vector3(0, 0.05, 40)
	await w.step(int(60 * (e.leave_reset_time + 0.5)))
	check(r.is_dead and m.is_dead and e.phase == EnemyEncounter.Phase.CLEARED, "leaving doesn't bring them back either")
	e.reset(true)
	check(not r.is_dead and not m.is_dead and r.visible, "a fresh run brings everyone back")


# ------------------------------------------------------------------ kicks

func _kick_at(target: Vector3) -> void:
	_aim(target)
	await w.press(InputFrame.make(Vector2.ZERO, false, false, true))


func test_kick_hurts_and_knocks_a_raider_down() -> void:
	await _setup()
	var r := _raider(Vector3(0, 0, -1.4), false)
	await w.step(2)
	var standing_head := r.head_position().y
	await _kick_at(r.global_position + Vector3(0, 1.0, 0))
	check_near(r.health, r.max_health - r.kick_damage, 0.5, "kick damage")
	check(r.is_knocked_down(), "knocked down")
	r.health = 1000.0  # so the headshot below doesn't kill it
	await w.step(20)
	check(r.global_position.z < -1.8, "sent flying back (%.2f)" % r.global_position.z)
	check(r.head_position().y < standing_head - 1.0, "lying down: the head zone is on the floor (%.2f)" % r.head_position().y)
	# From the side (from its feet, the chest hides the head).
	w.player.global_position = Vector3(3.0, 0.05, r.head_position().z)
	await w.step(1)
	await _shoot(r.head_position())
	check(hits.size() == 1 and hits[0].zone == &"head", "headshot on the floor")
	await w.step(int(60 * r.knockdown_time))
	check(not r.is_knocked_down() and absf(r.head_position().y - standing_head) < 0.15, "back on its feet (%.2f vs %.2f)" % [r.head_position().y, standing_head])


func test_kick_damage_scales_with_the_combo() -> void:
	await _setup()
	w.player.kick_damage_scale = func() -> float: return 2.5
	var r := _raider(Vector3(0, 0, -1.4), false)
	await w.step(2)
	await _kick_at(r.global_position + Vector3(0, 1.0, 0))
	check_near(r.health, r.max_health - r.kick_damage * 2.5, 0.5, "x2.5 kick")


func test_kick_kill_is_a_trick() -> void:
	await _setup()
	var tricks: Array[StringName] = []
	w.player.trick.connect(func(n: StringName, _i: Dictionary) -> void: tricks.append(n))
	var r := _raider(Vector3(0.6, 0, -1.3), false)
	await w.step(2)
	r.health = 10.0
	# Not quite looking at it: the kick still lands.
	await _kick_at(r.global_position + Vector3(-0.7, 1.0, 0))
	check(r.is_dead, "kicked to death")
	check(&"kick" in tricks and &"kick_kill" in tricks, "kick and kick kill (%s)" % [tricks])


func test_heavies_and_brutes_only_stagger() -> void:
	await _setup()
	var h: Enemy = load("res://enemies/heavy.gd").new()
	h.position = Vector3(0, 0, -1.4)
	w.add_child(h)
	await w.step(2)
	await _kick_at(h.global_position + Vector3(0, 1.0, 0))
	check(h.health < h.max_health, "the kick hurts")
	check(h.is_staggered() and not h.is_knocked_down(), "but it stays on its feet")


# ------------------------------------------------------------------ hit zones follow the body

func test_hit_zones_are_body_shaped() -> void:
	await _setup()
	var r := _raider(Vector3(0, 0, -10), false)
	await w.step(2)
	# Inside where the old box was, but past the thigh: a miss now.
	(w.player.weapon as Pistol).aim_assist = 0.0
	await _shoot(r.global_position + Vector3(0.27, 0.45, 0))
	check(not hits.any(func(h: Dictionary) -> bool: return h.target == r), "a shot past the leg misses")
	hits.clear()
	await _shoot(r.global_position + Vector3(0.1, 0.45, 0))
	check(hits.size() == 1 and hits[0].target == r and hits[0].zone == &"body", "the leg itself is hit")


func test_hit_zones_duck_with_the_raider() -> void:
	await _setup()
	var r := _raider(Vector3(0, 0, -10), false)
	await w.step(2)
	var standing := r.head_position()
	r.duck = 1.0
	await w.step(1)
	check(r.head_position().y < standing.y - 0.4, "ducked head zone (%.2f -> %.2f)" % [standing.y, r.head_position().y])
	await _shoot(standing)
	check(hits.is_empty() or hits[0].zone != &"head", "no headshot where its head was")


func test_aiming_puts_the_arms_up() -> void:
	await _setup()
	var r := _raider(Vector3(0, 0, -10), false)
	await w.step(2)
	var hand_low: Vector3 = r.hit_rig.parts["RightLowerArm"].global_position
	r.state = Raider.State.AIM
	r.aim_dir = Vector3(0, 0, 1)
	await w.step(1)
	var hand_up: Vector3 = r.hit_rig.parts["RightLowerArm"].global_position
	check(hand_up.y > hand_low.y + 0.15, "forearm raised to the rifle (%.2f -> %.2f)" % [hand_low.y, hand_up.y])


# ------------------------------------------------------------------ difficulty

func test_difficulty_makes_enemies_quicker() -> void:
	await _setup()
	var r := _raider(Vector3(0, 0, -12), false)
	var windup := r.windup
	var speed := r.move_speed
	r.activate(w.player)
	check(r.windup < windup and r.move_speed > speed, "quicker to aim and on its feet")
	check(r.aim_lead >= 0.5, "leads a runner")
	r.deactivate()
	var again := r.windup
	r.activate(w.player)
	check(r.windup == again, "applied once")


# ------------------------------------------------------------------ determinism

func _run_scripted_fight() -> Array:
	var p := await _setup(Vector3(0, 0.05, 6))
	var e := _encounter(Vector3(60, 20, 60))
	var wall := Vector3(0, 0, -6)
	w.add_box(wall + Vector3(0, 0.6, 0), Vector3(6, 1.2, 0.5))
	e.add_cover_wall(wall, 6, 0.5)
	e.add_enemy(Raider.new(), Transform3D(Basis.IDENTITY, Vector3(-6, 0, -18)))
	e.add_enemy(Raider.new(), Transform3D(Basis.IDENTITY, Vector3(6, 0, -18)))
	e.add_enemy(Mutant.new(), Transform3D(Basis.IDENTITY, Vector3(0, 0, -24)))
	var trace := []
	for i in 360:
		var f := InputFrame.make(Vector2(1.0 if (i / 60) % 2 == 0 else -1.0, 0.3))
		await w.step(1, f)
		if i % 30 == 0:
			for en in e.enemies:
				trace.append(en.global_position.snappedf(0.0001))
			trace.append(snappedf(_health().health, 0.001))
			trace.append(p.global_position.snappedf(0.0001))
	return trace


func test_enemies_are_deterministic() -> void:
	var a := await _run_scripted_fight()
	w.queue_free()
	await tree.process_frame
	w = TestWorld.new()
	tree.root.add_child(w)
	var b := await _run_scripted_fight()
	check(a.size() == b.size() and a == b, "the same input plays out the same fight")


# ------------------------------------------------------------------ sandbox arena

func test_sandbox_has_an_enemy_arena_by_zone_one() -> void:
	var level: Node3D = SANDBOX.instantiate()
	tree.root.add_child(level)
	var player: Player = level.get_node("Player")
	player.use_device_input = false
	player.scripted_input = InputFrame.new()
	await tree.physics_frame
	var arena := level.get_node_or_null("EnemyArena") as SandboxArena
	check(arena != null, "the sandbox has an arena")
	if arena:
		var raiders := arena.enemies.filter(func(en: Enemy) -> bool: return en is Raider).size()
		var mutants := arena.enemies.filter(func(en: Enemy) -> bool: return en is Mutant).size()
		check(raiders == 3 and mutants == 2, "3 raiders and 2 mutants (got %d, %d)" % [raiders, mutants])
		var b: SandboxBuilder = level.get_node("Builder")
		for i in b.spawns.size():
			check(not arena.bounds.has_point(b.spawns[i].origin), "zone %d spawn is outside the fight" % (i + 1))
		check(arena.covers.size() >= 14, "cover spots along the low walls (%d)" % arena.covers.size())
		# Walk in from zone 1 and the fight starts.
		level.go_to_zone(0)
		player.global_position = arena.entry.origin + Vector3(0, 0, 10)
		for i in 3:
			await tree.physics_frame
		check(arena.phase == EnemyEncounter.Phase.ACTIVE, "the fight starts when you walk in")
	level.queue_free()
	await tree.process_frame


# ------------------------------------------------------------------ running into enemies

func test_running_into_a_raider_slowly_is_blocked() -> void:
	await _setup()
	w.player.tuning.body_check_speed = 30.0  # never fast enough here
	var r := _raider(Vector3(0, 0, -3), false)
	await w.step(90, TestWorld.forward_input())
	check(not r.is_knocked_down(), "too slow to knock it over")
	check(w.player.global_position.z > r.global_position.z + 0.4, "can't walk through it (player z %.2f, raider z %.2f)" % [w.player.global_position.z, r.global_position.z])


func test_running_into_a_raider_knocks_it_over() -> void:
	await _setup()
	var r := _raider(Vector3(0, 0, -16), false)
	var before := [0.0]
	var walled := [false]
	var hit := await w.step_until(func() -> bool:
		walled[0] = walled[0] or w.player.state == Player.State.WALLRUN
		if not r.is_knocked_down():
			before[0] = w.player.horizontal_speed()
		return r.is_knocked_down(), 180, TestWorld.forward_input())
	check(hit, "a sprint into it knocks it over")
	check(before[0] >= w.player.tuning.body_check_speed, "hit at speed (%.1f m/s)" % before[0])
	var after := w.player.horizontal_speed()
	check(after < before[0] - 0.5 and after > before[0] * 0.4, "slowed, not stopped (%.1f -> %.1f m/s)" % [before[0], after])
	check_near(r.health, r.max_health, 0.01, "no damage, just knocked down")
	await w.step(30, TestWorld.forward_input())
	check(w.player.global_position.z < -17.0, "ran on through (z %.2f)" % w.player.global_position.z)
	check(not walled[0], "no wallrun off a body")
	await w.step(int(60 * r.knockdown_time) + 30)
	check(not r.is_knocked_down() and r.collision_layer != 0, "back up and solid again")


func test_running_into_a_heavy_staggers_it_and_you_shoulder_past() -> void:
	await _setup()
	var h: Node = load("res://enemies/heavy.gd").new()
	h.position = Vector3(0, 0, -16)
	w.add_child(h)
	var before := [0.0]
	var hit := await w.step_until(func() -> bool:
		if not h.is_staggered():
			before[0] = w.player.horizontal_speed()
		return h.is_staggered(), 180, TestWorld.forward_input())
	check(hit, "a sprint into it staggers it")
	check(not h.is_knocked_down(), "too heavy to knock over")
	var after := w.player.horizontal_speed()
	check(after < before[0] * w.player.tuning.body_check_keep and after > 0.5, "slowed more than a raider, not stopped (%.1f -> %.1f m/s)" % [before[0], after])
	await w.step(60, TestWorld.forward_input())
	check(w.player.global_position.z < h.global_position.z - 1.0, "shouldered past it (player z %.2f, heavy z %.2f)" % [w.player.global_position.z, h.global_position.z])
	check(h.collision_layer != 0, "solid again once you're by")
