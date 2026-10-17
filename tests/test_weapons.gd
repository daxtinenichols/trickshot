extends TestCase
## Test pistol + shooting targets: damage, headshots, falloff, fire modes,
## reload, accuracy while moving, recoil, and style tags on shots.
## Coordinates: the player faces -Z at yaw 0.

var w: TestWorld
var hits: Array[Dictionary] = []


func before_each() -> void:
	w = TestWorld.new()
	tree.root.add_child(w)
	hits.clear()


func after_each() -> void:
	SlowMo.set_speed(1.0)
	w.queue_free()
	await tree.process_frame


func _setup(pos := Vector3(0, 0.05, 0)) -> Player:
	w.add_floor()
	var p := w.spawn_player(pos)
	var gun := _gun()
	gun.hit.connect(func(info: Dictionary) -> void: hits.append(info))
	await w.step(20)
	return p


func _gun() -> Pistol:
	return w.player.weapon as Pistol


func _target(pos: Vector3, motion := ShootingTarget.Motion.STATIC, amplitude := 3.0, speed := 4.0) -> ShootingTarget:
	var t := ShootingTarget.new()
	t.motion = motion
	t.amplitude = amplitude
	t.move_speed = speed
	t.position = pos
	w.add_child(t)
	return t


func _head(t: ShootingTarget) -> Vector3:
	return t.global_position + Vector3(0, ShootingTarget.HEAD_HEIGHT, 0)


func _chest(t: ShootingTarget) -> Vector3:
	return t.global_position + Vector3(0, 1.0, 0)


## Turn the view to look at a point (yaw and pitch), and let the camera follow.
func _aim(point: Vector3) -> void:
	var p := w.player
	var eye := p.global_position + Vector3(0, p.head.position.y, 0)
	var d := point - eye
	p.yaw = atan2(-d.x, -d.z)
	p.pitch = atan2(d.y, Vector2(d.x, d.z).length())
	p.rotation = Vector3(0, p.yaw, 0)
	p.head.rotation = Vector3(p.pitch + p.view_kick().x, 0, 0)


## Aim at a point and pull the trigger once (one physics tick).
func _shoot(point: Vector3, f: InputFrame = null) -> void:
	_aim(point)
	_gun().trigger_pressed = true
	_gun().trigger_held = true
	await w.step(1, f)
	_gun().trigger_held = false


## Wait long enough for bloom and recoil to settle.
func _settle_gun() -> void:
	await w.step(40)


# ------------------------------------------------------------------ damage

func test_body_and_head_damage() -> void:
	await _setup()
	var t := _target(Vector3(0, 0, -10))
	await w.step(2)
	await _shoot(_chest(t))
	check(hits.size() == 1, "body shot hits")
	if hits.size() > 0:
		check(hits[0].zone == &"body", "chest is a body hit (got %s)" % hits[0].zone)
		check_near(hits[0].damage, 28.0, 0.01, "body damage at 10 m")
	await _settle_gun()
	await _shoot(_head(t))
	check(hits.size() == 2, "head shot hits")
	if hits.size() > 1:
		check(hits[1].zone == &"head", "head is a head hit (got %s)" % hits[1].zone)
		check_near(hits[1].damage, 70.0, 0.01, "headshot is 2.5x")


func test_damage_falls_off_with_range() -> void:
	await _setup()
	var t := _target(Vector3(0, 0, -50))
	await w.step(2)
	await _shoot(_chest(t))
	check(hits.size() == 1, "50 m body shot hits")
	if hits.size() > 0:
		# 30-70 m falls from 100% to 60%: ~50 m is ~80%.
		check_between(hits[0].damage, 21.0, 23.5, "damage at 50 m")


func test_two_headshots_kill_and_target_comes_back() -> void:
	await _setup()
	var t := _target(Vector3(0, 0, -12))
	var deaths := [0]
	t.killed.connect(func(_i: Dictionary) -> void: deaths[0] += 1)
	await w.step(2)
	await _shoot(_head(t))
	check(not t.is_dead, "one headshot doesn't kill")
	await _settle_gun()
	await _shoot(_head(t))
	check(t.is_dead and deaths[0] == 1, "second headshot kills")
	check(hits.size() == 2 and hits[1].killed, "hit info reports the kill")
	await _settle_gun()
	var before := hits.size()
	await _shoot(_head(t))
	check(hits.size() == before or hits[-1].target == null, "dead target can't be hit")
	await w.step_until(func() -> bool: return not t.is_dead, 200)
	check(not t.is_dead and is_equal_approx(t.health, t.max_health), "target respawns at full health")
	await w.step(5)
	await _shoot(_head(t))
	check(hits.size() > 0 and hits[-1].target == t, "respawned target can be hit again")


