extends RefCounted
## The checks behind campaign/tools/fall_probe.gd and the false-fall tests.
## Rough by design, like reach_probe: generous movement limits, so it
## errs toward finding too many places you can get to.

const CELL := 1.0
## How far either side of the course line the scan reaches.
const REACH := 22.0
const STEP := 0.6        # walk up
const CLIMB := 3.2       # climb onto a ledge right next to you
const JUMP_UP := 1.4     # onto a higher top a running jump away
const JUMP_LONG := 9.0   # level or downhill running jump
const HEADROOM := 1.0
## A visible floor counts as solid when a collider top is this close under it.
const FLOOR_SLACK := 1.0
## About the runner's radius: a top this close to a spot holds you there.
const FEET := 0.35
## A hard landing: about a 40 m drop.
const DROP_SPEED := 28.0
const DROP_TICKS := 12
## Wider than this between two floors is a gap you're meant to jump.
const SEAM_MAX := 1.2
## Narrower than the runner (radius 0.38) can't take you in.
const SEAM_MIN := 0.7
const OPENABLE := ["res://levels/door.gd", "res://levels/breakable_window.gd"]

## Doors and glass you kick or jump through: rays pass them.
static var _exclude: Array[RID] = []


## Loads a mission by id the way the game does, player parked.
static func load_level(tree: SceneTree, id: String) -> Node:
	var campaign: Script = load("res://campaign/campaign.gd")
	campaign.persist = false
	var all: Array = campaign.missions()
	for i in all.size():
		if all[i].id == id:
			campaign.current = i
	var level: Node = (load("res://campaign/mission.tscn") as PackedScene).instantiate()
	tree.root.add_child(level)
	var p: Node = level.get_node("Player")
	p.set("use_device_input", false)
	p.set_physics_process(false)
	for i in 4:
		await tree.physics_frame
	# Dressed the way it's played (headless runs leave the art look off),
	# so a dressed floor with nothing in it shows up.
	var look: Node = tree.root.get_node_or_null("ArtLook")
	if look != null and look.get("enabled"):
		look.call("_apply_all", level)
		await tree.physics_frame
	return level


## {tops, reached, false_falls, ground_falls, no_floor, no_floor_what,
## standable, seams}
static func probe(level: Node) -> Dictionary:
	var run: Node = level.get("run")
	var builder: Node = level.get_node("Builder")
	var space := (level as Node3D).get_world_3d().direct_space_state
	_exclude.clear()
	for n: Node in _all(level):
		var sc: Script = n.get_script()
		if n is CollisionObject3D and sc != null and sc.resource_path in OPENABLE:
			_exclude.append((n as CollisionObject3D).get_rid())
	var t0 := Time.get_ticks_msec()
	var line := course_line(builder)
	var cells := _cells_near(line)
	var surfaces := {}
	var tops := 0
	for c: Vector2i in cells:
		var t := _tops(space, _world(c, 0.0))
		if not t.is_empty():
			surfaces[c] = t
			tops += t.size()
	var t1 := Time.get_ticks_msec()
	# From the start and every checkpoint: all on the course, and it
	# saves modelling the long speed-gate jumps between them.
	var seeds: Array[Vector3] = []
	for xf: Transform3D in builder.get("spawns"):
		seeds.append(xf.origin)
	var false_falls: Array[Vector3] = []
	var ground_falls: Array[Vector3] = []
	var standable: Array[Vector3] = []
	var reached := _flood(space, surfaces, seeds, func(p: Vector3) -> bool:
		if not run.is_fall(p + Vector3(0, 0.05, 0)):
			standable.append(p)
			return false
		# Down on the bare ground off the course is a real fall; anything
		# else you stand on isn't.
		if _on_bare_ground(space, p):
			ground_falls.append(p)
		else:
			false_falls.append(p)
		return true)
	var t2 := Time.get_ticks_msec()
	var seams := _seams(space, standable)
	var t3 := Time.get_ticks_msec()
	var what := {}
	var no_floor := _no_floor(level, space, reached, what)
	if OS.has_environment("PROBE_TIME"):
		print("  scan %d  flood %d  seams %d  meshes %d ms" % [t1 - t0, t2 - t1, t3 - t2, Time.get_ticks_msec() - t3])
	return {"tops": tops, "reached": reached.size(), "false_falls": false_falls,
		"no_floor": no_floor, "no_floor_what": what, "standable": standable, "seams": seams, "ground_falls": ground_falls}


