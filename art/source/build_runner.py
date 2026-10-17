"""Builds the runner character (mesh + humanoid skeleton) and exports it to glTF.

Run with Blender 4.2+ (or the `bpy` Python module):
    blender --background --python art/source/build_runner.py
    python3 art/source/build_runner.py            # with `pip install bpy`

Output: art/characters/runner/runner.glb

Everything about the character lives here, so it can be rebuilt and tweaked
without hand-edited binary files. Proportions are in meters.

Conventions:
  * Bones use Godot's SkeletonProfileHumanoid names (Hips, Spine, Chest,
    LeftUpperArm, ...). Any humanoid animation retargeted in Godot maps
    straight onto this rig.
  * Rest pose is a T-pose facing -Y in Blender (+Z in glTF / Godot).
  * One mesh, one material. Body regions are painted as vertex colors, which
    the toon shader uses as the base color, so a palette change is one edit.
"""

import os
import sys

import bpy  # must come before bmesh when run as a module
import bmesh
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "characters", "runner", "runner.glb"))

# Palette (linear-ish sRGB values, shaded by the toon shader in game).
PALETTE = {
    "skin": (0.86, 0.64, 0.50),
    "hair": (0.10, 0.09, 0.10),
    "top": (0.93, 0.93, 0.95),
    "accent": (0.96, 0.33, 0.16),
    "pants": (0.17, 0.19, 0.24),
    "glove": (0.12, 0.12, 0.14),
    "shoe": (0.96, 0.96, 0.96),
    "sole": (0.96, 0.33, 0.16),
}

# Skeleton: name -> (head, tail, parent). Left side only; right is mirrored.
CENTER_BONES = [
    ("Hips", (0, 0, 0.96), (0, 0, 1.06), None),
    ("Spine", (0, 0, 1.06), (0, 0, 1.18), "Hips"),
    ("Chest", (0, 0, 1.18), (0, 0, 1.31), "Spine"),
    ("UpperChest", (0, 0, 1.31), (0, 0, 1.45), "Chest"),
    ("Neck", (0, 0, 1.45), (0, 0, 1.55), "UpperChest"),
    ("Head", (0, 0, 1.55), (0, 0, 1.76), "Neck"),
]
LEFT_BONES = [
    ("LeftShoulder", (0.03, 0, 1.42), (0.16, 0, 1.43), "UpperChest"),
    ("LeftUpperArm", (0.16, 0, 1.43), (0.43, 0, 1.43), "LeftShoulder"),
    ("LeftLowerArm", (0.43, 0, 1.43), (0.68, 0, 1.43), "LeftUpperArm"),
    ("LeftHand", (0.68, 0, 1.43), (0.85, 0, 1.43), "LeftLowerArm"),
    ("LeftUpperLeg", (0.095, 0, 0.93), (0.105, 0, 0.51), "Hips"),
    ("LeftLowerLeg", (0.105, 0, 0.51), (0.11, 0.02, 0.09), "LeftUpperLeg"),
    ("LeftFoot", (0.11, 0.02, 0.09), (0.11, -0.10, 0.03), "LeftLowerLeg"),
    ("LeftToes", (0.11, -0.10, 0.03), (0.11, -0.18, 0.03), "LeftFoot"),
]

# Body as a skin-modifier graph: (position, radius) vertices and edges.
# Radii are (x, y) half-extents of the cross-section.
BODY_VERTS = {
    "pelvis": ((0, 0.005, 0.94), (0.15, 0.10)),
    "waist": ((0, 0.0, 1.08), (0.125, 0.085)),
    "ribs": ((0, -0.005, 1.24), (0.145, 0.095)),
    "chest": ((0, -0.005, 1.37), (0.16, 0.10)),
    "neck_base": ((0, 0.005, 1.47), (0.06, 0.055)),
    "neck_top": ((0, 0.0, 1.55), (0.05, 0.05)),
}
LEFT_LIMB_VERTS = {
    "shoulder": ((0.17, 0.0, 1.42), (0.06, 0.06)),
    "elbow": ((0.43, 0.0, 1.43), (0.045, 0.045)),
    "wrist": ((0.67, 0.0, 1.43), (0.034, 0.03)),
    "knuckles": ((0.78, 0.0, 1.43), (0.045, 0.02)),
    "fingertips": ((0.85, 0.0, 1.43), (0.04, 0.018)),
    "hip": ((0.095, 0.0, 0.90), (0.085, 0.085)),
    "knee": ((0.105, 0.0, 0.51), (0.058, 0.058)),
    "ankle": ((0.11, 0.02, 0.10), (0.04, 0.04)),
    "heel": ((0.11, 0.05, 0.045), (0.045, 0.04)),
    "toe": ((0.11, -0.17, 0.04), (0.05, 0.035)),
}
BODY_EDGES = [
    ("pelvis", "waist"), ("waist", "ribs"), ("ribs", "chest"),
    ("chest", "neck_base"), ("neck_base", "neck_top"),
]
LEFT_LIMB_EDGES = [
    ("chest", "L.shoulder"), ("L.shoulder", "L.elbow"), ("L.elbow", "L.wrist"),
    ("L.wrist", "L.knuckles"), ("L.knuckles", "L.fingertips"),
    ("pelvis", "L.hip"), ("L.hip", "L.knee"), ("L.knee", "L.ankle"),
    ("L.ankle", "L.heel"), ("L.heel", "L.toe"),
]


