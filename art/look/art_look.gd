extends Node
## Applies the cel-shaded art look to whatever level is running, without the
## level or the player having to know about it. Autoloaded as `ArtLook`.
##
## On (default): toon materials, ink outlines, a styled sky and light, and
## speed lines. F6 toggles it, to compare with the graybox. The runner body
## (built by the corner cam, or here if a level has none) and the F7 chase
## camera stay either way.
##
## Visuals only ever read the player's state; nothing here feeds back into
## the simulation, so turning the look on or off can never change gameplay.
##
## Graybox geometry built by SandboxBuilder is restyled by swapping its
## materials. Real maps are authored with ArtLook.world_material() directly.

signal toggled(on: bool)

const GRAYBOX_SHADER := preload("res://levels/graybox.gdshader")
const TOON_SHADER := preload("res://art/shaders/toon.gdshader")
const OUTLINE_SHADER := preload("res://art/shaders/outline_post.gdshader")
const SpeedLines := preload("res://art/fx/speed_lines.gd")
const ChaseCamera := preload("res://art/look/chase_camera.gd")


## Graybox color -> art color. Same color language, richer palette.
const PALETTE := {
	"FLOOR": Color(0.66, 0.65, 0.66),
	"NEUTRAL": Color(0.90, 0.89, 0.87),
	"WALLRUN": Color(0.22, 0.56, 1.0),
	"PARKOUR": Color(1.0, 0.74, 0.16),
	"SLIDE": Color(0.20, 0.82, 0.60),
}

## Ambient (shadow) color and strength of the art look.
const AMBIENT := Color(0.74, 0.79, 0.92)
const AMBIENT_ENERGY := 0.55

var enabled := true
## Off in headless runs (tests) unless a test turns it on explicitly.
var auto_attach := true

var _world_materials := {}
var _swapped: Array = []  # [GeometryInstance3D, original material]
var _env_backup := {}
var _attached: Array = []  # nodes this look added, removed when turned off


func _ready() -> void:
	auto_attach = DisplayServer.get_name() != "headless"
	get_tree().node_added.connect(_on_node_added)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F6:
		set_enabled(not enabled)
		get_viewport().set_input_as_handled()


func set_enabled(on: bool) -> void:
	if on == enabled:
		return
	enabled = on
	if on:
		_apply_all(get_tree().root)
	else:
		_remove_all()
	toggled.emit(on)


## The toon material for world geometry of a given color. Shared per color,
## so a level's draw calls batch well.
func world_material(color: Color, grid := 0.35) -> ShaderMaterial:
	var key := "%s/%.2f" % [color.to_html(), grid]
	if not _world_materials.has(key):
		var m := ShaderMaterial.new()
		m.shader = TOON_SHADER
		m.set_shader_parameter("base_color", color)
		m.set_shader_parameter("grid_strength", grid)
		_world_materials[key] = m
	return _world_materials[key]


func _on_node_added(node: Node) -> void:
	if enabled and auto_attach:
		# Wait a frame: builders and players finish setting up in _ready.
		_apply.call_deferred(node)


func _apply_all(root: Node) -> void:
	_apply(root)
	for c in root.get_children():
		_apply_all(c)


func _apply(node: Node) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree() or not enabled:
		return
	if node is GeometryInstance3D:
		_restyle_geometry(node)
	elif node is WorldEnvironment:
		_restyle_environment(node)
	elif node is Player:
		attach_to_player(node)


func _restyle_geometry(g: GeometryInstance3D) -> void:
	var m := g.material_override as ShaderMaterial
	if m == null or m.shader != GRAYBOX_SHADER:
		return
	var base: Color = m.get_shader_parameter("base_color")
	var kind := _kind_for(g, base)
	var color: Color = PALETTE.get(kind, base)
	_swapped.append([g, m])
	g.material_override = world_material(color, 0.35 if kind == "FLOOR" else 0.2)


func _kind_for(g: Node, base: Color) -> String:
	var body := g.get_parent()
	if body and body.has_meta("kind"):
		return body.get_meta("kind")
	# Floor marks have no body: match the closest graybox color.
	var best := ""
	var best_d := 0.04
	for k: String in PALETTE:
		var c: Color = SandboxBuilder.COLORS[SandboxBuilder.Kind[k]]
		var d := Vector3(c.r - base.r, c.g - base.g, c.b - base.b).length()
		if d < best_d:
			best = k
			best_d = d
	return best


