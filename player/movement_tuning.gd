class_name MovementTuning
extends Resource
## Every number that shapes how movement feels lives here, so it can be tuned
## live from the in-game tuning panel (F2) without touching code.
## Units: meters, seconds, meters per second.

@export_group("Run")
## You always sprint. Ground speed with zero momentum.
@export_range(1.0, 20.0, 0.1) var run_speed := 7.5
## Ground speed cap at full momentum.
@export_range(1.0, 30.0, 0.1) var top_speed := 11.5
## Source-style ground acceleration factor.
@export_range(0.0, 30.0, 0.1) var ground_accel := 9.0
@export_range(0.0, 20.0, 0.1) var ground_friction := 6.0
## Below this speed friction acts as if moving at this speed (snappy stops).
@export_range(0.0, 10.0, 0.1) var stop_speed := 2.5

@export_group("Momentum")
## Momentum gained per second while flowing at speed.
@export_range(0.0, 2.0, 0.01) var momentum_gain := 0.35
## Momentum lost per second while slow.
@export_range(0.0, 5.0, 0.01) var momentum_decay := 0.9
## Instant momentum bump from each parkour move.
@export_range(0.0, 1.0, 0.01) var momentum_trick_bump := 0.08
## Fraction of momentum and speed lost when hitting a wall head-on.
@export_range(0.0, 1.0, 0.01) var wall_impact_loss := 0.5
## Speed into a wall that counts as a head-on impact.
@export_range(0.0, 20.0, 0.1) var wall_impact_speed := 6.0

@export_group("Air")
@export_range(0.0, 60.0, 0.1) var gravity := 19.0
@export_range(0.0, 20.0, 0.1) var jump_velocity := 7.8
## Quake-style air acceleration. Higher = stronger air strafing.
@export_range(0.0, 100.0, 0.5) var air_accel := 12.0
## Cap on wish speed in the air. Small values = light control + strafe gains.
@export_range(0.0, 10.0, 0.05) var air_wish_speed := 0.6
@export_range(0.0, 0.5, 0.01) var coyote_time := 0.12
@export_range(0.0, 0.5, 0.01) var jump_buffer := 0.12
@export_range(10.0, 100.0, 1.0) var max_fall_speed := 45.0

@export_group("Crouch and slide")
@export_range(0.5, 2.0, 0.05) var stand_height := 1.8
@export_range(0.5, 2.0, 0.05) var crouch_height := 1.0
@export_range(0.5, 10.0, 0.1) var crouch_speed := 3.5
## Minimum speed to start a slide.
@export_range(0.0, 15.0, 0.1) var slide_min_speed := 5.5
## Slide ends below this speed.
@export_range(0.0, 10.0, 0.1) var slide_exit_speed := 3.0
## One-off speed boost when a slide starts (needs the cooldown to be ready).
@export_range(0.0, 10.0, 0.1) var slide_boost := 1.2
@export_range(0.0, 5.0, 0.05) var slide_boost_cooldown := 1.2
@export_range(0.0, 10.0, 0.05) var slide_friction := 0.3
## How strongly slopes speed a slide up (multiplies gravity along the slope).
@export_range(0.0, 3.0, 0.05) var slide_slope_gain := 1.2
## Friction grows by this much per second of sliding, so flat slides end.
@export_range(0.0, 10.0, 0.05) var slide_friction_ramp := 1.0

@export_group("Vault and mantle")
## Highest obstacle (above feet) you vault over or step onto without jumping.
@export_range(0.2, 2.0, 0.05) var vault_max_height := 1.25
@export_range(0.0, 1.0, 0.05) var vault_min_height := 0.35
## Thickest obstacle that counts as vaultable; thicker ones are mantled onto.
@export_range(0.2, 3.0, 0.05) var vault_max_depth := 1.4
@export_range(0.05, 1.0, 0.01) var vault_time := 0.28
## Speed gained by a clean vault (0.15 = 15%). A sloppy one still keeps
## nearly all of it, so vaulting beats jumping over.
@export_range(0.0, 0.5, 0.01) var vault_speed_bonus := 0.15
## Extra momentum (raising your top speed) from a clean vault or mantle.
@export_range(0.0, 1.0, 0.01) var clean_move_momentum := 0.15
## How far above your feet you can catch a ledge while airborne.
@export_range(0.2, 3.0, 0.05) var mantle_air_reach := 1.55
@export_range(0.05, 1.0, 0.01) var mantle_time := 0.32
## Fraction of horizontal speed kept after a sloppy mantle. A clean one
## (quality at or above mantle_clean_quality) keeps all of it.
@export_range(0.0, 1.0, 0.01) var mantle_speed_keep := 0.55
@export_range(0.05, 1.0, 0.01) var mantle_clean_quality := 0.7
@export_range(0.0, 10.0, 0.1) var mantle_min_exit_speed := 3.5

