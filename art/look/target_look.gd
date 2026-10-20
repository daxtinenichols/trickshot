extends Node3D
## One dressed practice target, built by target_dresser.gd: the parts, and
## the hit flash on the paints that read as body and head. A file of its own
## (not an inner class) and loaded by path: a node whose script is an inner
## class of a script loaded at runtime hung Godot on quit.

const RED := Color(0.70, 0.24, 0.18)
## Amber glass, so the head still reads yellow (heads take extra damage).
const GLASS := Color(0.90, 0.68, 0.22)
const YELLOW := Color(0.92, 0.74, 0.28)
const WHITE := Color(0.86, 0.82, 0.74)
const TIMBER := Color(0.56, 0.42, 0.29)
const STEEL := Color(0.42, 0.40, 0.37)
const RUBBER := Color(0.13, 0.12, 0.12)
const HEAD_Y := 1.62

var look: Object
## Per-target paints for the parts that flash when hit.
var flashing: Array[StandardMaterial3D] = []
var flash := 0.0


func hit(_info: Dictionary) -> void:
	flash = 1.0


func _process(delta: float) -> void:
	if flash <= 0.0:
		return
	flash = move_toward(flash, 0.0, delta * 6.0)
	for m in flashing:
		m.emission = Color(1, 1, 1) * flash


## A paint that flashes, lit like the toon world but simpler.
func paint(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	m.emission_enabled = true
	m.emission = Color.BLACK
	flashing.append(m)
	return m


func world(kind: String, c: Color) -> Material:
	return look.wasteland_material(kind, c)


func box(center: Vector3, size: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = center
	mi.material_override = m
	add_child(mi)
	return mi


func cyl(center: Vector3, r_top: float, r_bottom: float, height: float, m: Material, axis := Vector3.UP) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bottom
	cm.height = height
	cm.radial_segments = 12
	cm.rings = 1
	mi.mesh = cm
	mi.position = center
	if axis == Vector3.BACK:
		mi.rotation.x = PI * 0.5
	mi.material_override = m
	add_child(mi)
	return mi


## An old tyre lying flat as the stand.
func tyre() -> void:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.2
	tm.outer_radius = 0.36
	tm.rings = 16
	tm.ring_segments = 8
	mi.mesh = tm
	mi.position = Vector3(0, 0.08, 0)
	mi.scale = Vector3(1, 0.9, 1)
	mi.material_override = world("NEUTRAL", RUBBER)
	add_child(mi)


## Painted rings on a face of the body: a bullseye at chest height.
func rings(z: float, at_y: float) -> void:
	var white := paint(WHITE)
	var red := paint(RED.darkened(0.1))
	cyl(Vector3(0, at_y, z), 0.2, 0.2, 0.012, white, Vector3.BACK)
	cyl(Vector3(0, at_y, z + signf(z) * 0.006), 0.13, 0.13, 0.012, red, Vector3.BACK)
	cyl(Vector3(0, at_y, z + signf(z) * 0.012), 0.06, 0.06, 0.012, white, Vector3.BACK)


## A sack-and-plank dummy on a rebar post with a paint-can head.
func dummy() -> void:
	tyre()
	var rust := world("RUST", STEEL)
	cyl(Vector3(0, 0.8, 0), 0.025, 0.025, 1.6, rust)
	# Two plank legs, a sack torso with a crossbar for shoulders.
	var plank := world("WOOD", TIMBER)
	for x in [-0.12, 0.12]:
		box(Vector3(x, 0.38, 0), Vector3(0.1, 0.62, 0.06), plank)
	var sack := paint(RED)
	box(Vector3(0, 1.0, 0), Vector3(0.42, 0.72, 0.24), sack)
	box(Vector3(0, 1.32, 0), Vector3(0.5, 0.08, 0.08), plank)
	rings(0.125, 1.05)
	# The head: a dented paint can, yellow.
	var can := paint(YELLOW)
	cyl(Vector3(0, HEAD_Y, 0), 0.15, 0.15, 0.3, can)
	cyl(Vector3(0, HEAD_Y + 0.155, 0), 0.155, 0.155, 0.02, world("RUST", STEEL))


## A cut steel plate in the shape of a person, hung from a pipe frame.
func plate() -> void:
	var rust := world("RUST", STEEL)
	# Feet of the frame, then the uprights each side.
	box(Vector3(0, 0.03, 0), Vector3(0.6, 0.06, 0.28), rust)
	for x in [-0.23, 0.23]:
		cyl(Vector3(x, 0.72, 0), 0.02, 0.02, 1.36, rust)
	var red := paint(RED)
	box(Vector3(0, 0.75, 0), Vector3(0.42, 1.2, 0.03), red)
	box(Vector3(0, 1.32, 0), Vector3(0.5, 0.12, 0.03), red)
	rings(0.02, 1.0)
	rings(-0.02, 1.0)
	# A round gong plate for the head on a short neck.
	cyl(Vector3(0, 1.43, 0), 0.03, 0.03, 0.1, rust)
	var gong := paint(YELLOW)
	cyl(Vector3(0, HEAD_Y, 0), 0.17, 0.17, 0.04, gong, Vector3.BACK)
	cyl(Vector3(0, HEAD_Y, 0.022), 0.07, 0.07, 0.01, paint(WHITE), Vector3.BACK)


## A stack of crate boards as the body, a plank on top with bottles.
func bottles() -> void:
	var wood := world("WOOD", TIMBER)
	var dark := world("WOOD", TIMBER.darkened(0.25))
	for i in 4:
		var y := 0.05 + 0.33 * i + 0.165
		box(Vector3(0, y, 0), Vector3(0.48, 0.31, 0.26), wood if i % 2 == 0 else dark)
	# A painted panel nailed to the front so the body still reads red.
	box(Vector3(0, 0.95, 0.135), Vector3(0.4, 0.6, 0.02), paint(RED))
	rings(0.15, 0.98)
	box(Vector3(0, 1.43, 0), Vector3(0.44, 0.04, 0.2), dark)
	# Three bottles inside the head ball: amber glass, one darker.
	var glass := paint(GLASS)
	var brown := paint(GLASS.darkened(0.25))
	for i in 3:
		var x := -0.1 + 0.1 * i
		var m := brown if i == 1 else glass
		cyl(Vector3(x, 1.56, 0), 0.04, 0.04, 0.2, m)
		cyl(Vector3(x, 1.7, 0), 0.015, 0.035, 0.08, m)
		cyl(Vector3(x, 1.76, 0), 0.016, 0.016, 0.04, m)
