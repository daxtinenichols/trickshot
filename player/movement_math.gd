class_name MovementMath
extends RefCounted
## Pure movement helpers (no scene access) so they can be unit tested.


## Source/Quake-style acceleration toward wish_dir, capped at wish_speed along
## that direction. Speed perpendicular to wish_dir is untouched, which is what
## makes air strafing gain speed.
static func accelerate(vel: Vector3, wish_dir: Vector3, wish_speed: float, accel: float, delta: float) -> Vector3:
	if wish_dir == Vector3.ZERO:
		return vel
	var current := vel.dot(wish_dir)
	var add := wish_speed - current
	if add <= 0.0:
		return vel
	var step := minf(accel * wish_speed * delta, add)
	return vel + wish_dir * step


## Quake-style ground friction on the horizontal part of vel.
static func apply_friction(vel: Vector3, friction: float, stop_speed: float, delta: float) -> Vector3:
	var h := Vector3(vel.x, 0.0, vel.z)
	var speed := h.length()
	if speed < 0.0001:
		return Vector3(0.0, vel.y, 0.0)
	var drop := maxf(speed, stop_speed) * friction * delta
	var new_speed := maxf(speed - drop, 0.0)
	h *= new_speed / speed
	return Vector3(h.x, vel.y, h.z)


static func horizontal(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


static func horizontal_speed(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


## Direction along a wall the player is travelling, given their velocity.
static func wall_tangent(wall_normal: Vector3, vel: Vector3) -> Vector3:
	var n := horizontal(wall_normal).normalized()
	var t := n.cross(Vector3.UP).normalized()
	if t.dot(vel) < 0.0:
		t = -t
	return t


## Velocity after a wall jump: keep the along-wall speed, push off and up.
static func wall_jump_velocity(vel: Vector3, wall_normal: Vector3, push: float, up: float, boost_dir: Vector3, boost: float) -> Vector3:
	var n := horizontal(wall_normal).normalized()
	var h := horizontal(vel)
	var along := h - n * h.dot(n)
	var out := along + n * push + boost_dir * boost
	out.y = up
	return out


## Velocity after a kick-off from a surface with normal n.
static func kick_velocity(vel: Vector3, n: Vector3, push: float, up: float, keep_tangent: float) -> Vector3:
	var hn := horizontal(n)
	if hn.length() < 0.2:
		# Kicking off a floor or ceiling: just launch upward/away.
		var out_v := horizontal(vel) * keep_tangent
		out_v.y = up if n.y >= 0.0 else -up * 0.5
		return out_v
	hn = hn.normalized()
	var h := horizontal(vel)
	var tangent := (h - hn * h.dot(hn)) * keep_tangent
	var out := tangent + hn * push
	out.y = maxf(up, vel.y)
	return out


## 0..1 momentum to ground wish speed.
static func ground_wish_speed(run_speed: float, top_speed: float, momentum: float) -> float:
	return lerpf(run_speed, top_speed, clampf(momentum, 0.0, 1.0))
