class_name Raider
extends Enemy
## A raider with a rifle. Keeps its distance, ducks behind cover, and pops
## up to shoot.
##
## Every shot is telegraphed: a red laser tracks you while the raider aims,
## then turns white and stops tracking (with a beep) just before it fires.
## The bullet is a bright slug that takes a moment to arrive, so moving
## sideways after the lock is a real dodge. Standing still, or running
## straight at a raider, is how you get hit.
##
## A raider is open to headshots while it stands to aim and while it
## recovers after a shot. A headshot that doesn't kill makes it flinch and
## cancels the shot; so does a kick.

enum State { HOLD, MOVE, AIM, RECOVER, RELOAD }

const Voices := preload("res://audio/voice_lines.gd")
## What it shouts when it tags you (audio/voices/taunts.json).
const Taunts := preload("res://audio/taunts.gd")

@export_group("Movement")
@export var move_speed := 4.5
@export var accel := 18.0
## Where it likes to fight from (m)...
@export var preferred_range := 16.0
## ...backing off if you get closer than this...
@export var min_range := 8.0
## ...and closing in past this.
@export var max_range := 28.0

@export_group("Shooting")
## Aiming time before a shot (s). The laser shows the whole time.
@export var windup := 0.9
## The last part of the windup: aim locked, laser white, beep. Dodge now.
@export var lock_time := 0.3
## How fast the aim follows you before the lock (degrees per second).
## Below your sideways speed at range, so moving shakes the aim.
@export var aim_track_rate := 75.0
## Standing exposed after a shot (s): the punish window.
@export var recover_time := 0.55
@export var shots_per_reload := 3
@export var reload_time := 2.2
## Wait between shots in one magazine (s).
@export var between_shots := 0.7
@export var bullet_speed := 38.0
@export var bullet_damage := 18.0
## 0 aims where you are, 1 aims where you'll be (by bullet flight time).
@export_range(0.0, 1.0, 0.05) var aim_lead := 0.0

const HEAD_RADIUS := 0.15
const HEAD_HEIGHT := 1.62
const BODY_SIZE := Vector3(0.55, 1.3, 0.34)
## How far ducking lowers the body (head center 1.62 -> 1.0 m: below a
## 1.2 m cover wall, with the top of the head just showing).
const DUCK_DROP := 0.62
## The hit zones duck by kneeling: hips drop this far and the torso hunches.
const DUCK_HIP_DROP := 0.4
const DUCK_LEAN := 0.3
const MUZZLE := Vector3(0.22, 1.42, -0.55)
## Windup multiplier while a spotter drone has you marked.
const SPOTTED_WINDUP := 0.6

var state := State.HOLD
var state_time := 0.0
var ammo := 3
var shots_fired := 0
## Where the rifle points (world, unit).
var aim_dir := Vector3.FORWARD
## The cover spot it holds: {pos, protect} (empty: open ground).
var cover := {}
var move_target := Vector3.ZERO

var _shot_timer := 0.0
var _rethink := 0.0
var _no_sight := 0.0
var _since_pick := 999.0
var _has_token := false
var _strafe := 1.0
var _laser: MeshInstance3D
var _laser_mat: StandardMaterial3D
## Whose taunts it shouts: "static" (the Host's raiders) or "ward".
var faction := "static"
var _taunt: Label3D
var _taunt_time := 0.0


func _ready() -> void:
	max_health = 100.0
	super()
	_on_reset()


func _head_height() -> float:
	return HEAD_HEIGHT


func _bar_height() -> float:
	return 2.1


func _build() -> void:
	_build_hit_rig(_hit_profile())
	_build_laser()


## Body proportions for the hit zones (HitRig profiles).
func _hit_profile() -> Dictionary:
	return HitRig.HUMAN


## The hit zones' pose from the state: ducking behind cover kneels and
## hunches, legs step with the speed, hands on the rifle where it points.
func _hit_pose(delta: float) -> Dictionary:
	var speed := EnemyMath.horizontal(velocity).length()
	var aim_w := 1.0 if state in [State.AIM, State.RECOVER] else 0.0
	var reload_w := 1.0 if state == State.RELOAD else 0.0
	var local_aim := Basis(Vector3.UP, yaw).inverse() * aim_dir
	return {"speed": speed, "delta": delta, "run": speed / maxf(move_speed, 0.1),
		"crouch": DUCK_HIP_DROP * duck, "lean": DUCK_LEAN * duck,
		"hands": _rifle_hands(local_aim, aim_w, reload_w)}


## Where the hands hold the rifle (enemy-local), from the same placement
## the model uses, with the chest where the hit zones put it.
func _rifle_hands(local_aim: Vector3, aim_w: float, reload_w: float) -> Array:
	var chest: Vector3 = hit_rig.head_local + Vector3(0, -0.3, 0.04) if hit_rig else Vector3(0, 1.33, -0.03)
	var xf := Poses.rifle_xf(chest, local_aim, aim_w, reload_w)
	return [xf * rifle_fore.lerp(rifle_mag, reload_w), xf * rifle_grip]


