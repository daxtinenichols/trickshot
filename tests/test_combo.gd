extends TestCase
## Skate-style combo scoring: multiplier from variety, repeat decay, speed
## bonus, banking, bailing, shot style and combo damage.

var w: TestWorld
var c: ComboTracker


func before_each() -> void:
	w = TestWorld.new()
	tree.root.add_child(w)
	c = ComboTracker.new()
	w.add_child(c)


func after_each() -> void:
	w.queue_free()
	await tree.process_frame


func _setup(pos := Vector3(0, 0.05, 0)) -> Player:
	w.add_floor()
	var p := w.spawn_player(pos)
	c.setup(p, p.weapon as Pistol)
	await w.step(20)
	return p


# ------------------------------------------------------------------ rules (no movement)

func test_variety_sets_multiplier_and_repeats_decay() -> void:
	await _setup()
	c.on_trick(&"slide", {"speed": 0.0})
	c.on_trick(&"vault", {"speed": 0.0})
	c.on_trick(&"slide", {"speed": 0.0})
	check(c.multiplier() == 2, "two different tricks = x2 (got x%d)" % c.multiplier())
	# slide 50 + vault 75 + slide 50*0.6 = 155
	check_near(c.combo_points, 155.0, 0.01, "repeat worth 60% of the last")
	check(c.combo_total() == 310, "total = points x multiplier (got %d)" % c.combo_total())


func test_speed_and_quality_scale_points() -> void:
	var p := await _setup()
	c.on_trick(&"vault", {"speed": p.tuning.top_speed})
	check_near(c.combo_points, 150.0, 0.01, "top speed doubles points")
	c.bail(&"test")
	c.on_trick(&"vault", {"speed": 0.0, "quality": 1.0})
	check_near(c.combo_points, 93.75, 0.01, "perfect quality is 1.25x")
	c.bail(&"test")
	c.on_trick(&"vault", {"speed": 0.0, "quality": 0.0})
	check_near(c.combo_points, 56.25, 0.01, "sloppy quality is 0.75x")


func test_bank_adds_to_score_and_bail_loses() -> void:
	await _setup()
	c.on_trick(&"slide", {})
	c.on_trick(&"backflip", {})
	c.bank()
	check(c.score == 700, "banked (50 + 300) x 2 = 700 (got %d)" % c.score)
	check(not c.is_active(), "combo cleared after banking")
	c.on_trick(&"slide", {})
	c.on_trick(&"crash", {})
	check(c.score == 700 and not c.is_active(), "crash bails: combo lost, score kept")
	check(c.best_combo == 700, "best combo recorded")


func test_feedback_events_score_nothing() -> void:
	await _setup()
	c.on_trick(&"quick_turn", {})
	c.on_trick(&"kick_miss", {})
	check(not c.is_active(), "quick turn and kick miss don't start a combo")


func test_combo_damage_scales_and_caps() -> void:
	var p := await _setup()
	check_near(c.damage_multiplier(), 1.0, 0.001, "no combo, standing: 1x")
	for t in [&"slide", &"vault", &"mantle", &"wallrun", &"wall_jump"]:
		c.on_trick(t, {})
	check_near(c.damage_multiplier(), 2.0, 0.001, "5 different tricks: 1 + 5 x 0.2 = 2x")
	p.velocity = Vector3(0, 0, -p.tuning.top_speed)
	check_near(c.damage_multiplier(), 3.0, 0.001, "at top speed it would be 4x, capped at 3x")


# ------------------------------------------------------------------ in play

func test_coming_to_rest_banks() -> void:
	var p := await _setup()
	await w.step_until(func() -> bool: return p.horizontal_speed() > 7.0, 600, TestWorld.forward_input())
	await w.press(InputFrame.make(Vector2(0, 1), false, true), 5)
	check(c.is_active(), "slide started a combo")
	var banked := await w.step_until(func() -> bool: return not c.is_active(), 240)
	check(banked and c.score > 0, "stopping banks the combo (score %d)" % c.score)


func test_two_seconds_without_a_trick_banks() -> void:
	var p := await _setup()
	await w.step_until(func() -> bool: return p.horizontal_speed() > 6.5, 600, TestWorld.forward_input())
	c.on_trick(&"vault", {"speed": p.horizontal_speed()})
	await w.step(int(c.bank_after * 60.0) - 10, TestWorld.forward_input())
	check(c.is_active(), "still going just before the 2 s window")
	await w.step(15, TestWorld.forward_input())
	check(not c.is_active() and c.score > 0, "banks after 2 s with no new trick")


func test_hard_landing_bails() -> void:
	w.add_floor()
	var p := w.spawn_player(Vector3(0, 9.0, 0))
	c.setup(p, p.weapon as Pistol)
	await w.step(1)
	c.on_trick(&"backflip", {})
	await w.step_until(func() -> bool: return p.state != Player.State.AIR, 180)
	check(p.state == Player.State.STUN, "hard landing stuns")
	check(not c.is_active() and c.score == 0, "and loses the combo")


func test_respawn_bails() -> void:
	var p := await _setup()
	c.on_trick(&"slide", {})
	p.respawn()
	check(not c.is_active() and c.score == 0, "falling out / respawning loses the combo")


