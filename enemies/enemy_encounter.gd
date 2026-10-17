class_name EnemyEncounter
extends Node3D
## A group of enemies in an area. They wait until you step into the area,
## then fight; leave for a few seconds, or go down, and everything resets.
## Clear it and it restarts after a short break, so you can keep practicing.
##
## Also hands out cover spots to raiders (one raider per spot) and limits
## how many raiders aim at you at once, so shots stay readable.
##
## Game logic only, ticked in physics. Order matters for determinism:
## enemies tick in the order they were added.

signal started
signal cleared
signal reset_done
## A raider bullet passed close without hitting (distance from your body, m).
signal near_miss(distance: float)
signal player_hurt(enemy: Node, amount: float, kind: StringName)
## Gunshots woke sleeping enemies ("shots draw more Hollows").
signal drew_enemies(count: int)

enum Phase { WAITING, ACTIVE, CLEARED }

## Enemy types are scripts in enemies/ named after the type: raider,
## mutant, trooper, shield, marksman, heavy, drone, gun_drone, camera_drone,
## spotter_drone, brute, leaper (enemies/<type>.gd, loaded by path).
const TYPE_DIR := "res://enemies/"

## How many raiders may be aiming at you at the same time.
@export var max_aiming := 2
## Seconds outside the area before the fight resets.
@export var leave_reset_time := 4.0
## Seconds after clearing before it restarts.
@export var restart_time := 6.0
## Listen for the player's shots: each one wakes the sleepers (enemies with
## `sleeper` set) within hearing_radius of you.
@export var hear_shots := false
@export var hearing_radius := 30.0
## A sleeper also wakes when you come this close (m).
@export var wake_distance := 5.0

var player: Player
var player_health: PlayerHealth
## The fight starts when you step inside (world space).
var bounds := AABB()
## Where you come back if you go down in here (outside the bounds).
var entry := Transform3D.IDENTITY
## {pos, protect, index}: protect points from the spot toward the cover, so
## the spot is safe from a player on that side.
var covers: Array[Dictionary] = []
var enemies: Array[Enemy] = []
var phase := Phase.WAITING
var kills := 0
var clears := 0

var _aiming: Array[Node] = []
## Seconds left on a spotter drone's mark (gunners lock on faster).
var _spotted := 0.0
var _claims := {}
var _outside := 0.0
var _phase_time := 0.0


func setup(p: Player) -> void:
	player = p
	player_health = PlayerHealth.ensure(p)
	if not player_health.died.is_connected(_on_player_died):
		player_health.died.connect(_on_player_died)
	var gun: Node = p.get("weapon")
	if gun and gun.has_signal("fired") and not gun.fired.is_connected(_on_player_fired):
		gun.fired.connect(_on_player_fired)


func _exit_tree() -> void:
	if player_health and is_instance_valid(player_health) and player_health.died.is_connected(_on_player_died):
		player_health.died.disconnect(_on_player_died)
	var gun: Node = player.get("weapon") if player and is_instance_valid(player) else null
	if gun and gun.has_signal("fired") and gun.fired.is_connected(_on_player_fired):
		gun.fired.disconnect(_on_player_fired)


func add_enemy(e: Enemy, at: Transform3D) -> Enemy:
	e.encounter = self
	e.seed_value = enemies.size() + 1
	e.transform = at
	add_child(e)
	e.set_home(e.global_transform)
	e.reset_to_home()
	enemies.append(e)
	return e


## The script for an enemy type ("trooper", "gun_drone"...). Plural list
## names ("raiders", "drones") work too. null if there's no such enemy.
static func script_for(type: String) -> Script:
	for t: String in [type, type.trim_suffix("s")]:
		var path := TYPE_DIR + t + ".gd"
		if t != "" and not t.begins_with("enemy") and ResourceLoader.exists(path):
			return load(path)
	return null


## Adds an enemy of a type from its spec: "wake" delays it, and any other
## key that names one of its settings (leash_radius, hover_height,
## preferred_range...) sets it. Returns null for an unknown type.
func add_from_spec(type: String, spec: Dictionary, at: Transform3D) -> Enemy:
	var script := script_for(type)
	var made: Object = script.new() if script and script.can_instantiate() else null
	var e := made as Enemy
	if e == null:
		if made is Node:
			(made as Node).free()
		push_warning("unknown enemy type: %s" % type)
		return null
	e.wake_delay = spec.get("wake", 0.0)
	for k: String in spec:
		if k in ["at", "yaw", "wake", "type"]:
			continue
		if k in e:
			e.set(k, spec[k])
	return add_enemy(e, at)


func add_cover(pos: Vector3, protect: Vector3) -> void:
	covers.append({"pos": pos, "protect": EnemyMath.horizontal(protect).normalized(), "index": covers.size()})


## Cover spots along both faces of a low wall (length along the wall's
## local X, rotated by yaw), one every `spacing` meters.
func add_cover_wall(center: Vector3, length: float, thickness: float, yaw := 0.0, spacing := 2.2) -> void:
	var b := Basis(Vector3.UP, yaw)
	var along := b.x
	var out := b.z
	var count := maxi(1, floori((length - 0.6) / spacing) + 1)
	var span := spacing * (count - 1)
	for i in count:
		var x := -span * 0.5 + spacing * i
		for side: float in [-1.0, 1.0]:
			var pos := center + along * x + out * side * (thickness * 0.5 + 0.55)
			add_cover(Vector3(pos.x, center.y, pos.z), -out * side)


