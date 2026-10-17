class_name DebugHud
extends CanvasLayer
## On-screen readouts for tuning movement: speed, state, momentum, a speed
## graph, and a feed of moves as they happen. F1 toggles it.

const STATE_COLORS := {
	Player.State.GROUND: Color(0.85, 0.87, 0.9),
	Player.State.AIR: Color(0.55, 0.8, 1.0),
	Player.State.CROUCH: Color(0.6, 0.6, 0.65),
	Player.State.SLIDE: Color(0.35, 0.9, 0.6),
	Player.State.VAULT: Color(1.0, 0.8, 0.3),
	Player.State.MANTLE: Color(1.0, 0.65, 0.2),
	Player.State.WALLRUN: Color(0.3, 0.6, 1.0),
	Player.State.WALLCLIMB: Color(0.75, 0.5, 1.0),
	Player.State.ROLL: Color(0.4, 1.0, 0.9),
	Player.State.STUN: Color(1.0, 0.35, 0.3),
}

const TRICK_NAMES := {
	&"hop": "HOP",
	&"spin_360": "360",
	&"spin_720": "720",
	&"spin_1080": "1080",
	&"backflip": "BACKFLIP",
	&"frontflip": "FRONT FLIP",
	&"wall_hop": "WALL HOP",
	&"door_kick": "DOOR KICK",
	&"window_kick": "WINDOW KICK",
	&"window_smash": "WINDOW SMASH",
	&"crash": "CRASH",
	&"kick": "KICK",
	&"kick_miss": "KICK",
	&"slide": "SLIDE",
	&"slide_jump": "SLIDE JUMP",
	&"vault": "VAULT",
	&"mantle": "MANTLE",
	&"wallrun": "WALLRUN",
	&"wall_jump": "WALL JUMP",
	&"wall_climb": "WALL CLIMB",
	&"wall_climb_kick": "CLIMB KICK",
	&"landing_roll": "ROLL LANDING",
	&"ground_roll": "ROLL",
	&"flip_roll": "FLIP ROLL",
	&"sideflip": "SIDE FLIP",
	&"ramp_run": "RAMP RUN",
	&"loop": "LOOP",
	&"kick_off": "KICK-OFF",
	&"hard_landing": "HARD LANDING",
	&"wall_impact": "BONK",
	&"boost": "BOOST",
}

const HELP := "Esc: maps, moves list, settings and controls · Backspace respawn · 1-9 zones, 0 shooting range, - ramps and loop · F1 HUD · F2 tuning · wheel click slow-mo (F3 holds it) · wheel zoom (third person) · F4 speed trail · F9 art look · F10 chase cam · F11 next map (or pick one in the Esc menu) · F12 corner cam"

var player: Player

var _speed_label: Label
var _state_label: Label
var _detail_label: Label
var _momentum_bar: ProgressBar
var _graph: SpeedGraph
var _feed: VBoxContainer
var _toast: Label
var _toast_time := 0.0
var _root: Control
var _hit_marker: HitMarker
var _rotation_label: Label
var _ammo_label: Label
var _pistol: Pistol

const SHOT_TAG_NAMES := {
	&"airborne": "AIRBORNE",
	&"wallrun": "WALLRUN",
	&"sliding": "SLIDING",
	&"climbing": "CLIMBING",
	&"vaulting": "VAULTING",
	&"flipping": "MID-FLIP",
	&"spinning": "MID-SPIN",
	&"upside_down": "UPSIDE DOWN",
	&"side_flipping": "MID-SIDE-FLIP",
	&"surface": "RAMP",
	&"fast": "FAST",
}


## How well a move was done, as players see it.
static func quality_grade(q: float) -> String:
	if q >= 0.9:
		return "PERFECT"
	if q >= 0.6:
		return "GOOD"
	return "OK"


static func state_color(s: int) -> Color:
	return STATE_COLORS.get(s, Color.WHITE)


