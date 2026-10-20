#!/usr/bin/env python3
"""Writes campaign/atlas.json: the whole city of Dead Air in one set of
world coordinates. Edit this script, not the JSON, then run

    python3 campaign/tools/make_atlas.py

Axes: meters, +X east, -Z north, Y up (Godot's). The broadcast tower stands
at the origin. Chapter 1 runs east to west along z ~ 0, from the Docks on
the harbour (x ~ 3400) to the tower; Chapter 2 heads north from the tower.

What it holds:
  districts   id, name, chapter, stage number, rect [x0, z0, x1, z1]
  streets     named avenues [x0, z0, x1, z1, width]; a few are diagonal
  water       the harbour and the reservoir: {id, y, poly [[x, z], ...]}
  open        ground no building stands on: {id, rect [x0, z0, x1, z1]}
  silt        the dry riverbed: a polyline and its width. From the dam in
              the north it runs south under the tower's west side (the
              Host's fall in Signal Out), loops south and east under
              Westside and Meridian, crosses the Chapter 1 line at the Silt
              stage, and runs out into the harbour north of the Docks
  tower       the broadcast tower (every level shows it on the skyline)
  landmarks   named structures, as boxes [x, z, sx, sz, y0, y1]; the Docks'
              are exact, so levels built through them (route "atlas_pieces":
              landmarks with "piece") and the skyline of their neighbours
              agree. "visual" ones (cranes over the water) show even close
              to a course, where nothing else of the skyline does
  blocks      every other building, rough: [x, z, sx, sz, h] boxes on each
              district's street grid. Later district threads refine them.

Same script, same city (seeded). Levels are routes through this map (their
"route_origin" is in these coordinates); campaign/atlas.gd builds the
skyline round a level from it.
"""

import json
import math
import os
import random

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "campaign", "atlas.json")

WATER_Y = -0.6
QUAY_X = 3440.0

TOWER = {"at": [0, 0], "size": [44, 44], "height": 232, "mast": 46}

# id, name, chapter, stage, rect, (block pitch, street width), height range, shade
DISTRICTS = [
    ("docks", "The Docks", 1, 1, [2950, -560, 3440, 420], (52, 12), (7, 15), 0),
    ("warehouse_glass", "Warehouse Row and the Glass District", 1, 2, [1900, -520, 2950, 420], (60, 12), (9, 22), 1),
    ("silt", "The Silt", 1, 3, [1560, -520, 1900, 420], (56, 12), (6, 16), 2),
    ("meridian", "Meridian", 1, 4, [1000, -520, 1560, 420], (72, 14), (14, 34), 1),
    ("westside", "Westside", 1, 5, [450, -520, 1000, 420], (50, 10), (8, 22), 2),
    ("calder", "Calder House and the Tower", 1, 6, [-60, -520, 450, 420], (56, 12), (26, 80), 3),
    ("signal_out", "Signal Out", 1, 7, [-420, -420, -60, 360], (48, 10), (10, 30), 2),
    ("kettle_row", "Kettle Row", 2, 8, [20, -1200, 900, -520], (44, 10), (10, 26), 0),
    ("the_mains", "The Mains", 2, 9, [20, -1900, 900, -1200], (56, 12), (6, 18), 2),
    ("the_terraces", "The Terraces", 2, 10, [20, -2550, 900, -1900], (48, 10), (16, 44), 3),
    ("reservoir", "Reservoir and the dam", 2, 11, [-700, -3300, 900, -2550], (90, 20), (6, 14), 2),
]
# Districts' sub-areas with their own heights (x0, x1 of the Glass District
# inside "warehouse_glass": towers).
GLASS = (1900, 2300, (30, 110))
# Ground outside every district, to the map's edge: low outskirts.
MAP = [-1300, -3600, 4400, 1500]
OUTSKIRTS = ((80, 16), (6, 16), 2)

# Avenues: [x0, z0, x1, z1, width]. Mostly on the grid; three diagonals.
STREETS = [
    ("Harbour Road", [2950, 300, 2950, -560, 16]),
    ("Calder Way", [-60, 40, 3440, 40, 18]),
    ("Meridian Avenue", [1560, 380, 1000, -330, 20]),
    ("Kettle Diagonal", [900, -540, 300, -1150, 16]),
    ("Westside Cut", [1000, -300, 450, 300, 16]),
    ("North Road", [460, -520, 460, -2550, 18]),
]

