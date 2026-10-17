extends "res://enemies/drone.gd"
## A spotter drone (the Host's): unarmed, it hangs high and back and paints
## you with a green beam. While it can see you, you're marked: every gunner
## in its encounter knows where you are even behind cover (they keep
## aiming at you through it, though walls still stop bullets) and locks on
## faster. Shoot it down to break the mark.

const SPOT_COLOR := Color(0.35, 1.0, 0.45)

var spotting := false
var _beam: MeshInstance3D
var _beam_mat: StandardMaterial3D


func _ready() -> void:
	super()
	max_health = 25.0
	health = max_health
	preferred_range = 18.0
	orbit_speed = 2.0
	hover_height = 6.5
	_beam = MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3.ONE
	_beam.mesh = b
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.albedo_color = Color(SPOT_COLOR, 0.35)
	_beam.material_override = _beam_mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.top_level = true
	_beam.visible = false
	add_child(_beam)


func _on_model() -> void:
	body.show_part("Gun", false)
	body.tint(Color(0.75, 0.95, 0.8))


func _telegraph_color() -> Color:
	return SPOT_COLOR


func _on_reset() -> void:
	super()
	spotting = false


## Never shoots: circles high and marks you while it can see you.
func _think(delta: float) -> void:
	state_time += delta
	face_toward(player.global_position, delta)
	_fly_to(_circle_point(), delta)
	spotting = can_see_player(head_position())
	telegraph = 0.6 if spotting else 0.0
	if spotting and encounter and encounter.has_method("spot"):
		encounter.spot(0.25)
	move_and_slide()


func _interrupt() -> void:
	super()
	spotting = false


func _animate(delta: float) -> void:
	super(delta)
	if _beam == null:
		return
	_beam.visible = spotting and active and not is_dead and player != null and is_inside_tree()
	if _beam.visible:
		var from := head_position()
		var to := EnemyMath.player_chest(player)
		var d := to - from
		var up := Vector3.UP if absf(d.normalized().y) < 0.99 else Vector3.RIGHT
		_beam.global_transform = Transform3D(Basis.looking_at(d.normalized(), up) * Basis.from_scale(Vector3(0.05, 0.05, d.length())), (from + to) * 0.5)
