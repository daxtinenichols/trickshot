#!/usr/bin/env python3
"""Lays out the Meridian car park for m07 Parking Spiral.

The car park is a helix: three laps of sloped decks around a walled core,
each lap 6.5 m lower than the last, from the top deck (19.5 m, where the
covered skybridge from the department store lands) down to the street.
It is a closed building: solid outer walls and core walls from the street
to above the top deck, so the run goes floor by floor (every deck is the
ceiling of the one below) and nobody drops straight to the bottom. It
can't be a route (route roofs are solid from the street up, and the laps
stand over each other), so this script writes it as ordinary pieces.

Rewrites every piece tagged "group": "car_park" in
campaign/missions/m07_parking_spiral.json, plus the mission's "bot_path"
(the main line, down the spiral) and "bot_path_alt" (the high line, down
the ledges outside the west wall). Everything else in the file is hand
written and left alone. Run it after changing the numbers here:

    python3 campaign/tools/build_car_park.py
"""

import json
import os

MISSION = os.path.join(os.path.dirname(__file__), "..", "missions", "m07_parking_spiral.json")
GROUP = "car_park"

# Footprint (outer walls) and lanes. Runs go down the west side (-Z), along
# the north side (+X), up the east side (+Z) and back along the south side
# (-X): every corner is a right turn.
X_OUT, Z_S, Z_N = 20.0, -470.0, -560.0
LANE = 9.0
X_IN = X_OUT - LANE            # 11: the core is x -11..11
Z_SI, Z_NI = Z_S - LANE, Z_N + LANE  # -479 and -551
CX = X_OUT - LANE / 2          # lane center x, 15.5
CZ_S, CZ_N = Z_S - LANE / 2, Z_N + LANE / 2  # -474.5, -555.5
TOP = 19.5
LAP = 6.5
# Drop along each side of a lap (long sides, short sides).
LONG_DROP, SHORT_DROP = 2.3, 0.95
LAPS = 3
SLAB = 0.5

# The skybridge: it leaves the mall's dock wall (MallBuilder.SKY_END, the
# end of the covered way out of the store) and climbs to the top deck.
BRIDGE_Y = 9.5
ROOF_EDGE = -430.0
BRIDGE_W = 4.0
BRIDGE_HEAD = 2.8
# The shell: outer and core walls stand this high, out of reach of the top
# deck (a 3 m face climbs).
SHELL_TOP = TOP + 4.5
WALL = 0.4
# The way out at the bottom: from the core north under the last lap's
# north side to the street.
EXIT_X = 5.0
EXIT_H = 3.0
# The street past the car park, and how far the mission runs down it.
ROAD_END = -660.0

out = []


def r(v):
    return round(v, 3)


def p(**kw):
    kw["group"] = GROUP
    for k, v in kw.items():
        if isinstance(v, list):
            kw[k] = [r(x) if isinstance(x, float) else x for x in v]
    out.append(kw)
    return kw


def box(at, size, look="NEUTRAL", kind="NEUTRAL", yaw=0):
    d = p(box=list(at), size=list(size), kind=kind, look=look)
    if yaw:
        d["yaw"] = yaw
    return d


def ramp(top, bottom, width, kind="NEUTRAL"):
    return p(ramp=list(top), to=list(bottom), width=width, kind=kind)


def corners(lap):
    """Heights of a lap's corners: SW (start), NW, NE, SE, next SW."""
    sw = TOP - LAP * lap
    nw = sw - LONG_DROP
    ne = nw - SHORT_DROP
    se = ne - LONG_DROP
    return sw, nw, ne, se, se - SHORT_DROP


def deck_y(lap, side, t):
    """Deck height on `side` ("W", "N", "E", "S") of `lap`, t 0..1 along it."""
    sw, nw, ne, se, sw2 = corners(lap)
    a, b = {"W": (sw, nw), "N": (nw, ne), "E": (ne, se), "S": (se, sw2)}[side]
    return a + (b - a) * t