# The Silt riverbed: dam -> tower west side -> south loop -> the crossing at
# the Silt stage -> the harbour.
SILT_PATH = [
    [-150, -2600], [-140, -1800], [-110, -900], [-62, -260], [-50, 0], [-60, 260],
    [-20, 560], [300, 760], [900, 820], [1400, 760], [1700, 420], [1760, 0],
    [1800, -480], [2100, -980], [2700, -1300], [3200, -1380], [QUAY_X + 40, -1400],
]
SILT_WIDTH = 64
SILT_FLOOR = -6.0

HARBOUR = [[QUAY_X, -1700], [4600, -1700], [4600, 1500], [QUAY_X, 1500]]
# The reservoir behind the dam (Chapter 2's last stage): held up high.
RESERVOIR = [[-560, -3300], [260, -3300], [260, -2654], [-560, -2654]]
# Open ground the city leaves bare round a level: the quay apron between the
# dock sheds and the water (the raiders' pickup drives up it).
OPEN = [{"id": "quay_apron", "rect": [3432.5, -700, 3440, 420]}]
WATERS = [{"id": "harbour", "y": WATER_Y, "poly": HARBOUR}, {"id": "reservoir", "y": 30.0, "poly": RESERVOIR}]


def docks_landmarks():
    """The Docks, exact (the levels run through these)."""
    out = []
    # The Line's camp: a big dock warehouse on the quay, roof 12 m.
    out.append({"id": "line_camp", "name": "The Line camp", "boxes": [[3401, 121, 62, 58, 0, 12]], "piece": True,
                "look": "BRICK"})
    # The fish market hall, the net lofts, the container yard and its
    # gantry cranes are the levels' own (route roofs and pieces).
    # Ship-to-shore cranes on the north quay, booms out over the water.
    sts = []
    for z in (-330, -400, -470):
        sts += [[3436, z - 7, 2.2, 2.2, 0, 44], [3436, z + 7, 2.2, 2.2, 0, 44],
                [3452, z - 7, 2.2, 2.2, 0, 44], [3452, z + 7, 2.2, 2.2, 0, 44],
                [3470, z, 84, 4, 44, 48], [3444, z, 10, 10, 44, 54]]
    # On the quay apron and over the water: seen from the levels, never in
    # the way, so they stand even close to a course ("visual").
    out.append({"id": "quay_cranes", "name": "Ship-to-shore cranes", "boxes": sts, "shade": 4, "visual": True})
    # The south gate out of the yard, onto the road to Warehouse Row.
    out.append({"id": "south_gate", "name": "South gate", "boxes": [[2988, 308, 1.2, 1.2, 0, 6], [2988, 328, 1.2, 1.2, 0, 6]]})
    return out


def other_landmarks():
    return [
        # Calder House: the old radio company's block east of the tower, its
        # wings the Stage 6 levels run through (6-1 Head Office, 6-2
        # Skybridge; boxes round their floors, from campaign-tools/stage6).
        {"id": "calder_house", "name": "Calder House", "boxes": [
            [394, -200, 126, 26, 0, 15], [344, -272, 26, 122, 0, 12], [276, -320, 114, 26, 0, 12],
            [224, -178, 38, 262, 0, 18], [194, -58, 58, 16, 0, 22.5], [173, 17, 26, 138, 0, 27],
            [233, 73, 98, 14, 0, 27], [351, 73, 154, 26, 0, 36], [415, 125, 26, 82, 0, 36],
            [295, 146, 218, 36, 0, 45], [197, 205, 22, 86, 0, 45], [88.5, 237, 199, 22, 0, 48],
            [0, 196, 14, 64, 0, 45]], "shade": 3},
        {"id": "meridian_mall", "name": "Meridian Mall", "boxes": [[1290, 120, 190, 150, 0, 26], [1290, -60, 120, 70, 0, 34]], "shade": 1},
        # Westside (Stage 5, exact): the rail line's viaduct, north from the
        # sidings to West Central and west to the end of the line, plus its
        # branch east to Meridian. 5-2 The Rail Line runs on it and ends at
        # "westside_exit", where Stage 6 starts ("point", "yaw").
        {"id": "rail_line", "name": "Westside rail line", "boxes": [[555, 76, 14, 576, 8, 10], [502, -200, 104, 14, 8, 10],
                                                                    [790, -200, 420, 10, 8, 10]], "shade": 4},
        {"id": "westside_exit", "name": "End of the Westside line", "boxes": [[452, -200, 4, 12, 0, 9]], "shade": 4,
         "point": [450, 10, -200], "yaw": 90},
        {"id": "dam", "name": "The dam", "boxes": [[-150, -2640, 420, 26, 0, 48]], "shade": 2},
        {"id": "terrace_wall", "name": "The Ward's wall", "boxes": [[460, -1900, 900, 6, 0, 18], [20, -2225, 6, 650, 0, 18], [900, -2225, 6, 650, 0, 18]], "shade": 3},
    ]


