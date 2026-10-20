class_name Pursuer
extends Node3D
## The chaser in a chase mission (the Host, hunting Echo down the tower).
## He follows your exact path: every tick your position is dropped as a
## breadcrumb, and he runs along the breadcrumbs at his own speed, which
## creeps up the longer the chase goes. Keep your speed up and the gap
## grows; stop, fall or fumble a move and he closes it.
##
## You can't play keep-away with him: when you're near him in a straight
## line but far along your own path (circling, doubling back), he stops
## following the crumbs and goes straight for you. Inside `lunge_range` he
## lunges, and within `catch_distance` (path or straight line) you're caught.
## Set pieces can bring him in close (`close_in`): he took a shortcut.
##
## Once the chase stops (you're caught, or the mission's over) MissionRun
## calls hold() every tick instead of tick(): he stops dead, he doesn't run
## on the spot. catch(you) first makes it a catch: he closes the last meter
## and grabs you (the body plays the grab from `caught` / `catch_ticks`).
##
## Deterministic: driven by MissionRun's physics tick, no physics queries.
## The body (the Host's model) only reads his state.

const BODY_SCRIPT_PATH := "res://art/characters/host/host_body.gd"

## Running speed at the start of the chase, m/s (you sprint at 11.5 and go
## faster from slides, drops and rolls). Fields can be set per mission in
## its "pursuer" block.
var speed := 10.4
## How much faster he gets each second, up to max_speed.
var speed_gain := 0.1
var max_speed := 11.4
## Seconds he waits before setting off after you start or respawn.
var delay := 1.2
## Grace period, seconds after he sets off: he can't catch you or lunge, and
## doesn't sprint to catch up past the leash, so you get a head start.
var grace := 4.0
## Closer than this and he has you (along your path or in a straight line).
var catch_distance := 2.2
## Closer than this and he lunges: lunge_boost m/s faster.
var lunge_range := 5.5
var lunge_boost := 3.5
## He never drops further back than this along your path: past it he runs
## at catchup_speed, so even a perfect run keeps him close, and any mistake
## puts him on your back.
var leash := 12.0
var catchup_speed := 15.0
## Straight-line range in which he cuts across instead of following your
## path, when your path is at least `shortcut_ratio` times longer.
var shortcut_range := 12.0
var shortcut_ratio := 1.3
var display_name := "THE HOST"

## Your path so far, and the distance along it to each point.
var crumbs := PackedVector3Array()
var _lengths := PackedFloat32Array()
## How far along the path he is (his nearest point on it).
var along := 0.0
var _wait := 0.0
var _chase_time := 0.0
## Distance between him and you, updated each tick: the shorter of your
## path and the straight line.
var gap := INF
## Straight-line distance to you.
var direct := INF
## His actual position (on your path unless he's cutting across).
var pos := Vector3.ZERO
## Velocity over the last tick, for the body.
var velocity := Vector3.ZERO
## True while he's lunging at you, or cutting straight across.
var lunging := false
var cutting := false
## Ticks since a set piece brought him in (the body plays a drop-in).
var since_close_in := 1 << 20
## He's got you: set by catch(), for the body's grab.
var caught := false
## Ticks since catch().
var catch_ticks := 0
## How close he ends up to whoever he grabbed (m, center to center).
var grab_distance := 0.85
var _crumb_i := 0

var _body: Node3D


func configure(d: Dictionary) -> void:
	for k: String in ["speed", "speed_gain", "max_speed", "delay", "grace", "catch_distance", "lunge_range",
			"lunge_boost", "leash", "catchup_speed", "shortcut_range", "shortcut_ratio"]:
		if d.has(k):
			set(k, float(d[k]))
	display_name = d.get("name", display_name)


func _ready() -> void:
	_build_body()


## Back to the start of the chase at `at` (a respawn point).
func reset(at: Vector3) -> void:
	crumbs = PackedVector3Array([at])
	_lengths = PackedFloat32Array([0.0])
	along = 0.0
	_crumb_i = 0
	_wait = delay
	_chase_time = 0.0
	gap = INF
	direct = INF
	pos = at
	velocity = Vector3.ZERO
	lunging = false
	cutting = false
	since_close_in = 1 << 20
	caught = false
	catch_ticks = 0
	global_position = at
	visible = false


func waiting() -> bool:
	return _wait > 0.0


func current_speed() -> float:
	if waiting():
		return 0.0
	var base := minf(speed + speed_gain * _chase_time, max_speed)
	if in_grace():
		return base
	if path_gap() > leash and path_gap() < INF:
		base = maxf(base, catchup_speed)
	if gap < lunge_range:
		base += lunge_boost
	return base


## Still in the head start after setting off (or waiting to).
func in_grace() -> bool:
	return waiting() or _chase_time < grace


func total() -> float:
	return _lengths[_lengths.size() - 1]


## How far you are ahead of him along your own path.
func path_gap() -> float:
	if crumbs.is_empty():
		return INF
	return total() - along


