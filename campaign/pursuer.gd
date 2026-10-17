class_name Pursuer
extends Node3D
## The chaser in a chase mission (the Host, hunting Echo down the tower).
## He follows your exact path: every tick your position is dropped as a
## breadcrumb, and he runs along the breadcrumbs at his own speed, which
## creeps up the longer the chase goes. Keep your speed up and the gap
## grows; stop, fall or fumble a move and he closes it. When he gets within
## `catch_distance` of you along the path, you're caught.
##
## Deterministic: driven by MissionRun's physics tick, no physics queries.

## Running speed at the start of the chase, m/s (you run 7.5-11.5).
## (Fields can be set per mission in its "pursuer" block.)
var speed := 7.6
## How much faster he gets each second, up to max_speed.
var speed_gain := 0.03
var max_speed := 9.4
## Seconds he waits before setting off after you start or respawn.
var delay := 2.5
var catch_distance := 1.6
## He never drops further back than this along your path: past it he runs
## at catchup_speed, so even a perfect run keeps him in your mirrors and
## any mistake costs you most of the lead.
var leash := 22.0
var catchup_speed := 12.5
var display_name := "THE HOST"

## Your path so far, and the distance along it to each point.
var crumbs := PackedVector3Array()
var _lengths := PackedFloat32Array()
## How far along the path he is.
var along := 0.0
var _wait := 0.0
var _chase_time := 0.0
## Path distance between him and you, updated each tick.
var gap := INF

var _body: Node3D


func configure(d: Dictionary) -> void:
	speed = d.get("speed", speed)
	speed_gain = d.get("speed_gain", speed_gain)
	max_speed = d.get("max_speed", max_speed)
	delay = d.get("delay", delay)
	catch_distance = d.get("catch_distance", catch_distance)
	leash = d.get("leash", leash)
	catchup_speed = d.get("catchup_speed", catchup_speed)
	display_name = d.get("name", display_name)


func _ready() -> void:
	_build_body()


## Back to the start of the chase at `at` (a respawn point).
func reset(at: Vector3) -> void:
	crumbs = PackedVector3Array([at])
	_lengths = PackedFloat32Array([0.0])
	along = 0.0
	_wait = delay
	_chase_time = 0.0
	gap = INF
	global_position = at
	visible = false


func current_speed() -> float:
	if gap > leash and gap < INF:
		return catchup_speed
	return minf(speed + speed_gain * _chase_time, max_speed)


func tick(target: Vector3, dt: float) -> void:
	if crumbs.is_empty():
		reset(target)
	if target.distance_to(crumbs[crumbs.size() - 1]) > 0.4:
		_lengths.append(_lengths[_lengths.size() - 1] + target.distance_to(crumbs[crumbs.size() - 1]))
		crumbs.append(target)
	var total := _lengths[_lengths.size() - 1]
	if _wait > 0.0:
		_wait -= dt
	else:
		_chase_time += dt
		along = minf(along + current_speed() * dt, total)
		visible = true
	global_position = point_at(along)
	gap = total - along + target.distance_to(crumbs[crumbs.size() - 1])
	if gap > 0.5:
		var ahead := point_at(minf(along + 1.0, total))
		var flat := Vector3(ahead.x - global_position.x, 0, ahead.z - global_position.z)
		if flat.length() > 0.05:
			global_basis = Basis.looking_at(flat.normalized(), Vector3.UP)


func has_caught() -> bool:
	return _wait <= 0.0 and gap <= catch_distance


## Point `d` meters along the breadcrumb path.
func point_at(d: float) -> Vector3:
	if crumbs.size() == 1:
		return crumbs[0]
	# Binary search for the segment holding d.
	var lo := 0
	var hi := _lengths.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if _lengths[mid] <= d:
			lo = mid
		else:
			hi = mid
	var seg := _lengths[hi] - _lengths[lo]
	var t := 0.0 if seg <= 0.0 else clampf((d - _lengths[lo]) / seg, 0.0, 1.0)
	return crumbs[lo].lerp(crumbs[hi], t)


## A stand-in figure until the Host has a model: a dark coat, a red
## headset light and a lamp you can see behind you.
func _build_body() -> void:
	_body = Node3D.new()
	add_child(_body)
	var coat := StandardMaterial3D.new()
	coat.albedo_color = Color(0.12, 0.1, 0.1)
	var torso := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.32
	cm.height = 1.8
	torso.mesh = cm
	torso.position = Vector3(0, 0.9, 0)
	torso.material_override = coat
	_body.add_child(torso)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1, 0.15, 0.1)
	glow.emission_enabled = true
	glow.emission = Color(1, 0.15, 0.1)
	glow.emission_energy_multiplier = 4.0
	var eye := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.36, 0.06, 0.08)
	eye.mesh = bm
	eye.position = Vector3(0, 1.62, -0.28)
	eye.material_override = glow
	_body.add_child(eye)
	var light := OmniLight3D.new()
	light.light_color = Color(1, 0.2, 0.15)
	light.omni_range = 6.0
	light.light_energy = 1.5
	light.position = Vector3(0, 1.8, 0)
	_body.add_child(light)
