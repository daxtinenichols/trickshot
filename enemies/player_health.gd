class_name PlayerHealth
extends Node
## The player's health, for enemies to hurt. Lives as a child of the player
## (added at runtime by whoever brings enemies, so player.gd stays untouched).
##
## Forgiving by design: a few hits to go down, and health comes back fast
## once you stop getting hit, so moving well keeps you alive. Going down
## respawns you (which also bails the combo, like any respawn).
##
## Pure game logic ticked in physics; HurtOverlay only reads it.

## amount after armor, from: the world point the damage came from.
signal damaged(amount: float, from: Vector3, kind: StringName)
signal died
signal healed

const NODE_NAME := "PlayerHealth"

@export var max_health := 100.0
## Seconds without damage before health starts coming back...
@export var regen_delay := 3.5
## ...at this many points per second.
@export var regen_rate := 35.0
## Off: damage still shows but never takes you down (testing).
@export var can_die := true

var player: Player
var health := 100.0
var deaths := 0
## Where you come back after going down (null: the player's own spawn).
var respawn_point: Variant = null
var _since_damage := 999.0
var _last_from := Vector3.ZERO


## The player's health node, or null if none was added.
static func of(p: Node) -> PlayerHealth:
	if p == null:
		return null
	return p.get_node_or_null(NODE_NAME) as PlayerHealth


## The player's health node, added if it doesn't exist yet.
static func ensure(p: Player) -> PlayerHealth:
	var h := of(p)
	if h == null:
		h = PlayerHealth.new()
		h.name = NODE_NAME
		h.player = p
		p.add_child(h)
	return h


func _ready() -> void:
	if player == null:
		player = get_parent() as Player
	health = max_health


func fraction() -> float:
	return clampf(health / maxf(max_health, 1.0), 0.0, 1.0)


func since_damage() -> float:
	return _since_damage


func last_damage_from() -> Vector3:
	return _last_from


func take_damage(amount: float, from: Vector3, kind := &"hit") -> void:
	if amount <= 0.0 or health <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	_since_damage = 0.0
	_last_from = from
	damaged.emit(amount, from, kind)
	if health <= 0.0:
		if can_die:
			_go_down()
		else:
			health = 1.0


func refill() -> void:
	health = max_health
	_since_damage = 999.0
	healed.emit()


func _go_down() -> void:
	deaths += 1
	if player:
		player.respawn(respawn_point)
	refill()
	died.emit()


func _physics_process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	_since_damage += delta
	if _since_damage >= regen_delay and health < max_health:
		health = minf(health + regen_rate * delta, max_health)
