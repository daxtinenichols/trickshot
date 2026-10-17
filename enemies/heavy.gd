extends "res://enemies/trooper.gd"
## A paramilitary heavy: heavy armor and a light machine gun. It doesn't
## take cover; it walks at you and lays down long bursts after a long,
## loud windup. Body shots barely scratch it, kicks hardly move it, and the
## helmet's glowing slit is the weak spot: headshots do full damage.


func _ready() -> void:
	super()
	max_health = 320.0
	health = max_health
	body_armor = 0.35
	has_helmet = false
	helmet = false
	burst = 6
	burst_gap = 0.08
	move_speed = 2.6
	preferred_range = 12.0
	min_range = 6.0
	max_range = 26.0
	turn_rate = 150.0
	windup = 1.05
	lock_time = 0.35
	aim_track_rate = 70.0
	aim_lead = 0.2
	recover_time = 0.9
	shots_per_reload = 3
	reload_time = 2.6
	bullet_damage = 8.0
	bullet_speed = 40.0
	kick_stagger = 0.2
	kick_shove = 2.0
	headshot_flinch = 0.25
	squad_spread = 0.0
	rifle_grip = Vector3(0, -0.05, 0.04)
	rifle_fore = Vector3(0, -0.05, -0.32)
	rifle_mag = Vector3(0, -0.1, -0.12)


func _model_path() -> String:
	return "res://enemies/models/heavy.glb"


func _on_model() -> void:
	pass


## No cover: it advances to its range and holds there.
func _pick_spot() -> void:
	_since_pick = 0.0
	_no_sight = 0.0
	cover = {}
	var to_player := EnemyMath.horizontal(player.global_position - global_position)
	var dist := to_player.length()
	var target := global_position
	if dist > preferred_range:
		target = global_position + to_player.normalized() * minf(dist - preferred_range, 4.0)
	elif dist < min_range:
		target = global_position - to_player.normalized() * 2.0
	if encounter and encounter.has_method("clamp_to_bounds"):
		target = encounter.clamp_to_bounds(target)
	move_target = Vector3(target.x, global_position.y, target.z)


func _needs_new_spot(dist: float) -> bool:
	return dist > preferred_range + 2.0 or dist < min_range or _no_sight > 2.5


func _in_cover() -> bool:
	return false
