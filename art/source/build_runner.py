"""Builds the runner character (mesh + humanoid skeleton) and exports it to glTF.

Run with Blender 4.2+ (or the `bpy` Python module):
    blender --background --python art/source/build_runner.py
    python3 art/source/build_runner.py            # with `pip install bpy`

Output: art/characters/runner/runner.glb (Parker), or with `-- echo`:
art/characters/runner/echo.glb (Echo, the second playable runner), or with
`-- mags`: art/characters/runner/mags.glb (Mags, the Line's dispatcher; a
character in levels, not playable).

All of them share the exact same skeleton (bone names AND positions), so
RunnerBody's poses drive either one unchanged. Everything else differs: body
shape, head and face, hair, outfit, gear and palette.

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

import math
import os
import sys

import bpy  # must come before bmesh when run as a module
import bmesh
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
RUNNER = next((r for r in ("echo", "mags") if r in sys.argv[1:]), "parker")
OUT = os.path.normpath(os.path.join(HERE, "..", "characters", "runner", "%s.glb" % ("runner" if RUNNER == "parker" else RUNNER)))

# Palette (linear-ish sRGB values, shaded by the toon shader in game).
# Wasteland outfit: olive field jacket and charcoal cargo pants, worn boots,
# goggles up on the forehead and a dusty scarf. The orange accent stays, so
# the runner still pops against the tan city.
PALETTE = {
    "skin": (0.80, 0.58, 0.44),
    "hair": (0.10, 0.09, 0.10),
    "top": (0.36, 0.39, 0.30),
    "accent": (0.96, 0.33, 0.16),
    "pants": (0.20, 0.19, 0.18),
    "glove": (0.24, 0.17, 0.12),
    "shoe": (0.46, 0.38, 0.30),
    "sole": (0.96, 0.33, 0.16),
    "goggle_band": (0.14, 0.13, 0.12),
    "lens": (0.95, 0.62, 0.20),
    "scarf": (0.70, 0.58, 0.44),
}
# Echo: the radio fixer, built to read as her own person from any angle:
# a big cloud of dark curls under on-ear headphones, a face, a cropped
# oxblood bomber with a cream shearling collar, a radio pack with a whip
# antenna on her back, a webbing belt with a handset, blue work pants and
# tall tan lace-up boots. Teal (her colour on the radio dial) marks the
# headphones, antenna tip and jacket trim.
ECHO_PALETTE = {
    "skin": (0.50, 0.32, 0.22),
    "hair": (0.11, 0.06, 0.05),
    "top": (0.36, 0.09, 0.09),
    "accent": (0.08, 0.60, 0.56),
    "rib": (0.12, 0.10, 0.10),
    "shirt": (0.78, 0.70, 0.56),
    "collar": (0.70, 0.60, 0.46),
    "pants": (0.17, 0.25, 0.36),
    "glove": (0.12, 0.11, 0.11),
    "boot": (0.46, 0.30, 0.17),
    "sole": (0.10, 0.09, 0.09),
    "metal": (0.22, 0.23, 0.21),
    "strap": (0.20, 0.19, 0.15),
    "canvas": (0.33, 0.33, 0.24),
    "eye_white": (0.92, 0.89, 0.84),
    "iris": (0.06, 0.04, 0.04),
    "brow": (0.08, 0.05, 0.04),
    "lips": (0.40, 0.18, 0.17),
    "pad": (0.16, 0.16, 0.17),
}
# Mags: sixties, warm, tired, tough. Grey hair in a short thick braid,
# reading glasses low on her nose on a cord, an old studio headset round her
# neck, a patched canvas vest stuffed with chalk and pencils over a faded
# denim shirt with rolled sleeves, fingerless gloves, cargo trousers and worn
# boots. Amber (the Line's dispatch light) is her accent.
MAGS_PALETTE = {
    "skin": (0.74, 0.54, 0.42),
    "hair": (0.66, 0.65, 0.62),
    "hair_dark": (0.48, 0.47, 0.45),
    "vest": (0.47, 0.38, 0.24),
    "pocket": (0.40, 0.32, 0.20),
    "patch": (0.27, 0.32, 0.36),
    "patch2": (0.52, 0.24, 0.17),
    "stitch": (0.86, 0.80, 0.66),
    "shirt": (0.38, 0.46, 0.54),
    "pants": (0.33, 0.33, 0.26),
    "glove": (0.18, 0.15, 0.13),
    "boot": (0.30, 0.20, 0.13),
    "sole": (0.12, 0.11, 0.10),
    "strap": (0.22, 0.17, 0.12),
    "metal": (0.40, 0.40, 0.38),
    "headset": (0.13, 0.13, 0.14),
    "pad": (0.24, 0.21, 0.19),
    "accent": (0.95, 0.60, 0.14),
    "frame": (0.27, 0.16, 0.09),
    "cord": (0.55, 0.30, 0.20),
    "chalk": (0.93, 0.92, 0.88),
    "chalk2": (0.55, 0.78, 0.86),
    "pencil": (0.93, 0.72, 0.16),
    "lead": (0.15, 0.13, 0.12),
    "eye_white": (0.90, 0.87, 0.82),
    "iris": (0.20, 0.26, 0.24),
    "brow": (0.56, 0.55, 0.52),
    "lips": (0.56, 0.34, 0.30),
}
if RUNNER == "echo":
    PALETTE = ECHO_PALETTE
elif RUNNER == "mags":
    PALETTE = MAGS_PALETTE

# Rigid parts (hair, gear, face) are tagged with a "part" attribute: tag N
# is RIGID[N - 1] = (palette entry, bone the part follows rigidly). 0 = the
# skinned body. Filled by main().
RIGID = []

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

# Echo's build: same skeleton, a different body. Narrower shoulders and a
# cinched waist, fuller bust and hips, slimmer arms and calves, smaller hands
# and feet. name -> (position, or None to keep Parker's, radii).
ECHO_VERTS = {
    "pelvis": ((0, 0.008, 0.94), (0.162, 0.11)),
    "waist": ((0, 0.0, 1.08), (0.104, 0.078)),
    "ribs": ((0, -0.006, 1.23), (0.124, 0.092)),
    "chest": ((0, -0.016, 1.355), (0.138, 0.112)),
    "neck_base": ((0, 0.006, 1.47), (0.05, 0.048)),
    "neck_top": ((0, 0.004, 1.575), (0.046, 0.046)),
    "shoulder": ((0.158, 0.0, 1.42), (0.05, 0.052)),
    "elbow": (None, (0.037, 0.037)), "wrist": (None, (0.028, 0.025)),
    "knuckles": (None, (0.038, 0.017)), "fingertips": (None, (0.033, 0.015)),
    "hip": ((0.1, 0.0, 0.90), (0.094, 0.092)), "knee": (None, (0.054, 0.056)),
    "ankle": (None, (0.042, 0.042)), "heel": (None, (0.046, 0.043)), "toe": (None, (0.05, 0.036)),
}
# Mags's build: same skeleton, an older, sturdier body. A soft middle and
# broad back, a touch of a stoop (chest and neck carried forward), strong
# forearms and working hands, and chunky boots.
MAGS_VERTS = {
    "pelvis": ((0, 0.008, 0.94), (0.158, 0.11)),
    "waist": ((0, -0.008, 1.08), (0.138, 0.108)),
    "ribs": ((0, -0.004, 1.23), (0.146, 0.102)),
    "chest": ((0, -0.006, 1.355), (0.152, 0.108)),
    "neck_base": ((0, -0.006, 1.47), (0.058, 0.054)),
    "neck_top": ((0, -0.008, 1.55), (0.05, 0.05)),
    "shoulder": ((0.163, 0.004, 1.412), (0.058, 0.06)),
    "elbow": (None, (0.045, 0.045)), "wrist": (None, (0.033, 0.03)),
    "knuckles": (None, (0.044, 0.02)), "fingertips": (None, (0.039, 0.018)),
    "hip": ((0.098, 0.0, 0.90), (0.09, 0.09)), "knee": (None, (0.059, 0.059)),
    "ankle": (None, (0.047, 0.047)), "heel": (None, (0.052, 0.046)), "toe": (None, (0.056, 0.042)),
}
_BUILD = {"echo": ECHO_VERTS, "mags": MAGS_VERTS}.get(RUNNER, {})
for _k, (_p, _r) in _BUILD.items():
    _table = BODY_VERTS if _k in BODY_VERTS else LEFT_LIMB_VERTS
    _table[_k] = (_p or _table[_k][0], _r)


def mirror(p):
    return (-p[0], p[1], p[2])


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def build_armature():
    arm_data = bpy.data.armatures.new("RunnerRig")  # same rig for every runner
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
        # (taper, width, height) per runner; Mags has a softer, rounder jaw.
        taper, w, h = {"echo": (0.3, 0.087, 0.114), "mags": (0.2, 0.09, 0.115)}.get(RUNNER, (0.22, 0.092, 0.118))
        taper = 1.0 - max(0.0, -z) * taper
        v.co = Vector((x * w * taper, y * 0.100 * taper - max(0.0, -z) * 0.012, z * h))
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


def _ellipsoid(name, center, radii, segments=(12, 8), rot=None):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments[0], v_segments=segments[1], radius=1.0)
    m = Matrix.Translation(Vector(center)) @ (rot or Matrix.Identity(4)) @ Matrix.Diagonal(Vector(radii + (1.0,)))
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    return _bm_object(name, bm, smooth=True)


def _box(name, center, size, rot=None):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    m = Matrix.Translation(Vector(center)) @ (rot or Matrix.Identity(4)) @ Matrix.Diagonal(Vector(tuple(size) + (1.0,)))
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    return _bm_object(name, bm)


def _rod(name, a, b, radius, segments=8):
    a, b = Vector(a), Vector(b)
    d = b - a
    bm = bmesh.new()
    rot = d.to_track_quat("Z", "Y").to_matrix().to_4x4()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segments, radius1=radius, radius2=radius, depth=d.length,
                          matrix=Matrix.Translation((a + b) / 2.0) @ rot)
    return _bm_object(name, bm)


def _bm_object(name, bm, smooth=False):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    if smooth:
        for poly in mesh.polygons:
            poly.use_smooth = True
    return obj


def _arc(name, center, radius, start, end, minor, segments=16):
    """A square tube bent along a circular arc in the XZ plane (over the top
    of the head), angles in radians from +X."""
    verts = []
    bm = bmesh.new()
    for i in range(segments + 1):
        t = start + (end - start) * i / segments
        ring = []
        for dr, dw in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            r = radius + dr * minor
            p = Vector((math.cos(t) * r, dw * minor, math.sin(t) * r))
            ring.append(bm.verts.new(p + Vector(center)))
        verts.append(ring)
    for i in range(segments):
        for k in range(4):
            k2 = (k + 1) % 4
            bm.faces.new((verts[i][k], verts[i + 1][k], verts[i + 1][k2], verts[i][k2]))
    bm.faces.new(verts[0])
    bm.faces.new(list(reversed(verts[-1])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _bm_object(name, bm)


def build_echo_hair():
    """Echo's hair: a big cloud of curls round the back, sides and top of her
    head, open at the face, so her silhouette is nothing like Parker's tight
    cap. Each curl is its own little ball, which reads as texture in cel."""
    parts = []
    # A cap under the curls so no scalp shows between them.
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=12, radius=1.0)
    for v in bm.verts:
        x, y, z = v.co
        v.co = Vector((x * 0.1, y * 0.112, max(z, -0.35) * 0.112)) + Vector((0, 0.008, 1.668))
    drop = [v for v in bm.verts if v.co.y < -0.04 and v.co.z < 1.715]
    bmesh.ops.delete(bm, geom=drop, context="VERTS")
    cap = _bm_object("EchoHairCap", bm, smooth=True)
    solid = cap.modifiers.new("Solid", "SOLIDIFY")
    solid.thickness = 0.012
    apply_modifiers(cap)
    parts.append((cap, "hair", "Head"))

    # Curls on a shell bigger than the head: golden-spiral points, seeded
    # jitter so the build is deterministic.
    center = Vector((0, 0.03, 1.70))
    shell = Vector((0.125, 0.125, 0.112))
    n = 90
    rnd = 0
    for i in range(n):
        rnd = (rnd * 1103515245 + 12345) & 0x7FFFFFFF
        jitter = (rnd % 1000) / 1000.0
        zf = 1.0 - 2.0 * (i + 0.5) / n
        ring = math.sqrt(max(0.0, 1.0 - zf * zf))
        a = i * 2.39996323
        d = Vector((math.cos(a) * ring, math.sin(a) * ring, zf))
        p = center + Vector((d.x * shell.x, d.y * shell.y, d.z * shell.z))
        # Keep the face clear and stop at the nape and jaw.
        if p.y < -0.025 and p.z < 1.735:
            continue
        if p.z < 1.57 or (p.z < 1.63 and p.y < 0.03):
            continue
        r = 0.036 + 0.014 * jitter
        parts.append((_ellipsoid("Curl", tuple(p), (r, r, r * 0.92), (8, 6)), "hair", "Head"))
    # A short fringe of curls along the hairline.
    for x in (-0.07, -0.035, 0.0, 0.035, 0.07):
        parts.append((_ellipsoid("Fringe", (x, -0.07 + abs(x) * 0.35, 1.745 - abs(x) * 0.35), (0.03, 0.026, 0.024), (8, 6)), "hair", "Head"))
    return parts


def build_echo_face():
    """Eyes, brows, nose and lips. Parker's face is hidden by goggles and
    scarf; Echo's is the first thing you see in the studio and on the chase
    cam's turnarounds."""
    parts = []
    for side in (-1, 1):
        x = 0.031 * side
        parts.append((_ellipsoid("EyeWhite", (x, -0.091, 1.655), (0.015, 0.008, 0.0098)), "eye_white", "Head"))
        parts.append((_ellipsoid("Iris", (x, -0.0975, 1.654), (0.0078, 0.004, 0.0085), (10, 6)), "iris", "Head"))
        brow_rot = Matrix.Rotation(0.12 * side, 4, "Y")
        parts.append((_box("Brow", (x * 1.08, -0.095, 1.68), (0.028, 0.008, 0.005), brow_rot), "brow", "Head"))
    parts.append((_ellipsoid("Nose", (0, -0.104, 1.632), (0.011, 0.014, 0.019)), "skin", "Head"))
    parts.append((_ellipsoid("Lips", (0, -0.093, 1.601), (0.019, 0.008, 0.0068)), "lips", "Head"))
    # Small hoop earrings would vanish under the headphones; cheekbones do the
    # rest through the narrower jaw in build_head.
    return parts