def side_point(lap, side, t, offset=0.0):
    """A point on a side's lane, t along it (in running order), `offset` m
    from the lane center toward the outer wall (negative: toward the core)."""
    if side == "W":
        z = Z_SI + (Z_NI - Z_SI) * t
        return (-CX - offset, deck_y(lap, side, t), z)
    if side == "N":
        x = -X_IN + 2 * X_IN * t
        return (x, deck_y(lap, side, t), CZ_N - offset)
    if side == "E":
        z = Z_NI + (Z_SI - Z_NI) * t
        return (CX + offset, deck_y(lap, side, t), z)
    x = X_IN - 2 * X_IN * t
    return (x, deck_y(lap, side, t), CZ_S + offset)


def parapet(a, b, h=1.0, t=0.3):
    """A wall `h` m above the deck line from a to b (works on slopes: a ramp
    piece whose top edge is the wall's top)."""
    top = (a[0], a[1] + h, a[2])
    bot = (b[0], b[1] + h, b[2])
    if top[1] < bot[1]:
        top, bot = bot, top
    if abs(top[1] - bot[1]) < 0.01:
        mid = ((a[0] + b[0]) / 2, a[1] + h / 2, (a[2] + b[2]) / 2)
        size = [max(abs(a[0] - b[0]), t), h, max(abs(a[2] - b[2]), t)]
        return box(mid, size, look="NEUTRAL")
    return p(ramp=list(top), to=list(bot), width=t, kind="NEUTRAL")


# ------------------------------------------------------------- the decks

def corner_slab(x, y, z):
    if y <= 0.01:
        return
    box((x, y - SLAB / 2, z), (LANE, SLAB, LANE), look="TILE", kind="FLOOR")


def laps():
    for lap in range(LAPS):
        sw, nw, ne, se, sw2 = corners(lap)
        if lap > 0:
            corner_slab(-CX, sw, CZ_S)
        # West: down toward -Z.
        ramp((-CX, sw, Z_SI), (-CX, nw, Z_NI), LANE)
        corner_slab(-CX, nw, CZ_N)
        ramp((-X_IN, nw, CZ_N), (X_IN, ne, CZ_N), LANE)
        corner_slab(CX, ne, CZ_N)
        ramp((CX, ne, Z_NI), (CX, se, Z_SI), LANE)
        corner_slab(CX, se, CZ_S)
        ramp((X_IN, se, CZ_S), (-X_IN, sw2, CZ_S), LANE)
        # Outer walls (car park parapets) along each side and corner. The
        # top lap's west wall has a broken stretch where the high line
        # steps out onto the ledges.
        if lap == 0:
            a, b = (Z_SI - BREAK[0]) / (Z_SI - Z_NI), (Z_SI - BREAK[1]) / (Z_SI - Z_NI)
            parapet((-X_OUT + 0.15, sw, Z_SI), (-X_OUT + 0.15, deck_y(0, "W", a), BREAK[0]))
            parapet((-X_OUT + 0.15, deck_y(0, "W", b), BREAK[1]), (-X_OUT + 0.15, nw, Z_NI))
            p(mark=[-X_OUT + 1.0, deck_y(0, "W", a) + 0.02, BREAK[0] - 1.0], size=[1.6, 0.3], color="#b98a62")
        else:
            parapet((-X_OUT + 0.15, sw, Z_SI), (-X_OUT + 0.15, nw, Z_NI))
        parapet((-X_IN, nw, Z_N + 0.15), (X_IN, ne, Z_N + 0.15))
        parapet((X_OUT - 0.15, ne, Z_NI), (X_OUT - 0.15, se, Z_SI))
        parapet((X_IN, se, Z_S - 0.15), (-X_IN, sw2, Z_S - 0.15))
        for (x, y, z, ex, ez) in [(-CX, nw, CZ_N, -1, -1), (CX, ne, CZ_N, 1, -1), (CX, se, CZ_S, 1, 1)] + ([(-CX, sw, CZ_S, -1, 1)] if lap > 0 else []):
            if y <= 0.01:
                continue
            parapet((x + ex * (LANE / 2 - 0.15), y, z - LANE / 2), (x + ex * (LANE / 2 - 0.15), y, z + LANE / 2))
            parapet((x - LANE / 2, y, z + ez * (LANE / 2 - 0.15)), (x + LANE / 2, y, z + ez * (LANE / 2 - 0.15)))
        # Inner walls round the core. The last lap's south side opens into
        # the core (x -5..5), where Juno waits.
        parapet((-X_IN - 0.15, sw, Z_SI), (-X_IN - 0.15, nw, Z_NI))
        parapet((-X_IN, nw, Z_NI - 0.15), (X_IN, ne, Z_NI - 0.15))
        parapet((X_IN + 0.15, ne, Z_NI), (X_IN + 0.15, se, Z_SI))
        if lap == LAPS - 1:
            for (x0, x1) in [(X_IN, 5.0), (-5.0, -X_IN)]:
                t0, t1 = (X_IN - x0) / (2 * X_IN), (X_IN - x1) / (2 * X_IN)
                parapet((x0, deck_y(lap, "S", t0), Z_SI + 0.15), (x1, deck_y(lap, "S", t1), Z_SI + 0.15))
        else:
            parapet((X_IN, se, Z_SI + 0.15), (-X_IN, sw2, Z_SI + 0.15))
        # Level signs at the start of each lap.
        p(label="LEVEL %d" % (LAPS - lap), at=[-X_OUT + 0.6, sw + 2.6, CZ_S], size=1.2)


