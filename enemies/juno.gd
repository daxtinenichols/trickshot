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


func _model_path() -> String:
	return "res://enemies/models/juno.glb"


func _on_reset() -> void:
	super()
	is_beaten = false
	fate = ""
	enraged = false
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
		enraged = true
		move_speed = 9.5
		windup = 0.5
		reposition = 1.5
	return killed


func _beat() -> void:
	is_beaten = true
	_beaten_time = 0.0
	telegraph = 0.0
	_interrupt()
	velocity = Vector3(0, velocity.y, 0)
	beaten.emit()


func _decide(f: String) -> void:
	fate = f
	fate_decided.emit(f)


func tick(delta: float) -> void:
	if is_beaten and not is_dead:
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