def build_echo_gear():
    """Headphones on her head, the shearling collar, the radio pack and
    antenna on her back, belt and handset, boot cuffs and a knee pad.
    Returns (object, palette key, rigid bone) triples."""
    gear = []
    # Headphones: band over the curls, a cup on each side, a boom mic.
    gear.append((_arc("HeadphoneBand", (0, 0.0, 1.655), 0.15, math.radians(8), math.radians(172), 0.009), "metal", "Head"))
    for side in (-1, 1):
        x = 0.148 * side
        rot = Matrix.Rotation(math.pi / 2, 4, "Y")
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=16, radius1=0.042, radius2=0.036, depth=0.04,
                              matrix=Matrix.Translation(Vector((x, 0.0, 1.655))) @ rot)
        gear.append((_bm_object("HeadphoneCup", bm), "metal", "Head"))
        gear.append((_ring_x("CupRim", (x + 0.021 * side, 0.0, 1.655), 0.034, 0.006), "accent", "Head"))
    gear.append((_rod("BoomMic", (0.15, -0.02, 1.64), (0.05, -0.115, 1.6), 0.0045), "metal", "Head"))
    gear.append((_ellipsoid("MicTip", (0.045, -0.118, 1.598), (0.011, 0.011, 0.011), (8, 6)), "accent", "Head"))

    # Shearling collar: a soft band lying on the shoulders.
    gear.append((_ring("Collar", (0, 0.01, 1.452), 0.078, 0.072, 0.017, tilt=0.22), "collar", "UpperChest"))

    # Radio pack between the shoulder blades, with dial, light and antenna.
    gear.append((_box("RadioPack", (0, 0.155, 1.29), (0.23, 0.1, 0.26)), "canvas", "UpperChest"))
    gear.append((_box("PackFlap", (0, 0.16, 1.40), (0.24, 0.11, 0.04)), "strap", "UpperChest"))
    gear.append((_box("RadioFace", (0, 0.2055, 1.27), (0.19, 0.01, 0.15)), "metal", "UpperChest"))
    gear.append((_ellipsoid("Dial", (-0.06, 0.212, 1.29), (0.03, 0.008, 0.03), (12, 6)), "accent", "UpperChest"))
    for x in (0.03, 0.07):
        gear.append((_box("Knob", (x, 0.212, 1.25), (0.022, 0.012, 0.022)), "rib", "UpperChest"))
    gear.append((_rod("Antenna", (0.09, 0.17, 1.42), (0.15, 0.25, 1.98), 0.006, 6), "metal", "UpperChest"))
    gear.append((_ellipsoid("AntennaTip", (0.151, 0.251, 1.985), (0.014, 0.014, 0.014), (8, 6)), "accent", "UpperChest"))
    # Pack straps over the shoulders and down the front.
    for side in (-1, 1):
        x = 0.085 * side
        gear.append((_box("StrapTop", (x, 0.02, 1.44), (0.032, 0.2, 0.014), Matrix.Rotation(0.12, 4, "X")), "strap", "UpperChest"))
        gear.append((_box("StrapFront", (x, -0.106, 1.37), (0.032, 0.012, 0.15), Matrix.Rotation(-0.3, 4, "X")), "strap", "UpperChest"))

    # Webbing belt with a buckle, a pouch and the handset on her left hip.
    gear.append((_ring("Belt", (0, 0.006, 0.985), 0.158, 0.106, 0.018), "strap", "Hips"))
    gear.append((_box("Buckle", (0, -0.12, 0.985), (0.05, 0.016, 0.034)), "metal", "Hips"))
    gear.append((_box("Pouch", (-0.12, 0.08, 0.95), (0.07, 0.05, 0.08)), "strap", "Hips"))
    gear.append((_box("Handset", (0.165, -0.01, 0.95), (0.04, 0.06, 0.13)), "metal", "Hips"))
    gear.append((_rod("HandsetAerial", (0.165, 0.0, 1.0), (0.168, 0.0, 1.08), 0.005, 6), "metal", "Hips"))
    gear.append((_ellipsoid("HandsetLight", (0.186, -0.01, 0.97), (0.006, 0.012, 0.012), (8, 6)), "accent", "Hips"))

    # Boot cuffs (folded tops of the tall boots) and a pad on her right knee.
    for side, bone in ((1, "LeftLowerLeg"), (-1, "RightLowerLeg")):
        gear.append((_ring("BootCuff", (0.108 * side, 0.004, 0.36), 0.056, 0.056, 0.016), "boot", bone))
    gear.append((_box("KneePad", (-0.105, -0.055, 0.5), (0.085, 0.03, 0.1)), "pad", "RightLowerLeg"))
    return gear


