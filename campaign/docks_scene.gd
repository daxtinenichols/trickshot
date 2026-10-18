extends Node3D
## The Line's camp on its dock warehouse roof (Stage 1, the Docks), as a
## set piece: {"set_piece": "camp", "at": [x, y, z] (the roof's center, on
## it), "state": ...}. MissionBuilder loads this by path for "camp", and
## MissionRun ticks it like the chase set pieces (campaign/set_piece.gd):
## same setup / reset / tick and `went` signal.
##
##   "state": "intact"  (Dawn Run) dawn in the camp: Echo at her relay
##       bench holding out the parcel, Mags at the dispatch board, the kids
##       asleep under the tarps, Juno's empty bunk. Fired at "trigger" (on
##       the way back), the raid, seen from the waterfront: the camp goes to
##       its wrecked state, smoke climbs off the roof, a Static pickup pulls
##       away north along the quay with Echo fighting in the back, and the
##       Host's camera drone lifts off the roof and flies for the tower.
##       went("raid").
##   "state": "wrecked"  (The Yard) the camp after the raid. With "handoff":
##       true Mags stands by the way out holding the pistol out; running
##       past her takes it: went("handoff").
##
## Layout in the camp's frame (x east, z south, from the roof's center):
## the start lane runs west along z 9..21, the way back in comes south down
## x 18..30; the camp itself is the north-west of the roof. Visual only,
## apart from a few solid things to stand among (bench, board, bunks,
## crates); the moving parts are looks.

const FIGURE_PATH := "res://art/characters/runner/runner_figure.gd"
## The pickup's road: along the quay apron, south to north (world x; the
## quay edge is 3440).
const QUAY_X := 3438.0
const PICKUP_FROM_Z := 140.0
const PICKUP_TO_Z := -420.0
const PICKUP_SPEED := 13.0
## The drone: up off the roof, then away to the tower (world origin).
const DRONE_RISE_TICKS := 150
const DRONE_SPEED := 14.0
const DRONE_UP := 38.0
## Mags hands the pistol over to anyone passing within this of her hand.
const HANDOFF_RADIUS := 2.4

var kind := "camp"
var spec := {}
var trigger := Vector3.ZERO
var radius := 12.0
var fired := false
var ticks := 0
signal went(kind: String)

var state := "intact"
var _intact: Node3D
var _wrecked: Node3D
var _pickup: Node3D
var _drone: Node3D
var _smoke: CPUParticles3D
var _fire_light: OmniLight3D
var _pistol: Node3D
var _hand := Vector3.ZERO
var _handed := false


func setup(p: Dictionary) -> void:
	kind = String(p.set_piece)
	spec = p
	state = String(p.get("state", "intact"))
	position = _vec(p.get("at", [0, 0, 0]))
	rotation.y = deg_to_rad(float(p.get("yaw", 0.0)))
	trigger = _vec(p.get("trigger", [0, -1000, 0]))
	radius = float(p.get("radius", 12.0))
	_build_shared()
	_intact = _build_intact()
	_wrecked = _build_wrecked()
	if state == "intact":
		_build_raid()
	reset()


func reset() -> void:
	fired = false
	ticks = 0
	_handed = false
	_show(_intact, state == "intact")
	_show(_wrecked, state != "intact")
	if _pistol != null:
		_pistol.visible = true
	if _pickup != null:
		_pickup.visible = false
		_drone.visible = false
		_smoke.emitting = false
		_fire_light.visible = false