func test_body_shots_need_more_hits() -> void:
	await _setup()
	var t := _target(Vector3(0, 0, -10))
	await w.step(2)
	for i in 3:
		await _shoot(_chest(t))
		await _settle_gun()
	check(not t.is_dead, "three body shots don't kill")
	await _shoot(_chest(t))
	check(t.is_dead, "four body shots kill")


func test_health_refills_if_you_stop_shooting() -> void:
	await _setup()
	var t := _target(Vector3(0, 0, -10))
	await w.step(2)
	await _shoot(_head(t))
	check(t.health < t.max_health, "damaged")
	await w.step(int(60 * (t.regen_delay + 0.2)))
	check(is_equal_approx(t.health, t.max_health), "health refills after a pause")


# ------------------------------------------------------------------ fire modes

func test_semi_auto_fires_once_per_press() -> void:
	await _setup()
	var gun := _gun()
	gun.trigger_held = true
	gun.trigger_pressed = true
	await w.step(1)
	gun.trigger_held = true
	await w.step(30)
	check(gun.shots_fired == 1, "holding in semi fires once (got %d)" % gun.shots_fired)


func test_semi_auto_rate_is_capped() -> void:
	await _setup()
	var gun := _gun()
	for i in 60:
		gun.trigger_pressed = true
		await w.step(1)
	check_between(gun.shots_fired, 6, 8, "mashing for 1 s in semi")


func test_full_auto_rate() -> void:
	await _setup()
	var gun := _gun()
	gun.mode_pressed = true
	await w.step(1)
	check(gun.full_auto, "mode toggles to full auto")
	gun.trigger_held = true
	await w.step(60)
	gun.trigger_held = false
	check_between(gun.shots_fired, 10, 12, "holding for 1 s in auto")


func test_magazine_and_reload() -> void:
	await _setup()
	var gun := _gun()
	gun.full_auto = true
	gun.trigger_held = true
	await w.step(180)
	gun.trigger_held = false
	check(gun.shots_fired == 15, "a magazine is 15 rounds (fired %d)" % gun.shots_fired)
	check(gun.ammo == 0 or gun.is_reloading(), "empty")
	gun.trigger_pressed = true
	await w.step(1)
	check(gun.is_reloading(), "pulling the trigger on empty reloads")
	await w.step(int(60 * gun.stats.reload_time) + 2)
	check(gun.ammo == 15 and not gun.is_reloading(), "full after reload")
	# Manual reload.
	gun.full_auto = false
	gun.trigger_pressed = true
	await w.step(1)
	gun.reload_pressed = true
	await w.step(1)
	check(gun.is_reloading(), "R reloads a partial magazine")


# ------------------------------------------------------------------ accuracy and feel

func test_first_shot_is_exact_at_full_sprint() -> void:
	var p := await _setup(Vector3(0, 0.05, 30))
	var t := _target(Vector3(0, 0, -80))
	await w.step_until(func() -> bool: return p.horizontal_speed() >= p.tuning.top_speed * 0.9, 900, TestWorld.forward_input())
	check(p.horizontal_speed() >= p.tuning.top_speed * 0.9, "at top speed")
	await _shoot(_head(t), TestWorld.forward_input())
	check(hits.size() == 1 and hits[0].zone == &"head", "first shot at full sprint lands on the head")
	if hits.size() > 0:
		check(&"fast" in hits[0].tags, "fast shot is tagged")


func test_spam_blooms_and_recovers() -> void:
	await _setup()
	var gun := _gun()
	var s0 := gun.current_spread()
	gun.full_auto = true
	gun.trigger_held = true
	await w.step(30)
	gun.trigger_held = false
	check(gun.current_spread() > s0 + 1.0, "holding the trigger blooms the spread")
	await w.step(40)
	check_near(gun.current_spread(), s0, 0.01, "spread recovers once you stop")


func test_recoil_kicks_view_without_moving_aim() -> void:
	var p := await _setup()
	_aim(Vector3(0, 1.66, -20))
	var pitch0 := p.pitch
	await _shoot(Vector3(0, 1.66, -20))
	await tree.process_frame
	check(p.view_kick().x > deg_to_rad(0.5), "shot kicks the view up")
	check_near(p.pitch, pitch0, 0.0001, "kick doesn't change the real pitch (flips stay clean)")
	await w.step(30)
	check(p.view_kick().x < deg_to_rad(0.05), "view settles back")


