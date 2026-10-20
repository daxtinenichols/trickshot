extends RefCounted
## Finds things standing inside the level: enemies whose bodies overlap a
## wall, and props sunk into walls or into each other. Used by
## art/tools/clip_audit.gd and tests/test_coplanar.gd.

## How deep (m) an overlap must go to count: resting on a floor or leaning on
## a wall is fine.
const DEPTH := 0.08


## [{what: "enemy"|"prop", node: Node3D, at: Vector3, into: String}]
static func find(root: Node) -> Array:
	var out: Array = []
	var space := (root as Node3D).get_world_3d().direct_space_state
	for e: Node in root.get_tree().get_nodes_in_group("enemies"):
		if not root.is_ancestor_of(e) or not (e is CollisionObject3D):
			continue
		var hit := _overlap(space, e as CollisionObject3D)
		if hit != "":
			out.append({what = "enemy", node = e, at = (e as Node3D).global_position, into = hit})
	for body: Node in root.find_children("*", "StaticBody3D", true, false):
		if body.has_meta("prop"):
			var hit := _overlap(space, body as CollisionObject3D)
			if hit != "":
				out.append({what = "prop " + str(body.get_meta("prop")), node = body, at = (body as Node3D).global_position, into = hit})
	return out


## The first static thing a body's shapes, shrunk by DEPTH all round, still
## overlap ("" when clear).
static func _overlap(space: PhysicsDirectSpaceState3D, body: CollisionObject3D) -> String:
	for c in body.get_children():
		var cs := c as CollisionShape3D
		if cs == null or cs.disabled or cs.shape == null:
			continue
		var shrunk := _shrunk(cs.shape)
		if shrunk == null:
			continue
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = shrunk
		q.transform = cs.global_transform
		q.collision_mask = 1
		q.exclude = [body.get_rid()]
		var foot := cs.global_position.y - _half_height(cs.shape)
		for h: Dictionary in space.intersect_shape(q, 8):
			var other := h.collider as Node
			if other is StaticBody3D and other != body and _top(other as Node3D) > foot + 0.35:
				var size := ""
				for oc in other.get_children():
					if oc is CollisionShape3D and (oc as CollisionShape3D).shape is BoxShape3D:
						size = str(((oc as CollisionShape3D).shape as BoxShape3D).size.snappedf(0.01))
				return "%s %s %s %s" % [other.get_meta("prop", other.name), other.get_meta("kind", ""), other.get_meta("look", ""), size]
	return ""


## The top of a body's boxes (a floor, a pavement slab: a prop bedded in one
## is fine).
static func _top(body: Node3D) -> float:
	var top := -INF
	for c in body.get_children():
		var cs := c as CollisionShape3D
		if cs and cs.shape:
			top = maxf(top, cs.global_position.y + _half_height(cs.shape))
	return top


static func _half_height(s: Shape3D) -> float:
	if s is BoxShape3D:
		return (s as BoxShape3D).size.y * 0.5
	if s is CapsuleShape3D:
		return (s as CapsuleShape3D).height * 0.5
	if s is CylinderShape3D:
		return (s as CylinderShape3D).height * 0.5
	if s is SphereShape3D:
		return (s as SphereShape3D).radius
	return 0.0


static func _shrunk(s: Shape3D) -> Shape3D:
	if s is BoxShape3D:
		var b := BoxShape3D.new()
		b.size = ((s as BoxShape3D).size - Vector3.ONE * DEPTH * 2.0).max(Vector3.ONE * 0.02)
		return b
	if s is CapsuleShape3D:
		var c := CapsuleShape3D.new()
		c.radius = maxf((s as CapsuleShape3D).radius - DEPTH, 0.02)
		c.height = maxf((s as CapsuleShape3D).height - DEPTH * 2.0, c.radius * 2.0)
		return c
	if s is CylinderShape3D:
		var y := CylinderShape3D.new()
		y.radius = maxf((s as CylinderShape3D).radius - DEPTH, 0.02)
		y.height = maxf((s as CylinderShape3D).height - DEPTH * 2.0, 0.04)
		return y
	if s is SphereShape3D:
		var p := SphereShape3D.new()
		p.radius = maxf((s as SphereShape3D).radius - DEPTH, 0.02)
		return p
	return null
