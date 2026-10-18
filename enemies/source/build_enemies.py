"""Builds the enemy models and exports them to glTF.

Run with Blender 4.2+ (or the `bpy` Python module):
    blender --background --python enemies/source/build_enemies.py
    python3 enemies/source/build_enemies.py          # with `pip install bpy`
    python3 enemies/source/build_enemies.py raider   # just one

Output: enemies/models/<name>.glb
  raider   the Host's crew: scrap armor, respirator, glowing goggles, a
           loudspeaker on the back, a scrap rifle ("Rifle" node) and the
           bruiser's scrap shield ("ScrapShield").
  soldier  the paramilitary (trooper, shield, marksman): helmet and visor,
           plate carrier, radio pack, a carbine ("Rifle"), a riot shield
           ("Shield") and a scoped rifle ("LongRifle"); each type shows
           the parts it uses.
  hunter   a Static hunter: lean, hooded, built to run.
  juno     Juno, the Static's star hunter (boss): goggles up, braid, scarf.
  heavy    the paramilitary heavy: bulky armor, full helmet, a light
           machine gun ("Rifle").
  mutant   a Hollow: hunched, long arms, claws, bone spines, glowing eyes.
  drone    a rigid quadcopter: "Frame", "Rotor0".."Rotor3" (spin about
           their own up axis), "Lens" (glows), "Gun".

Conventions match the runner (art/source/build_runner.py), so the same
pose code drives every humanoid:
  * Bones use Godot's SkeletonProfileHumanoid names (Hips, Spine, ...).
  * Rest pose is a T-pose facing -Y in Blender (+Z in Godot); the game
    turns the model to face -Z.
  * One body mesh painted with vertex colors (the toon shader's base color),
    plus a "Glow" mesh for parts that light up (eyes, lenses, visor strip).
  * Gear is rigid: each piece follows exactly one bone.
Everything here is our own work (CC0-compatible): primitives and skin
modifiers, no imported assets.
"""

import math
import os
import sys

import bpy  # must come before bmesh when run as a module
import bmesh
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.normpath(os.path.join(HERE, "..", "models"))


# ---------------------------------------------------------------- scene helpers

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def link(obj):
    bpy.context.scene.collection.objects.link(obj)
    return obj


def deselect():
    for o in bpy.context.selected_objects:
        o.select_set(False)


def apply_modifiers(obj):
    deselect()
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    for m in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def join(objs, name):
    deselect()
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    objs[0].name = name
    objs[0].data.name = name
    return objs[0]


def from_bmesh(bm, name, smooth=False):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for p in mesh.polygons:
        p.use_smooth = smooth
    return link(bpy.data.objects.new(name, mesh))


def paint(obj, color):
    """Gives every vertex one color (a "Col" point attribute)."""
    attr = obj.data.color_attributes.get("Col") or obj.data.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    for d in attr.data:
        d.color = (color[0], color[1], color[2], 1.0)
    return obj


def xf(pos=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    """Matrix from position, XYZ euler (degrees) and scale."""
    r = Matrix.Rotation(math.radians(rot[2]), 4, "Z") @ Matrix.Rotation(math.radians(rot[1]), 4, "Y") \
        @ Matrix.Rotation(math.radians(rot[0]), 4, "X")
    s = Matrix.Diagonal((scale[0], scale[1], scale[2], 1.0))
    return Matrix.Translation(Vector(pos)) @ r @ s


# ---------------------------------------------------------------- primitives
# All take a size in meters and a transform; they return a new object.

def box(name, size, m, bevel=0.012):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    if bevel > 0.0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=min(bevel, min(size) * 0.45), segments=2,
                        affect="EDGES", profile=0.5)
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    return from_bmesh(bm, name)


def cyl(name, r1, r2, depth, m, segments=12, smooth=True):
    """Cylinder/cone along local Z, centered."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segments, radius1=r1, radius2=r2, depth=depth)
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    return from_bmesh(bm, name, smooth)


def ball(name, radii, m, cut_below=None, segments=16, rings=10):
    """Ellipsoid; cut_below (local, -1..1) drops the part under that height."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=1.0)
    if cut_below is not None:
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < cut_below - 1e-4], context="VERTS")
    for v in bm.verts:
        v.co = Vector((v.co.x * radii[0], v.co.y * radii[1], v.co.z * radii[2]))
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    obj = from_bmesh(bm, name, True)
    if cut_below is not None:
        s = obj.modifiers.new("Solid", "SOLIDIFY")
        s.thickness = 0.012
        apply_modifiers(obj)
    return obj