func test_aim_down_sights_zooms() -> void:
	var p := await _setup()
	var gun := _gun()
	gun.aim_held = true
	await w.step(20)
	check_near(p.aim_zoom, 1.0, 0.001, "fully aimed")
	check(p.camera.fov < 70.0, "camera zooms in (fov %.1f)" % p.camera.fov)
	check(p.aim_sensitivity_scale() < 0.8, "look slows down while zoomed")
	gun.aim_held = false
	await w.step(20)
	check(p.aim_zoom == 0.0 and p.camera.fov > 80.0, "zoom returns")


# ------------------------------------------------------------------ moving targets and style

func test_moving_target_hitboxes_follow_it() -> void:
	await _setup()
	var t := _target(Vector3(0, 0, -15), ShootingTarget.Motion.STRAFE, 3.0, 4.0)
	await w.step(25)
	check(absf(t.global_position.x) > 1.0, "target moved (x %.2f)" % t.global_position.x)
	await _shoot(_head(t))
	check(hits.size() == 1 and hits[0].target == t and hits[0].zone == &"head", "headshot on a moving target")


func test_airborne_flip_shot_is_tagged() -> void:
	var p := await _setup()
	var t := _target(Vector3(0, 0, -12))
	await w.press(InputFrame.make(Vector2.ZERO, true))
	await w.step_until(func() -> bool: return p.state == Player.State.AIR, 30)
	# Pull the view most of the way over (backflip), then aim at the target
	# upside down by continuing the flip.
	for i in 10:
		p._look(0.0, deg_to_rad(15.0))
		await w.step(1)
	var tags := p.shot_tags()
	check(&"airborne" in tags, "in the air (%s)" % [tags])
	check(&"flipping" in tags, "mid-flip (%s)" % [tags])
	check(&"upside_down" in tags, "upside down at 150 deg (%s)" % [tags])
	check(t != null, "target present")


func test_shooting_a_window_breaks_it() -> void:
	await _setup()
	var win := BreakableWindow.new()
	w.add_child(win)
	win.global_position = Vector3(0, 1.0, -8)
	await w.step(2)
	await _shoot(Vector3(0, 1.6, -8))
	check(win.is_broken, "shot window shatters")


func test_hip_fire_shot_through_crosshair_at_range() -> void:
	# First-shot accuracy: a 60 m headshot from the hip with no aiming.
	await _setup()
	var t := _target(Vector3(0, 0, -60))
	await w.step(2)
	await _shoot(_head(t))
	check(hits.size() == 1 and hits[0].zone == &"head", "60 m hip-fire headshot lands")


func test_recoil_punches_up_then_settles() -> void:
	var p := await _setup()
	_aim(Vector3(0, 1.66, -20))
	await _shoot(Vector3(0, 1.66, -20))
	var kicks: Array[float] = []
	for i in 6:
		await tree.process_frame
		kicks.append(p.view_kick().x)
	check(kicks[0] > 0.0 and kicks[2] > kicks[0], "the kick builds over a few frames, not one jump (%s)" % str(kicks))
	check(kicks.max() < deg_to_rad(_gun().stats.recoil_pitch) * 1.2, "peaks near the recoil amount")
	check(p.camera.fov > p._fov_base + 0.2, "the view widens for a moment")


## Hits are felt through the gun, view and marker; time never stalls,
## so shooting mid-run never breaks your flow.
func test_headshots_and_kills_never_slow_time() -> void:
	await _setup()
	var t := _target(Vector3(0, 0, -15))
	var killed := false
	for i in 6:
		await _shoot(_head(t))
		check(Engine.time_scale == 1.0 and Engine.physics_ticks_per_second == 60, "time keeps running on hit %d" % i)
		killed = hits.any(func(h: Dictionary) -> bool: return h.killed)
		if killed:
			break
		await _settle_gun()
	check(hits.size() > 0 and hits[0].zone == &"head", "headshots landed")
	check(killed, "and a kill")


# ------------------------------------------------------------------ aim help

