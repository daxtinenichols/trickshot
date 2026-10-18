extends "res://enemies/raider.gd"
## A paramilitary soldier: better armed and better drilled than the Host's
## raiders, for the harder missions. (Who they are in the story is the
## story thread's call; in code they're just soldiers.)
##
## Plays like a raider (cover, ducking, the same red-then-white laser and
## lock beep before it fires) with four differences:
##   * a three-round burst per trigger pull: the lock is still your cue to
##     move, and a sideways dash still dodges all three;
##   * a helmet and body armor: body shots do much less damage, and the
##     first headshot only knocks the helmet off (and makes it flinch); the
##     next headshot kills;
##   * they lead their shots a little, so running in a straight line at
##     constant speed stops working;
##   * squads spread out: each picks cover away from where its squadmates
##     already are, so a group ends up around you instead of in a line.

## Body shots are multiplied by this (headshots aren't).
@export_range(0.0, 1.0, 0.05) var body_armor := 0.6
## The helmet stops one headshot (doing only this much of its damage).
@export var has_helmet := true
@export_range(0.0, 1.0, 0.05) var helmet_soak := 0.1

var helmet := true
@export var burst := 3
@export var burst_gap := 0.09
## How much spreading out from squadmates matters when picking cover.
@export var squad_spread := 6.0

var _burst_left := 0
var _burst_timer := 0.0
var _burst_dir := Vector3.FORWARD


func _ready() -> void:
	super()
	max_health = 70.0
	health = max_health
	move_speed = 5.0
	preferred_range = 18.0
	min_range = 9.0
	max_range = 30.0
	windup = 0.8
	lock_time = 0.3
	aim_track_rate = 85.0
	aim_lead = 0.3
	recover_time = 0.6
	shots_per_reload = 4
	reload_time = 2.0
	bullet_speed = 42.0
	bullet_damage = 10.0
	headshot_flinch = 0.4


func _model_path() -> String:
	return "res://enemies/models/soldier.glb"


func _on_model() -> void:
	body.show_part("Shield", false)
	body.show_part("LongRifle", false)


func _on_reset() -> void:
	super()
	_burst_left = 0
	_burst_timer = 0.0
	helmet = has_helmet
	if body:
		body.show_part("Helmet", helmet)


func take_hit(info: Dictionary) -> bool:
	if is_dead:
		return false
	var head: bool = info.get("zone", &"body") == &"head"
	if not head or helmet:
		info = info.duplicate()
		info.damage = float(info.get("damage", 0.0)) * (helmet_soak if head else body_armor)
	if head and helmet:
		helmet = false
		_knock_helmet_off(info)
	return super(info)


## The helmet flies off, away from the shot. Looks only.
func _knock_helmet_off(info: Dictionary) -> void:
	EnemySfx.play_at(self, &"clank", -4.0)
	if body:
		body.show_part("Helmet", false)
	if not is_inside_tree():
		return
	var m := MeshInstance3D.new()
	var dome := SphereMesh.new()
	dome.radius = 0.13
	dome.height = 0.13
	dome.is_hemisphere = true
	m.mesh = dome
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.86, 0.87, 0.88)
	m.material_override = mat
	m.top_level = true
	add_child(m)
	var start := head_position() + Vector3.UP * 0.05
	m.global_position = start
	var push := EnemyMath.horizontal(info.get("direction", -forward())).normalized() * 1.2
	var tw := m.create_tween()
	tw.set_parallel(true)
	tw.tween_method(func(t: float) -> void:
		m.global_position = start + push * t + Vector3.UP * (1.6 * t - 3.0 * t * t * 1.0), 0.0, 1.0, 0.7)
	tw.tween_property(m, "rotation", Vector3(4.0, 2.0, 1.0), 0.7)
	tw.chain().tween_property(m, "scale", Vector3.ONE * 0.01, 0.4).set_delay(1.5)
	tw.chain().tween_callback(m.queue_free)


func _interrupt() -> void:
	super()
	# A flinch or a kick ends the burst too.
	_burst_left = 0


func _fire() -> void:
	ammo -= 1
	shots_fired += 1
	_release_token()
	_burst_dir = aim_dir
	_burst_left = burst - 1
	_burst_timer = burst_gap
	_spawn_bullet(aim_dir)
	EnemySfx.play_at(self, &"soldier_shot", -3.0)


func _think(delta: float) -> void:
	super(delta)
	if _burst_left > 0 and not is_dead:
		_burst_timer -= delta
		if _burst_timer <= 0.0:
			_burst_timer = burst_gap
			_burst_left -= 1
			# Climbs a little with each round, from the locked aim.
			var n := burst - 1 - _burst_left
			var right := _burst_dir.cross(Vector3.UP).normalized()
			_spawn_bullet((_burst_dir + Vector3.UP * 0.008 * n + right * 0.006 * (1 if n % 2 == 0 else -1)).normalized())
			EnemySfx.play_at(self, &"soldier_shot", -3.0)
