extends TestCase

const DT := 1.0 / 60.0


func test_accelerate_reaches_but_does_not_exceed_wish_speed() -> void:
	var v := Vector3.ZERO
	for i in 600:
		v = MovementMath.accelerate(v, Vector3.FORWARD, 7.0, 10.0, DT)
	check_near(v.length(), 7.0, 0.001, "speed settles at wish speed")


func test_accelerate_never_slows_you_down() -> void:
	var v := Vector3(0, 0, -15)
	v = MovementMath.accelerate(v, Vector3.FORWARD, 7.0, 10.0, DT)
	check_near(v.length(), 15.0, 0.0001, "faster than wish speed is untouched")


func test_air_strafing_gains_speed() -> void:
	# Classic strafe: wish direction kept ~90 degrees to velocity while turning.
	var v := Vector3(0, 0, -8)
	for i in 120:
		var dir := MovementMath.horizontal(v).normalized()
		var wish := dir.rotated(Vector3.UP, deg_to_rad(-89.0))
		v = MovementMath.accelerate(v, wish, 0.6, 12.0, DT)
	check(MovementMath.horizontal_speed(v) > 8.3, "strafing adds speed (got %.2f)" % MovementMath.horizontal_speed(v))


func test_holding_forward_in_air_does_not_add_speed() -> void:
	var v := Vector3(0, 0, -8)
	for i in 120:
		v = MovementMath.accelerate(v, Vector3.FORWARD, 0.6, 12.0, DT)
	check_near(v.length(), 8.0, 0.0001, "no free speed from W in the air")


func test_friction_stops_and_keeps_vertical() -> void:
	var v := Vector3(5, -3, 0)
	for i in 120:
		v = MovementMath.apply_friction(v, 6.0, 2.5, DT)
	check_near(MovementMath.horizontal_speed(v), 0.0, 0.0001, "friction stops horizontal motion")
	check_near(v.y, -3.0, 0.0001, "friction leaves vertical speed alone")


func test_wall_tangent_follows_velocity() -> void:
	var n := Vector3(1, 0, 0)
	var t := MovementMath.wall_tangent(n, Vector3(0, 0, -5))
	check(t.dot(Vector3(0, 0, -1)) > 0.99, "tangent points the way you move")
	t = MovementMath.wall_tangent(n, Vector3(0, 0, 5))
	check(t.dot(Vector3(0, 0, 1)) > 0.99, "and flips when you move the other way")


func test_wall_jump_pushes_off_and_keeps_along_speed() -> void:
	var v := Vector3(0, -1, -9)
	var out := MovementMath.wall_jump_velocity(v, Vector3(1, 0, 0), 6.0, 7.0, Vector3.ZERO, 0.0)
	check_near(out.x, 6.0, 0.001, "pushed away from the wall")
	check_near(out.z, -9.0, 0.001, "speed along the wall kept")
	check_near(out.y, 7.0, 0.001, "upward speed set")


func test_kick_velocity_off_wall() -> void:
	var v := Vector3(-4, -2, -6)  # moving into a wall facing +x
	var out := MovementMath.kick_velocity(v, Vector3(1, 0, 0), 7.5, 6.5, 0.9)
	check_near(out.x, 7.5, 0.001, "launched straight off the wall")
	check_near(out.z, -5.4, 0.001, "90% of along-wall speed kept")
	check_near(out.y, 6.5, 0.001, "launched upward")


func test_ground_wish_speed_scales_with_momentum() -> void:
	check_near(MovementMath.ground_wish_speed(6.0, 9.5, 0.0), 6.0, 0.0001, "zero momentum = run speed")
	check_near(MovementMath.ground_wish_speed(6.0, 9.5, 1.0), 9.5, 0.0001, "full momentum = top speed")
	check_near(MovementMath.ground_wish_speed(6.0, 9.5, 5.0), 9.5, 0.0001, "clamped")
