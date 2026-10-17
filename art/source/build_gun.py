"""Builds the scrap pistol (the player's sidearm) and exports it to glTF.

Run with Blender 4.2+ (or the `bpy` Python module):
    blender --background --python art/source/build_gun.py
    python3 art/source/build_gun.py            # with `pip install bpy`

Output: art/weapons/scrap_pistol.glb

A wasteland sidearm: worn gunmetal slide, olive frame, a rusty compensator
held on with a hose clamp, cloth tape around the grip and an orange front
sight (the runner's accent color). Every part is a beveled box, so the cel
shader catches a bright edge on each chamfer.

Conventions:
  * Coordinates below are Godot's (Y up, barrel toward -Z), in meters, and
    converted to Blender on the way in. The grip sits around the origin.
  * The muzzle is at (0, 0.032, -0.128), matching Pistol.MUZZLE_LOCAL, so
    the first-person model drops straight into Pistol.view_model.
  * Two meshes, "Frame" and "Slide" (so the slide can blow back), one
    material, colors as vertex colors (same as the runner).
"""

import math
import os
import sys

import bpy  # must come before bmesh when run as a module
import bmesh
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "weapons", "scrap_pistol.glb"))

PALETTE = {
    "metal": (0.20, 0.21, 0.23),
    "metal_dark": (0.08, 0.08, 0.09),
    "steel": (0.55, 0.56, 0.58),
    "frame": (0.33, 0.32, 0.24),
    "grip": (0.13, 0.12, 0.11),
    "tape": (0.66, 0.58, 0.44),
    "rust": (0.48, 0.25, 0.13),
    "accent": (0.96, 0.33, 0.16),
}

GRIP_TILT = -0.26  # radians about X: the grip's bottom leans back

# name, size, center, color, rotation about X (radians), parent frame
# ("grip" parts are placed in the tilted grip's own frame). Parts named in
# SLIDE_PARTS become a separate "Slide" mesh, so the game can blow it back.
SLIDE_PARTS = {"slide", "serration1", "serration2", "serration3", "port", "rear_sight", "front_sight"}
PARTS = [
    # Barrel, only seen through the port when the slide is back.
    ("barrel", (0.012, 0.012, 0.170), (0.0, 0.032, -0.025), "steel", 0.0, None),
    # Slide, with rear cocking serrations and an open ejection port.
    ("slide", (0.032, 0.040, 0.180), (0.0, 0.032, -0.015), "metal", 0.0, None),
    ("serration1", (0.034, 0.030, 0.003), (0.0, 0.030, 0.048), "metal_dark", 0.0, None),
    ("serration2", (0.034, 0.030, 0.003), (0.0, 0.030, 0.056), "metal_dark", 0.0, None),
    ("serration3", (0.034, 0.030, 0.003), (0.0, 0.030, 0.064), "metal_dark", 0.0, None),
    ("port", (0.016, 0.004, 0.038), (0.006, 0.051, -0.002), "metal_dark", 0.0, None),
    ("hammer", (0.012, 0.016, 0.012), (0.0, 0.036, 0.080), "metal", -0.35, None),
    ("rear_sight", (0.030, 0.008, 0.008), (0.0, 0.055, 0.066), "metal_dark", 0.0, None),
    ("front_sight", (0.006, 0.011, 0.006), (0.0, 0.057, -0.096), "accent", 0.0, None),
    # Scavenged compensator, clamped on.
    ("compensator", (0.036, 0.046, 0.024), (0.0, 0.030, -0.116), "rust", 0.0, None),
    ("comp_port1", (0.022, 0.004, 0.004), (0.0, 0.0535, -0.110), "metal_dark", 0.0, None),
    ("comp_port2", (0.022, 0.004, 0.004), (0.0, 0.0535, -0.120), "metal_dark", 0.0, None),
    ("bore", (0.012, 0.012, 0.004), (0.0, 0.032, -0.1265), "metal_dark", 0.0, None),
    ("clamp", (0.037, 0.050, 0.006), (0.0, 0.030, -0.097), "steel", 0.0, None),
    ("clamp_screw", (0.008, 0.010, 0.008), (0.020, 0.040, -0.097), "steel", 0.0, None),
    # Frame, rail and trigger guard.
    ("frame", (0.030, 0.018, 0.135), (0.0, 0.004, -0.028), "frame", 0.0, None),
    ("rail", (0.022, 0.006, 0.050), (0.0, -0.008, -0.070), "frame", 0.0, None),
    ("guard_bottom", (0.010, 0.006, 0.050), (0.0, -0.032, -0.010), "frame", 0.0, None),
    ("guard_front", (0.010, 0.036, 0.006), (0.0, -0.016, -0.033), "frame", 0.0, None),
    ("trigger", (0.006, 0.022, 0.006), (0.0, -0.014, -0.004), "steel", 0.25, None),
    # Grip (tilted), cloth tape and a brass-ish baseplate.
    ("grip", (0.030, 0.100, 0.046), (0.0, -0.045, 0.0), "grip", 0.0, "grip"),
    ("tape1", (0.033, 0.014, 0.049), (0.0, -0.030, 0.0), "tape", 0.0, "grip"),
    ("tape2", (0.033, 0.010, 0.049), (0.0, -0.058, 0.0), "tape", 0.0, "grip"),
    ("baseplate", (0.033, 0.008, 0.050), (0.0, -0.097, 0.001), "rust", 0.0, "grip"),
]

