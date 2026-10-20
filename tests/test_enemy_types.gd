extends TestCase
## The enemy roster beyond the first raiders and mutants: models for every
## type, the Ward (troopers, shields, marksmen, heavies), drones (gun,
## camera, spotter), the newer Hollows (brute, leaper) and Static (hunter,
## bruiser, Juno), plus the encounter hooks missions use (types by name,
## sleepers woken by gunshots). Coordinates: the player faces -Z at yaw 0.

const Encounter := preload("res://enemies/enemy_encounter.gd")
const SANDBOX := preload("res://levels/sandbox.tscn")
const TYPES := ["raider", "mutant", "crawler", "trooper", "shield", "marksman", "heavy", "drone",
	"gun_drone", "camera_drone", "spotter_drone", "brute", "leaper", "hunter", "bruiser", "juno"]
const FLYERS := ["drone", "gun_drone", "camera_drone", "spotter_drone"]

var w: TestWorld
var hits: Array[Dictionary] = []


func before_each() -> void:
	w = TestWorld.new()
	tree.root.add_child(w)
	hits.clear()


func after_each() -> void:
	Enemy.use_models = true
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


func _make(type: String, pos: Vector3, active := true, face_player := false) -> Enemy:
	var e: Enemy = Encounter.script_for(type).new()
	e.position = pos
	if face_player:
		e.rotation.y = PI
	w.add_child(e)
	if active:
		e.activate(w.player)
	return e


func _encounter(size := Vector3(80, 30, 80), center := Vector3.ZERO) -> EnemyEncounter:
	var e := EnemyEncounter.new()
	w.add_child(e)
	e.bounds = AABB(center - size * 0.5, size)
	e.entry = Transform3D(Basis.IDENTITY, center + Vector3(0, 0.1, size.z * 0.5 + 5.0))
	e.setup(w.player)
	return e


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
	await w.step(30)


func _bullets() -> int:
	var n := 0
	for c in w.get_children():
		if c is EnemyProjectile and not (c as EnemyProjectile).done:
			n += 1
	return n


func _frames(n: int) -> void:
	for i in n:
		await tree.process_frame


# ------------------------------------------------------------------ models

func test_every_type_has_a_model_that_matches_its_hit_zones() -> void:
	await _setup()
	for t: String in TYPES:
		var e := _make(t, Vector3(0, 0, -10), false)
		await w.step(3)
		await _frames(3)
		check(e.body != null, "%s loads its model" % t)
		if e.body == null:
			continue
		if t in FLYERS:
			check(e.body.parts.has("Rotor0"), "%s has rotors" % t)
		else:
			check(e.body.has_bones(), "%s is skinned" % t)
			# The model's head is where the head hit zone is.
			var head: Vector3 = e.body.bone_position("Head")
			var zone := e.head_position()
			check(head.distance_to(zone) < 0.2 * (e.get("size_scale") if "size_scale" in e else 1.0) + 0.05,
				"%s: model head %.2f m from the head zone" % [t, head.distance_to(zone)])
		e.queue_free()
		await w.step(1)


func test_raider_model_kneels_behind_cover() -> void:
	await _setup()
	var r := _make("raider", Vector3(0, 0, -10), false) as Raider
	r.duck = 1.0
	for i in 40:
		r.duck = 1.0
		await tree.process_frame
	var head: Vector3 = r.body.bone_position("Head")
	check(head.y < 1.25, "the ducked model's head is low behind a 1.2 m wall (%.2f m)" % head.y)
	check(r.body.ground_offset < -0.2, "kneeling lowers the model to the ground (%.2f)" % r.body.ground_offset)


func test_rifle_points_where_the_raider_aims() -> void:
	await _setup()
	var r := _make("raider", Vector3(0, 0, -10), false) as Raider
	r.state = Raider.State.AIM
	r.aim_dir = Vector3(0, 0.0, -1)
	for i in 60:
		r.state = Raider.State.AIM
		await tree.process_frame
	var rifle: Node3D = r.body.parts.get("Rifle")
	check(rifle != null, "the rifle is in the model")
	if rifle:
		# Modeled facing +Z, the rifle points along its basis -(-z) once turned.
		var fwd := rifle.global_basis.z
		check(fwd.dot(r.aim_dir) > 0.95, "the rifle points along the aim (%.2f)" % fwd.dot(r.aim_dir))
		var hand: Vector3 = r.body.bone_position("RightHand")
		check(hand.distance_to(rifle.global_position) < 0.2, "the right hand is on the grip (%.2f m)" % hand.distance_to(rifle.global_position))