def ring(name, rx, ry, minor, m, segments=20):
    """A chunky elliptical band (square tube) around local Z."""
    bm = bmesh.new()
    verts = []
    for i in range(segments):
        a = 2.0 * math.pi * i / segments
        ca, sa = math.cos(a), math.sin(a)
        for dx, dz in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            r = 1.0 + dx * minor / max(rx, ry)
            verts.append(bm.verts.new(Vector((ca * rx * r, sa * ry * r, dz * minor))))
    for i in range(segments):
        j = (i + 1) % segments
        for k in range(4):
            k2 = (k + 1) % 4
            bm.faces.new((verts[i * 4 + k], verts[j * 4 + k], verts[j * 4 + k2], verts[i * 4 + k2]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    return from_bmesh(bm, name, True)


def skin_graph(name, verts, edges, root, levels=2):
    """Smooth organic shape from (position, (rx, ry)) nodes and edges."""
    names = list(verts.keys())
    index = {n: i for i, n in enumerate(names)}
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([verts[n][0] for n in names], [(index[a], index[b]) for a, b in edges], [])
    obj = link(bpy.data.objects.new(name, mesh))
    skin = obj.modifiers.new("Skin", "SKIN")
    skin.use_smooth_shade = True
    skin.branch_smoothing = 0.6
    for i, n in enumerate(names):
        sv = mesh.skin_vertices[0].data[i]
        sv.radius = verts[n][1]
        sv.use_root = n == root
    sub = obj.modifiers.new("Subsurf", "SUBSURF")
    sub.levels = levels
    sub.render_levels = levels
    apply_modifiers(obj)
    return obj


def mirror(p):
    return (-p[0], p[1], p[2])


def mirror_m(m):
    """The same transform reflected to the other side (x -> -x)."""
    f = Matrix.Diagonal((-1.0, 1.0, 1.0, 1.0))
    return f @ m @ f


# ---------------------------------------------------------------- humanoid rig

def bones_for(r):
    """Humanoid bones from a dict of joint positions (left side + center)."""
    center = [
        ("Hips", r["hips"], r["spine"], None),
        ("Spine", r["spine"], r["chest"], "Hips"),
        ("Chest", r["chest"], r["upper"], "Spine"),
        ("UpperChest", r["upper"], r["neck"], "Chest"),
        ("Neck", r["neck"], r["head"], "UpperChest"),
        ("Head", r["head"], r["head_top"], "Neck"),
    ]
    left = [
        ("LeftShoulder", r["clavicle"], r["shoulder"], "UpperChest"),
        ("LeftUpperArm", r["shoulder"], r["elbow"], "LeftShoulder"),
        ("LeftLowerArm", r["elbow"], r["wrist"], "LeftUpperArm"),
        ("LeftHand", r["wrist"], r["fingers"], "LeftLowerArm"),
        ("LeftUpperLeg", r["hip"], r["knee"], "Hips"),
        ("LeftLowerLeg", r["knee"], r["ankle"], "LeftUpperLeg"),
        ("LeftFoot", r["ankle"], r["ball"], "LeftLowerLeg"),
        ("LeftToes", r["ball"], r["toe"], "LeftFoot"),
    ]
    out = list(center)
    for name, head, tail, parent in left:
        out.append((name, head, tail, parent))
        rp = parent.replace("Left", "Right") if parent.startswith("Left") else parent
        out.append((name.replace("Left", "Right"), mirror(head), mirror(tail), rp))
    return out


def build_armature(name, rig):
    data = bpy.data.armatures.new(name + "Rig")
    arm = link(bpy.data.objects.new(name, data))
    deselect()
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    edit = data.edit_bones
    for bname, head, tail, parent in bones_for(rig):
        b = edit.new(bname)
        b.head = head
        b.tail = tail
        b.align_roll(Vector((0, -1, 0)) if abs(Vector(tail).z - Vector(head).z) > 0.05 else Vector((0, 0, 1)))
        if parent:
            b.parent = edit[parent]
            b.use_connect = (Vector(edit[parent].tail) - Vector(head)).length < 1e-4
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


def limb_graph(rig, t):
    """Body skin-graph nodes from the rig and a thickness table `t`."""
    v = {
        "pelvis": (r_add(rig["hips"], (0, 0.005, -0.02)), t["pelvis"]),
        "waist": (rig["spine"], t["waist"]),
        "ribs": (rig["chest"], t["ribs"]),
        "chest": (rig["upper"], t["chest"]),
        "neck_base": (r_add(rig["neck"], (0, 0, 0.01)), t["neck"]),
        "neck_top": (rig["head"], (t["neck"][0] * 0.85, t["neck"][1] * 0.85)),
    }
    left = {
        "shoulder": (rig["shoulder"], t["shoulder"]),
        "elbow": (rig["elbow"], t["elbow"]),
        "wrist": (rig["wrist"], t["wrist"]),
        "knuckles": (r_lerp(rig["wrist"], rig["fingers"], 0.6), t["hand"]),
        "fingertips": (rig["fingers"], (t["hand"][0] * 0.85, t["hand"][1] * 0.9)),
        "hip": (r_add(rig["hip"], (0, 0, -0.03)), t["hip"]),
        "knee": (rig["knee"], t["knee"]),
        "ankle": (r_add(rig["ankle"], (0, 0, 0.01)), t["ankle"]),
        "heel": (r_add(rig["ankle"], (0, 0.04, -0.045)), t["heel"]),
        "toe": (r_add(rig["toe"], (0, 0.01, 0.01)), t["toe"]),
    }
    for k, (p, rr) in left.items():
        v["L." + k] = (p, rr)
        v["R." + k] = (mirror(p), rr)
    e = [("pelvis", "waist"), ("waist", "ribs"), ("ribs", "chest"), ("chest", "neck_base"), ("neck_base", "neck_top")]
    for a, b in [("chest", "L.shoulder"), ("L.shoulder", "L.elbow"), ("L.elbow", "L.wrist"),
                 ("L.wrist", "L.knuckles"), ("L.knuckles", "L.fingertips"),
                 ("pelvis", "L.hip"), ("L.hip", "L.knee"), ("L.knee", "L.ankle"),
                 ("L.ankle", "L.heel"), ("L.heel", "L.toe")]:
        e.append((a, b))
        e.append((a.replace("L.", "R."), b.replace("L.", "R.")))
    return v, e


def r_add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def r_lerp(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def bind(obj, bone):
    """Makes a gear piece follow one bone rigidly."""
    g = obj.vertex_groups.new(name=bone)
    g.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    return obj


def build_humanoid(name, rig, thickness, region_for, palette, gear, glow, extras):
    """Body + rigid gear (skinned), Glow mesh (skinned), extras (rigid
    objects exported as their own nodes). gear/glow: [(obj, color, bone)]."""
    arm = build_armature(name, rig)
    verts, edges = limb_graph(rig, thickness)
    body = skin_graph(name + "Body", verts, edges, "pelvis")
    head = rig["head_shape"](name)
    body = join([body, head], name + "Body")
    deselect()
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=0.0005)
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")

    deselect()
    body.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")

    # The head and neck top are rigid with the head bone (no stretching).
    mesh = body.data
    head_z = rig["head"][2] - 0.02
    head_ids = [v.index for v in mesh.vertices if v.co.z > head_z and abs(v.co.x) < 0.2]
    for g in body.vertex_groups:
        if g.name != "Head":
            g.remove(head_ids)
    (body.vertex_groups.get("Head") or body.vertex_groups.new(name="Head")).add(head_ids, 1.0, "REPLACE")

    groups = {g.index: g.name for g in body.vertex_groups}
    col = mesh.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    for v in mesh.vertices:
        best, w = "Hips", -1.0
        for g in v.groups:
            if g.weight > w:
                best, w = groups[g.group], g.weight
        c = palette[region_for(v.co, best)]
        col.data[v.index].color = (c[0], c[1], c[2], 1.0)

    pieces = [body]
    # Gear with a 4th entry goes into its own skinned mesh of that name
    # (e.g. "Helmet"), so the game can knock it off.
    groups = {}
    for entry in gear:
        obj, color, bone = entry[:3]
        paint(obj, palette[color])
        bind(obj, bone)
        if len(entry) > 3:
            groups.setdefault(entry[3], []).append(obj)
        else:
            pieces.append(obj)
    body = join(pieces, name + "Mesh")
    body.data.color_attributes.active_color = body.data.color_attributes["Col"]
    skin_to(body, arm)
    separate = []
    for gname, objs in groups.items():
        g = join(objs, gname)
        g.data.color_attributes.active_color = g.data.color_attributes["Col"]
        skin_to(g, arm)
        separate.append(g)

    glow_obj = None
    if glow:
        parts = []
        for obj, color, bone in glow:
            paint(obj, palette[color])
            bind(obj, bone)
            parts.append(obj)
        glow_obj = join(parts, "Glow")
        glow_obj.data.color_attributes.active_color = glow_obj.data.color_attributes["Col"]
        skin_to(glow_obj, arm)

    for obj, color in extras:
        if isinstance(color, str):
            paint(obj, palette[color])
    return arm, [o for o in [body, glow_obj] if o] + separate + [o for o, _ in extras]


def skin_to(obj, arm):
    obj.parent = arm
    obj.matrix_parent_inverse = arm.matrix_world.inverted()
    mod = next((m for m in obj.modifiers if m.type == "ARMATURE"), None) or obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm


def material_for(objs):
    mat = bpy.data.materials.new("EnemyToon")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    attr = nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    mat.node_tree.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.8
    for o in objs:
        if o.type == "MESH":
            o.data.materials.clear()
            o.data.materials.append(mat)
            o.data.color_attributes.active_color = o.data.color_attributes.get("Col")


def export(name, objs):
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name + ".glb")
    material_for(objs)
    deselect()
    for o in objs:
        o.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_yup=True,
        export_apply=False, export_skins=True, export_animations=False,
        export_vertex_color="ACTIVE", export_all_vertex_colors=False,
    )
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objs if o.type == "MESH")
    print("wrote", path, "tris:", tris)


