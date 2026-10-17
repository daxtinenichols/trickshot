extends "res://enemies/drone.gd"
## One of the Host's camera drones: it films the run for the broadcast.
## Unarmed and fragile, it buzzes close around you with its REC light on.
## Shooting it down counts as a kill and emits feed_cut (the "Cut the Feed"
## moment the radio and scoring can react to).

signal feed_cut

var _rec: Label3D


func _ready() -> void:
	super()
	max_health = 12.0
	health = max_health
	preferred_range = 7.0
	orbit_speed = 5.0
	fly_speed = 8.0
	hover_height = 3.0
	_rec = Label3D.new()
	_rec.text = "● REC"
	_rec.font_size = 36
	_rec.outline_size = 8
	_rec.pixel_size = 0.005
	_rec.modulate = Color(1.0, 0.2, 0.15)
	_rec.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_rec.position = Vector3(0, 0.45, 0)
	_pose.add_child(_rec)


func _die(info: Dictionary) -> void:
	super(info)
	feed_cut.emit()


func _on_model() -> void:
	body.show_part("Gun", false)
	body.tint(Color(0.95, 0.9, 1.0))


## Never shoots: just keeps circling and filming.
func _think(delta: float) -> void:
	state_time += delta
	_orbit_flip -= delta
	if _orbit_flip <= 0.0:
		_orbit = -_orbit
		_orbit_flip = _rng.randf_range(2.0, 4.0)
	face_toward(player.global_position, delta)
	_fly_to(_circle_point(), delta)
	move_and_slide()


func _animate(delta: float) -> void:
	super(delta)
	if _rec:
		# Blinks once a second.
		_rec.visible = not is_dead and fmod(Time.get_ticks_msec() / 1000.0, 1.0) < 0.6
