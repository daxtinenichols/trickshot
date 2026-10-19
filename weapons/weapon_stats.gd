class_name WeaponStats
extends Resource
## Numbers that define a gun. Tunable without touching code.

@export var display_name := "Test Pistol"

@export_group("Damage")
@export_range(1.0, 200.0, 1.0) var damage := 28.0
@export_range(1.0, 5.0, 0.05) var headshot_multiplier := 2.5
## Full damage out to this range (m), then falls off linearly...
@export_range(0.0, 200.0, 1.0) var falloff_start := 30.0
## ...down to min_damage_fraction at this range.
@export_range(0.0, 300.0, 1.0) var falloff_end := 70.0
@export_range(0.0, 1.0, 0.01) var min_damage_fraction := 0.6
@export_range(1.0, 500.0, 1.0) var max_range := 150.0

@export_group("Fire")
## Fastest you can click in semi-auto (shots per second).
@export_range(1.0, 30.0, 0.5) var semi_max_rate := 7.0
@export_range(1.0, 30.0, 0.5) var auto_rate := 11.0
@export_range(1, 100, 1) var magazine := 15
@export_range(0.1, 5.0, 0.05) var reload_time := 1.25

@export_group("Aim help (degrees, at full strength)")
## A shot that would miss bends onto a target whose hitbox centre is within
## this angle of it (heads first).
@export_range(0.0, 10.0, 0.1) var assist_miss_cone := 2.5
## A body hit moves up to the head if the head is within this angle.
@export_range(0.0, 10.0, 0.1) var assist_head_cone := 1.2
## Controller: look slows down while a target is within this angle...
@export_range(0.0, 20.0, 0.5) var assist_slow_cone := 4.0
## ...to this share of normal speed.
@export_range(0.0, 1.0, 0.05) var assist_slow_speed := 0.45

@export_group("Recoil (degrees)")
@export_range(0.0, 10.0, 0.05) var recoil_pitch := 1.2
@export_range(0.0, 5.0, 0.05) var recoil_yaw := 0.35
## How fast the view settles back (per second).
@export_range(0.0, 40.0, 0.5) var recoil_recovery := 12.0
## Random roll of the view per shot, and how much the view widens.
@export_range(0.0, 5.0, 0.05) var recoil_roll := 0.5
@export_range(0.0, 10.0, 0.1) var fov_punch := 1.6

@export_group("Aim")
@export_range(20.0, 90.0, 1.0) var aim_fov := 62.0
@export_range(0.01, 1.0, 0.01) var aim_time := 0.12
