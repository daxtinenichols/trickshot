extends "res://enemies/raider.gd"
## A Static hunter: a raider who runs like you do. It never settles into
## cover; it keeps moving to your side (wherever you're not looking), hops
## over low walls on the way, and snaps off quick shots with a short
## windup when it stops. Light: it can't take much. Keep turning and keep
## moving, and catch it when it stops to shoot.

## How high it hops over things in its way (m/s up).
@export var hop_speed := 7.0
## How often it picks a new flanking spot (s).
@export var reposition := 2.4

var hops := 0
var _side := 1.0


func _ready() -> void:
	super()
	max_health = 80.0
	health = max_health
	move_speed = 7.5
	accel = 30.0
	preferred_range = 11.0
	min_range = 6.0
	max_range = 24.0
	windup = 0.7
	lock_time = 0.25
	aim_track_rate = 95.0
	aim_lead = 0.25
	recover_time = 0.45
	between_shots = 0.9
	shots_per_reload = 4
	reload_time = 1.6
	turn_rate = 540.0


func _model_path() -> String:
	return "res://enemies/models/hunter.glb"


func _on_model() -> void:
	pass


func _on_reset() -> void:
	super()
	_side = 1.0 if seed_value % 2 == 1 else -1.0
	hops = 0


func _in_cover() -> bool:
	return false


func _needs_new_spot(dist: float) -> bool:
	return dist < min_range or _no_sight > 1.5 or _since_pick > reposition or dist > max_range


## Picks a spot off to your side, where you're not looking.
func _pick_spot() -> void:
	_since_pick = 0.0
	_no_sight = 0.0
	cover = {}
	var look := EnemyMath.horizontal(player.look_direction() if player.has_method("look_direction") else -player.global_basis.z)
	if look.length_squared() < 0.01:
		look = Vector3.FORWARD
	look = look.normalized()
	# Swap sides each time, so it crosses your view: a moving target.
	_side = -_side
	var side := look.cross(Vector3.UP) * _side
	var target := player.global_position + (side * 0.9 + look * 0.45).normalized() * preferred_range
	if encounter and encounter.has_method("clamp_to_bounds"):
		target = encounter.clamp_to_bounds(target)
	move_target = Vector3(target.x, global_position.y, target.z)


func _think(delta: float) -> void:
	super(delta)
	# Parkour: hop whatever is in the way.
	if state == State.MOVE and is_on_floor() and is_on_wall():
		velocity.y = hop_speed
		hops += 1


func _lower_pose(base: Dictionary) -> Dictionary:
	return Poses.blend(base, Poses.hop(), 0.0 if is_on_floor() else 1.0)
