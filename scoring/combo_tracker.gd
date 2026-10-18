class_name ComboTracker
extends Node
## Skate-style combo scoring.
##
## - Every move and every stylish hit adds points to the running combo.
## - Multiplier = number of DIFFERENT tricks in the combo, so variety pays.
##   Repeating a trick in the same combo is worth less each time.
## - Each trick's points scale with speed (1x at run pace, 2x at top speed)
##   and with how well it was done (quality 0..1 -> 0.75x..1.25x).
## - The combo banks (points x multiplier go to your score) when you come to
##   rest or go `bank_after` seconds without a new trick. Sliding, wallrunning,
##   climbing and vaulting hold the clock.
## - A kill finishes the combo: it banks right away, ending on the kill.
## - Bailing (crash, hard landing, slamming into a wall, falling out) loses it.
## - Damage scales with the combo: 1 + 0.2 per different trick, times the
##   speed bonus, capped at 3x.
## - Flow: the live combo raises the player's ground cruise speed. Each trick
##   adds flow_per_trick (flips and 360s count flow_flip_weight times), scaled
##   by quality and by the same repeat decay as points. A clean bank lets it
##   fade over flow_fade_time; a bail drops it at once.
##
## Pure game logic: reads the player, never changes it.

signal combo_changed
## A trick (or shot style) was just added, worth `points` before the multiplier.
signal added(trick_name: StringName, points: int)
signal banked(points: int, multiplier: int, total: int)
## A combo ended and scored. summary: {entries, points, multiplier, total,
## reason (&"kill", &"rest", &"timeout")}.
signal finished(summary: Dictionary)
signal bailed(points: int, reason: StringName)

## Base points per trick. Names match Player.trick signal names, plus shot
## tricks created here.
const POINTS := {
	&"hop": 25,
	&"slide": 50,
	&"slide_jump": 75,
	&"vault": 75,
	&"mantle": 75,
	&"wallrun": 50,           # on entry; plus WALLRUN_PER_SECOND while on the wall
	&"wall_jump": 150,
	&"wall_hop": 150,
	&"wall_climb": 100,
	&"wall_climb_kick": 150,
	&"landing_roll": 100,
	&"ground_roll": 75,
	&"flip_roll": 250,
	&"kick_off": 150,         # 250 when kicking off a target
	&"kick": 50,
	&"kick_kill": 300,        # a kick that finishes an enemy
	&"door_kick": 100,
	&"window_kick": 100,
	&"window_smash": 150,
	&"backflip": 300,
	&"frontflip": 300,
	&"sideflip": 300,
	&"ramp_run": 75,
	&"loop": 500,
	&"spin_360": 200,
	&"spin_720": 500,
	&"spin_1080": 900,
	# Shots
	&"hit": 25,
	&"headshot": 150,
	&"air_shot": 200,
	&"long_shot": 200,
	&"slide_shot": 200,
	&"wallrun_shot": 300,
	&"flip_shot": 400,
	&"spin_shot": 400,
	&"kill": 100,
	&"combo_kill": 500,
	&"feed_cut": 400,         # shooting down one of the Host's camera drones
}
const KICK_OFF_TARGET_POINTS := 250
const WALLRUN_PER_SECOND := 100.0
const BAIL_TRICKS := [&"crash", &"hard_landing", &"wall_impact"]
## States where a long move is under way, so the bank clock holds.
const HOLDING_STATES := [
	Player.State.SLIDE, Player.State.WALLRUN, Player.State.WALLCLIMB,
	Player.State.VAULT, Player.State.MANTLE, Player.State.ROLL,
	Player.State.SURFACE,
]
const REST_STATES := [Player.State.GROUND, Player.State.CROUCH]
## Rotations, which count extra toward flow.
const FLIP_TRICKS := [&"backflip", &"frontflip", &"sideflip", &"spin_360", &"spin_720", &"spin_1080"]

