extends "res://enemies/hunter.gd"
## Juno, the Static's star hunter and a former Line courier: the boss fight
## up the Meridian car park (4-2). She fights like a hunter, only
## better: she reads where you look, keeps flanking, and gets faster once
## she's hurt.
##
## She can't be killed outright. When her health runs out she's beaten:
## she drops to a knee and the fight stops (signal `beaten`). Then it's
## your call, which the mission reads for the radio:
##   * shoot her again while she's down: not spared (`fate` = "not_spared",
##     she dies, and it counts as a kill);
##   * leave her be for spare_time seconds, or walk away (spare_distance):
##     spared (`fate` = "spared"; she leaves, which clears the encounter).
## `fate_decided(fate)` fires once either way.
##
## With `phases` (4-2's car park) the fight comes in stages. Her guard
## takes ordinary hits; it breaks only to a kick at the end of a combo of
## GUARD_COMBO tricks or more, or a headshot while you're off the ground
## (in the air or on a wall). Each phase takes `breaks_per_phase` breaks:
## then she staggers (story_event "juno:phase", numbered "juno:phase:1"...)
## and runs on ahead to the next phase's spot. Run past a phase's `until`
## point and she goes on ahead the same way, unbroken. The last phase's
## breaks beat her. Each phase is
##   {"spot": [x, y, z], "area": [x0, z0, x1, z1] (where she keeps to),
##    "path": [[x, y, z], ...] (her run there from the last spot),
##    "until": [x, y, z], "range": [min, preferred, max]}
## in world space. She's quicker and sharper each phase, and harder on you
## when you slow down (under SLOW_SPEED, about base top speed: a quick windup, more damage).

signal beaten
signal fate_decided(fate: String)
signal story_event(event_name: String)

## Below this fraction of her health she speeds up.
@export_range(0.0, 1.0, 0.05) var enrage_at := 0.5
@export var spare_time := 8.0
@export var spare_distance := 25.0
## The fight's stages (see the top); none for the old one-room duel.
@export var phases: Array = []
@export var breaks_per_phase := 2
## Her kick when she runs you down.
@export var strike_damage := 40.0

var is_beaten := false
## "" while undecided, then "spared" or "not_spared".
var fate := ""
var enraged := false

var _beaten_time := 0.0
var _nameplate: Label3D
## The phase she's fighting (an index into `phases`) and its guard breaks.
var phase := 0
var guard_breaks := 0
## Points left on her run to the next spot (empty while she fights).
var _run: Array = []
var _base_windup := 0.0
var _base_damage := 0.0
var _base_between := 0.0
var _base_recover := 0.0
var _strike_cd := 0.0
var _slow_for := 0.0
## You've reached this phase's `until` point (she goes on once she isn't
## on your heels).
var _reached_until := false
## Strikes that landed (tests).
var strikes := 0

const ENRAGE_SPEED := 1.2
const ENRAGE_WINDUP := 0.77
const ENRAGE_REPOSITION := 0.75
## Tricks in the combo a kick must finish to break her guard.
const GUARD_COMBO := 3
## How fast she runs between spots (m/s).
const RUN_SPEED := 16.0
## Slower than this (m/s) and she makes you pay.
const SLOW_SPEED := 12.0
const SLOW_WINDUP := 0.45
const SLOW_DAMAGE := 1.5
## ...and fires again this much sooner.
const SLOW_CADENCE := 0.35
const CHASE_RANGE := 18.0
const CHASE_SPEED := 13.2
const STRIKE_REACH := 2.4
const STRIKE_COOLDOWN := 0.9
## How long you have to stay slow before she comes for you (a landing's
## dip doesn't count).
const SLOW_GRACE := 0.4
## Each phase: faster on her feet and on the trigger.
const PHASE_SPEED := 1.12
const PHASE_WINDUP := 0.85


func _ready() -> void:
	super()
	max_health = 420.0
	one_shot_headshot = false
	health = max_health
	move_speed = 8.0
	windup = 0.65
	lock_time = 0.25
	aim_track_rate = 110.0
	aim_lead = 0.4
	bullet_damage = 16.0
	shots_per_reload = 5
	reposition = 2.0
	kick_stagger = 0.5
	knockdown_time = 1.0
	_build_nameplate()
	if not phases.is_empty():
		aim_lead = 1.0
		aim_track_rate = 160.0
		_enter_phase(0)


## Her name over her head while the duel is on, so you know who you're
## fighting from across the car park.
func _build_nameplate() -> void:
	_nameplate = Label3D.new()
	_nameplate.text = "JUNO"
	_nameplate.font_size = 64
	_nameplate.outline_size = 16
	_nameplate.modulate = Color(1.0, 0.25, 0.15)
	_nameplate.outline_modulate = Color(0.08, 0.02, 0.02)
	_nameplate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_nameplate.fixed_size = true
	_nameplate.pixel_size = 0.0012
	_nameplate.position = Vector3(0, 2.25, 0)
	_nameplate.visible = false
	_visual.add_child(_nameplate)


