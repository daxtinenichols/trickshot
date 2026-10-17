"""Builds the prop kit (crates, wrecks, barricades, rooftop clutter, the
Host's loudspeakers and radio masts) and exports each prop to glTF.

Run with Blender 4.2+ (or the `bpy` Python module):
    blender --background --python art/source/build_props.py
    python3 art/source/build_props.py              # with `pip install bpy`
    python3 art/source/build_props.py crate_wood   # only some props

Output:
    art/props/<name>.glb   one mesh per prop, colors as vertex colors
    art/props/props.json   per prop: bounding size, box colliders, tags

Conventions (shared with art/props/prop_kit.gd):
  * Coordinates are Godot's (Y up, front toward -Z), in meters, converted to
    Blender on the way in. Each prop's origin is its bottom center (y = 0).
  * Colliders are a few boxes per prop, written next to the model in
    props.json, so the model and its collision come from one place. Gameplay
    reads geometry, not kinds: a 0.9 m crate is vaultable, a 1.8 m stack is a
    mantle, a container side is a wallrun, all by their size.
  * Every part is a beveled box, cylinder, cone, prism or lump. Parts are
    painted with vertex colors; the game's prop shader adds dust and grime.
    Vertex alpha 0 marks parts that glow (lamps, dials).
"""

import json
import math
import os
import random
import sys

import bpy  # must come before bmesh when run as a module
import bmesh
from mathutils import Euler, Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.normpath(os.path.join(HERE, "..", "props"))

PALETTE = {
    "wood": (0.55, 0.40, 0.24),
    "wood_dark": (0.36, 0.25, 0.15),
    "wood_grey": (0.54, 0.50, 0.44),
    "metal": (0.30, 0.31, 0.33),
    "metal_dark": (0.12, 0.12, 0.13),
    "steel": (0.58, 0.58, 0.58),
    "rust": (0.50, 0.26, 0.13),
    "rust_dark": (0.32, 0.17, 0.09),
    "concrete": (0.64, 0.62, 0.57),
    "concrete_dark": (0.45, 0.43, 0.40),
    "olive": (0.36, 0.38, 0.24),
    "teal": (0.24, 0.44, 0.44),
    "container": (0.56, 0.22, 0.15),
    "tarp_blue": (0.20, 0.36, 0.55),
    "tarp_tan": (0.62, 0.54, 0.38),
    "orange": (0.96, 0.45, 0.12),
    "static_red": (0.62, 0.11, 0.10),
    "black": (0.06, 0.06, 0.07),
    "rubber": (0.09, 0.09, 0.09),
    "plant": (0.32, 0.50, 0.21),
    "plant_dark": (0.20, 0.34, 0.14),
    "soil": (0.26, 0.19, 0.13),
    "sand": (0.66, 0.58, 0.42),
    "glass": (0.10, 0.12, 0.14),
    "white": (0.82, 0.80, 0.74),
    "yellow": (0.86, 0.68, 0.18),
    "lamp_red": (1.0, 0.18, 0.10),
    "lamp_amber": (1.0, 0.62, 0.22),
}
GLOW = {"lamp_red", "lamp_amber"}


# ---------------------------------------------------------------- geometry

def to_blender(v):
    """Godot (x, y, z) -> Blender (x, -z, y); glTF export maps it back."""
    return Vector((v[0], -v[2], v[1]))


def place(center, rot):
    """Godot-space matrix: rotation in degrees, applied Y, then X, then Z
    (Godot's default Euler order), then the move to `center`."""
    rx, ry, rz = (math.radians(a) for a in (rot or (0, 0, 0)))
    r = Matrix.Rotation(ry, 4, "Y") @ Matrix.Rotation(rx, 4, "X") @ Matrix.Rotation(rz, 4, "Z")
    return Matrix.Translation(Vector(center)) @ r