def build_mags_hair():
    """Mags's hair: grey, pulled back off her face into a short, thick braid
    that hangs to the top of her back, with a little volume over the temples.
    Plaits are offset ellipsoids, chunky enough to read in cel."""
    parts = []
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=12, radius=1.0)
    for v in bm.verts:
        x, y, z = v.co
        v.co = Vector((x * 0.099, y * 0.111, max(z, -0.42) * 0.107)) + Vector((0, 0.006, 1.668))
    drop = [v for v in bm.verts if v.co.y < -0.036 and v.co.z < 1.708]
    bmesh.ops.delete(bm, geom=drop, context="VERTS")
    cap = _bm_object("MagsHairCap", bm, smooth=True)
    solid = cap.modifiers.new("Solid", "SOLIDIFY")
    solid.thickness = 0.012
    apply_modifiers(cap)
    parts.append((cap, "hair", "Head"))
    # Swept-back volume over each temple and a gathered knot at the crown
    # of the braid, so the hair isn't a flat helmet.
    for side in (-1, 1):
        parts.append((_ellipsoid("Temple", (0.072 * side, -0.01, 1.70), (0.034, 0.06, 0.04), (10, 8)), "hair", "Head"))
    parts.append((_ellipsoid("BraidKnot", (0, 0.10, 1.625), (0.05, 0.035, 0.042), (10, 8)), "hair_dark", "Head"))
    # The braid: plaits alternating left and right, thinning toward the tie.
    for i in range(5):
        t = i / 4.0
        side = -1 if i % 2 else 1
        r = 0.036 - 0.008 * t
        c = (0.009 * side, 0.118 + 0.018 * t, 1.585 - 0.13 * t)
        rot = Matrix.Rotation(0.35 * side, 4, "Y")
        parts.append((_ellipsoid("Plait", c, (r * 0.95, r * 0.8, r * 1.15), (10, 8), rot), "hair", "Head"))
    parts.append((_ring("BraidTie", (0, 0.138, 1.445), 0.02, 0.018, 0.006), "accent", "Head"))
    parts.append((_ellipsoid("BraidEnd", (0, 0.14, 1.415), (0.022, 0.018, 0.03), (8, 6)), "hair", "Head"))
    return parts


