#!/usr/bin/env python3
"""Writes Stage 3, the Silt: l3_1_the_silt.json and l3_2_the_drain.json.

Two atlas levels (campaign/atlas.gd) between the Glass District and the
Meridian mall. Story beats and radio lines come from the Round 2 Stage 3
section of the story brief (mission-briefs.md); chatter is the old Silt
Line's (already voiced).

3-1 The Silt: from the blown Calder Way bridge (2-3 ends on its deck at
  (1790, 8, 40) facing west) down the snapped deck into the dry bed, north
  up the Silt between its flood walls (sunk buses, Echo's relay box, the
  Static's Hollows pens), then west up a concrete outfall channel to the
  storm-drain mouth.
3-2 The Drain: west into the drain, south down the big round storm-drain
  main (its curved walls to run, the ring pipe to loop, a pumping chamber)
  and up through a rusted grate onto the mall's south lot, where 4-1
  starts: (1500, 0, 380) facing west.

Run it after changing the numbers here, then check the ends meet:

    python3 campaign/tools/build_silt.py
    godot --headless --path . -s res://campaign/tools/route_info.gd -- res://campaign/missions/l3_2_the_drain.json
"""

import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
MISSIONS = os.path.join(HERE, "..", "missions")

START = [1790, 8, 40]          # 2-3's end, on the Silt bridge deck
MALL = [1500, 0, 380]          # 4-1's start (the mall's south entrance)
BANK_H = 7.0                   # the Silt's flood walls
DUST = "#a08a68"
SPEED_GATE = {"lower": "ledge"}


# ------------------------------------------------------------------ helpers

def piece(p, at, length=0):
    return {"piece": p, "at": at, "length": length}


def walls(length, left=-6.0, right=6.0, h=BANK_H, look=None, at=0.0):
    """Flood walls down both sides of a roof (inner faces at left/right)."""
    out = []
    for x, s in ((left, -1), (right, 1)):
        b = {"box": [x + s * 1.5, h * 0.5, -length * 0.5], "size": [3.0, h, length], "kind": "NEUTRAL"}
        if look:
            b["look"] = look
        out.append(piece(b, at))
    return out


def dust(length, at=0.0, width=12.0):
    return [piece({"mark": [0, 0.004, -length * 0.5], "size": [width, length], "color": DUST}, at)]


def bus_jam(length, at=0.0):
    """A roof of sunk buses side by side: dark gaps between them, window
    bands down the outer sides."""
    out = []
    for x in (-3.0, 0.0, 3.0):
        out.append(piece({"mark": [x, 0.006, -length * 0.5], "size": [0.25, length], "color": "#2b2622"}, at))
    for x in (-6.05, 6.05):
        out.append(piece({"box": [x, -1.0, -length * 0.5], "size": [0.1, 0.9, length - 1.0], "kind": "NEUTRAL", "look": "TILE"}, at))
    return out


def pipe_banks(length, at=0.0):
    """The drain main's curved walls: a bank up each side, from 2.2 m off
    the middle to the wall (run them)."""
    out = []
    for side in (-1.0, 1.0):
        out.append(piece({"bank": [side * 2.2, 0, 0], "length": length, "side": side, "radius": 4.0, "angle": 72, "straight": 0.4}, at, length))
    return out


def ring_pipe(at, x=-5.5):
    """The ring pipe: a running loop round a broken pipe joint (the
    Chapter's one loop), off the main lane, with the pipe's shell round it."""
    return [piece({"loop": [x, 0, 0], "radius": 4.5, "width": 3.5, "shift": 3.0}, at, 10),
            {"set_piece": "ring_pipe", "at": at, "x": x + 1.5, "trigger": at, "radius": 1.0, "radius_m": 5.3}]


def headwall(at, h=6.0, w=12.0, top=13.0):
    """A storm-drain mouth: a concrete headwall across the end of the
    channel with the culvert's dark opening in it."""
    return [
        piece({"box": [0, h + (top - h) * 0.5, -0.6], "size": [w + 8, top - h, 1.2], "kind": "NEUTRAL"}, at),
        piece({"box": [-(w * 0.5 + 2), top * 0.5, -0.6], "size": [4, top, 1.2], "kind": "NEUTRAL"}, at),
        piece({"box": [w * 0.5 + 2, top * 0.5, -0.6], "size": [4, top, 1.2], "kind": "NEUTRAL"}, at),
        piece({"box": [0, h * 0.5, -9.0], "size": [w, h, 0.4], "kind": "NEUTRAL", "look": "RUST"}, at),
        piece({"box": [-(w * 0.5 + 0.25), h * 0.5, -4.8], "size": [0.5, h, 8.4], "kind": "NEUTRAL"}, at),
        piece({"box": [w * 0.5 + 0.25, h * 0.5, -4.8], "size": [0.5, h, 8.4], "kind": "NEUTRAL"}, at),
        piece({"box": [0, h + 0.25, -4.8], "size": [w + 1, 0.5, 8.4], "kind": "NEUTRAL"}, at),
    ]