# ------------------------------------------------------------------ geometry

def seg_dist(p, a, b):
    ax, az = a
    bx, bz = b
    dx, dz = bx - ax, bz - az
    l2 = dx * dx + dz * dz
    t = 0.0 if l2 == 0 else max(0.0, min(1.0, ((p[0] - ax) * dx + (p[1] - az) * dz) / l2))
    cx, cz = ax + dx * t, az + dz * t
    return math.hypot(p[0] - cx, p[1] - cz)


def in_poly(p, poly):
    x, z = p
    inside = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, zi = poly[i]
        xj, zj = poly[j]
        if (zi > z) != (zj > z) and x < (xj - xi) * (z - zi) / (zj - zi) + xi:
            inside = not inside
        j = i
    return inside


def corners(x, z, sx, sz):
    return [(x - sx / 2, z - sz / 2), (x + sx / 2, z - sz / 2), (x + sx / 2, z + sz / 2), (x - sx / 2, z + sz / 2), (x, z)]


def blocked(x, z, sx, sz, rects):
    """True if the box touches the river, the water, an avenue or a landmark."""
    for c in corners(x, z, sx, sz):
        if any(in_poly(c, w["poly"]) for w in WATERS):
            return True
        for i in range(len(SILT_PATH) - 1):
            if seg_dist(c, SILT_PATH[i], SILT_PATH[i + 1]) < SILT_WIDTH / 2 + 6:
                return True
        for _, s in STREETS:
            if seg_dist(c, (s[0], s[1]), (s[2], s[3])) < s[4] / 2 + 3:
                return True
    for r in rects:
        if x - sx / 2 < r[2] and x + sx / 2 > r[0] and z - sz / 2 < r[3] and z + sz / 2 > r[1]:
            return True
    return False


def district_at(x, z):
    for d in DISTRICTS:
        r = d[4]
        if r[0] <= x < r[2] and r[1] <= z < r[3]:
            return d
    return None


def grid_blocks(rng, rect, pitch, street, heights, keep_out, shade, owner=None):
    out = []
    x0, z0, x1, z1 = rect
    x = x0
    while x < x1 - 1:
        z = z0
        while z < z1 - 1:
            bx = min(pitch, x1 - x) - street
            bz = min(pitch, z1 - z) - street
            if bx > 8 and bz > 8:
                # A block is one to three buildings of different heights.
                parts = rng.choice([1, 1, 2, 2, 3])
                along_x = bx >= bz
                n = parts
                for k in range(n):
                    if along_x:
                        w = bx / n
                        cx, cz, sx, sz = x + street / 2 + w * (k + 0.5), z + street / 2 + bz / 2, w - 0.6, bz
                    else:
                        w = bz / n
                        cx, cz, sx, sz = x + street / 2 + bx / 2, z + street / 2 + w * (k + 0.5), bx, w - 0.6
                    d = district_at(cx, cz)
                    if owner is not None and (d is None or d[0] != owner):
                        continue
                    if owner is None and d is not None:
                        continue
                    lo, hi = heights
                    if d is not None and d[0] == "warehouse_glass" and GLASS[0] <= cx < GLASS[1]:
                        lo, hi = GLASS[2]
                    h = rng.uniform(lo, hi)
                    if rng.random() < 0.06:
                        h *= 1.6
                    if not blocked(cx, cz, sx, sz, keep_out):
                        out.append([round(cx, 1), round(cz, 1), round(sx, 1), round(sz, 1), round(h, 1), shade])
            z += pitch
        x += pitch
    return out


