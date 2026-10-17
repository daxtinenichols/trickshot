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
- Shown on render layer 10 (`own_body`). The first-person camera leaves that
  layer out; third-person cameras include it. The body still casts its
  shadow in first person.

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
- **Whole-body rotation**: flips follow the player's actual air rotation,
  rolls spin over the roll's duration, prone and dives lie the body down.
- **Leans**: into turns while running, away from the wall on wallruns.
- **Kicks** play as a short overlay pose on the `trick` signal.

Poses are plain joint angles in degrees (see the header of `runner_poses.gd`
for the sign conventions), so tweaking one is a one-line change. Check them
with the pose sheet (below).

Later, the same system can blend in authored or mocap clips per state where a
pose is not enough (the rig's humanoid names make that a drop-in), and add
foot IK for slopes and stairs.

### Hooks wanted from gameplay

The body reads two private player fields today: `_wall_normal` (which side
the wall is on) and `_path_time` (vault/mantle progress). A small public,
read-only accessor for each on `Player` would make this robust.

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

In game: **F6** toggles the art look (compare with graybox), **F7** toggles a
full-screen chase camera to watch the runner animate.

## Maps (proposal)

Levels are built in two passes:

1. **Blockout** on a 1 m grid from a modular kit whose sizes match the
   movement numbers (vault walls ≤ 1.2 m, mantle ledges up to the climb
   reach, wallrun walls tall enough for a full run, slide ramps at slide
   angles). Collision comes from the blockout, so gameplay can be tested
   before any art exists.
2. **Art pass** swaps kit pieces for dressed versions with the same
   collision, so the art can never break a route.

The authoring tool is still open: Blender (import hints like `-col` give
collision with no plugins, and the kit can be scripted) or TrenchBroom with
the func_godot plugin (fast brush-based editing, like Hammer for CS maps).

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