func tick(player_pos: Vector3, _run: Node) -> void:
	if state == "wrecked":
		if _pistol != null and not _handed and player_pos.distance_to(to_global(_hand)) <= HANDOFF_RADIUS + 1.0 \
				and Vector2(player_pos.x, player_pos.z).distance_to(Vector2(to_global(_hand).x, to_global(_hand).z)) <= HANDOFF_RADIUS:
			_handed = true
			_pistol.visible = false
			went.emit("handoff")
		return
	if not fired:
		if player_pos.distance_to(trigger) <= radius:
			_fire()
		return
	ticks += 1
	var t := ticks / 60.0
	# The pickup: off up the quay, away from you.
	var z := PICKUP_FROM_Z - PICKUP_SPEED * maxf(0.0, t - 0.5)
	_pickup.visible = z > PICKUP_TO_Z
	_pickup.position = to_local(Vector3(QUAY_X, 0.0, z))
	_pickup.rotation.y = -rotation.y
	# The drone: up off the roof, then away to the tower.
	var lift := clampf(float(ticks) / DRONE_RISE_TICKS, 0.0, 1.0)
	var start := Vector3(-6, 1.0, -8)
	var up := start + Vector3(0, 9.0 * (1.0 - (1.0 - lift) * (1.0 - lift)), 0)
	var away := maxf(0.0, t - DRONE_RISE_TICKS / 60.0) * DRONE_SPEED
	var dir := (to_local(Vector3.ZERO) - start)
	dir.y = 0.0
	dir = dir.normalized()
	_drone.position = up + dir * away + Vector3(0, minf(away * 0.08, DRONE_UP), 0)
	_drone.visible = away < 700.0
	_drone.rotation.y = atan2(dir.x, dir.z)


func _fire() -> void:
	fired = true
	ticks = 0
	_show(_intact, false)
	_show(_wrecked, true)
	_pickup.visible = true
	_drone.visible = true
	_smoke.emitting = true
	_fire_light.visible = true
	went.emit("raid")


## Shows or hides one state of the camp, solid parts and all.
func _show(n: Node3D, on: bool) -> void:
	n.visible = on
	for c: CollisionShape3D in n.find_children("*", "CollisionShape3D", true, false):
		c.disabled = not on


# ---------------------------------------------------------------- builds

## What stays the same whatever happened: Juno's bunk (untouched), the
## relay mast, crates, water tank.
func _build_shared() -> void:
	var cots := _node(self, "Cots")
	for i in 5:
		var x := -26.0 + i * 3.2
		_cot(cots, Vector3(x, 0, -22), i == 4)
	var juno := Label3D.new()
	juno.text = "JUNO"
	juno.font_size = 40
	juno.pixel_size = 0.004
	juno.modulate = Color(0.12, 0.12, 0.12)
	juno.outline_size = 0
	juno.position = Vector3(-26.0 + 4 * 3.2, 0.56, -21.0)
	juno.rotation_degrees = Vector3(-90, 0, 0)
	cots.add_child(juno)
	var tape := _box(cots, Vector3(-26.0 + 4 * 3.2, 0.535, -21.0), Vector3(0.5, 0.02, 0.14), _mat(Color(0.86, 0.84, 0.78)), false)
	tape.name = "JunoTape"
	# Her things still on it: a pack, a folded jacket, boots.
	_box(cots, Vector3(-26.0 + 4 * 3.2 - 0.1, 0.72, -22.4), Vector3(0.5, 0.4, 0.3), _mat(Color(0.35, 0.3, 0.42)), false)
	_box(cots, Vector3(-26.0 + 4 * 3.2 + 0.1, 0.6, -21.8), Vector3(0.45, 0.1, 0.35), _mat(Color(0.8, 0.8, 0.82)), false)
	_box(cots, Vector3(-26.0 + 4 * 3.2 + 0.25, 0.08, -20.6), Vector3(0.3, 0.16, 0.12), _mat(Color(0.18, 0.15, 0.12)), false)
	_prop("antenna_mast", Vector3(13.5, 0, 1.0), 0.0)
	_prop("water_tank", Vector3(-27, 0, -2), 0.0)
	_prop("crate_stack", Vector3(-28, 0, 5.5), 90.0)
	_prop("barrel_rust", Vector3(-24, 0, 6.5), 0.0)
	_prop("generator", Vector3(15.5, 0, -2.5), 90.0)


