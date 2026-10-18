extends "res://enemies/trooper.gd"
## A paramilitary shield bearer: a riot shield up front, a carbine fired
## one-handed past its edge. It doesn't hide behind cover, it is the cover:
## it walks you down to close range and keeps the shield between you.
##
## Shots from the front clank off the shield (no damage, no points). The
## top of the helmet shows over it, so a clean headshot still works, and
## the rest is about movement:
##   * get around it: it turns slowly, so a wallrun or a run past its side
##     opens its back;
##   * get over it: shots from above (jumps, flips, high ground) clear the
##     shield's top;
##   * kick the shield: it knocks the shield aside and staggers the bearer,
##     wide open, for a moment.

const PlateScript := preload("res://enemies/shield_plate.gd")
## The shield in the bearer's space (center), facing -Z.
const SHIELD_POS := Vector3(-0.12, 0.95, -0.46)
const SHIELD_SIZE := Vector3(0.66, 1.14, 0.08)
## A kicked shield stays down this long (s).
@export var guard_break := 1.4

var plate: StaticBody3D
var shield_hits := 0
## 0 = shield up .. 1 = knocked aside.
var guard_down := 0.0


func _ready() -> void:
	super()
	max_health = 90.0
	health = max_health
	move_speed = 3.2
	preferred_range = 8.0
	min_range = 4.0
	max_range = 22.0
	turn_rate = 110.0
	windup = 0.95
	burst = 1
	shots_per_reload = 5
	bullet_damage = 14.0
	kick_stagger = guard_break
	squad_spread = 0.0


func _build() -> void:
	super()
	plate = PlateScript.new(self)
	plate.name = "Shield"
	var cs := CollisionShape3D.new()
	cs.shape = box_shape(SHIELD_SIZE)
	plate.add_child(cs)
	plate.position = SHIELD_POS
	_hit_root.add_child(plate)


func _build_placeholder() -> void:
	super()
	var m := _material(Color(0.2, 0.22, 0.25))
	_mesh_box(SHIELD_SIZE, SHIELD_POS, m)


func _on_model() -> void:
	body.show_part("LongRifle", false)


## The shield mesh in the model.
func _shield_part() -> String:
	return "Shield"


func _on_reset() -> void:
	super()
	guard_down = 0.0
	if plate:
		plate.set_enabled(true)


func _set_alive_collision(on: bool) -> void:
	super(on)
	if plate:
		plate.set_enabled(on)


func on_shield_hit(_info: Dictionary) -> void:
	shield_hits += 1
	EnemySfx.play_at(self, &"clank", -2.0)


func on_kicked(by: Node, dir := Vector3.ZERO) -> bool:
	var killed := super(by, dir)
	if not is_dead:
		guard_down = 1.0
		plate.set_enabled(false)
	return killed


func tick(delta: float) -> void:
	super(delta)
	if guard_down > 0.0 and not is_staggered():
		guard_down = 0.0
		if not is_dead:
			plate.set_enabled(true)


## No cover: it walks you down, keeping the shield on you.
func _pick_spot() -> void:
	_since_pick = 0.0
	_no_sight = 0.0
	cover = {}
	var to_player := EnemyMath.horizontal(player.global_position - global_position)
	var dist := to_player.length()
	var target := global_position
	if dist > preferred_range:
		target = global_position + to_player.normalized() * minf(dist - preferred_range, 5.0)
	elif dist < min_range:
		target = global_position - to_player.normalized() * 2.0
	if encounter and encounter.has_method("clamp_to_bounds"):
		target = encounter.clamp_to_bounds(target)
	move_target = Vector3(target.x, global_position.y, target.z)


func _needs_new_spot(dist: float) -> bool:
	return dist > preferred_range + 1.5 or dist < min_range or _no_sight > 2.0


func _in_cover() -> bool:
	return false


# ---------------------------------------------------------------- presentation

func _animate_body(delta: float) -> void:
	super(delta)
	# Left hand on the shield's handle; the shield swings aside when kicked.
	var down := guard_down if is_staggered() else 0.0
	var xf := Transform3D(Basis(Vector3.UP, 0.9 * down) * Basis(Vector3.RIGHT, -0.5 * down),
			SHIELD_POS + Vector3(-0.3, -0.25, 0.25) * down)
	body.hold(_shield_part(), xf)
	body.reach("Left", xf * Vector3(0, 0, 0.08), Poses.LEFT_POLE)


## One-handed: the left hand is on the shield.
func hold_rifle(local_aim: Vector3, aim_w: float, reload_w: float, _left_hold: Vector3) -> void:
	var chest: Vector3 = body.global_transform.affine_inverse() * body.bone_position("UpperChest")
	var xf := Poses.rifle_xf(chest, local_aim, aim_w, reload_w * 0.0, body.phase)
	body.hold(rifle_part, xf)
	body.reach("Right", xf * rifle_grip, Poses.RIGHT_POLE)
