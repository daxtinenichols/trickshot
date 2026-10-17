extends RefCounted
## The prop kit: post-apocalyptic set dressing that the player can also run
## on (crates, wrecks, barricades, containers, the Host's loudspeakers...).
##
## Models come from art/source/build_props.py, which also writes
## props.json: each prop's size, box colliders and tags. Use it from a map
## builder:
##
##     const PropKit := preload("res://art/props/prop_kit.gd")
##     PropKit.place(_root, "car_wreck", Transform3D(Basis(Vector3.UP, 0.4), pos))
##
## Origin is each prop's bottom center, front toward -Z. Collision is the
## catalog's boxes on the world layer, so gameplay treats a prop like any
## other geometry: a 0.9 m crate vaults, a container side wallruns.
##
## Everything loads by path at runtime (no class_name, no preloaded .glb), so
## a model the editor hasn't imported yet falls back to gray boxes of the
## same size instead of breaking the map.

const DIR := "res://art/props/"
const CATALOG_PATH := "res://art/props/props.json"
const SHADER_PATH := "res://art/props/prop.gdshader"
const FALLBACK_SHADER_PATH := "res://levels/graybox.gdshader"

static var _catalog := {}
static var _scenes := {}
static var _material: Material
static var _fallback: Material


## Every prop's catalog entry, by name.
static func catalog() -> Dictionary:
	if _catalog.is_empty():
		var f := FileAccess.open(CATALOG_PATH, FileAccess.READ)
		if f == null:
			push_warning("PropKit: no catalog at %s" % CATALOG_PATH)
			return _catalog
		var data: Variant = JSON.parse_string(f.get_as_text())
		if data is Dictionary:
			_catalog = data
	return _catalog


static func names() -> PackedStringArray:
	var out := PackedStringArray(catalog().keys())
	out.sort()
	return out


static func has(prop_name: String) -> bool:
	return catalog().has(prop_name)


## Bounding size (x, y, z) in meters.
static func size_of(prop_name: String) -> Vector3:
	var s: Array = catalog().get(prop_name, {}).get("size", [1, 1, 1])
	return Vector3(s[0], s[1], s[2])


static func tags_of(prop_name: String) -> PackedStringArray:
	return PackedStringArray(catalog().get(prop_name, {}).get("tags", []))


## Adds prop `prop_name` under `parent` at `xform` and returns its root: a
## StaticBody3D with the catalog's colliders (or a plain Node3D for props
## without any, or when `collide` is false). Returns null for an unknown name.
static func place(parent: Node, prop_name: String, xform := Transform3D.IDENTITY, collide := true) -> Node3D:
	var entry: Dictionary = catalog().get(prop_name, {})
	if entry.is_empty():
		push_warning("PropKit: unknown prop '%s'" % prop_name)
		return null
	var colliders: Array = entry.get("colliders", [])
	var root: Node3D
	if collide and not colliders.is_empty():
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		for c: Dictionary in colliders:
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = _vec(c.size)
			shape.shape = box
			shape.transform = _collider_transform(c)
			body.add_child(shape)
		root = body
	else:
		root = Node3D.new()
	root.name = prop_name.to_pascal_case()
	root.transform = xform
	root.set_meta("prop", prop_name)
	# Gameplay never reads kinds; this keeps graybox tools and ArtLook happy.
	root.set_meta("kind", "NEUTRAL")
	var model := _model(prop_name)
	if model != null:
		root.add_child(model)
	else:
		_add_fallback(root, colliders if not colliders.is_empty() else [{"size": entry.get("size", [1, 1, 1]), "center": [0, entry.get("size", [1, 1, 1])[1] * 0.5, 0], "rot": [0, 0, 0]}])
	parent.add_child(root)
	return root


## Collider transform from a catalog entry (rotation in degrees, Godot's
## YXZ order, same as build_props.py).
static func _collider_transform(c: Dictionary) -> Transform3D:
	var r := _vec(c.get("rot", [0, 0, 0]))
	var b := Basis.from_euler(Vector3(deg_to_rad(r.x), deg_to_rad(r.y), deg_to_rad(r.z)))
	return Transform3D(b, _vec(c.center))


static func _model(prop_name: String) -> Node3D:
	if not _scenes.has(prop_name):
		var path := DIR + prop_name + ".glb"
		_scenes[prop_name] = load(path) if ResourceLoader.exists(path) else null
	var scene := _scenes[prop_name] as PackedScene
	if scene == null:
		return null
	var model := scene.instantiate() as Node3D
	if model == null:
		return null
	model.name = "Model"
	var mat := material()
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = mat
	return model


## The shared prop material (vertex colors, cel lit, dust and grime).
static func material() -> Material:
	if _material == null:
		var shader: Shader = load(SHADER_PATH) if ResourceLoader.exists(SHADER_PATH) else null
		if shader == null:
			var m := StandardMaterial3D.new()
			m.vertex_color_use_as_albedo = true
			_material = m
		else:
			var sm := ShaderMaterial.new()
			sm.shader = shader
			_material = sm
	return _material


static func _add_fallback(root: Node3D, boxes: Array) -> void:
	if _fallback == null:
		var sm := ShaderMaterial.new()
		sm.shader = load(FALLBACK_SHADER_PATH)
		sm.set_shader_parameter("base_color", Color(0.62, 0.6, 0.56))
		_fallback = sm
	for c: Dictionary in boxes:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = _vec(c.size)
		mi.mesh = bm
		mi.transform = _collider_transform(c)
		mi.material_override = _fallback
		root.add_child(mi)


static func _vec(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])
