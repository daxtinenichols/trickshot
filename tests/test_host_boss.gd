extends TestCase
## The Host as a boss (enemies/host_boss.gd, for m09b Head Office): he
## shoots, runs when hit, can't die, and leaves his encounter clear without
## a kill. Coordinates: the player faces -Z at yaw 0.

const Encounter := preload("res://enemies/enemy_encounter.gd")

var w: TestWorld
var events: Array[String] = []


func before_each() -> void:
	w = TestWorld.new()
	tree.root.add_child(w)
	events.clear()


func after_each() -> void:
	w.queue_free()
	await tree.process_frame


func _boss(spec: Dictionary) -> Enemy:
	w.add_floor()
	var p := w.spawn_player(Vector3(0, 0.05, 0), 0.0)
	PlayerHealth.ensure(p)
	await w.step(5)
	var enc := EnemyEncounter.new()
	w.add_child(enc)
	enc.bounds = AABB(Vector3(-40, -5, -60), Vector3(80, 30, 80))
	enc.entry = Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 25))
	enc.setup(p)
	# 20 m ahead, facing back at the runner (+Z), like a route encounter.
	var e := enc.add_from_spec("host_boss", spec, Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0.05, -20)))
	e.story_event.connect(func(n: String) -> void: events.append(n))
	enc.start()
	for x in enc.enemies:
		x.activate(p)
	return e


func test_the_host_runs_when_hit_and_cant_die() -> void:
	var e := await _boss({"appearance": 1, "flee": [8, 0, -6], "flee_time": 2.0})
	var killed := []
	e.killed.connect(func(info: Dictionary) -> void: killed.append(info))
	await w.step(30)
	check("host:seen" in events, "he sees you (%s)" % [events])
	var start := e.global_position
	for i in 5:
		check(not e.take_hit({"damage": 500.0, "zone": &"head", "position": e.head_position()}), "a hit never kills him")
	check(events.count("host:hit") == 5 and "host:run" in events, "each hit is an event, and he runs (%s)" % [events])
	check(e.health == e.max_health and killed.is_empty(), "no damage, no kill")
	await w.step(60)
	var moved: Vector3 = e.global_position - start
	check(moved.x > 2.0 and moved.z < -1.5, "he runs for his exit: right and away (%s)" % moved)
	await w.step(90)
	check(e.gone and not e.visible, "then he's gone")
	check(e.encounter.phase == e.encounter.Phase.CLEARED, "and his encounter can clear")


func test_the_host_runs_on_his_own_after_a_while() -> void:
	var e := await _boss({"run_after": 1.5})
	await w.step(150)
	check(e.fleeing or e.gone, "he doesn't stand there forever")
	check(not e.is_queued_for_deletion(), "still around while he runs")


func test_the_host_boss_has_his_model_and_gun() -> void:
	var e := await _boss({})
	check(e.body != null and e.body.has_bones(), "the Host's skinned model")
	check(e.body.parts.has("Rifle"), "with his carbine")
	check(e.body.scale.x > 1.05, "a big man (%.2f)" % e.body.scale.x)