def catwalk(d, y=3.8, look="RUST"):
    """A service catwalk (or a pipe bridge) across the way, `d` m along the
    roof, high enough to run under."""
    return [piece({"box": [0, y, -d], "size": [12, 0.3, 1.6], "kind": "NEUTRAL", "look": look}, 0.0),
            piece({"box": [0, y + 0.55, -d - 0.75], "size": [12, 0.08, 0.08], "kind": "NEUTRAL", "look": look}, 0.0)]


def crew(d, enc_at, y=3.8, xs=(-4.5, -1.5, 1.5, 4.5)):
    """Static herders up on a catwalk (catwalk(d)), facing down the pipe:
    an encounter starting `enc_at` m along the same roof."""
    return [enemy("raider", x, d - enc_at, 0.2 * i, elevation=y + 0.15, cover=False, aim_lead=LEAD, move_speed=0.0)
            for i, x in enumerate(xs)]


def shaft(d, y0, top, ceiling=None, length=8.0, look="RUST"):
    """Walls and a roof over the ramp up out of a roof `d` m long (ramps
    don't get an interior of their own), from its floor y0 up to `top`,
    and a header up from the roof's own `ceiling` to meet it."""
    out = [piece(box(x, (y0 + top) * 0.5, -d - length * 0.5, 0.1, top - y0, length, look=look), 0) for x in (-5.94, 5.94)]
    out.append(piece(box(0, top + 0.15, -d - length * 0.5, 12.0, 0.3, length, look=look), 0))
    if ceiling is not None:
        out.append(piece(box(0, (y0 + ceiling + top) * 0.5, -d, 12.0, top - y0 - ceiling, 0.3, look=look), 0))
    return out


def pumps(length, at=0.0):
    """The pumping station's machines along both walls (out of the lane)."""
    out = []
    d = 4.0
    while d < length - 4.0:
        for side in (-1, 1):
            out.append(piece({"box": [side * 4.9, 1.4, -d], "size": [1.8, 2.8, 3.2], "kind": "NEUTRAL", "look": "RUST"}, at))
            out.append(piece({"box": [side * 5.4, 5.5, -d], "size": [0.7, 0.7, 6.0], "kind": "NEUTRAL", "look": "RUST"}, at))
        d += 10.0
    return out


def trick_run(y, look=None, interior=None, roof=10):
    """Weirs (or pump plinths) to jump with a flip, a 360 and a front flip:
    three different tricks keep the combo and its Flow up for a tier-2
    gate's run-up."""
    out = []
    for trick in ("flip", "spin", "front"):
        out.append({"gap": 3, "trick": trick})
        r = {"roof": roof, "y": y, "bare": True}
        if look:
            r["look"] = look
        if interior:
            r["interior"] = interior
        out.append(r)
    return out


def enemy(t, x, d, wake=0.0, **kw):
    e = {"type": t, "x": x, "d": d, "wake": wake}
    e.update(kw)
    return e


def course(first, last, step=16.0, hurdle=True, k=0):
    """Hurdles through a fight, `step` m apart, each one flipped or spun
    over: the combo (and its Flow) never lapses, so the trick line stays
    fast enough to outrun the Hollows and too wild to hit."""
    tricks = ("flip", "spin", "front")
    out = []
    d, i = first, 0
    while d <= last + 0.01:
        out.append({"hurdles": hurdle, "at": round(d, 1), "trick": tricks[(k + i) % 3]})
        d += step
        i += 1
    return out


AIMING = 5
# Herders lead a runner who holds a straight line.
LEAD = 1.0


def herders(first, last, n, x=5.0, **kw):
    """Static herders with rifles behind sandbags at the sides, from `first`
    to `last` m into an encounter: a plain line runs into their fire, a
    trick line is too fast and wild to hit (combo armor). They lead a
    straight runner (LEAD), so holding a line doesn't dodge, and hold
    their posts (never wander into the lane)."""
    out = []
    for i in range(n):
        d = first + (last - first) * i / max(n - 1, 1)
        out.append(enemy("raider", x if i % 2 == 0 else -x, round(d, 1), 0.2 * i, aim_lead=LEAD, move_speed=0.0, **kw))
    return out