def merge_colored(name, parts):
    """Joins rigid pieces [(obj, color)] into one object, painted per piece."""
    objs = []
    for obj, color in parts:
        paint(obj, color)
        objs.append(obj)
    obj = join(objs, name)
    obj.data.color_attributes.active_color = obj.data.color_attributes["Col"]
    return obj


def set_origin(obj, point):
    """Moves the object's origin to `point` (world) without moving the mesh."""
    obj.data.transform(Matrix.Translation(-Vector(point)))
    obj.location = Vector(point)


# ---------------------------------------------------------------- raider

RAIDER_PALETTE = {
    "skin": (0.66, 0.46, 0.34),
    "jacket": (0.50, 0.17, 0.12),
    "jacket_dark": (0.30, 0.10, 0.08),
    "pants": (0.36, 0.30, 0.22),
    "boot": (0.16, 0.13, 0.11),
    "glove": (0.11, 0.10, 0.10),
    "metal": (0.42, 0.40, 0.37),
    "rust": (0.62, 0.34, 0.16),
    "dark": (0.12, 0.12, 0.13),
    "strap": (0.24, 0.17, 0.11),
    "brass": (0.78, 0.58, 0.24),
    "crest": (0.92, 0.36, 0.10),
    "lens": (1.0, 0.20, 0.08),
    "wrap": (0.70, 0.62, 0.48),
}

HUMAN_RIG = {
    "hips": (0, 0, 0.96), "spine": (0, 0, 1.06), "chest": (0, 0, 1.19), "upper": (0, 0, 1.32),
    "neck": (0, 0, 1.46), "head": (0, 0, 1.55), "head_top": (0, 0, 1.78),
    "clavicle": (0.03, 0, 1.43), "shoulder": (0.18, 0, 1.44), "elbow": (0.45, 0, 1.44),
    "wrist": (0.70, 0, 1.44), "fingers": (0.87, 0, 1.44),
    "hip": (0.10, 0, 0.93), "knee": (0.11, 0, 0.51), "ankle": (0.115, 0.02, 0.09),
    "ball": (0.115, -0.10, 0.03), "toe": (0.115, -0.18, 0.03),
}

HUMAN_THICK = {
    "pelvis": (0.16, 0.11), "waist": (0.14, 0.095), "ribs": (0.165, 0.11), "chest": (0.18, 0.115),
    "neck": (0.065, 0.06), "shoulder": (0.068, 0.068), "elbow": (0.05, 0.05), "wrist": (0.038, 0.034),
    "hand": (0.05, 0.022), "hip": (0.092, 0.092), "knee": (0.064, 0.064), "ankle": (0.048, 0.048),
    "heel": (0.055, 0.05), "toe": (0.058, 0.04),
}


def human_head(name, jaw=1.0):
    def make(_n):
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=14, radius=1.0)
        for v in bm.verts:
            x, y, z = v.co
            taper = 1.0 - max(0.0, -z) * 0.2
            v.co = Vector((x * 0.096 * taper, y * 0.108 * taper - max(0.0, -z) * 0.014 * jaw, z * 0.12))
            v.co += Vector((0, -0.008, 1.645))
        return from_bmesh(bm, name + "Head", True)
    return make


def raider_region(co, bone):
    x, y, z = co
    if bone in ("Head", "Neck"):
        return "skin"
    if bone.endswith("Hand"):
        return "glove"
    if bone.endswith("LowerArm"):
        return "wrap" if abs(x) > 0.6 else "skin"
    if bone.endswith("Foot") or bone.endswith("Toes"):
        return "boot"
    if bone.endswith("LowerLeg"):
        return "boot" if z < 0.24 else "pants"
    if bone.endswith("UpperLeg") or bone == "Hips":
        return "pants" if z < 1.0 else "jacket_dark"
    if bone.endswith("UpperArm"):
        return "jacket"
    return "jacket" if z > 1.1 else "jacket_dark"