def top_deck():
    """The roof level where the skybridge lands: the south lane from the
    bridge west to the first corner."""
    x0, x1 = -X_OUT, 2.5
    box(((x0 + x1) / 2, TOP - SLAB / 2, CZ_S), (x1 - x0, SLAB, LANE), look="TILE", kind="FLOOR")
    # South wall, open where the skybridge comes in.
    parapet((-X_OUT, TOP, Z_S - 0.15), (-BRIDGE_W / 2, TOP, Z_S - 0.15))
    parapet((-X_OUT + 0.15, TOP, Z_S), (-X_OUT + 0.15, TOP, Z_SI))
    # Core side, and a tall shutter at the open east end so nobody skips
    # the first lap by dropping off it.
    parapet((-X_IN, TOP, Z_SI + 0.15), (x1, TOP, Z_SI + 0.15))
    box((x1 + 0.2, TOP + 1.75, CZ_S), (0.4, 3.5, LANE), look="RUST")
    p(prop="chalk_arrow", at=[-6.0, TOP, CZ_S], yaw=90)


def columns():
    """Columns from the street to the top, at the lanes' edges."""
    top = TOP + 1.0
    xs = [-X_OUT + 0.4, -X_IN - 0.4, X_IN + 0.4, X_OUT - 0.4]
    zs = [Z_S - 0.4, Z_SI - 0.4, Z_NI + 0.4, Z_N + 0.4]
    spots = set()
    for x in xs:
        for z in zs:
            spots.add((x, z))
        for k in range(1, 6):
            spots.add((x, Z_SI + (Z_NI - Z_SI) * k / 6))
    for z in zs:
        for x in [-5.6, 5.6]:
            spots.add((x, z))
    for (x, z) in sorted(spots):
        box((x, top / 2, z), (0.6, top, 0.6), look="NEUTRAL")


def cars():
    """Wrecks parked along the outer walls: cover for the fights, dressing
    for the rest."""
    k = 0
    for lap in range(LAPS):
        for side, sign in [("W", 1), ("E", -1)]:
            for t in [0.12, 0.3, 0.52, 0.7, 0.88]:
                k += 1
                if k % 3 == 0:
                    continue
                x, y, z = side_point(lap, side, t, 3.3)
                p(prop="car_wreck", at=[x, y, z], yaw=(5 if k % 2 else -4) + (0 if sign > 0 else 180))
        # A couple on the short sides, nose to the wall.
        for side, t in [("N", 0.25), ("S", 0.7)]:
            x, y, z = side_point(lap, side, t, 3.0)
            p(prop="car_wreck", at=[x, y, z], yaw=90 if side == "N" else -90)


def lights():
    for lap in range(LAPS):
        sw, nw, ne, se, _ = corners(lap)
        for (x, y, z) in [(-CX + 3.4, nw, CZ_N - 3.4), (CX - 3.4, se, CZ_S + 3.4)]:
            if y > 0.01:
                p(fire=[x, y + 0.2, z], size=[0.9, 1.0, 0.9])
                p(prop="barrel_rust", at=[x, y, z])


# ------------------------------------------------------------- bridge, street