def mirror(p):
    return (-p[0], p[1], p[2])


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def build_armature():
    arm_data = bpy.data.armatures.new("RunnerRig")
    arm = bpy.data.objects.new("Runner", arm_data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    bones = list(CENTER_BONES)
    for name, head, tail, parent in LEFT_BONES:
        bones.append((name, head, tail, parent))
        rparent = parent.replace("Left", "Right") if parent and parent.startswith("Left") else parent
        bones.append((name.replace("Left", "Right"), mirror(head), mirror(tail), rparent))
    edit = arm_data.edit_bones
    for name, head, tail, parent in bones:
        b = edit.new(name)
        b.head = head
        b.tail = tail
        # Roll so every bone's local Z points forward-ish: consistent axes
        # make procedural rotations predictable on both sides.
        b.align_roll(Vector((0, -1, 0)) if abs(Vector(tail).z - Vector(head).z) > 0.05 else Vector((0, 0, 1)))
        if parent:
            b.parent = edit[parent]
            b.use_connect = (Vector(edit[parent].tail) - Vector(head)).length < 1e-4
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


def build_body():
    verts = {}
    for k, v in BODY_VERTS.items():
        verts[k] = v
    for k, (p, r) in LEFT_LIMB_VERTS.items():
        verts["L." + k] = (p, r)
        verts["R." + k] = (mirror(p), r)
    edges = list(BODY_EDGES)
    for a, b in LEFT_LIMB_EDGES:
        edges.append((a, b))
        edges.append((a.replace("L.", "R."), b.replace("L.", "R.")))

    names = list(verts.keys())
    index = {n: i for i, n in enumerate(names)}
    mesh = bpy.data.meshes.new("RunnerBody")
    mesh.from_pydata([verts[n][0] for n in names], [(index[a], index[b]) for a, b in edges], [])
    obj = bpy.data.objects.new("RunnerBody", mesh)
    bpy.context.scene.collection.objects.link(obj)
    skin = obj.modifiers.new("Skin", "SKIN")
    skin.use_smooth_shade = True
    skin.branch_smoothing = 0.6
    for i, n in enumerate(names):
        sv = mesh.skin_vertices[0].data[i]
        sv.radius = verts[n][1]
        sv.use_root = n == "pelvis"
    sub = obj.modifiers.new("Subsurf", "SUBSURF")
    sub.levels = 2
    sub.render_levels = 2
    apply_modifiers(obj)
    return obj


def build_head():
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=14, radius=1.0)
    for v in bm.verts:
        # Slightly longer front-to-back than wide, chin tapered.
        x, y, z = v.co
        taper = 1.0 - max(0.0, -z) * 0.22
        v.co = Vector((x * 0.092 * taper, y * 0.104 * taper - max(0.0, -z) * 0.012, z * 0.118))
        v.co += Vector((0, -0.008, 1.64))
    mesh = bpy.data.meshes.new("RunnerHead")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("RunnerHead", mesh)
    bpy.context.scene.collection.objects.link(obj)
    for p in mesh.polygons:
        p.use_smooth = True
    return obj


def build_hair():
    """Short cap plus a small tied-back tail, kept chunky for cel shading."""
    parts = []
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=12, radius=1.0)
    for v in bm.verts:
        x, y, z = v.co
        v.co = Vector((x * 0.1, y * 0.113, max(z, -0.15) * 0.105)) + Vector((0, 0.002, 1.665))
    # Drop the front-lower verts so the face shows.
    drop = [v for v in bm.verts if v.co.y < -0.035 and v.co.z < 1.70]
    bmesh.ops.delete(bm, geom=drop, context="VERTS")
    mesh = bpy.data.meshes.new("RunnerHair")
    bm.to_mesh(mesh)
    bm.free()
    cap = bpy.data.objects.new("RunnerHair", mesh)
    bpy.context.scene.collection.objects.link(cap)
    solid = cap.modifiers.new("Solid", "SOLIDIFY")
    solid.thickness = 0.012
    apply_modifiers(cap)
    parts.append(cap)

    tail = bpy.data.meshes.new("RunnerTail")
    tail.from_pydata([(0, 0.10, 1.70), (0, 0.15, 1.63), (0, 0.16, 1.55)], [(0, 1), (1, 2)], [])
    tobj = bpy.data.objects.new("RunnerTail", tail)
    bpy.context.scene.collection.objects.link(tobj)
    skin = tobj.modifiers.new("Skin", "SKIN")
    for sv, r in zip(tail.skin_vertices[0].data, [(0.035, 0.03), (0.03, 0.028), (0.012, 0.012)]):
        sv.radius = r
    tsub = tobj.modifiers.new("Subsurf", "SUBSURF")
    tsub.levels = 1
    apply_modifiers(tobj)
    parts.append(tobj)
    return parts


