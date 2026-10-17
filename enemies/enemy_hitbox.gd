class_name EnemyHitbox
extends StaticBody3D
## One hit zone of an enemy (head or body). The pistol reads the "zone" and
## "target" metas like it does for practice targets; kicks are passed on to
## the enemy.

const LAYER := 4

var enemy: Node


func _init(owner_enemy: Node = null, zone := &"body") -> void:
	enemy = owner_enemy
	collision_layer = LAYER
	collision_mask = 0
	set_meta("zone", zone)
	set_meta("target", owner_enemy)
	# Aim help finds hit zones through this group.
	add_to_group("hitboxes")


func on_kicked(by: Node, dir := Vector3.ZERO) -> void:
	if enemy and enemy.has_method("on_kicked"):
		enemy.on_kicked(by, dir)


func set_enabled(on: bool) -> void:
	collision_layer = LAYER if on else 0