def build_raider():
    reset_scene()
    p = RAIDER_PALETTE
    rig = dict(HUMAN_RIG)
    rig["head_shape"] = human_head("Raider")
    gear = []
    glow = []
    # Respirator over the mouth with two filter cans.
    gear.append((ball("Mask", (0.075, 0.06, 0.06), xf((0, -0.085, 1.6)), segments=14), "dark", "Head"))
    for s in (-1, 1):
        gear.append((cyl("Filter", 0.032, 0.03, 0.05, xf((0.06 * s, -0.12, 1.585), (70, 0, -30 * s))), "metal", "Head"))
    # Goggles: strap and glowing red lenses (the Static crew's look).
    gear.append((ring("GoggleStrap", 0.1, 0.112, 0.011, xf((0, -0.006, 1.675), (-8, 0, 0))), "strap", "Head"))
    for s in (-1, 1):
        gear.append((cyl("GoggleCup", 0.03, 0.028, 0.03, xf((0.037 * s, -0.106, 1.675), (90, 0, 0))), "dark", "Head"))
        glow.append((cyl("Lens", 0.024, 0.024, 0.008, xf((0.037 * s, -0.122, 1.675), (90, 0, 0))), "lens", "Head"))
    # Mohawk crest of scrap fins.
    for i in range(5):
        y = -0.06 + 0.035 * i
        gear.append((box("Crest", (0.018, 0.03, 0.06 - abs(i - 1.5) * 0.008), xf((0, y, 1.77 - abs(y) * 0.25), (-12 + 8 * i, 0, 0)), 0.004), "crest", "Head"))
    # Left shoulder: a rusted pauldron with spikes.
    pad = ball("Pauldron", (0.11, 0.1, 0.075), xf((0.2, 0, 1.47), (0, 18, 0)), cut_below=-0.15)
    gear.append((pad, "rust", "LeftUpperArm"))
    for i, (dy, dz) in enumerate([(-0.04, 0.0), (0.0, 0.01), (0.04, 0.0)]):
        gear.append((cyl("Spike", 0.018, 0.0, 0.08, xf((0.21, dy, 1.55 + dz), (0, 14, 0)), 6, False), "metal", "LeftUpperArm"))
    # Scrap chest plate, a little crooked, with rivets.
    gear.append((box("ChestPlate", (0.25, 0.04, 0.2), xf((0.02, -0.115, 1.3), (6, 0, 4)), 0.01), "metal", "UpperChest"))
    for rx, rz in [(-0.08, 1.37), (0.1, 1.38), (-0.07, 1.22), (0.11, 1.23)]:
        gear.append((ball("Rivet", (0.012, 0.01, 0.012), xf((rx, -0.138, rz)), segments=6, rings=4), "dark", "UpperChest"))
    # Bandolier across the chest with brass shells.
    gear.append((box("Bandolier", (0.06, 0.03, 0.5), xf((0.0, -0.135, 1.22), (0, -38, 0)), 0.006), "strap", "Chest"))
    for i in range(5):
        t = -0.15 + 0.075 * i
        gear.append((cyl("Shell", 0.01, 0.01, 0.045, xf((t * 0.62, -0.155, 1.22 + t * 0.79), (0, -38, 0)), 6), "brass", "Chest"))
    # Belt with pouches.
    gear.append((ring("Belt", 0.16, 0.115, 0.022, xf((0, 0.005, 0.99))), "strap", "Hips"))
    for s in (-1, 1):
        gear.append((box("Pouch", (0.07, 0.05, 0.07), xf((0.11 * s, -0.11, 0.97)), 0.01), "strap", "Hips"))
    # Loudspeaker on the back: the Host's show, everywhere they go.
    gear.append((box("SpeakerBox", (0.2, 0.1, 0.22), xf((0, 0.17, 1.28)), 0.015), "dark", "UpperChest"))
    gear.append((cyl("Horn", 0.04, 0.1, 0.12, xf((0.04, 0.2, 1.47), (-60, 0, -10)), 14), "rust", "UpperChest"))
    # Knee pads and forearm wraps.
    for s in (-1, 1):
        gear.append((box("KneePad", (0.09, 0.04, 0.11), xf((0.11 * s, -0.06, 0.52)), 0.015), "metal", "LeftLowerLeg" if s > 0 else "RightLowerLeg"))
        for i in range(2):
            gear.append((ring("Wrap", 0.044, 0.042, 0.01, xf((0.58 * s + 0.04 * i * s, 0, 1.44), (0, 90, 0))), "wrap", "LeftLowerArm" if s > 0 else "RightLowerArm"))
    extras = [(build_scrap_rifle(p), None), (build_scrap_shield(p), None)]
    arm, objs = build_humanoid("Raider", rig, HUMAN_THICK, raider_region, p, gear, glow, extras)
    export("raider", [arm] + objs)


def build_scrap_shield(p):
    """A bruiser's shield: a car door and sheet metal, bolted together."""
    parts = [
        (box("Door", (0.66, 0.06, 0.9), xf((0, 0, 0.05), (0, 3, 0)), 0.04), p["rust"]),
        (box("Sheet", (0.6, 0.03, 0.5), xf((0.04, -0.03, -0.4), (0, -4, 0)), 0.01), p["metal"]),
        (box("Window", (0.4, 0.02, 0.18), xf((0, -0.035, 0.3)), 0.02), p["dark"]),
        (box("Handle", (0.06, 0.08, 0.2), xf((0, 0.07, 0)), 0.01), p["strap"]),
    ]
    for i in range(4):
        parts.append((cyl("Spike", 0.025, 0.0, 0.12, xf((-0.24 + 0.16 * i, -0.08, 0.5), (90, 0, 0)), 6, False), p["metal"]))
    return merge_colored("ScrapShield", parts)


def build_scrap_rifle(p):
    """Rifle along -Y (Godot +Z, turned to -Z in game), grip at the origin."""
    parts = [
        (box("Receiver", (0.06, 0.34, 0.09), xf((0, -0.08, 0.04)), 0.01), p["metal"]),
        (cyl("Barrel", 0.016, 0.016, 0.42, xf((0, -0.45, 0.055), (90, 0, 0)), 10), p["dark"]),
        (cyl("Muzzle", 0.026, 0.022, 0.06, xf((0, -0.66, 0.055), (90, 0, 0)), 10), p["dark"]),
        (box("Magazine", (0.04, 0.06, 0.15), xf((0, -0.12, -0.07), (-14, 0, 0)), 0.008), p["rust"]),
        (box("Grip", (0.04, 0.05, 0.11), xf((0, 0.02, -0.04), (18, 0, 0)), 0.008), p["strap"]),
        (box("Stock", (0.045, 0.24, 0.07), xf((0, 0.2, 0.02), (6, 0, 0)), 0.01), p["strap"]),
        (cyl("Scope", 0.022, 0.022, 0.14, xf((0, -0.08, 0.115), (90, 0, 0)), 10), p["dark"]),
        (box("Tape", (0.066, 0.05, 0.096), xf((0, -0.2, 0.04)), 0.004), p["wrap"]),
    ]
    obj = merge_colored("Rifle", parts)
    return obj


# ---------------------------------------------------------------- hunter and Juno

HUNTER_PALETTE = dict(RAIDER_PALETTE)
HUNTER_PALETTE.update({
    "jacket": (0.2, 0.22, 0.24),
    "jacket_dark": (0.13, 0.14, 0.15),
    "pants": (0.24, 0.22, 0.2),
    "hood": (0.32, 0.12, 0.1),
    "scarf": (0.9, 0.42, 0.12),
    "hair": (0.12, 0.08, 0.06),
    "teal": (0.16, 0.5, 0.5),
})


