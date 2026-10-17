# Trickshot

A fast first-person parkour shooter. Moving with style scores points (Skate-style combos), and shooting well while doing it is the point of the game.

This repo is currently the **movement sandbox**: a graybox level for building and tuning the movement and a test pistol before any real levels or scoring.

## Running it

1. Install **Godot 4.7.1 (standard, not .NET)** from https://godotengine.org/download.
2. Open Godot, choose **Import**, and select `project.godot` in this folder.
3. Press **F5** (or the play button). You spawn on the run track.

Mouse/keyboard and controller both work (any XInput pad, including a wired or wireless Xbox 360 controller; the Settings tab lists the controllers it sees). Press **Esc** (or Start) for the menu: a list of every move and how to do it, settings (mouse and aim-down-sights sensitivity, controller look speed, field of view, invert, volume), and custom controls.

## Controls

| Action | Keyboard / mouse | Controller |
|---|---|---|
| Move | WASD | Left stick |
| Look | Mouse | Right stick |
| Jump / vault / climb | Space | A |
| Crouch / slide / roll | Ctrl or C | B |
| Dolphin dive (prone jump) | Z | D-pad down |
| Kick | F | RB or R3 |
| Quick turn (180) | Shift | LB |
| Lean (side flip in the air) | Q / E | D-pad left / right |
| Fire | Left mouse | Right trigger |
| Aim down sights | Right mouse | Left trigger |
| Reload | R | X |
| Semi / full auto | B or V | Y |
| Respawn | Backspace | Back |
| Menu (moves, settings, controls) | Esc | Start |
| Jump to zone | 1–9, 0 = shooting range, - = ramps and loop | |
| HUD / tuning / slow-mo / speed trail / corner view | F1 / F2 / F3 / F4 / F5 | |
| Art look / chase camera / next level | F9 / F10 / F11 | |

You always sprint: there's no walk or sprint key. Let go of the stick to stop.

A small third-person view in the lower-left corner shows your character so you can see what your moves look like (F5 hides it).

## How the moves work

Every move is simple to do. Doing it *precisely* gets you more out of it: more speed, a longer wallrun, a higher climb. The HUD grades each move OK / GOOD / PERFECT so you can feel the difference.

| Move | How | What precision gets you |
|---|---|---|
| Run | Move in any direction (always a sprint) | Keeping your speed up builds momentum, which raises your top speed (7.5 to 11.5 m/s) |
| Hop / bunny hop | Jump as you land | Jumping within ~2 frames of landing keeps all your speed; early jumps bleed it |
| Hurdle / vault | Press jump at a waist-high (yellow) wall, on the ground or in the air. Never automatic: you can always just jump over | Taking off at the right distance gives a faster, cleaner vault |
| Mantle | Jump into a ledge up to ~1.5 m above your reach | Grabbing it cleanly keeps more speed |
| Slide | Crouch while sprinting | Faster entry slides further; slopes add speed |
| Slide landing | Hold crouch as you land from a fall | Turns some of your fall into forward speed |
| Dolphin dive (prone jump) | Z. There's no lying prone or crawling | Tap to dive and pop up into a slide; hold to stay on your belly for low gaps. You get up by yourself when the slide runs out. Dive through low windows |
| Wallrun | Jump into a blue wall at an angle, holding a direction | Shallow angle + speed = longer, floatier run. Look and aim anywhere while running; crouch drops off |
| Wall hop | Jump during a wallrun or next to a wall in the air | Kicks you off the wall; chain wall to wall |
| Wall climb | Jump at a wall head-on | Straighter and faster = higher. Jump mid-climb to kick back off it (your view stays put; quick turn if you want to face away) |
| Ramp run / loop | Run onto a purple ramp or loop | Gravity slows you going up and speeds you coming down. Fast enough and you run up steep ramps and upside down round loops; too slow and you drop off. Launch off the lip of a ramp for air tricks |
| Roll | On the ground, flick the view down past your feet | A forward roll, like a flip on the ground. Keeps your speed |
| Landing roll | Land tucked forward (view pointing down, or partway into a front flip), or press crouch just before a hard landing | Rolls out of big drops without losing speed instead of a stun |
| Kick | F. In the air: kick off walls and targets | Kicking with speed pushes you further. Kicks doors open and breaks windows |
| Quick turn | Shift | Spins you 180. On a wall it faces you away from it, ready to jump |
| Lean | Q / E on the ground | Peek around corners |
| Side flip | Hold Q or E in the air | Rolls you sideways. Let go near level to land clean; land on your side and you crash |
| Window smash | Run, slide or dive into glass fast enough | |
| Backflip / front flip | In the air, keep moving the view up and over (backflip) or down and over (front flip) until it comes back around | Past straight up/down the view turns faster, so commit to the flick. The HUD shows your flip progress. Land level or you crash |
| 360 / 720 | In the air, turn a full circle | Quick turn doesn't count |

You never have to stand still, but you can: let go of the stick and you stop quickly.

## Shooting

The test pistol is hitscan. The first shot after the gun settles always goes exactly where the crosshair is, even mid-flip at full sprint. Spamming blooms the spread, and controlled fire stays accurate.

- Body 28 damage, headshot ×2.5 (70). Targets have 100 health: two headshots or four body shots. Target heads are 36 cm across.
- Damage falls off from 30 m to 70 m, down to 60%.
- Semi-auto is capped at 7 shots/s. Full-auto fires 11 shots/s. Magazine 15, reload 1.25 s.
- Recoil kicks the view and settles back. It is visual only, so it never breaks a flip.
- Aiming down sights zooms in and slows the look speed to match.
- Target health refills after 2.5 s without a hit, so kills reward landing shots quickly.
- Hits are tagged with what you were doing (airborne, wallrun, mid-flip, upside down, sliding, diving, fast). These tags feed into scoring later.