## Dawn, before: Echo at the bench, Mags at the board, kids asleep.
func _build_intact() -> Node3D:
	var n := _node(self, "Intact")
	_bench(n, Vector3(10, 0, 5.2), false)
	_board(n, Vector3(0.5, 0, 2.5), 0.0, false)
	for i in 2:
		var at := Vector3(-14.0 - i * 5.0, 0, -6)
		_prop_on(n, "tarp_shelter", at, 0.0)
		# Kids asleep in bedrolls under it.
		for k in 2:
			_bedroll(n, at + Vector3(-0.6 + k * 1.2, 0, 0.2), false)
	# Echo holds out the parcel to you; Mags turns from the board.
	_figure(n, "echo", Vector3(12.2, 0, 7.4), _yaw_to(Vector3(12.2, 0, 7.4), Vector3(19, 0, 15)), "holding_out", "")
	_box(n, Vector3(12.2, 0, 7.4) + Basis(Vector3.UP, _yaw_to(Vector3(12.2, 0, 7.4), Vector3(19, 0, 15))) * Vector3(-0.2, 1.22, 0.62),
		Vector3(0.34, 0.2, 0.26), _mat(Color(0.62, 0.48, 0.3)), false).name = "Parcel"
	_figure(n, "mags", Vector3(2.8, 0, 4.0), _yaw_to(Vector3(2.8, 0, 4.0), Vector3(19, 0, 15)), "idle")
	return n


## After: tarps down, the bench on its side, Echo's headphones on the
## floor, a radio dropped by the way in; Mags on the floor with the kids.
func _build_wrecked() -> Node3D:
	var n := _node(self, "Wrecked")
	_bench(n, Vector3(10, 0, 5.2), true)
	_board(n, Vector3(0.5, 0, 2.5), 0.0, true)
	for i in 2:
		var at := Vector3(-14.0 - i * 5.0, 0, -6)
		var torn := _box(n, at + Vector3(0.4 * i, 0.05, 0.3), Vector3(3.4, 0.06, 2.6), _mat(Color(0.32, 0.38, 0.3)), false)
		torn.rotation_degrees = Vector3(0, 18.0 - 30.0 * i, 6.0)
		_bedroll(n, at + Vector3(1.2, 0, 1.4), true)
	# Echo's headphones where they fell, near the way in.
	var phones := _node(n, "Headphones")
	phones.position = Vector3(20.2, 0.05, -2.2)
	_box(phones, Vector3(0, 0.04, 0), Vector3(0.36, 0.05, 0.05), _mat(Color(0.1, 0.1, 0.1)), false)
	for sx: float in [-1.0, 1.0]:
		_box(phones, Vector3(sx * 0.17, 0.05, 0.06), Vector3(0.1, 0.1, 0.1), _mat(Color(0.75, 0.2, 0.15)), false)
	var radio := _node(n, "DroppedRadio")
	radio.position = Vector3(21.6, 0.12, 1.2)
	radio.rotation_degrees = Vector3(0, 30, 80)
	_box(radio, Vector3.ZERO, Vector3(0.36, 0.22, 0.12), _mat(Color(0.2, 0.22, 0.2)), false)
	_box(radio, Vector3(0.1, 0.24, 0), Vector3(0.02, 0.3, 0.02), _mat(Color(0.5, 0.5, 0.5)), false)
	if spec.get("handoff", false):
		# Mags by the way out, holding the pistol out to Parker.
		var at := Vector3(21.6, 0, 9.0)
		var yaw := _yaw_to(at, Vector3(24, 0, 5))
		var mags := _figure(n, "mags", at, yaw, "holding_out", "pistol")
		_hand = at + Basis(Vector3.UP, yaw) * Vector3(-0.2, 1.22, 0.62)
		_pistol = mags.get("held_model") if mags != null else null
		if _pistol == null:
			# No figure (or no pistol model): a stand-in on her hand.
			_pistol = _node(n, "Pistol")
			_pistol.position = _hand
			_pistol.rotation.y = yaw
			_box(_pistol, Vector3(0, 0, 0.05), Vector3(0.05, 0.08, 0.24), _mat(Color(0.15, 0.15, 0.16)), false)
			_box(_pistol, Vector3(0, -0.07, -0.04), Vector3(0.045, 0.12, 0.06), _mat(Color(0.32, 0.2, 0.12)), false)
		for k in 2:
			_bedroll(n, Vector3(13.0 + k * 1.1, 0, -4.0), true)
	else:
		_figure(n, "mags", Vector3(13.6, 0, -3.6), _yaw_to(Vector3(13.6, 0, -3.6), Vector3(24, 0, -2)), "sitting")
		for k in 2:
			_bedroll(n, Vector3(12.2 + k * 1.0, 0, -5.2 + k * 0.4), true)
	return n


