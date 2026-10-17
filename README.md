# Trickshot

A fast first-person parkour shooter. Moving with style scores points (Skate-style combos), and shooting well while doing it is the point of the game.

This repo is currently the **movement sandbox**: a graybox level for building and tuning the movement and a test pistol before any real levels or scoring.

## Running it

1. Install **Godot 4.7.1 (standard, not .NET)** from https://godotengine.org/download.
2. Open Godot, choose **Import**, and select `project.godot` in this folder.
3. Press **F5** (or the play button). You spawn on the run track.

Mouse/keyboard and controller both work (any XInput pad, including a wired or wireless Xbox 360 controller; the Settings tab lists the controllers it sees). Press **Esc** (or Start) for the menu: a list of every move and how to do it, settings (mouse and aim-down-sights sensitivity, controller look speed, field of view, aim help, invert, third-person camera following flips, volume, music and sound-effect levels), and custom controls.

## Controls

| Action | Keyboard / mouse | Controller |
|---|---|---|
| Move | WASD | Left stick |
| Look | Mouse | Right stick |
| Jump / vault / climb | Space | A |
| Crouch / slide / roll (double-tap to roll) | Ctrl or C | B |
| Kick | F | R3 |
| Mouse lean and roll (test): hold Shift and move the mouse left/right. Running, you lean into the turn (faster turn = more lean = harder turn, speed kept); in the air or on a wall you roll instead of turn | Shift + mouse | |
| Lean / quick turn (side flip in the air, steer a wallrun) | Q / E | LB / RB |
| Fire | Left mouse | Right trigger |
| Aim down sights | Right mouse | Left trigger |
| Reload | R | X |
| Semi / full auto | B or V | D-pad left |
| Respawn | Backspace | Back |
| Menu (maps, moves, settings, controls) | Esc | Start |
| Jump to zone | 1–9, 0 = shooting range, - = ramps and loop | |
| Slow motion (40% for 3 s, then a 6 s cooldown) | Click the mouse wheel | D-pad down |
| HUD / tuning / speed trail | F1 / F2 / F4 | |
| Art look / third-person camera / next level | F9 / F10 / F11 | |
| Zoom the third-person camera (in past the closest goes to first person) | Mouse wheel | |

You always sprint: there's no walk or sprint key. Let go of the stick to stop.

Click the mouse wheel and time eases down to 40% for 3 seconds, then eases back; click again to end it early. It then needs 6 seconds to recharge (the readout under the score counts down). The screen edges darken while time is slowed. The game still runs the same 1/60 s steps, just less often, so a move in slow motion plays out exactly as it would at full speed.

Play in first person, or press F10 (or scroll the wheel out) for third person.

## How the moves work

Every move is simple to do. Doing it *precisely* gets you more out of it: more speed, a longer wallrun, a higher climb. The HUD grades each move OK / GOOD / PERFECT so you can feel the difference.