CHATTER_SILT = {
    "bail": [
        {"who": "host", "line": "Splat! Don't swallow any of that, Parker."},
        {"who": "mags", "line": "Up! Up, they're coming."},
        {"who": "host", "line": "Oh, he's in it now. Literally."},
        {"who": "mags", "line": "Don't lie there. Move."},
        {"who": "host", "line": "Face first in the Silt! That'll stain."},
    ],
    "combo": [
        {"who": "mags", "line": "Good. Faster than them, that's all you need."},
        {"who": "host", "line": "Oh, he's making them look slow. They're not slow!"},
        {"who": "mags", "line": "That's it. Keep your feet out of the muck."},
        {"who": "host", "line": "Folks, he's dancing with the Hollows. Don't try this at home. You don't have a home."},
        {"who": "mags", "line": "That's how you outrun them. Don't stop."},
        {"who": "host", "line": "Look at him dance down there! Come on, crawlers, keep up."},
    ],
    "kill": [
        {"who": "mags", "line": "Okay, but don't stop for them."},
        {"who": "host", "line": "Ooh, he's swatting crawlers! Plenty more where that came from."},
        {"who": "mags", "line": "Leave the rest. Go."},
        {"who": "host", "line": "One down! Out of... yeah, I don't know. Lots."},
        {"who": "mags", "line": "Don't fight them all. Run."},
    ],
    "down": [
        {"who": "host", "line": "Dinner's... oh, he's up again. Well, they'll keep."},
        {"who": "mags", "line": "Up. They're slow, you're not. Act like it."},
        {"who": "host", "line": "Down in the Silt! Folks, I'm not going down there to check."},
        {"who": "host", "line": "Dinner's served!"},
        {"who": "mags", "line": "You stopped. Never stop down there."},
    ],
}
TAPE_SILT = {"who": "echo", "line": "...the Silt's not empty. The Hollows used to be people. Whatever he says."}
TAPE_DRAIN = {"who": "echo", "line": "...don't stop on the low pipes. They come up through the drains. I watched them do it."}

CLUTTER = ["debris_pile", "tire_stack", "barrel_rust", "car_wreck", "crate_wood", "pallet"]


# ------------------------------------------------------------------ 3-1

def must(who, line):
    """A story line the Stage 3 brief lists under "Must play": never
    dropped ("keep" is the older name the radio still reads)."""
    return {"who": who, "line": line, "must": True, "keep": True}


def box(x, y, z, sx, sy, sz, **kw):
    b = {"box": [x, y, z], "size": [sx, sy, sz], "kind": "NEUTRAL"}
    b.update(kw)
    return b


def wall_x(x_face, side, z0, z1, h):
    """A flood wall along z (from z0 to z1), its inner face at x_face,
    thick away from the run on `side` (-1 west, 1 east)."""
    return box(x_face + side * 1.5, h * 0.5, (z0 + z1) * 0.5, 3.0, h, abs(z1 - z0))


def wall_z(z_face, side, x0, x1, h):
    return box((x0 + x1) * 0.5, h * 0.5, z_face + side * 1.5, abs(x1 - x0), h, 3.0)


def bus(length):
    """A sunk bus's roof (the high line runs bus to bus): its window bands
    down both sides."""
    out = []
    for x in (-1.62, 1.62):
        out.append(piece(box(x, -1.05, -length * 0.5, 0.06, 0.8, length - 1.6, kind="FLOOR"), 0))
    return out