## The raid's moving parts: smoke and a fire glow over the roof, the
## pickup, the drone.
func _build_raid() -> void:
	_smoke = CPUParticles3D.new()
	_smoke.name = "Smoke"
	_smoke.position = Vector3(-14, 1.0, -6)
	_smoke.amount = 48
	_smoke.lifetime = 9.0
	_smoke.emitting = false
	_smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_smoke.emission_sphere_radius = 3.0
	_smoke.direction = Vector3(0.25, 1, 0)
	_smoke.spread = 12.0
	_smoke.gravity = Vector3(0.6, 1.2, 0)
	_smoke.initial_velocity_min = 2.0
	_smoke.initial_velocity_max = 4.0
	_smoke.scale_amount_min = 4.0
	_smoke.scale_amount_max = 9.0
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var sm := StandardMaterial3D.new()
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Color(0.16, 0.15, 0.14, 0.55)
	sm.vertex_color_use_as_albedo = true
	quad.material = sm
	_smoke.mesh = quad
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.9))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	_smoke.color_ramp = fade
	add_child(_smoke)
	_fire_light = OmniLight3D.new()
	_fire_light.position = Vector3(-14, 2.0, -6)
	_fire_light.light_color = Color(1.0, 0.5, 0.2)
	_fire_light.light_energy = 3.0
	_fire_light.omni_range = 14.0
	add_child(_fire_light)
	_pickup = _node(self, "Pickup")
	var paint := _mat(Color(0.36, 0.3, 0.24))
	var dark := _mat(Color(0.08, 0.08, 0.09))
	_box(_pickup, Vector3(0, 0.9, -1.4), Vector3(2.0, 1.0, 2.2), paint, false)
	_box(_pickup, Vector3(0, 1.75, -1.2), Vector3(1.9, 0.75, 1.6), dark, false)
	_box(_pickup, Vector3(0, 0.75, 1.3), Vector3(2.0, 0.7, 2.8), paint, false)
	_box(_pickup, Vector3(0, 1.15, 2.7), Vector3(2.0, 0.5, 0.08), paint, false)
	for sx: float in [-1.0, 1.0]:
		_box(_pickup, Vector3(sx * 0.97, 1.15, 1.3), Vector3(0.06, 0.5, 2.8), paint, false)
		for wz: float in [-1.6, 1.6]:
			var wheel := _box(_pickup, Vector3(sx * 0.9, 0.4, wz), Vector3(0.3, 0.8, 0.8), dark, false)
			wheel.name = "Wheel"
	# A Static flag on a pole, and Echo in the back, fighting it.
	_box(_pickup, Vector3(0.8, 2.6, 2.5), Vector3(0.05, 2.2, 0.05), dark, false)
	_box(_pickup, Vector3(0.8, 3.3, 2.1), Vector3(0.03, 0.6, 0.8), _mat(Color(0.75, 0.12, 0.1)), false)
	var echo := _figure(_pickup, "echo", Vector3(0, 1.1, 1.6), PI, "idle")
	if echo != null:
		echo.set("walk_speed", 1.6)
	_drone = _node(self, "Drone")
	_box(_drone, Vector3.ZERO, Vector3(0.7, 0.22, 0.7), dark, false)
	for a in 4:
		var arm := Basis(Vector3.UP, PI * 0.25 + a * PI * 0.5) * Vector3(0, 0, 0.55)
		_box(_drone, arm * 0.5, Vector3(0.08, 0.06, 0.55), dark, false).rotation.y = PI * 0.25 + a * PI * 0.5
		_box(_drone, arm + Vector3(0, 0.08, 0), Vector3(0.4, 0.02, 0.4), _mat(Color(0.3, 0.3, 0.3)), false)
	var eye := _box(_drone, Vector3(0, -0.12, 0.3), Vector3(0.16, 0.16, 0.16), _mat(Color(1.0, 0.15, 0.1), 4.0), false)
	eye.name = "Eye"