| Move | How | What precision gets you |
|---|---|---|
| Run | Move in any direction (always a sprint) | Keeping your speed up builds momentum, which raises your running speed (7.5 to 11.5 m/s). There is no top speed: speed you earn on top of that (clean vaults, perfect hops, wall jumps, rolls, slopes) carries while you keep running forward, bleeding slowly, so chaining clean moves keeps stacking it. Let go of forward and you stop as usual |
| Hop / bunny hop | Jump as you land | Jumping within ~2 frames of landing keeps all your speed and adds a little, with no cap, so perfect chains keep getting faster; early jumps bleed it |
| Hurdle / vault | Press jump at a waist-high (yellow) wall, on the ground or in the air. Never automatic: you can always just jump over | A vault never slows you: you cross at your running speed. Taking off at the right distance gives a cleaner vault that adds speed and momentum |
| Mantle | Jump into a ledge up to ~1.5 m above your reach | You keep moving forward as you pull up, and come out at your running speed. A clean grab adds a little, even at the top of a wall climb; a sloppy one loses a little |
| Slide | Crouch while sprinting | Faster entry slides further; slopes add speed |
| Slide landing | Press crouch just before you land from a fall | Turns some of your fall into forward speed |
| Wallrun | Jump into a blue wall at an angle, holding a direction | You keep the angle you hit the wall at, and gravity keeps bending your path down: nothing holds you up. Shallow angle + speed = a longer run. Lean (Q or E) to roll your path round on the wall like a roll: toward the wall turns it up, away turns it down. Running up the wall costs speed. Look and aim anywhere while running; crouch drops off |
| Wall hop | Jump during a wallrun or next to a wall in the air | Kicks you off the wall; the steeper you're running up it, the harder. Chain wall to wall |
| Wall climb | Jump at a wall head-on | Straighter and faster = higher. Jump mid-climb to kick back off it (your view stays put; hold Q or E while turning to face away quickly) |
| Ramp run / loop | Run onto a purple ramp or loop | Gravity slows you going up and speeds you coming down. Fast enough and you run up steep ramps and upside down round loops; too slow and you drop off. Steer with the stick to run off the side. Whenever you leave a ramp or loop you fly off like a real body: you keep your angle and keep turning the way it was turning you (move the view to take over), so off a loop you can come round and land it like a flip. Land on a ramp mid-flip and you crash into it. Launch off the lip of a ramp for air tricks |
| Sideways ramp | Run onto a purple bank at an angle, or across any steep ramp | Run along it tilted like a wallrun; steer with the stick or look up the slope to climb it, let go to drift down |
| Roll | On the ground, flick the view down past your feet | A forward roll, like a flip on the ground. Keeps your speed |
| Ground roll | Double-tap crouch while running | A quick forward roll that keeps your speed |
| Landing roll | Hold crouch in the air (from any angle, even mid-flip), or land tucked forward | You curl into a ball and roll out of big drops without losing speed instead of a stun |
| Kick | F. In the air: kick off walls and targets | Kicking with speed pushes you further and keeps your speed along the wall. Kicks doors open and breaks windows |
| Lean / quick turn | Hold Q or E | Leans you to peek. While held, turning the view toward that side (Q left, E right) is faster and your run follows it without losing speed (in the air, part of your speed follows) |
| Side flip | Hold Q or E in the air | Rolls you sideways one way (the first one you press). Holding it, or crouch, tucks you in and spins you faster; let go to open up and slow down. Near level it settles; land on your side and you shoulder-roll, keeping your speed (the further off level, the more it costs). A lean you were holding on a wallrun doesn't flip you as you come off: let go and lean again |
| Window smash | Run or slide into glass fast enough | Low windows are too low to run through: slide under them |
| Backflip / front flip | In the air, keep moving the view up and over (backflip) or down and over (front flip) until it comes back around | Past straight up/down the view turns faster, so commit to the flick. Flick hard past halfway and let go: momentum carries you round to level. Hold crouch to keep spinning. The HUD shows your flip progress. Land level or you crash |
| 360 / 720 | In the air, turn a full circle | Momentum carries a fast spin round the same way as flips. Quick turn (Q/E) speeds the turn up |

You never have to stand still, but you can: let go of the stick and you stop quickly.

## Shooting

The test pistol is hitscan. The first shot after the gun settles always goes exactly where the crosshair is, even mid-flip at full sprint. Spamming blooms the spread, and controlled fire stays accurate.

- Body 28 damage, headshot ×2.5 (70). Targets have 100 health: two headshots or four body shots. Target heads are 36 cm across.
- Damage falls off from 30 m to 70 m, down to 60%.
- Semi-auto is capped at 7 shots/s. Full-auto fires 11 shots/s. Magazine 15, reload 1.25 s.
- Recoil kicks the view and settles back. It is visual only, so it never breaks a flip.
- Aiming down sights zooms in and slows the look speed to match.
- Target health refills after 2.5 s without a hit, so kills reward landing shots quickly.
- Hits are tagged with what you were doing (airborne, wallrun, mid-flip, upside down, sliding, fast). These tags feed into scoring later.
- Aim help (Settings, 0 = off, default 50%): a shot that just misses bends onto the nearest head or body in clear view (up to 2.5° at full), and a hit just under a head moves up to it (1.2°). On a controller, look slows down while the crosshair is near a target. Targets join it by putting their hitboxes in the `hitboxes` group.

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

## Enemies

The sandbox has an **enemy arena** right behind the start of zone 1: press 1, turn around and run in. The fight starts when you step inside, resets if you leave for a few seconds or go down, and restarts a few seconds after you clear it.

- **Raiders** (the Static) keep their distance and duck behind low walls, then stand up to shoot. Every shot is telegraphed: a red laser tracks you while they aim, then it turns white and stops tracking (with a beep) just before the shot. Their bullets are bright slugs you can see, so moving sideways after the lock dodges them. Standing still, or running straight at a raider, gets you hit. At most two raiders aim at you at once. They back off if you get close.
- **Mutants** (Hollows) guard their patch: they rush you when you come near, hop low walls, and leap when they're a few meters away. The leap is telegraphed (they crouch, glow and growl) and aimed at where you are, so a sidestep or a jump makes it miss, and they're winded for a moment after landing. Up close they wind up a swipe you can back out of. They give up a chase that runs long and walk back.
- **Hitting them:** yellow heads are headshots (2.5x damage). Two headshots or four body shots drop a raider; a mutant takes two headshots or five body shots. With a combo going, a single headshot can kill. A headshot that doesn't kill makes them flinch and cancels their attack, and a **kick** knocks them back and cancels it too. Every kill finishes your combo, like a target kill.
- **Your health:** a few hits take you down. A red flash and an arrow show where a hit came from, and a health bar appears bottom left while you're hurt. Health comes back after a few seconds without damage. Going down puts you back at the arena entrance and loses the combo.