@export_group("Wallrun")
@export_range(0.0, 15.0, 0.1) var wallrun_min_speed := 5.0
@export_range(0.0, 5.0, 0.05) var wallrun_max_time := 1.6
## Gravity multiplier while wallrunning.
@export_range(0.0, 1.0, 0.01) var wallrun_gravity_scale := 0.15
## Speed the wallrun accelerates toward along the wall.
@export_range(0.0, 20.0, 0.1) var wallrun_speed := 8.5
@export_range(0.0, 30.0, 0.1) var wallrun_accel := 6.0
## Max angle between your movement and the wall (degrees) to start a wallrun.
@export_range(0.0, 90.0, 1.0) var wallrun_max_entry_angle := 60.0

@export_group("Ramps and loops")
## Steep ramps and loops (anything in the "runnable" group) can be run on.
## Gravity along them, as a fraction of normal gravity.
@export_range(0.0, 2.0, 0.01) var surface_gravity_scale := 0.6
## How fast running (holding forward) speeds you up on them, up to top speed.
@export_range(0.0, 30.0, 0.1) var surface_accel := 6.5
## Speed needed to stay on a vertical surface. Below this you drop off.
@export_range(0.0, 20.0, 0.1) var surface_min_speed := 3.0
## Speed needed to stay on upside down (the top of a loop).
@export_range(0.0, 30.0, 0.1) var surface_inverted_speed := 6.0
## How fast you can turn while running on a ramp, loop or bank (degrees/s),
## toward where you look or with the stick.
@export_range(0.0, 360.0, 1.0) var surface_steer := 110.0
## Share of gravity that pulls your path down a slope when you run across
## it (banks). Lower holds your line like a wallrun.
@export_range(0.0, 1.0, 0.01) var surface_cross_gravity := 0.35
## Push into the surface (m/s) that keeps your feet on it.
@export_range(0.0, 10.0, 0.1) var surface_stick := 2.0
## How strongly a track (loop) steers you along itself.
## (Steering with the stick overrides it, so you can run off the side.)
@export_range(0.0, 20.0, 0.1) var surface_flow_assist := 5.0
## Flying off a surface turning slower than this (degrees/s) doesn't carry
## the turn into the air.
@export_range(0.0, 360.0, 1.0) var surface_exit_spin_min := 15.0
## How quickly your body (and view) turns to match the surface. Lower is
## smoother over the seams between track pieces, higher hugs the track.
@export_range(1.0, 60.0, 0.5) var surface_align_rate := 12.0
## Runnable slopes flatter than this (normal y) are just ground.
@export_range(0.5, 1.0, 0.005) var surface_enter_flatness := 0.95
@export_range(0.5, 1.0, 0.005) var surface_exit_flatness := 0.97

@export_group("Wall jump and climb")
@export_range(0.0, 20.0, 0.1) var wall_jump_push := 6.0
@export_range(0.0, 20.0, 0.1) var wall_jump_up := 7.2
## Extra speed added along your movement direction on a wall jump.
@export_range(0.0, 10.0, 0.1) var wall_jump_boost := 1.2
## Grace time after leaving a wall during which a wall jump still works.
@export_range(0.0, 0.5, 0.01) var wall_jump_grace := 0.15
@export_range(0.0, 20.0, 0.1) var wall_climb_speed := 5.5
@export_range(0.0, 2.0, 0.01) var wall_climb_time := 0.6
## How head-on you must face a wall to climb it (dot product, 1 = straight on).
@export_range(0.0, 1.0, 0.01) var wall_climb_facing := 0.7
@export_range(0.0, 20.0, 0.1) var wall_climb_kick_push := 6.5
@export_range(0.0, 20.0, 0.1) var wall_climb_kick_up := 6.0

