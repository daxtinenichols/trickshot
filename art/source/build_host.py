"""Builds the Host (the raider warlord who runs the radio show) and exports
him to glTF.

Run with Blender 4.2+ (or the `bpy` Python module):
    blender --background --python art/source/build_host.py
    python3 art/source/build_host.py            # with `pip install bpy`

Output: art/characters/host/host.glb

He's built on the runners' exact skeleton (build_runner.py's armature,
reused as is), so every RunnerPoses pose and the run cycle drive him
unchanged; the game shows him 1.1x bigger than Parker. Only the mesh and
palette are his: a heavy build, a long black duster split at the back with
gold trim, an open collar over a blood-red shirt, slicked-back hair and a
beard, tinted glasses, and his broadcast headset with a mic boom and a red
ON AIR lamp, so he reads as the voice on the radio the moment you see him.
"""

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
_argv = sys.argv
sys.argv = [sys.argv[0]]  # build_runner reads its runner from argv
import build_runner as br  # noqa: E402
sys.argv = _argv

import bpy  # noqa: E402
import bmesh  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

OUT = os.path.normpath(os.path.join(HERE, "..", "characters", "host", "host.glb"))

br.PALETTE = {
    "skin": (0.70, 0.50, 0.40),
    "hair": (0.16, 0.12, 0.10),
    "top": (0.12, 0.10, 0.09),      # the duster
    "shirt": (0.50, 0.06, 0.06),
    "accent": (0.86, 0.62, 0.22),   # gold trim
    "pants": (0.09, 0.09, 0.10),
    "glove": (0.05, 0.05, 0.05),
    "shoe": (0.10, 0.08, 0.07),
    "sole": (0.30, 0.05, 0.05),
    "goggle_band": (0.24, 0.24, 0.26),  # headset metal
    "lens": (1.00, 0.16, 0.10),         # ON AIR lamp
    "scarf": (0.05, 0.05, 0.06),        # tinted glasses
    "coat": (0.12, 0.10, 0.09),
}
# Part tags (see build_runner.PARTS): 1 hair, 2 headset, 3 lamp, 4 glasses,
# 5 gold trim; 8 collar (rigid with the upper chest), 9 coat tails (rigid
# with the hips, so the legs swing clear of them).
br.PARTS = {1: "hair", 2: "goggle_band", 3: "lens", 4: "scarf", 5: "accent", 8: "coat", 9: "coat", 10: "accent"}
br.CHEST_PARTS = {8, 9, 10}
HIP_PARTS = {9, 10}

# A big man: thick neck, barrel chest, heavy arms and legs, big hands.
HOST_RADII = {
    "pelvis": (0.165, 0.115), "waist": (0.15, 0.105), "ribs": (0.17, 0.115),
    "chest": (0.185, 0.12), "neck_base": (0.07, 0.066), "neck_top": (0.06, 0.058),
    "shoulder": (0.074, 0.072), "elbow": (0.055, 0.055), "wrist": (0.04, 0.036),
    "knuckles": (0.052, 0.024), "fingertips": (0.046, 0.021),
    "hip": (0.095, 0.095), "knee": (0.064, 0.064), "ankle": (0.046, 0.046),
    "heel": (0.05, 0.045), "toe": (0.055, 0.04),
}
for _k, _r in HOST_RADII.items():
    _table = br.BODY_VERTS if _k in br.BODY_VERTS else br.LEFT_LIMB_VERTS
    _table[_k] = (_table[_k][0], _r)


def region_for(co, bone):
    x, y, z = co
    if bone in ("Head", "Neck"):
        return "skin"
    if bone.endswith("Hand"):
        return "glove"
    if bone.endswith("LowerArm"):
        # Duster sleeves to the wrist, a gold cuff.
        return "coat" if abs(x) < 0.61 else ("accent" if abs(x) < 0.635 else "glove")
    if bone.endswith("Foot") or bone.endswith("Toes"):
        return "sole" if z < 0.02 else "shoe"
    if bone.endswith("LowerLeg"):
        return "shoe" if z < 0.2 else "pants"
    if bone.endswith("UpperLeg"):
        return "pants"
    if bone == "Hips":
        return "pants" if z < 0.98 else "coat"
    # Torso: the duster hangs open over a red shirt, widest at the collar.
    if y < -0.04 and 1.02 < z:
        if abs(x) < 0.03 + max(0.0, z - 1.02) * 0.14:
            return "shirt"
    return "coat"


br.region_for = region_for