## The course as a line: the start, every checkpoint, the reach goals and
## the route's end, in that order.
static func course_line(builder: Node) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for xf: Transform3D in builder.get("spawns"):
		pts.append(xf.origin)
	var mission: Dictionary = builder.get("mission")
	for o: Dictionary in mission.get("objectives", []):
		if o.get("at", null) is Array:
			pts.append(_vec(o.at))
	if mission.has("route_end"):
		pts.append(_vec(mission.route_end))
	return pts


static func _vec(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


static func _cells_near(line: Array[Vector3]) -> Dictionary:
	var cells := {}
	var r := int(ceil(REACH / CELL))
	for i in line.size():
		var a := line[i]
		var b := line[mini(i + 1, line.size() - 1)]
		var n := maxi(int(Vector2(b.x - a.x, b.z - a.z).length() / (CELL * 4.0)), 1)
		for k in n + 1:
			var p := a.lerp(b, k / float(n))
			var c := _cell(p)
			for dx in range(-r, r + 1):
				for dz in range(-r, r + 1):
					if dx * dx + dz * dz <= r * r:
						cells[c + Vector2i(dx, dz)] = true
	return cells


static func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))


static func _world(c: Vector2i, y: float) -> Vector3:
	return Vector3((c.x + 0.5) * CELL, y, (c.y + 0.5) * CELL)


## Every standable top in a column (rays straight down, through solids).
static func _tops(space: PhysicsDirectSpaceState3D, at: Vector3) -> Array[float]:
	var tops: Array[float] = []
	var y := 140.0
	var guard := 0
	while y > -45.0 and guard < 32:
		guard += 1
		var r := space.intersect_ray(_ray(Vector3(at.x, y, at.z), Vector3(at.x, -45.0, at.z), 1))
		if r.is_empty():
			break
		var hy: float = r.position.y
		var p := Vector3(at.x, hy, at.z)
		if (r.normal as Vector3).y > 0.6 and not _solid_at(space, p + Vector3(0, 0.05, 0)) \
				and space.intersect_ray(_ray(p + Vector3(0, 0.02, 0), p + Vector3(0, HEADROOM, 0), 1)).is_empty():
			tops.append(hy)
		# A ray starting inside a solid passes out of it: on to the next top.
		y = hy - 0.02
	return tops


## The bare ground: the route's ground slab, or nothing at all under you.
static func _on_bare_ground(space: PhysicsDirectSpaceState3D, p: Vector3) -> bool:
	var q := _ray(p + Vector3(0, 0.3, 0), p + Vector3(0, -0.3, 0), 1)
	var r := space.intersect_ray(q)
	if r.is_empty():
		return true
	var body: Object = r.collider
	return body != null and body.has_meta("kind") and String(body.get_meta("kind")) == "FLOOR" and p.y < 0.3


## From the start, with generous limits; `stop(p)` true ends the branch
## there (a fall).
static func _flood(space: PhysicsDirectSpaceState3D, surfaces: Dictionary, seeds: Array[Vector3], stop: Callable) -> Dictionary:
	var seen := {}
	var queue: Array = []
	for start: Vector3 in seeds:
		var c0 := _cell(start)
		var best := 1.5
		for y: float in surfaces.get(c0, []):
			if absf(y - start.y) < best:
				best = absf(y - start.y)
				if not seen.has(_world(c0, y)):
					seen[_world(c0, y)] = true
					queue.append([c0, y])
	var near := int(ceil(1.2 / CELL))
	var far := int(ceil(JUMP_LONG / CELL))
	while not queue.is_empty():
		var item: Array = queue.pop_back()
		var c: Vector2i = item[0]
		var y: float = item[1]
		for dx in range(-far, far + 1):
			for dz in range(-far, far + 1):
				var d2 := dx * dx + dz * dz
				if d2 > far * far or d2 == 0:
					continue
				var n := c + Vector2i(dx, dz)
				if not surfaces.has(n):
					continue
				var adjacent := absi(dx) <= 1 and absi(dz) <= 1
				var close := absi(dx) <= near and absi(dz) <= near
				for ny: float in surfaces[n]:
					var up := ny - y
					var ok := up <= 0.0 or (adjacent and up <= STEP) or (close and up <= CLIMB) or up <= JUMP_UP
					if not ok:
						continue
					var key := _world(n, ny)
					if seen.has(key):
						continue
					if _blocked(space, _world(c, y), key):
						continue
					seen[key] = true
					if stop.call(key):
						continue
					queue.append([n, ny])
	return seen