def skybridge():
    """From the mall's dock wall up to the top deck: a covered walkway (walls
    and roof) that climbs 10 m. Slide up it with speed."""
    z0, z1 = ROOF_EDGE, Z_S
    ramp((0, TOP, z1), (0, BRIDGE_Y, z0), BRIDGE_W)
    hw = BRIDGE_W / 2 + 0.15
    # Walls: a sloped parapet is a 1 m band under its top edge, so stack
    # bands up to the roof.
    for s in (-1, 1):
        for h in (1.0, 2.0, BRIDGE_HEAD):
            parapet((s * hw, BRIDGE_Y, z0), (s * hw, TOP, z1), h=h)
    # Roof: a sloped sheet over the walls.
    p(ramp=[0, TOP + BRIDGE_HEAD + 0.3, z1], to=[0, BRIDGE_Y + BRIDGE_HEAD + 0.3, z0], width=BRIDGE_W + 0.9, kind="NEUTRAL", look="CORRUGATED")
    # Frame every 8 m, and legs down to the ground.
    n = 5
    for i in range(1, n + 1):
        t = i / (n + 1)
        z = z0 + (z1 - z0) * t
        y = BRIDGE_Y + (TOP - BRIDGE_Y) * t
        for s in (-1, 1):
            box((s * (hw + 0.2), y + BRIDGE_HEAD / 2, z), (0.25, BRIDGE_HEAD + 0.4, 0.25), look="RUST")
    for t in (0.3, 0.7):
        z = z0 + (z1 - z0) * t
        y = BRIDGE_Y + (TOP - BRIDGE_Y) * t
        for s in (-1, 1):
            box((s * (hw + 0.4), (y - 1.0) / 2, z), (0.6, y - 1.0, 0.6), look="NEUTRAL")


# ------------------------------------------------------------- the shell

def wall_z(x, z0, z1, holes=(), top=SHELL_TOP):
    """A wall along z at x from z0 to z1 (z0 > z1), street to `top`, with
    holes (za, zb, y_low, y_high), za > zb."""
    a = z0
    for (za, zb, lo, hi) in sorted(holes, reverse=True) + [(z1, z1, 0, 0)]:
        if a - za > 0.01:
            box((x, top / 2, (a + za) / 2), (WALL, top, a - za), look="NEUTRAL")
        if za - zb > 0.01:
            if lo > 0.01:
                box((x, lo / 2, (za + zb) / 2), (WALL, lo, za - zb), look="NEUTRAL")
            box((x, (hi + top) / 2, (za + zb) / 2), (WALL, top - hi, za - zb), look="NEUTRAL")
        a = zb


def wall_x(z, x0, x1, holes=(), top=SHELL_TOP):
    """A wall along x at z from x0 to x1 (x0 < x1), holes (xa, xb, lo, hi)."""
    a = x0
    for (xa, xb, lo, hi) in sorted(holes) + [(x1, x1, 0, 0)]:
        if xa - a > 0.01:
            box(((a + xa) / 2, top / 2, z), (xa - a, top, WALL), look="NEUTRAL")
        if xb - xa > 0.01:
            if lo > 0.01:
                box(((xa + xb) / 2, lo / 2, z), (xb - xa, lo, WALL), look="NEUTRAL")
            box(((xa + xb) / 2, (hi + top) / 2, z), (xb - xa, top - hi, WALL), look="NEUTRAL")
        a = xb


