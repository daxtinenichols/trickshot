extends RefCounted
## Combo armor: the faster and wilder you move, the harder you are to hit.
## Every enemy gunshot rolls against your exposure when it leaves the
## barrel. A hit flies where the enemy aimed (still dodgeable by turning
## after the lock); a miss is pushed off you so it cracks past close
## enough to hear. Damage never changes, only whether the shot lands.
##
## Exposure (1.0 = a normal target):
##   * speed: 1.5 at a walk (4 m/s or less), 0.7 at top speed, 0.4 at
##     15 m/s and faster, straight lines in between;
##   * x0.6 while sliding, wallrunning or part way round a flip or spin;
##   * x0.85 with a live combo of 2x or more.
## Hit chance = HIT_CHANCE x exposure squared (capped at 1): about 1 in 2
## at top speed on a plain line, near certain at a walk, 1 in 10 for a
## fast line full of tricks.
##
## Deterministic: reads only the player's sim state and rolls the shooting
## enemy's own seeded RNG. Loaded by path (no class_name).

const SLOW_SPEED := 4.0
const FAST_SPEED := 15.0
const SLOW_EXPOSURE := 1.5
const TOP_EXPOSURE := 0.7
const FAST_EXPOSURE := 0.4
## Sliding, wallrunning, flipping or spinning.
const TRICK_SCALE := 0.6
## A live combo of at least COMBO_MIN tricks.
const COMBO_SCALE := 0.85
const COMBO_MIN := 2
## Chance a shot lands at exposure 1.
const HIT_CHANCE := 1.0
## A shot that rolls a hit and was locked within this of where you are
## now (m, at your distance) goes where you are: holding your line doesn't
## dodge by luck of the lead. Changing line after the lock moves you
## further than this, and still dodges.
const LOCK_SNAP := 0.7
## How far a miss passes from your chest (m).
const MISS_MIN := 0.9
const MISS_MAX := 1.6

## Off (every shot flies true) for tests that need exact aim.
static var enabled := true


## How exposed the player is right now (see the top of the file).
static func exposure(player: Node) -> float:
	if player == null or not player.has_method("horizontal_speed"):
		return 1.0
	var v: float = player.horizontal_speed()
	var top: float = player.tuning.top_speed if "tuning" in player and player.tuning else 11.5
	var e: float
	if v <= SLOW_SPEED:
		e = SLOW_EXPOSURE
	elif v <= top:
		e = lerpf(SLOW_EXPOSURE, TOP_EXPOSURE, (v - SLOW_SPEED) / maxf(top - SLOW_SPEED, 0.01))
	elif v < FAST_SPEED:
		e = lerpf(TOP_EXPOSURE, FAST_EXPOSURE, (v - top) / maxf(FAST_SPEED - top, 0.01))
	else:
		e = FAST_EXPOSURE
	if _tricking(player):
		e *= TRICK_SCALE
	if player.has_method("combo_multiplier") and player.combo_multiplier() >= COMBO_MIN:
		e *= COMBO_SCALE
	return e


static func _tricking(player: Node) -> bool:
	if player.has_method("is_tricking_in_air") and player.is_tricking_in_air():
		return true
	if player.has_method("is_sliding") and player.is_sliding():
		return true
	return "state" in player and player.state == Player.State.WALLRUN


static func hit_chance(player: Node) -> float:
	var e := exposure(player)
	return clampf(HIT_CHANCE * e * e, 0.0, 1.0)


## The direction a shot really flies: `dir` if it rolls a hit, else turned
## off the player so it passes MISS_MIN..MISS_MAX m from the chest (to the
## side or overhead, never into the floor at your feet, never along the
## way you're running).
## `target`, when given, is where the shot would hit you if it left now.
static func shot_dir(dir: Vector3, from: Vector3, player: Node3D, rng: RandomNumberGenerator, target := Vector3.INF) -> Vector3:
	if not enabled or player == null:
		return dir
	var roll := rng.randf()
	if roll < hit_chance(player):
		if target != Vector3.INF and EnemyMath.point_segment_distance(target, from, from + dir * (from.distance_to(target) + 1.0)) <= LOCK_SNAP:
			return (target - from).normalized()
		return dir
	var chest := EnemyMath.player_chest(player)
	var dist := maxf(from.distance_to(chest), 1.0)
	var aimed := from + dir * dist
	# Push the miss across the way you're moving, never along it (a miss
	# just behind a fast runner would land on them a moment later): over
	# your head for a shot from the side, to either side for one from
	# ahead or behind.
	var moving: Vector3 = player.velocity - dir * player.velocity.dot(dir) if "velocity" in player else Vector3.ZERO
	var axis: Vector3
	if moving.length() > 1.0:
		axis = dir.cross(moving.normalized()).normalized()
		if axis.y < 0.0:
			axis = -axis
		if axis.y < 0.2 and rng.randf() < 0.5:
			axis = -axis  # level: either side
	else:
		var side := dir.cross(Vector3.UP)
		if side.length_squared() < 1e-6:
			side = Vector3.RIGHT
		side = side.normalized()
		var up := side.cross(dir).normalized()
		var a := rng.randf_range(0.0, PI)
		axis = side * cos(a) + up * sin(a)
	return (aimed + axis * rng.randf_range(MISS_MIN, MISS_MAX) - from).normalized()