## A wall between two spots, no room to climb, or a floor in the way down.
static func _blocked(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> bool:
	var top := maxf(a.y, b.y)
	for h: float in [0.7, 1.6]:
		var q := _ray(Vector3(a.x, top + h, a.z), Vector3(b.x, top + h, b.z), 1)
		if not space.intersect_ray(q).is_empty():
			return true
	if b.y > a.y + 0.3:
		var u := _ray(Vector3(a.x, a.y + 1.0, a.z), Vector3(a.x, b.y + 1.6, a.z), 1)
		if not space.intersect_ray(u).is_empty():
			return true
	if b.y < a.y - 0.3:
		var d := _ray(Vector3(b.x, a.y + 0.9, b.z), Vector3(b.x, b.y + 0.1, b.z), 1)
		if not space.intersect_ray(d).is_empty():
			return true
	return false


## Spots next to where you can be that show a floor (a mesh top facing up)
## with nothing solid in it: you'd step onto it and drop through.
static func _no_floor(level: Node, space: PhysicsDirectSpaceState3D, reached: Dictionary, what: Dictionary) -> Array[Vector3]:
	# Reached tops by cell, to test "can you step onto this?".
	var by_cell := {}
	var area := AABB()
	var first := true
	for k: Vector3 in reached:
		var c := _cell(k)
		if not by_cell.has(c):
			by_cell[c] = []
		by_cell[c].append(k.y)
		if first:
			area = AABB(k, Vector3.ZERO)
			first = false
		else:
			area = area.expand(k)
	area = area.grow(2.0)
	var near := {}
	for c: Vector2i in by_cell:
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				near[c + Vector2i(dx, dz)] = true
	var out: Array[Vector3] = []
	var seen := {}
	for mi: MeshInstance3D in _meshes(level):
		# Scripted set pieces (a bridge that blows) and fire glow aren't floors.
		if mi.is_in_group("mission_fire") or _in_set_piece(mi):
			continue
		var box := mi.global_transform * mi.get_aabb()
		if not box.intersects(area) or box.size.x * box.size.z < 0.5:
			continue
		var c0 := _cell(box.position)
		var c1 := _cell(box.end)
		var cells: Array[Vector2i] = []
		if (c1.x - c0.x + 1) * (c1.y - c0.y + 1) > near.size():
			for c: Vector2i in near:
				if c.x >= c0.x and c.x <= c1.x and c.y >= c0.y and c.y <= c1.y:
					cells.append(c)
		else:
			for cx in range(c0.x, c1.x + 1):
				for cz in range(c0.y, c1.y + 1):
					if near.has(Vector2i(cx, cz)):
						cells.append(Vector2i(cx, cz))
		if cells.is_empty():
			continue
		var tri := mi.mesh.generate_triangle_mesh()
		if tri == null:
			continue
		var inv := mi.global_transform.affine_inverse()
		for c: Vector2i in cells:
			var w := _world(c, box.end.y + 0.1)
			var from := inv * w
			var dir := (inv.basis * Vector3.DOWN).normalized()
			var hit := tri.intersect_ray(from, dir)
			if hit.is_empty():
				continue
			var pos: Vector3 = mi.global_transform * (hit.position as Vector3)
			var nrm: Vector3 = (mi.global_transform.basis * (hit.normal as Vector3)).normalized()
			if absf(nrm.y) < 0.8 or pos.y < -1.0:
				continue
			# Can you get onto it: a reached top beside it at about its height?
			var beside := false
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					for y: float in by_cell.get(c + Vector2i(dx, dz), []):
						if absf(y - pos.y) < 0.6:
							beside = true
			if not beside:
				continue
			if not _holds(space, pos):
				var key := Vector3(c.x, snappedf(pos.y, 0.5), c.y)
				if not seen.has(key):
					seen[key] = true
					out.append(pos)
					what[pos] = String(level.get_path_to(mi))
	return out


## Narrow slots between two floors at the same height (two roofs laid edge
## to edge with a sliver between): a runner can drop into one or snag on
## it. Between each standable top and the next cell east and south, walks
## a ray down every 0.1 m; a stretch with nothing within 1 m under the
## floor's height, SEAM_MIN..SEAM_MAX wide, is a seam.
static func _seams(space: PhysicsDirectSpaceState3D, tops: Array[Vector3]) -> Array[Vector3]:
	var level := {}
	for t: Vector3 in tops:
		level[Vector3(t.x, snappedf(t.y, 0.1), t.z)] = true
	var out: Array[Vector3] = []
	for t: Vector3 in tops:
		for d: Vector3 in [Vector3(CELL, 0, 0), Vector3(0, 0, CELL)]:
			var other := t + d
			var same := false
			for dy: float in [-0.1, 0.0, 0.1]:
				if level.has(Vector3(other.x, snappedf(t.y + dy, 0.1), other.z)):
					same = true
			if not same:
				continue
			var gap := 0
			var widest := 0
			for k in range(1, 10):
				var p := t + d * (k / 10.0)
				var q := _ray(p + Vector3(0, 0.3, 0), p - Vector3(0, 1.0, 0), 1)
				if space.intersect_ray(q).is_empty():
					gap += 1
					widest = maxi(widest, gap)
				else:
					gap = 0
			if widest * 0.1 >= SEAM_MIN and widest * 0.1 <= SEAM_MAX:
				out.append(t + d * 0.5)
	return out


## Something solid holds a runner up here: a collider top within
## FLOOR_SLACK under `pos` anywhere under the runner's feet (an edge the
## art overhangs by a few cm is no hole), or `pos` inside a solid (a
## dressed crate stack is one tall box).
static func _holds(space: PhysicsDirectSpaceState3D, pos: Vector3) -> bool:
	if _solid_at(space, pos + Vector3(0, 0.05, 0)):
		return true
	for o: Vector3 in [Vector3.ZERO, Vector3(FEET, 0, 0), Vector3(-FEET, 0, 0), Vector3(0, 0, FEET), Vector3(0, 0, -FEET)]:
		if not space.intersect_ray(_ray(pos + o + Vector3(0, 0.5, 0), pos + o - Vector3(0, FLOOR_SLACK, 0), 1)).is_empty():
			return true
	return false


static func _solid_at(space: PhysicsDirectSpaceState3D, p: Vector3) -> bool:
	var pt := PhysicsPointQueryParameters3D.new()
	pt.position = p
	pt.collision_mask = 1
	pt.exclude = _exclude
	return not space.intersect_point(pt, 1).is_empty()


static func _in_set_piece(n: Node) -> bool:
	while n != null:
		if String(n.name).begins_with("SetPiece_"):
			return true
		n = n.get_parent()
	return false


## Drops the player hard (DROP_SPEED straight down) onto each of `tops` and
## returns the ones it went through. The level's MissionRun is paused.
static func drop_through(tree: SceneTree, level: Node, tops: Array[Vector3]) -> Array[Vector3]:
	var run: Node = level.get("run")
	run.set_physics_process(false)
	var player: CharacterBody3D = level.get_node("Player")
	player.set("use_device_input", false)
	player.set("scripted_input", (load("res://player/input_frame.gd") as Script).new())
	player.set_physics_process(true)
	var out: Array[Vector3] = []
	for t: Vector3 in tops:
		player.global_position = t + Vector3(0, 1.0, 0)
		player.velocity = Vector3(0, -DROP_SPEED, 0)
		for i in DROP_TICKS:
			await tree.physics_frame
		# Down through it: well under the top and still over it (a slope or
		# a narrow top just slides you off).
		var p := player.global_position
		if p.y < t.y - 0.5 and Vector2(p.x - t.x, p.z - t.z).length() < 0.6:
			out.append(t)
	player.set_physics_process(false)
	return out


static func _ray(a: Vector3, b: Vector3, mask: int) -> PhysicsRayQueryParameters3D:
	var q := PhysicsRayQueryParameters3D.create(a, b, mask)
	q.exclude = _exclude
	return q


static func _all(n: Node) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var x: Node = stack.pop_back()
		out.append(x)
		stack.append_array(x.get_children())
	return out


static func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var x: Node = stack.pop_back()
		if x is MeshInstance3D:
			var mi := x as MeshInstance3D
			if mi.mesh != null and mi.is_visible_in_tree() and mi.layers & 1:
				out.append(mi)
		for ch: Node in x.get_children():
			stack.append(ch)
	return out


## Merge points into boxes (points within 2 m).
static func cluster(points: Array[Vector3]) -> Array[AABB]:
	var boxes: Array[AABB] = []
	for p: Vector3 in points:
		var merged := false
		for i in boxes.size():
			if boxes[i].grow(2.0).has_point(p):
				boxes[i] = boxes[i].expand(p)
				merged = true
				break
		if not merged:
			boxes.append(AABB(p, Vector3.ZERO))
	return boxes