def apply_modifiers(obj):
    bpy.context.view_layer.objects.active = obj
    for o in bpy.context.selected_objects:
        o.select_set(False)
    obj.select_set(True)
    for m in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def join(objs, name):
    for o in bpy.context.selected_objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    objs[0].name = name
    objs[0].data.name = name
    return objs[0]


def region_for(co, bone):
    """Which palette entry a vertex gets, from its dominant bone and position."""
    x, y, z = co
    if bone in ("Head", "Neck"):
        return "skin"
    if bone.endswith("Hand"):
        return "glove"
    if bone.endswith("LowerArm"):
        # Sleeves stop just below the elbow; a thin accent cuff.
        return "accent" if abs(x) < 0.47 else "skin"
    if bone.endswith("Foot") or bone.endswith("Toes"):
        return "sole" if z < 0.02 else "shoe"
    if bone.endswith("LowerLeg"):
        return "shoe" if z < 0.13 else "pants"
    if bone.endswith("UpperLeg") or bone == "Hips":
        return "pants" if z < 0.99 else "top"
    # Torso and upper arms: white top with an accent stripe across the chest
    # and down the outside of each arm, for a readable silhouette in motion.
    if abs(z - 1.30) < 0.018 and y < 0.0:
        return "accent"
    if bone.endswith("UpperArm") and z > 1.455:
        return "accent"
    return "top"


def paint_and_skin(body, arm):
    for o in bpy.context.selected_objects:
        o.select_set(False)
    body.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")

    mesh = body.data
    groups = {g.index: g.name for g in body.vertex_groups}
    color_attr = mesh.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    hair_ids = set(mesh.attributes["is_hair"].data[i].value and i or -1 for i in range(len(mesh.vertices)))
    hair_ids.discard(-1)
    for v in mesh.vertices:
        best, weight = "Hips", -1.0
        for g in v.groups:
            if g.weight > weight:
                best, weight = groups[g.group], g.weight
        region = "hair" if v.index in hair_ids else region_for(v.co, best)
        c = PALETTE[region]
        color_attr.data[v.index].color = (c[0], c[1], c[2], 1.0)
    mesh.color_attributes.active_color = color_attr

    # Hair and head follow the head bone rigidly.
    head_group = body.vertex_groups["Head"]
    head_ids = [v.index for v in mesh.vertices if v.index in hair_ids or v.co.z > 1.53]
    for g in body.vertex_groups:
        if g.name != "Head":
            g.remove(head_ids)
    head_group.add(head_ids, 1.0, "REPLACE")


def tag(obj, value):
    attr = obj.data.attributes.new("is_hair", "BOOLEAN", "POINT")
    for d in attr.data:
        d.value = value


def build_material(obj):
    mat = bpy.data.materials.new("RunnerToon")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    attr = nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    mat.node_tree.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.8
    obj.data.materials.clear()
    obj.data.materials.append(mat)


def main():
    reset_scene()
    arm = build_armature()
    body = build_body()
    head = build_head()
    hair = build_hair()
    tag(body, False)
    tag(head, False)
    for h in hair:
        tag(h, True)
    body = join([body, head] + hair, "RunnerMesh")
    # Merge the doubled verts that the skin modifier leaves at branch joins.
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=0.0005)
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    paint_and_skin(body, arm)
    body.data.attributes.remove(body.data.attributes["is_hair"])
    build_material(body)

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    for o in bpy.context.selected_objects:
        o.select_set(False)
    arm.select_set(True)
    body.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=OUT,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=False,
        export_skins=True,
        export_animations=False,
        export_vertex_color="ACTIVE",
        export_all_vertex_colors=False,
    )
    print("wrote", OUT, "verts:", len(body.data.vertices), "tris:", sum(len(p.vertices) - 2 for p in body.data.polygons))


if __name__ == "__main__":
    main()
    sys.exit(0)
