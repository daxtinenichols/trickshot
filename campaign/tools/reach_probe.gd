extends SceneTree
## Where can a runner get to? Loads a mission (or a map scene) and floods
## the standable surfaces from the start, with generous movement limits
## (steps, 3 m climbs onto a ledge, running jumps, any drop), then prints
## the reachable places that match a filter, grouped into boxes.
##   godot --headless --path . -s res://campaign/tools/reach_probe.gd -- <mission id | res://scene.tscn> [min_y] [max_z]
## Prints the reachable surfaces with y >= min_y (default 12.6) or z < max_z.
## Rough by design: it finds leaks to look at, it doesn't prove a line works.

const CELL := 0.5
const STEP := 0.6        # walk up
const CLIMB := 3.2       # climb / mantle onto a ledge right next to you
const JUMP_UP := 1.4     # onto a higher top a running jump away
const JUMP_LONG := 4.0   # level or downhill running jump (gaps wider than this are rare indoors)
const HEADROOM := 1.0

var surfaces := {}       # Vector2i -> Array[float] (standable tops)
var min_y_cut := 12.6
var max_z_cut := -INF
var parent := {}
## Left out of the flood (e.g. the store's roof hatch, to find other ways up).
var skip_box := AABB()
var entries: Array = []  # [from, to]: steps from below min_y onto it


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var id: String = args[0] if args.size() > 0 else "l4_1_meridian_mall"
	var min_y := float(args[1]) if args.size() > 1 else 12.6
	var max_z := float(args[2]) if args.size() > 2 else -INF
	var level := await _load(id)
	var start: Vector3 = (level.get_node("Player") as Node3D).global_position
	var space := (level as Node3D).get_world_3d().direct_space_state
	var rect := Rect2(-62, -470, 124, 530)
	var t0 := Time.get_ticks_msec()
	_space = space
	_scan(space, rect)
	print("scanned %d columns in %d ms" % [surfaces.size(), Time.get_ticks_msec() - t0])
	min_y_cut = min_y
	max_z_cut = max_z
	if args.size() > 3:
		var v := args[3].split_floats(",")
		skip_box = AABB(Vector3(v[0], v[1], v[2]), Vector3(v[3], v[4], v[5]))
	var reached := _flood(start)
	if OS.has_environment("PROBE_TO"):
		var v := OS.get_environment("PROBE_TO").split_floats(",")
		var target := Vector3(v[0], v[1], v[2])
		var best_k := Vector3.ZERO
		var best := INF
		for k: Vector3 in reached:
			if k.distance_to(target) < best:
				best = k.distance_to(target)
				best_k = k
		var pts: Array[String] = []
		var k := best_k
		var n := 0
		while parent.has(k) and n < 20000:
			var pk: Vector3 = parent[k]
			if absf(pk.y - k.y) > 0.4 or pk.distance_to(k) > 1.0 or n % 40 == 0:
				pts.push_front(str(pk.snapped(Vector3.ONE * 0.1)))
			k = pk
			n += 1
		print("  path to %s: %s" % [best_k, " ".join(pts)])
	var shown := {}
	for e: Array in entries:
		var to: Vector3 = e[1]
		var bucket := Vector3i(int(to.x / 4.0), 0, int(to.z / 4.0))
		if shown.has(bucket):
			continue
		shown[bucket] = true
		print("  way up  %s -> %s" % [(e[0] as Vector3).snapped(Vector3.ONE * 0.1), to.snapped(Vector3.ONE * 0.1)])
		if OS.has_environment("PROBE_TRACE"):
			var k: Vector3 = to
			var pts: Array[String] = []
			var n := 0
			while parent.has(k) and n < 5000:
				var pk: Vector3 = parent[k]
				if absf(pk.y - k.y) > 0.4 or n % 25 == 0:
					pts.push_front(str(pk.snapped(Vector3.ONE * 0.1)))
				k = pk
				n += 1
			print("    via " + " ".join(pts))
	print("reachable surfaces: %d" % reached.size())
	var hits: Array[Vector3] = []
	for k: Vector3 in reached:
		if k.y >= min_y or k.z < max_z:
			hits.append(k)
	for b: AABB in _cluster(hits):
		print("  reach  x %.1f..%.1f  y %.1f..%.1f  z %.1f..%.1f" % [b.position.x, b.end.x, b.position.y, b.end.y, b.position.z, b.end.z])
	quit()


func _load(id: String) -> Node:
	var level: Node
	if id.ends_with(".tscn"):
		level = (load(id) as PackedScene).instantiate()
	else:
		var campaign: Script = load("res://campaign/campaign.gd")
		campaign.persist = false
		var all: Array = campaign.missions()
		for i in all.size():
			if all[i].id == id:
				campaign.current = i
		level = (load("res://campaign/mission.tscn") as PackedScene).instantiate()
	root.add_child(level)
	var p: Node = level.get_node("Player")
	p.set("use_device_input", false)
	p.set_physics_process(false)
	for i in 4:
		await physics_frame
	return level