@export_group("Landing")
## Fall speed above which a landing is hard unless you roll.
@export_range(0.0, 40.0, 0.5) var hard_landing_speed := 13.0
## Press crouch within this many seconds before touching down to roll.
@export_range(0.0, 1.0, 0.01) var roll_window := 0.3
@export_range(0.05, 2.0, 0.01) var roll_time := 0.45
## Speed added along your heading by a clean roll.
@export_range(0.0, 10.0, 0.1) var roll_boost := 1.0
## Fraction of horizontal speed kept after a hard landing.
@export_range(0.0, 1.0, 0.01) var hard_landing_keep := 0.35
@export_range(0.0, 2.0, 0.01) var hard_landing_stun := 0.35
## Two crouch presses this close together (seconds) while running: a roll.
@export_range(0.1, 0.6, 0.01) var double_tap_window := 0.3
## Crouch held this long in the air is a tuck: you land in a roll from any
## angle, as long as the fall is at least tuck_roll_min_fall (m/s).
@export_range(0.0, 1.0, 0.01) var tuck_hold_time := 0.2
@export_range(0.0, 20.0, 0.1) var tuck_roll_min_fall := 4.0

@export_group("Kick-off")
@export_range(0.5, 4.0, 0.05) var kick_range := 1.7
@export_range(0.0, 20.0, 0.1) var kick_push := 7.5
@export_range(0.0, 20.0, 0.1) var kick_up := 6.5
## Fraction of speed along the surface kept through a weak kick-off; a
## strong one (kicking hard into the surface) keeps all of it.
@export_range(0.0, 1.0, 0.01) var kick_keep_tangent := 0.9
@export_range(0, 6, 1) var kicks_per_air_time := 2
@export_range(0.0, 50.0, 0.5) var kick_target_impulse := 14.0

@export_group("Skill")
## Every move works when done roughly, but precise timing, angles and speed
## make it better. Each quality value below is 0..1 (1 = perfect).
##
## Jump pressed within this many seconds of touching down = perfect hop.
@export_range(0.0, 0.2, 0.005) var hop_perfect_window := 0.035
## Horizontal speed kept by a hop pressed at the very start of the buffer.
@export_range(0.5, 1.0, 0.01) var hop_early_keep := 0.9
## Off = steering in the air can turn you but never adds speed (no bhop/surf
## strafe gains). On = Quake-style strafe acceleration.
@export var air_strafe_gain := false
## Crouch pressed within this many seconds of landing turns into a slide.
@export_range(0.0, 0.5, 0.01) var slide_land_window := 0.2
## Fraction of fall speed turned into forward speed by a perfect slide landing.
@export_range(0.0, 1.0, 0.01) var slide_land_conversion := 0.35
## Shortest wallrun (sloppy entry); the best entry gets wallrun_max_time.
@export_range(0.0, 3.0, 0.05) var wallrun_min_time := 0.55
## Gravity scale for a sloppy wallrun; the best gets wallrun_gravity_scale.
@export_range(0.0, 1.0, 0.01) var wallrun_sloppy_gravity := 0.5
## Speed lost per second while wallrunning with no direction held.
@export_range(0.0, 20.0, 0.1) var wallrun_misalign_drag := 5.0
## How fast leaning rolls your wallrun's path round, degrees per second:
## toward the wall turns it up, away turns it down.
@export_range(0.0, 360.0, 1.0) var wallrun_angle_rate := 80.0
## Steepest angle you can run up a wall (from a steep entry), and down it.
@export_range(0.0, 85.0, 1.0) var wallrun_max_up_angle := 55.0
@export_range(0.0, 85.0, 1.0) var wallrun_max_down_angle := 45.0
## Share of gravity that slows you while running up a wall (the steeper,
## the more it costs).
@export_range(0.0, 1.0, 0.01) var wallrun_climb_cost := 0.6
## Extra kick-off power when jumping off at the steepest angle (0.5 = 50%).
@export_range(0.0, 2.0, 0.05) var wallrun_steep_kick := 0.5
## Ideal distance from a wall when you jump to vault it (from body edge).
@export_range(0.0, 2.0, 0.05) var vault_ideal_distance := 0.35
## Fraction of speed into a wall that a kick-off turns into push.
@export_range(0.0, 1.0, 0.01) var kick_reflect := 0.5