def build_mags_face():
    """Eyes under heavy lids, grey brows that tip down at the ends (tired,
    kind), a strong nose, thin lips, and reading glasses low on her nose on
    a cord that loops behind her neck."""
    parts = []
    for side in (-1, 1):
        x = 0.032 * side
        parts.append((_ellipsoid("EyeWhite", (x, -0.091, 1.655), (0.014, 0.008, 0.0088)), "eye_white", "Head"))
        parts.append((_ellipsoid("Iris", (x, -0.0972, 1.6535), (0.007, 0.004, 0.0074), (10, 6)), "iris", "Head"))
        parts.append((_ellipsoid("Lid", (x, -0.092, 1.6615), (0.0165, 0.0086, 0.0062)), "skin", "Head"))
        brow_rot = Matrix.Rotation(-0.16 * side, 4, "Y")
        parts.append((_box("Brow", (x * 1.1, -0.096, 1.681), (0.032, 0.009, 0.0065), brow_rot), "brow", "Head"))
        # Reading glasses: half-moon frames low on the nose, arms to the ears.
        frame = _ring("GlassFrame", (0, 0, 0), 0.018, 0.012, 0.0028, tilt=math.pi / 2, segments=16)
        frame.data.transform(Matrix.Translation(Vector((0.031 * side, -0.112, 1.641))))
        parts.append((frame, "frame", "Head"))
        parts.append((_rod("GlassArm", (0.05 * side, -0.108, 1.645), (0.09 * side, -0.01, 1.655), 0.0022, 6), "frame", "Head"))
        # The cord: from the arm's end down behind the neck.
        parts.append((_rod("GlassCord", (0.09 * side, -0.005, 1.652), (0.055 * side, 0.065, 1.50), 0.0018, 5), "cord", "Head"))
        parts.append((_rod("GlassCord", (0.055 * side, 0.065, 1.50), (0.0, 0.075, 1.475), 0.0018, 5), "cord", "Head"))
    parts.append((_rod("GlassBridge", (-0.013, -0.114, 1.645), (0.013, -0.114, 1.645), 0.0022, 6), "frame", "Head"))
    parts.append((_ellipsoid("Nose", (0, -0.105, 1.630), (0.0125, 0.016, 0.021)), "skin", "Head"))
    parts.append((_ellipsoid("Lips", (0, -0.0935, 1.599), (0.019, 0.0075, 0.0052)), "lips", "Head"))
    return parts