def build_hunter(juno=False):
    """Lean, light gear for running: a hood and mask (hunter), or for Juno
    goggles up, a braid and a long scarf, the Line courier she was."""
    reset_scene()
    p = HUNTER_PALETTE
    rig = dict(HUMAN_RIG)
    rig["head_shape"] = human_head("Juno" if juno else "Hunter", jaw=0.6 if juno else 1.0)
    thick = {k: (v[0] * 0.92, v[1] * 0.92) for k, v in HUMAN_THICK.items()}
    if juno:
        thick["pelvis"] = (0.155, 0.11)
        thick["chest"] = (0.165, 0.11)
        thick["waist"] = (0.12, 0.085)
    gear = []
    glow = []
    if juno:
        gear.append((ball("Hair", (0.1, 0.114, 0.104), xf((0, 0.008, 1.668)), cut_below=-0.1, segments=18), "hair", "Head"))
        for i in range(4):
            gear.append((ball("Braid", (0.03, 0.03, 0.04), xf((0, 0.12 + 0.01 * i, 1.6 - 0.07 * i)), segments=8, rings=6), "hair", "Head"))
        gear.append((ring("GoggleStrap", 0.1, 0.114, 0.01, xf((0, -0.004, 1.71), (-14, 0, 0))), "strap", "Head"))
        for s_ in (-1, 1):
            glow.append((cyl("Lens", 0.024, 0.022, 0.024, xf((0.036 * s_, -0.11, 1.735), (70, 0, 0))), "lens", "Head"))
        gear.append((ring("Scarf", 0.075, 0.072, 0.032, xf((0, -0.004, 1.49), (8, 0, 0))), "scarf", "UpperChest"))
        gear.append((box("ScarfTail", (0.08, 0.02, 0.36), xf((0.06, 0.1, 1.3), (-12, 0, 6)), 0.01), "scarf", "UpperChest"))
        gear.append((box("Stripe", (0.02, 0.01, 0.3), xf((-0.09, -0.12, 1.28)), 0.003), "teal", "Chest"))
    else:
        gear.append((ball("Hood", (0.118, 0.13, 0.13), xf((0, 0.02, 1.66)), cut_below=-0.35, segments=18), "hood", "Head"))
        gear.append((ball("Mask", (0.082, 0.05, 0.05), xf((0, -0.09, 1.6)), segments=12), "dark", "Head"))
        for s_ in (-1, 1):
            glow.append((cyl("Lens", 0.02, 0.02, 0.008, xf((0.034 * s_, -0.11, 1.66), (90, 0, 0))), "lens", "Head"))
        gear.append((ring("Scarf", 0.075, 0.072, 0.03, xf((0, -0.004, 1.49), (8, 0, 0))), "hood", "UpperChest"))
    # Light harness, wrapped hands, knee pads for landings.
    gear.append((box("Harness", (0.05, 0.03, 0.46), xf((0.0, -0.12, 1.24), (0, 36, 0)), 0.006), "strap", "Chest"))
    gear.append((box("Pack", (0.18, 0.08, 0.2), xf((0, 0.15, 1.26)), 0.02), "strap", "Chest"))
    gear.append((ring("Belt", 0.15, 0.105, 0.02, xf((0, 0.005, 0.99))), "strap", "Hips"))
    for s_ in (-1, 1):
        side = "Left" if s_ > 0 else "Right"
        gear.append((box("KneePad", (0.085, 0.04, 0.1), xf((0.11 * s_, -0.058, 0.52)), 0.015), "dark", side + "LowerLeg"))
        for i in range(2):
            gear.append((ring("Wrap", 0.04, 0.038, 0.009, xf((0.6 * s_ + 0.04 * i * s_, 0, 1.44), (0, 90, 0))), "wrap", side + "LowerArm"))
    extras = [(build_scrap_rifle(p), None)]
    name = "Juno" if juno else "Hunter"
    arm, objs = build_humanoid(name, rig, thick, raider_region, p, gear, glow, extras)
    export(name.lower(), [arm] + objs)


# ---------------------------------------------------------------- soldier

SOLDIER_PALETTE = {
    # The Ward: clean grey-and-white corporate security, blue stripe.
    "skin": (0.58, 0.42, 0.32),
    "uniform": (0.46, 0.48, 0.5),
    "uniform_dark": (0.3, 0.32, 0.34),
    "boot": (0.09, 0.09, 0.10),
    "glove": (0.12, 0.12, 0.13),
    "armor": (0.82, 0.84, 0.85),
    "armor_dark": (0.55, 0.57, 0.59),
    "helmet": (0.86, 0.87, 0.88),
    "visor": (0.05, 0.06, 0.07),
    "strip": (0.25, 0.6, 1.0),
    "accent": (0.12, 0.38, 0.85),
    "black": (0.06, 0.06, 0.07),
    "shield": (0.75, 0.77, 0.79),
    "glass": (0.2, 0.26, 0.3),
}


def soldier_region(co, bone):
    x, y, z = co
    if bone in ("Head", "Neck"):
        return "uniform_dark"
    if bone.endswith("Hand"):
        return "glove"
    if bone.endswith("Foot") or bone.endswith("Toes"):
        return "boot"
    if bone.endswith("LowerLeg"):
        return "boot" if z < 0.26 else "uniform"
    if bone.endswith("UpperLeg") or bone == "Hips":
        return "uniform"
    return "uniform_dark" if bone.endswith("LowerArm") else "uniform"


def build_soldier():
    reset_scene()
    p = SOLDIER_PALETTE
    rig = dict(HUMAN_RIG)
    rig["head_shape"] = human_head("Soldier")
    thick = dict(HUMAN_THICK)
    thick["chest"] = (0.19, 0.12)
    thick["shoulder"] = (0.072, 0.072)
    gear = []
    glow = []
    # Helmet shell, brim and a full visor with a lit strip: no face, ever.
    # (The helmet is its own mesh: a trooper's first headshot knocks it off.)
    gear.append((ball("Helmet", (0.122, 0.13, 0.11), xf((0, 0.0, 1.665)), cut_below=-0.05, segments=20), "helmet", "Head", "Helmet"))
    gear.append((ring("HelmetRim", 0.122, 0.13, 0.012, xf((0, 0.0, 1.66))), "armor_dark", "Head", "Helmet"))
    gear.append((ball("Visor", (0.1, 0.05, 0.075), xf((0, -0.085, 1.62)), segments=16), "visor", "Head", "Helmet"))
    glow.append((box("VisorStrip", (0.14, 0.012, 0.014), xf((0, -0.133, 1.635)), 0.004), "strip", "Head"))
    gear.append((box("Rail", (0.02, 0.1, 0.03), xf((0.12, -0.01, 1.66)), 0.005), "black", "Head", "Helmet"))
    # Under the helmet: cropped hair and a balaclava.
    gear.append((ball("Cap", (0.1, 0.112, 0.1), xf((0, 0.005, 1.665)), cut_below=-0.2, segments=16), "uniform_dark", "Head"))
    # Plate carrier: front and back plates, pouches, shoulder straps.
    gear.append((box("FrontPlate", (0.3, 0.06, 0.32), xf((0, -0.11, 1.25)), 0.02), "armor", "Chest"))
    gear.append((box("BackPlate", (0.3, 0.06, 0.32), xf((0, 0.11, 1.25)), 0.02), "armor", "Chest"))
    for i in range(3):
        gear.append((box("MagPouch", (0.07, 0.05, 0.09), xf((-0.09 + 0.09 * i, -0.16, 1.15)), 0.01), "armor_dark", "Chest"))
    for s in (-1, 1):
        gear.append((box("Strap", (0.05, 0.24, 0.025), xf((0.1 * s, 0, 1.43)), 0.006), "armor_dark", "UpperChest"))
    gear.append((box("Patch", (0.08, 0.01, 0.04), xf((-0.07, -0.142, 1.36)), 0.003), "accent", "Chest"))
    # Radio pack with an antenna.
    gear.append((box("Radio", (0.2, 0.09, 0.24), xf((0, 0.19, 1.27)), 0.015), "black", "Chest"))
    gear.append((cyl("Antenna", 0.005, 0.003, 0.4, xf((0.07, 0.2, 1.55), (-8, 0, 0)), 5, False), "black", "Chest"))
    # Shoulder, elbow and knee pads, a belt with a thigh rig.
    for s in (-1, 1):
        side = "Left" if s > 0 else "Right"
        gear.append((ball("ShoulderPad", (0.08, 0.085, 0.06), xf((0.21 * s, 0, 1.47), (0, 20 * s, 0)), cut_below=-0.2), "armor", side + "UpperArm"))
        gear.append((box("ElbowPad", (0.06, 0.07, 0.07), xf((0.45 * s, 0.02, 1.44)), 0.015), "armor_dark", side + "LowerArm"))
        gear.append((box("KneePad", (0.1, 0.05, 0.12), xf((0.11 * s, -0.065, 0.52)), 0.02), "armor", side + "LowerLeg"))
    gear.append((ring("Belt", 0.165, 0.12, 0.024, xf((0, 0.005, 0.99))), "black", "Hips"))
    gear.append((box("Holster", (0.05, 0.1, 0.16), xf((-0.17, -0.01, 0.8)), 0.01), "black", "RightUpperLeg"))
    extras = [(build_carbine(p), None), (build_shield(p), None), (build_long_rifle(p), None)]
    arm, objs = build_humanoid("Soldier", rig, thick, soldier_region, p, gear, glow, extras)
    export("soldier", [arm] + objs)


