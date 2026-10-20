# Enemies

Every enemy is a script in `enemies/` named after its type, extends
`enemies/enemy.gd`, and uses the same hit-zone contract as targets (layer 4,
metas `zone` and `target`, group `hitboxes`), so the pistol and the combo
scoring need nothing new. Behaviour ticks in physics from game state and a
seeded RNG (deterministic); the models only read the state.

Only the final level is a chase. Every other enemy guards its patch.

## Hit zones

Each humanoid has body-shaped hit zones (`enemies/hit_rig.gd`): a head,
chest, hips, and upper and lower arms and legs, sized from its model, so a
shot past the shoulder or between the legs misses. They follow the pose the
state calls for in the physics tick (ducking, the Hollows' hunch, running,
hands on the gun where it aims, flinching, lying flat after a kick), so they
stay deterministic. The drawn model eases between poses, so the two can be
a few centimeters apart mid-move. The head is the `head` zone, the rest is
`body`. Drones keep their box. To see them, render with `hitboxes` (below).

## Kicks

A kick (on the ground, or kicking off an enemy in the air) deals
`kick_damage` (35) times the same combo multiplier shots get, and knocks
the enemy flat on its back for `knockdown_time` (1.5 s, Juno 1 s) before it
gets up. Heavies and brutes are too heavy: they only stagger. A kick that
finishes an enemy is a "KICK KILL" trick. The kick reaches an enemy a
little off your look ray.

## Difficulty

`enemies/difficulty.gd` scales every type's numbers when it joins a fight:
25% faster on their feet, windups and pauses 28% shorter, the locked dodge
window 20% shorter, aim that tracks 60% faster and leads a runner, faster
bullets, 20% more damage. `Difficulty.level` (1 = this, 0 = the old
numbers) scales all of it. Up to three gunners aim at once. Gunners lead a
runner fully: at the lock they aim where you'll be if you hold your line,
so changing line after the lock is what dodges. Hits do double damage (a
raider kills in three). A raider moving to cover stops to take a ready
shot rather than letting you run past.

## Combo armor

Every gunshot rolls against your exposure when it's fired
(`enemies/combo_armor.gd`): 1.5 at a walk, 0.7 at top speed, 0.4 at 15 m/s
and up, x0.6 while sliding, wallrunning or part way round a flip or spin,
x0.85 with a 2x+ combo. Hit chance = exposure squared (capped at 1): a
standing target is always hit, a plain line at top speed about half the
time, a fast line full of tricks about 1 in 10. A miss cracks past 0.9-1.6 m
away, never along the way you're running. A faint pulsing red edge shows
while someone is aiming at you and you're easy to hit.

## Respawning

Mission encounters set `keep_dead`: whoever you kill stays dead when you
go down or leave the area; only the survivors go back to their spots, and
a cleared area stays cleared. A fresh run of the mission brings everyone
back. The sandbox arena still restarts so you can practice.

## Factions

The Static (with their camera and spotter drones) and the Ward (with their
gun drones) never share an encounter. The Hollows can turn up with either.
`tests/test_campaign.gd` checks every mission.

## Types

Every normal enemy dies to one headshot, whatever the damage, range, combo
or armor (`Enemy.one_shot_headshot`). Juno and the Host turn it off.

| type | faction | what it does | how you beat it |
|---|---|---|---|
| `raider` | Static | rifle, cover, red laser that turns white and beeps before the shot | move after the lock; headshot when it pops up |
| `hunter` | Static | runs like you, keeps moving to your side, hops low walls, quick shots | keep turning; catch it when it stops to shoot |
| `bruiser` | Static | big raider behind a scrap shield, walks you down, scattergun fan up close | get round it, headshot over the top, or kick the shield |
| `juno` | Static | boss: a better hunter, faster once hurt, can't be killed outright (see below). Her own look: long bone-white coat, red visor and scarf, platinum ponytail, her name over her head | |
| `mutant` / `crawler` | Hollows | rushes, leaps (crouch-and-glow windup), swipes; winded after landing | sidestep the leap, headshot while winded |
| `leaper` | Hollows | small and quick, leaps far and often, short winded window | watch the ledges, quick headshots |
| `brute` | Hollows | huge, bone-armored front (shots barely hurt), soft back (extra damage); roars, then charges in a locked straight line | sidestep after the line locks; it's dazed if it hits a wall; shoot its back |
| `trooper` | Ward | like a raider but 3-round bursts, leads shots, body armor; squads spread around you | keep moving; one headshot (the helmet flies off) |
| `shield` | Ward | riot shield blocks shots from the front, walks you down, one-handed carbine | over it, around it (turns slowly), headshot over the top, kick it aside |
| `marksman` | Ward | scoped rifle from up to 55 m, one heavy shot, quick laser aim | break line of sight, move on the lock |
| `heavy` | Ward | heavy armor (body shots barely hurt), LMG bursts of 6, walks at you, kicks barely move it | one headshot |
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
- Juno with `phases` (4-2 Parking Spiral): a fight in stages. Her guard
  shrugs off ordinary hits and breaks only to a kick ending a combo of 3+
  tricks or a headshot while you're in the air or on a wall;
  `breaks_per_phase` (2) breaks end a phase (story event `juno:phase`, so
  `juno:phase:1`...), and she runs on to the next phase's `spot`. Reach a
  phase's `until` point and she goes on ahead unbroken. The last phase's
  breaks beat her. Under base top speed (`SLOW_SPEED`, 12 m/s) for 0.4 s
  within 18 m of her and she runs you down and kicks (`strike_damage`); she
  hops holes and isn't bowled over by running into her.

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
xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --fixed-fps 60 -s res://enemies/tools/enemy_shots.gd -- <out_dir> [hitboxes] [lineup]
```

`hitboxes` draws the hit zones over the models; a lineup name (`juno`,
`raider`...) renders just that one.

The sandbox's enemy arena alternates two waves when you clear it: the
Host's crew, then troopers, a shield bearer and gun drones.
