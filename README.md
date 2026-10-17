# Trickshot

A fast first-person parkour shooter. Moving with style scores points (Skate-style combos), and shooting well while doing it is the point of the game.

This repo is currently the **movement sandbox**: a graybox level for building and tuning the movement and a test pistol before any real levels or scoring.

## Running it

1. Install **Godot 4.7.1 (standard, not .NET)** from https://godotengine.org/download.
2. Open Godot, choose **Import**, and select `project.godot` in this folder.
3. Press **F5** (or the play button). You spawn on the run track.

Mouse/keyboard and controller both work. Press **Esc** (or Start) for the menu: a list of every move and how to do it, settings (mouse and aim-down-sights sensitivity, controller look speed, field of view, invert, volume), and custom controls.

## Controls

| Action | Keyboard / mouse | Controller |
|---|---|---|
| Move | WASD | Left stick |
| Look | Mouse | Right stick |
| Sprint (hold, any direction) | Shift | L3 |
| Jump / vault / climb | Space | A |
| Crouch / slide / roll | Ctrl or C | B |
| Prone (hold) / dolphin dive | Z | D-pad down |
| Kick | F | RB or R3 |
| Quick turn (180) | Q | LB |
| Fire | Left mouse | Right trigger |
| Aim down sights | Right mouse | Left trigger |
| Reload | R | X |
| Semi / full auto | B or V | Y |
| Respawn | Backspace | Back |
| Menu (moves, settings, controls) | Esc | Start |
| Jump to zone | 1–9, 0 = shooting range | |
| HUD / tuning / slow-mo / speed trail | F1 / F2 / F3 / F4 | |

## How the moves work

Every move is simple to do. Doing it *precisely* gets you more out of it: more speed, a longer wallrun, a higher climb. The HUD grades each move OK / GOOD / PERFECT so you can feel the difference.

| Move | How | What precision gets you |
|---|---|---|
| Sprint | Hold Shift while moving, in any direction | Holding speed builds momentum, which raises your top speed (6 to 9.5 m/s) |
| Hop / bunny hop | Jump as you land | Jumping within ~2 frames of landing keeps all your speed; early jumps bleed it |
| Hurdle / vault | Jump at a waist-high (yellow) wall | Taking off at the right distance gives a faster, cleaner vault |
| Mantle | Jump into a ledge up to ~1.5 m above your reach | Grabbing it cleanly keeps more speed |
| Slide | Crouch while sprinting | Faster entry slides further; slopes add speed |
| Slide landing | Hold crouch as you land from a fall | Turns some of your fall into forward speed |
| Prone | Hold Z (or hold crouch while standing still). Let go to get up | |
| Dolphin dive | Z while running fast | Tap to dive and pop up into a slide, hold to stay down. Dive through low windows |
| Wallrun | Jump into a blue wall at an angle, holding a direction | Shallow angle + speed = longer, floatier run. Look and aim anywhere while running; crouch drops off |
| Wall hop | Jump during a wallrun or next to a wall in the air | Kicks you off the wall; chain wall to wall |
| Wall climb | Jump at a wall head-on | Straighter and faster = higher. Jump mid-climb to kick back off it |
| Landing roll | Crouch just before a hard landing | Good timing keeps speed instead of a stun |
| Kick | F. In the air: kick off walls and targets | Kicking with speed pushes you further. Kicks doors open and breaks windows |
| Quick turn | Q | Spins you 180. On a wall it faces you away from it, ready to jump |
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

Scoring works like Skate. Every move and every stylish hit adds points to a running combo shown at the bottom of the screen.

- **Multiplier:** +1 for each different trick in the combo. Repeating a trick is worth 60% of the last time.
- **Speed and precision:** points scale from 1x at run pace to 2x at top speed, and from 0.75x (OK) to 1.25x (PERFECT).
- **Banking:** the combo's points times its multiplier go to your score when you come to rest or go 2 s without a new trick. Sliding, wallrunning, climbing and vaulting hold the clock.
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

Color language: gray is plain, blue is wallrun, yellow is vault/mantle/climb, green is slide, and red is targets (yellow heads are headshots).

## Tuning

Player settings (sensitivity, FOV, controls) live in the Esc menu and save to `user://settings.cfg`.

Press **F2** in game for live sliders on every movement number. **Save** writes your tuning to your user folder and loads it next time. In the editor, **Save as project defaults** writes it to `player/default_tuning.tres` so everyone gets it.

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
| `player/` | Player controller (`player.gd`), tuning resource, input frame, movement math |
| `weapons/` | Test pistol, weapon stats, procedural sounds |
| `targets/` | Shooting targets |
| `levels/` | Sandbox scene, level builder (the layout is built in code), doors, windows, kick dummies |
| `scoring/` | Combo tracker (Skate-style combos, score, combo damage) |
| `ui/` | Debug HUD, pause menu (moves list, settings, controls), tuning panel, hit marker, speed graph |
| `autoload/` | Default input bindings, player settings and custom bindings |
| `fx/` | Speed trail |
| `tests/` | Test runner and suites |
| `tools/` | Screenshot tool |
| `art/` | Art look: runner character and its animation, cel shader, outlines, speed trails. See [docs/art-pipeline.md](docs/art-pipeline.md) |

## Art look

The sandbox runs with the cel-shaded look on: toon shading, ink outlines, and speed lines at the screen edges when you're fast. **F6** switches between the art look and plain graybox. **F7** switches to a third-person chase camera so you can watch the runner animate (motion trails stream from the hands and feet above run speed). How the art, animation and maps are made is in [docs/art-pipeline.md](docs/art-pipeline.md).
