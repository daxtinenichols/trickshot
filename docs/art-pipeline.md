# Art, animation and maps pipeline

How Trickshot's visuals are made, and the rules that keep them from ever
touching gameplay. Everything here lives under `art/` (plus this doc and
`tests/test_art.gd`).

## The one rule

Visuals read the simulation; they never write to it. The player's
`simulate(InputFrame)` stays the only thing that moves the player, so the game
stays deterministic (needed for multiplayer later) and the art can change at
any time without changing how the game plays. `tests/test_art.gd` runs the
same scripted course with and without the art attached and requires the two
runs to match exactly.

## Assets and licenses

| Source | Use | License |
|---|---|---|
| Our own Blender scripts (`art/source/*.py`) | Character, props, level kit | Ours |
| Hand-written Godot shaders (`art/shaders/`) | Cel look, outlines, speed lines | Ours |
| CC0 libraries (Kenney, Quaternius, Poly Haven, ambientCG) | Props, textures, extra animations when useful | CC0, safe in a public repo |

Avoid Mixamo and store assets whose license forbids redistributing the raw
files: this repo is public, so anything committed is redistributed.

Models are built by Python scripts run in Blender, not hand-edited binaries.
That keeps every asset reproducible, reviewable in a diff, and rebuildable in
the cloud:

```
blender --background --python art/source/build_runner.py   # or: pip install bpy; python3 art/source/build_runner.py
```

The output `.glb` is committed, so nobody needs Blender just to play. Anyone
can still open the result in Blender and edit by hand; if they do, they should
say so, since the script would overwrite those edits.

## The runner (player character)

- One skinned mesh, ~8k triangles, one material. Body regions are painted as
  vertex colors (`PALETTE` in `build_runner.py`), so a recolor is one edit.
- Skeleton uses **Godot's humanoid bone names** (`Hips`, `Spine`, `Chest`,
  `LeftUpperArm`...), T-pose rest. Any humanoid animation (mocap, CC0 packs,
  hand-keyed clips) retargets onto it in Godot with no renaming.
- Shown on render layer 2. The first-person camera leaves that layer out;
  the chase camera (F10) includes it. The body
  still casts its shadow in first person. The view-model pistol is on its
  own layer (`Pistol.VIEW_LAYER`), which only the first-person camera sees.

## Animation: pose blending driven by state

`art/characters/runner/runner_body.gd` animates the runner every frame from
the player's state. There are no transition clips. Each move has a key pose
or a cycle (`runner_poses.gd`) and the body eases each pose's weight toward
what the player is doing right now, so any move can flow into any other
mid-way. This is what makes the move set blend seamlessly by construction:

- **Run cycle** advances with distance travelled, not time, so feet never
  skate at any speed. Stride, lean and arm swing scale with speed.
- **Grounding**: in grounded states the lowest contact point (feet, knees,
  hips, hands) is kept on the floor. Crouch, slide, roll and prone heights
  fall out of the poses with no per-move tuning.
- **Aim**: chest, neck and head turn toward where the player looks.
- **Whole-body rotation**: flips and side flips follow the player's actual
  air rotation, rolls spin over the roll's duration, prone and dives lie the
  body down.
- **Leans**: into turns while running, with the lean input, and away from
  the wall on wallruns (feet on the wall).
- **Aiming** down sights brings the gun arm up along the view.
- **Ramps and loops**: the body works in the player's own frame, which tilts
  on surfaces, so it runs upside down through loops with the player.
- **Kicks** play as a short overlay pose on the `trick` signal.
- States added later fall back to run/idle or air poses until they get
  their own.

Poses are plain joint angles in degrees (see the header of `runner_poses.gd`
for the sign conventions), so tweaking one is a one-line change. Check them
with the pose sheet (below).