def build_carbine(p):
    parts = [
        (box("Receiver", (0.055, 0.3, 0.085), xf((0, -0.08, 0.04)), 0.008), p["black"]),
        (box("Handguard", (0.05, 0.22, 0.06), xf((0, -0.33, 0.045)), 0.008), p["armor_dark"]),
        (cyl("Barrel", 0.013, 0.013, 0.16, xf((0, -0.5, 0.05), (90, 0, 0)), 10), p["black"]),
        (cyl("Brake", 0.02, 0.02, 0.05, xf((0, -0.6, 0.05), (90, 0, 0)), 8), p["black"]),
        (box("Magazine", (0.035, 0.06, 0.16), xf((0, -0.12, -0.08), (-10, 0, 0)), 0.006), p["black"]),
        (box("Grip", (0.035, 0.045, 0.1), xf((0, 0.02, -0.04), (16, 0, 0)), 0.006), p["black"]),
        (box("Stock", (0.04, 0.2, 0.08), xf((0, 0.19, 0.02)), 0.01), p["armor_dark"]),
        (box("Sight", (0.03, 0.06, 0.05), xf((0, -0.1, 0.11)), 0.006), p["black"]),
        (box("Light", (0.03, 0.05, 0.03), xf((0.04, -0.38, 0.03)), 0.004), p["accent"]),
    ]
    return merge_colored("Rifle", parts)


def build_long_rifle(p):
    """The marksman's rifle: long barrel, big scope, bipod folded."""
    parts = [
        (box("Receiver", (0.055, 0.34, 0.08), xf((0, -0.08, 0.04)), 0.008), p["black"]),
        (box("Handguard", (0.05, 0.3, 0.055), xf((0, -0.39, 0.045)), 0.008), p["armor_dark"]),
        (cyl("Barrel", 0.012, 0.012, 0.36, xf((0, -0.7, 0.05), (90, 0, 0)), 10), p["black"]),
        (cyl("Brake", 0.022, 0.022, 0.07, xf((0, -0.9, 0.05), (90, 0, 0)), 8), p["black"]),
        (cyl("Scope", 0.028, 0.034, 0.26, xf((0, -0.1, 0.13), (90, 0, 0)), 12), p["black"]),
        (cyl("ScopeLens", 0.03, 0.03, 0.01, xf((0, -0.235, 0.13), (90, 0, 0)), 12), p["strip"]),
        (box("Magazine", (0.035, 0.07, 0.1), xf((0, -0.12, -0.05)), 0.006), p["black"]),
        (box("Grip", (0.035, 0.045, 0.1), xf((0, 0.03, -0.04), (16, 0, 0)), 0.006), p["black"]),
        (box("Stock", (0.045, 0.26, 0.1), xf((0, 0.22, 0.01)), 0.012), p["armor_dark"]),
        (box("Cheek", (0.04, 0.12, 0.04), xf((0, 0.18, 0.08)), 0.008), p["black"]),
    ]
    return merge_colored("LongRifle", parts)


def build_shield(p):
    """Riot shield, centered at its origin, face toward -Y (the front)."""
    parts = [
        (box("Panel", (0.62, 0.05, 1.1), xf((0, 0, 0)), 0.04), p["shield"]),
        (box("Rim", (0.66, 0.03, 1.14), xf((0, 0.012, 0)), 0.02), p["black"]),
        (box("Window", (0.36, 0.01, 0.12), xf((0, -0.03, 0.34)), 0.01), p["glass"]),
        (box("Stripe", (0.5, 0.01, 0.06), xf((0, -0.03, -0.22)), 0.006), p["accent"]),
        (box("Handle", (0.06, 0.06, 0.18), xf((0, 0.06, 0)), 0.01), p["black"]),
    ]
    return merge_colored("Shield", parts)


# ---------------------------------------------------------------- heavy

HEAVY_PALETTE = dict(SOLDIER_PALETTE)
HEAVY_PALETTE.update({
    "uniform": (0.36, 0.38, 0.4),
    "uniform_dark": (0.24, 0.25, 0.27),
    "armor": (0.7, 0.72, 0.74),
    "armor_dark": (0.42, 0.44, 0.46),
    "helmet": (0.74, 0.76, 0.78),
    "hazard": (0.95, 0.62, 0.12),
    "strip": (1.0, 0.45, 0.15),
})