@export_group("Flips and spins")
## How far short of a full turn (degrees) still counts as a 360 or a flip.
@export_range(0.0, 90.0, 1.0) var rotation_tolerance := 35.0
## Landing with the view tipped further than this (degrees) is a crash.
@export_range(60.0, 180.0, 1.0) var crash_pitch := 100.0
## In the air, once the view tips past 75 degrees it turns this much faster,
## so a committed flick carries you over into a flip.
@export_range(1.0, 4.0, 0.05) var flip_look_gain := 1.75
## Landing tucked forward (view down or further over) rolls instead of
## landing hard. Needs at least this fall speed, or a half-done front flip.
@export_range(0.0, 30.0, 0.5) var flip_roll_min_fall := 9.5
## On the ground, pull the view this many degrees past straight down to roll.
@export_range(5.0, 120.0, 1.0) var ground_roll_flick := 40.0
## How fast that pull fades (radians per second), so it has to be a flick.
@export_range(0.0, 20.0, 0.1) var ground_roll_flick_decay := 3.0
## Side flip roll speed while lean is held in the air (degrees per second).
@export_range(90.0, 1440.0, 10.0) var side_flip_speed := 480.0
## Let go of lean within this many degrees of level and you settle upright.
@export_range(0.0, 90.0, 1.0) var side_settle_degrees := 40.0
## Landing rolled over further than this (degrees) is a crash.
@export_range(10.0, 120.0, 1.0) var side_crash_degrees := 50.0
## Side flips keep their direction once started. Tucked (lean or crouch
## held) you spin at side_flip_speed; opened up, at this share of it.
@export_range(0.0, 1.0, 0.01) var spin_open_share := 0.35
## How fast the side-flip spin speeds up or slows down (degrees/s per s).
@export_range(100.0, 5000.0, 10.0) var spin_accel := 2400.0
## Flips and turns carry on after you stop moving the view, if you were
## turning faster than spin_carry_min (degrees/s). The spin fades over
## about spin_carry_time seconds; tucking (crouch) keeps it going.
@export_range(0.0, 2000.0, 10.0) var spin_carry_min := 270.0
@export_range(0.0, 2.0, 0.01) var spin_carry_time := 0.3

@export_group("Quick turn and boost")
## Holding a lean button turns the view this many times faster toward that
## side (Q left, E right); turning the other way is normal speed.
@export_range(1.0, 5.0, 0.1) var quick_turn_look_scale := 2.5
## Holding boost (Shift) in the air or on a wall, moving the mouse left and
## right rolls you instead of turning: a side flip in the air, rolling your
## path round on a wall. This scales how far (1 = as far as it would turn).
@export_range(0.1, 4.0, 0.05) var mouse_roll_scale := 1.0
## While quick turning, your speed turns with your view: all of it on the
## ground, this share of it in the air.
@export_range(0.0, 1.0, 0.01) var quick_turn_air_carry := 0.35
## Speed added by a boost (m/s), and seconds before the next one.
@export_range(0.0, 10.0, 0.1) var boost_speed := 3.5
@export_range(0.0, 10.0, 0.1) var boost_cooldown := 2.0
## Seconds the boost holds your top speed up, fading back over this time.
@export_range(0.0, 3.0, 0.05) var boost_time := 0.8

@export_group("Breakables")
## Speed at which running or sliding into a window smashes it.
@export_range(0.0, 20.0, 0.1) var smash_speed := 5.0

@export_group("Context")
## Mirror's Edge style: vaults and high mantles need a jump press (buffered),
## so you choose when to use an obstacle. Off = everything is automatic.
@export var vault_requires_jump := true

@export_group("Camera")
@export_range(0.0005, 0.02, 0.0005) var mouse_sensitivity := 0.0025
@export_range(0.5, 10.0, 0.1) var gamepad_look_speed := 3.2
## Stick look speed multiplier in the air, so flips and 360s fit in a jump.
@export_range(1.0, 4.0, 0.1) var gamepad_air_spin := 2.0
@export_range(50.0, 120.0, 1.0) var base_fov := 85.0
## Extra FOV at top speed.
@export_range(0.0, 40.0, 1.0) var speed_fov_bonus := 10.0
@export_range(0.0, 30.0, 0.5) var wallrun_tilt_degrees := 9.0
## Lean on the ground: how far the camera moves sideways and tilts.
@export_range(0.0, 1.0, 0.01) var lean_offset := 0.4
@export_range(0.0, 30.0, 0.5) var lean_tilt_degrees := 12.0
## Running, the lean is mostly a quick turn, so the view only peeks this
## share of the way (full peek standing still, easing down to it at run
## speed).
@export_range(0.0, 1.0, 0.01) var lean_peek_running_share := 0.15
## How fast lean eases in and out (full lean per second).
@export_range(1.0, 20.0, 0.5) var lean_speed := 7.0
## Head bob amplitude in meters at run speed (0 = off).
@export_range(0.0, 0.2, 0.005) var head_bob := 0.035
## Camera dip on landing, meters per m/s of fall speed.
@export_range(0.0, 0.05, 0.001) var landing_dip := 0.012