def the_silt():
    # Leg 0, west: the snapped deck, down into the bed.
    leg0 = [
        {"roof": 10, "y": 8, "bridge": True, "do": [
            {"set_piece": "silt_wreck", "at": 6, "trigger": 0, "radius": 40},
        ]},
        {"ramp_down": 0, "length": 24, "width": 12},
        {"turn": "right", "size": 24},
    ]
    # Leg 1, north up the bed between its flood walls (world_walls).
    leg1 = [
        {"roof": FIRST, "y": 0, "bare": True, "do": [
            {"checkpoint": "The Silt", "at": 4, "objective": 0},
            {"radio": must("mags", "They were people, Parker. Stayed in the dust too long. Don't let them get hold of you."), "at": 8, "radius": 9},
            {"encounter": "first hollows", "max_aiming": AIMING + 2, "at": 30, "length": 48, "enemies": [
                enemy("crawler", -3.5, 16), enemy("crawler", 3.5, 26, 0.4), enemy("leaper", 0, 38, 0.8)] + herders(4, 40, 4) + crew(52, 30) + crew(68, 30)},
            {"prop": "car_wreck", "x": 4.2, "at": 74, "yaw": 20},
        ] + catwalk(52, look="CORRUGATED") + catwalk(68) + course(12, 76, hurdle="tire_stack") + dust(FIRST)},
        {"fork": [
            {"roof": 6, "y": 0, "bare": True},
            {"ramp_up": 3, "length": 8, "width": 3.2},
            {"roof": 13, "y": 3, "width": 3.2, "look": "RUST", "bare": True, "do": bus(13)},
            {"gap": 4, "trick": "spin"},
            {"roof": 13, "y": 3, "width": 3.2, "look": "RUST", "bare": True, "do": bus(13)},
            {"gap": 4, "trick": "flip"},
            {"roof": 13, "y": 3, "width": 3.2, "look": "RUST", "bare": True, "do": bus(13)},
            # A lorry jam, wide enough to line up the wall run off it.
            {"roof": 28, "y": 3, "look": "CORRUGATED", "bare": True},
            {"wallrun": 12, "side": -1},
            {"roof": 16, "y": 3, "look": "CORRUGATED", "bare": True, "do": [
                {"tape": "l3_1_tape_hollows", "x": 0, "at": 9}]},
            {"roof": 13, "y": 0, "bare": True},
        ], "side": -1, "spread": BUS_X},
        {"roof": FORK_MAIN, "y": 0, "bare": True, "do": [
            {"radio": must("mags", "See that box on the lamppost? That's one of Echo's. She put one on every block that'd let her."), "at": 34, "radius": 10},
            {"radio": must("parker", "Even down here?"), "at": 34, "radius": 10},
            {"radio": must("mags", "Especially down here. Nobody else was going to."), "at": 34, "radius": 10},
            {"set_piece": "relay_box", "at": 34, "x": 5.4, "trigger": 14, "radius": 10},
            {"encounter": "dust pack", "max_aiming": AIMING, "at": 56, "length": 60, "enemies": [
                enemy("crawler", -3.5, 10), enemy("crawler", 3.5, 18, 0.3), enemy("leaper", -2, 28, 0.6),
                enemy("crawler", 2.5, 36, 0.9), enemy("brute", 0, 48, 1.2)] + herders(6, 56, 6)},
        ] + course(8, 120, k=1) + dust(FORK_MAIN)},
        {"join": True},
        {"roof": PENS, "y": 0, "bare": True, "do": [
            {"checkpoint": "The pens", "at": 4, "objective": 1},
            {"radio": {"who": "host", "line": "Feeding time! I do love a nature segment."}, "at": 30, "radius": 9},
            {"set_piece": "hollows_cage", "at": 34, "x": 3.6, "trigger": 12, "radius": 12},
            {"encounter": "the pens", "max_aiming": AIMING, "at": 18, "length": 62, "enemies": [
                enemy("raider", 7.4, 18, 0.0, elevation=BANK_H, cover=False),
                enemy("raider", 7.4, 40, 0.6, elevation=BANK_H, cover=False),
                enemy("crawler", 3.6, 14, 0.9, leash_radius=34, aggro_radius=30),
                enemy("crawler", 4.4, 16, 1.1, leash_radius=34, aggro_radius=30),
                enemy("leaper", 3.0, 18, 1.3, leash_radius=34, aggro_radius=30),
                enemy("crawler", 4.0, 19, 1.5, leash_radius=34, aggro_radius=30),
                enemy("brute", -2.5, 50, 0.4)] + herders(20, 68, 8, x=-4.5)},
        ] + course(10, 90, hurdle="tire_stack", k=2) + dust(PENS)},
        {"turn": "left", "size": 24},
    ]
    # Leg 2, west up the outfall channel (walled deep: it climbs two weirs)
    # to the drain mouth.
    leg2 = [
        {"roof": 8, "y": 0, "bare": True, "do": [
            {"checkpoint": "Outfall", "at": 3, "objective": 2},
            {"label": "OUTFALL 7 · NO ENTRY", "at": 5, "size": 0.9},
        ] + dust(8)},
        # The weirs: concrete spillways up, run without breaking stride.
        {"ramp_up": 3, "length": 8, "width": 12},
        {"roof": 2, "y": 3, "bare": True, "look": "NEUTRAL"},
        {"ramp_up": 6, "length": 8, "width": 12},
        {"roof": 2, "y": 6, "bare": True, "look": "NEUTRAL"},
    ] + trick_run(6, "NEUTRAL", roof=14) + [
        {"roof": 56, "y": 6, "bare": True, "look": "NEUTRAL", "do": [
            {"encounter": "outfall", "max_aiming": AIMING + 5, "at": 0, "length": 46, "enemies": [
                ] + herders(2, 26, 6, x=4.5) + crew(30, 0) + crew(42, 0)}]
            + catwalk(30) + catwalk(42) + course(4, 20, hurdle="barrel_rust")},
        {"gate": {"tier": 2}},
        {"roof": 10, "y": 6, "bare": True, "look": "NEUTRAL"},
        {"ramp_down": 0, "length": 12, "width": 12},
        {"roof": 10, "y": 0, "bare": True, "do": [
            {"radio": {"who": "mags", "line": "Storm drain. It runs under the bank and comes up at the mall. Don't stop in there."}, "at": 0, "radius": 10},
            {"label": "STORM DRAIN · MERIDIAN", "at": 6, "size": 0.9},
        ] + dust(10) + headwall(10)},
    ]
    m = {
        "id": "l3_1_the_silt",
        "title": "The Silt",
        "runner": "",
        "atlas": True,
        "plain_runner": True,
        # The test bots ride its trick lines steady (tests/test_campaign.gd).
        "bot_steady": True,
        "par_seconds": 150,
        "start": {"at": START, "yaw": 90},
        # The tower from the bridge, and down the outfall channel (it ends
        # at the drain's headwall).
        "tower_views": [START, [1690, 6, CHANNEL_Z]],
        "route_origin": {"at": START, "yaw": 90},
        "chalk": True,
        "road_lines": False,
        "clutter": CLUTTER,
        "city_open": CITY_OPEN,
        "objectives": [
            {"type": "reach", "name": "the pens", "text": "Up the Silt. Don't stop", "at": "@The pens"},
            {"type": "reach", "name": "the outfall", "text": "Past the pens to the outfall", "at": "@Outfall"},
            {"type": "reach", "name": "the storm drain", "text": "Up the outfall to the storm drain", "at": "end"},
        ],
        "radio": [
            {"on": "start", "who": "mags", "line": "You're alive. Okay. Okay, good. Run. It's not the dust you need to worry about."},
            dict(on="tape", fx="tape", keep=True, **TAPE_SILT),
        ],
        "chatter": CHATTER_SILT,
        "pieces": world_walls(),
        "route": leg0 + leg1 + leg2,
    }
    return m


