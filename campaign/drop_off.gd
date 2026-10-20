extends Node3D
## A delivery drop-off for a "deliver" objective, where the carried object
## leaves your hands (Dax 2026-10-20): a crate (or a hatch in the floor)
## by the run line, lit, with "DROP" chalked on the floor, so you see it
## coming. Running through the objective's region tosses the object in
## on the move (MissionRun._deliver): no stop, no lost speed.
##
## Objective keys: "at" + "size"/"radius" (the region, like "reach"),
## "drop": "crate" (default) or "hatch", "drop_at": [x, y, z] for the
## receptacle (default the region's centre), "drop_yaw": degrees the chalk
## faces (0: read heading -Z). The floor under it is found by a ray.
## Visual only: nothing here is solid or changes the run.

const CARRY_MODELS := "res://weapons/carry_models.gd"
const TOSS_TIME := 0.35

var kind := "parcel"
var style := "crate"
var delivered := false

var _builder: Node3D
var _spot := Vector3.ZERO
var _yaw := 0.0
var _placed := false
var _inside: Node3D
var _flying: Node3D
var _toss_from := Vector3.ZERO
var _toss_t := -1.0
var _light: OmniLight3D


func setup(o: Dictionary, carried: String, builder: Node3D) -> void:
	kind = carried if carried not in ["gun", "hands"] else "parcel"
	style = String(o.get("drop", "crate"))
	_builder = builder
	_spot = MissionBuilder.vec(o.get("drop_at", o.get("at", [0, 0, 0])))
	_yaw = deg_to_rad(float(o.get("drop_yaw", 0.0)))
	top_level = true
	global_position = _spot


func _physics_process(_delta: float) -> void:
	if _placed:
		return
	_placed = true
	# Down onto the roof (or floor) under the spot.
	var q := PhysicsRayQueryParameters3D.create(_spot + Vector3.UP * 2.0, _spot + Vector3.DOWN * 8.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		_spot = hit.position
	global_position = _spot
	rotation.y = _yaw
	_build()


func _build() -> void:
	var wood := _mat(Color(0.45, 0.32, 0.2))
	var dark := _mat(Color(0.18, 0.15, 0.12))
	if style == "hatch":
		# A hatch in the roof, lid thrown back, a dark hole to drop into.
		_box(Vector3(1.1, 0.12, 1.1), Vector3(0, 0.06, 0), _mat(Color(0.3, 0.3, 0.3), 0.4, 0.6))
		_box(Vector3(0.8, 0.02, 0.8), Vector3(0, 0.125, 0), _mat(Color(0.02, 0.02, 0.02)))
		var lid := _box(Vector3(0.9, 0.05, 0.9), Vector3(0, 0.5, 0.5), _mat(Color(0.35, 0.36, 0.34), 0.4, 0.6))
		lid.rotation.x = -1.2
	else:
		# An open crate: four slat walls and a floor.
		_box(Vector3(1.1, 0.06, 0.8), Vector3(0, 0.03, 0), dark)
		for s: float in [-1.0, 1.0]:
			_box(Vector3(1.1, 0.6, 0.05), Vector3(0, 0.33, s * 0.38), wood)
			_box(Vector3(0.05, 0.6, 0.8), Vector3(s * 0.53, 0.33, 0), wood)
		_box(Vector3(1.12, 0.06, 0.06), Vector3(0, 0.48, 0.41), dark)
		var lid := _box(Vector3(1.1, 0.04, 0.8), Vector3(0, 0.82, -0.6), wood)
		lid.rotation.x = 1.1
	# A courier's flag on a pole, so it shows from the roof before.
	var steel := _mat(Color(0.25, 0.25, 0.26), 0.5, 0.7)
	_box(Vector3(0.06, 2.8, 0.06), Vector3(-0.55, 1.4, -0.3), steel)
	var flag := _mat(Color(0.98, 0.45, 0.12))
	flag.emission_enabled = true
	flag.emission = Color(0.98, 0.42, 0.1)
	flag.emission_energy_multiplier = 0.5
	flag.cull_mode = BaseMaterial3D.CULL_DISABLED
	_box(Vector3(0.02, 0.5, 0.75), Vector3(-0.55, 2.5, 0.1), flag)
	# Lit so it reads at a distance, chalked so you know what it's for.
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.72, 0.4)
	_light.omni_range = 7.0
	_light.light_energy = 2.5
	_light.shadow_enabled = false
	_light.position = Vector3(0, 2.2, 0)
	add_child(_light)
	if _builder != null and _builder.has_method("_chalk"):
		var xf := Transform3D(Basis(Vector3.UP, _yaw), _spot + Basis(Vector3.UP, _yaw) * Vector3(0, 0, 3.2))
		_builder._chalk(xf, "up", 2.4, true, "DROP")
	if delivered:
		show_delivered()


## Back to waiting for the object (a fresh run).
func reset() -> void:
	delivered = false
	_toss_t = -1.0
	for n: Node3D in [_inside, _flying]:
		if is_instance_valid(n):
			n.queue_free()
	_inside = null
	_flying = null
	if _light:
		_light.light_energy = 2.5


## The object goes in, thrown from `from` (world) in a quick arc.
func deliver(from: Vector3, carried: String) -> void:
	if carried not in ["gun", "hands"]:
		kind = carried
	delivered = true
	_flying = (load(CARRY_MODELS) as Script).call("build", kind, 1)
	_flying.top_level = true
	add_child(_flying)
	_flying.global_position = from
	_toss_from = from
	_toss_t = 0.0


## Already delivered (a practice start past it): the object sits inside.
func show_delivered() -> void:
	delivered = true
	if not _placed:
		return
	if not is_instance_valid(_inside):
		_inside = (load(CARRY_MODELS) as Script).call("build", kind, 1)
		_inside.position = Vector3(0.05, 0.2 if style == "crate" else -0.1, 0)
		_inside.rotation.y = 0.4
		add_child(_inside)
	if _light:
		_light.light_energy = 0.8


func _process(delta: float) -> void:
	if _toss_t < 0.0 or not is_instance_valid(_flying):
		return
	_toss_t += delta / TOSS_TIME
	var t := minf(_toss_t, 1.0)
	var to := global_position + Vector3.UP * (0.2 if style == "crate" else -0.1)
	var p := _toss_from.lerp(to, t) + Vector3.UP * sin(t * PI) * 0.8
	_flying.global_position = p
	_flying.rotation = Vector3(t * 4.0, t * 2.0, 0)
	if t >= 1.0:
		_flying.queue_free()
		_flying = null
		_toss_t = -1.0
		show_delivered()


func _mat(c: Color, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.position = pos
	m.material_override = mat
	add_child(m)
	return m
