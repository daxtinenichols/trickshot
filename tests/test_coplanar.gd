extends TestCase
## No flicker: once the look is on, no two surfaces with different looks lie
## in the same plane anywhere in the campaign or the base maps (z-fighting:
## the renderer can't pick one, so they shimmer through each other).

const MISSION := preload("res://campaign/mission.tscn")
const COPLANAR := preload("res://art/look/coplanar.gd")
const BASES := ["res://maps/rooftops.tscn", "res://maps/combo_park.tscn", "res://maps/mall.tscn", "res://levels/sandbox.tscn"]
## What may still overlap per level (m²): a prop's foot on a box, a few
## centimeters of a banked strip's corner.
const MAX_AREA := 0.5
const MAX_PAIR := 0.25

var level: Node


func before_each() -> void:
	Campaign.persist = false
	Campaign.reset_progress()
	Campaign.unlock_all = true


func after_each() -> void:
	if is_instance_valid(level):
		level.queue_free()
	level = null
	await tree.process_frame


func _open(id: String) -> void:
	if id.begins_with("res://"):
		level = (load(id) as PackedScene).instantiate()
	else:
		var all: Array = Campaign.missions()
		for i in all.size():
			if all[i].id == id:
				Campaign.current = i
		level = MISSION.instantiate()
	tree.root.add_child(level)
	var p := level.get_node_or_null("Player")
	if p:
		p.use_device_input = false
		p.set_physics_process(false)
	for i in 3:
		await tree.physics_frame
	tree.root.get_node("ArtLook")._apply_all(level)
	await tree.process_frame


func _fights(id: String) -> Array:
	await _open(id)
	var found: Array = COPLANAR.find(level)
	level.queue_free()
	level = null
	await tree.process_frame
	return found


func test_no_two_looks_share_a_plane() -> void:
	var ids: Array = []
	for m: Dictionary in Campaign.missions():
		ids.append(m.id)
	for id: String in ids + BASES:
		var found: Array = await _fights(id)
		var area := 0.0
		for f: Dictionary in found:
			area += f.area
		var worst: Dictionary = found[0] if not found.is_empty() else {area = 0.0}
		check(area <= MAX_AREA and worst.area <= MAX_PAIR,
			"%s: %d flickering overlaps, %.2f m² (worst %.2f m² at %s); see art/tools/coplanar_audit.gd"
			% [id, found.size(), area, worst.area, worst.get("at", Vector3.ZERO)])


## The audit itself: two flush boxes with different looks fight until the
## look grows them apart; one look on both never counts.
func test_flush_boxes_are_drawn_apart() -> void:
	var look := tree.root.get_node("ArtLook")
	level = Node3D.new()
	tree.root.add_child(level)
	var a := _box(Vector3(4, 1, 4), Vector3.ZERO, look.wasteland_material("FLOOR"))
	var b := _box(Vector3(1, 0.1, 1), Vector3(0, 0.45, 0), look.wasteland_material("PARKOUR"))
	var same := _box(Vector3(1, 0.1, 1), Vector3(1.5, 0.45, 1.5), look.wasteland_material("FLOOR"))
	check(COPLANAR.find(level).size() == 1, "a plate flush on a floor fights it (and one look on both doesn't)")
	look.layer_box(a)
	look.layer_box(b)
	look.layer_box(same)
	check(COPLANAR.find(level).is_empty(), "grown apart, nothing fights")
	check(float(b.get_meta("box_grow")) > float(a.get_meta("box_grow")), "the detail draws over the floor")
	check(float(a.get_meta("box_grow")) <= 0.006 and float(b.get_meta("box_grow")) <= 0.006, "the growth stays a few millimeters")


func _box(size: Vector3, at: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = at
	level.add_child(mi)
	return mi
