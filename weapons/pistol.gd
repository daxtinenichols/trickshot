class_name Pistol
extends Node3D
## Hitscan test pistol: semi-auto or full-auto, headshots, damage falloff,
## bloom, recoil, reload, aim down sights. Lives under the player's camera.
##
## Accuracy philosophy: the first shot always goes exactly where the crosshair
## is, even mid-flip at full speed. Spamming blooms; controlled fire doesn't.

signal fired(ammo: int)
## info: {collider, target, zone, damage, distance, position, normal, direction, killed, tags}
signal hit(info: Dictionary)
signal reload_started
signal reloaded
signal mode_changed(full_auto: bool)

const HITBOX_MASK := 1 | 4

@export var stats: WeaponStats

var player: Player
var camera: Camera3D
var use_device_input := true
## Scripted input (tests): set these each tick.
var trigger_held := false
var trigger_pressed := false
var aim_held := false
var reload_pressed := false
var mode_pressed := false

## Optional: returns a damage multiplier (e.g. from the combo). Called per hit.
var damage_scale := Callable()
var full_auto := false
var ammo := 0
var shots_fired := 0
var aim_blend := 0.0

var _cooldown := 0.0
var _reload_left := 0.0
var _bloom := 0.0
var _since_shot := 999.0
var _await_release := false
var _rng := RandomNumberGenerator.new()
var _model: Node3D
var _kick := 0.0
var _flash: OmniLight3D
var _audio: AudioStreamPlayer
var _hit_audio: AudioStreamPlayer
var _shot_sound: AudioStreamWAV
var _dry_sound: AudioStreamWAV
var _head_tick: AudioStreamWAV
var _body_tick: AudioStreamWAV
var _impacts: Array[Node3D] = []


func _ready() -> void:
	if stats == null:
		stats = WeaponStats.new()
	ammo = stats.magazine
	_rng.seed = 1234
	_build_model()
	_audio = AudioStreamPlayer.new()
	_audio.volume_db = -6.0
	add_child(_audio)
	_hit_audio = AudioStreamPlayer.new()
	add_child(_hit_audio)
	_shot_sound = Sfx.gunshot()
	_dry_sound = Sfx.dry_fire()
	_head_tick = Sfx.hit_tick(true)
	_body_tick = Sfx.hit_tick(false)


func setup(p: Player) -> void:
	player = p
	camera = p.camera


func is_reloading() -> bool:
	return _reload_left > 0.0


func _physics_process(delta: float) -> void:
	# Follow the player's input source, so tests and tools can script both.
	if player:
		use_device_input = player.use_device_input
	if use_device_input:
		# A click that recaptures the mouse shouldn't also fire: after the
		# mouse comes back, fire and aim wait until both are let go once.
		var live := player == null or player.is_mouse_captured()
		var firing := Input.is_action_pressed("fire") or Input.is_action_pressed("aim")
		if not live:
			_await_release = true
		elif _await_release and not firing:
			_await_release = false
		live = live and not _await_release
		trigger_held = live and Input.is_action_pressed("fire")
		trigger_pressed = live and Input.is_action_just_pressed("fire")
		aim_held = live and Input.is_action_pressed("aim")
		reload_pressed = Input.is_action_just_pressed("reload")
		mode_pressed = Input.is_action_just_pressed("fire_mode")
	tick(delta)
	if not use_device_input:
		trigger_pressed = false
		reload_pressed = false
		mode_pressed = false