All enemy logic ticks in physics from game state and a seeded random number generator, so the same input always plays out the same fight. Their numbers are exported on `enemies/raider.gd` and `enemies/mutant.gd`.

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
| 9 | Doors and windows | Door kicks, slide-under windows and window smashes |
| 0 | Shooting range | Static and moving targets, a wall to wallrun-and-shoot from, a platform for air shots |
| (behind 1) | Enemy arena | Raiders behind low walls and mutants guarding the back; see Enemies above |
| - | Ramps and loop | A loop after a long run-up, a launch ramp, a tall steep ramp with height markers, a sideways ramp |

## Levels

Pick a level in the **Esc** menu, or press **F11** to cycle through them: Sandbox, Rooftops, Combo Park, Ruined Mall, Campaign.

**Rooftops** is a timed obstacle course across the city's roofs, about 950 m, with two wide corners. The first leg runs straight: hurdles and a slide bar, a gap, a door and a window wall, a wallrun across a 12 m gap, a 3 m climb, a low window to slide through, a 9 m drop to roll out of, a sideways ramp and an optional loop, a long sprint, an AC field and a second climb, then a window wall and the first corner (turn left; a banked curve round the outside lets you carve it at speed). The second leg splits: the high line goes up a fallen slab onto a narrow roof with a wallrun gap, the low line drops to the roofs below for a pipe, vaults and a climb back up. They meet at the second corner (turn right, banked too). The last leg steps up three roofs by mantling, forks over a wide gap (wallrun on the left or a girder on the right), slides down to a wide roof with an optional loop, and jumps a last gap to the finish. Falling to the street puts you back at the last checkpoint and the clock keeps running. Your best time is saved. Keys 1–0 jump to the start and each checkpoint (from a checkpoint it's practice and doesn't set a best time).

**Combo Park** is an open yard with no set route, built for keeping a combo alive: a two-tier tower in the middle (mantle steps, a climb face, slide ramps down three sides, kick-off pillars), a half-pipe, a loop at the end of a long runway, a wallrun zigzag over a red floor, a hurdle field with slide bars, a door and window wall, sideways ramps along the west side (one gentle, one steep), blue fins and mantle blocks in between, long walls down both sides, and targets throughout. North of the yard the park runs on for 550 m: a canal to carve down, a wall alley to cross without touching the ground, rollers to pump, and a broken overpass that curves 45 degrees over pillars, with a gap to jump and a fallen slab to slide down to the exit. Above the east side the high road gives a second way through: a line of low roofs with hurdles, a pipe, a gap, crates, a climb, a wallrun gap and a slide back down. Keys 1–0 jump between areas.

**Ruined Mall** is a two-floor mall gone to ruin, built for flow and later for fights: a skylit atrium with escalators, a bridge and hanging billboards to wallrun, shops with glass you can run or shoot through, a caved-in walkway beside a blue wall, and a food court under a collapsed roof with a debris ramp back up. A catwalk and the food court lead into the north wing: a 250 m concourse under one skylight, with walkways, bridges, escalators and blue hoardings over gaps in the floor. The wing ends at a department store (a well through the sales floor with stopped escalators and a high line up a wallrun wall, and roof access up to its roof) and a loading dock out onto the service road. Keys 1–9 jump between areas.

## Campaign

**Campaign** (Esc menu or F11) opens *Dead Air*: all thirteen missions by act, each with its story beat, what it teaches and your best result. Six are playable so far, and together they run west across the city:

- **0 Dawn Run** (dock rooftops): deliver a parcel, run home, and hear the Host announce he has Echo.
- **1 The Yard** (Combo Park): Mags's last lesson: a x3 combo, three dummies, two headshots, 6,000 points, then out the south gate.
- **2 On Air** (warehouse roofs, 540 m): the Host names you on air; wallruns, wall hops and three of the Static's raiders shooting back from behind sandbags.
- **3 Glass District** (office roofs, 560 m): windows to slide through, a climb to the upper offices, toll spotters to take out, on to the Silt bridge.
- **4 Silt Line** (the Silt, 530 m): the bridge is gone; run through the crawlers without stopping, climb onto the overpass and run it to Meridian Mall.
- **12 Signal Out** (the burning tower): you play Echo and the Host chases you. He follows your exact path, never drops more than about 22 m behind, and catches you if you slow down; Parker coaches you on the radio. Beating it unlocks Echo as a runner for every mission.