def shell():
    """Outer walls and the core's walls, street to SHELL_TOP. Holes: the
    skybridge door, the high line's break in the top lap and its way back
    in on the second lap, the core's door off the last lap, and the way
    out under the last lap's north side."""
    xo = X_OUT + WALL / 2
    a, b = (Z_SI - BREAK[0]) / (Z_SI - Z_NI), (Z_SI - BREAK[1]) / (Z_SI - Z_NI)
    lo = min(deck_y(0, "W", a), deck_y(0, "W", b))
    reentry = (REENTRY[0], REENTRY[1], deck_y(1, "W", (Z_SI - REENTRY[1]) / (Z_SI - Z_NI)) - 0.2, LEDGES[2][2] + 4.5)
    wall_z(-xo, Z_S + 0.2, Z_N - 0.2, [(BREAK[0], BREAK[1], lo - 0.2, lo + 4.0), reentry])
    wall_z(xo, Z_S + 0.2, Z_N - 0.2)
    wall_x(Z_S + WALL / 2, -xo, xo, [(-BRIDGE_W / 2 - 0.3, BRIDGE_W / 2 + 0.3, TOP - 0.3, TOP + BRIDGE_HEAD + 0.3)])
    wall_x(Z_N - WALL / 2, -xo, xo, [(-EXIT_X, EXIT_X, 0, EXIT_H)])
    xi = X_IN + WALL / 2
    wall_z(-xi, Z_SI, Z_NI)
    wall_z(xi, Z_SI, Z_NI)
    wall_x(Z_SI + WALL / 2, -xi, xi, [(-5.0, 5.0, 0, 4.0)])
    wall_x(Z_NI - WALL / 2, -xi, xi, [(-EXIT_X, EXIT_X, 0, EXIT_H)])
    # The way out is a tunnel under the north lane, and the space under the
    # last lap's west side is shut off where it meets the street.
    for sx in (-1, 1):
        box((sx * (EXIT_X + WALL / 2), EXIT_H / 2, (Z_NI + Z_N) / 2), (WALL, EXIT_H, Z_NI - Z_N), look="NEUTRAL")
    box((-(X_OUT + X_IN) / 2, TOP / 3 / 2, Z_SI), (LANE, TOP / 3, WALL), look="NEUTRAL")
    # The core is lit from its open top, and by the fire on Juno's floor.
    # Ruins either side of the way out, so the street only goes on west.
    for sx in (-1, 1):
        x0 = X_OUT + WALL
        p(building=[sx * (x0 + 46.0) / 2, 14.0, Z_N - 1.0], size=[46.0 - x0, 2.0])


def street():
    """Ground past the mall's road, ruins either side and at the end."""
    z0, z1 = -458.0, ROAD_END - 70.0
    # No ground under the high line's ledges: a slip there is a fall.
    hx0, hx1 = YARD_X
    hz0, hz1 = YARD_Z
    for (xa, xb, za, zb) in [(-70.0, hx0, z0, z1), (hx1, 70.0, z0, z1), (hx0, hx1, z0, hz0), (hx0, hx1, hz1, z1)]:
        box(((xa + xb) / 2, -0.5, (za + zb) / 2), (xb - xa, 1, za - zb), look="FLOOR", kind="FLOOR")
    for s in (-1, 1):
        for i, (za, zb) in enumerate([(z0, -520.0), (-520.0, -600.0), (-600.0, z1)]):
            h = [30.0, 24.0, 34.0][i]
            p(building=[s * 58.0, h, (za + zb) / 2], size=[24.0, za - zb])
    p(building=[0, 32.0, z1 - 10.0], size=[140.0, 20.0])
    # The service road heading west, with what's left on it.
    for z in range(-566, int(ROAD_END) - 10, -6):
        p(mark=[0, 0, z], size=[0.25, 3.0], color="#d1bd80")
    for (x, z, yaw) in [(-7, -585, 80), (8, -610, -100), (-9, -640, 95), (10, -662, 20)]:
        p(prop="car_wreck", at=[x, 0, z], yaw=yaw)
    p(row="barricade_jersey", **{"from": [-12, 0, -596], "to": [-4, 0, -596]}, count=4)
    p(row="barricade_jersey", **{"from": [4, 0, -628], "to": [12, 0, -628]}, count=4)
    for (x, z) in [(-14, -575), (15, -600), (-15, -630)]:
        p(prop="street_sign", at=[x, 0, z], yaw=90)
    p(prop="loudspeaker_pole", at=[-6, 0, -568], yaw=200)
    p(label="STORM CHANNELS", at=[0, 5.5, ROAD_END - 4.0], size=1.6)
    p(prop="chalk_arrow", at=[0, 0, -570])


# ------------------------------------------------------------- the high line

# Where the top lap's west wall is broken (z range), and the service ledges
# outside it (z0, z1, y), each lower: step out through the break and drop
# ledge to ledge, then over the wall into the end of the second lap's west
# side, skipping the whole top lap.
BREAK = (-492.6, -501.4)  # between two columns
LEDGES = [
    (-490.0, -516.0, 16.8),
    (-521.0, -537.0, 14.1),
    (-542.0, -559.5, 11.5),
]
LEDGE_W = 5.0
LEDGE_X = -X_OUT - 0.3 - LEDGE_W / 2
# Where the high line comes back in through the second lap's west wall.
REENTRY = (-541.0, -556.0)
# The yard under the ledges (x, z ranges): walled round, no floor.
YARD_X = (LEDGE_X - LEDGE_W / 2 - 0.2, -X_OUT - WALL)
YARD_Z = (-488.0, -561.0)