func tick(target: Vector3, dt: float) -> void:
	if crumbs.is_empty():
		reset(target)
	var last := crumbs[crumbs.size() - 1]
	if target.distance_to(last) > 0.4:
		_lengths.append(total() + target.distance_to(last))
		crumbs.append(target)
	var before := pos
	since_close_in += 1
	if _wait > 0.0:
		_wait -= dt
		pos = point_at(along)
	else:
		_chase_time += dt
		visible = true
		var step := current_speed() * dt
		var to_you := target - pos
		cutting = to_you.length() < shortcut_range and absf(to_you.y) < 1.6 \
				and path_gap() > to_you.length() * shortcut_ratio + 1.0
		if cutting:
			# Straight at you, and his place on your path catches up to
			# wherever he's got to.
			pos = pos.move_toward(target, step)
			_rejoin()
		else:
			along = minf(along + step, total())
			# Back onto your path smoothly after cutting across.
			pos = pos.move_toward(point_at(along), step * 1.6 + 0.02)
	global_position = pos
	direct = pos.distance_to(target)
	gap = minf(path_gap() + target.distance_to(crumbs[crumbs.size() - 1]), direct)
	lunging = not in_grace() and gap < lunge_range
	velocity = (pos - before) / dt if dt > 0.0 else Vector3.ZERO
	var face := Vector3(target.x - pos.x, 0, target.z - pos.z) if (cutting or lunging) else Vector3(velocity.x, 0, velocity.z)
	if face.length() > 0.05:
		global_basis = Basis.looking_at(face.normalized(), Vector3.UP)


func has_caught() -> bool:
	return not in_grace() and gap <= catch_distance


## He's got you at `target` (your position): from now on hold() closes in
## and the body grabs. Call once, when has_caught() first goes true (or from
## a set piece that scripts a catch).
func catch(target: Vector3) -> void:
	caught = true
	catch_ticks = 0
	lunging = false
	cutting = false
	visible = true
	_face(target - pos)


## The chase has stopped (caught, mission over, or paused by the mission):
## he stops running, so the body settles to a stand instead of running on
## the spot. Caught, he steps in to `grab_distance` of `target` and holds
## you there. Call every physics tick instead of tick().
func hold(target: Vector3, dt: float) -> void:
	# A set piece moving him itself (e.g. a fall) keeps him.
	if get("scripted") and not caught:
		return
	var before := pos
	lunging = false
	cutting = false
	if caught:
		catch_ticks += 1
		var flat := Vector3(target.x - pos.x, 0, target.z - pos.z)
		var want := target - flat.normalized() * grab_distance if flat.length() > 0.01 else pos
		want.y = target.y
		pos = pos.move_toward(want, 9.0 * dt)
		_face(flat)
	global_position = pos
	direct = pos.distance_to(target)
	velocity = (pos - before) / dt if dt > 0.0 and not caught else Vector3.ZERO


func _face(dir: Vector3) -> void:
	dir.y = 0.0
	if dir.length() > 0.05:
		global_basis = Basis.looking_at(dir.normalized(), Vector3.UP)


## A set piece: he took a shortcut and is suddenly `to_gap` m behind you
## along your path (only ever closer, never further). Returns true if it
## brought him in.
func close_in(to_gap: float) -> bool:
	if waiting() or crumbs.size() < 2 or path_gap() <= to_gap:
		return false
	along = maxf(total() - to_gap, along)
	pos = point_at(along)
	global_position = pos
	_crumb_i = _index_at(along)
	since_close_in = 0
	return true


## While cutting across: his place on your path is the furthest crumb
## (from where he was) within reach of him.
func _rejoin() -> void:
	var best := _crumb_i
	var i := _index_at(along)
	var n := crumbs.size()
	while i < n:
		if crumbs[i].distance_to(pos) < 1.2:
			best = i
		i += 1
	if best > _crumb_i or _lengths[best] > along:
		_crumb_i = best
		along = maxf(along, _lengths[best])


func _index_at(d: float) -> int:
	var lo := 0
	var hi := _lengths.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if _lengths[mid] <= d:
			lo = mid
		else:
			hi = mid
	return lo


## Point `d` meters along the breadcrumb path.
func point_at(d: float) -> Vector3:
	if crumbs.size() == 1:
		return crumbs[0]
	var lo := _index_at(d)
	var hi := mini(lo + 1, crumbs.size() - 1)
	var seg := _lengths[hi] - _lengths[lo]
	var t := 0.0 if seg <= 0.0 else clampf((d - _lengths[lo]) / seg, 0.0, 1.0)
	return crumbs[lo].lerp(crumbs[hi], t)


## The Host's model, running (art/characters/host, loaded by path), with a
## red lamp you can see behind you. Falls back to a dark stand-in.
func _build_body() -> void:
	var script := load(BODY_SCRIPT_PATH) as Script if ResourceLoader.exists(BODY_SCRIPT_PATH) else null
	if script != null and script.can_instantiate():
		_body = script.new()
		_body.name = "HostBody"
		_body.set("pursuer", self)
		add_child(_body)
	else:
		_body = Node3D.new()
		_body.name = "StandIn"
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
	var light := OmniLight3D.new()
	light.name = "Lamp"
	light.light_color = Color(1, 0.2, 0.15)
	light.omni_range = 7.0
	light.light_energy = 1.8
	light.position = Vector3(0, 2.1, 0)
	add_child(light)