func _animate(delta: float) -> void:
	super(delta)
	if _nameplate:
		_nameplate.visible = active and not is_dead and not is_beaten


func _model_path() -> String:
	return "res://enemies/models/juno.glb"


func _on_reset() -> void:
	super()
	is_beaten = false
	fate = ""
	if enraged:
		_enrage(false)
	_beaten_time = 0.0
	if body:
		body.visible = true
	if not phases.is_empty():
		_run.clear()
		_set_alive_collision(true)
		_enter_phase(0)


func take_hit(info: Dictionary) -> bool:
	if is_dead:
		return false
	if not phases.is_empty() and not is_beaten:
		return _guarded_hit(info)
	if is_beaten:
		# Shot while she's down: the player chose.
		if fate == "":
			_decide("not_spared")
			hits_taken += 1
			_flash = 1.0
			damaged.emit(info)
			_die(info)
			return true
		return false
	if health - float(info.get("damage", 0.0)) <= 0.0:
		info = info.duplicate()
		info.damage = maxf(health - 1.0, 0.0)
		super(info)
		_beat()
		return false
	var killed := super(info)
	if not enraged and health <= max_health * enrage_at:
		_enrage(true)
	return killed


## Hurt: faster on her feet and on the trigger (undone when the duel resets).
func _enrage(on: bool) -> void:
	enraged = on
	var k := 1.0 if on else -1.0
	move_speed *= pow(ENRAGE_SPEED, k)
	windup *= pow(ENRAGE_WINDUP, k)
	reposition *= pow(ENRAGE_REPOSITION, k)


## A hit in the phased fight: only a guard break counts.
func _guarded_hit(info: Dictionary) -> bool:
	if not _run.is_empty():
		return false
	hits_taken += 1
	_flash = 1.0
	if not breaks_guard(info):
		_flash = 0.4
		return false
	guard_breaks += 1
	damaged.emit(info)
	_stagger = maxf(_stagger, 0.9)
	_interrupt()
	if guard_breaks >= breaks_per_phase:
		_end_phase()
	return false


## Does this hit break her guard: a kick finishing a combo of GUARD_COMBO
## tricks or more, or a headshot from the air or a wall?
func breaks_guard(info: Dictionary) -> bool:
	if info.get("kick", false):
		return player != null and player.has_method("combo_multiplier") and player.combo_multiplier() >= GUARD_COMBO
	if info.get("zone", &"body") != &"head":
		return false
	var tags: Array = info.get("tags", [])
	return &"airborne" in tags or &"wallrun" in tags or &"flipping" in tags


## This phase is over (broken, or you ran past it): she staggers, says her
## piece, and runs on to the next spot; after the last she's beaten.
func _end_phase() -> void:
	story_event.emit("juno:phase")
	if phase >= phases.size() - 1:
		_beat()
		return
	_enter_phase(phase + 1)
	var ph: Dictionary = phases[phase]
	_run = (ph.get("path", []) as Array).duplicate()
	_run.append(ph.spot)
	_set_alive_collision(false)
	telegraph = 0.0


## Her settings for phase `i`: range, speed and windup step up each phase.
func _enter_phase(i: int) -> void:
	if _base_windup == 0.0:
		_base_windup = windup
		_base_damage = bullet_damage
		_base_between = between_shots
		_base_recover = recover_time
	phase = i
	guard_breaks = 0
	_reached_until = false
	var ph: Dictionary = phases[i]
	var r: Array = ph.get("range", [6.0, 11.0, 24.0])
	min_range = float(r[0])
	preferred_range = float(r[1])
	max_range = float(r[2])
	move_speed = 8.0 * pow(PHASE_SPEED, i)
	windup = _base_windup * pow(PHASE_WINDUP, i)


## Has the player reached this phase's `until` point (since it began)?
func _passed(ph: Dictionary) -> bool:
	if not ph.has("until") or player == null:
		return false
	var u := Vector3(ph.until[0], ph.until[1], ph.until[2])
	var d := player.global_position - u
	if Vector2(d.x, d.z).length() < 6.0 and absf(d.y) < 3.0:
		_reached_until = true
	return _reached_until


## Keeps a point inside this phase's area.
func _keep_in_phase(p: Vector3) -> Vector3:
	var a: Array = phases[phase].get("area", [])
	if a.size() < 4:
		return p
	return Vector3(clampf(p.x, minf(a[0], a[2]), maxf(a[0], a[2])), p.y, clampf(p.z, minf(a[1], a[3]), maxf(a[1], a[3])))


func _pick_spot() -> void:
	super()
	if not phases.is_empty():
		move_target = _keep_in_phase(move_target)