func test_wallrun_scores_per_second() -> void:
	w.add_floor()
	w.add_box(Vector3(2.0, 3.0, -30.0), Vector3(1.0, 6.0, 60.0))
	var p := w.spawn_player(Vector3(-1.8, 0.05, 0), -0.3)
	c.setup(p, p.weapon as Pistol)
	await w.step(20)
	await w.step_until(func() -> bool: return p.global_position.x > 0.3, 300, TestWorld.forward_input())
	await w.press(InputFrame.make(Vector2(0, 1), true))
	var ok := await w.step_until(func() -> bool: return p.state == Player.State.WALLRUN, 90, TestWorld.forward_input())
	check(ok, "wallrun starts")
	var entry := c.entries[c._find(&"wallrun")] if c._find(&"wallrun") >= 0 else {}
	var start: float = entry.get("points", 0.0)
	await w.step(30, TestWorld.forward_input())
	var now: float = c.entries[c._find(&"wallrun")].points if c._find(&"wallrun") >= 0 else 0.0
	check(now - start > 45.0, "half a second on the wall adds ~50+ points (got %.1f)" % (now - start))
	check(c.is_active(), "combo held while on the wall")


func test_air_headshot_scores_style_and_hits_harder() -> void:
	var p := await _setup()
	var t := ShootingTarget.new()
	t.position = Vector3(0, 0, -12)
	w.add_child(t)
	var gun := p.weapon as Pistol
	var hits: Array[Dictionary] = []
	gun.hit.connect(func(i: Dictionary) -> void: hits.append(i))
	await w.step(2)
	# Build a combo, then jump and shoot the head once well off the ground.
	c.on_trick(&"slide", {})
	c.on_trick(&"vault", {})
	await w.press(InputFrame.make(Vector2.ZERO, true))
	await w.step_until(func() -> bool: return p.time_off_ground() >= 0.45, 60)
	var head := t.global_position + Vector3(0, ShootingTarget.HEAD_HEIGHT, 0)
	var eye := p.camera.global_position
	var d := head - eye
	p.yaw = atan2(-d.x, -d.z)
	p.pitch = atan2(d.y, Vector2(d.x, d.z).length())
	p.rotation = Vector3(0, p.yaw, 0)
	p.head.rotation = Vector3(p.pitch, 0, 0)
	gun.trigger_pressed = true
	await w.step(1)
	check(hits.size() == 1 and hits[0].zone == &"head", "headshot landed")
	if hits.is_empty():
		return
	check_near(hits[0].damage, 70.0 * 1.4, 0.5, "two-trick combo: headshot does 1.4x (got %.1f)" % hits[0].damage)
	check(c._find(&"headshot") >= 0, "headshot scored")
	check(c._find(&"air_shot") >= 0, "air shot scored")
	check(c.multiplier() == 4, "slide, vault, headshot, air shot = x4 (got x%d)" % c.multiplier())


# ------------------------------------------------------------------ kill finish and HUD

func _kill_hit() -> Dictionary:
	return {"target": w, "zone": &"head", "killed": true, "tags": [], "distance": 10.0}


func test_kill_finishes_and_banks_the_combo() -> void:
	await _setup()
	var summaries: Array[Dictionary] = []
	c.finished.connect(func(s: Dictionary) -> void: summaries.append(s))
	c.on_trick(&"slide", {})
	c.on_trick(&"vault", {})
	c.on_hit(_kill_hit())
	check(not c.is_active(), "the kill ended the combo")
	# slide 50 + vault 75 + headshot 150 + combo kill 500 = 775, x4
	check(c.score == 3100, "banked straight away (got %d)" % c.score)
	check(summaries.size() == 1 and summaries[0].reason == &"kill", "finished by a kill")
	if summaries.size() == 1:
		check(summaries[0].entries.back().name == &"combo_kill", "the chain ends on the kill")


func test_hud_shows_tricks_then_the_kill_card_then_points() -> void:
	await _setup()
	var hud := ComboHud.new()
	w.add_child(hud)
	hud.setup(c)
	c.on_trick(&"wallrun", {})
	c.on_trick(&"backflip", {})
	check(hud._pops.get_child_count() == 2, "each trick pops up")
	check((hud._pops.get_child(1) as Label).text == "+300  BACKFLIP", "pop shows points and name (%s)" % (hud._pops.get_child(1) as Label).text)
	c.on_hit(_kill_hit())
	check(hud._card.visible, "combo card shows")
	check(hud._card_title.text == "COMBO KILL", "kill finish is called out (%s)" % hud._card_title.text)
	check(hud._card_chain.text.ends_with("COMBO KILL"), "chain ends with the kill (%s)" % hud._card_chain.text)
	hud._process(0.1)
	check(not hud._card_total.visible, "total waits a beat")
	check(roundi(hud._shown_score) == 0, "score hasn't moved yet")
	for i in 60:
		hud._process(1.0 / 60.0)
	check(hud._card_total.visible, "then the points are awarded")
	check(roundi(hud._shown_score) == c.score, "score counted up to %d (shows %d)" % [c.score, roundi(hud._shown_score)])
