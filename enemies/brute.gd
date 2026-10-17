extends "res://enemies/mutant.gd"
## A brute: a huge Hollow, armored in front (bone plates) and soft behind.
## Shots from the front barely hurt; shots in the back hurt extra, so the
## fight is about getting behind it.
##
## No leaps: it roars (a long, glowing windup that lines up on you, then
## locks), then charges in a straight line it can't steer. Sidestep and it thunders past, and if it slams into
## a wall it's dazed, back turned, for a moment. Up close it swipes hard. Too
## heavy to kick around. Like every Hollow it guards its patch.

## Damage multipliers by where the shot comes from.
@export var front_armor := 0.2
@export var back_weakness := 1.6
@export_group("Charge")
@export var charge_min := 5.0
@export var charge_max := 15.0
@export var charge_windup := 0.8
## The end of the windup where its line is locked (s).
@export var charge_lock := 0.35
@export var charge_speed := 13.0
@export var charge_time := 1.0
@export var charge_cooldown := 3.5
@export var charge_damage := 38.0
@export var dazed_time := 1.6
@export var charge_recover := 0.7

var charges := 0
var _charge_ready := 0.0
var _charge_dir := Vector3.FORWARD
var _charge_hit := false


func _init() -> void:
	size_scale = 1.4


func _ready() -> void:
	super()
	max_health = 260.0
	health = max_health
	run_speed = 6.5
	chase_turn_rate = 110.0
	turn_rate = 200.0
	leap_min = INF
	swipe_damage = 28.0
	swipe_windup = 0.45
	swipe_range = 2.4
	swipe_reach = 3.0
	kick_stagger = 0.15
	kick_shove = 1.5
	headshot_flinch = 0.2
	leash_radius = 20.0


func _on_model() -> void:
	super()
	body.show_part("Armor", true)
	body.tint(Color(0.78, 0.72, 0.7))


func _on_reset() -> void:
	super()
	_charge_ready = 0.4
	_charge_hit = false


## Hit from the front (the shot travels against its facing) or behind.
func take_hit(info: Dictionary) -> bool:
	if is_dead:
		return false
	var dir: Vector3 = info.get("direction", Vector3.ZERO)
	var facing := EnemyMath.horizontal(dir).normalized().dot(forward())
	info = info.duplicate()
	if facing < -0.3:
		info.damage = float(info.get("damage", 0.0)) * front_armor
		EnemySfx.play_at(self, &"clank", -6.0)
	elif facing > 0.3:
		info.damage = float(info.get("damage", 0.0)) * back_weakness
	return super(info)


func is_dazed() -> bool:
	return state == State.DAZED and not is_dead


func _interrupt() -> void:
	# Too heavy for a kick or a headshot to stop a charge.
	if state not in [State.CHARGE_WINDUP, State.CHARGE]:
		super()


func _think(delta: float) -> void:
	_charge_ready = maxf(_charge_ready - delta, 0.0)
	match state:
		State.CHARGE_WINDUP:
			state_time += delta
			steer(Vector3.ZERO, 30.0, delta)
			# It lines up on you, then locks its line for the last moment:
			# step aside then.
			if state_time < charge_windup - charge_lock:
				face_toward(player.global_position, delta, 0.6)
			telegraph = clampf(state_time / charge_windup, 0.0, 1.0)
			if state_time >= charge_windup:
				_charge_dir = forward()
				_charge_hit = false
				charges += 1
				_set_state(State.CHARGE)
			move_and_slide()
			return
		State.CHARGE:
			state_time += delta
			velocity = Vector3(_charge_dir.x * charge_speed, velocity.y, _charge_dir.z * charge_speed)
			if not _charge_hit:
				var axis := EnemyMath.player_axis(player)
				var center := global_position + Vector3.UP * 0.9 * size_scale
				if EnemyMath.point_segment_distance(center, axis[0], axis[1]) <= 0.7 * size_scale + Player.RADIUS:
					_charge_hit = true
					hits_landed += 1
					_chase_time = 0.0
					hurt_player(charge_damage, &"charge")
			move_and_slide()
			var slammed := is_on_wall() and state_time > 0.1
			if slammed:
				velocity = Vector3(0, velocity.y, 0)
				EnemySfx.play_at(self, &"crash", -4.0)
				_set_state(State.DAZED)
			elif state_time >= charge_time:
				_set_state(State.LAND)
			return
		State.DAZED:
			state_time += delta
			steer(Vector3.ZERO, 20.0, delta)
			if state_time >= dazed_time:
				_set_state(State.CHASE)
			move_and_slide()
			return
	super(delta)
	# From a chase, wind up a charge when there's room to run at you.
	if state == State.CHASE and _charge_ready <= 0.0 and is_on_floor():
		var to_player := EnemyMath.horizontal(player.global_position - global_position)
		var dist := to_player.length()
		var ahead := forward().dot(to_player.normalized()) > 0.8
		if dist >= charge_min and dist <= charge_max and ahead and _player_in_leash() and can_see_player():
			_charge_ready = charge_cooldown
			_set_state(State.CHARGE_WINDUP)
			EnemySfx.play_at(self, &"growl", 2.0)


func _set_state(s: State) -> void:
	super(s)
	if s == State.CHARGE_WINDUP:
		telegraph = 0.0
	if s == State.LAND:
		state_time = land_recover - charge_recover


func _animate_body(delta: float) -> void:
	match state:
		State.CHARGE_WINDUP:
			body.step(0.0, 2.2, delta)
			body.show_pose(Poses.add(Poses.coil(telegraph * 0.6), {"Neck": Vector3(-20, 0, 0) * telegraph,
				"LeftUpperArm": Vector3(-30, 0, 30) * telegraph, "RightUpperArm": Vector3(-30, 0, -30) * telegraph}), delta)
		State.CHARGE:
			body.step(charge_speed, 2.6, delta)
			body.show_pose(Poses.add(Poses.lope(body.phase, 1.2), {"Spine": Vector3(16, 0, 0), "Neck": Vector3(-10, 0, 0)}), delta, 20.0)
		State.DAZED:
			body.show_pose(Poses.add(Poses.winded(sin(state_time * 4.0)), {"Head": Vector3(10, 20 * sin(state_time * 3.0), 0)}), delta)
		_:
			super(delta)