## You slowed down near her: she comes straight at you and kicks.
func _run_down(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	_tick_solid(delta)
	var to := EnemyMath.horizontal(player.global_position - global_position)
	face_toward(player.global_position, delta, 2.0)
	steer(to.normalized() * CHASE_SPEED if to.length() > 1.2 else Vector3.ZERO, accel * 3.0, delta)
	_hop_holes()
	telegraph = 0.0
	if _strike_cd <= 0.0 and to.length() <= STRIKE_REACH and absf(player.global_position.y - global_position.y) < 1.6:
		_strike_cd = STRIKE_COOLDOWN
		strikes += 1
		EnemySfx.play_at(self, &"swipe")
		hurt_player(strike_damage, &"kick")
	move_and_slide()


## Run into in the phased fight: she isn't bowled over, she lets you
## shoulder past and keeps coming.
func on_body_checked(by: Node, dir: Vector3, speed: float) -> bool:
	if phases.is_empty() or is_beaten or is_dead:
		return super(by, dir, speed)
	_barged = BARGE_TIME
	_set_body_solid(false)
	return true


## A hole in the floor just ahead: she jumps it, like you would.
func _hop_holes() -> void:
	var h := EnemyMath.horizontal(velocity)
	if not is_on_floor() or h.length() < 3.0:
		return
	var ahead := global_position + h.normalized() * 1.4 + Vector3.UP * 0.5
	var q := PhysicsRayQueryParameters3D.create(ahead, ahead + Vector3.DOWN * 2.0, 1)
	q.exclude = [get_rid()]
	if get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		velocity.y = hop_speed
		hops += 1


func _think(delta: float) -> void:
	super(delta)
	if not phases.is_empty() and state == State.MOVE:
		_hop_holes()


## Her run between spots: straight along the path, through anything in
## the way (she knows the car park), not stopping to shoot.
func _tick_run(delta: float) -> void:
	var to: Array = _run[0]
	var target := Vector3(to[0], to[1], to[2])
	var d := target - global_position
	var step := RUN_SPEED * delta
	if d.length() <= step:
		global_position = target
		_run.pop_front()
		if _run.is_empty():
			velocity = Vector3.ZERO
			_set_alive_collision(true)
			_set_state(State.HOLD)
			_rethink = 0.0
			_since_pick = reposition
		return
	velocity = d.normalized() * RUN_SPEED
	global_position += velocity * delta
	yaw = EnemyMath.yaw_of(EnemyMath.horizontal(d))
	rotation = Vector3(0, yaw, 0)


func _beat() -> void:
	is_beaten = true
	_beaten_time = 0.0
	telegraph = 0.0
	_interrupt()
	velocity = Vector3(0, velocity.y, 0)
	beaten.emit()


## Reaching her ends the duel too (fighting is never required): she drops
## to a knee as if shot down, and the spare-or-not choice follows.
func concede() -> void:
	if not is_beaten and not is_dead:
		_beat()


func _decide(f: String) -> void:
	fate = f
	fate_decided.emit(f)


func tick(delta: float) -> void:
	if is_beaten and not is_dead:
		_knocked = maxf(_knocked - delta, 0.0)
		_tick_solid(delta)
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
		steer(Vector3.ZERO, 20.0, delta)
		move_and_slide()
		_beaten_time += delta
		duck = move_toward(duck, 1.0, 3.0 * delta)
		if fate == "":
			var far := player != null and distance_to_player() > spare_distance
			if _beaten_time >= spare_time or far:
				_decide("spared")
				_leave()
		return
	if not phases.is_empty() and not is_dead:
		if not _run.is_empty():
			_tick_run(delta)
			return
		var slow := player != null and player.horizontal_speed() < SLOW_SPEED
		_slow_for = _slow_for + delta if slow else 0.0
		var chasing := active and _slow_for >= SLOW_GRACE and distance_to_player() < CHASE_RANGE
		# Past her spot: she runs on ahead, unless she's on your heels.
		if active and not chasing and phase < phases.size() - 1 and _passed(phases[phase]):
			_end_phase()
			return
		windup = _base_windup * pow(PHASE_WINDUP, phase) * (SLOW_WINDUP if slow else 1.0)
		bullet_damage = _base_damage * (SLOW_DAMAGE if slow else 1.0)
		between_shots = _base_between * (SLOW_CADENCE if slow else 1.0)
		recover_time = _base_recover * (SLOW_CADENCE if slow else 1.0)
		_strike_cd = maxf(_strike_cd - delta, 0.0)
		if chasing and _stagger <= 0.0:
			_run_down(delta)
			return
	super(delta)


## Spared: she's out of the fight (the encounter can clear), alive.
func _leave() -> void:
	is_dead = true
	_set_alive_collision(false)
	if encounter and encounter.has_method("on_enemy_killed"):
		encounter.on_enemy_killed(self)
	var tw := create_tween()
	tw.tween_interval(2.0)
	tw.tween_callback(func() -> void: visible = false)


func _animate_body(delta: float) -> void:
	if is_beaten:
		body.show_pose(Poses.layer(Poses.kneel(), Poses.add(Poses.low_ready(), {"Head": Vector3(24, 0, 0)})), delta, 8.0)
		hold_rifle(Vector3.FORWARD, 0.0, 0.0, rifle_fore)
		return
	super(delta)