Later, the same system can blend in authored or mocap clips per state where a
pose is not enough (the rig's humanoid names make that a drop-in), and add
foot IK for slopes and stairs.

### What it reads from the player

Public, read-only: `state`, `state_time`, `velocity`, `pitch`, `lean`,
`aim_zoom`, `air_rotation()`, `air_roll()`, `roll_progress()`,
`vault_progress()`, `wall_normal()`, `is_diving()`, the player's own basis,
and the `landed` / `trick` / `respawned` signals.

## The look

- **Toon shader** (`art/shaders/toon.gdshader`): flat color, two hard light
  bands, shadows as their own hard band, optional rim light (on for the
  runner, off for world surfaces) and the faint meter grid for blockouts.
- **Ink outlines** (`art/shaders/outline_post.gdshader`): a full-screen pass
  from the depth buffer that draws silhouettes and creases in one measure.
  Works in Forward+ and Compatibility.
- **Ambient** is a flat cool tint, so shadows are blue-gray, not black.
- **Speed colors** everywhere use one ramp: blue below run speed, yellow at
  run speed, red at top speed. Motion trails stream from hands and feet
  above run pace (third person), and speed lines build at the screen edges
  in first person.
- **Color language** from the graybox carries over: blue = wallrun, yellow =
  vault/mantle/climb, green = slide, red = targets.

`ArtLook` (autoload) applies all of this to whatever level runs. For the
code-built sandbox it swaps the graybox materials; real maps use
`ArtLook.world_material(color)` directly.

In game: **F9** toggles the art look
(compare with graybox), **F10** toggles a full-screen chase camera (the wheel zooms it; zooming
all the way in returns to first person).

## Environment textures

`art/shaders/wasteland.gdshader` textures world geometry procedurally in
world space (planar projection, no UVs or image files): `surface` picks
concrete, rusted metal, asphalt, painted metal or concrete (chips show what's
under the paint) or a building facade with a window grid. Detail is
posterized into a few flat steps so it sits inside the cel bands. Dust
settles on top faces, grime streaks down walls. `ArtLook.SURFACES` maps each
gameplay kind to a surface; a builder can set a visual-only `look` meta on a
body (e.g. `"FACADE"`) to dress it differently from its gameplay kind. Cel
lighting is shared through `art/shaders/toon_light.gdshaderinc`.

## Gun

`art/source/build_gun.py` builds `art/weapons/scrap_pistol.glb` (beveled
boxes, vertex colors, a separate "Slide" mesh). `art/weapons/gun_look.gd`
puts it in first person under `Pistol.view_model` and in the runner's right
hand, turns off the test pistol's builtin visuals, and draws every shot from
the Pistol's `shot` signal: muzzle flash (`art/shaders/muzzle_flash.gdshader`),
flash light, smoke, slide blowback (locked back on empty), casings, tracer,
sparks, dust, chips and bullet-hole decals. Sounds are synthesized in
`art/fx/gun_audio.gd`. Preview with `art/tools/gun_shots.gd`.
F5-F8 are left alone because the Godot editor uses them to run, pause and
stop the game.

## Maps

Maps are built in code for now, like the sandbox: a builder script
(`maps/*_builder.gd`, extending `SandboxBuilder`) places boxes, ramps,
loops, doors, windows and targets, and the scene reuses the sandbox's
player, HUD and menu. That keeps every size tied to the movement numbers and
lets tests run the real map:

- **Rooftops** (`maps/rooftop_course_builder.gd`, `maps/course_timer.gd`): a
  timed course along -Z. `tests/test_maps.gd` runs a scripted player from
  start to finish without falling, so a change that breaks the route fails CI.
- **Combo Park** (`maps/combo_park_builder.gd`): an open yard of features a
  few steps apart. Tests check each spawn and that the tower, half-pipe,
  loop, zigzag and sideways ramps work in place.
- **Ruined Mall** (`maps/mall_builder.gd`): two floors round a skylit
  atrium, with escalators, a bridge, hanging billboards to wallrun, shops
  with breakable storefront glass, a collapsed walkway beside a wallrun wall,
  and a caved-in food court with a debris ramp up. Bodies carry visual-only
  `look` (TILE, RUST, SIGN...) and `look_color` metas for the art pass.
  Tests check each spawn, the escalator climb and the storefront glass.
- **Long maps and the campaign**: Rooftops, Combo Park and the mall are
  campaign base maps. Each builder has `ENTRY` (= `spawns[0]`) and `EXIT`
  Transform3D constants (the mall also `ANCHOR_ENTRY`/`ANCHOR_EXIT` for its
  department store) and `open_exit`, which leaves the far (-Z) edge of the
  ring of buildings open so a mission can carry on. Main line runs to -Z.
- **Closed edges**: every map's floor is ringed with `MapPieces.perimeter`;
  `_check_closed` in tests/test_maps.gd proves it.
- **Sideways ramps** (`MapPieces.bank` in `maps/map_pieces.gd`): a quarter
  pipe turned to rise beside the way you run, with its flow along the run.
  The player rides them with the normal surface rules; steepness and radius
  are constants at the top of each builder.

Sizes used: vault obstacles 0.9–1 m, slide bars at 1.1 m clearance, mantle
steps 1.5 m, climb faces 3 m, running-jump gaps 4–6 m, wallrun gaps 12 m
(too far to jump), quarter pipes radius 3.5–4.5 m.

Later, for hand-made maps: build a blockout on a 1 m grid from a modular kit
with these sizes, then an art pass that swaps kit pieces for dressed versions
with the same collision, so the art can never break a route. The tool is
still open: Blender (`-col` import hints give collision with no plugins) or
TrenchBroom with func_godot (brush editing, like Hammer).

Map overview shots: `xvfb-run godot --path . -s res://art/tools/map_shots.gd -- <out_dir>`.

## Checking visuals without a GPU

`art/tools/art_shots.gd` renders the sandbox with the look on and off, a
contact sheet of every key pose, and side-on filmstrips of the runner moving
under scripted input (run and jump, slide, vault):

```
xvfb-run godot --path . --fixed-fps 60 -s res://art/tools/art_shots.gd -- /tmp/shots
```

In a container without a GPU, install `mesa-vulkan-drivers` for Forward+
(software Vulkan), or add `--rendering-method gl_compatibility`. Compatibility
renders noticeably brighter than Forward+, so judge colors in Forward+.