## Every standable top in every column (rays straight down, through solids).
func _scan(space: PhysicsDirectSpaceState3D, rect: Rect2) -> void:
	var nx := int(rect.size.x / CELL)
	var nz := int(rect.size.y / CELL)
	for ix in nx:
		for iz in nz:
			var x := rect.position.x + (ix + 0.5) * CELL
			var z := rect.position.y + (iz + 0.5) * CELL
			var tops: Array[float] = []
			var ceiling := 80.0
			var y := 80.0
			var guard := 0
			while y > -6.0 and guard < 24:
				guard += 1
				var q := PhysicsRayQueryParameters3D.create(Vector3(x, y, z), Vector3(x, -6.0, z), 1)
				var r := space.intersect_ray(q)
				if r.is_empty():
					break
				var hy: float = r.position.y
				if (r.normal as Vector3).y > 0.6 and ceiling - hy >= HEADROOM:
					tops.append(hy)
				# Walk down through this solid: the next ray starts under it.
				var probe := hy - 0.05
				var steps := 0
				while steps < 400:
					steps += 1
					var pt := PhysicsPointQueryParameters3D.new()
					pt.position = Vector3(x, probe, z)
					pt.collision_mask = 1
					if space.intersect_point(pt, 1).is_empty():
						break
					probe -= 0.1
				ceiling = probe
				y = probe - 0.01
			if not tops.is_empty():
				surfaces[Vector2i(ix, iz)] = tops
	_origin = rect.position


var _origin := Vector2.ZERO


func _cell_of(p: Vector3) -> Vector2i:
	return Vector2i(int((p.x - _origin.x) / CELL), int((p.z - _origin.y) / CELL))


func _world(c: Vector2i, y: float) -> Vector3:
	return Vector3(_origin.x + (c.x + 0.5) * CELL, y, _origin.y + (c.y + 0.5) * CELL)


func _flood(start: Vector3) -> Dictionary:
	var seen := {}
	var c0 := _cell_of(start)
	var best := -1.0
	var best_d := INF
	for y: float in surfaces.get(c0, []):
		if absf(y - start.y) < best_d:
			best_d = absf(y - start.y)
			best = y
	var queue: Array = [[c0, best]]
	seen[_world(c0, best)] = true
	var near := int(ceil(1.2 / CELL))
	var far := int(ceil(JUMP_LONG / CELL))
	while not queue.is_empty():
		var item: Array = queue.pop_back()
		var c: Vector2i = item[0]
		var y: float = item[1]
		for dx in range(-far, far + 1, 1):
			for dz in range(-far, far + 1, 1):
				var d2 := dx * dx + dz * dz
				if d2 > far * far or d2 == 0:
					continue
				var n := c + Vector2i(dx, dz)
				if not surfaces.has(n):
					continue
				var nw := _world(n, 0)
				if skip_box.has_point(Vector3(nw.x, 10, nw.z)):
					continue
				var adjacent := absi(dx) <= 1 and absi(dz) <= 1
				var close := absi(dx) <= near and absi(dz) <= near
				for ny: float in surfaces[n]:
					var up := ny - y
					var ok := up <= 0.0
					if adjacent and up <= STEP:
						ok = true
					elif close and up <= CLIMB:
						ok = true
					elif up <= JUMP_UP:
						ok = true
					if not ok:
						continue
					var key := _world(n, ny)
					if seen.has(key):
						continue
					if _blocked(_world(c, y), key):
						continue
					seen[key] = true
					parent[key] = _world(c, y)
					var cw := _world(c, y)
					if (y < min_y_cut - 1.0 and ny >= min_y_cut) or (cw.z >= max_z_cut and key.z < max_z_cut):
						entries.append([_world(c, y), key])
					queue.append([n, ny])
	return seen


var _space: PhysicsDirectSpaceState3D


## A wall between two spots (a jump can't pass through it): rays at knee
## and head height, above the higher of the two.
func _blocked(a: Vector3, b: Vector3) -> bool:
	var top := maxf(a.y, b.y)
	for h: float in [0.7, 1.6]:
		var q := PhysicsRayQueryParameters3D.create(Vector3(a.x, top + h, a.z), Vector3(b.x, top + h, b.z), 1)
		if not _space.intersect_ray(q).is_empty():
			return true
	# A climb: room over your head to get up there.
	if b.y > a.y + 0.3:
		var u := PhysicsRayQueryParameters3D.create(Vector3(a.x, a.y + 1.0, a.z), Vector3(a.x, b.y + 1.6, a.z), 1)
		if not _space.intersect_ray(u).is_empty():
			return true
	# A drop: nothing between you and where you land (no falling through a
	# floor you were standing beside).
	if b.y < a.y - 0.3:
		var d := PhysicsRayQueryParameters3D.create(Vector3(b.x, a.y + 0.9, b.z), Vector3(b.x, b.y + 0.1, b.z), 1)
		if not _space.intersect_ray(d).is_empty():
			return true
	return false


## Merge reachable points into boxes (points within 1.5 m).
func _cluster(points: Array[Vector3]) -> Array[AABB]:
	var boxes: Array[AABB] = []
	for p: Vector3 in points:
		var merged := false
		for i in boxes.size():
			if boxes[i].grow(1.5).has_point(p):
				boxes[i] = boxes[i].expand(p)
				merged = true
				break
		if not merged:
			boxes.append(AABB(p, Vector3.ZERO))
	return boxes