func _build_placeholder() -> void:
	var cloth := _material(Color(0.62, 0.2, 0.16))
	var dark := _material(Color(0.18, 0.16, 0.15))
	var head := _material(Color(1.0, 0.82, 0.28))
	# Legs, torso, shoulders, head, a scrap mask stripe and the rifle.
	_mesh_box(Vector3(0.2, 0.75, 0.22), Vector3(-0.13, 0.38, 0), dark)
	_mesh_box(Vector3(0.2, 0.75, 0.22), Vector3(0.13, 0.38, 0), dark)
	_mesh_box(Vector3(0.52, 0.7, 0.3), Vector3(0, 1.1, 0), cloth)
	_mesh_box(Vector3(0.66, 0.14, 0.32), Vector3(0, 1.42, 0), cloth)
	_mesh_sphere(HEAD_RADIUS, Vector3(0, HEAD_HEIGHT, 0), head)
	_mesh_box(Vector3(0.34, 0.07, 0.05), Vector3(0, HEAD_HEIGHT + 0.02, -0.2), dark)
	_mesh_box(Vector3(0.08, 0.1, 0.8), MUZZLE + Vector3(0, 0, 0.3), dark)


func _build_laser() -> void:
	_laser = MeshInstance3D.new()
	var lb := BoxMesh.new()
	lb.size = Vector3(1, 1, 1)
	_laser.mesh = lb
	_laser_mat = StandardMaterial3D.new()
	_laser_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_laser_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_laser_mat.albedo_color = Color(1, 0.1, 0.05, 0.0)
	_laser.material_override = _laser_mat
	_laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_laser.top_level = true
	_laser.visible = false
	add_child(_laser)
	_taunt = Label3D.new()
	_taunt.font_size = 40
	_taunt.outline_size = 10
	_taunt.pixel_size = 0.006
	_taunt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_taunt.modulate = Color(1.0, 0.75, 0.35)
	_taunt.position = Vector3(0, 2.45, 0)
	_taunt.visible = false
	_visual.add_child(_taunt)


func _on_reset() -> void:
	state = State.HOLD
	state_time = 0.0
	ammo = shots_per_reload
	cover = {}
	_release_token()
	_no_sight = 0.0
	_since_pick = 999.0
	_rethink = 0.0
	_strafe = 1.0 if seed_value % 2 == 0 else -1.0
	# Stagger the first shots so a group never fires in unison.
	_shot_timer = _rng.randf_range(0.7, 1.5)
	if _hit_root:
		_hit_root.position.y = 0.0


func _interrupt() -> void:
	if state == State.AIM:
		_set_state(State.HOLD)
		_shot_timer = maxf(_shot_timer, 0.5)
	_release_token()


func is_aiming() -> bool:
	return state == State.AIM and not is_dead


func is_locked() -> bool:
	return is_aiming() and state_time >= aim_time() - lock_time


## The windup it's using right now: shorter while a spotter drone marks you.
func aim_time() -> float:
	return maxf(windup * (SPOTTED_WINDUP if _spotted() else 1.0), lock_time + 0.2)


func _spotted() -> bool:
	return encounter != null and encounter.has_method("is_spotted") and encounter.is_spotted()


func muzzle_position() -> Vector3:
	return global_position + Basis(Vector3.UP, yaw) * (MUZZLE + Vector3.DOWN * DUCK_DROP * duck)


## The eye it would shoot from once standing (it checks sight before
## popping up from cover).
func standing_eye() -> Vector3:
	return global_position + Vector3.UP * HEAD_HEIGHT


# ---------------------------------------------------------------- behaviour