# Leg 1 runs north up the bed from the bridge corner (1750, 40): its roofs
# end to end from z 28, the fork's two plazas and its main roof, then the
# pens, then the corner into the outfall (leg 2, west along z -350).
FIRST, FORK_MAIN, PENS, PLAZA = 80.0, 130.0, 110.0, 28.0
BUS_X = 14.0
BED_X = 1750.0
Z_FORK = 28.0 - FIRST
Z_JOIN = Z_FORK - PLAZA - FORK_MAIN - PLAZA
Z_PENS_END = Z_JOIN - PENS
CHANNEL_Z = Z_PENS_END - 12.0
MOUTH_X = 1554.0
CITY_OPEN = [[1700, -10, 1800, 80], [1712, CHANNEL_Z - 22, 1792, 28], [MOUTH_X - 4, CHANNEL_Z - 30, 1744, CHANNEL_Z + 30]]


def world_walls():
    """The Silt's flood walls round the bed (7 m: no way out of it) and the
    outfall channel's (13 m: it climbs to 6 m), in world coordinates."""
    h, hc = BANK_H, 13.0
    e, w = BED_X + 6.0, BED_X - 6.0
    wf = BED_X - BUS_X - 7.0
    out = [
        # East bank, the bridge corner to the outfall.
        wall_x(e, 1, 28.0, CHANNEL_Z - 9.0, h),
        # The bridge corner's south and west: the wreck dams the bed.
        wall_z(52.0, 1, BED_X - 12.0, BED_X + 12.0, h),
        wall_x(BED_X - 12.0, -1, 52.0, 28.0, h),
        # West bank: in to the bus line past the fork, out again after it.
        wall_x(w, -1, 28.0, Z_FORK, h),
        wall_z(Z_FORK, 1, wf - 3.0, w, h),
        wall_x(wf, -1, Z_FORK, Z_JOIN, h),
        wall_z(Z_JOIN, -1, wf - 3.0, w, h),
        wall_x(w, -1, Z_JOIN, CHANNEL_Z + 6.0, h),
        # The outfall channel, west to the drain mouth.
        wall_z(CHANNEL_Z + 6.0, 1, MOUTH_X, w + 3.0, hc),
        wall_z(CHANNEL_Z - 6.0, -1, MOUTH_X, e + 3.0, hc),
    ]
    return out


# ------------------------------------------------------------------ 3-2