func test_placeholder_when_models_are_off() -> void:
	await _setup()
	Enemy.use_models = false
	var e := _make("trooper", Vector3(0, 0, -10), false)
	await w.step(2)
	check(e.body == null, "no model")
	check(e.find_children("*", "MeshInstance3D", true, false).size() > 3, "placeholder boxes instead")


# ------------------------------------------------------------------ the Ward

func test_trooper_helmet_takes_one_headshot() -> void:
	await _setup()
	var t := _make("trooper", Vector3(0, 0, -12), false, true)
	t.one_shot_headshot = false
	await w.step(2)
	await _shoot(t.head_position())
	check(hits.size() == 1 and hits[0].zone == &"head", "first headshot hits the head")
	check(not t.is_dead and not t.helmet, "it knocks the helmet off without killing")
	await _shoot(t.head_position())
	check(t.is_dead, "the second headshot kills")


## Dax: every normal enemy dies to one headshot, through helmets, armor and
## falloff, even with a weak shot. Bosses don't.
func test_one_headshot_kills_every_normal_enemy() -> void:
	await _setup()
	var x := -12.0
	for type in TYPES:
		var e := _make(type, Vector3(x, 0, -30), false)
		x += 3.0
		await w.step(1)
		var killed := e.take_hit({"zone": &"head", "damage": 1.0, "direction": Vector3.FORWARD})
		if type == "juno":
			check(not killed and not e.is_dead, "juno is a boss: a headshot doesn't kill her")
		else:
			check(killed and e.is_dead, "%s dies to one headshot" % type)
	var b := _make("raider", Vector3(0, 0, -30), false)
	var plain := b.take_hit({"zone": &"body", "damage": 1.0, "direction": Vector3.FORWARD})
	check(not plain and not b.is_dead, "a body shot still does normal damage")


func test_trooper_armor_soaks_body_shots() -> void:
	await _setup()
	var t := _make("trooper", Vector3(0, 0, -12), false, true)
	var r := _make("raider", Vector3(3, 0, -12), false, true)
	await w.step(2)
	t.take_hit({"damage": 20.0, "zone": &"body"})
	r.take_hit({"damage": 20.0, "zone": &"body"})
	check(t.max_health - t.health < (r.max_health - r.health) * 0.7, "a trooper takes much less from a body shot")


func test_trooper_fires_a_telegraphed_burst() -> void:
	await _setup()
	var t := _make("trooper", Vector3(0, 0, -30), true, true)
	var aimed := false
	var most := 0
	for i in 360:
		await w.step(1)
		aimed = aimed or t.is_locked()
		most = maxi(most, _bullets())
		if t.shots_fired >= 1 and t.get("_burst_left") == 0 and _bullets() == 0 and most > 0:
			break
	check(aimed, "it locked on before firing")
	check(t.shots_fired >= 1, "it fired")
	check(most == 3, "one trigger pull is a three-round burst (%d in the air)" % most)


func test_shield_blocks_shots_from_the_front() -> void:
	await _setup()
	var s := _make("shield", Vector3(0, 0, -10), false, true)
	await w.step(2)
	await _shoot(s.global_position + Vector3(0, 1.1, 0))
	check(hits.size() == 1 and hits[0].target == null, "the chest shot hits the shield, not the bearer")
	check(s.health == s.max_health and s.shield_hits == 1, "no damage, a clank")
	await _shoot(s.head_position() + Vector3(0, 0.08, 0))
	check(hits.size() == 2 and hits[1].zone == &"head", "the helmet shows over the top: a headshot")


func test_kicking_the_shield_opens_the_bearer() -> void:
	await _setup()
	var s := _make("shield", Vector3(0, 0, -10), false, true)
	await w.step(2)
	s.plate.on_kicked(w.player, Vector3(0, 0, -1))
	check(s.is_staggered() and s.plate.collision_layer == 0, "the kick knocks the shield aside")
	await _shoot(s.global_position + Vector3(0, 1.1, 0))
	check(hits.size() == 1 and hits[0].target == s, "now a chest shot hits the bearer")
	await w.step(120)
	check(s.plate.collision_layer != 0, "the shield comes back up")


