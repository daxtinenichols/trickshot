extends TestCase
## Smoke tests on the real sandbox scene: it loads, every zone spawn is a
## safe place to stand, and the signature features work in place.

const SANDBOX := preload("res://levels/sandbox.tscn")

var level: Node3D
var player: Player


func before_each() -> void:
	level = SANDBOX.instantiate()
	tree.root.add_child(level)
	player = level.get_node("Player")
	player.use_device_input = false
	player.scripted_input = InputFrame.new()
	await tree.physics_frame


func after_each() -> void:
	Engine.time_scale = 1.0
	level.queue_free()
	await tree.process_frame


func _step(frames: int, f: InputFrame = null) -> void:
	player.scripted_input = f if f != null else InputFrame.new()
	for i in frames:
		await tree.physics_frame


func test_has_ten_zones() -> void:
	var b: SandboxBuilder = level.get_node("Builder")
	check(b.spawns.size() == 10, "10 zone spawns (got %d)" % b.spawns.size())


func test_every_zone_spawn_is_standable() -> void:
	var b: SandboxBuilder = level.get_node("Builder")
	for i in b.spawns.size():
		level.go_to_zone(i)
		await _step(40)
		check(player.state == Player.State.GROUND, "zone %d: standing (state %s)" % [i + 1, Player.State.keys()[player.state]])
		check_near(player.global_position.y, 0.0, 0.05, "zone %d: on the floor" % (i + 1))


func test_every_zone_has_clear_run_up() -> void:
	# Running forward from each spawn for half a second shouldn't hit anything.
	var b: SandboxBuilder = level.get_node("Builder")
	for i in b.spawns.size():
		level.go_to_zone(i)
		await _step(20)
		var z0 := player.global_position.z
		await _step(30, TestWorld.forward_input())
		check(z0 - player.global_position.z > 2.0, "zone %d: free to run forward" % (i + 1))


func test_vault_lane_first_wall() -> void:
	level.go_to_zone(1)
	await _step(20)
	var reached := false
	for i in 300:
		await _step(1, TestWorld.forward_input())
		if player.global_position.z < -8.6:
			reached = true
			break
	check(reached, "reached the first vault wall")
	await _step(1, InputFrame.make(Vector2(0, 1), true))
	check(player.state == Player.State.VAULT, "vaults the first yellow wall")
	await _step(30, TestWorld.forward_input())
	check(player.global_position.z < -10.5, "made it over")


func test_wallrun_corridor() -> void:
	level.go_to_zone(3)
	player.global_position = Vector3(70, 0.05, -6)
	await _step(20)
	player.set_view(-0.35)
	var seen := false
	player.scripted_input = TestWorld.forward_input()
	for i in 240:
		await tree.physics_frame
		if player.global_position.x > 71.0 and player.state == Player.State.GROUND:
			player.scripted_input = InputFrame.make(Vector2(0, 1), true)
		elif player.state == Player.State.AIR:
			player.scripted_input = TestWorld.forward_input()
		if player.state == Player.State.WALLRUN:
			seen = true
			break
	check(seen, "wallruns on the corridor wall")


func test_respawn_key_returns_to_zone() -> void:
	level.go_to_zone(2)
	await _step(10)
	player.global_position = Vector3(0, -45, 0)
	await _step(3)
	var b: SandboxBuilder = level.get_node("Builder")
	check(player.global_position.distance_to(b.spawns[2].origin) < 1.0, "falling out puts you back at the zone")


func test_slide_hill_ramp_speeds_you_up() -> void:
	level.go_to_zone(5)
	player.global_position = Vector3(-55, 10.05, -8)
	await _step(20)
	var on_ramp := false
	for i in 200:
		await _step(1, TestWorld.forward_input())
		if player.global_position.z < -16.0:
			on_ramp = true
			break
	check(on_ramp, "ran onto the ramp")
	await _step(1, InputFrame.make(Vector2(0, 1), false, true))
	var slide := InputFrame.make(Vector2(0, 1), false, true)
	slide.crouch_pressed = false
	var top_speed := 0.0
	for i in 150:
		await _step(1, slide)
		top_speed = maxf(top_speed, player.horizontal_speed())
	check(top_speed > player.tuning.top_speed, "sliding down beats running top speed (%.1f m/s)" % top_speed)


func test_drop_tower_roll() -> void:
	level.go_to_zone(6)
	player.global_position = Vector3(-85, 12.05, -12)
	await _step(20)
	var falling := false
	for i in 120:
		await _step(1, TestWorld.forward_input())
		if player.state == Player.State.AIR and player.global_position.y < 1.2:
			falling = true
			break
	check(falling, "ran off the 12 m tower")
	await _step(1, InputFrame.make(Vector2(0, 1), false, true))
	for i in 20:
		await _step(1, TestWorld.forward_input())
		if player.state != Player.State.AIR:
			break
	check(player.state == Player.State.ROLL, "rolled out of the 12 m drop")


func test_breach_zone_door_and_wall_are_solid() -> void:
	level.go_to_zone(8)
	# Walk at the wall right of the door: must be blocked (no gaps).
	player.global_position = Vector3(140.5, 0.05, -11)
	await _step(10)
	await _step(90, TestWorld.forward_input())
	check(player.global_position.z > -13.8, "wall beside the door is solid")
	# Kick the door open and walk through it.
	player.global_position = Vector3(138.5, 0.05, -12.6)
	player.set_view(0.0)
	await _step(10)
	await _step(1, InputFrame.make(Vector2.ZERO, false, false, true))
	await _step(15)
	var through := false
	for i in 120:
		await _step(1, TestWorld.forward_input())
		if player.global_position.z < -15.0:
			through = true
			break
	check(through, "kicked the door open and went through")