def high_line():
    for (z0, z1, y) in LEDGES:
        box((LEDGE_X, y - 0.25, (z0 + z1) / 2), (LEDGE_W, 0.5, z0 - z1), look="RUST")
        for z in (z0 - 2.0, z1 + 2.0):
            box((LEDGE_X - LEDGE_W / 2 + 0.4, (y - 0.5) / 2, z), (0.3, y - 0.5, 0.3), look="RUST")
        p(mark=[LEDGE_X, y, z0 - 1.0], size=[2.6, 0.3], color="#b98a62")
    # A screen of sheeting along the outside, ground to well over the top
    # ledge, and across both ends: the ledges are a way down, not out.
    top = LEDGES[0][2] + 4.5
    sx = YARD_X[0]
    box((sx, top / 2, (YARD_Z[0] + YARD_Z[1]) / 2), (0.3, top, YARD_Z[0] - YARD_Z[1]), look="CORRUGATED")
    for z in YARD_Z:
        box(((YARD_X[0] + YARD_X[1]) / 2, top / 2, z), (YARD_X[1] - YARD_X[0], top, 0.3), look="CORRUGATED")
    # Back in over the second lap's west wall, at the end of its west side.
    p(tape=[LEDGE_X, LEDGES[1][2], -515.0], id="m07_tape_ledges")


# ------------------------------------------------------------- enemies

def sandbag(x, y, z, yaw=0):
    p(prop="sandbag_wall", at=[x, y, z], yaw=yaw)
    return {"at": [r(x), r(y), r(z)], "length": 2.0, "yaw": yaw}


def at(pt, **kw):
    d = {"at": [r(pt[0]), r(pt[1]), r(pt[2])]}
    d.update(kw)
    return d


def enemies():
    # The first two laps: hunters and gunners on the decks.
    for lap, name in [(0, "upper decks"), (1, "lower decks")]:
        sw, nw, ne, se, sw2 = corners(lap)
        cover, raiders, others = [], [], []
        # A gunner across the north side, one up the east side, one on the
        # south side: they shoot along the lane at you coming round.
        g1 = side_point(lap, "N", 0.55, -3.2)
        cover.append(sandbag(g1[0] - 2.0, g1[1], g1[2], 90))
        raiders.append(at(g1, yaw=90))
        g2 = side_point(lap, "E", 0.4, -3.0)
        cover.append(sandbag(g2[0], g2[1], g2[2] - 2.0, 0))
        raiders.append(at(g2, yaw=0, wake=1.0))
        g3 = side_point(lap, "S", 0.6, -3.2)
        cover.append(sandbag(g3[0] + 2.0, g3[1], g3[2], 90))
        raiders.append(at(g3, yaw=-90, wake=1.5))
        # Hunters come at you from the side.
        for side, t, off, wake in [("W", 0.6, -3.4, 0.0), ("N", 0.75, 2.6, 1.0), ("E", 0.3, -3.3, 2.0)]:
            others.append(dict(at(side_point(lap, side, t, off), yaw=180), type="hunter", wake=wake))
        y0 = sw2 - 0.5
        p(encounter=name, area={"at": [0, (y0 + sw + 3) / 2, (Z_S + Z_N) / 2], "size": [2 * X_OUT, sw + 3 - y0, Z_S - Z_N]},
          raiders=raiders, enemies=others, cover=cover)
    # Juno in the core, with two of hers.
    cover = [sandbag(-4, 0, -508, 0), sandbag(5, 0, -524, 0), sandbag(-3, 0, -538, 0)]
    for (x, z, yaw) in [(-8, -500, 10), (8, -515, -170), (-7, -545, 100)]:
        p(prop="car_wreck", at=[x, 0, z], yaw=yaw)
    p(fire=[0, 0.2, -532], size=[1.2, 1.4, 1.2])
    p(prop="barrel_rust", at=[0, 0, -532])
    p(prop="loudspeaker_pole", at=[9.5, 0, -490], yaw=-30)
    p(loop=[-6.5, 0, -520], radius=4.5, width=3.5, shift=5.5)
    p(encounter="Juno", area={"at": [0, 2.5, (Z_SI + Z_NI) / 2], "size": [2 * X_IN, 5, Z_SI - Z_NI]},
      raiders=[], enemies=[
          {"type": "juno", "at": [-2.5, 0, -544], "yaw": 180},
          {"type": "hunter", "at": [6, 0, -530], "yaw": 180, "wake": 0.5},
          {"type": "hunter", "at": [8, 0, -542], "yaw": 180, "wake": 1.0},
      ], cover=cover)
    # A Static roadblock on the way out.
    cover = [sandbag(-3, 0, -612, 0), sandbag(4, 0, -614, 0)]
    p(prop="barricade_scrap", at=[-8.5, 0, -613], yaw=0)
    p(prop="barricade_scrap", at=[9.5, 0, -614], yaw=0)
    p(encounter="roadblock", area={"at": [0, 3, -605], "size": [30, 8, 40]},
      raiders=[{"at": [-3, 0, -614.5], "yaw": 180}, {"at": [4, 0, -616.5], "yaw": 180, "wake": 0.8}], cover=cover)


