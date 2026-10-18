extends RefCounted
## Finds z-fighting: faces of two different meshes with different materials
## lying in the same plane, facing the same way and overlapping. The renderer
## can't tell which is in front, so the two looks flicker through each other.
## Used by art/tools/coplanar_audit.gd and tests/test_coplanar.gd.

## Faces closer than this along their normal count as the same plane
## (the depth buffer resolves anything further apart at game distances).
const PLANE_TOL := 0.00005
## Overlaps smaller than this (m²) are ignored (edges that only touch).
const MIN_AREA := 0.02


## Every visible static mesh face under `root`, as world-space triangles.
## Moving things (the player, enemies, pickups) are skipped.
static func collect(root: Node) -> Array:
	var tris: Array = []
	var id := 0
	for g: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := g as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree() or _moving(mi, root):
			continue
		var xf := mi.global_transform
		var faces := mi.mesh.get_faces()
		# ArtLook grows boxes a little when drawn (see ArtLook.box_grow).
		var grow: Variant = mi.get_meta("box_grow", 0.0) if mi.mesh is BoxMesh else 0.0
		if grow is float and grow > 0.0:
			for i in faces.size():
				faces[i] += faces[i].sign() * grow
		var mat := _material(mi)
		var lift: float = mi.get_meta("face_lift", 0.0)
		for i in range(0, faces.size(), 3):
			var a: Vector3 = xf * faces[i]
			var b: Vector3 = xf * faces[i + 1]
			var c: Vector3 = xf * faces[i + 2]
			# Godot winds front faces clockwise: this points out of the face.
			var n := (c - a).cross(b - a)
			if n.length_squared() < 1e-8:
				continue
			n = n.normalized()
			if n.y < -0.9 and maxf(a.y, maxf(b.y, c.y)) < 0.05:
				continue  # the underside of something standing on the ground
			tris.append([a, b, c, n, n.dot(a) + lift, id, mat, mi])
		id += 1
	return tris


## Pairs of meshes that fight, worst first:
## [{a: MeshInstance3D, b: MeshInstance3D, area: float, at: Vector3}].
static func find(root: Node) -> Array:
	var buckets := {}
	for t: Array in collect(root):
		var n: Vector3 = t[3]
		var key := Vector4i(roundi(n.x * 200), roundi(n.y * 200), roundi(n.z * 200), floori(t[4] / PLANE_TOL))
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(t)
	var pairs := {}
	for key: Vector4i in buckets:
		var here: Array = buckets[key]
		var next_key := Vector4i(key.x, key.y, key.z, key.w + 1)
		var group: Array = here + (buckets[next_key] if buckets.has(next_key) else [])
		_sweep(group, here.size(), pairs)
	var out: Array = pairs.values()
	out.sort_custom(func(p, q): return p.area > q.area)
	return out.filter(func(p): return p.area >= MIN_AREA)


## Sweep and prune along the plane's first axis. Only pairs with at least
## one triangle from the first `own` entries count, so neighboring buckets
## aren't compared twice.
static func _sweep(group: Array, own: int, pairs: Dictionary) -> void:
	if group.size() < 2:
		return
	var n: Vector3 = group[0][3]
	var u := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := n.cross(u)
	var items: Array = []
	for i in group.size():
		var t: Array = group[i]
		var poly := PackedVector2Array([
			Vector2(u.dot(t[0]), v.dot(t[0])), Vector2(u.dot(t[1]), v.dot(t[1])), Vector2(u.dot(t[2]), v.dot(t[2]))])
		var lo := Vector2(minf(poly[0].x, minf(poly[1].x, poly[2].x)), minf(poly[0].y, minf(poly[1].y, poly[2].y)))
		var hi := Vector2(maxf(poly[0].x, maxf(poly[1].x, poly[2].x)), maxf(poly[0].y, maxf(poly[1].y, poly[2].y)))
		items.append([lo, hi, poly, t, i < own])
	items.sort_custom(func(p, q): return p[0].x < q[0].x)
	for i in items.size():
		var a: Array = items[i]
		for j in range(i + 1, items.size()):
			var b: Array = items[j]
			if b[0].x >= a[1].x:
				break
			if not (a[4] or b[4]):
				continue
			var ta: Array = a[3]
			var tb: Array = b[3]
			if ta[5] == tb[5] or ta[6] == tb[6]:
				continue
			if absf(ta[4] - tb[4]) > PLANE_TOL or b[0].y >= a[1].y or a[0].y >= b[1].y:
				continue
			var area := _overlap(a[2], b[2])
			if area <= 0.0005:
				continue
			var k := Vector2i(mini(ta[5], tb[5]), maxi(ta[5], tb[5]))
			if not pairs.has(k):
				pairs[k] = {a = ta[7], b = tb[7], area = 0.0, at = (ta[0] + ta[1] + ta[2]) / 3.0}
			pairs[k].area += area


## Overlap area of two triangles (convex clip, either winding).
static func _overlap(p: PackedVector2Array, q: PackedVector2Array) -> float:
	if _signed_area(p) < 0.0:
		p = PackedVector2Array([p[0], p[2], p[1]])
	if _signed_area(q) < 0.0:
		q = PackedVector2Array([q[0], q[2], q[1]])
	var out := p
	for i in 3:
		var e0 := q[i]
		var e1 := q[(i + 1) % 3]
		var inp := out
		out = PackedVector2Array()
		for j in inp.size():
			var a := inp[j]
			var b := inp[(j + 1) % inp.size()]
			var da := (e1 - e0).cross(a - e0)
			var db := (e1 - e0).cross(b - e0)
			if da >= 0.0:
				out.append(a)
			if (da >= 0.0) != (db >= 0.0):
				out.append(a + (b - a) * (da / (da - db)))
		if out.size() < 3:
			return 0.0
	return absf(_signed_area(out))


static func _signed_area(poly: PackedVector2Array) -> float:
	var s := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		s += a.x * b.y - b.x * a.y
	return s * 0.5


## What a face looks like: two faces that look the same can't flicker.
static func _material(mi: MeshInstance3D) -> String:
	var m: Material = mi.material_override
	if m == null and mi.mesh.get_surface_count() > 0:
		m = mi.get_active_material(0)
	if m is ShaderMaterial and (m as ShaderMaterial).shader:
		var sm := m as ShaderMaterial
		return "%s|%s|%s|%s" % [sm.shader.get_rid().get_id(), sm.get_shader_parameter("base_color"),
			sm.get_shader_parameter("surface"), sm.get_shader_parameter("grid_strength")]
	return "o%d" % (m if m else mi).get_instance_id()


static func _moving(n: Node, root: Node) -> bool:
	var p := n
	while p != null and p != root:
		if p is CharacterBody3D or p is RigidBody3D or p is AnimatableBody3D or p is Skeleton3D:
			return true
		p = p.get_parent()
	return false