def the_drain(start, a1, a2):
    """`start`: 3-1's end. a1: the drain main's length (south) and a2 the
    lot's (west), solved so the run ends at MALL."""
    pipe = {"interior": 7, "look": "NEUTRAL"}
    L0 = 2.0
    leg0 = [
        {"roof": L0, "y": 0, "bare": True, "interior": 6, "do": [
            {"checkpoint": "The drain", "at": 1, "objective": 0},
        ]},
        {"turn": "left", "size": 24},
    ]
    main = [
        {"roof": 70, "y": 0, "bare": True, **pipe, "do": pipe_banks(70) + [
            {"radio": {"who": "mags", "line": "Pipe's wide enough. Run the wall if you're brave."}, "at": 30, "radius": 10},
            {"encounter": "main pipe", "max_aiming": AIMING + 3, "at": 26, "length": 42, "enemies": [
                enemy("crawler", -4.5, 4), enemy("leaper", 4.5, 14, 0.4), enemy("brute", -4.5, 20, 0.5), enemy("crawler", -4.5, 24, 0.8)]
                + crew(36, 26) + crew(44, 26) + crew(60, 26) + crew(67, 26)},
        ] + catwalk(36) + catwalk(44) + catwalk(60) + catwalk(67) + course(6, 18, step=12, hurdle="barrel_rust") + course(34, 66, hurdle="barrel_rust", k=2)},
        {"fork": [
            {"roof": 2, "y": 0, "bare": True, "interior": 7, "do": shaft(2, 0, 7.0, look="NEUTRAL")},
            # Up into the side pipe on a ramp: a 3 m step at speed is a
            # wall to run, not a ledge to climb.
            {"ramp_up": 3, "length": 8, "width": 12},
            # The pipe is wider either side of its wallruns: its own walls
            # stand back from the wallrun faces, so a wallrun ends where its
            # wall does instead of running on along the pipe.
            {"roof": 14, "y": 3, "bare": True, "interior": 4, "look": "RUST", "width": 16},
            {"wallrun": 12, "side": -1},
            {"roof": 18, "y": 3, "bare": True, "interior": 4, "look": "RUST", "width": 16, "do": [
                {"tape": "l3_2_tape_drains", "x": 0, "at": 10}]},
            {"wallrun": 12, "side": 1},
            {"roof": 14, "y": 3, "bare": True, "interior": 4, "look": "RUST", "width": 16},
            {"gap": 5, "trick": "flip"},
            {"roof": 14, "y": 3, "bare": True, "interior": 4, "look": "RUST"},
            {"roof": 20, "y": 0, "bare": True, "interior": 7},
        ], "side": -1, "spread": 18},
        {"roof": 44, "y": 0, "bare": True, **pipe, "do": pipe_banks(44) + [
            {"encounter": "side pipes", "max_aiming": AIMING + 2, "at": 2, "length": 42, "enemies": [
                enemy("crawler", -4.5, 6), enemy("leaper", 4.5, 14, 0.4), enemy("crawler", -4.5, 22, 0.8)]
                + crew(28, 2) + crew(42, 2)},
        ] + catwalk(28) + catwalk(42) + course(4, 40, hurdle="barrel_rust", k=2)},
        {"roof": 36, "y": 0, "bare": True, "interior": 12, "look": "NEUTRAL", "do": ring_pipe(18) + [
            {"label": "RING MAIN 4", "at": 4, "size": 0.8}]},
        {"roof": 38, "y": 0, "bare": True, **pipe, "do": [
            {"hole": 0, "style": "broken", "at": 14},
            {"hole": 0, "style": "duct", "at": 32},
        ]},
        {"join": True},
        {"roof": 32, "y": 0, "bare": True, **pipe, "do": [
            {"checkpoint": "Pumping station", "at": 4, "objective": 1},
            {"hole": 0, "style": "duct", "at": 28},
        ] + pumps(20) + course(4, 14, step=10, hurdle="barrel_rust", k=1) + shaft(32, 0, 17, 7)},
        # Up the pump hall on its sloped sumps, not breaking stride.
        {"ramp_up": 3, "length": 8, "width": 12},
        {"roof": 8, "y": 3, "bare": True, "interior": 14, "look": "RUST", "do": [
            {"encounter": "pump hall", "max_aiming": AIMING + 3, "at": 0, "length": 30, "enemies": [
                enemy("leaper", -4.5, 6), enemy("leaper", 4.5, 22, 0.3, elevation=3)]
                + herders(2, 6, 2) + crew(20, 0, y=3.0, xs=(-4.5, 4.5)) + crew(24, 0, y=3.0) + crew(28, 0, y=3.0)}]
                + shaft(8, 3, 17)},
        {"ramp_up": 6, "length": 8, "width": 12},
        {"roof": 14, "y": 6, "bare": True, "interior": 11, "look": "RUST"},
    ] + trick_run(6, "RUST", 11) + [
        {"roof": 56, "y": 6, "bare": True, "interior": 11, "look": "RUST", "do": course(4, 20, hurdle="barrel_rust")},
        {"gate": {"tier": 2}},
        {"roof": 14, "y": 6, "bare": True, "interior": 11, "look": "RUST"},
        {"ramp_down": 0, "length": 20, "width": 12},
        {"roof": 110, "y": 0, "bare": True, **pipe, "do": pipe_banks(110) + [
            {"checkpoint": "Last pipe", "at": 4, "objective": 2},
            {"encounter": "last pipe", "max_aiming": AIMING + 3, "at": 30, "length": 44, "enemies": [
                enemy("crawler", 3, 6), enemy("crawler", -3, 14, 0.3), enemy("leaper", 0, 24, 0.6), enemy("crawler", 3, 32, 0.9),
                enemy("leaper", -2, 40, 1.2)] + crew(36, 30) + crew(50, 30) + crew(66, 30)},
        ] + catwalk(36) + catwalk(50) + catwalk(66) + course(26, 106, hurdle="barrel_rust")},
        {"roof": 60, "y": 0, "bare": True, **pipe, "do": [
            {"hole": 0, "style": "broken", "at": 14},
            {"hurdles": "barrel_rust", "at": 40},
        ]},
        {"roof": a1, "y": 0, "bare": True, **pipe, "do": pipe_banks(a1) + [
            {"encounter": "under the lot", "max_aiming": AIMING + 2, "at": 4, "length": 48, "enemies": [
                enemy("crawler", -4.5, 6), enemy("brute", 4.5, 18, 0.4), enemy("crawler", 4.5, 28, 0.8), enemy("leaper", -4.5, 36, 1.0)]
                + crew(16, 4) + crew(32, 4) + crew(48, 4)},
        ] + catwalk(16) + catwalk(32) + catwalk(48) + course(8, 56, hurdle="barrel_rust", k=1)},
        {"turn": "right", "size": 24},
    ]
    leg2 = [
        {"roof": 2, "y": 0, "bare": True, "interior": 6, "do": shaft(2, 0, 7.0, look="NEUTRAL")},
        {"ramp_up": 3, "length": 8, "width": 12},
        {"roof": 8, "y": 3, "bare": True, "interior": 4, "do": [
            {"door": 0, "look": "RUST", "at": 6},
            {"radio": must("host", "Meridian Mall, folks! The arena! Parker, darling, you just walked into the main event."), "at": 7, "radius": 6},
        ]},
        {"roof": 3, "y": 3, "bare": True},
        {"ramp_down": 0, "length": 7, "width": 12},
        {"roof": a2, "y": 0, "bare": True, "do": [
            {"label": "MERIDIAN MALL · SOUTH LOT", "at": a2 - 4, "size": 1.2},
            {"piece": {"light": [0, 5, 0], "range": 18, "energy": 1.5, "color": "#ffe2b0"}, "at": 2, "length": 0},
        ]},
    ]
    # Underground: line the generated walls (a building's, with windows)
    # with the drain's bare concrete, above the curved walls where it has
    # them, and keep the side-pipe and pump hall rust.
    # A slab over each lined roof (and over the corners after one) keeps the
    # daylight out of every seam.
    segs = leg0 + main + leg2
    for i, seg in enumerate(segs):
        if "interior" in seg:
            h = float(seg["interior"])
            w = float(seg.get("width", 12.0)) * 0.5
            lo = 3.0 if any("bank" in f.get("piece", {}) for f in seg.get("do", [])) else 0.0
            look = seg.get("look", "NEUTRAL")
            do = seg.setdefault("do", [])
            for x in (-w, w):
                # Its foot a hair off the floor: nothing on the floor fights it.
                do.append(piece(box(x, (lo + 0.05 + h) * 0.5, -seg["roof"] * 0.5, 0.1, h - lo - 0.05, seg["roof"], look=look), 0))
            do.append(piece(box(0, h + 0.45, -seg["roof"] * 0.5, 14.0, 0.5, seg["roof"] + 0.4, look=look), 0))
            nxt = segs[i + 1] if i + 1 < len(segs) else {}
            if "turn" in nxt:
                # The corner: roofed, and walled all round but where the
                # drain comes in and goes out (12 m openings).
                n = float(nxt.get("size", 24))
                d0 = seg["roof"]
                dc = d0 + n * 0.5
                out_x = -n * 0.5 if nxt["turn"] == "left" else n * 0.5
                stub = n * 0.5 - 6.0
                hh = h + 0.7
                do.append(piece(box(0, h + 0.45, -dc, n + 2.0, 0.5, n + 2.0, look=look), 0))
                do.append(piece(box(0, hh * 0.5, -d0 - n - 0.2, n + 0.8, hh, 0.4, look=look), 0))
                do.append(piece(box(-out_x + (0.2 if out_x < 0 else -0.2), hh * 0.5, -dc, 0.4, hh, n, look=look), 0))
                for sx in (-1, 1):
                    do.append(piece(box(sx * (6.0 + stub * 0.5), hh * 0.5, -d0 + 0.2, stub, hh, 0.4, look=look), 0))
                for dd in (d0 + stub * 0.5, d0 + n - stub * 0.5):
                    do.append(piece(box(out_x + (-0.2 if out_x < 0 else 0.2), hh * 0.5, -dd, 0.4, hh, stub, look=look), 0))
    m = {
        "id": "l3_2_the_drain",
        "title": "The Drain",
        "runner": "",
        "atlas": True,
        "plain_runner": True,
        # The test bots ride its trick lines steady (tests/test_campaign.gd).
        "bot_steady": True,
        "par_seconds": 170,
        "start": {"at": start["at"], "yaw": start["yaw"]},
        "route_origin": {"at": start["at"], "yaw": start["yaw"]},
        # Underground till the lot: the tower shows over the mall from there.
        "tower_views": [MALL],
        # The lot runs on west to the mall (4-1 builds it): keep it clear.
        "city_open": [[MALL[0] - 60, MALL[2] - 30, MALL[0] + 8, MALL[2] + 30]],
        "chalk": True,
        "road_lines": False,
        "clutter": CLUTTER,
        "objectives": [
            {"type": "reach", "name": "the pumping station", "text": "Down the drain main. Don't stop", "at": "@Pumping station"},
            {"type": "reach", "name": "the last pipe", "text": "Over the pumps", "at": "@Last pipe"},
            {"type": "reach", "name": "the mall", "text": "Kick the grate and get out at the mall", "at": "end"},
        ],
        "radio": [
            {"on": "start", "who": "host", "line": "Folks, he's gone down the drain. Ha. I've been waiting all day to say that."},
            dict(on="tape", fx="tape", keep=True, **TAPE_DRAIN),
        ],
        "chatter": CHATTER_SILT,
        "route": leg0 + main + leg2,
    }
    return m


