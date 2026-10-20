class_name SandboxArena
extends "res://enemies/enemy_encounter.gd"
## The sandbox's enemy test arena, behind the run track's start (turn around
## at zone 1). Three raiders behind low walls, then two mutants guarding the
## back half. Low walls are vaultable, the side and back walls are blue
## for wallruns, and the yellow block on the left is high ground to mantle.
##
## Clearing it alternates the roster: wave 1 is the Host's crew (raiders and
## mutants), wave 2 the harder enemies (paramilitary soldiers, a shield
## bearer and gun drones), so both can be practiced here.
##
## Graybox geometry uses the sandbox's shader and kind metas, so the art
## look restyles it like the rest of the sandbox.

const SHADER := preload("res://levels/graybox.gdshader")
# By path, not class name: the sandbox loads first, and a stale class cache
# in the editor must not stop it loading.
const RaiderScript := preload("res://enemies/raider.gd")
const MutantScript := preload("res://enemies/mutant.gd")
const SoldierScript := preload("res://enemies/trooper.gd")
const ShieldScript := preload("res://enemies/shield.gd")
const DroneScript := preload("res://enemies/drone.gd")
const COLORS := {
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
## The rosters it alternates between; `enemies` is the current one.
var waves: Array = []
var wave := 0
var _status: Label3D
var _materials := {}


func _ready() -> void:
	var p := get_parent().get_node_or_null("Player") as Player
	_build_geometry()
	bounds = AABB(origin + Vector3(-26, -6, -26), Vector3(52, 30, 78))
	entry = Transform3D(Basis(Vector3.UP, PI), origin + Vector3(0, 0.1, -34))
	# Raiders: two up front, one deep. Mutants wake a moment later.
	add_enemy(RaiderScript.new(), _at(Vector3(-4, 0, 7.0)))
	add_enemy(RaiderScript.new(), _at(Vector3(14, 0, 23.0)))
	add_enemy(RaiderScript.new(), _at(Vector3(-16, 0, 23.0)))
	# Mutants guard the back half: they rush you there, not across the arena.
	for spot: Array in [[Vector3(8, 0, 32), 2.0], [Vector3(-8, 0, 32), 3.5]]:
		var m := MutantScript.new()
		m.wake_delay = spot[1]
		m.leash_radius = 24.0
		m.aggro_radius = 18.0
		add_enemy(m, _at(spot[0]))
	waves.append(enemies.duplicate())
	enemies.clear()
	# Wave 2: two soldiers in cover, a shield bearer up the middle, and two
	# drones over the back half.
	add_enemy(SoldierScript.new(), _at(Vector3(14, 0, 23.0)))
	var s2 := SoldierScript.new()
	s2.wake_delay = 1.0
	add_enemy(s2, _at(Vector3(-16, 0, 23.0)))
	add_enemy(ShieldScript.new(), _at(Vector3(2, 0, 14.0)))
	for spot: Array in [[Vector3(-10, 0, 30), 1.5], [Vector3(10, 0, 34), 2.5]]:
		var d := DroneScript.new()
		d.wake_delay = spot[1]
		d.hover_height = 4.5
		d.leash_radius = 18.0
		add_enemy(d, _at(spot[0]))
	waves.append(enemies.duplicate())
	enemies.assign(waves[0])
	_bench_others()
	started.connect(func() -> void: _set_status(""))
	cleared.connect(func() -> void: _set_status("ARENA CLEAR\nnext wave soon"))
	reset_done.connect(func() -> void: _set_status(_wave_title()))
	_set_status(_wave_title())
	if p:
		setup(p)
		overlay = HurtOverlay.new()
		add_child(overlay)
		overlay.setup(player_health)


## A clear swaps in the other wave; going down or leaving keeps this one.
func reset(revive_all := false) -> void:
	if phase == Phase.CLEARED and waves.size() > 1:
		wave = (wave + 1) % waves.size()
		enemies.assign(waves[wave])
	super(revive_all)
	_bench_others()


func _wave_title() -> String:
	return "ENEMY ARENA\nstep in to start" if wave == 0 else "ENEMY ARENA: WAVE 2\nsoldiers, shield, drones"


## Hides the waves not in play (no hit zones, no thinking).
func _bench_others() -> void:
	for i in waves.size():
		if i == wave:
			continue
		for e: Enemy in waves[i]:
			e.deactivate()
			e.visible = false
			e.set_physics_process(false)
			e.process_mode = Node.PROCESS_MODE_DISABLED
			e._set_alive_collision(false)
	for e: Enemy in waves[wave]:
		e.process_mode = Node.PROCESS_MODE_INHERIT
		e.set_physics_process(true)


func _at(local: Vector3) -> Transform3D:
	return Transform3D(Basis.IDENTITY, origin + local)


func _set_status(text: String) -> void:
	_status.text = text
	_status.visible = text != ""


func _build_geometry() -> void:
	var o := origin
	# Back and side walls (wallrun).
	_box(o + Vector3(0, 3, 52), Vector3(56, 6, 1), "WALLRUN")
	# Side walls stop at the back wall instead of running into it, so the
	# two dresses don't flicker in the corner.
	_box(o + Vector3(-27, 3, 11.75), Vector3(1, 6, 79.5), "WALLRUN")
	_box(o + Vector3(27, 3, 11.75), Vector3(1, 6, 79.5), "WALLRUN")
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