All weapon numbers are in `weapons/weapon_stats.gd`.

## Combos and score

Scoring works like Skate. Every move and every stylish hit adds points to a running combo shown at the bottom of the screen, and each one pops up as you do it ("+300 BACKFLIP").

- **Multiplier:** +1 for each different trick in the combo. Repeating a trick is worth 60% of the last time.
- **Speed and precision:** points scale from 1x at run pace to 2x at top speed, and from 0.75x (OK) to 1.25x (PERFECT).
- **Banking:** the combo's points times its multiplier go to your score when you come to rest or go 2 s without a new trick. Sliding, wallrunning, climbing and vaulting hold the clock.
- **Kill finish:** a kill ends the combo on the spot. A card shows the whole chain ending in COMBO KILL, then the points count into your score.
- **Bailing:** a crash, a hard landing, slamming into a wall or falling out loses the combo.
- **Shots count too:** headshot, air shot (0.4 s+ off the ground), long shot (40 m+), slide shot, wallrun shot, flip shot, spin shot and kills each add a trick.
- **Damage:** shots hit harder in a combo: 1 + 0.2 per different trick, times the speed bonus, capped at 3x.

Point values are in `scoring/combo_tracker.gd`.

## Sandbox zones

| Key | Zone | What to practice |
|---|---|---|
| 1 | Run track | Momentum and top speed, distance markers |
| 2 | Vault lane | Hurdles, vaults and mantles at speed |
| 3 | Mantle heights | Ledge grabs from 1.2 m to 4.8 m |
| 4 | Wallrun | Corridor, wall-to-wall zig-zag, long practice wall |
| 5 | Wall climb | Climbs, climb + mantle, climb kick back |
| 6 | Slide hill | Downhill slides |
| 7 | Drop tower | Landing rolls, flips and 360s from height |
| 8 | Kick-off yard | Air kicks off pillars and targets |
| 9 | Doors and windows | Door kicks, dives and window smashes |
| 0 | Shooting range | Static and moving targets, a wall to wallrun-and-shoot from, a platform for air shots |
| - | Ramps and loop | A loop after a long run-up, a launch ramp, a tall steep ramp with height markers |

## Levels

**F11** cycles through the levels: Sandbox, Rooftops, Combo Park.

**Rooftops** is a timed obstacle course across six rooftops. The clock starts at the green line and stops at the yellow finish. Hurdles and a slide bar, a gap, a door and a window wall, a wallrun across a 12 m gap, a 3 m climb, a dive window, a 9 m drop to roll out of, a sideways ramp and an optional loop, more hurdles and a last gap. Falling to the street puts you back at the last checkpoint and the clock keeps running. Your best time is saved. Keys 1–4 jump to the start and each checkpoint (from a checkpoint it's practice and doesn't set a best time).

**Combo Park** is an open yard with no set route, built for keeping a combo alive: a two-tier tower in the middle (mantle steps, a climb face, slide ramps down three sides, kick-off pillars), a half-pipe, a loop at the end of a long runway, a wallrun zigzag over a red floor, a hurdle field with slide bars, a door and window wall, sideways ramps along the west side (one gentle, one steep), blue fins and mantle blocks in between, long walls down both sides, and targets throughout. Keys 1–6 jump between areas.

Color language: gray is plain, blue is wallrun, yellow is vault/mantle/climb, green is slide, purple is runnable ramps and loops, and red is targets (yellow heads are headshots).

## Tuning

Player settings (sensitivity, FOV, controls) live in the Esc menu and save to `user://settings.cfg`.

Press **F2** in game for live sliders on every movement number. **Save** writes your tuning to your user folder and loads it next time. In the editor, **Save as project defaults** writes it to `player/default_tuning.tres` so everyone gets it.

Tuning saved before playtest 2 is ignored (the movement defaults changed a lot), so you start from the new feel.

F3 toggles slow motion and F4 shows a speed-colored trail, which help when judging a move.

## Tests

Movement and shooting are covered by headless tests that drive a real player with scripted input:

```
godot --headless --path . --import
godot --headless --path . --fixed-fps 60 -s res://tests/run_tests.gd
```

Add `-- <name>` to run only tests whose name contains `<name>`. GitHub Actions runs the same tests on every push (`.github/workflows/tests.yml`).

## Layout

| Folder | Contents |
|---|---|
| `player/` | Player controller (`player.gd`), tuning resource, input frame, movement math, third-person body rig |
| `weapons/` | Test pistol, weapon stats, procedural sounds |
| `targets/` | Shooting targets |
| `levels/` | Sandbox scene, level builder (the layout is built in code), ramp and loop shapes, doors, windows, kick dummies |
| `scoring/` | Combo tracker (Skate-style combos, score, combo damage) |
| `ui/` | Debug HUD, combo HUD, corner third-person view, pause menu (moves list, settings, controls), tuning panel, hit marker, speed graph |
| `autoload/` | Default input bindings, player settings and custom bindings |
| `fx/` | Speed trail |
| `tests/` | Test runner and suites |
| `tools/` | Screenshot tool |
| `maps/` | Rooftops course (with its timer), Combo Park, F11 level switcher |
| `art/` | Art look: runner character and its animation, cel shader, outlines, speed trails. See [docs/art-pipeline.md](docs/art-pipeline.md) |

## Art look

The sandbox runs with the cel-shaded look on: toon shading, ink outlines, and speed lines at the screen edges when you're fast. **F9** switches between the art look and plain graybox. **F10** switches to a full-screen third-person chase camera (the F5 corner view shows the same runner) (motion trails stream from the hands and feet above run speed). How the art, animation and maps are made is in [docs/art-pipeline.md](docs/art-pipeline.md).
