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
  safe to stand on, and runs a bot through mission 0, through every mission built from a `route`
  (mission 12's bot must also stay ahead of the Host), and through every hand-made mission with a
  `bot_path` (see "Hand-made missions" below). A route mission is tested automatically;
  `ROUTE_ONLY=m09` runs just the matching missions and prints their length, legs and enemy count.
- Pictures: `xvfb-run -a godot --path . --fixed-fps 60 -s res://campaign/tools/mission_shots.gd -- <out_dir>`.

## The file

```json
{
 "id": "m02_on_air",            // same as its entry in campaign.json
 "title": "On Air",
 "runner": "",                  // "" = the player's pick; "echo" or "parker" forces one
 "base": "",                    // optional: build on an existing map, e.g. "res://maps/rooftop_course_builder.gd"
 "base_set": {},                // optional: the base builder's exported settings, e.g. {"hide_course_marks": true}
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

## Routes: long missions

The campaign crosses the city from Parker's docks in the east to the
broadcast tower in the west; each mission starts where the last ended.
Long missions (500–1000 m) are written as a `route`: segments laid end to
end toward -Z from the start, each roof with its features. The route adds
its pieces, checkpoints and radio lines to the mission, a street under it
and the city on both sides, and a bot route the tests run to the end.
See `m03_glass_district.json`.

```json
"route": [
 {"roof": 52, "do": [{"hurdles": true, "at": 14}, {"slide": true, "at": 30}]},
 {"gap": 5},
 {"roof": 64, "do": [{"checkpoint": "Office roofs", "at": 3}, {"window": 3.3, "at": 22}]},
 {"wallrun": 12, "side": 1},
 {"roof": 44, "y": 17, "do": [...]},
 {"ramp_down": 0, "length": 22}
]
```

| segment | |
|---|---|
| `{"roof": length, "y": h, "width": 12, "do": [...]}` | a roof (y 0 is the street). Higher than the roof before and straight on: a yellow face to climb (3 m max). Lower after a gap: a drop (roll from 3.5 m) |
| `{"roof": 80, "y": 1, "interior": 6}` | the inside of a building: walls and a roof `interior` m over the floor, with skylights every 10 m (a warehouse, an office floor). Enter by ramp or straight on; climb out to a higher roof at its end |
| `{"roof": 26, "bridge": true, "beyond": 150}` | a bridge deck on piers instead of a building (railings, girders); `beyond` m more of the span carry on past its end, seen but not run (m03's Silt bridge) |
| `{"gap": m}` | a running jump: 4–7 m level, up to 9 m onto a lower roof |
| `{"wallrun": 12, "side": 1}` | a gap with a blue wall on the right (-1 left) |
| `{"ramp_up": y}` / `{"ramp_down": y, "length": 22}` | a ramp to a new height (down is a slide ramp) |
| `{"street": m}` | a stretch at street level (y 0) |
| `{"skip": m}` | nothing for `m` m: the base map's own ground past its EXIT (a route from `base_exit` starts 6 m behind EXIT) |
| `{"turn": "left", "size": 20, "angle": 90}` | a corner where the run turns left or right: 90° (a square roof `size` m across) or 45° (`"angle": 45`, a slab joining the roofs before and after) |
| `{"fork": [segments], "side": 1, "spread": 18}` | the route splits on a wide roof: `fork` is a second line run beside the main one (right, or `-1` left), while the segments after it carry on the main line |
| `{"join": true}` | the two lines meet again on a wide roof (the shorter one is lengthened); both must end at the same height |

Features on a roof, `at` meters from its start:

| feature | |
|---|---|
| `{"hurdles": true}` | a row of road barriers to vault |
| `{"slide": true}` | a bar to slide under (12 m of ground before it) |
| `{"window": x}` | a wall across with a low window at x to slide through |
| `{"hop": true, "side": -1}` | a wall hop pair |
| `{"checkpoint": "Name", "objective": 1}` | a checkpoint; objectives and radio can use `"at": "@Name"`, and `"at": "end"` for the route's end |
| `{"encounter": "id", "length": 40, "raiders": [[x, d, wake]], "mutants": [[x, d]], "troopers": [[x, d, wake]], "drones": [[x, d, height]]}` | enemies (d from the feature); raiders and troopers get sandbags 3 m in front, drones hover `height` m up |
| `"enemies": [{"type": "shield", "x": 2, "d": 20, "wake": 1, "height": 4}]` (in an encounter) | any enemy type, placed like troopers: raiders, troopers and marksmen get sandbags (`"cover": true/false` overrides), `*drone` types hover `height` m up, crawlers, leapers and brutes are leashed to their patch; other fields set the enemy's settings |
| `{"piece": {"bank": [4, 0, -10], "length": 10, "side": 1}, "length": 12}` | any mission piece in the roof's frame (x across, y up from the roof, z from this spot, negative further along), turned with its leg; `length` m of roof kept clear of clutter |
| `{"tape": "id", "x": 4.6, "height": 0}` | a lost tape |
| `{"radio": {"who", "line"}, "radius": 7}` | a radio line played here |
| `{"prop": "car_wreck", "x": -4, "yaw": 80}`, `{"label": "text"}`, `{"mark": "#f57320"}` | dressing |
| `{"lane": x}` | where the test bot runs from here |

Everything after a corner is laid out turned with the run (checkpoints
face along it). Two 45° corners make a 90° turn with a diagonal stretch
between; on a diagonal leg roofs are turned boxes and checkpoints turned
regions (`area_yaw`), but enemy areas stay square to the grid (the box
around the turned area), so keep encounters on legs square to the grid. Missions keep
heading west overall: turn back the other way after a corner. A fork's line
can't hold checkpoints, corners or another fork; put its own hazards and
pickups on it (a high line of climbs and wallruns, a low line through the
street, an encounter on one of them).

Where the route begins: by default at the world origin heading -Z. Set
`"route_origin": {"at": [x, y, z], "yaw": 90}`, or `"route_from":
"base_exit"` to carry on from the base map's `EXIT` (the base's far edge is
then left open).

The test bot runs every route mission (`bot`), and again down the other
line of every fork (`bot_alt`); `route_legs` tells it where the corners
are, so its triggers are distances along the run, not world z.

`"chalk": true` paints the run: an orange courier chalk arrow where each
main-line roof starts, and a faded mark on the other line of a fork.

`"roof_look"` sets the art look of every generated roof building (default
`FACADE`; a segment's own `look` wins). `TOWER_BASE` dresses them as the
broadcast tower's scaffolded concrete decks (m10).

Roofs also get edge clutter from `clutter` (a mission-level list of props),
kept out of run-ups, landings and features. Keep lines long and open:
there is no speed cap, so a fast run must still land every roof.

### Checkpoints

```json
{"name": "Lookout roof", "at": [0, 8, -85], "size": [14, 8, 4], "objective": 1}
```

Crossing the box (`at` is its center, `size` its full size) moves your
respawn there. `spawn` sets a different respawn point than `at`.
`objective` is the objective a practice run from this checkpoint starts on.
Checkpoints are in order; reaching a later one counts the ones before.

### Objectives

Done in order; the mission is complete when the last required one is.

**Kill goals are never required to win.** A `shoot` objective is a bonus
goal unless it says `"optional": false` (only the yard's practice dummies in
The Yard do), and any objective with `"optional": true` is one too. The
chain steps over bonus goals, so reaching the end always wins and nobody is
sent back for enemies they ran past. A bonus opens when the chain reaches
it (its `objective:N` line plays then), stays open until the next required
objective is done, shows under the objective on the HUD, and is worth
`MissionRun.BONUS_POINTS` (1,000) when finished in time (`done:N` plays).
The results card counts them. Keep `clear` for story beats you can't skip,
like Juno's fight. Radio and HUD text for a bonus must not say the player
has to do it to go on.

| type | fields | done when |
|---|---|---|
| `reach` | `at`, `size` (box) or `radius` (cylinder 3 m up and down), `name` | you're inside the region |
| `score` | `points` | your total score this run reaches it |
| `combo` | `multiplier` | you bank a combo at that multiplier or more |
| `shoot` | `count`, `headshots` (true = only headshot kills count) | that many target kills since the objective began (a bonus goal by default) |
| `collect` | `count` (default: every tape) | that many tapes found |
| `clear` | `encounter` (its id) | that encounter is cleared: every enemy down, or out of the fight like a spared Juno |

`text` is what the HUD shows; without it a default is written.

### Radio

Story lines play once, queued, without ever stopping the game:

```json
{"on": "go", "who": "host", "line": "Parker, darling, you're on the air."}
{"at": [4, 8, -62], "radius": 7, "who": "mags", "line": "Wall on the right, same as home."}
```

`who`: `mags`, `host`, `echo`, `parker`, `juno`, `vell`. Triggers (`on`):
`start` (mission loads), `go` (you leave the start), `objective:N` (objective
N begins), `done:N`, `checkpoint:N`, `complete`, `time:SECONDS`, `fall`,
`caught`, `down`, `tape`, `kill:TYPE` (the first kill of an enemy listed by
type, like `kill:camera_drone`). Or use `at` with `radius`/`size` to play when you reach a
spot.

`chatter` holds reactions to how you play, by event: `bail`, `combo` (a
banked combo of x4 or more), `fall`, `kill`, `headshot`, `down` (enemies
took you down), `caught`, `tape`.
Each is a list of `{"who", "line"}` used in turn, at most one every few
seconds, and never over a story line.

Every line is spoken. After adding or rewording lines, run
`python3 audio/tools/make_voices.py` (setup in its header) to voice them (lines from the story briefs are usually voiced already: `--briefs` reads them ahead of time into `audio/voices/upcoming.json`); until
then a new line shows as a subtitle only. Voices per speaker are in
`audio/voices/cast.json`; `audio/voices/script.csv` is the recording script, and
a recorded take saved under `audio/voices/recorded/` replaces the synthetic one.

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
| `{"building": [x, roof_y, z], "size": [w, d]}` | a building from the street to its roof (ruined facade look); `"look": "TOWER"` dresses it as the broadcast tower (scaffold, aviation paint, lattice mast on the roof) |
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
| `{"encounter": "name", "area": {...}, "raiders": [...], "mutants": [...], "cover": [...]}` | enemies (below) |

### Enemies

```json
{"encounter": "lookouts", "area": {"at": [0, 12, -106], "size": [12, 10, 46]},
 "raiders": [{"at": [-3, 8, -119], "yaw": 180}, {"at": [0, 8, -126], "yaw": 180, "wake": 1.5}],
 "mutants": [{"at": [0, 8, -140], "leash_radius": 14, "aggro_radius": 10}],
 "cover": [{"at": [-3, 8, -116], "length": 2.0, "yaw": 0}]}
```

The Host's raiders (rifles, take cover, a red laser before each shot) and
mutants (rush and leap, leashed to where they stand) from `enemies/`. They
wake when you step into `area` (a box: `at` center, `size` full size) and
fight until they're all down. Leave the area for a few seconds, or go down,
and they reset; going down sends you back to the last checkpoint. `yaw` 180
faces +Z (toward a runner coming down the usual -Z route); `wake` delays an
enemy by that many seconds. `cover` rows are spots raiders hide behind, one
every `spacing` m (2.2) on both sides of a low wall `length` m long; put a
`sandbag_wall` or barricade there too. Other kinds go in `"enemies": [{"type": "drone", "at": [...], "yaw": 180}]`:
each type spawns `res://enemies/<type>.gd` (same contract as raiders), and
any other field sets that enemy's property of the same name. If a kind
is missing, troopers, shields, marksmen and heavies stand in as raiders and
crawlers, leapers and brutes as mutants. Every type in `docs/enemies.md`
has a script now.
Optional: `max_aiming` (2: raiders
aiming at once), `restart` (seconds before a cleared encounter comes back;
never by default), `hear_shots` (true: your shots wake the encounter's
`"sleeper": true` enemies within `hearing_radius`, 30 m; they also wake
within `wake_distance`, 5 m). Every kill counts toward `shoot` objectives,
like targets. A boss who can be spared (Juno) never counts as a kill unless
you finish her, so use a `clear` objective for her fight, and the radio
events `fate:spared` / `fate:not_spared` for the line that follows.

## Hand-made missions on a base map

The Meridian Mall missions (m05-m07) are laid out by hand on the mall
(`"base": "res://maps/mall_builder.gd"`): the building is the level, and
the mission adds its dressing, gates, enemies and radio as ordinary
pieces. Each one runs between two of the mall's hand-off points, in order:
m05 Atrium from `ENTRY` to `ANCHOR_ENTRY`, m06 Anchor Store from
`ANCHOR_ENTRY` to `ANCHOR_EXIT` (the store roof), and m07 Parking Spiral
from `ANCHOR_EXIT` across a skybridge to a car park past the mall's `EXIT`.

- `"open_exit": true` opens the base map's far edge (as a route does), so
  pieces can carry on past it.
- `"bot_path": [[x, z], [x, z, "jump"], ...]` is the test bot's line:
  waypoints it runs through in order, with `"jump"`, `"crouch"` or `"roll"`
  done on reaching one. `"bot_path_alt"` is a second line (the high line),
  run as well. A turned checkpoint needs `"yaw"` so its respawn faces along
  the run.
- m07's car park (a three-lap helix of sloped decks round an open core,
  where Juno waits) can't be a route, since its laps stand over each other.
  `campaign/tools/build_car_park.py` writes it: every piece tagged
  `"group": "car_park"` plus both bot paths. Change the numbers there and
  re-run it; everything else in the file is hand-written and kept.

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
