class_name SandboxArena
extends EnemyEncounter
## The sandbox's enemy test arena, behind the run track's start (turn around
## at zone 1). Three raiders behind low walls, then two mutants guarding the
## back half. Low walls are vaultable, the side and back walls are blue
## for wallruns, and the yellow block on the left is high ground to mantle.
##
## Graybox geometry uses the sandbox's shader and kind metas, so the art
## look restyles it like the rest of the sandbox.

const SHADER := preload("res://levels/graybox.gdshader")
const COLORS := {
	"FLOOR": Color(0.56, 0.58, 0.62),
	"NEUTRAL": Color(0.76, 0.77, 0.80),
	"WALLRUN": Color(0.27, 0.6, 0.98),
	"PARKOUR": Color(0.98, 0.78, 0.26),
}
## Low cover: you can vault it, a ducked raider's head is just below it.
const COVER_HEIGHT := 1.2
const COVER_THICK := 0.5

## Arena origin (world). The entrance is on its -Z side, toward zone 1.
@export var origin := Vector3(0, 0, 60)

var overlay: HurtOverlay
var _status: Label3D
var _materials := {}


func _ready() -> void:
	var p := get_parent().get_node_or_null("Player") as Player
	_build_geometry()
	bounds = AABB(origin + Vector3(-26, -6, -26), Vector3(52, 30, 78))
	entry = Transform3D(Basis(Vector3.UP, PI), origin + Vector3(0, 0.1, -34))
	# Raiders: two up front, one deep. Mutants wake a moment later.
	add_enemy(Raider.new(), _at(Vector3(-4, 0, 7.0)))
	add_enemy(Raider.new(), _at(Vector3(14, 0, 23.0)))
	add_enemy(Raider.new(), _at(Vector3(-16, 0, 23.0)))
	# Mutants guard the back half: they rush you there, not across the arena.
	for spot: Array in [[Vector3(8, 0, 32), 2.0], [Vector3(-8, 0, 32), 3.5]]:
		var m := Mutant.new()
		m.wake_delay = spot[1]
		m.leash_radius = 24.0
		m.aggro_radius = 18.0
		add_enemy(m, _at(spot[0]))
	started.connect(func() -> void: _set_status(""))
	cleared.connect(func() -> void: _set_status("ARENA CLEAR\nrestarting soon"))
	reset_done.connect(func() -> void: _set_status("ENEMY ARENA\nstep in to start"))
	_set_status("ENEMY ARENA\nstep in to start")
	if p:
		setup(p)
		overlay = HurtOverlay.new()
		add_child(overlay)
		overlay.setup(player_health)


func _at(local: Vector3) -> Transform3D:
	return Transform3D(Basis.IDENTITY, origin + local)


func _set_status(text: String) -> void:
	_status.text = text
	_status.visible = text != ""


func _build_geometry() -> void:
	var o := origin
	# The sandbox floor ends at z = 90: extend it under the back of the arena.
	_box(Vector3(o.x, -0.5, 101), Vector3(56, 1, 22), "FLOOR")
	# Back and side walls (wallrun).
	_box(o + Vector3(0, 3, 52), Vector3(56, 6, 1), "WALLRUN")
	_box(o + Vector3(-27, 3, 12), Vector3(1, 6, 80), "WALLRUN")
	_box(o + Vector3(27, 3, 12), Vector3(1, 6, 80), "WALLRUN")
	# Low cover rows, nearest first.
	for wall: Array in [
		[Vector3(-12, 0, -6), 6.0], [Vector3(7, 0, -8), 5.0],
		[Vector3(-4, 0, 6), 7.0], [Vector3(14, 0, 4), 5.0],
		[Vector3(-16, 0, 22), 5.0], [Vector3(14, 0, 22), 5.0], [Vector3(2, 0, 20), 6.0],
	]:
		var c: Vector3 = o + wall[0]
		_box(c + Vector3(0, COVER_HEIGHT * 0.5, 0), Vector3(wall[1], COVER_HEIGHT, COVER_THICK), "PARKOUR")
		add_cover_wall(c, wall[1], COVER_THICK)
	# Tall pillars break sight lines (and can be wallrun).
	_box(o + Vector3(10, 3, 13), Vector3(2, 6, 2), "WALLRUN")
	_box(o + Vector3(-9, 3, 14), Vector3(2, 6, 2), "WALLRUN")
	# High ground on the left: mantle up and shoot down.
	_box(o + Vector3(-21, 1.2, 4), Vector3(4, 2.4, 4), "PARKOUR")
	_status = Label3D.new()
	_status.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_status.pixel_size = 0.0064
	_status.font_size = 64
	_status.outline_size = 12
	_status.modulate = Color(1.0, 0.55, 0.45)
	_status.outline_modulate = Color(0.08, 0.09, 0.12)
	_status.position = o + Vector3(0, 4.2, -28)
	_status.top_level = true
	add_child(_status)


func _box(center: Vector3, size: Vector3, kind: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("kind", kind)
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	if not _materials.has(kind):
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("base_color", COLORS[kind])
		_materials[kind] = m
	mesh.material_override = _materials[kind]
	body.add_child(mesh)
	add_child(body)
	body.global_position = center
	return body