func _think(delta: float) -> void:
	state_time += delta
	var to_player := EnemyMath.horizontal(player.global_position - global_position)
	var dist := to_player.length()
	# Marked by a spotter drone: it knows where you are, even behind cover.
	var sees := can_see_player(standing_eye()) or _spotted()
	_no_sight = 0.0 if sees else _no_sight + delta
	_since_pick += delta
	match state:
		State.HOLD:
			_duck_toward(1.0 if _in_cover() else 0.0, delta)
			face_toward(player.global_position, delta)
			steer(Vector3.ZERO, accel, delta)
			_rethink -= delta
			if _rethink <= 0.0:
				_rethink = 0.5
				if _needs_new_spot(dist):
					_pick_spot()
					_set_state(State.MOVE)
			_shot_timer -= delta
			if state == State.HOLD and _shot_timer <= 0.0 and sees and dist <= max_range * 1.4 and _take_token():
				_set_state(State.AIM)
				aim_dir = (_aim_point() - muzzle_position()).normalized()
		State.MOVE:
			_duck_toward(0.0, delta)
			face_toward(player.global_position, delta)
			var to := EnemyMath.horizontal(move_target - global_position)
			if to.length() < 0.35 or state_time > 4.0:
				_set_state(State.HOLD)
				_shot_timer = maxf(_shot_timer, 0.35)
			else:
				steer(to.normalized() * minf(move_speed, to.length() * 4.0), accel, delta)
		State.AIM:
			_duck_toward(0.0, delta, 6.0)
			face_toward(player.global_position, delta)
			steer(Vector3.ZERO, accel, delta)
			var wind := aim_time()
			telegraph = clampf(state_time / wind, 0.0, 1.0)
			if state_time < wind - lock_time:
				var want := (_aim_point() - muzzle_position()).normalized()
				aim_dir = EnemyMath.turn_dir(aim_dir, want, deg_to_rad(aim_track_rate) * delta)
			elif state_time - delta < wind - lock_time:
				EnemySfx.play_at(self, &"lock", -4.0)
			if state_time >= wind:
				_fire()
				_set_state(State.RECOVER)
		State.RECOVER:
			_duck_toward(0.0, delta)
			face_toward(player.global_position, delta)
			steer(Vector3.ZERO, accel, delta)
			if state_time >= recover_time:
				if ammo <= 0:
					_set_state(State.RELOAD)
				else:
					_set_state(State.HOLD)
					_shot_timer = between_shots
		State.RELOAD:
			_duck_toward(1.0 if _in_cover() else 0.0, delta)
			face_toward(player.global_position, delta)
			steer(Vector3.ZERO, accel, delta)
			if state_time >= reload_time:
				ammo = shots_per_reload
				_set_state(State.HOLD)
				_shot_timer = 0.35
				_rethink = 0.0
	move_and_slide()


func _set_state(s: State) -> void:
	if state == State.AIM and s != State.AIM:
		_release_token()
	state = s
	state_time = 0.0
	if s != State.AIM:
		telegraph = 0.0


func _duck_toward(target: float, delta: float, rate := 3.5) -> void:
	duck = move_toward(duck, target, rate * delta)


## Where the raider aims: your chest, plus some lead if it has any.
func _aim_point() -> Vector3:
	var chest := EnemyMath.player_chest(player)
	if aim_lead <= 0.0:
		return chest
	var flight := muzzle_position().distance_to(chest) / bullet_speed
	return chest + player.velocity * flight * aim_lead


func _fire() -> void:
	ammo -= 1
	shots_fired += 1
	_release_token()
	_spawn_bullet(aim_dir)
	EnemySfx.play_at(self, &"raider_shot", -2.0)


func _spawn_bullet(dir: Vector3) -> void:
	var b := EnemyProjectile.new()
	b.velocity = dir * bullet_speed
	b.damage = bullet_damage
	b.player = player
	b.player_health = player_health
	b.shooter = self
	b.hit_player.connect(_on_bullet_hit)
	if encounter and encounter.has_method("on_bullet"):
		encounter.on_bullet(b)
	var parent: Node = encounter if encounter else get_parent()
	parent.add_child(b)
	b.global_position = muzzle_position()


func _on_bullet_hit(amount: float) -> void:
	if encounter and encounter.has_method("on_player_hurt"):
		encounter.on_player_hurt(self, amount, &"bullet")
	var taunt := Taunts.next(faction, seed_value)
	if taunt.is_empty():
		return
	_taunt.text = taunt.line
	_taunt_time = 1.6
	var audio := get_node_or_null(^"/root/GameAudio")
	if audio != null:
		audio.play_voice_on(self, Voices.stream_for(taunt.who, taunt.line))


# ---------------------------------------------------------------- positioning

func _in_cover() -> bool:
	return not cover.is_empty() and EnemyMath.horizontal(cover.pos - global_position).length() < 0.6 and _cover_protects(cover)


func _cover_protects(c: Dictionary) -> bool:
	if c.is_empty() or player == null:
		return false
	var to_player := EnemyMath.horizontal(player.global_position - c.pos).normalized()
	return to_player.dot(c.protect) > 0.35


func _needs_new_spot(dist: float) -> bool:
	if dist < min_range:
		return true
	if _no_sight > 2.5:
		return true
	if not cover.is_empty():
		return not _cover_protects(cover) or dist > max_range + 6.0
	# In the open with an encounter around: look for cover now and then.
	return dist > max_range or (encounter != null and _since_pick > 3.0)


