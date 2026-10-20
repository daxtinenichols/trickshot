extends Node3D
## Movement sandbox: wires the player to the level, HUD and debug tools.

@onready var builder: SandboxBuilder = $Builder
@onready var player: Player = $Player
@onready var hud: DebugHud = $DebugHud
@onready var tuning_panel: TuningPanel = $TuningPanel
@onready var trail: SpeedTrail = $SpeedTrail


var menu: PauseMenu
var combo: ComboTracker
var combo_hud: ComboHud


func _ready() -> void:
	hud.setup(player)
	tuning_panel.setup(player)
	trail.player = player
	menu = PauseMenu.new()
	add_child(menu)
	menu.setup(player)  # applies saved settings (after tuning so they win)
	combo = ComboTracker.new()
	add_child(combo)
	combo.setup(player, player.weapon as Pistol)
	combo_hud = ComboHud.new()
	add_child(combo_hud)
	combo_hud.setup(combo)
	go_to_zone(0)
	hud.show_toast("Esc: maps, moves list, settings and controls", 4.0)


func go_to_zone(index: int) -> void:
	if index < 0 or index >= builder.spawns.size():
		return
	player.respawn(builder.spawns[index])
	hud.show_toast(builder.zone_names[index])


func _unhandled_input(event: InputEvent) -> void:
	for i in builder.spawns.size():
		if InputMap.has_action("zone_%d" % (i + 1)) and event.is_action_pressed("zone_%d" % (i + 1)):
			go_to_zone(i)
			return
