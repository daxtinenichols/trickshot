extends RefCounted
## Models for the things a runner carries instead of the gun (Pistol.held),
## built from boxes and cylinders so they're our own: build(kind, layer)
## returns a Node3D centred on the hand grip, about life size, with every
## mesh on render `layer` (Pistol.VIEW_LAYER in first person, the body's
## layer in the third-person hand, 1 for a delivered one in the world).
## Unknown kinds get the parcel.

const KINDS := ["parcel", "jerry_can", "relay", "tape"]


static func build(kind: String, layer := 1) -> Node3D:
	var root := Node3D.new()
	root.name = kind
	match kind:
		"jerry_can":
			_jerry_can(root)
		"relay":
			_relay(root)
		"tape":
			_tape(root)
		_:
			_parcel(root)
	for m: Node in root.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).layers = layer
		if layer != 1:
			(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


## A courier parcel: taped cardboard, tied with string, a paper label.
static func _parcel(root: Node3D) -> void:
	var card := _mat(Color(0.6, 0.45, 0.28), 0.9)
	var tape := _mat(Color(0.78, 0.66, 0.42), 0.5)
	var twine := _mat(Color(0.86, 0.8, 0.66), 1.0)
	var label := _mat(Color(0.92, 0.9, 0.84), 1.0)
	var ink := _mat(Color(0.15, 0.13, 0.12), 1.0)
	_box(root, Vector3(0.3, 0.18, 0.24), Vector3.ZERO, card)
	_box(root, Vector3(0.302, 0.182, 0.06), Vector3.ZERO, tape)
	_box(root, Vector3(0.012, 0.186, 0.244), Vector3(0.05, 0, 0), twine)
	_box(root, Vector3(0.304, 0.186, 0.012), Vector3(0, 0, -0.05), twine)
	_box(root, Vector3(0.09, 0.004, 0.06), Vector3(-0.08, 0.092, 0.05), label)
	_box(root, Vector3(0.06, 0.005, 0.006), Vector3(-0.08, 0.093, 0.04), ink)
	_box(root, Vector3(0.05, 0.005, 0.006), Vector3(-0.085, 0.093, 0.06), ink)
	# A red cross: medicine (Dawn Run's insulin).
	var red := _mat(Color(0.75, 0.12, 0.1), 0.8)
	_box(root, Vector3(0.05, 0.004, 0.014), Vector3(0.1, 0.092, 0.06), red)
	_box(root, Vector3(0.014, 0.004, 0.05), Vector3(0.1, 0.092, 0.06), red)


## A dented water jerry can, handle on top.
static func _jerry_can(root: Node3D) -> void:
	var paint := _mat(Color(0.3, 0.36, 0.22), 0.6, 0.3)
	var dark := _mat(Color(0.12, 0.12, 0.11), 0.5, 0.5)
	_box(root, Vector3(0.14, 0.32, 0.26), Vector3(0, -0.04, 0), paint)
	# The X stamped into the sides.
	for s: float in [-1.0, 1.0]:
		var x := _box(root, Vector3(0.008, 0.3, 0.03), Vector3(s * 0.072, -0.04, 0), dark)
		x.rotation.x = 0.7
		var y := _box(root, Vector3(0.008, 0.3, 0.03), Vector3(s * 0.072, -0.04, 0), dark)
		y.rotation.x = -0.7
	for z: float in [-0.07, 0.0, 0.07]:
		_box(root, Vector3(0.03, 0.05, 0.022), Vector3(0, 0.145, z), paint)
	_box(root, Vector3(0.03, 0.02, 0.18), Vector3(0, 0.175, 0), paint)
	var spout := _cyl(root, 0.025, 0.06, Vector3(0, 0.14, 0.1), dark)
	spout.rotation.x = 0.5


## Echo's spare relay: a scuffed steel box, dials, a lit lamp, a whip aerial.
static func _relay(root: Node3D) -> void:
	var steel := _mat(Color(0.34, 0.36, 0.37), 0.5, 0.6)
	var black := _mat(Color(0.08, 0.08, 0.09), 0.6)
	var face := _mat(Color(0.16, 0.17, 0.18), 0.7)
	_box(root, Vector3(0.24, 0.13, 0.18), Vector3.ZERO, steel)
	_box(root, Vector3(0.2, 0.09, 0.006), Vector3(0, 0, 0.092), face)
	for i in 3:
		var knob := _cyl(root, 0.014, 0.02, Vector3(-0.06 + i * 0.05, -0.01, 0.1), black)
		knob.rotation.x = PI * 0.5
	var lamp := _mat(Color(0.3, 1.0, 0.45), 0.3)
	lamp.emission_enabled = true
	lamp.emission = Color(0.3, 1.0, 0.45)
	lamp.emission_energy_multiplier = 2.0
	_box(root, Vector3(0.014, 0.014, 0.008), Vector3(0.08, 0.025, 0.096), lamp)
	_cyl(root, 0.004, 0.32, Vector3(0.09, 0.22, -0.06), black)
	_box(root, Vector3(0.16, 0.02, 0.02), Vector3(0, 0.075, 0), black)


## The Host's master tape: a reel of tape in a taped-up clear case.
static func _tape(root: Node3D) -> void:
	var case_mat := _mat(Color(0.75, 0.8, 0.85, 0.45), 0.2)
	case_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var reel := _mat(Color(0.7, 0.7, 0.72), 0.4, 0.7)
	var tape := _mat(Color(0.2, 0.12, 0.08), 0.4)
	var label := _mat(Color(0.85, 0.2, 0.15), 0.8)
	var hub := _cyl(root, 0.11, 0.012, Vector3.ZERO, reel)
	hub.rotation.x = PI * 0.5
	var wound := _cyl(root, 0.085, 0.016, Vector3.ZERO, tape)
	wound.rotation.x = PI * 0.5
	_box(root, Vector3(0.05, 0.03, 0.002), Vector3(0, 0, 0.0095), label)
	_box(root, Vector3(0.25, 0.25, 0.026), Vector3.ZERO, case_mat)


static func _mat(c: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.position = pos
	m.material_override = mat
	parent.add_child(m)
	return m


static func _cyl(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = 16
	m.mesh = c
	m.position = pos
	m.material_override = mat
	parent.add_child(m)
	return m
