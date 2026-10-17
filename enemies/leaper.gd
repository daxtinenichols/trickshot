extends "res://enemies/mutant.gd"
## A leaper: a small, quick Hollow that cuts you off, leaping ledge to ledge
## far and often. Fragile (two body shots), and winded only briefly after
## a landing, so the headshot window is short. Watch the ledges above you.


func _init() -> void:
	size_scale = 0.8


func _ready() -> void:
	super()
	max_health = 55.0
	health = max_health
	run_speed = 9.8
	chase_turn_rate = 260.0
	leap_min = 3.5
	leap_max = 13.0
	leap_windup = 0.32
	leap_time = 0.55
	leap_cooldown = 1.1
	leap_lead = 0.5
	land_recover = 0.55
	leap_damage = 16.0
	leap_hit_radius = 0.6
	swipe_damage = 10.0
	kick_shove = 10.0
	leash_radius = 22.0


func _on_model() -> void:
	super()
	body.tint(Color(1.1, 1.05, 0.95))