def build_mags_gear():
    """The studio headset round her neck, the vest's pockets (chalk and
    pencils sticking out of them), patches, belt, cargo pockets, rolled
    sleeves and boot tops. Returns (object, palette key, rigid bone) triples."""
    gear = []
    # Headset: band round the back of the neck, the cups resting forward on
    # her collarbones, a coiled lead down to a vest pocket.
    band = _arc("HeadsetBand", (0, 0, 0), 0.086, 0.0, math.pi, 0.008)
    band.data.transform(Matrix.Translation(Vector((0, -0.012, 1.462))) @ Matrix.Rotation(-math.pi / 2, 4, "X"))
    gear.append((band, "headset", "UpperChest"))
    for side in (-1, 1):
        x = 0.1 * side
        gear.append((_rod("HeadsetYoke", (0.086 * side, -0.012, 1.462), (x, -0.06, 1.44), 0.006, 6), "metal", "UpperChest"))
        rot = Matrix.Rotation(-1.15, 4, "X") @ Matrix.Rotation(0.35 * side, 4, "Y")
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=16, radius1=0.045, radius2=0.04, depth=0.034,
                              matrix=Matrix.Translation(Vector((x, -0.088, 1.43))) @ rot)
        gear.append((_bm_object("HeadsetCup", bm), "headset", "UpperChest"))
        pad = _ring("CupPad", (0, 0, 0), 0.036, 0.036, 0.009, segments=16)
        pad.data.transform(Matrix.Translation(Vector((x, -0.078, 1.448))) @ rot)
        gear.append((pad, "pad", "UpperChest"))
    gear.append((_ellipsoid("CupLight", (0.1, -0.104, 1.418), (0.008, 0.006, 0.008), (8, 6)), "accent", "UpperChest"))
    # Coiled lead: a zigzag of short rods from the left cup to the chest pocket.
    a = Vector((0.11, -0.112, 1.405))
    for i in range(6):
        b = Vector((0.11 + (0.012 if i % 2 == 0 else -0.004), -0.122, 1.405 - 0.013 * (i + 1)))
        gear.append((_rod("HeadsetLead", tuple(a), tuple(b), 0.004, 5), "headset", "UpperChest"))
        a = b

    # Vest pockets: two on the chest with flaps, two big ones low down.
    for side in (-1, 1):
        x = 0.078 * side
        gear.append((_box("ChestPocket", (x, -0.118, 1.275), (0.066, 0.022, 0.074)), "pocket", "UpperChest"))
        gear.append((_box("PocketFlap", (x, -0.128, 1.305), (0.07, 0.01, 0.022)), "vest", "UpperChest"))
        gear.append((_box("LowPocket", (0.088 * side, -0.124, 1.115), (0.08, 0.024, 0.085)), "pocket", "Spine"))
    # Chalk sticks in her left chest pocket, pencils in the right.
    for i, (dx, key) in enumerate(((0.062, "chalk"), (0.078, "chalk2"), (0.094, "chalk"))):
        gear.append((_rod("Chalk", (dx, -0.114, 1.28), (dx + 0.004 * (i - 1), -0.116, 1.345 - 0.008 * i), 0.0065, 6), key, "UpperChest"))
    for i, dx in enumerate((-0.062, -0.08, -0.095)):
        top = Vector((dx - 0.012 * (i - 1), -0.118, 1.36 + 0.01 * (i % 2)))
        gear.append((_rod("Pencil", (dx, -0.116, 1.27), tuple(top), 0.0042, 6), "pencil", "UpperChest"))
        gear.append((_rod("PencilTip", tuple(top), tuple(top + (top - Vector((dx, -0.116, 1.27))).normalized() * 0.012), 0.0022, 6), "lead", "UpperChest"))
    # Patches: one on the front, two on the back, each with a stitched edge.
    for center, size, key, bone in (((-0.085, -0.129, 1.115), (0.05, 0.004, 0.04), "patch2", "Spine"),
                                    ((0.06, 0.11, 1.28), (0.09, 0.006, 0.075), "patch", "UpperChest"),
                                    ((-0.07, 0.107, 1.16), (0.07, 0.006, 0.06), "patch2", "Spine")):
        gear.append((_box("Patch", center, size), key, bone))
        sy = 1 if center[1] > 0 else -1
        gear.append((_box("Stitch", (center[0], center[1] + 0.0035 * sy, center[2] + size[2] * 0.5 - 0.004), (size[0] * 0.9, 0.002, 0.003)), "stitch", bone))

    # Belt and buckle, cargo pockets on the outside of each thigh.
    gear.append((_ring("Belt", (0, 0.004, 0.985), 0.156, 0.112, 0.018), "strap", "Hips"))
    gear.append((_box("Buckle", (0, -0.124, 0.985), (0.046, 0.014, 0.034)), "metal", "Hips"))
    for side, bone in ((1, "LeftUpperLeg"), (-1, "RightUpperLeg")):
        gear.append((_box("CargoPocket", (0.182 * side, -0.005, 0.68), (0.026, 0.1, 0.12)), "pants", bone))
        gear.append((_box("CargoFlap", (0.19 * side, -0.005, 0.735), (0.02, 0.104, 0.026)), "pocket", bone))
    # Rolled shirt sleeves just below the elbow, and worn boot tops.
    for side, bone in ((1, "LeftLowerArm"), (-1, "RightLowerArm")):
        gear.append((_ring_x("RolledSleeve", (0.49 * side, 0.0, 1.43), 0.046, 0.014), "shirt", bone))
    for side, bone in ((1, "LeftLowerLeg"), (-1, "RightLowerLeg")):
        gear.append((_ring("BootTop", (0.108 * side, 0.006, 0.205), 0.056, 0.058, 0.014), "boot", bone))
    return gear