func test_heavy_shrugs_off_body_shots() -> void:
	await _setup()
	var h := _make("heavy", Vector3(0, 0, -12), false, true)
	await w.step(2)
	for i in 4:
		h.take_hit({"damage": 28.0, "zone": &"body"})
	check(h.health > h.max_health * 0.85, "four body shots barely dent it (%.0f/%.0f)" % [h.health, h.max_health])
	h.kick_shove = h.kick_shove
	h.on_kicked(w.player, Vector3(0, 0, -1))
	check(h.velocity.length() < 4.0, "a kick hardly moves it")


func test_marksman_aims_from_long_range() -> void:
	await _setup()
	var m := _make("marksman", Vector3(0, 0, -45), true, true)
	var ok := await w.step_until(func() -> bool: return m.is_aiming(), 300)
	check(ok, "it aims at you from 45 m")


# ------------------------------------------------------------------ drones

func test_drone_hovers_and_one_hit_drops_it() -> void:
	await _setup()
	var d := _make("gun_drone", Vector3(0, 0, -12), false)
	await w.step(240)
	check_near(d.global_position.y, d.hover_height, 0.6, "hovers at its height")
	await _shoot(d.global_position + Vector3(0, 0.45, 0))
	check(d.is_dead, "one body shot drops it")
	await w.step(150)
	check(d.global_position.y < 1.0, "it falls to the ground (%.1f m)" % d.global_position.y)


func test_drone_telegraphs_its_burst_and_moving_dodges_it() -> void:
	await _setup()
	var d := _make("gun_drone", Vector3(0, 0, -14), true)
	var locked_at := -1
	var fired_at := -1
	var f := InputFrame.make(Vector2(1, 0))
	for i in 600:
		_aim(d.global_position)
		await w.step(1, f)
		if locked_at < 0 and d.is_locked():
			locked_at = i
		if fired_at < 0 and d.shots_fired > 0:
			fired_at = i
		if d.bursts >= 2:
			break
	check(locked_at >= 0 and fired_at > locked_at, "locks before it fires")
	check(d.shots_fired >= d.shots_per_burst, "a burst of %d" % d.shots_per_burst)
	check(_health().health >= _health().max_health - 0.01, "running sideways dodged it (%.0f hp)" % _health().health)


func test_drone_stays_on_its_patch() -> void:
	await _setup(Vector3(0, 0.05, 40))
	var d := _make("drone", Vector3(0, 0, -12), true)
	var home := d.global_position
	await w.step(400)
	check(EnemyMath.horizontal(d.global_position - home).length() <= d.leash_radius + 1.0, "it never follows you off its patch")


func test_camera_drone_films_but_never_shoots() -> void:
	await _setup()
	var c := _make("camera_drone", Vector3(0, 0, -10), true)
	var cut := [false]
	c.feed_cut.connect(func() -> void: cut[0] = true)
	await w.step(400)
	check(_health().health == _health().max_health, "harmless")
	check(c.distance_to_player() < 12.0, "it stays close to film you (%.1f m)" % c.distance_to_player())
	c.take_hit({"damage": 100.0})
	check(cut[0], "shooting it down cuts the feed")


func test_spotter_marks_you_for_the_gunners() -> void:
	await _setup()
	var e := _encounter()
	var r := e.add_from_spec("raider", {}, Transform3D(Basis.IDENTITY, Vector3(-6, 0, -16))) as Raider
	var s := e.add_from_spec("spotter_drone", {}, Transform3D(Basis.IDENTITY, Vector3(6, 0, -18)))
	await w.step(2)
	e.start()
	var ok := await w.step_until(func() -> bool: return e.is_spotted(), 300)
	check(ok, "the spotter marks you")
	check(r.aim_time() < r.windup, "marked, raiders lock on faster")
	s.take_hit({"damage": 100.0})
	await w.step(30)
	check(not e.is_spotted() and is_equal_approx(r.aim_time(), r.windup), "shooting it down breaks the mark")


# ------------------------------------------------------------------ Hollows

