# Writing missions

A campaign mission is one JSON file in `campaign/missions/`. It holds the
layout, checkpoints, objectives and every radio line, so a new level or a
rewrite of the story needs no code. `campaign/campaign.json` lists all
thirteen missions of *Dead Air* in order; a mission with a `file` is
playable, one without shows its story beat in the campaign menu as "coming
later".

## Trying a mission

- In game: Esc → Campaign, pick it, Play. Keys 1–9 jump to the start and
  each checkpoint (a practice run: nothing is saved).
- In the editor: open `campaign/mission.tscn`, select **Builder**, set
  **Mission Path** to the file, and tick **Rebuild** after saving the JSON
  to see the layout. Run the scene (F6) to play it.
- Tests: `tests/test_campaign.gd` loads every mission, checks every spawn is
  safe to stand on, and runs scripted routes through missions 0, 2 and 12.
  Add a route for a new mission when its layout settles.
- Pictures: `xvfb-run -a godot --path . --fixed-fps 60 -s res://campaign/tools/mission_shots.gd -- <out_dir>`.

## The file

```json
{
 "id": "m02_on_air",            // same as its entry in campaign.json
 "title": "On Air",
 "runner": "",                  // "" = the player's pick; "echo" or "parker" forces one
 "base": "",                    // optional: build on an existing map, e.g. "res://maps/rooftop_course_builder.gd"
 "fail_y": 2.5,                 // below this you've fallen: back to the last checkpoint
 "par_seconds": 60,
 "start": {"at": [0, 8, -3], "yaw": 0},
 "checkpoints": [ ... ],
 "objectives": [ ... ],
 "radio": [ ... ],
 "chatter": { ... },
 "pursuer": { ... },            // only in a chase
 "pieces": [ ... ]
}
```

(JSON has no comments; they are here only to explain.) Coordinates are
meters, Y up, and the route usually runs toward -Z. Sizes come from the
movement numbers: a 0.8–1.1 m block vaults, up to ~1.5 m above your hands
mantles, a 1.1 m gap under a bar slides, ~9 m is a running jump, ~12 m
needs a wallrun, a 3 m face climbs.

### Checkpoints

```json
{"name": "Lookout roof", "at": [0, 8, -85], "size": [14, 8, 4], "objective": 1}
```

Crossing the box (`at` is its center, `size` its full size) moves your
respawn there. `spawn` sets a different respawn point than `at`.
`objective` is the objective a practice run from this checkpoint starts on.
Checkpoints are in order; reaching a later one counts the ones before.

### Objectives

Done in order; the mission is complete when the last one is.

| type | fields | done when |
|---|---|---|
| `reach` | `at`, `size` (box) or `radius` (cylinder 3 m up and down), `name` | you're inside the region |
| `score` | `points` | your total score this run reaches it |
| `combo` | `multiplier` | you bank a combo at that multiplier or more |
| `shoot` | `count`, `headshots` (true = only headshot kills count) | that many target kills since the objective began |
| `collect` | `count` (default: every tape) | that many tapes found |

`text` is what the HUD shows; without it a default is written.

### Radio

Story lines play once, queued, without ever stopping the game:

```json
{"on": "go", "who": "host", "line": "Parker, darling, you're on the air."}
{"at": [4, 8, -62], "radius": 7, "who": "mags", "line": "Wall on the right, same as home."}
```

`who`: `mags`, `host`, `echo`, `parker`, `juno`. Triggers (`on`):
`start` (mission loads), `go` (you leave the start), `objective:N` (objective
N begins), `done:N`, `checkpoint:N`, `complete`, `time:SECONDS`, `fall`,
`caught`, `tape`. Or use `at` with `radius`/`size` to play when you reach a
spot.

`chatter` holds reactions to how you play, by event: `bail`, `combo` (a
banked combo of x4 or more), `fall`, `kill`, `headshot`, `caught`, `tape`.
Each is a list of `{"who", "line"}` used in turn, at most one every few
seconds, and never over a story line.

### The chase

```json
"pursuer": {"name": "THE HOST", "speed": 7.6, "speed_gain": 0.03, "max_speed": 9.4,
            "delay": 2.5, "catch_distance": 1.6, "leash": 22, "catchup_speed": 12.5}
```

He sets off `delay` seconds after you, follows your exact path, speeds up
over time, and never drops more than `leash` meters behind (past it he runs
at `catchup_speed`). Within `catch_distance` you're caught and go back to
the last checkpoint. A clean run keeps him about `leash` behind; a stop of
two or three seconds gets you caught.