class Prop:
    """Collects one prop's parts, colliders and tags."""

    def __init__(self, name, seed=0):
        self.name = name
        self.parts = []      # (bmesh, color name)
        self.colliders = []  # {"size", "center", "rot"}
        self.tags = []
        self.rng = random.Random(hash(name) & 0xFFFF ^ seed)

    # -- parts

    def box(self, size, center, color, rot=None, bevel=0.02):
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        for v in bm.verts:
            v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
        if bevel > 0.0:
            # Small chamfers: the cel shader lights them as bright edges.
            w = min(bevel, min(size) * 0.25)
            bmesh.ops.bevel(bm, geom=list(bm.edges), offset=w, segments=1, affect="EDGES", profile=0.5)
        self._add(bm, place(center, rot), color)

    def cyl(self, radius, height, center, color, rot=None, seg=12, radius2=None):
        """Cylinder (or cone, with radius2) along Y before rotation."""
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg,
                              radius1=radius, radius2=radius if radius2 is None else radius2,
                              depth=height)
        # bmesh builds along Z; stand it up along Godot's Y.
        m = place(center, rot) @ Matrix.Rotation(-math.pi * 0.5, 4, "X")
        self._add(bm, m, color)

    def prism(self, profile, length, center, color, rot=None):
        """Extrudes a 2D (z, y) outline `length` m along X."""
        bm = bmesh.new()
        half = length * 0.5
        left = [bm.verts.new((-half, y, z)) for z, y in profile]
        right = [bm.verts.new((half, y, z)) for z, y in profile]
        bm.faces.new(left)
        bm.faces.new(list(reversed(right)))
        n = len(profile)
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((left[i], left[j], right[j], right[i]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        self._add(bm, place(center, rot), color)

    def lump(self, size, center, color, rot=None, rough=0.18):
        """A rough, low-poly blob: sandbags, rubble, leaves."""
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=2, radius=0.5)
        for v in bm.verts:
            v.co *= 1.0 + self.rng.uniform(-rough, rough)
        m = place(center, rot) @ Matrix.Diagonal(Vector((size[0], size[1], size[2], 1.0)))
        self._add(bm, m, color)

    def _add(self, bm, m, color):
        for v in bm.verts:
            v.co = m @ v.co
        self.parts.append((bm, color))

    # -- colliders and tags

    def collide(self, size, center, rot=None):
        self.colliders.append({
            "size": [round(s, 4) for s in size],
            "center": [round(c, 4) for c in center],
            "rot": [round(a, 3) for a in (rot or (0, 0, 0))],
        })

    def tag(self, *tags):
        self.tags.extend(tags)


# ---------------------------------------------------------------- props
# Each builder fills a Prop. Sizes come from the movement numbers: hurdles
# and vaults are up to ~1.1 m, mantles reach ~1.5 m above your hands, a
# runnable wall is ~3 m+ tall.

PROPS = {}


def prop(fn):
    PROPS[fn.__name__] = fn
    return fn


@prop
def crate_wood(p):
    """A 0.9 m courier crate: the standard vault."""
    _crate(p, (0.0, 0.0, 0.0), 0.0, 1.0, 0.9)
    p.collide((1.0, 0.9, 1.0), (0, 0.45, 0))
    p.tag("vault")


def _crate(p, base, yaw, w, h, stencil=True):
    r = math.radians(yaw)

    def at(x, y, z):
        return (base[0] + x * math.cos(r) + z * math.sin(r), base[1] + y, base[2] - x * math.sin(r) + z * math.cos(r))

    rot = (0, yaw, 0)
    p.box((w - 0.06, h - 0.04, w - 0.06), at(0, h * 0.5, 0), "wood", rot, 0.01)
    t = 0.07
    for sx in (-1, 1):
        for sz in (-1, 1):
            p.box((t, h, t), at(sx * (w - t) * 0.5, h * 0.5, sz * (w - t) * 0.5), "wood_dark", rot)
    for y in (t * 0.5, h - t * 0.5):
        for sz in (-1, 1):
            p.box((w, t, t), at(0, y, sz * (w - t) * 0.5), "wood_dark", rot)
            p.box((t, t, w), at(sz * (w - t) * 0.5, y, 0), "wood_dark", rot)
    # Diagonal braces on the front and back.
    ang = math.degrees(math.atan2(h - 2 * t, w - 2 * t))
    diag = math.hypot(w - 2 * t, h - 2 * t)
    for sz in (-1, 1):
        p.box((diag, t, 0.03), at(0, h * 0.5, sz * (w * 0.5 - 0.005)), "wood_dark", (0, yaw, ang * sz))
    if stencil:
        p.box((0.28, 0.12, 0.012), at(0.18, h * 0.72, -w * 0.5 - 0.012), "orange", rot, 0.0)


@prop
def crate_stack(p):
    """Two crates and a small one beside them: a 1.8 m mantle."""
    _crate(p, (-0.05, 0.0, 0.0), 0.0, 1.0, 0.9)
    _crate(p, (0.03, 0.9, 0.04), 7.0, 0.95, 0.85, stencil=False)
    _crate(p, (0.95, 0.0, 0.1), -12.0, 0.7, 0.6, stencil=False)
    p.collide((1.0, 0.9, 1.0), (-0.05, 0.45, 0.0))
    p.collide((0.95, 0.85, 0.95), (0.03, 1.325, 0.04), (0, 7, 0))
    p.collide((0.7, 0.6, 0.7), (0.95, 0.3, 0.1), (0, -12, 0))
    p.tag("mantle")


@prop
def pallet(p):
    for i in range(7):
        x = -0.54 + i * 0.18
        p.box((0.14, 0.025, 1.0), (x, 0.137, 0), "wood_grey", None, 0.005)
    for z in (-0.42, 0.0, 0.42):
        p.box((1.2, 0.1, 0.12), (0, 0.075, z), "wood_dark")
    p.box((0.14, 0.025, 1.0), (0.12, 0.012, 0.0), "wood_grey", None, 0.005)
    p.collide((1.2, 0.15, 1.0), (0, 0.075, 0))


@prop
def barrel_rust(p):
    p.cyl(0.29, 0.88, (0, 0.44, 0), "rust", seg=14)
    for y in (0.2, 0.62):
        p.cyl(0.30, 0.04, (0, y, 0), "rust_dark", seg=14)
    p.cyl(0.25, 0.02, (0, 0.885, 0), "metal_dark", seg=14)
    p.cyl(0.03, 0.02, (0.14, 0.895, 0.05), "metal", seg=8)
    p.box((0.2, 0.25, 0.01), (0, 0.45, -0.29), "yellow", None, 0.0)
    p.collide((0.6, 0.9, 0.6), (0, 0.45, 0))
    p.tag("vault")


@prop
def shipping_container(p):
    """A 6 m dock container lying along X: wallrun its sides, run its roof."""
    L, H, W = 6.0, 2.6, 2.44
    p.box((L - 0.2, H - 0.2, W - 0.12), (0, H * 0.5, 0), "container", None, 0.0)
    # Corrugation on the long sides.
    n = 22
    for i in range(n):
        x = -L * 0.5 + 0.25 + i * (L - 0.5) / (n - 1)
        for sz in (-1, 1):
            p.box((0.12, H - 0.3, 0.04), (x, H * 0.5, sz * (W * 0.5 - 0.03)), "container", None, 0.01)
    # Frame: corner posts and top/bottom rails.
    for sx in (-1, 1):
        for sz in (-1, 1):
            p.box((0.16, H, 0.16), (sx * (L * 0.5 - 0.08), H * 0.5, sz * (W * 0.5 - 0.08)), "rust_dark")
    for y in (0.08, H - 0.08):
        for sz in (-1, 1):
            p.box((L, 0.16, 0.16), (0, y, sz * (W * 0.5 - 0.08)), "rust_dark")
        for sx in (-1, 1):
            p.box((0.16, 0.16, W), (sx * (L * 0.5 - 0.08), y, 0), "rust_dark")
    # Doors on +X with lock bars.
    for sz in (-1, 1):
        p.box((0.04, H - 0.4, W * 0.5 - 0.12), (L * 0.5 - 0.02, H * 0.5, sz * W * 0.25), "container", None, 0.01)
        for k in (-0.3, 0.3):
            p.cyl(0.025, H - 0.3, (L * 0.5 + 0.02, H * 0.5, sz * W * 0.25 + k), "steel", seg=6)
    # A courier route mark: an orange slash on one side.
    p.box((1.2, 0.18, 0.01), (-1.4, 1.5, -W * 0.5 - 0.06), "orange", (0, 0, 18), 0.0)
    p.collide((L, H, W), (0, H * 0.5, 0))
    p.tag("wallrun", "roof")


@prop
def water_tank(p):
    """A rooftop water tank on legs."""
    legs_h = 1.5
    r = 1.15
    for sx in (-1, 1):
        for sz in (-1, 1):
            p.box((0.14, legs_h, 0.14), (sx * 0.8, legs_h * 0.5, sz * 0.8), "rust_dark")
            p.collide((0.14, legs_h, 0.14), (sx * 0.8, legs_h * 0.5, sz * 0.8))
    for sz in (-1, 1):
        p.box((1.74, 0.08, 0.08), (0, 0.6, sz * 0.8), "rust_dark")
        p.box((0.08, 0.08, 1.74), (sz * 0.8, 0.6, 0), "rust_dark")
    p.box((2.0, 0.12, 2.0), (0, legs_h + 0.06, 0), "wood_dark")
    p.cyl(r, 2.0, (0, legs_h + 0.12 + 1.0, 0), "wood_grey", seg=16)
    for y in (0.4, 1.0, 1.6):
        p.cyl(r + 0.03, 0.06, (0, legs_h + 0.12 + y, 0), "metal_dark", seg=16)
    p.cyl(r + 0.05, 0.5, (0, legs_h + 2.37, 0), "rust", seg=16, radius2=0.12)
    p.cyl(0.08, 1.4, (0.55, 0.7, 0.55), "metal", seg=8)
    p.collide((2.0, 2.12, 2.0), (0, legs_h + 1.06, 0))
    p.tag("cover")


@prop
def ac_unit(p):
    """A rooftop air-con box: vault it or run over it."""
    p.box((1.6, 0.95, 1.0), (0, 0.55, 0), "white")
    p.box((1.7, 0.1, 1.1), (0, 0.05, 0), "metal_dark")
    p.cyl(0.36, 0.06, (-0.35, 1.04, 0), "metal_dark", seg=16)
    for a in (0, 60, 120):
        p.box((0.66, 0.02, 0.07), (-0.35, 1.06, 0), "metal", (0, a, 0), 0.0)
    for i in range(6):
        p.box((0.5, 0.03, 0.01), (0.4, 0.3 + i * 0.1, -0.505), "metal_dark", None, 0.0)
    p.cyl(0.06, 0.5, (0.85, 0.3, 0.25), "rust", (0, 0, 90), seg=8)
    p.box((0.6, 0.25, 0.01), (-0.4, 0.45, -0.506), "rust", None, 0.0)
    p.collide((1.6, 1.05, 1.0), (0, 0.525, 0))
    p.tag("vault")


@prop
def vent_stack(p):
    p.box((0.6, 0.12, 0.6), (0, 0.06, 0), "metal_dark")
    p.cyl(0.18, 1.5, (0, 0.85, 0), "metal", seg=12)
    p.cyl(0.32, 0.12, (0, 1.65, 0), "rust", seg=12, radius2=0.05)
    for a in (0, 90):
        p.box((0.02, 0.12, 0.5), (0, 1.56, 0), "metal_dark", (0, a, 0), 0.0)
    p.collide((0.4, 1.7, 0.4), (0, 0.85, 0))


@prop
def satellite_dish(p):
    p.box((0.7, 0.1, 0.7), (0, 0.05, 0), "metal_dark")
    p.cyl(0.06, 1.1, (0, 0.6, 0), "metal", seg=8)
    p.cyl(0.7, 0.18, (0, 1.35, -0.1), "white", (-62, 0, 0), seg=16, radius2=0.2)
    p.cyl(0.02, 0.7, (0, 1.55, -0.38), "metal", (-62, 0, 0), seg=6)
    p.box((0.08, 0.1, 0.08), (0, 1.73, -0.68), "metal_dark")
    p.box((0.5, 0.12, 0.01), (0.1, 1.4, -0.21), "static_red", (-62, 0, 0), 0.0)
    p.collide((0.2, 1.2, 0.2), (0, 0.6, 0))


@prop
def antenna_mast(p):
    """A 12 m lattice radio mast, the Static's relay: three legs, cross
    braces, dipoles on top and a red warning lamp."""
    H = 12.0
    r = 0.45
    legs = [(r * math.cos(a), r * math.sin(a)) for a in (math.radians(90), math.radians(210), math.radians(330))]
    for x, z in legs:
        p.cyl(0.04, H, (x, H * 0.5, z), "rust_dark", seg=6)
    step = 1.0
    i = 0
    y = 0.4
    while y < H - 0.5:
        for k in range(3):
            a = legs[k]
            b = legs[(k + 1) % 3]
            mx, mz = (a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5
            yaw = math.degrees(math.atan2(-(b[1] - a[1]), b[0] - a[0]))
            span = math.hypot(b[0] - a[0], b[1] - a[1])
            p.box((span, 0.03, 0.03), (mx, y, mz), "rust", (0, yaw, 0), 0.0)
            d = math.hypot(span, step)
            tilt = math.degrees(math.atan2(step, span)) * (1 if i % 2 == 0 else -1)
            p.box((d, 0.025, 0.025), (mx, y + step * 0.5, mz), "rust", (0, yaw, tilt), 0.0)
        y += step
        i += 1
    p.cyl(0.05, 2.0, (0, H + 1.0, 0), "metal", seg=8)
    for k, y in enumerate((H + 0.4, H + 1.0, H + 1.6)):
        p.box((1.6 - k * 0.4, 0.04, 0.04), (0, y, 0), "steel", (0, k * 60, 0), 0.0)
    p.cyl(0.09, 0.16, (0, H + 2.08, 0), "lamp_red", seg=8)
    p.box((0.5, 0.6, 0.3), (0, 2.0, 0.0), "metal_dark")
    p.box((0.4, 0.3, 0.01), (0, 2.05, -0.16), "static_red", None, 0.0)
    p.collide((0.9, H, 0.9), (0, H * 0.5, 0))
    p.tag("landmark")


@prop
def loudspeaker_pole(p):
    """The Host's voice on every street: a pole of horn speakers."""
    H = 4.6
    p.box((0.5, 0.1, 0.5), (0, 0.05, 0), "metal_dark")
    p.cyl(0.07, H, (0, H * 0.5, 0), "metal", seg=8)
    p.box((0.3, 0.4, 0.2), (0, 2.2, 0.08), "olive")
    p.box((0.16, 0.06, 0.01), (0, 2.28, -0.025), "lamp_amber", None, 0.0)
    for k, (yaw, pitch) in enumerate(((0, -12), (120, -18), (240, -10))):
        y = H - 0.35 - k * 0.12
        r = math.radians(yaw)
        dx, dz = -math.sin(r), -math.cos(r)
        p.box((0.08, 0.08, 0.3), (dx * 0.12, y, dz * 0.12), "metal_dark", (0, yaw, 0))
        p.cyl(0.08, 0.16, (dx * 0.3, y, dz * 0.3), "olive", (pitch - 90, yaw, 0), seg=10)
        p.cyl(0.09, 0.55, (dx * 0.62, y - 0.04, dz * 0.62), "olive", (pitch - 90, yaw, 0), seg=10, radius2=0.3)
        p.cyl(0.27, 0.01, (dx * 0.9, y - 0.08, dz * 0.9), "black", (pitch - 90, yaw, 0), seg=10)
    # Cable down the pole and a static-noise paint band.
    p.cyl(0.015, H - 0.6, (0.09, (H - 0.6) * 0.5 + 0.3, 0), "black", seg=5)
    for k in range(3):
        p.box((0.16, 0.04, 0.16), (0, 1.2 + k * 0.09, 0), "static_red" if k % 2 == 0 else "black", None, 0.0)
    p.collide((0.18, H, 0.18), (0, H * 0.5, 0))
    p.tag("story")


@prop
def planter_tub(p):
    """A half-barrel of rooftop greens from a Line camp."""
    p.cyl(0.45, 0.5, (0, 0.25, 0), "wood", seg=14, radius2=0.5)
    for y in (0.1, 0.4):
        p.cyl(0.48 + y * 0.1, 0.04, (0, y, 0), "metal_dark", seg=14)
    p.cyl(0.46, 0.03, (0, 0.47, 0), "soil", seg=14)
    for i in range(6):
        a = i * 1.05 + p.rng.uniform(-0.3, 0.3)
        rr = p.rng.uniform(0.1, 0.3)
        s = p.rng.uniform(0.22, 0.34)
        p.lump((s, s * 1.2, s), (math.cos(a) * rr, 0.6 + p.rng.uniform(0, 0.12), math.sin(a) * rr), "plant" if i % 2 else "plant_dark")
    p.collide((1.0, 0.55, 1.0), (0, 0.275, 0))


@prop
def tarp_shelter(p):
    """A camp lean-to: four posts and a sagging tarp."""
    for x, z, h in ((-1.4, -1.1, 2.4), (1.4, -1.1, 2.4), (-1.4, 1.1, 1.8), (1.4, 1.1, 1.8)):
        p.box((0.09, h, 0.09), (x, h * 0.5, z), "wood_grey")
        p.collide((0.09, h, 0.09), (x, h * 0.5, z))
    slope = math.degrees(math.atan2(0.6, 2.2))
    p.box((3.1, 0.03, 1.2), (-0.0, 2.27, -0.55), "tarp_blue", (slope, 0, 0), 0.0)
    p.box((3.1, 0.03, 1.2), (0.0, 1.98, 0.55), "tarp_blue", (slope + 6, 0, 0), 0.0)
    p.box((0.9, 0.03, 0.9), (0.9, 2.3, -0.3), "tarp_tan", (slope, 0, 3), 0.0)
    for x in (-1.4, 1.4):
        p.box((0.04, 0.04, 2.3), (x, 2.12, 0), "wood_dark", (slope, 0, 0), 0.0)
    _crate(p, (-0.7, 0.0, 0.3), 15, 0.6, 0.5, stencil=False)
    p.collide((0.6, 0.5, 0.6), (-0.7, 0.25, 0.3), (0, 15, 0))
    p.cyl(0.18, 0.04, (0.6, 0.02, 0.4), "metal_dark", seg=10)
    p.tag("camp")


@prop
def railing(p):
    """A 2 m roof-edge railing: a waist-high vault."""
    for x in (-0.95, 0.95):
        p.box((0.06, 1.05, 0.06), (x, 0.525, 0), "rust")
    p.box((2.0, 0.06, 0.06), (0, 1.02, 0), "rust")
    p.box((2.0, 0.04, 0.04), (0, 0.55, 0), "rust_dark")
    p.box((0.06, 0.5, 0.06), (0.3, 0.75, 0), "rust_dark", (0, 0, 14))
    p.collide((2.0, 1.05, 0.08), (0, 0.525, 0))
    p.tag("vault")


@prop
def scaffold_bay(p):
    """One 2 x 1.2 m bay of scaffolding, 3 m tall, decked at 1.5 m and 3 m."""
    W, D, H = 2.0, 1.2, 3.0
    for sx in (-1, 1):
        for sz in (-1, 1):
            p.cyl(0.03, H + 0.3, (sx * W * 0.5, (H + 0.3) * 0.5, sz * D * 0.5), "steel", seg=6)
    for y in (0.15, 1.5, H):
        for sz in (-1, 1):
            p.cyl(0.025, W, (0, y, sz * D * 0.5), "steel", (0, 0, 90), seg=6)
        for sx in (-1, 1):
            p.cyl(0.025, D, (sx * W * 0.5, y, 0), "steel", (90, 0, 0), seg=6)
    diag = math.hypot(W, 1.35)
    p.cyl(0.02, diag, (0, 0.82, D * 0.5), "steel", (0, 0, math.degrees(math.atan2(W, 1.35))), seg=6)
    for y in (1.5, H):
        for i in range(4):
            p.box((W - 0.04, 0.04, 0.27), (0, y + 0.045, -0.43 + i * 0.29), "wood" if i % 2 else "wood_grey", None, 0.005)
        p.collide((W, 0.1, D), (0, y + 0.03, 0))
    for sx in (-1, 1):
        for sz in (-1, 1):
            p.collide((0.06, H + 0.3, 0.06), (sx * W * 0.5, (H + 0.3) * 0.5, sz * D * 0.5))
    p.box((W - 0.1, 0.5, 0.01), (0, 3.6, -D * 0.5), "orange", None, 0.0)
    p.tag("climb")


@prop
def plank_bridge(p):
    """A 4 m run of planks across a gap (runs along Z)."""
    n = 0
    z = -1.9
    while z < 1.95:
        w = p.rng.uniform(0.2, 0.28)
        p.box((0.82 + p.rng.uniform(-0.05, 0.05), 0.05, w - 0.03), (p.rng.uniform(-0.03, 0.03), 0.075, z + w * 0.5), "wood_grey" if n % 3 else "wood", (0, p.rng.uniform(-3, 3), 0), 0.006)
        z += w
        n += 1
    for x in (-0.36, 0.36):
        p.box((0.1, 0.06, 4.0), (x, 0.025, 0), "wood_dark")
    p.collide((0.8, 0.1, 4.0), (0, 0.05, 0))
    p.tag("bridge")


@prop
def car_wreck(p):
    """A rusted sedan on flat tires, nose toward -Z: vault the hood."""
    paint = "teal"
    p.box((1.8, 0.62, 4.4), (0, 0.55, 0), paint, None, 0.06)
    p.box((1.82, 0.12, 4.42), (0, 0.3, 0), "rust_dark", None, 0.03)
    # Cabin, narrowing up; windows are dark.
    p.prism([(-1.2, 0.0), (1.0, 0.0), (0.7, 0.5), (-0.7, 0.5)], 1.6, (0, 0.86, 0.15), paint)
    p.prism([(-1.15, 0.02), (0.95, 0.02), (0.66, 0.44), (-0.66, 0.44)], 1.64, (0, 0.88, 0.15), "glass")
    p.box((1.5, 0.04, 1.3), (0, 1.37, 0.15), paint, None, 0.01)
    # Hood dented, rust patches.
    p.box((1.6, 0.04, 1.2), (0, 0.87, -1.55), "rust", (-3, 0, 2), 0.0)
    p.box((0.6, 0.02, 0.9), (0.4, 0.865, 1.6), "rust", None, 0.0)
    for sz, z in ((-1, -2.21), (1, 2.21)):
        p.box((1.84, 0.16, 0.12), (0, 0.38, z), "metal")
        for x in (-0.65, 0.65):
            p.box((0.3, 0.12, 0.03), (x, 0.62, z + sz * 0.005), "white" if sz < 0 else "static_red", None, 0.0)
    for sx in (-1, 1):
        for z in (-1.35, 1.35):
            p.cyl(0.33, 0.22, (sx * 0.84, 0.25, z), "rubber", (0, 0, 90), seg=12)
            p.cyl(0.18, 0.24, (sx * 0.84, 0.25, z), "metal", (0, 0, 90), seg=8)
    p.box((0.9, 0.3, 0.01), (-0.92, 0.6, 0.6), "orange", (0, 90, -14), 0.0)
    p.collide((1.8, 0.9, 4.4), (0, 0.45, 0))
    p.collide((1.6, 0.5, 2.2), (0, 1.15, 0.15))
    p.tag("vault", "cover")


@prop
def barricade_jersey(p):
    """A 2 m concrete road barrier (0.8 m): a quick vault."""
    p.prism([(-0.3, 0.0), (0.3, 0.0), (0.3, 0.08), (0.13, 0.25), (0.1, 0.8), (-0.1, 0.8), (-0.13, 0.25), (-0.3, 0.08)], 2.0, (0, 0, 0), "concrete")
    for x in (-0.5, 0.5):
        p.box((0.3, 0.06, 0.62), (x, 0.03, 0), "concrete_dark", None, 0.0)
    p.box((0.7, 0.14, 0.01), (-0.3, 0.55, -0.12), "orange", (8, 0, 0), 0.0)
    p.box((0.5, 0.1, 0.01), (0.45, 0.4, 0.15), "static_red", (-15, 0, 4), 0.0)
    p.collide((2.0, 0.8, 0.5), (0, 0.4, 0))
    p.tag("vault")


@prop
def barricade_scrap(p):
    """A Static roadblock: sheet metal, tires and rebar spikes, 1.6 m."""
    for i, x in enumerate((-1.0, 0.0, 1.0)):
        p.box((1.1, 1.5, 0.05), (x + p.rng.uniform(-0.05, 0.05), 0.75, p.rng.uniform(-0.05, 0.05)), "rust" if i != 1 else "metal", (p.rng.uniform(-6, 2), 0, p.rng.uniform(-4, 4)), 0.01)
    for x in (-1.45, -0.5, 0.5, 1.45):
        p.box((0.1, 1.6, 0.1), (x, 0.8, 0.12), "wood_dark")
    p.box((3.0, 0.1, 0.1), (0, 1.1, 0.12), "wood_dark")
    for x in (-0.9, 0.6):
        p.cyl(0.35, 0.24, (x, 0.12, -0.3), "rubber", seg=12)
        p.cyl(0.35, 0.24, (x + 0.1, 0.36, -0.32), "rubber", seg=12)
    for i in range(7):
        x = -1.3 + i * 0.43
        p.cyl(0.015, 0.5, (x, 1.7, -0.08), "rust_dark", (p.rng.uniform(-30, -10), 0, p.rng.uniform(-10, 10)), seg=5)
    # The Static's tag: noise bars.
    for k in range(4):
        p.box((0.8 - k * 0.15, 0.06, 0.01), (0.05 + k * 0.05, 0.9 + k * 0.1, -0.06), "static_red" if k % 2 == 0 else "black", None, 0.0)
    p.collide((3.0, 1.6, 0.6), (0, 0.8, 0))
    p.tag("mantle", "cover")


@prop
def sandbag_wall(p):
    """A 2 m wall of sandbags, 1 m tall: vault or take cover."""
    rows = 4
    for r in range(rows):
        n = 5 if r % 2 == 0 else 4
        off = 0.0 if r % 2 == 0 else 0.2
        for i in range(n):
            x = -0.8 + off + i * 0.4
            p.lump((0.42, 0.26, 0.5 - r * 0.04), (x, 0.13 + r * 0.24, r * 0.03), "sand" if (i + r) % 3 else "tarp_tan", (0, p.rng.uniform(-8, 8), 0), 0.04)
    p.collide((2.0, 1.0, 0.55), (0, 0.5, 0.04))
    p.tag("vault", "cover")


@prop
def debris_pile(p):
    """Rubble: concrete chunks and rebar, ~0.8 m high."""
    chunks = [
        ((1.2, 0.5, 0.9), (0.0, 0.25, 0.0), (6, 20, -4)),
        ((0.9, 0.4, 0.7), (0.9, 0.18, 0.4), (-8, -30, 10)),
        ((0.8, 0.35, 0.6), (-0.9, 0.16, -0.3), (12, 50, 6)),
        ((0.7, 0.3, 0.5), (0.2, 0.62, -0.1), (-14, 10, 18)),
        ((0.5, 0.25, 0.4), (-0.4, 0.12, 0.7), (4, -15, -10)),
    ]
    for size, c, rot in chunks:
        p.box(size, c, "concrete" if size[0] > 0.6 else "concrete_dark", rot, 0.05)
    for i in range(7):
        a = p.rng.uniform(0, math.tau)
        r = p.rng.uniform(0.6, 1.3)
        s = p.rng.uniform(0.12, 0.25)
        p.lump((s, s * 0.7, s), (math.cos(a) * r, s * 0.3, math.sin(a) * r), "concrete_dark", None, 0.25)
    for i in range(3):
        p.cyl(0.012, 1.1, (p.rng.uniform(-0.5, 0.5), 0.6, p.rng.uniform(-0.3, 0.3)), "rust_dark", (p.rng.uniform(-50, 50), p.rng.uniform(0, 180), p.rng.uniform(-30, 30)), seg=5)
    p.collide((1.2, 0.5, 0.9), (0.0, 0.25, 0.0), (6, 20, -4))
    p.collide((0.9, 0.4, 0.7), (0.9, 0.18, 0.4), (-8, -30, 10))
    p.collide((0.8, 0.35, 0.6), (-0.9, 0.16, -0.3), (12, 50, 6))
    p.tag("clutter")


@prop
def dumpster(p):
    p.prism([(-0.55, 0.15), (0.55, 0.15), (0.6, 1.15), (-0.6, 1.15)], 1.9, (0, 0, 0), "olive", (0, 0, 0))
    p.box((1.95, 0.06, 1.25), (0, 1.17, 0), "olive", None, 0.01)
    p.box((0.95, 0.04, 1.2), (0.47, 1.23, 0.05), "metal_dark", (-8, 0, 0), 0.0)
    p.box((0.95, 0.04, 1.2), (-0.47, 1.25, 0.05), "metal_dark", (-3, 0, 0), 0.0)
    p.box((0.4, 0.3, 0.3), (-0.5, 1.4, 0.1), "tarp_tan", (0, 20, 0), 0.04)
    for x in (-0.8, 0.8):
        for z in (-0.4, 0.4):
            p.cyl(0.07, 0.06, (x, 0.07, z), "rubber", (0, 0, 90), seg=8)
    for x in (-0.95, 0.95):
        p.box((0.06, 0.1, 1.0), (x * 1.01, 0.95, 0), "rust_dark")
    p.box((0.9, 0.35, 0.01), (0.2, 0.6, -0.58), "static_red", (4, 0, 0), 0.0)
    p.collide((1.9, 1.2, 1.2), (0, 0.6, 0))
    p.tag("mantle", "cover")


@prop
def tire_stack(p):
    for i in range(3):
        y = 0.12 + i * 0.24
        x = p.rng.uniform(-0.04, 0.04)
        p.cyl(0.36, 0.23, (x, y, 0), "rubber", seg=14)
        p.cyl(0.2, 0.235, (x, y, 0), "black", seg=10)
        p.cyl(0.16, 0.24, (x, y, 0), "metal", seg=10)
    p.collide((0.72, 0.72, 0.72), (0, 0.36, 0))
    p.tag("vault")


@prop
def billboard(p):
    """A roadside billboard (6 x 3 m panel at 5-8 m), papered over with the
    Static's on-air posters. The panel is a wallrun."""
    for x in (-2.0, 2.0):
        p.box((0.25, 5.2, 0.25), (x, 2.6, 0.15), "rust_dark")
        p.collide((0.25, 5.2, 0.25), (x, 2.6, 0.15))
    p.box((6.2, 3.2, 0.2), (0, 6.6, 0), "metal_dark")
    p.box((6.0, 3.0, 0.02), (0, 6.6, -0.11), "white", None, 0.0)
    # Poster: red frame, black stripes like a broken signal, an orange tear.
    p.box((5.6, 0.3, 0.01), (0, 7.75, -0.125), "static_red", None, 0.0)
    for k in range(5):
        w = 4.6 - (k % 3) * 0.9
        p.box((w, 0.16, 0.01), (-0.3 + (k % 2) * 0.4, 7.25 - k * 0.32, -0.125), "black", None, 0.0)
    p.box((1.0, 1.2, 0.01), (2.1, 5.9, -0.126), "white", (0, 0, 12), 0.0)
    p.box((0.9, 0.25, 0.012), (-2.0, 5.5, -0.127), "orange", (0, 0, -20), 0.0)
    # Catwalk under the panel.
    p.box((6.0, 0.06, 0.6), (0, 4.98, -0.35), "metal", None, 0.0)
    for x in (-2.8, -1.4, 0.0, 1.4, 2.8):
        p.box((0.04, 0.04, 0.6), (x, 4.94, -0.35), "rust_dark", None, 0.0)
    p.collide((6.2, 3.2, 0.2), (0, 6.6, 0))
    p.collide((6.0, 0.06, 0.6), (0, 4.98, -0.35))
    p.tag("wallrun", "story")


@prop
def street_sign(p):
    p.cyl(0.04, 2.9, (0, 1.45, 0), "metal", (0, 0, 4), seg=8)
    p.box((0.9, 0.22, 0.02), (0.1, 2.75, 0), "teal", (0, 0, 4), 0.0)
    p.box((0.75, 0.2, 0.02), (0.1, 2.55, 0), "teal", (0, 90, 4), 0.0)
    p.box((0.5, 0.5, 0.02), (0.08, 2.05, -0.01), "yellow", (0, 0, 45 + 4), 0.0)
    p.collide((0.1, 2.9, 0.1), (0, 1.45, 0))


@prop
def fence_chainlink(p):
    """A 3 m chain-link panel, 2.2 m tall: climb it or wallrun it."""
    W, H = 3.0, 2.2
    for x in (-1.5, 1.5):
        p.cyl(0.04, H + 0.1, (x, (H + 0.1) * 0.5, 0), "steel", seg=8)
    p.cyl(0.025, W, (0, H, 0), "steel", (0, 0, 90), seg=6)
    p.cyl(0.02, W, (0, 0.08, 0), "steel", (0, 0, 90), seg=6)
    step = 0.15
    x = -1.5 + step
    while x < 1.5 - 0.01:
        p.box((0.008, H - 0.1, 0.008), (x, H * 0.5, 0), "metal", None, 0.0)
        x += step
    y = 0.2
    while y < H - 0.05:
        p.box((W, 0.008, 0.008), (0, y, 0), "metal", None, 0.0)
        y += step
    for i in range(10):
        p.cyl(0.012, 0.25, (-1.4 + i * 0.31, H + 0.15, 0), "rust_dark", (0, 0, 35 if i % 2 else -35), seg=4)
    p.box((0.7, 0.4, 0.015), (0.5, 1.3, -0.02), "static_red", (0, 0, -3), 0.0)
    p.collide((W, H, 0.08), (0, H * 0.5, 0))
    p.tag("wallrun", "climb")


@prop
def generator(p):
    """A raider generator: what powers the Host's speakers."""
    for x in (-0.7, 0.7):
        for z in (-0.4, 0.4):
            p.cyl(0.025, 0.9, (x, 0.45, z), "rust_dark", seg=6)
    for y in (0.05, 0.9):
        for z in (-0.4, 0.4):
            p.cyl(0.025, 1.4, (0, y, z), "rust_dark", (0, 0, 90), seg=6)
    p.box((0.7, 0.55, 0.6), (-0.3, 0.38, 0), "yellow")
    p.cyl(0.18, 0.45, (0.35, 0.4, 0), "metal_dark", (0, 0, 90), seg=12)
    p.box((1.3, 0.25, 0.7), (0, 0.78, 0), "static_red")
    p.cyl(0.06, 0.12, (0.3, 0.96, 0.1), "metal", seg=8)
    p.cyl(0.04, 0.5, (0.6, 0.95, -0.25), "rust", seg=8)
    p.box((0.18, 0.12, 0.01), (-0.3, 0.45, -0.31), "metal_dark", None, 0.0)
    p.box((0.05, 0.05, 0.01), (-0.2, 0.47, -0.32), "lamp_amber", None, 0.0)
    p.collide((1.45, 0.92, 0.85), (0, 0.46, 0))
    p.tag("vault")


@prop
def radio_set(p):
    """A camp radio on a crate: Mags's rig, or one left playing the Host."""
    _crate(p, (0, 0, 0), 0, 0.7, 0.6, stencil=False)
    p.box((0.5, 0.28, 0.32), (0, 0.74, 0), "olive")
    p.box((0.44, 0.03, 0.01), (0, 0.84, -0.165), "metal_dark", None, 0.0)
    for x in (-0.15, -0.05):
        p.cyl(0.035, 0.03, (x, 0.7, -0.17), "metal_dark", (90, 0, 0), seg=10)
    p.box((0.14, 0.08, 0.01), (0.13, 0.72, -0.165), "lamp_amber", None, 0.0)
    for i in range(4):
        p.box((0.12, 0.012, 0.01), (0.13, 0.66 - i * 0.02, -0.165), "black", None, 0.0)
    p.cyl(0.008, 0.9, (0.2, 1.3, 0.1), "steel", (0, 0, -12), seg=5)
    p.box((0.12, 0.04, 0.06), (-0.14, 0.9, 0.0), "metal_dark")
    p.collide((0.7, 0.88, 0.7), (0, 0.44, 0))
    p.tag("story", "vault")


@prop
def tape_cassette(p):
    """A lost broadcast tape (collectible), drawn 3x size so it reads at
    speed. Floats; no collider (missions add the pickup area)."""
    s = 3.0
    p.box((0.1 * s, 0.064 * s, 0.012 * s), (0, 0.032 * s, 0), "black", None, 0.004)
    p.box((0.08 * s, 0.03 * s, 0.002 * s), (0, 0.04 * s, -0.006 * s - 0.001), "white", None, 0.0)
    p.box((0.05 * s, 0.012 * s, 0.002 * s), (0, 0.04 * s, -0.006 * s - 0.004), "glass", None, 0.0)
    for x in (-0.022, 0.022):
        p.cyl(0.008 * s, 0.014 * s, (x * s, 0.04 * s, 0), "white", (90, 0, 0), seg=8)
    p.box((0.08 * s, 0.008 * s, 0.002 * s), (0, 0.055 * s, -0.006 * s - 0.003), "orange", None, 0.0)
    p.tag("collectible")


@prop
def chalk_arrow(p):
    """An orange courier route mark painted on the ground, pointing -Z."""
    p.box((0.18, 0.004, 0.9), (0, 0.002, 0.15), "orange", None, 0.0)
    p.prism([(-0.05, 0.0), (0.35, 0.0), (0.35, 0.004), (-0.05, 0.004)], 0.18, (0.13, 0.002, -0.4), "orange", (0, -35 + 90, 0))
    p.prism([(-0.05, 0.0), (0.35, 0.0), (0.35, 0.004), (-0.05, 0.004)], 0.18, (-0.13, 0.002, -0.4), "orange", (0, 35 + 90, 0))
    p.tag("decal")


# ---------------------------------------------------------------- export

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def build_mesh(p):
    """Joins the parts into one Blender object with vertex colors."""
    bm = bmesh.new()
    color_layer = bm.loops.layers.color.new("Col")
    top = 0.0
    for part, _ in p.parts:
        for v in part.verts:
            top = max(top, v.co.y)
    top = max(top, 0.3)
    for part, color in p.parts:
        base = Vector(PALETTE[color])
        glow = color in GLOW
        jitter = 1.0 if glow else p.rng.uniform(0.92, 1.06)
        index = {}
        for v in part.verts:
            index[v] = bm.verts.new(to_blender(v.co))
        for f in part.faces:
            nf = bm.faces.new([index[v] for v in f.verts])
            for loop, src in zip(nf.loops, f.verts):
                y = src.co.y
                # Fake ambient occlusion: darker toward the ground.
                ao = 1.0 if glow else 0.72 + 0.28 * min(1.0, max(0.0, y / min(top, 1.2)))
                c = base * jitter * ao
                loop[color_layer] = (min(c.x, 1.0), min(c.y, 1.0), min(c.z, 1.0), 0.0 if glow else 1.0)
        part.free()
    mesh = bpy.data.meshes.new(p.name)
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    mesh.color_attributes.active_color = mesh.color_attributes["Col"]
    mesh.color_attributes.render_color_index = mesh.color_attributes.active_color_index
    for poly in mesh.polygons:
        poly.use_smooth = False
    obj = bpy.data.objects.new(p.name, mesh)
    bpy.context.collection.objects.link(obj)
    mat = bpy.data.materials.new("Prop")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    attr = nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    mat.node_tree.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    mesh.materials.append(mat)
    return obj


def bounds(obj):
    """Godot-space size of the mesh (x, y, z)."""
    xs = [v.co.x for v in obj.data.vertices]
    ys = [-v.co.y for v in obj.data.vertices]  # Blender -y is Godot z
    zs = [v.co.z for v in obj.data.vertices]
    return [max(xs) - min(xs), max(zs) - min(zs), max(ys) - min(ys)], min(zs)


def export(name, catalog):
    reset_scene()
    p = Prop(name)
    PROPS[name](p)
    obj = build_mesh(p)
    size, bottom = bounds(obj)
    path = os.path.join(OUT_DIR, name + ".glb")
    for o in bpy.context.selected_objects:
        o.select_set(False)
    obj.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=False,
        export_animations=False,
        export_vertex_color="ACTIVE",
        export_all_vertex_colors=False,
    )
    tris = sum(len(poly.vertices) - 2 for poly in obj.data.polygons)
    catalog[name] = {
        "size": [round(s, 3) for s in size],
        "bottom": round(bottom, 3),
        "colliders": p.colliders,
        "tags": p.tags,
        "tris": tris,
        "about": (PROPS[name].__doc__ or "").strip().split("\n")[0],
    }
    print("wrote %-22s tris %5d  size %s" % (name, tris, catalog[name]["size"]))


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    names = [a for a in args if a in PROPS] or list(PROPS)
    catalog_path = os.path.join(OUT_DIR, "props.json")
    catalog = {}
    if os.path.exists(catalog_path):
        with open(catalog_path) as f:
            catalog = json.load(f)
    for name in names:
        export(name, catalog)
    # Drop entries for props that no longer exist.
    catalog = {k: catalog[k] for k in PROPS if k in catalog}
    with open(catalog_path, "w") as f:
        json.dump(catalog, f, indent=1, sort_keys=True)
        f.write("\n")


if __name__ == "__main__":
    main()
    sys.exit(0)
