extends Node3D
## Movement sandbox: wires the player to the level, HUD and debug tools.

@onready var builder: SandboxBuilder = $Builder
@onready var player: Player = $Player
@onready var hud: DebugHud = $DebugHud
@onready var tuning_panel: TuningPanel = $TuningPanel
@onready var trail: SpeedTrail = $SpeedTrail


func _ready() -> void:
	hud.setup(player)
	tuning_panel.setup(player)
	trail.player = player
	go_to_zone(0)


func go_to_zone(index: int) -> void:
	if index < 0 or index >= builder.spawns.size():
		return
	player.respawn(builder.spawns[index])
	hud.show_toast(builder.zone_names[index])


func _unhandled_input(event: InputEvent) -> void:
	for i in 9:
		if event.is_action_pressed("zone_%d" % (i + 1)):
			go_to_zone(i)
			return
	if event.is_action_pressed("debug_slowmo"):
		Engine.time_scale = 0.3 if is_equal_approx(Engine.time_scale, 1.0) else 1.0