# ---------------------------------------------------------------- parts

func _bench(parent: Node3D, at: Vector3, smashed: bool) -> void:
	var n := _node(parent, "RelayBench")
	n.position = at
	var wood := _mat(Color(0.45, 0.34, 0.22))
	if smashed:
		# On its side, the gear scattered.
		var top := _box(n, Vector3(0, 0.45, -0.3), Vector3(2.4, 0.08, 0.9), wood, true)
		top.rotation_degrees = Vector3(80, 0, 0)
		for i in 5:
			var g := _box(n, Vector3(-1.6 + i * 0.8, 0.1, 0.6 + 0.4 * (i % 2)), Vector3(0.35, 0.2, 0.25), _mat(Color(0.2, 0.22, 0.2)), false)
			g.rotation_degrees = Vector3(0, 35.0 * i, 70.0 * (i % 2))
		return
	_box(n, Vector3(0, 0.88, 0), Vector3(2.4, 0.08, 0.9), wood, true)
	for sx: float in [-1.1, 1.1]:
		_box(n, Vector3(sx, 0.42, 0), Vector3(0.08, 0.84, 0.8), wood, false)
	# Her relays: boxes with dials, a soldering iron, coils of wire.
	for i in 4:
		_box(n, Vector3(-0.8 + i * 0.45, 1.04, -0.15), Vector3(0.36, 0.24, 0.3), _mat(Color(0.2, 0.22, 0.2)), false)
		_box(n, Vector3(-0.8 + i * 0.45, 1.06, 0.01), Vector3(0.06, 0.06, 0.02), _mat(Color(0.9, 0.6, 0.2), 2.0), false)
	_box(n, Vector3(0.9, 0.94, 0.25), Vector3(0.2, 0.03, 0.03), _mat(Color(0.6, 0.6, 0.6)), false)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 1.6, 0.3)
	lamp.light_color = Color(1.0, 0.75, 0.45)
	lamp.light_energy = 1.2
	lamp.omni_range = 5.0
	n.add_child(lamp)


## The dispatch board: a chalkboard of routes on legs, facing south.
func _board(parent: Node3D, at: Vector3, yaw: float, knocked: bool) -> void:
	var n := _node(parent, "DispatchBoard")
	n.position = at
	n.rotation.y = yaw
	var wood := _mat(Color(0.4, 0.3, 0.2))
	if knocked:
		var b := _box(n, Vector3(0, 0.2, 1.0), Vector3(3.2, 2.0, 0.08), _mat(Color(0.14, 0.17, 0.15)), false)
		b.rotation_degrees = Vector3(-84, 0, 4)
		return
	_box(n, Vector3(0, 1.6, 0), Vector3(3.2, 2.0, 0.08), _mat(Color(0.14, 0.17, 0.15)), true)
	for sx: float in [-1.5, 1.5]:
		_box(n, Vector3(sx, 0.9, 0), Vector3(0.1, 1.8, 0.1), wood, false)
	var chalk := Label3D.new()
	chalk.text = "ROUTES\nOKAFOR - HIGH ROOF  (P)\nMARKET RUN - TUE\nWATER - PIER 4\nJUNO - ?"
	chalk.font_size = 44
	chalk.pixel_size = 0.0045
	chalk.modulate = Color(0.92, 0.92, 0.88)
	chalk.outline_size = 0
	chalk.position = Vector3(0, 1.6, 0.05)
	n.add_child(chalk)