def mags_region(co, bone):
    """Mags's clothes, painted by dominant bone and position."""
    x, y, z = co
    if bone in ("Head", "Neck"):
        return "skin"
    if bone.endswith("Hand"):
        return "glove" if abs(x) < 0.775 else "skin"
    if bone.endswith("LowerArm"):
        return "shirt" if abs(x) < 0.49 else "skin"
    if bone.endswith("Foot") or bone.endswith("Toes"):
        return "sole" if z < 0.025 else "boot"
    if bone.endswith("LowerLeg"):
        return "boot" if z < 0.205 else "pants"
    if bone.endswith("UpperLeg") or bone == "Hips":
        if z < 0.995:
            return "pants"
    if bone.endswith("UpperArm"):
        return "shirt"
    # The vest: open down the front over the shirt, a V at the neck, no
    # sleeves (the shirt shows at the shoulders), the shirt tail below it.
    if z < 1.02:
        return "shirt"
    if y < -0.06 and abs(x) < 0.022:
        return "shirt"
    if y < -0.03 and z > 1.36 and abs(x) < 0.03 + (z - 1.36) * 0.9:
        return "shirt"
    if abs(x) > 0.14 and z > 1.33:
        return "shirt"
    return "vest"


def _ring_x(name, center, radius, minor):
    """A ring facing along X (headphone cup rims)."""
    obj = _ring(name, (0, 0, 0), radius, radius, minor)
    obj.data.transform(Matrix.Translation(Vector(center)) @ Matrix.Rotation(math.pi / 2, 4, "Y"))
    return obj


