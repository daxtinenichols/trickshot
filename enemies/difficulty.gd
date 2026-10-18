extends RefCounted
## How hard the enemies are, in one place. Each type keeps its own numbers
## (raider.gd, mutant.gd...); this scales them all when an enemy first joins
## a fight: faster on their feet, quicker to aim and fire, tighter aim that
## leads a runner who goes straight, harder hits. Loaded by path (no
## class_name).
##
## The shots stay telegraphed (laser, white lock, beep), so turning after
## the lock still dodges; there is just less time to do it.
##
## Deterministic: plain multipliers on settings, applied once per enemy.

## 1.0 = the game as tuned (hard). 0.0 = the old, easier numbers. Values in
## between (or above 1) scale every multiplier below toward (or past) it.
static var level := 1.0

## Movement: walk/run/fly speeds, acceleration and turning.
const SPEED := 1.25
const SPEED_KEYS := ["move_speed", "run_speed", "walk_speed", "fly_speed", "orbit_speed",
	"hop_speed", "charge_speed", "accel", "turn_rate", "chase_turn_rate"]
## Attack timing: windups, pauses between shots, reloads, recoveries.
const TIME := 0.72
const TIME_KEYS := ["windup", "between_shots", "between_bursts", "reload_time", "recover_time",
	"leap_windup", "swipe_windup", "charge_windup", "leap_cooldown", "charge_cooldown",
	"land_recover", "swipe_recover", "reposition", "burst_gap"]
## The locked, white-laser part of a windup: the dodge window.
const LOCK := 0.8
const LOCK_KEYS := ["lock_time", "charge_lock"]
## How fast the aim follows you before the lock.
const TRACK := 1.6
const TRACK_KEYS := ["aim_track_rate"]
## Bullets fly faster (less time to step out of the way).
const BULLET := 1.3
const BULLET_KEYS := ["bullet_speed"]
## Damage per hit.
const DAMAGE := 1.2
const DAMAGE_KEYS := ["bullet_damage", "leap_damage", "swipe_damage", "charge_damage"]
## Gunners lead a moving target at least this much (0 = aim where you are,
## 1 = where you'll be when the bullet arrives).
const MIN_LEAD := 0.55
## Shooting spread (degrees) tightens.
const SPREAD := 0.7
const SPREAD_KEYS := ["spread"]


static func _scale(k: float) -> float:
	return lerpf(1.0, k, level)


## Scales one enemy's settings. Call once (Enemy does, on activate).
static func apply(e: Object) -> void:
	if level == 0.0:
		return
	for group: Array in [[SPEED_KEYS, SPEED], [TIME_KEYS, TIME], [LOCK_KEYS, LOCK], [TRACK_KEYS, TRACK],
			[BULLET_KEYS, BULLET], [DAMAGE_KEYS, DAMAGE], [SPREAD_KEYS, SPREAD]]:
		var f := _scale(group[1])
		for key: String in group[0]:
			if key in e:
				var v: Variant = e.get(key)
				if v is float:
					e.set(key, v * f)
	if "aim_lead" in e:
		e.set("aim_lead", maxf(float(e.get("aim_lead")), MIN_LEAD * clampf(level, 0.0, 1.0)))