func test_brute_is_armored_in_front_and_soft_behind() -> void:
	await _setup()
	var b := _make("brute", Vector3(0, 0, -10), false, true)
	await w.step(2)
	# It faces +Z (toward you): a shot travelling -Z hits its front.
	b.take_hit({"damage": 50.0, "zone": &"body", "direction": Vector3(0, 0, -1)})
	var front := b.max_health - b.health
	var before := b.health
	b.take_hit({"damage": 50.0, "zone": &"body", "direction": Vector3(0, 0, 1)})
	var back := before - b.health
	check(front < 15.0, "front shots barely hurt (%.0f)" % front)
	check(back > 60.0, "back shots hurt extra (%.0f)" % back)


func test_brute_charge_misses_a_sidestep_and_dazes_it_on_a_wall() -> void:
	await _setup()
	w.add_box(Vector3(0, 1.5, 3.5), Vector3(20, 3, 1))
	var b := _make("brute", Vector3(0, 0, -10), true, true)
	var ok := await w.step_until(func() -> bool: return b.state == Mutant.State.CHARGE_WINDUP, 400)
	check(ok, "it winds up a charge")
	await w.step_until(func() -> bool: return b.state_time > b.charge_windup - b.charge_lock + 0.05, 60)
	# Step aside once its line is locked.
	w.player.global_position = Vector3(4.5, 0.05, 0)
	ok = await w.step_until(func() -> bool: return b.is_dazed(), 200)
	check(ok, "it slams the wall and is dazed")
	check(_health().health == _health().max_health, "the sidestep dodged it")


func test_leaper_leaps_often() -> void:
	await _setup()
	var l := _make("leaper", Vector3(0, 0, -11), true, true)
	# You keep running around: it keeps cutting you off with leaps.
	for i in 420:
		var f := InputFrame.make(Vector2(1.0 if (i / 90) % 2 == 0 else -1.0, 0.0))
		await w.step(1, f)
	check(l.leaps >= 2, "leapt %d times in 7 s" % l.leaps)


func test_shots_draw_sleeping_hollows() -> void:
	await _setup()
	var e := _encounter()
	e.hear_shots = true
	var awake := e.add_from_spec("raider", {}, Transform3D(Basis.IDENTITY, Vector3(0, 0, -16)))
	var sleeper := e.add_from_spec("crawler", {"sleeper": true}, Transform3D(Basis.IDENTITY, Vector3(10, 0, -20)))
	var drew := [0]
	e.drew_enemies.connect(func(n: int) -> void: drew[0] += n)
	await w.step(2)
	e.start()
	await w.step(5)
	check(awake.active and not sleeper.active, "sleepers stay put when the fight starts")
	awake.take_hit({"damage": 1000.0})
	check(e.phase == EnemyEncounter.Phase.CLEARED, "a sleeper nobody woke doesn't hold up the clear")
	e.reset()
	e.start()
	await _shoot(Vector3(0, 1, -30))
	check(sleeper.active and drew[0] == 1, "a gunshot wakes it")


# ------------------------------------------------------------------ the Static

func test_hunter_flanks_to_your_side() -> void:
	await _setup()
	var e := _encounter()
	var h := e.add_from_spec("hunter", {}, Transform3D(Basis.IDENTITY, Vector3(0, 0, -14)))
	await w.step(2)
	e.start()
	var widest := 0.0
	for i in 300:
		_aim(Vector3(0, 1.4, -20))  # keep looking ahead
		await w.step(1)
		widest = maxf(widest, absf(h.global_position.x))
	check(widest > 6.0, "it runs out to your side (%.1f m)" % widest)


func test_bruiser_hides_behind_scrap() -> void:
	await _setup()
	var b := _make("bruiser", Vector3(0, 0, -10), false, true)
	await w.step(2)
	await _shoot(b.global_position + Vector3(0, 1.0, 0))
	check(hits.size() == 1 and hits[0].target == null and b.health == b.max_health, "the scrap shield stops a chest shot")


func test_juno_can_be_spared() -> void:
	await _setup()
	var e := _encounter()
	var j := e.add_from_spec("juno", {"spare_time": 2.0}, Transform3D(Basis.IDENTITY, Vector3(0, 0, -12)))
	var fates: Array[String] = []
	var beaten := [false]
	j.beaten.connect(func() -> void: beaten[0] = true)
	j.fate_decided.connect(func(f: String) -> void: fates.append(f))
	await w.step(2)
	e.start()
	j.take_hit({"damage": 10000.0})
	check(beaten[0] and j.is_beaten and not j.is_dead, "a finishing blow beats her instead of killing her")
	await w.step(150)
	check(fates == ["spared"], "left alone, she's spared (%s)" % [fates])
	check(e.phase == EnemyEncounter.Phase.CLEARED, "and the fight is over")