# ------------------------------------------------------------- bot paths

def bot_paths():
    """Waypoints [x, z, action] for the test bots."""
    main = [[15, -390], [15, -402], [13, -406], [2, -406], [0, -410], [0, -466], [-1, -474.5],
            [-13.5, -474.5], [-15.5, -478]]
    for lap in range(LAPS):
        last = lap == LAPS - 1
        main += [[-15.5, Z_NI + 1], [-13.5, CZ_N], [13.5, CZ_N], [CX, Z_NI + 1], [CX, Z_SI - 1], [13.5, CZ_S]]
        if not last:
            main += [[-13.5, CZ_S], [-CX, Z_SI - 1]]
    main += [[5, CZ_S], [2.5, Z_SI + 1.5], [1.5, Z_SI - 3], [2.5, -536], [1.5, -566], [0, ROAD_END + 5]]
    alt = main[:main.index([-15.5, -478]) + 1] + [[-17.0, -490.0], [LEDGE_X, -499.0], [LEDGE_X, -511.0], [LEDGE_X, -515.0, "jump"],
                      [LEDGE_X, -526.0], [LEDGE_X, -532.0], [LEDGE_X, -536.0, "jump"],
                      [LEDGE_X, -543.0], [-20.3, -547.0, "jump"], [-16.0, -551.0],
                      [-13.5, CZ_N]]
    # Then the second lap from its north side on, like the main line.
    i = main.index([-13.5, CZ_N], main.index([-13.5, CZ_N]) + 1)
    alt += main[i + 1:]
    return main, alt


def main():
    top_deck()
    laps()
    columns()
    cars()
    lights()
    skybridge()
    shell()
    street()
    high_line()
    enemies()
    with open(MISSION) as f:
        mission = json.load(f)
    pieces = [q for q in mission.get("pieces", []) if q.get("group") != GROUP]
    mission["pieces"] = pieces + out
    mission["bot_path"], mission["bot_path_alt"] = bot_paths()
    with open(MISSION, "w") as f:
        f.write(dump(mission))
        f.write("\n")
    print("%d car park pieces" % len(out))


def dump(m):
    """The mission file with one piece (and waypoint) per line."""
    lines = ["{"]
    keys = list(m.keys())
    for i, k in enumerate(keys):
        comma = "," if i < len(keys) - 1 else ""
        v = m[k]
        if isinstance(v, list) and v and isinstance(v[0], (dict, list)):
            lines.append(" %s: [" % json.dumps(k))
            for j, item in enumerate(v):
                lines.append("  %s%s" % (json.dumps(item), "," if j < len(v) - 1 else ""))
            lines.append(" ]%s" % comma)
        elif isinstance(v, dict) and k == "chatter":
            lines.append(" %s: {" % json.dumps(k))
            ck = list(v.keys())
            for j, c in enumerate(ck):
                lines.append("  %s: [" % json.dumps(c))
                for n, item in enumerate(v[c]):
                    lines.append("   %s%s" % (json.dumps(item), "," if n < len(v[c]) - 1 else ""))
                lines.append("  ]%s" % ("," if j < len(ck) - 1 else ""))
            lines.append(" }%s" % comma)
        else:
            lines.append(" %s: %s%s" % (json.dumps(k), json.dumps(v), comma))
    lines.append("}")
    return "\n".join(lines)


if __name__ == "__main__":
    main()