GRIP_ORIGIN = (0.0, 0.004, 0.045)


def to_blender(v):
    """Godot (x, y, z) -> Blender (x, -z, y); glTF export maps it back."""
    return Vector((v[0], -v[2], v[1]))


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def godot_matrix(center, rot_x, parent):
    m = Matrix.Translation(Vector(center)) @ Matrix.Rotation(rot_x, 4, "X")
    if parent == "grip":
        m = Matrix.Translation(Vector(GRIP_ORIGIN)) @ Matrix.Rotation(GRIP_TILT, 4, "X") @ m
    return m


def build_part(name, size, center, color, rot_x, parent):
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    m = godot_matrix(center, rot_x, parent) @ Matrix.Diagonal(Vector((size[0], size[1], size[2], 1.0)))
    for v in bm.verts:
        v.co = to_blender(m @ v.co)
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    # Small chamfers: the cel shader lights them as bright edges.
    bev = obj.modifiers.new("bevel", "BEVEL")
    bev.width = min(0.0018, min(size) * 0.3)
    bev.segments = 1
    bev.limit_method = "NONE"
    apply_modifiers(obj)
    paint(obj, PALETTE[color])
    return obj


def apply_modifiers(obj):
    bpy.context.view_layer.objects.active = obj
    for o in bpy.context.selected_objects:
        o.select_set(False)
    obj.select_set(True)
    for m in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def paint(obj, c):
    mesh = obj.data
    attr = mesh.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    for d in attr.data:
        d.color = (c[0], c[1], c[2], 1.0)
    mesh.color_attributes.active_color = attr


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


def build_material(obj):
    mat = bpy.data.materials.new("GunToon")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    attr = nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    mat.node_tree.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    obj.data.materials.clear()
    obj.data.materials.append(mat)


def main():
    reset_scene()
    frame = join([build_part(*p) for p in PARTS if p[0] not in SLIDE_PARTS], "Frame")
    slide = join([build_part(*p) for p in PARTS if p[0] in SLIDE_PARTS], "Slide")
    for obj in (frame, slide):
        # Flat shading: hard facets read better in cel than smoothed normals.
        for poly in obj.data.polygons:
            poly.use_smooth = False
        build_material(obj)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    for o in bpy.context.selected_objects:
        o.select_set(False)
    frame.select_set(True)
    slide.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=OUT,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=False,
        export_animations=False,
        export_vertex_color="ACTIVE",
        export_all_vertex_colors=False,
    )
    tris = sum(len(p.vertices) - 2 for o in (frame, slide) for p in o.data.polygons)
    print("wrote", OUT, "tris:", tris)


if __name__ == "__main__":
    main()
    sys.exit(0)
