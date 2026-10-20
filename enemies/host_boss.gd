extends "res://enemies/raider.gd"
## The Host in person (m09b Head Office): he turns up on a balcony, a
## catwalk or in his office, takes a few shots at you with his gold carbine,
## then runs. Same model as the chase in Signal Out (art/characters/host,
## shown 1.1x).
##
## He can't die, and a hit is never a kill. Hitting him is a bonus: each
## hit is a "host:hit" story event, and `hits_to_run` hits (default 1: the
## first) send him running at once. He also runs `run_after` seconds after
## he wakes, after `shots_before_run` shots, when you get within
## `flee_distance`, or when you kick him. Running, he heads for `flee` (an
## offset in his own frame: he faces +Z toward the runner, so [8, 0, -6] is
## 8 m to the runner's right and 6 m further along the run) for up to
## `flee_time` seconds, then he's gone: out of the fight, so his encounter
## can clear (like a spared Juno).
##
## Story events (signal story_event; MissionRun forwards them to the radio):
## "host:seen" when he first sees you, "host:hit" per hit, "host:run" when
## he takes off.
##
## Mission spec (route encounter "enemies" list): {"type": "host_boss",
## "x": 3, "d": 20, "elevation": 3.5, "appearance": 1, "flee": [8, 0, -6]}.
## Optional: "run_after", "hits_to_run", "shots_before_run",
## "flee_distance", "flee_speed", "flee_time".

signal story_event(event_name: String)

const MODEL_PATH := "res://art/characters/host/host.glb"
const SCALE := 1.1

## Which of his turns this is (1 atrium balcony, 2 server room catwalk,
## 3 corner office); for the mission's own use.
@export var appearance := 1
@export var run_after := 6.0
@export var hits_to_run := 1
@export var shots_before_run := 4
@export var flee_distance := 7.0
## Where he runs to, in his own frame (+Z toward the runner). Empty: away
## from you.
@export var flee: Array = []
@export var flee_speed := 9.0
@export var flee_time := 3.0

var fleeing := false
var gone := false
var seen := false
## Hits this appearance.
var hits := 0

var _flee_left := 0.0
var _flee_dir := Vector3.FORWARD
var _flee_target := Vector3.INF
var _awake := 0.0


func _ready() -> void:
	super()
	max_health = 1000.0
	one_shot_headshot = false
	health = max_health
	# He's a showman, not a soldier: quick to aim, a light carbine.
	windup = 0.75
	lock_time = 0.28
	aim_track_rate = 95.0
	bullet_damage = 14.0
	shots_per_reload = 4
	between_shots = 0.55
	preferred_range = 18.0
	min_range = 0.0
	max_range = 40.0
	_hit_root.scale = Vector3.ONE * SCALE


func _head_height() -> float:
	return HEAD_HEIGHT * SCALE


func _bar_height() -> float:
	return 2.3


func _model_path() -> String:
	return MODEL_PATH


func _on_model() -> void:
	body.scale = Vector3.ONE * SCALE


func _on_reset() -> void:
	super()
	fleeing = false
	gone = false
	seen = false
	hits = 0
	_flee_left = 0.0
	_awake = 0.0
	_flee_target = Vector3.INF
	visible = true
	if is_inside_tree():
		_set_alive_collision(true)


## He holds his spot: no hunting for cover.
func _needs_new_spot(_dist: float) -> bool:
	return false


func take_hit(info: Dictionary) -> bool:
	if is_dead or gone:
		return false
	hits_taken += 1
	hits += 1
	_flash = 1.0
	damaged.emit(info)
	_damage_number(info)
	_story("host:hit")
	if info.get("zone", &"body") == &"head":
		_stagger = maxf(_stagger, headshot_flinch)
	_interrupt()
	if hits >= hits_to_run:
		_run()
	return false


func on_kicked(by: Node, dir := Vector3.ZERO) -> bool:
	if gone:
		return false
	var killed := super(by, dir)
	_run()
	return killed


func _think(delta: float) -> void:
	if gone:
		return
	if not seen and can_see_player(standing_eye()):
		seen = true
		_story("host:seen")
	if fleeing:
		_flee_tick(delta)
		return
	_awake += delta
	if _awake >= run_after or shots_fired >= shots_before_run or distance_to_player() <= flee_distance:
		_run()
		return
	super(delta)


func _run() -> void:
	if fleeing or gone:
		return
	fleeing = true
	_flee_left = flee_time
	_interrupt()
	_set_state(State.MOVE)
	_flee_target = Vector3.INF
	if flee.size() >= 3:
		# His frame: +Z is the way he faces (forward()), toward the runner.
		var frame := Basis(Vector3.UP, EnemyMath.yaw_of(forward()) + PI)
		_flee_target = global_position + frame * Vector3(float(flee[0]), float(flee[1]), float(flee[2]))
		_flee_dir = EnemyMath.horizontal(_flee_target - global_position).normalized()
	elif player != null:
		_flee_dir = EnemyMath.horizontal(global_position - player.global_position).normalized()
	if _flee_dir.length_squared() < 0.5:
		_flee_dir = -forward()
	_story("host:run")


func _flee_tick(delta: float) -> void:
	_flee_left -= delta
	duck = move_toward(duck, 0.0, 4.0 * delta)
	face_toward(global_position + _flee_dir, delta, 2.5)
	steer(_flee_dir * flee_speed, 30.0, delta)
	move_and_slide()
	var arrived := _flee_target != Vector3.INF and EnemyMath.horizontal(_flee_target - global_position).length() < 0.8
	if _flee_left <= 0.0 or arrived:
		_vanish()


## Out of the fight: off the board, and his encounter can clear.
func _vanish() -> void:
	gone = true
	is_dead = true
	fleeing = false
	telegraph = 0.0
	velocity = Vector3.ZERO
	_set_alive_collision(false)
	visible = false
	if encounter and encounter.has_method("on_enemy_killed"):
		encounter.on_enemy_killed(self)


func _story(event_name: String) -> void:
	story_event.emit(event_name)


func _animate_body(delta: float) -> void:
	if fleeing:
		var speed := EnemyMath.horizontal(velocity).length()
		body.step(speed, 1.9, delta)
		var pose := RunnerPoses.run(body.phase, clampf(speed / 9.0, 0.0, 1.1))
		body.show_pose(pose, delta, 14.0)
		hold_rifle(Vector3.FORWARD, 0.0, 0.0, rifle_fore)
		return
	super(delta)