func test_juno_not_spared_if_you_shoot_her_down() -> void:
	await _setup()
	var j := _make("juno", Vector3(0, 0, -12), false, true)
	var fates: Array[String] = []
	j.fate_decided.connect(func(f: String) -> void: fates.append(f))
	await w.step(2)
	j.take_hit({"damage": 10000.0})
	await w.step(10)
	await _shoot(j.global_position + Vector3(0, 0.8, 0))
	check(fates == ["not_spared"] and j.is_dead, "shooting her while she's down decides it")


# ------------------------------------------------------------------ hooks

func test_types_by_name() -> void:
	for t: String in TYPES:
		check(Encounter.script_for(t) != null, "%s resolves" % t)
	check(Encounter.script_for("drones") == Encounter.script_for("drone"), "plural list names resolve")
	check(Encounter.script_for("enemy_body") == null and Encounter.script_for("nope") == null, "only real enemy types")


func test_add_from_spec_sets_settings() -> void:
	await _setup()
	var e := _encounter()
	var d := e.add_from_spec("gun_drone", {"hover_height": 6.5, "wake": 1.5, "leash_radius": 9.0}, Transform3D.IDENTITY)
	check(d != null and d.hover_height == 6.5 and d.leash_radius == 9.0 and d.wake_delay == 1.5, "spec keys set the drone's settings")
	check(e.add_from_spec("player_health", {}, Transform3D.IDENTITY) == null, "a script that isn't an enemy is refused")


func test_sandbox_arena_alternates_waves() -> void:
	var level: Node3D = SANDBOX.instantiate()
	tree.root.add_child(level)
	var player: Player = level.get_node("Player")
	player.use_device_input = false
	player.scripted_input = InputFrame.new()
	await tree.physics_frame
	var arena := level.get_node("EnemyArena") as SandboxArena
	check(arena.waves.size() == 2 and arena.wave == 0, "two waves, starting with the Host's crew")
	for en: Enemy in arena.waves[1]:
		check(not en.visible, "wave 2 is benched")
	arena.restart_time = 0.5
	level.go_to_zone(0)
	player.global_position = arena.entry.origin + Vector3(0, 0, 10)
	await tree.physics_frame
	await tree.physics_frame
	for en: Enemy in arena.enemies.duplicate():
		en.take_hit({"damage": 10000.0})
	check(arena.phase == EnemyEncounter.Phase.CLEARED, "wave 1 cleared")
	for i in 40:
		await tree.physics_frame
	check(arena.wave == 1, "wave 2 is up")
	var kinds := {}
	for en: Enemy in arena.enemies:
		kinds[en.get_script().resource_path.get_file()] = true
		check(en.visible, "wave 2 enemies are back")
	check(kinds.has("trooper.gd") and kinds.has("shield.gd") and kinds.has("drone.gd"), "troopers, a shield and drones (%s)" % [kinds.keys()])
	level.queue_free()
	await tree.process_frame


# ------------------------------------------------------------------ determinism

func _run_mixed_fight() -> Array:
	var p := await _setup(Vector3(0, 0.05, 6))
	var e := _encounter(Vector3(60, 30, 60))
	var wall := Vector3(0, 0, -8)
	w.add_box(wall + Vector3(0, 0.6, 0), Vector3(6, 1.2, 0.5))
	e.add_cover_wall(wall, 6, 0.5)
	for spec: Array in [["trooper", Vector3(-6, 0, -18)], ["shield", Vector3(4, 0, -16)], ["gun_drone", Vector3(0, 0, -20)],
			["brute", Vector3(8, 0, -24)], ["hunter", Vector3(-8, 0, -22)], ["spotter_drone", Vector3(-4, 0, -26)]]:
		e.add_from_spec(spec[0], {}, Transform3D(Basis.IDENTITY, spec[1]))
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


func test_new_enemies_are_deterministic() -> void:
	var a := await _run_mixed_fight()
	w.queue_free()
	await tree.process_frame
	w = TestWorld.new()
	tree.root.add_child(w)
	var b := await _run_mixed_fight()
	check(a.size() == b.size() and a == b, "the same input plays out the same fight")
