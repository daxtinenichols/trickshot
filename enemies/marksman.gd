extends "res://enemies/trooper.gd"
## A paramilitary marksman: a scoped rifle from far away. One heavy shot at
## a time, with a laser like a raider spotter's but a quicker aim: the
## laser crossing the level is the warning, so keep moving and break its
## line of sight, or win the duel with a headshot first. Lighter body
## armor than a trooper, the same helmet.


func _ready() -> void:
	super()
	max_health = 70.0
	health = max_health
	body_armor = 0.8
	burst = 1
	preferred_range = 32.0
	min_range = 14.0
	max_range = 55.0
	windup = 0.75
	lock_time = 0.3
	aim_track_rate = 110.0
	aim_lead = 0.15
	between_shots = 1.6
	shots_per_reload = 3
	reload_time = 2.4
	bullet_speed = 70.0
	bullet_damage = 30.0
	rifle_part = "LongRifle"
	rifle_grip = Vector3(0, -0.04, 0.03)
	rifle_fore = Vector3(0, -0.02, -0.38)


func _on_model() -> void:
	body.show_part("Shield", false)
	body.show_part("Rifle", false)