def write(m):
    path = os.path.join(MISSIONS, m["id"] + ".json")
    with open(path, "w") as f:
        json.dump(m, f, indent=1)
        f.write("\n")
    print("wrote", os.path.relpath(path))


def route_end(mission_id):
    """[x, y, z, yaw] where a written mission's route ends (route_info.gd)."""
    import subprocess
    godot = os.environ.get("GODOT", os.path.expanduser("~/godot/godot"))
    out = subprocess.run([godot, "--headless", "--path", os.path.join(HERE, "..", ".."), "-s", "res://campaign/tools/route_info.gd",
                          "--", "res://campaign/missions/%s.json" % mission_id], capture_output=True, text=True).stdout
    for line in out.splitlines():
        if "  end [" in line:
            end = json.loads(line[line.index("end [") + 4:line.rindex("]") + 1])
            return end + [float(line.split("yaw")[-1])]
    raise SystemExit("no route end for %s:\n%s" % (mission_id, out))


def main():
    write(the_silt())
    x, y, z, yaw = route_end("l3_1_the_silt")
    start = {"at": [round(x, 3), round(y, 3), round(z, 3)], "yaw": round(yaw)}
    # Solve the drain main's last pipe (a1, south) and the lot (a2, west)
    # so 3-2 ends at the mall's south entrance, where 4-1 starts.
    a1, a2 = 100.0, 10.0
    for _ in range(3):
        write(the_drain(start, round(a1, 3), round(a2, 3)))
        ex, ey, ez, eyaw = route_end("l3_2_the_drain")
        if abs(ex - MALL[0]) < 0.01 and abs(ez - MALL[2]) < 0.01:
            break
        a1 += MALL[2] - ez
        a2 += ex - MALL[0]
    print("3-1 ends at %s; 3-2 ends at (%.2f, %.2f, %.2f) yaw %.0f; last pipe %.1f m, lot %.1f m" % (start, ex, ey, ez, eyaw, a1, a2))
    if a1 < 60 or a2 < 4:
        raise SystemExit("the drain doesn't fit: shorten its stretches")


if __name__ == "__main__":
    main()