Mags, the Host, Echo and Parker talk over the radio (subtitles low in the middle) while you run; nothing stops the game. The clock starts when you leave the start, the objective shows under it, falling sends you to the last checkpoint, and lost broadcast tapes hide on the harder routes. Number keys jump to checkpoints as practice runs. Missions are data files; how to write one is in [docs/missions.md](docs/missions.md).

Color language: gray is plain, blue is wallrun, yellow is vault/mantle/climb, green is slide, purple is runnable ramps and loops, and red is targets (yellow heads are headshots).

## Tuning

Player settings (sensitivity, FOV, controls) live in the Esc menu and save to `user://settings.cfg`.

Press **F2** in game for live sliders on every movement number. **Save** writes your tuning to your user folder and loads it next time. In the editor, **Save as project defaults** writes it to `player/default_tuning.tres` so everyone gets it.

Tuning saved before playtest 2 is ignored (the movement defaults changed a lot), so you start from the new feel.

F3 toggles slow motion with no time limit or cooldown, and F4 shows a speed-colored trail, which help when judging a move.

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
| `enemies/` | Raiders, mutants, their bullets, player health and hurt overlay, encounters, the sandbox arena |
| `levels/` | Sandbox scene, level builder (the layout is built in code), ramp and loop shapes, doors, windows, kick dummies |
| `scoring/` | Combo tracker (Skate-style combos, score, combo damage) |
| `ui/` | Debug HUD, combo HUD, pause menu (moves list, settings, controls), tuning panel, hit marker, speed graph |
| `autoload/` | Default input bindings, player settings and custom bindings |
| `fx/` | Speed trail |
| `tests/` | Test runner and suites |
| `tools/` | Screenshot tool |
| `maps/` | Rooftops course (with its timer), Combo Park, Ruined Mall, F11 level switcher |
| `campaign/` | Campaign list, mission scene, mission data files (`missions/*.json`), mission rules, radio, chase, mission HUD, campaign menu. See [docs/missions.md](docs/missions.md) |
| `art/props/` | Prop kit: crates, wrecks, barricades, containers, loudspeakers and more, built by `art/source/build_props.py` |
| `art/` | Art look: runner character and its animation, cel shader, outlines, speed trails. See [docs/art-pipeline.md](docs/art-pipeline.md) |
| `audio/` | Music and movement/world sounds (the `GameAudio` autoload), all synthesised in code. See [audio/SOURCES.md](audio/SOURCES.md) |

## Sound

Everything you hear is synthesised in code, so there are no audio files to license. The `GameAudio` autoload only listens to the player and the combo; it never changes the run.

- **Footsteps** speed up with your pace and change with the ground: concrete, gritty asphalt (map floors) and ringing metal (wallrun panels, slide strips, ramps and loops). They follow you up walls on a wallrun or climb.
- **Moves:** jumps and wall jumps, landings graded by how hard you hit (rolling it out softens them, big drops kick up debris), slide scrape, rolls, vault and mantle hand plants, flips and spins, kicks, wall bonks. Wind rises with speed, with a hiss near top speed.
- **World:** glass shattering and doors slamming, however they break or open.
- **Music:** an 8-bar wasteland loop. With no combo it plays "on air" through the warlord's radio, filtered with a crackle under it. A combo opens it to full sound with drums and bass; 3 tricks add percussion, 5 add the lead. Combo milestones (3, 5, 8 tricks) get a radio jingle, banking rings out and a bail stings.
- **Slow-mo** muffles and deepens everything while it's on.

The first launch builds the sounds in the background (the music fades in a few seconds later) and caches them in `user://audio_cache.bin`; later launches load the cache. To audition every sound as WAV files:

```
godot --headless --path . -s res://audio/tools/export_sounds.gd -- <out_dir>
```

## Art look

The sandbox runs with the cel-shaded look on: toon shading, ink outlines, and speed lines at the screen edges when you're fast. **F9** switches between the art look and plain graybox. **F10** (or scrolling out of first person) switches to a full-screen third-person camera that tilts with your view and zooms with the wheel (motion trails stream from the hands and feet above run speed). The world is a dusty post-apocalyptic city: procedural concrete, rust, cracked asphalt and chipped paint, all in world space with no texture files. Obstacles are dressed as part of it: vaults are concrete barriers, brick walls, sandbags, rails or crate stacks, slide bars are pipes and girders, wallrun walls are sheet-metal hoardings, billboards and containers, slide ramps are bent sheet metal and escalators have steps. It's visual only (what you hit is the same box), and F9's graybox still shows the color code. The sidearm is a taped-up scrap pistol with a rusty compensator, in first person and in the runner's hand; shots have a cel muzzle flash, slide blowback, casings, tracers, sparks, dust and bullet holes, and layered procedural gunshot audio. How the art, animation and maps are made is in [docs/art-pipeline.md](docs/art-pipeline.md).