func tick(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_since_shot += delta
	if _since_shot >= stats.bloom_recovery_delay:
		_bloom = maxf(_bloom - stats.bloom_recovery * delta, 0.0)
	aim_blend = move_toward(aim_blend, 1.0 if aim_held and not is_reloading() else 0.0, delta / stats.aim_time)
	if player:
		player.aim_zoom = aim_blend
		player.aim_fov = stats.aim_fov
	if mode_pressed:
		full_auto = not full_auto
		mode_changed.emit(full_auto)
	if _reload_left > 0.0:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_reload_left = 0.0
			ammo = stats.magazine
			reloaded.emit()
		return
	if reload_pressed and ammo < stats.magazine:
		_start_reload()
		return
	if ammo <= 0:
		# Empty: a fresh pull clicks and reloads; letting go reloads too.
		if trigger_pressed:
			_play(_audio, _dry_sound)
			_start_reload()
		elif not trigger_held:
			_start_reload()
		return
	var wants := trigger_held if full_auto else trigger_pressed
	if not wants or _cooldown > 0.0:
		return
	_fire()


func _start_reload() -> void:
	_reload_left = stats.reload_time
	reload_started.emit()


func current_spread() -> float:
	var speed_frac := clampf(player.horizontal_speed() / player.tuning.top_speed, 0.0, 1.0) if player else 0.0
	return lerpf(stats.hip_spread, stats.aim_spread, aim_blend) + _bloom + stats.move_spread * speed_frac


func _fire() -> void:
	ammo -= 1
	shots_fired += 1
	_since_shot = 0.0
	_cooldown = 1.0 / (stats.auto_rate if full_auto else stats.semi_max_rate)
	# First shot after the gun has settled is perfectly accurate.
	var spread := 0.0 if _bloom < 0.05 else current_spread()
	var basis := camera.global_transform.basis
	var dir := -basis.z
	if spread > 0.0:
		var angle := deg_to_rad(spread) * sqrt(_rng.randf())
		var around := _rng.randf() * TAU
		dir = (dir + (basis.x * cos(around) + basis.y * sin(around)) * tan(angle)).normalized()
	_bloom = minf(_bloom + stats.bloom_per_shot, stats.max_bloom)
	if player:
		player.add_view_kick(deg_to_rad(stats.recoil_pitch), deg_to_rad(_rng.randf_range(-stats.recoil_yaw, stats.recoil_yaw)), stats.recoil_recovery)

	var from := camera.global_position
	var to := from + dir * stats.max_range
	var q := PhysicsRayQueryParameters3D.create(from, to, HITBOX_MASK)
	if player:
		q.exclude = [player.get_rid()]
	var result := get_world_3d().direct_space_state.intersect_ray(q)
	var end := to if result.is_empty() else (result.position as Vector3)
	_effects(end, result)
	fired.emit(ammo)
	if result.is_empty():
		return
	_resolve_hit(result, from, dir)


func _resolve_hit(result: Dictionary, from: Vector3, dir: Vector3) -> void:
	var collider: Object = result.collider
	var distance := from.distance_to(result.position)
	var zone: StringName = collider.get_meta("zone") if collider and collider.has_meta("zone") else &"world"
	var falloff := 1.0
	if distance > stats.falloff_start:
		var t := clampf((distance - stats.falloff_start) / maxf(stats.falloff_end - stats.falloff_start, 0.01), 0.0, 1.0)
		falloff = lerpf(1.0, stats.min_damage_fraction, t)
	var scale := float(damage_scale.call()) if damage_scale.is_valid() else 1.0
	var dmg := stats.damage * falloff * (stats.headshot_multiplier if zone == &"head" else 1.0) * scale
	var info := {
		"collider": collider,
		"zone": zone,
		"damage": dmg,
		"distance": distance,
		"damage_scale": scale,
		"position": result.position,
		"normal": result.normal,
		"direction": dir,
		"killed": false,
		"tags": player.shot_tags() if player else [],
	}
	var target: Object = collider.get_meta("target") if collider and collider.has_meta("target") else null
	info["target"] = target
	if target and target.has_method("take_hit"):
		info.killed = target.take_hit(info)
	elif collider and collider.has_method("on_hit"):
		collider.on_hit(info)
	if target:
		_play(_hit_audio, _head_tick if zone == &"head" else _body_tick)
	hit.emit(info)


# ---------------------------------------------------------------- visuals

func _build_model() -> void:
	_model = Node3D.new()
	_model.scale = Vector3.ONE * 0.8
	add_child(_model)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.13, 0.14, 0.17)
	dark.roughness = 0.4
	dark.metallic = 0.6
	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color(1.0, 0.55, 0.2)
	_part(Vector3(0.045, 0.06, 0.24), Vector3(0, 0.035, -0.02), dark)     # slide
	_part(Vector3(0.04, 0.13, 0.06), Vector3(0, -0.05, 0.05), dark)        # grip
	_part(Vector3(0.012, 0.012, 0.03), Vector3(0, 0.072, -0.12), accent)   # front sight
	_part(Vector3(0.03, 0.01, 0.07), Vector3(0, -0.005, -0.06), accent)    # rail stripe
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.75, 0.4)
	_flash.omni_range = 4.0
	_flash.light_energy = 0.0
	_flash.position = Vector3(0, 0.04, -0.2)
	_model.add_child(_flash)


func _part(size: Vector3, pos: Vector3, mat: Material) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.position = pos
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_model.add_child(m)


func _process(delta: float) -> void:
	_kick = move_toward(_kick, 0.0, delta * 6.0)
	_flash.light_energy = move_toward(_flash.light_energy, 0.0, delta * 60.0)
	var hip := Vector3(0.17, -0.17, -0.44)
	var ads := Vector3(0.0, -0.105, -0.36)
	var pos := hip.lerp(ads, aim_blend)
	pos.z += _kick * 0.06
	var rot_x := _kick * 0.35
	if is_reloading():
		var t := 1.0 - _reload_left / stats.reload_time
		var dip := sin(t * PI)
		pos.y -= dip * 0.12
		rot_x -= dip * 0.9
	_model.position = pos
	_model.rotation = Vector3(rot_x, 0, 0)
	for i in range(_impacts.size() - 1, -1, -1):
		if not is_instance_valid(_impacts[i]):
			_impacts.remove_at(i)


func _effects(end: Vector3, result: Dictionary) -> void:
	_kick = 1.0
	_flash.light_energy = 3.0
	_play(_audio, _shot_sound)
	if not is_inside_tree():
		return
	var muzzle := _model.global_transform * Vector3(0, 0.04, -0.16)
	var tracer := MeshInstance3D.new()
	var len := muzzle.distance_to(end)
	var bm := BoxMesh.new()
	bm.size = Vector3(0.012, 0.012, len)
	tracer.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.9, 0.55, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tracer.material_override = mat
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tracer.top_level = true
	add_child(tracer)
	if len > 0.01:
		tracer.global_transform = Transform3D(Basis.looking_at((end - muzzle).normalized(), Vector3.UP if absf((end - muzzle).normalized().y) < 0.99 else Vector3.RIGHT), (muzzle + end) * 0.5)
	var tw := tracer.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.06)
	tw.tween_callback(tracer.queue_free)
	if not result.is_empty() and result.collider is StaticBody3D and not (result.collider as Object).has_meta("target"):
		_impact_mark(result.position, result.normal)


func _impact_mark(pos: Vector3, normal: Vector3) -> void:
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.035
	s.height = 0.07
	m.mesh = s
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.08, 0.08, 0.1)
	m.material_override = mat
	m.top_level = true
	add_child(m)
	m.global_position = pos + normal * 0.005
	_impacts.append(m)
	if _impacts.size() > 40:
		var oldest: Node3D = _impacts.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	var tw := m.create_tween()
	tw.tween_interval(6.0)
	tw.tween_callback(m.queue_free)


func _play(player_node: AudioStreamPlayer, stream: AudioStream) -> void:
	if player_node == null:
		return
	player_node.stream = stream
	player_node.play()