def build_heavy():
    reset_scene()
    p = HEAVY_PALETTE
    rig = dict(HUMAN_RIG)
    rig["head_shape"] = human_head("Heavy")
    thick = {k: (v[0] * 1.22, v[1] * 1.22) for k, v in HUMAN_THICK.items()}
    thick["chest"] = (0.24, 0.15)
    thick["ribs"] = (0.22, 0.14)
    gear = []
    glow = []
    # Full helmet with a faceplate and one glowing slit.
    gear.append((ball("Helmet", (0.135, 0.14, 0.135), xf((0, 0.0, 1.655)), segments=20), "helmet", "Head"))
    gear.append((box("Faceplate", (0.2, 0.06, 0.17), xf((0, -0.12, 1.63)), 0.025), "armor", "Head"))
    glow.append((box("Slit", (0.15, 0.012, 0.016), xf((0, -0.152, 1.665)), 0.004), "strip", "Head"))
    gear.append((box("Gorget", (0.24, 0.24, 0.07), xf((0, 0, 1.5)), 0.03), "armor_dark", "UpperChest"))
    # Heavy plates with hazard stripes.
    gear.append((box("FrontPlate", (0.4, 0.09, 0.42), xf((0, -0.15, 1.24)), 0.03), "armor", "Chest"))
    gear.append((box("BackPlate", (0.4, 0.09, 0.42), xf((0, 0.15, 1.24)), 0.03), "armor", "Chest"))
    for i in range(3):
        gear.append((box("Hazard", (0.06, 0.01, 0.3), xf((-0.12 + 0.12 * i, -0.198, 1.24), (0, 30, 0)), 0.003), "hazard", "Chest"))
    gear.append((box("Belly", (0.34, 0.08, 0.16), xf((0, -0.12, 1.02)), 0.03), "armor_dark", "Spine"))
    # Ammo pack on the back feeding the gun.
    gear.append((box("AmmoPack", (0.32, 0.16, 0.3), xf((0, 0.27, 1.22)), 0.03), "black", "Chest"))
    for s_ in (-1, 1):
        side = "Left" if s_ > 0 else "Right"
        gear.append((ball("Pauldron", (0.14, 0.13, 0.1), xf((0.25 * s_, 0, 1.48), (0, 25 * s_, 0)), cut_below=-0.25), "armor", side + "UpperArm"))
        gear.append((box("Bracer", (0.16, 0.1, 0.1), xf((0.58 * s_, 0, 1.44)), 0.02), "armor_dark", side + "LowerArm"))
        gear.append((box("Thigh", (0.15, 0.12, 0.22), xf((0.11 * s_, -0.05, 0.75)), 0.03), "armor", side + "UpperLeg"))
        gear.append((box("Greave", (0.13, 0.08, 0.3), xf((0.11 * s_, -0.06, 0.38)), 0.03), "armor", side + "LowerLeg"))
    gear.append((ring("Belt", 0.2, 0.15, 0.03, xf((0, 0.005, 0.99))), "black", "Hips"))
    lmg = merge_colored("Rifle", [
        (box("Receiver", (0.09, 0.4, 0.13), xf((0, -0.1, 0.05)), 0.015), p["black"]),
        (cyl("Barrel", 0.022, 0.022, 0.5, xf((0, -0.55, 0.06), (90, 0, 0)), 10), p["black"]),
        (cyl("Shroud", 0.04, 0.04, 0.3, xf((0, -0.45, 0.06), (90, 0, 0)), 12), p["armor_dark"]),
        (cyl("Drum", 0.09, 0.09, 0.08, xf((0.0, -0.12, -0.08), (0, 90, 0)), 16), p["armor"]),
        (box("Grip", (0.045, 0.05, 0.12), xf((0, 0.04, -0.05), (16, 0, 0)), 0.008), p["black"]),
        (box("ForeGrip", (0.04, 0.05, 0.12), xf((0, -0.32, -0.05)), 0.008), p["black"]),
        (box("Stock", (0.06, 0.2, 0.1), xf((0, 0.2, 0.03)), 0.012), p["armor_dark"]),
        (box("Hazard", (0.095, 0.05, 0.135), xf((0, -0.26, 0.05)), 0.004), p["hazard"]),
    ])
    arm, objs = build_humanoid("Heavy", rig, thick, soldier_region, p, gear, glow, [(lmg, None)])
    export("heavy", [arm] + objs)


# ---------------------------------------------------------------- mutant

MUTANT_PALETTE = {
    "skin": (0.56, 0.6, 0.47),
    "skin_dark": (0.36, 0.38, 0.3),
    "ash": (0.26, 0.25, 0.23),
    "bone": (0.86, 0.82, 0.68),
    "rag": (0.36, 0.28, 0.2),
    "mouth": (0.3, 0.1, 0.08),
    "eye": (0.85, 1.0, 0.25),
}

# Hunched: hips low, the spine pitched forward so the head sits ahead of
# the body (head center ~1.38 m up, ~0.28 m forward, matching its hit zone).
MUTANT_RIG = {
    "hips": (0, 0, 0.84), "spine": (0, -0.04, 0.98), "chest": (0, -0.1, 1.12), "upper": (0, -0.17, 1.24),
    "neck": (0, -0.24, 1.32), "head": (0, -0.27, 1.36), "head_top": (0, -0.3, 1.5),
    "clavicle": (0.04, -0.17, 1.28), "shoulder": (0.25, -0.17, 1.3), "elbow": (0.6, -0.17, 1.3),
    "wrist": (0.93, -0.17, 1.3), "fingers": (1.12, -0.17, 1.3),
    "hip": (0.13, 0, 0.82), "knee": (0.15, -0.05, 0.45), "ankle": (0.16, 0.02, 0.08),
    "ball": (0.16, -0.1, 0.03), "toe": (0.16, -0.2, 0.03),
}

MUTANT_THICK = {
    "pelvis": (0.17, 0.13), "waist": (0.18, 0.15), "ribs": (0.24, 0.17), "chest": (0.27, 0.18),
    "neck": (0.09, 0.09), "shoulder": (0.1, 0.1), "elbow": (0.065, 0.065), "wrist": (0.05, 0.045),
    "hand": (0.075, 0.03), "hip": (0.11, 0.11), "knee": (0.07, 0.075), "ankle": (0.05, 0.05),
    "heel": (0.06, 0.055), "toe": (0.07, 0.045),
}


def mutant_head(_name):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=18, v_segments=12, radius=1.0)
    for v in bm.verts:
        x, y, z = v.co
        # Low skull, heavy brow, long jaw jutting forward.
        jut = max(0.0, -y) * max(0.0, -z) * 0.05
        v.co = Vector((x * 0.11, y * 0.13 - jut, z * 0.105 + (0.015 if z > 0.5 and y < 0 else 0.0)))
        v.co += Vector((0, -0.31, 1.385))
    return from_bmesh(bm, "MutantHead", True)


def mutant_region(co, bone):
    x, y, z = co
    if bone.endswith("Hand") or bone.endswith("Foot") or bone.endswith("Toes"):
        return "ash"
    if bone.endswith("LowerArm"):
        return "skin_dark" if abs(x) > 0.75 else "skin"
    if bone.endswith("LowerLeg"):
        return "skin_dark" if z < 0.3 else "skin"
    if bone == "Hips" or (bone.endswith("UpperLeg") and z > 0.7):
        return "rag"
    # Darker blotches on the back.
    if y > 0.05 and math.sin(x * 40.0) * math.sin(z * 30.0) > 0.35:
        return "skin_dark"
    return "skin"