@export var bank_after := 2.0
## Below this speed on the ground for `rest_time`, you've come to rest.
@export var rest_speed := 1.0
@export var rest_time := 0.25
## Each repeat of a trick in one combo is worth this fraction of the last.
@export var repeat_decay := 0.6
@export var damage_per_trick := 0.2
@export var damage_cap := 3.0
## Air shots need this long off the ground.
@export var air_shot_time := 0.4
@export var long_shot_distance := 40.0

var player: Player
## How well the last trick added was done (0..1), or -1 if it isn't graded.
var last_quality := -1.0
var score := 0
var best_combo := 0
## Current combo: one entry per trick name, in order first done:
## {name, points (float), count, flow (m/s)}.
var entries: Array[Dictionary] = []
var combo_points := 0.0
var time_left := 0.0

var _rest := 0.0
var _wallrun_entry := -1
## Flow of the live combo (sum of the entries' flow), and what's left of the
## last banked combo's flow as it fades out.
var _flow := 0.0
var _fade_flow := 0.0
var _fade_from := 0.0


func setup(p: Player, pistol: Pistol = null) -> void:
	player = p
	p.trick.connect(on_trick)
	p.respawned.connect(func() -> void: bail(&"respawn"))
	p.flow_source = flow
	p.repeat_scale_source = repeat_scale
	p.combo_source = multiplier
	if pistol:
		pistol.hit.connect(on_hit)
		pistol.damage_scale = damage_multiplier
	# Kicks hurt enemies by the same combo multiplier as shots.
	p.kick_damage_scale = damage_multiplier


func is_active() -> bool:
	return not entries.is_empty()


func multiplier() -> int:
	return entries.size()


## The points shown (rounded) times the multiplier, so the card's sum adds up.
func combo_total() -> int:
	return roundi(combo_points) * multiplier()


## Extra ground cruise speed from style (m/s): the live combo's flow, or
## the last clean combo's as it fades, whichever is more.
func flow() -> float:
	return maxf(_flow, _fade_flow)


## What the last `n` of the tricks in `names` (already added to this combo)
## are worth after repeat decay: 1 + 0.6 + ... for the first ones, less for
## later repeats.
func repeat_scale(names: Array, n: int) -> float:
	var total := 0
	for e in entries:
		if e.name in names:
			total += e.count
	var earlier := maxi(total - n, 0)
	var sum := 0.0
	for i in n:
		sum += pow(repeat_decay, earlier + i)
	return sum


## 1x at run pace or slower, 2x at top speed and above.
func speed_bonus(speed: float) -> float:
	if player == null:
		return 1.0
	var t := player.tuning
	return 1.0 + clampf((speed - t.run_speed) / maxf(t.top_speed - t.run_speed, 0.01), 0.0, 1.0)


## Shot damage scale from the current combo and speed (1x .. damage_cap).
func damage_multiplier() -> float:
	var speed := player.horizontal_speed() if player else 0.0
	return minf((1.0 + damage_per_trick * multiplier()) * speed_bonus(speed), damage_cap)


# ---------------------------------------------------------------- events

func on_trick(trick_name: StringName, info: Dictionary) -> void:
	if trick_name in BAIL_TRICKS:
		bail(trick_name)
		return
	if not POINTS.has(trick_name):
		return  # feedback-only events (quick turn, kick miss)
	var base: float = POINTS[trick_name]
	if trick_name == &"kick_off" and info.get("target", false):
		base = KICK_OFF_TARGET_POINTS
	var idx := add(trick_name, base, float(info.get("speed", 0.0)), info.get("quality", -1.0))
	if trick_name == &"wallrun":
		_wallrun_entry = idx


