extends "res://enemies/shield.gd"
## A Static bruiser: a big raider behind a scrap shield (a car door and
## sheet metal) with a sawn-off scattergun. Like the Ward's shield bearers
## it walks you down with the shield up, so get round it or hit it where
## the shield isn't (its head shows over the top). Up close the scattergun
## throws a fan of three slugs: a sideways step still clears them. A kick
## knocks the shield aside.

## Angle between the slugs in the fan (degrees).
@export var spread := 7.0


func _ready() -> void:
	super()
	# A Static raider, though it fights like the Ward's shield bearers.
	faction = "static"
	max_health = 150.0
	health = max_health
	has_helmet = false
	helmet = false
	body_armor = 0.85
	move_speed = 3.6
	preferred_range = 6.0
	min_range = 3.0
	max_range = 16.0
	windup = 0.85
	lock_time = 0.3
	bullet_damage = 11.0
	bullet_speed = 34.0
	aim_lead = 0.1
	shots_per_reload = 2
	reload_time = 2.2


func _hit_profile() -> Dictionary:
	return HitRig.BULKY


func _model_path() -> String:
	return "res://enemies/models/raider.glb"


func _on_model() -> void:
	body.show_part("ScrapShield", true)
	body.tint(Color(1.05, 0.95, 0.9))


func _shield_part() -> String:
	return "ScrapShield"


func _fire() -> void:
	ammo -= 1
	shots_fired += 1
	_release_token()
	var right := aim_dir.cross(Vector3.UP).normalized()
	for i in [-1, 0, 1]:
		_spawn_bullet(aim_dir.rotated(Vector3.UP, deg_to_rad(spread) * i) if right != Vector3.ZERO else aim_dir)
	EnemySfx.play_at(self, &"raider_shot", 1.0)