def build_mutant():
    reset_scene()
    p = MUTANT_PALETTE
    rig = dict(MUTANT_RIG)
    rig["head_shape"] = mutant_head
    gear = []
    glow = []
    # Bone spines along the hunched back.
    for i, (y, z, bone) in enumerate([(0.13, 1.05, "Spine"), (0.1, 1.18, "Chest"), (0.04, 1.3, "UpperChest"), (-0.04, 1.39, "UpperChest")]):
        gear.append((cyl("Spine", 0.03, 0.0, 0.16 - i * 0.015, xf((0, y, z), (-30 - i * 12, 0, 0)), 6, False), "bone", bone))
    # Growths on one shoulder.
    gear.append((ball("Growth", (0.09, 0.08, 0.07), xf((0.2, -0.12, 1.36))), "skin_dark", "UpperChest"))
    gear.append((ball("Growth2", (0.05, 0.05, 0.045), xf((0.27, -0.06, 1.34))), "skin_dark", "UpperChest"))
    # Jaw, teeth and glowing eyes.
    gear.append((box("Jaw", (0.13, 0.12, 0.04), xf((0, -0.38, 1.315), (10, 0, 0)), 0.02), "mouth", "Head"))
    for i in range(4):
        gear.append((cyl("Tooth", 0.008, 0.0, 0.03, xf((-0.045 + 0.03 * i, -0.43, 1.34), (0, 0, 0)), 4, False), "bone", "Head"))
    for s in (-1, 1):
        glow.append((ball("Eye", (0.03, 0.016, 0.02), xf((0.048 * s, -0.432, 1.405)), segments=8, rings=6), "eye", "Head"))
    # Claws: three per hand.
    for s in (-1, 1):
        side = "Left" if s > 0 else "Right"
        for i in range(3):
            gear.append((cyl("Claw", 0.014, 0.0, 0.14, xf((1.14 * s + 0.05 * s, -0.19 + 0.025 * i, 1.29), (0, 90 * s + 12 * s, 0)), 5, False), "bone", side + "Hand"))
        gear.append((ring("Band", 0.07, 0.065, 0.012, xf((0.82 * s, -0.17, 1.3), (0, 90, 0))), "rag", side + "LowerArm"))
    # A rag loincloth.
    gear.append((ring("Rope", 0.18, 0.14, 0.015, xf((0, 0, 0.86))), "rag", "Hips"))
    for y in (-1, 1):
        gear.append((box("Flap", (0.2, 0.02, 0.24), xf((0, 0.13 * y, 0.74), (10 * y, 0, 0)), 0.006), "rag", "Hips"))
    # Bone armor grown over the front (its own mesh, "Armor": only brutes
    # show it). The back stays soft.
    for i, (z, w) in enumerate([(1.3, 0.42), (1.17, 0.4), (1.04, 0.34)]):
        gear.append((box("ChestPlate", (w, 0.07, 0.12), xf((0, -0.3 + i * 0.07, z), (-25 + i * 8, 0, 0)), 0.03), "bone", "UpperChest" if i == 0 else ("Chest" if i == 1 else "Spine"), "Armor"))
    gear.append((ball("SkullPlate", (0.12, 0.1, 0.06), xf((0, -0.34, 1.47), (20, 0, 0)), cut_below=-0.3), "bone", "Head", "Armor"))
    for s_ in (-1, 1):
        side = "Left" if s_ > 0 else "Right"
        gear.append((box("ArmPlate", (0.22, 0.12, 0.1), xf((0.75 * s_, -0.21, 1.31)), 0.03), "bone", side + "LowerArm", "Armor"))
        gear.append((box("ShoulderPlate", (0.18, 0.16, 0.08), xf((0.27 * s_, -0.2, 1.4), (-20, 0, 0)), 0.03), "bone", "UpperChest", "Armor"))
        gear.append((box("ShinPlate", (0.1, 0.06, 0.24), xf((0.155 * s_, -0.09, 0.27)), 0.02), "bone", side + "LowerLeg", "Armor"))
    arm, objs = build_humanoid("Mutant", rig, MUTANT_THICK, mutant_region, p, gear, glow, [])
    export("mutant", [arm] + objs)


# ---------------------------------------------------------------- drone

DRONE_PALETTE = {
    "shell": (0.85, 0.82, 0.74),
    "dark": (0.12, 0.12, 0.13),
    "metal": (0.45, 0.45, 0.46),
    "accent": (0.92, 0.3, 0.12),
    "lens": (1.0, 0.25, 0.1),
    "blade": (0.2, 0.2, 0.21),
}


def build_drone():
    """Origin at the drone's center; faces -Y (Godot +Z, turned in game)."""
    reset_scene()
    p = DRONE_PALETTE
    frame = [
        (box("Body", (0.34, 0.42, 0.16), xf((0, 0, 0)), 0.05), p["shell"]),
        (box("Belly", (0.26, 0.3, 0.06), xf((0, 0.02, -0.1)), 0.02), p["dark"]),
        (box("Stripe", (0.345, 0.12, 0.04), xf((0, 0.08, 0.035)), 0.01), p["accent"]),
        (cyl("LensHood", 0.085, 0.075, 0.08, xf((0, -0.23, 0.0), (90, 0, 0)), 16), p["dark"]),
        (cyl("Antenna", 0.006, 0.004, 0.22, xf((0.08, 0.14, 0.18), (-12, 0, 0)), 5), p["dark"]),
        (box("SpeakerGrille", (0.12, 0.02, 0.06), xf((0, 0.21, 0.0)), 0.006), p["metal"]),
    ]
    for i in range(4):
        ang = 45 + 90 * i
        c, s = math.cos(math.radians(ang)), math.sin(math.radians(ang))
        frame.append((box("Arm", (0.36, 0.05, 0.035), xf((c * 0.26, s * 0.26, 0.02), (0, 0, ang)), 0.01), p["metal"]))
        frame.append((ring("Guard", 0.17, 0.17, 0.016, xf((c * 0.42, s * 0.42, 0.04)), 24), p["dark"]))
        frame.append((cyl("Motor", 0.035, 0.035, 0.06, xf((c * 0.42, s * 0.42, 0.04))), p["metal"]))
    frame_obj = merge_colored("Frame", frame)
    rotors = []
    for i in range(4):
        ang = 45 + 90 * i
        c, s = math.cos(math.radians(ang)), math.sin(math.radians(ang))
        center = (c * 0.42, s * 0.42, 0.08)
        blade = merge_colored("Rotor%d" % i, [
            (box("Blade", (0.3, 0.035, 0.008), xf(center, (0, 6, 30 * i)), 0.003), p["blade"]),
            (cyl("Hub", 0.018, 0.018, 0.02, xf(center)), p["metal"]),
        ])
        set_origin(blade, center)
        rotors.append(blade)
    lens = merge_colored("Lens", [(cyl("Glass", 0.06, 0.06, 0.02, xf((0, -0.27, 0.0), (90, 0, 0)), 16), p["lens"])])
    gun = merge_colored("Gun", [
        (box("Pod", (0.08, 0.16, 0.07), xf((0, -0.06, -0.16)), 0.015), p["dark"]),
        (cyl("Barrel", 0.014, 0.014, 0.2, xf((0, -0.2, -0.16), (90, 0, 0)), 8), p["dark"]),
    ])
    export("drone", [frame_obj, lens, gun] + rotors)


BUILDERS = {"raider": build_raider, "hunter": build_hunter, "juno": lambda: build_hunter(True), "soldier": build_soldier, "heavy": build_heavy, "mutant": build_mutant, "drone": build_drone}


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    names = [a for a in args if a in BUILDERS] or list(BUILDERS)
    for n in names:
        BUILDERS[n]()


if __name__ == "__main__":
    main()
    sys.exit(0)
