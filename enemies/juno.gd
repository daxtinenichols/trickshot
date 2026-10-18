extends "res://enemies/hunter.gd"
## Juno, the Static's star hunter and a former Line courier: the boss duel
## at the bottom of the car park (m07). She fights like a hunter, only
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

signal beaten
signal fate_decided(fate: String)

## Below this fraction of her health she speeds up.
@export_range(0.0, 1.0, 0.05) var enrage_at := 0.5
@export var spare_time := 8.0
@export var spare_distance := 25.0

var is_beaten := false
## "" while undecided, then "spared" or "not_spared".
var fate := ""
var enraged := false

var _beaten_time := 0.0
var _nameplate: Label3D

const ENRAGE_SPEED := 1.2
const ENRAGE_WINDUP := 0.77
const ENRAGE_REPOSITION := 0.75


func _ready() -> void:
	super()
	max_health = 420.0
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


func take_hit(info: Dictionary) -> bool:
	if is_dead:
		return false
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
