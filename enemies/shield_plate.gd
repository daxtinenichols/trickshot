extends StaticBody3D
## A riot shield's plate: stops the player's shots (it's on the hitbox
## layer, with no zone or target, so a shot that hits it scores nothing)
## and passes kicks on to its bearer, which knocks the shield aside.

const LAYER := 4

var bearer: Node


func _init(owner_enemy: Node = null) -> void:
	bearer = owner_enemy
	collision_layer = LAYER
	collision_mask = 0


## Called by the pistol for hits on things that aren't targets.
func on_hit(info: Dictionary) -> void:
	if bearer and bearer.has_method("on_shield_hit"):
		bearer.on_shield_hit(info)


func on_kicked(by: Node, dir := Vector3.ZERO) -> void:
	if bearer and bearer.has_method("on_kicked"):
		bearer.on_kicked(by, dir)


func set_enabled(on: bool) -> void:
	collision_layer = LAYER if on else 0