func alive_count() -> int:
	var n := 0
	for e in enemies:
		# Sleepers nobody woke don't hold up a clear.
		if not e.is_dead and not (e.sleeper and not e.active):
			n += 1
	return n


func player_inside() -> bool:
	return player != null and bounds.has_point(player.global_position)


# ---------------------------------------------------------------- raider services

## The best free cover spot for a raider: safe from where you are, at the
## raider's preferred range, and not far to walk. {} if none fits.
func find_cover(r: Node) -> Dictionary:
	if player == null:
		return {}
	var best := {}
	var best_score := INF
	var mine: int = _claims.get(r.get_instance_id(), -1)
	for c in covers:
		if c.index != mine and c.index in _claims.values():
			continue
		var to_player := EnemyMath.horizontal(player.global_position - c.pos)
		var d := to_player.length()
		if d < r.min_range + 1.0 or d > r.max_range:
			continue
		if to_player.normalized().dot(c.protect) < 0.5:
			continue
		var walk := EnemyMath.horizontal(c.pos - r.global_position).length()
		var score := absf(d - r.preferred_range) + walk * 0.6 + _crowding(r, c.pos)
		if score < best_score:
			best_score = score
			best = c
	return best


## Squads (enemies with a squad_spread) avoid cover in the same direction
## from you as a squadmate, so they spread out around you.
func _crowding(r: Node, pos: Vector3) -> float:
	var spread: float = r.get("squad_spread") if "squad_spread" in r else 0.0
	if spread <= 0.0:
		return 0.0
	var dir := EnemyMath.horizontal(pos - player.global_position).normalized()
	var penalty := 0.0
	for e in enemies:
		if e == r or e.is_dead or not ("squad_spread" in e):
			continue
		var other := EnemyMath.horizontal(e.global_position - player.global_position).normalized()
		var angle := rad_to_deg(dir.angle_to(other))
		if angle < 45.0:
			penalty += spread * (1.0 - angle / 45.0)
	return penalty


func claim_cover(r: Node, c: Dictionary) -> void:
	if c.is_empty():
		_claims.erase(r.get_instance_id())
	else:
		_claims[r.get_instance_id()] = c.index


func request_aim(r: Node) -> bool:
	if r in _aiming:
		return true
	if _aiming.size() >= max_aiming:
		return false
	_aiming.append(r)
	return true


## A spotter drone sees you: marks you for a moment.
func spot(seconds := 0.25) -> void:
	_spotted = maxf(_spotted, seconds)


func is_spotted() -> bool:
	return _spotted > 0.0


func release_aim(r: Node) -> void:
	_aiming.erase(r)


func aiming_count() -> int:
	return _aiming.size()


func clamp_to_bounds(p: Vector3) -> Vector3:
	var lo := bounds.position + Vector3(1.5, 0, 1.5)
	var hi := bounds.end - Vector3(1.5, 0, 1.5)
	return Vector3(clampf(p.x, lo.x, hi.x), p.y, clampf(p.z, lo.z, hi.z))


func on_bullet(b: EnemyProjectile) -> void:
	b.near_miss.connect(func(d: float) -> void: near_miss.emit(d))


func on_player_hurt(e: Node, amount: float, kind: StringName) -> void:
	player_hurt.emit(e, amount, kind)


func on_enemy_killed(e: Enemy) -> void:
	kills += 1
	release_aim(e)
	_claims.erase(e.get_instance_id())
	if phase == Phase.ACTIVE and alive_count() == 0:
		phase = Phase.CLEARED
		_phase_time = 0.0
		clears += 1
		cleared.emit()


# ---------------------------------------------------------------- flow

func start() -> void:
	phase = Phase.ACTIVE
	_phase_time = 0.0
	_outside = 0.0
	if player_health:
		player_health.respawn_point = entry
	for e in enemies:
		if not e.sleeper:
			e.activate(player)
	started.emit()


## Wakes sleepers within `radius` of a point. Returns how many woke.
func wake_sleepers(at: Vector3, radius: float) -> int:
	var n := 0
	for e in enemies:
		if e.sleeper and not e.active and not e.is_dead and e.global_position.distance_to(at) <= radius:
			e.wake_delay = 0.0
			e.activate(player)
			n += 1
	return n


func _on_player_fired(_ammo: int) -> void:
	if hear_shots and phase == Phase.ACTIVE and player:
		var n := wake_sleepers(player.global_position, hearing_radius)
		if n > 0:
			drew_enemies.emit(n)


func reset() -> void:
	for c in get_children():
		if c is EnemyProjectile:
			c.queue_free()
			(c as EnemyProjectile).done = true
	for e in enemies:
		e.reset_to_home()
	_aiming.clear()
	_claims.clear()
	_spotted = 0.0
	kills = 0
	phase = Phase.WAITING
	_phase_time = 0.0
	_outside = 0.0
	reset_done.emit()


func _on_player_died() -> void:
	reset()


func _physics_process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	if player == null:
		return
	_phase_time += delta
	_spotted = maxf(_spotted - delta, 0.0)
	match phase:
		Phase.WAITING:
			if player_inside():
				start()
		Phase.ACTIVE:
			wake_sleepers(player.global_position, wake_distance)
			_outside = 0.0 if player_inside() else _outside + delta
			if _outside >= leave_reset_time:
				if player_health:
					player_health.respawn_point = null
				reset()
		Phase.CLEARED:
			if _phase_time >= restart_time:
				reset()