## Shoots once at `point` with aim help at `strength`; returns the hit zone
## (&"" on a miss).
func _assisted_shot(point: Vector3, strength: float) -> StringName:
	for t in tree.get_nodes_in_group("targets"):
		t.health = t.max_health  # keep it alive through the series
	_gun().aim_assist = strength
	var before := hits.size()
	await _shoot(point)
	await _settle_gun()
	return hits[before].zone if hits.size() > before else &""


func test_aim_help_bends_near_misses_onto_the_head() -> void:
	await _setup()
	var t := _target(Vector3(0, 0, -15))
	await w.step(2)
	var beside := _head(t) + Vector3(0.35, 0, 0)  # just past the head
	check(await _assisted_shot(beside, 0.0) == &"", "off: a near miss misses")
	check(await _assisted_shot(beside, 1.0) == &"head", "on: it bends onto the head")
	var wide := _head(t) + Vector3(1.5, 0, 0)
	check(await _assisted_shot(wide, 1.0) == &"", "a wide miss still misses")
	var neck := t.global_position + Vector3(0, 1.35, 0)  # top of the body
	check(await _assisted_shot(neck, 0.0) == &"body", "off: the top of the body is a body hit")
	check(await _assisted_shot(neck, 1.0) == &"head", "on: a hit just under the head moves up to it")
	check(await _assisted_shot(_chest(t), 1.0) == &"body", "a chest shot stays a body shot")


func test_aim_help_never_goes_through_walls() -> void:
	await _setup()
	var t := _target(Vector3(0, 0, -15))
	# A wall covering the target's head from the side the shot passes.
	w.add_box(Vector3(0, 1.62, -12), Vector3(0.6, 0.6, 0.2))
	await w.step(2)
	check(await _assisted_shot(_head(t) + Vector3(0.6, 0, 0), 1.0) != &"head", "no bending onto a head behind cover")


func test_aim_help_slows_controller_look_over_targets() -> void:
	await _setup()
	var t := _target(Vector3(0, 0, -15))
	await w.step(2)
	_aim(_head(t))
	await w.step(1)
	_aim(_head(t))
	_gun().aim_assist = 1.0
	check(_gun().look_slowdown() < 0.6, "slower over a target (%.2f)" % _gun().look_slowdown())
	_gun().aim_assist = 0.0
	check(_gun().look_slowdown() == 1.0, "off: full speed")
	_gun().aim_assist = 1.0
	_aim(_head(t) + Vector3(5, 0, 0))
	check(_gun().look_slowdown() == 1.0, "full speed away from targets")


func test_aim_help_setting_reaches_the_gun() -> void:
	await _setup()
	Settings.aim_assist = 0.2
	Settings.apply_to(w.player)
	check_near(_gun().aim_assist, 0.2, 0.001, "setting applied")
	Settings.reset_values()
	Settings.apply_to(w.player)
	check_near(_gun().aim_assist, 0.5, 0.001, "default is light help")


func test_hit_marker_pops_on_hits() -> void:
	var m := HitMarker.new()
	w.add_child(m)
	m.show_hit(true, false)
	check(m.pop_scale() > 1.5 and m.is_showing(), "pops in big on a headshot")
	for i in 10:
		await tree.process_frame
	check(m.pop_scale() < 1.1, "and snaps down")


func test_gun_hooks_for_art() -> void:
	await _setup()
	var gun := _gun()
	var shots := []
	gun.shot.connect(func(muzzle: Vector3, end: Vector3, result: Dictionary) -> void: shots.append([muzzle, end, result]))
	var t := _target(Vector3(0, 0, -15))
	await _shoot(_chest(t))
	check(shots.size() == 1, "shot signal on every shot")
	if shots.size() == 1:
		check(shots[0][0].distance_to(gun.muzzle_transform().origin) < 0.2, "from the muzzle")
		check(not (shots[0][2] as Dictionary).is_empty() and shots[0][1].distance_to(_chest(t)) < 0.5, "to the hit, with its result")
	check(gun.reload_progress() == -1.0, "not reloading")
	gun.reload_pressed = true
	await w.step(1)
	gun.reload_pressed = false
	await w.step(30)
	check_between(gun.reload_progress(), 0.2, 0.8, "partway through a reload")
	gun.builtin_visuals = false
	var shown := 0
	for m in gun.view_model.find_children("*", "MeshInstance3D", true, false):
		if (m as MeshInstance3D).is_visible_in_tree():
			shown += 1
	check(shown == 0, "the test pistol's boxes hide for a real model")
	check(gun.view_model.visible, "the view model node stays for the real gun")
