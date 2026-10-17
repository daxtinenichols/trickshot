extends RefCounted
## Dresses practice targets (ShootingTarget, group "targets") as junk the
## courier set up to shoot at: a scrap dummy, a painted steel plate or a
## plank of bottles. Visual only: the target's hitboxes, health, motion and
## falling over are untouched. The dress hangs off the target's pivot, so it
## moves and falls with it, and stays inside the hitboxes (body 0.5 x 1.35 x
## 0.28 m, head a 0.18 m ball at 1.62 m), so what you see is what you hit.
## The body still reads as faded red and the head as bright, and both flash
## when hit. Loaded by path from ArtLook (no class_name).

const STYLES := ["dummy", "plate", "bottles"]
const LOOK_PATH := "res://art/look/target_look.gd"


## Dresses `target`. Returns the node it added (a child of the target's
## pivot) or null. The target's own meshes are hidden and listed in `hidden`
## so the caller can show them again.
static func dress(target: Node3D, look: Object, hidden: Array) -> Node3D:
	var pivot: Node3D = null
	for c in target.get_children():
		if c is Node3D and c.get_child_count() > 0 and not (c is Label3D):
			pivot = c
			break
	if pivot == null or pivot.has_node("TargetLook"):
		return null
	var style: String = target.get_meta("dress", "")
	if not STYLES.has(style):
		style = STYLES[int(_hash(target.global_position) * STYLES.size()) % STYLES.size()]
	var script := load(LOOK_PATH) as Script
	if script == null:
		return null
	for c in pivot.get_children():
		if c is MeshInstance3D and c.visible:
			c.visible = false
			hidden.append(c)
	var root: Node3D = script.new()
	root.name = "TargetLook"
	root.look = look
	match style:
		"dummy": root.dummy()
		"plate": root.plate()
		"bottles": root.bottles()
	root.set_meta("style", style)
	pivot.add_child(root)
	if target.has_signal("damaged"):
		target.damaged.connect(root.hit)
	return root


static func _hash(p: Vector3) -> float:
	var v := sin(snappedf(p.x, 0.1) * 12.9898 + snappedf(p.y, 0.1) * 4.1414 + snappedf(p.z, 0.1) * 78.233) * 43758.5453
	return v - floorf(v)