### Pieces

| piece | fields |
|---|---|
| `{"building": [x, roof_y, z], "size": [w, d]}` | a building from the street to its roof (ruined facade look) |
| `{"box": [x, y, z], "size": [w, h, d], "kind": "WALLRUN"}` | a block; kind is the color language: `FLOOR`, `NEUTRAL`, `WALLRUN` (blue), `PARKOUR` (yellow), `SLIDE` (green), `SURFACE`; `look` overrides the art look (e.g. `FACADE`); `yaw` in degrees |
| `{"prop": "car_wreck", "at": [x, y, z], "yaw": 70}` | a prop from the kit (below) |
| `{"row": "barricade_jersey", "from": [..], "to": [..], "count": 6}` | a row of one prop |
| `{"door": [x, y, z]}` | kickable door, hinge at the point |
| `{"window": [x, y, z], "size": [2.2, 1.4]}` | breakable window, bottom center |
| `{"target": [x, y, z], "motion": "strafe", "amplitude": 3, "speed": 3}` | shooting target: `static`, `strafe`, `bob`, `circle` |
| `{"ramp": [top], "to": [bottom], "width": 4, "kind": "SLIDE"}` | flat ramp |
| `{"loop": [x, y, z], "radius": 4.5, "width": 3.5, "shift": 5.5}` | running loop |
| `{"quarter_pipe": [x, y, z], "radius": 4, "angle": 80, "width": 8}` | quarter pipe |
| `{"bank": [x, y, z], "length": 10, "side": 1}` | sideways ramp |
| `{"label": "text", "at": [x, y, z], "size": 0.8}` | floating sign |
| `{"mark": [x, y, z], "size": [w, d], "color": "#f57320"}` | painted floor mark |
| `{"tape": [x, y, z], "id": "m02_tape_container"}` | a lost broadcast tape (collectible); ids must be unique |
| `{"fire": [x, y, z], "size": [w, h, d]}` | flames and light, no collision |

## Props

`art/source/build_props.py` builds the prop kit into `art/props/<name>.glb`
and writes `art/props/props.json` with each prop's size, box colliders and
tags. Every prop's origin is its bottom center, front toward -Z.
`art/props/prop_kit.gd` places them (`PropKit.place(parent, name, xform)`),
loading models by path and falling back to gray boxes if one isn't imported
yet. Render them all with
`xvfb-run -a godot --path . --fixed-fps 60 -s res://art/tools/prop_shots.gd -- <out_dir>`.

| prop | size, use |
|---|---|
| `crate_wood` | 0.9 m, vault |
| `crate_stack` | 1.75 m, mantle |
| `pallet`, `barrel_rust`, `tire_stack` | low clutter, vault |
| `shipping_container` | 6 × 2.6 × 2.4 m, wallrun the sides, run the roof |
| `water_tank` | rooftop tank on legs, 3.6 m deck |
| `ac_unit`, `vent_stack`, `satellite_dish` | rooftop clutter |
| `antenna_mast` | 12 m lattice radio mast with a red lamp |
| `loudspeaker_pole` | the Host's horn speakers on a pole |
| `planter_tub`, `tarp_shelter`, `radio_set` | Line camp pieces |
| `railing` | 1.05 m, vault |
| `scaffold_bay` | 2 × 1.2 × 3 m, decks at 1.5 and 3 m |
| `plank_bridge` | 4 m of planks across a gap |
| `car_wreck` | 0.9 m hood (vault), 1.4 m roof |
| `barricade_jersey` | 0.8 m concrete barrier, vault |
| `barricade_scrap` | 1.6 m Static roadblock, mantle |
| `sandbag_wall` | 1 m, vault and cover |
| `debris_pile` | rubble |
| `dumpster` | 1.2 m, mantle |
| `billboard` | 6 × 3 m panel 5–8 m up, wallrun; catwalk |
| `street_sign`, `fence_chainlink` (3 × 2.2 m), `generator` | street pieces |
| `tape_cassette` | the collectible tape (no collision) |
| `chalk_arrow` | orange courier route mark on the ground (no collision) |

Add a prop: write a function decorated with `@prop` in `build_props.py`
(parts are beveled boxes, cylinders, cones, prisms and lumps, painted from
the palette; add `collide(...)` boxes and tags), run
`python3 art/source/build_props.py <name>`, then import in Godot.
Glowing parts use the `lamp_*` colors.
