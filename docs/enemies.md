# Enemies

Every enemy is a script in `enemies/` named after its type, extends
`enemies/enemy.gd`, and uses the same hit-zone contract as targets (layer 4,
metas `zone` and `target`, group `hitboxes`), so the pistol and the combo
scoring need nothing new. Behaviour ticks in physics from game state and a
seeded RNG (deterministic); the models only read the state.

Only the final level is a chase. Every other enemy guards its patch.

## Types

| type | faction | what it does | how you beat it |
|---|---|---|---|
| `raider` | Static | rifle, cover, red laser that turns white and beeps before the shot | move after the lock; headshot when it pops up |
| `hunter` | Static | runs like you, keeps moving to your side, hops low walls, quick shots | keep turning; catch it when it stops to shoot |
| `bruiser` | Static | big raider behind a scrap shield, walks you down, scattergun fan up close | get round it, headshot over the top, or kick the shield |
| `juno` | Static | boss: a better hunter, faster once hurt, can't be killed outright (see below) | |
| `mutant` / `crawler` | Hollows | rushes, leaps (crouch-and-glow windup), swipes; winded after landing | sidestep the leap, headshot while winded |
| `leaper` | Hollows | small and quick, leaps far and often, short winded window | watch the ledges, quick headshots |
| `brute` | Hollows | huge, bone-armored front (shots barely hurt), soft back (extra damage); roars, then charges in a locked straight line | sidestep after the line locks; it's dazed if it hits a wall; shoot its back |
| `trooper` | Ward | like a raider but 3-round bursts, leads shots, body armor; the helmet stops the first headshot; squads spread around you | keep moving; two headshots |
| `shield` | Ward | riot shield blocks shots from the front, walks you down, one-handed carbine | over it, around it (turns slowly), headshot over the top, kick it aside |
| `marksman` | Ward | scoped rifle from up to 55 m, one heavy shot, quick laser aim | break line of sight, move on the lock |
| `heavy` | Ward | heavy armor (body shots barely hurt), LMG bursts of 6, walks at you, kicks barely move it | headshots (full damage) |
| `drone` / `gun_drone` | Ward | quadcopter, circles you at range, telegraphed 3-shot bursts; one hit drops it | air and wallrun shots |
| `camera_drone` | Static | the Host's broadcast camera: harmless, circles close with REC on; emits `feed_cut` when shot down | free trick shot |
| `spotter_drone` | Static | hangs high and paints you with a green beam; while it sees you, its encounter's gunners keep aiming at you behind cover and lock on faster | shoot it first |

## Placing them

Encounters (`enemies/enemy_encounter.gd`) start when you step into their
`bounds` and reset if you leave or go down.

- `EnemyEncounter.add_from_spec(type, spec, transform)` loads
  `enemies/<type>.gd` by path (plural list names like `"drones"` work too),
  sets `wake` (delay in seconds), and sets any other spec key that names one
  of the enemy's settings (`hover_height`, `leash_radius`,
  `preferred_range`, `sleeper`...). Unknown types return null.
- Raiders, troopers, marksmen and hunters use the encounter's cover rows
  (`add_cover_wall`); shields, bruisers and heavies need none.
- Drones hover `hover_height` (4 m) above their spot and stay within
  `leash_radius` (16 m) of it: make the encounter area tall enough.
- Shots draw more Hollows: set the encounter's `hear_shots`, and give
  enemies `"sleeper": true`. Sleepers stay put when the fight starts and
  wake when you fire within `hearing_radius` (30 m) of them or come within
  `wake_distance` (5 m); the encounter emits `drew_enemies(count)`. A
  sleeper nobody woke doesn't hold up the clear.
- Juno: when her health runs out she's beaten (signal `beaten`) and kneels.
  Shoot her again and `fate` is `"not_spared"` (she dies, a kill); leave her
  for `spare_time` (8 s) or walk `spare_distance` (25 m) away and `fate` is
  `"spared"` (she leaves and the encounter clears). `fate_decided(fate)`
  fires once either way.

## Models

`enemies/source/build_enemies.py` (Blender 4.2+ or `pip install bpy`) builds
every model into `enemies/models/*.glb` from primitives and skin modifiers:
our own work, no imported assets. Humanoids share the runner's bone names
and pose convention; `enemies/enemy_body.gd` poses them from the state each
frame (key poses blended, feet kept on the ground, two-bone IK puts the hands
on the gun, which the state places so it points exactly where the enemy
aims). Several types share a model and show or hide parts (`Shield`,
`ScrapShield`, `LongRifle`, `Helmet`, `Armor`) or tint it. If a model can't
load, the enemy falls back to its placeholder boxes.

Review renders:

```
xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --fixed-fps 60 -s res://enemies/tools/enemy_shots.gd -- <out_dir>
```

The sandbox's enemy arena alternates two waves when you clear it: the
Host's crew, then troopers, a shield bearer and gun drones.