## A pistol hit. Style comes from what the player was doing when they fired.
func on_hit(info: Dictionary) -> void:
	if info.get("target") == null:
		return
	var speed := player.horizontal_speed() if player else 0.0
	var tags: Array = info.get("tags", [])
	var style: Array[StringName] = []
	if info.get("zone", &"") == &"head":
		style.append(&"headshot")
	if &"airborne" in tags and player and player.time_off_ground() >= air_shot_time:
		style.append(&"air_shot")
	if float(info.get("distance", 0.0)) > long_shot_distance:
		style.append(&"long_shot")
	if &"wallrun" in tags:
		style.append(&"wallrun_shot")
	if &"sliding" in tags:
		style.append(&"slide_shot")
	if &"flipping" in tags or &"side_flipping" in tags or &"upside_down" in tags:
		style.append(&"flip_shot")
	if &"spinning" in tags:
		style.append(&"spin_shot")
	if info.get("killed", false):
		# Cut the Feed: the target is a camera drone (it has the feed_cut signal).
		var target: Object = info.get("target")
		if target.has_signal(&"feed_cut"):
			style.append(&"feed_cut")
		style.append(&"combo_kill" if is_active() else &"kill")
	if style.is_empty():
		style.append(&"hit")
	for s in style:
		add(s, POINTS[s], speed)
	if info.get("killed", false):
		bank(&"kill")


## Adds a trick to the combo (starting one if needed). Returns its entry index.
func add(trick_name: StringName, base: float, speed: float, quality: float = -1.0) -> int:
	var q_scale := lerpf(0.75, 1.25, clampf(quality, 0.0, 1.0)) if quality >= 0.0 else 1.0
	var value := base * speed_bonus(speed) * q_scale
	var idx := _find(trick_name)
	if idx < 0:
		entries.append({"name": trick_name, "points": 0.0, "count": 0, "flow": 0.0})
		idx = entries.size() - 1
	var e := entries[idx]
	var decay := pow(repeat_decay, e.count)
	value *= decay
	e.count += 1
	e.points += value
	combo_points += value
	var flow_add := _flow_per_trick(trick_name) * q_scale * decay
	e.flow += flow_add
	_flow += flow_add
	time_left = bank_after
	_rest = 0.0
	last_quality = quality
	added.emit(trick_name, roundi(value))
	combo_changed.emit()
	return idx


func bank(reason := &"rest") -> void:
	if not is_active():
		return
	var total := combo_total()
	var mult := multiplier()
	var pts := roundi(combo_points)
	var summary := {"entries": entries.duplicate(true), "points": pts, "multiplier": mult, "total": total, "reason": reason}
	score += total
	best_combo = maxi(best_combo, total)
	# A clean finish keeps its speed for a moment: flow eases out.
	_fade_from = flow()
	_fade_flow = _fade_from
	_clear()
	banked.emit(pts, mult, total)
	finished.emit(summary)


func bail(reason: StringName) -> void:
	_fade_flow = 0.0
	if not is_active():
		return
	var lost := combo_total()
	_clear()
	bailed.emit(lost, reason)


func _clear() -> void:
	entries.clear()
	combo_points = 0.0
	time_left = 0.0
	_rest = 0.0
	_wallrun_entry = -1
	_flow = 0.0
	combo_changed.emit()


func _flow_per_trick(trick_name: StringName) -> float:
	if player == null:
		return 0.0
	var t := player.tuning
	return t.flow_per_trick * (t.flow_flip_weight if trick_name in FLIP_TRICKS else 1.0)


func _find(trick_name: StringName) -> int:
	for i in entries.size():
		if entries[i].name == trick_name:
			return i
	return -1


# ---------------------------------------------------------------- tick

func _physics_process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	if player == null:
		return
	if _fade_flow > 0.0:
		var fade := player.tuning.flow_fade_time
		_fade_flow = maxf(_fade_flow - _fade_from * delta / fade, 0.0) if fade > 0.0 else 0.0
	if not is_active():
		return
	var state := player.state
	if state == Player.State.WALLRUN and _wallrun_entry >= 0 and _wallrun_entry < entries.size():
		var add_pts := WALLRUN_PER_SECOND * delta * speed_bonus(player.horizontal_speed())
		entries[_wallrun_entry].points += add_pts
		combo_points += add_pts
	if state in HOLDING_STATES:
		time_left = bank_after
	else:
		time_left -= delta
	if state in REST_STATES and player.horizontal_speed() < rest_speed:
		_rest += delta
	else:
		_rest = 0.0
	if time_left <= 0.0:
		bank(&"timeout")
	elif _rest >= rest_time:
		bank(&"rest")