def echo_region(co, bone):
    """Echo's outfit, painted by dominant bone and position."""
    x, y, z = co
    if bone in ("Head", "Neck"):
        return "skin"
    if bone.endswith("Hand"):
        # Fingerless gloves: dark over the palm, bare fingers.
        return "glove" if abs(x) < 0.775 else "skin"
    if bone.endswith("LowerArm"):
        # Full jacket sleeves with a dark knit cuff and a teal piping line.
        if abs(x) > 0.62:
            return "rib"
        return "accent" if z > 1.462 else "top"
    if bone.endswith("Foot") or bone.endswith("Toes"):
        return "sole" if z < 0.025 else "boot"
    if bone.endswith("LowerLeg"):
        return "boot" if z < 0.37 else "pants"
    if bone.endswith("UpperLeg") or bone == "Hips":
        if z < 0.995:
            return "pants"
    # Cropped bomber: knit band at the hem, the cream shirt showing below it
    # and at the open neck, teal piping down the zip and along the sleeves.
    if z < 1.035:
        return "shirt"
    if z < 1.075:
        return "rib"
    if y < -0.06 and abs(x) < 0.03 and z < 1.40:
        return "accent" if abs(x) > 0.012 else "rib"
    if y < -0.05 and abs(x) < 0.045 and z > 1.40:
        return "shirt"
    if bone.endswith("UpperArm") and z > 1.462:
        return "accent"
    return "top"