func _ready() -> void:
	layer = 10
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.add_theme_stylebox_override("panel", _panel_style())
	_root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)

	_speed_label = _label(box, 40)
	_state_label = _label(box, 20)
	_momentum_bar = ProgressBar.new()
	_momentum_bar.max_value = 1.0
	_momentum_bar.step = 0.001
	_momentum_bar.show_percentage = false
	_momentum_bar.custom_minimum_size = Vector2(320, 10)
	box.add_child(_momentum_bar)
	_detail_label = _label(box, 14)
	_detail_label.modulate = Color(1, 1, 1, 0.75)
	_graph = SpeedGraph.new()
	box.add_child(_graph)

	_feed = VBoxContainer.new()
	_feed.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_feed.position = Vector2(-340, 16)
	_feed.custom_minimum_size = Vector2(320, 0)
	_feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	_root.add_child(_feed)

	var cross := Label.new()
	cross.text = "+"
	cross.add_theme_font_size_override("font_size", 22)
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.position = Vector2(-6, -16)
	_root.add_child(cross)

	_toast = Label.new()
	_toast.add_theme_font_size_override("font_size", 34)
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_toast.add_theme_constant_override("outline_size", 8)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.position = Vector2(-300, 90)
	_toast.custom_minimum_size = Vector2(600, 0)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_toast)

	# Flip / spin progress while airborne, so players can feel how close
	# they are to completing a rotation.
	_rotation_label = Label.new()
	_rotation_label.add_theme_font_size_override("font_size", 22)
	_rotation_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_rotation_label.add_theme_constant_override("outline_size", 6)
	_rotation_label.set_anchors_preset(Control.PRESET_CENTER)
	_rotation_label.position = Vector2(-150, 40)
	_rotation_label.custom_minimum_size = Vector2(300, 0)
	_rotation_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_rotation_label)

	_hit_marker = HitMarker.new()
	_root.add_child(_hit_marker)

	_ammo_label = Label.new()
	_ammo_label.add_theme_font_size_override("font_size", 30)
	_ammo_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_ammo_label.add_theme_constant_override("outline_size", 6)
	_ammo_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_ammo_label.position = Vector2(-260, -100)
	_ammo_label.custom_minimum_size = Vector2(240, 0)
	_ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_root.add_child(_ammo_label)

	var help := Label.new()
	help.text = HELP
	help.add_theme_font_size_override("font_size", 13)
	help.modulate = Color(1, 1, 1, 0.7)
	help.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	help.position = Vector2(16, -52)
	_root.add_child(help)


func setup(p: Player) -> void:
	player = p
	_graph.player = p
	p.trick.connect(_on_trick)
	_pistol = p.weapon as Pistol
	if _pistol:
		_pistol.hit.connect(_on_shot_hit)


func show_toast(text: String, duration := 2.0) -> void:
	_toast.text = text
	_toast_time = duration


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_hud"):
		_root.visible = not _root.visible


func _process(delta: float) -> void:
	_toast_time -= delta
	_toast.modulate.a = clampf(_toast_time, 0.0, 1.0)
	if player == null:
		return
	var h := player.horizontal_speed()
	_speed_label.text = "%.1f m/s" % h
	_state_label.text = Player.State.keys()[player.state]
	_state_label.modulate = state_color(player.state)
	_momentum_bar.value = player.momentum
	_detail_label.text = "momentum %.0f%%   vertical %+.1f m/s   height %.1f m   %d fps" % [
		player.momentum * 100.0, player.velocity.y, player.global_position.y, Engine.get_frames_per_second()]
	_rotation_label.text = rotation_text(player)
	if _pistol:
		var mode := "AUTO" if _pistol.full_auto else "SEMI"
		_ammo_label.text = ("RELOADING" if _pistol.is_reloading() else "%d / %d" % [_pistol.ammo, _pistol.stats.magazine]) + "\n" + mode
	if SlowMo.speed < 1.0:
		_detail_label.text += "   SLOW-MO %d%%" % roundi(SlowMo.speed * 100.0)
	for child in _feed.get_children():
		var item := child as Label
		var age: float = item.get_meta("age") + delta
		item.set_meta("age", age)
		item.modulate.a = clampf(3.0 - age, 0.0, 1.0)
		if age > 3.0:
			item.queue_free()


