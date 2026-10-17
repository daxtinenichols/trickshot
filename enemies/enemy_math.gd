class_name EnemyMath
extends RefCounted
## Small geometry helpers for enemy logic. Pure functions, so they are easy
## to test and always give the same answer for the same input.


## Shortest distance between segments p1-q1 and p2-q2.
static func segment_distance(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> float:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 1e-8 and e <= 1e-8:
		return r.length()
	if a <= 1e-8:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 1e-8:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var denom := a * e - b * b
			s = clampf((b * f - c * e) / denom, 0.0, 1.0) if denom > 1e-8 else 0.0
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	return ((p1 + d1 * s) - (p2 + d2 * t)).length()


static func point_segment_distance(p: Vector3, a: Vector3, b: Vector3) -> float:
	return segment_distance(p, p, a, b)


## The player's body as a capsule axis [bottom, top] (radius Player.RADIUS).
## Follows the body when it runs on loops and ramps.
static func player_axis(player: Node3D) -> Array[Vector3]:
	var up: Vector3 = player.body_up() if player.has_method("body_up") else Vector3.UP
	var height: float = player.head.position.y + Player.EYE_OFFSET if "head" in player and player.head else 1.8
	var r := Player.RADIUS
	var feet := player.global_position
	return [feet + up * r, feet + up * maxf(height - r, r)]


## The point enemies aim at: the middle of the chest.
static func player_chest(player: Node3D) -> Vector3:
	var axis := player_axis(player)
	return axis[0].lerp(axis[1], 0.6)


## Turns yaw `from` toward `to` by at most `max_step` radians.
static func turn_yaw(from: float, to: float, max_step: float) -> float:
	var diff := wrapf(to - from, -PI, PI)
	return from + clampf(diff, -max_step, max_step)


## The yaw that faces along a horizontal direction (-Z forward at yaw 0).
static func yaw_of(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


static func horizontal(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## Rotates direction `from` toward `to` by at most `max_angle` radians.
static func turn_dir(from: Vector3, to: Vector3, max_angle: float) -> Vector3:
	var a := from.normalized()
	var b := to.normalized()
	var angle := a.angle_to(b)
	if angle <= max_angle or angle < 1e-5:
		return b
	var axis := a.cross(b)
	if axis.length_squared() < 1e-8:
		axis = Vector3.UP
	return a.rotated(axis.normalized(), max_angle)