def _ring(name, center, rx, ry, minor, tilt=0.0, segments=24):
    """A torus around the head/neck, elliptical, tilted about X (radians)."""
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    # A square tube swept around an ellipse: chunky facets read well in cel.
    verts = []
    for i in range(segments):
        a = 2.0 * math.pi * i / segments
        ca, sa = math.cos(a), math.sin(a)
        for dx, dz in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            r = 1.0 + dx * minor / max(rx, ry)
            p = Vector((ca * rx * r, sa * ry * r, dz * minor))
            p = Matrix.Rotation(tilt, 3, "X") @ p
            verts.append(bm.verts.new(p + Vector(center)))
    for i in range(segments):
        j = (i + 1) % segments
        for k in range(4):
            k2 = (k + 1) % 4
            bm.faces.new((verts[i * 4 + k], verts[j * 4 + k], verts[j * 4 + k2], verts[i * 4 + k2]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def _lens(name, center, radius, depth):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=12, radius1=radius, radius2=radius * 0.9, depth=depth,
                          matrix=Matrix.Translation(Vector(center)) @ Matrix.Rotation(math.pi / 2, 4, "X"))
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def build_gear():
    """Goggles pushed up on the forehead and a scarf around the neck, all
    rigid with the head. Returns (object, part tag) pairs."""
    gear = []
    # Strap around the head just above the brow, tipped down at the front.
    gear.append((_ring("GoggleBand", (0, -0.006, 1.705), 0.101, 0.114, 0.011, tilt=-0.18), 2))
    for x in (-0.034, 0.034):
        gear.append((_lens("Lens", (x, -0.118, 1.712), 0.024, 0.022), 3))
    # Scarf: a thick loop around the neck plus a knot at the front.
    gear.append((_ring("Scarf", (0, -0.004, 1.49), 0.07, 0.068, 0.03, tilt=0.12), 4))
    gear.append((_lens("ScarfKnot", (0.02, -0.08, 1.46), 0.032, 0.04), 4))
    return gear


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
        if RUNNER == "echo":
            # Jacket sleeves rolled to mid-forearm, a teal band at the roll.
            return "top" if abs(x) < 0.53 else ("accent" if abs(x) < 0.55 else "skin")
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


def skin(body, arm):
    """Automatic weights for the skinned body and head only: loose rigid
    parts in the mix make bone heat weighting fail."""
    for o in bpy.context.selected_objects:
        o.select_set(False)
    body.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")


def paint(body):
    """Vertex colors from the outfit regions, and every rigid part (plus the
    head) bound with full weight to the one bone it follows."""
    mesh = body.data
    groups = {g.index: g.name for g in body.vertex_groups}
    color_attr = mesh.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    part = mesh.attributes["part"].data
    regions = {"echo": echo_region, "mags": mags_region}.get(RUNNER, region_for)
    rigid = {}  # bone -> vertex ids that follow it rigidly
    for v in mesh.vertices:
        tag_value = part[v.index].value
        if tag_value > 0:
            region, bone = RIGID[tag_value - 1]
        else:
            best, weight = "Hips", -1.0
            for g in v.groups:
                if g.weight > weight:
                    best, weight = groups[g.group], g.weight
            region = regions(v.co, best)
            # The head (and the top of the neck) follows the head bone rigidly.
            bone = "Head" if v.co.z > 1.53 else None
        if bone:
            rigid.setdefault(bone, []).append(v.index)
        c = PALETTE[region]
        color_attr.data[v.index].color = (c[0], c[1], c[2], 1.0)
    mesh.color_attributes.active_color = color_attr

    for bone, ids in rigid.items():
        for g in body.vertex_groups:
            g.remove(ids)
        group = body.vertex_groups.get(bone) or body.vertex_groups.new(name=bone)
        group.add(ids, 1.0, "REPLACE")


def tag(obj, value):
    attr = obj.data.attributes.new("part", "INT", "POINT")
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
    tag(body, 0)
    tag(head, 0)
    if RUNNER == "echo":
        rigid = build_echo_hair() + build_echo_face() + build_echo_gear()
    elif RUNNER == "mags":
        rigid = build_mags_hair() + build_mags_face() + build_mags_gear()
    else:
        parker_parts = {2: "goggle_band", 3: "lens", 4: "scarf"}
        rigid = [(h, "hair", "Head") for h in build_hair()] + [(g, parker_parts[t], "Head") for g, t in build_gear()]
    for g, region, bone in rigid:
        if (region, bone) not in RIGID:
            RIGID.append((region, bone))
        tag(g, RIGID.index((region, bone)) + 1)
    body = join([body, head], "RunnerMesh")
    # Merge the doubled verts that the skin modifier leaves at branch joins.
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=0.0005)
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    skin(body, arm)
    for g, _, bone in rigid:
        g.vertex_groups.new(name=bone).add(list(range(len(g.data.vertices))), 1.0, "REPLACE")
    body = join([body] + [g for g, _, _ in rigid], "RunnerMesh")
    paint(body)
    body.data.validate()
    body.data.attributes.remove(body.data.attributes["part"])
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