func _cot(parent: Node3D, at: Vector3, juno: bool) -> void:
	_box(parent, at + Vector3(0, 0.45, 0), Vector3(0.85, 0.12, 2.0), _mat(Color(0.32, 0.36, 0.28)), true)
	for sx: float in [-0.38, 0.38]:
		for sz: float in [-0.9, 0.9]:
			_box(parent, at + Vector3(sx, 0.2, sz), Vector3(0.05, 0.4, 0.05), _mat(Color(0.25, 0.25, 0.25)), false)
	if not juno:
		_box(parent, at + Vector3(0, 0.56, 0.3), Vector3(0.75, 0.1, 1.2), _mat(Color(0.5, 0.42, 0.34)), false)


## A kid in a bedroll: asleep (lying) or sitting up, wrapped.
func _bedroll(parent: Node3D, at: Vector3, sitting: bool) -> void:
	var cloth := _mat(Color(0.42, 0.33, 0.28) if not sitting else Color(0.36, 0.4, 0.46))
	var skin := _mat(Color(0.55, 0.4, 0.3))
	if sitting:
		_box(parent, at + Vector3(0, 0.35, 0), Vector3(0.5, 0.7, 0.45), cloth, false)
		_box(parent, at + Vector3(0, 0.82, 0), Vector3(0.22, 0.24, 0.22), skin, false)
	else:
		_box(parent, at + Vector3(0, 0.14, 0.2), Vector3(0.55, 0.28, 1.3), cloth, false)
		_box(parent, at + Vector3(0, 0.14, -0.6), Vector3(0.22, 0.2, 0.24), skin, false)


func _figure(parent: Node3D, runner: String, at: Vector3, yaw: float, pose: String, held := "auto") -> Node3D:
	if Engine.is_editor_hint():
		return null
	var script := load(FIGURE_PATH) as Script if ResourceLoader.exists(FIGURE_PATH) else null
	if script == null or not script.can_instantiate():
		return null
	var f: Node3D = script.new()
	f.name = "Figure_" + runner
	f.runner = runner
	f.pose_name = pose
	f.held = held
	f.position = at
	f.rotation.y = yaw
	parent.add_child(f)
	return f


## The yaw a figure at `from` turns to face `to` (figures face +Z at 0).
static func _yaw_to(from: Vector3, to: Vector3) -> float:
	return atan2(to.x - from.x, to.z - from.z)


func _prop(prop_name: String, at: Vector3, yaw_deg: float) -> void:
	_prop_on(self, prop_name, at, yaw_deg)


func _prop_on(parent: Node3D, prop_name: String, at: Vector3, yaw_deg: float) -> void:
	var kit: Script = load("res://art/props/prop_kit.gd")
	kit.call("place", parent, prop_name, Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), at), false)


func _node(parent: Node3D, n: String) -> Node3D:
	var node := Node3D.new()
	node.name = n
	parent.add_child(node)
	return node


func _mat(c: Color, glow := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	return m


## A box part; `solid` ones also stop you (a static body of their own).
func _box(parent: Node3D, center: Vector3, size: Vector3, mat: Material, solid: bool) -> Node3D:
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = mat
	mesh.position = center
	parent.add_child(mesh)
	if solid:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
		mesh.add_child(body)
	return mesh


static func _vec(a: Variant) -> Vector3:
	if a is Array and a.size() >= 3:
		return Vector3(a[0], a[1], a[2])
	return Vector3.ZERO