def _tube(name, path, radii, levels=1):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([tuple(p) for p in path], [(i, i + 1) for i in range(len(path) - 1)], [])
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    skin = obj.modifiers.new("Skin", "SKIN")
    for sv, r in zip(mesh.skin_vertices[0].data, radii):
        sv.radius = r
    if levels > 0:
        sub = obj.modifiers.new("Subsurf", "SUBSURF")
        sub.levels = levels
    br.apply_modifiers(obj)
    return obj


def _panel(name, quads, thickness):
    """A flat panel from rows of points (outer ring of a coat tail), given
    some thickness."""
    bm = bmesh.new()
    rows = [[bm.verts.new(Vector(p)) for p in row] for row in quads]
    for r in range(len(rows) - 1):
        for c in range(len(rows[r]) - 1):
            bm.faces.new((rows[r][c], rows[r][c + 1], rows[r + 1][c + 1], rows[r + 1][c]))
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    solid = obj.modifiers.new("Solid", "SOLIDIFY")
    solid.thickness = thickness
    solid.offset = 0.0
    br.apply_modifiers(obj)
    for p in obj.data.polygons:
        p.use_smooth = True
    return obj


def build_head():
    """A broad, square head with a heavy jaw."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=14, radius=1.0)
    for v in bm.verts:
        x, y, z = v.co
        jaw = 1.0 + max(0.0, -z) * 0.08
        v.co = Vector((x * 0.098 * jaw, y * 0.104 - max(0.0, -z) * 0.01, z * 0.12))
        v.co += Vector((0, -0.008, 1.645))
    mesh = bpy.data.meshes.new("HostHead")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("HostHead", mesh)
    bpy.context.scene.collection.objects.link(obj)
    for p in mesh.polygons:
        p.use_smooth = True
    # A big nose and a heavy brow, so the face reads at a distance.
    nose = _tube("HostNose", [(0, -0.1, 1.655), (0, -0.122, 1.615)], [(0.016, 0.014), (0.022, 0.018)], 1)
    brow = _tube("HostBrow", [(-0.06, -0.093, 1.69), (0, -0.104, 1.685), (0.06, -0.093, 1.69)], [(0.012, 0.01)] * 3, 1)
    return br.join([obj, nose, brow], "HostHead")


def build_hair():
    """Slicked back, plus a short boxed beard."""
    parts = []
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=12, radius=1.0)
    for v in bm.verts:
        x, y, z = v.co
        v.co = Vector((x * 0.104, y * 0.116 + max(0.0, y) * 0.012, max(z, -0.2) * 0.1)) + Vector((0, 0.006, 1.676))
    drop = [v for v in bm.verts if v.co.y < -0.06 and v.co.z < 1.735]
    bmesh.ops.delete(bm, geom=drop, context="VERTS")
    mesh = bpy.data.meshes.new("HostHair")
    bm.to_mesh(mesh)
    bm.free()
    cap = bpy.data.objects.new("HostHair", mesh)
    bpy.context.scene.collection.objects.link(cap)
    solid = cap.modifiers.new("Solid", "SOLIDIFY")
    solid.thickness = 0.014
    br.apply_modifiers(cap)
    parts.append((cap, 1))
    # Beard: a chunky horseshoe round the jaw.
    beard = _tube("HostBeard", [(-0.08, -0.04, 1.6), (-0.06, -0.085, 1.555), (0, -0.104, 1.535),
                                (0.06, -0.085, 1.555), (0.08, -0.04, 1.6)],
                  [(0.02, 0.02), (0.03, 0.028), (0.034, 0.03), (0.03, 0.028), (0.02, 0.02)])
    parts.append((beard, 1))
    return parts


def build_headset():
    """The broadcast headset: a band over the top, a cup on each ear, the
    mic boom round to his mouth and a red lamp on the left cup. Tinted
    glasses too. All rigid with the head."""
    gear = []
    # Band over the crown, from ear to ear (a ring stood up on its side).
    band = br._ring("HeadsetBand", (0, 0.0, 1.66), 0.112, 0.112, 0.01, tilt=math.pi / 2, segments=28)
    # Keep only the top half.
    bm = bmesh.new()
    bm.from_mesh(band.data)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < 1.655], context="VERTS")
    bm.to_mesh(band.data)
    bm.free()
    gear.append((band, 2))
    for x in (-0.108, 0.108):
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=16, radius1=0.045, radius2=0.04, depth=0.04,
                              matrix=Matrix.Translation(Vector((x, 0.0, 1.645)))
                              @ Matrix.Rotation(math.copysign(math.pi / 2, x), 4, "Y"))
        mesh = bpy.data.meshes.new("HeadsetCup")
        bm.to_mesh(mesh)
        bm.free()
        cup = bpy.data.objects.new("HeadsetCup", mesh)
        bpy.context.scene.collection.objects.link(cup)
        gear.append((cup, 2))
    # The ON AIR lamp on the left cup, and a stubby antenna.
    gear.append((br._lens("OnAirLamp", (0.135, 0.0, 1.645), 0.018, 0.02), 3))
    lamp = gear[-1][0]
    lamp.rotation_euler = (0, math.pi / 2, 0)
    bpy.context.view_layer.objects.active = lamp
    for o in bpy.context.selected_objects:
        o.select_set(False)
    lamp.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    gear.append((_tube("HeadsetAntenna", [(0.12, 0.02, 1.67), (0.15, 0.05, 1.79)], [(0.006, 0.006), (0.004, 0.004)], 0), 2))
    gear.append((br._lens("AntennaTip", (0.15, 0.05, 1.795), 0.012, 0.012), 3))
    # Mic boom from the right cup round the cheek to the mouth.
    gear.append((_tube("MicBoom", [(-0.11, -0.01, 1.63), (-0.1, -0.07, 1.6), (-0.06, -0.115, 1.585), (-0.025, -0.125, 1.585)],
                       [(0.007, 0.007)] * 4, 0), 2))
    gear.append((br._lens("Mic", (-0.02, -0.128, 1.585), 0.016, 0.03), 4))
    # Tinted glasses: two rounded lenses and a bridge.
    for x in (-0.037, 0.037):
        gear.append((br._lens("Glasses", (x, -0.103, 1.665), 0.026, 0.012), 4))
    gear.append((_tube("GlassesBridge", [(-0.012, -0.108, 1.668), (0.012, -0.108, 1.668)], [(0.004, 0.004)] * 2, 0), 4))
    return gear


def build_coat():
    """The duster's high collar (rigid with the chest) and its two long
    tails, split up the back and hanging behind the legs (rigid with the
    hips), each with a gold hem."""
    out = []
    collar = br._ring("Collar", (0, 0.025, 1.49), 0.098, 0.085, 0.016, tilt=0.45, segments=24)
    # Open at the front.
    bm = bmesh.new()
    bm.from_mesh(collar.data)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.y < -0.06 and abs(v.co.x) < 0.05], context="VERTS")
    bm.to_mesh(collar.data)
    bm.free()
    out.append((collar, 8))
    for side in (-1.0, 1.0):
        rows = []
        for z, spread, back in ((1.0, 0.0, 0.0), (0.82, 0.03, 0.03), (0.62, 0.07, 0.07), (0.46, 0.1, 0.1)):
            row = []
            for t in (0.0, 0.25, 0.5, 0.75, 1.0):
                # From the side seam round to the split at the back.
                a = (0.06 + 0.94 * t) * math.pi * 0.5
                rx = 0.17 + spread
                ry = 0.125 + back
                row.append((side * (math.cos(a) * rx + 0.004), math.sin(a) * ry + 0.01, z))
            rows.append(row)
        tail = _panel("CoatTail", rows, 0.016)
        out.append((tail, 9))
        hem = _tube("CoatHem", [(side * (0.17 + 0.1) * math.cos(a), (0.125 + 0.1) * math.sin(a) + 0.01, 0.465)
                                for a in [(0.06 + 0.94 * t) * math.pi * 0.5 for t in (0.0, 0.33, 0.66, 1.0)]],
                    [(0.012, 0.012)] * 4, 0)
        out.append((hem, 10))
    # The duster's skirt at the sides of the hips, rigid with the hips too.
    return out


def main():
    br.reset_scene()
    arm = br.build_armature()
    body = br.build_body()
    head = build_head()
    br.tag(body, 0)
    br.tag(head, 0)
    rigid = build_hair() + build_headset() + build_coat()
    for g, t in rigid:
        br.tag(g, t)
    body = br.join([body, head] + [g for g, _ in rigid], "HostMesh")
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=0.0005)
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    br.paint_and_skin(body, arm)
    # The coat tails go with the hips instead of the chest.
    part = body.data.attributes["part"].data
    hip_ids = [i for i in range(len(body.data.vertices)) if part[i].value in HIP_PARTS]
    for g in body.vertex_groups:
        g.remove(hip_ids)
    body.vertex_groups["Hips"].add(hip_ids, 1.0, "REPLACE")
    body.data.attributes.remove(body.data.attributes["part"])
    br.build_material(body)

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