func _pick_spot() -> void:
	_since_pick = 0.0
	_no_sight = 0.0
	var c := {}
	if encounter and encounter.has_method("find_cover"):
		c = encounter.find_cover(self)
	if not c.is_empty():
		if encounter.has_method("claim_cover"):
			encounter.claim_cover(self, c)
		cover = c
		move_target = c.pos
		return
	if encounter and encounter.has_method("claim_cover"):
		encounter.claim_cover(self, {})
	cover = {}
	# Open ground: back off (or close in) to the preferred range, sidestepping.
	var away := EnemyMath.horizontal(global_position - player.global_position)
	if away.length_squared() < 0.01:
		away = -forward()
	away = away.normalized()
	_strafe = -_strafe
	var side := away.cross(Vector3.UP) * _strafe
	var target := player.global_position + away * preferred_range + side * 4.0
	if encounter and encounter.has_method("clamp_to_bounds"):
		target = encounter.clamp_to_bounds(target)
	move_target = Vector3(target.x, global_position.y, target.z)


func _take_token() -> bool:
	if _has_token:
		return true
	if encounter and encounter.has_method("request_aim"):
		_has_token = encounter.request_aim(self)
	else:
		_has_token = true
	return _has_token


func _release_token() -> void:
	if _has_token and encounter and encounter.has_method("release_aim"):
		encounter.release_aim(self)
	_has_token = false


# ---------------------------------------------------------------- presentation

func _model_path() -> String:
	return "res://enemies/models/raider.glb"


func _on_model() -> void:
	body.show_part("ScrapShield", false)


## The gun part in the model and the hand holds on it (rifle frame,
## barrel toward -Z): grip, handguard and magazine.
var rifle_part := "Rifle"
var rifle_grip := Vector3(0, -0.035, 0.02)
var rifle_fore := Vector3(0, -0.01, -0.3)
var rifle_mag := Vector3(0, -0.12, -0.13)

var _aim_w := 0.0
var _reload_w := 0.0


func _animate_body(delta: float) -> void:
	var speed := EnemyMath.horizontal(velocity).length()
	body.step(speed, 1.5, delta)
	var aiming := state in [State.AIM, State.RECOVER]
	_aim_w = move_toward(_aim_w, 1.0 if aiming else 0.0, delta * (7.0 if aiming else 3.0))
	_reload_w = move_toward(_reload_w, 1.0 if state == State.RELOAD else 0.0, delta * 5.0)
	var lower := Poses.blend(Poses.stand(), Poses.legs(body.phase, speed / move_speed), clampf(speed, 0.0, 1.0))
	lower = Poses.blend(lower, Poses.kneel(), duck)
	lower = _lower_pose(lower)
	var local_aim := Basis(Vector3.UP, yaw).inverse() * aim_dir
	var pitch := rad_to_deg(asin(clampf(local_aim.y, -1.0, 1.0)))
	var upper := Poses.blend(Poses.low_ready(), Poses.aim(pitch), _aim_w)
	var pose := Poses.layer(lower, upper)
	if is_staggered():
		pose = Poses.add(pose, Poses.flinch())
	body.show_pose(pose, delta)
	hold_rifle(local_aim, _aim_w, _reload_w, rifle_fore.lerp(rifle_mag, _reload_w))


## A chance for a subclass to change the legs (hops, kneeling...).
func _lower_pose(base: Dictionary) -> Dictionary:
	return base


## Puts the rifle where the state says and both hands on it.
func hold_rifle(local_aim: Vector3, aim_w: float, reload_w: float, left_hold: Vector3) -> void:
	var chest: Vector3 = body.global_transform.affine_inverse() * body.bone_position("UpperChest")
	var xf := Poses.rifle_xf(chest, local_aim, aim_w, reload_w, body.phase)
	body.hold(rifle_part, xf)
	body.reach("Right", xf * rifle_grip, Poses.RIGHT_POLE)
	body.reach("Left", xf * left_hold, Poses.LEFT_POLE)


func _animate(delta: float) -> void:
	if body == null:
		_pose.position.y = -DUCK_DROP * duck if not is_dead else _pose.position.y
	_taunt_time = maxf(_taunt_time - delta, 0.0)
	_taunt.visible = _taunt_time > 0.0 and not is_dead
	_draw_laser()


func _draw_laser() -> void:
	if not is_aiming() or not is_inside_tree():
		_laser.visible = false
		return
	var from := muzzle_position()
	var to := from + aim_dir * 80.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if not r.is_empty():
		to = r.position
	var len := from.distance_to(to)
	if len < 0.05:
		_laser.visible = false
		return
	var locked := is_locked()
	var w := 0.035 if locked else 0.018
	var up := Vector3.UP if absf(aim_dir.y) < 0.99 else Vector3.RIGHT
	_laser.global_transform = Transform3D(Basis.looking_at(aim_dir, up) * Basis.from_scale(Vector3(w, w, len)), (from + to) * 0.5)
	_laser_mat.albedo_color = Color(1.0, 0.95, 0.9, 0.95) if locked else Color(1.0, 0.12, 0.05, 0.25 + 0.5 * telegraph)
	_laser.visible = true