func _on_trick(trick_name: StringName, info: Dictionary) -> void:
	var item := Label.new()
	item.text = "%s   %.1f m/s" % [TRICK_NAMES.get(trick_name, String(trick_name).to_upper()), info.get("speed", 0.0)]
	if info.has("quality"):
		item.text = "%s  %s" % [quality_grade(info.quality), item.text]
	item.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	item.add_theme_font_size_override("font_size", 22)
	item.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	item.add_theme_constant_override("outline_size", 6)
	var bad := trick_name in [&"hard_landing", &"wall_impact", &"crash"]
	item.add_theme_color_override("font_color", Color(1, 0.45, 0.35) if bad else Color(1, 0.92, 0.6))
	item.set_meta("age", 0.0)
	_feed.add_child(item)
	_feed.move_child(item, 0)
	while _feed.get_child_count() > 7:
		_feed.get_child(_feed.get_child_count() - 1).free()


## "BACKFLIP 64%" while a flip or spin is under way in the air.
static func rotation_text(p: Player) -> String:
	if p.state != Player.State.AIR:
		return ""
	var r := p.air_rotation()
	var parts: Array[String] = []
	var flip := absf(r.y)
	if flip > deg_to_rad(100.0):
		var pct := fmod(flip, TAU) / TAU * 100.0
		parts.append("%s %d%%" % ["BACKFLIP" if r.y > 0.0 else "FRONT FLIP", roundi(pct)])
	var spin := absf(r.x)
	if spin > deg_to_rad(120.0):
		parts.append("SPIN %d%%" % roundi(fmod(spin, TAU) / TAU * 100.0))
	var side := absf(p.air_roll())
	if side > deg_to_rad(60.0):
		parts.append("SIDE FLIP %d%%" % roundi(fmod(side, TAU) / TAU * 100.0))
	return "   ".join(parts)


## Describes a shot for the feed: "HEADSHOT · AIRBORNE · MID-FLIP  70".
static func shot_text(info: Dictionary) -> String:
	var parts: Array[String] = []
	if info.get("killed", false):
		parts.append("KILL")
	if info.get("zone", &"") == &"head":
		parts.append("HEADSHOT")
	for t: StringName in info.get("tags", []):
		parts.append(SHOT_TAG_NAMES.get(t, String(t).to_upper()))
	return "%s   %d" % [" · ".join(parts) if not parts.is_empty() else "HIT", roundi(float(info.get("damage", 0.0)))]


func _on_shot_hit(info: Dictionary) -> void:
	if info.get("target") == null:
		return
	var head: bool = info.get("zone", &"") == &"head"
	var kill: bool = info.get("killed", false)
	_hit_marker.show_hit(head, kill)
	# Only stylish or decisive shots go in the feed, to keep it readable.
	if not (kill or head or not (info.get("tags", []) as Array).is_empty()):
		return
	var item := Label.new()
	item.text = shot_text(info)
	item.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	item.add_theme_font_size_override("font_size", 22)
	item.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	item.add_theme_constant_override("outline_size", 6)
	item.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3) if kill else Color(1.0, 0.85, 0.25) if head else Color(0.8, 0.9, 1.0))
	item.set_meta("age", 0.0)
	_feed.add_child(item)
	_feed.move_child(item, 0)
	while _feed.get_child_count() > 7:
		_feed.get_child(_feed.get_child_count() - 1).free()


func _label(parent: Node, font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	parent.add_child(l)
	return l


func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.05, 0.06, 0.09, 0.6)
	s.set_corner_radius_all(8)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 8
	s.content_margin_bottom = 10
	return s