def frontage(rng, street, heights, shade, keep_out):
    """Buildings square to a diagonal avenue on both sides (straight
    frontage), as turned boxes [x, z, sx, sz, h, shade, yaw_deg]."""
    x0, z0, x1, z1, w = street
    dx, dz = x1 - x0, z1 - z0
    length = math.hypot(dx, dz)
    ux, uz = dx / length, dz / length
    nx, nz = -uz, ux
    yaw = math.degrees(math.atan2(ux, uz))
    out = []
    for side in (-1, 1):
        s = 10.0
        while s < length - 10:
            l = rng.uniform(18, 34)
            depth = rng.uniform(18, 26)
            off = side * (w / 2 + 3 + depth / 2)
            cx = x0 + ux * (s + l / 2) + nx * off
            cz = z0 + uz * (s + l / 2) + nz * off
            ok = True
            for c in [(cx + ux * l / 2 + nx * depth / 2, cz + uz * l / 2 + nz * depth / 2),
                      (cx - ux * l / 2 - nx * depth / 2, cz - uz * l / 2 - nz * depth / 2), (cx, cz)]:
                if in_poly(c, HARBOUR) or any(seg_dist(c, SILT_PATH[i], SILT_PATH[i + 1]) < SILT_WIDTH / 2 + 6 for i in range(len(SILT_PATH) - 1)):
                    ok = False
            if ok:
                d = district_at(cx, cz)
                lo, hi = d[6] if d else heights
                out.append([round(cx, 1), round(cz, 1), round(l - 1.0, 1), round(depth, 1), round(rng.uniform(lo, hi), 1), d[7] if d else shade, round(yaw, 2)])
            s += l
    return out


def near_diagonal(x, z, sx, sz):
    for _, s in STREETS:
        if s[0] != s[2] and s[1] != s[3]:
            for c in corners(x, z, sx, sz):
                if seg_dist(c, (s[0], s[1]), (s[2], s[3])) < s[4] / 2 + 32:
                    return True
    return False


def main():
    rng = random.Random(20261018)
    landmarks = docks_landmarks() + other_landmarks()
    keep_out = []
    for lm in landmarks:
        for b in lm["boxes"]:
            keep_out.append([b[0] - b[2] / 2 - 4, b[1] - b[3] / 2 - 4, b[0] + b[2] / 2 + 4, b[1] + b[3] / 2 + 4])
    t = TOWER
    keep_out.append([t["at"][0] - 40, t["at"][1] - 40, t["at"][0] + 40, t["at"][1] + 40])
    blocks = []
    for d in DISTRICTS:
        pitch, street = d[5]
        blocks += grid_blocks(rng, d[4], pitch, street, d[6], keep_out, d[7], owner=d[0])
    pitch, street = OUTSKIRTS[0]
    blocks += grid_blocks(rng, MAP, pitch, street, OUTSKIRTS[1], keep_out, OUTSKIRTS[2])
    # Diagonal avenues get straight frontage; grid blocks close to them go.
    blocks = [b for b in blocks if not near_diagonal(b[0], b[1], b[2], b[3])]
    for _, s in STREETS:
        if s[0] != s[2] and s[1] != s[3]:
            blocks += frontage(rng, s, OUTSKIRTS[1], OUTSKIRTS[2], keep_out)
    atlas = {
        "_note": "Generated by campaign/tools/make_atlas.py. Edit the script, not this file.",
        "axes": "meters; +x east, -z north, y up; the broadcast tower at the origin",
        "map": MAP,
        "tower": TOWER,
        "districts": [{"id": d[0], "name": d[1], "chapter": d[2], "stage": d[3], "rect": d[4]} for d in DISTRICTS],
        "streets": [{"name": n, "line": s} for n, s in STREETS],
        "water": WATERS,
        "open": OPEN,
        "silt": {"path": SILT_PATH, "width": SILT_WIDTH, "floor": SILT_FLOOR},
        "landmarks": landmarks,
        "blocks": blocks,
    }
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(atlas, f, separators=(",", ":"))
        f.write("\n")
    print("wrote %s: %d blocks, %d landmarks" % (os.path.relpath(OUT, ROOT), len(blocks), len(landmarks)))


if __name__ == "__main__":
    main()