func _restyle_environment(we: WorldEnvironment) -> void:
	var env := we.environment
	if env == null or _env_backup.has(env):
		return
	_env_backup[env] = {
		"ambient_light_source": env.ambient_light_source,
		"ambient_light_color": env.ambient_light_color,
		"ambient_light_energy": env.ambient_light_energy,
		"ssao_enabled": env.ssao_enabled,
		"tonemap_mode": env.tonemap_mode,
		"fog_light_color": env.fog_light_color,
		"fog_density": env.fog_density,
		"adjustment_enabled": env.adjustment_enabled,
		"adjustment_saturation": env.adjustment_saturation,
	}
	# Flat, cool ambient = the cel shadow color. No AO smudges.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = AMBIENT
	env.ambient_light_energy = AMBIENT_ENERGY
	env.ssao_enabled = false
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_light_color = Color(0.80, 0.86, 0.96)
	env.fog_density = 0.0035
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	var sky_mat := env.sky.sky_material as ProceduralSkyMaterial if env.sky else null
	if sky_mat:
		_env_backup[sky_mat] = {
			"sky_top_color": sky_mat.sky_top_color,
			"sky_horizon_color": sky_mat.sky_horizon_color,
			"ground_horizon_color": sky_mat.ground_horizon_color,
			"ground_bottom_color": sky_mat.ground_bottom_color,
		}
		sky_mat.sky_top_color = Color(0.24, 0.50, 0.92)
		sky_mat.sky_horizon_color = Color(0.86, 0.90, 0.98)
		sky_mat.ground_horizon_color = Color(0.86, 0.90, 0.98)
		sky_mat.ground_bottom_color = Color(0.45, 0.50, 0.62)


## Adds outlines and speed lines to a player, plus the runner body and the
## chase camera if it has none yet. Public so tests and tools can attach the
## look in headless runs.
func attach_to_player(player: Player) -> void:
	if not player.has_node("RunnerBody"):
		ensure_body(player)
	if not player.has_node("ChaseCamera"):
		var chase: Camera3D = ChaseCamera.new()
		chase.name = "ChaseCamera"
		player.add_child(chase)
		chase.setup(player)
	if player.has_meta("art_look"):
		return
	player.set_meta("art_look", true)
	_add(player.camera, make_outline_quad())
	var lines: CanvasLayer = SpeedLines.new()
	_add(player, lines)
	lines.setup(player)


## The player's runner body, built on first use. The first-person camera is
## set to skip its layer so you never see your own insides.
static func ensure_body(player: Player) -> Node3D:
	var body: Node3D = player.get_node_or_null("RunnerBody")
	if body == null:
		body = RunnerBody.new()
		body.name = "RunnerBody"
		player.add_child(body)
		body.setup(player)
	player.camera.cull_mask &= ~RunnerBody.LAYER
	return body


static func make_outline_quad() -> MeshInstance3D:
	var quad := MeshInstance3D.new()
	quad.name = "InkOutlines"
	var mesh := QuadMesh.new()
	mesh.flip_faces = true
	quad.mesh = mesh
	var m := ShaderMaterial.new()
	m.shader = OUTLINE_SHADER
	m.render_priority = 100
	quad.material_override = m
	quad.extra_cull_margin = 16384.0
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	quad.position = Vector3(0, 0, -0.1)
	quad.layers = 0xFFFFF
	return quad


func _add(parent: Node, child: Node) -> void:
	parent.add_child(child)
	_attached.append(child)


func _remove_all() -> void:
	for pair in _swapped:
		if is_instance_valid(pair[0]):
			pair[0].material_override = pair[1]
	_swapped.clear()
	for res in _env_backup:
		if is_instance_valid(res):
			for prop: String in _env_backup[res]:
				res.set(prop, _env_backup[res][prop])
	_env_backup.clear()
	for n in _attached:
		if is_instance_valid(n):
			var p: Node = n.get_parent()
			if p is Player:
				p.remove_meta("art_look")
			n.queue_free()
	_attached.clear()
