extends Node
## Applies the cel-shaded art look to whatever level is running, without the
## level or the player having to know about it. Autoloaded as `ArtLook`.
##
## On (default): toon materials, ink outlines, a styled sky and light, and
## speed lines. F9 toggles it, to compare with the graybox. The runner body
## (built here, see ensure_body) and the F10 chase
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
## Optional parts are loaded at runtime, not preloaded or named by class:
## if one is missing or not imported yet (a fresh copy before the editor
## reimports), it is skipped with a warning instead of taking the whole look
## (environment, runner) down with it.
const WASTELAND_SHADER_PATH := "res://art/shaders/wasteland.gdshader"
const GUN_LOOK_PATH := "res://art/weapons/gun_look.gd"
const DRESSER_PATH := "res://art/look/obstacle_dresser.gd"
## Gameplay kinds dressed as part of the city (see obstacle_dresser.gd).
const DRESSED_KINDS := ["PARKOUR", "WALLRUN", "SLIDE"]
const OUTLINE_SHADER := preload("res://art/shaders/outline_post.gdshader")
const SpeedLines := preload("res://art/fx/speed_lines.gd")
const ChaseCamera := preload("res://art/look/chase_camera.gd")


## Graybox kind -> art color. Same color language as the graybox (blue walls
## to run on, yellow to vault or climb, green to slide under), faded and
## weathered for the post-apocalyptic look.
const PALETTE := {
	"FLOOR": Color(0.40, 0.37, 0.34),
	"NEUTRAL": Color(0.60, 0.56, 0.50),
	"WALLRUN": Color(0.22, 0.45, 0.76),
	"PARKOUR": Color(0.86, 0.60, 0.14),
	"SLIDE": Color(0.25, 0.60, 0.45),
	"SURFACE": Color(0.60, 0.57, 0.52),
	"FACADE": Color(0.54, 0.50, 0.45),
	"TILE": Color(0.66, 0.62, 0.55),
	"RUST": Color(0.44, 0.38, 0.32),
	"SIGN": Color(0.62, 0.30, 0.24),
	"BRICK": Color(0.56, 0.33, 0.25),
	"CORRUGATED": Color(0.40, 0.47, 0.48),
	"WOOD": Color(0.56, 0.42, 0.29),
}

## Which wasteland.gdshader surface each kind uses, and its texture scale in
## meters. Painted kinds wear through to rust (metal) or concrete.
enum Surface { PLAIN, CONCRETE, RUST, ASPHALT, PAINTED_METAL, PAINTED_CONCRETE, FACADE, TILE, BRICK, CORRUGATED, WOOD }
const SURFACES := {
	"FLOOR": [Surface.ASPHALT, 1.0],
	"NEUTRAL": [Surface.CONCRETE, 1.0],
	"WALLRUN": [Surface.PAINTED_METAL, 1.0],
	"PARKOUR": [Surface.PAINTED_CONCRETE, 0.8],
	"SLIDE": [Surface.PAINTED_METAL, 0.8],
	"SURFACE": [Surface.PAINTED_CONCRETE, 1.2],
	"FACADE": [Surface.FACADE, 1.0],
	"TILE": [Surface.TILE, 1.0],
	"RUST": [Surface.RUST, 1.0],
	"SIGN": [Surface.PAINTED_METAL, 0.7],
	"BRICK": [Surface.BRICK, 1.0],
	"CORRUGATED": [Surface.CORRUGATED, 1.0],
	"WOOD": [Surface.WOOD, 1.0],
}

## Ambient (shadow) color and strength: warm gray, like light bounced off dust.
const AMBIENT := Color(0.82, 0.74, 0.66)
const AMBIENT_ENERGY := 0.3
## Hazy, dusty sky and fog.
const SKY_TOP := Color(0.46, 0.50, 0.56)
const SKY_HORIZON := Color(0.92, 0.76, 0.56)
const GROUND_BOTTOM := Color(0.40, 0.33, 0.27)
const FOG := Color(0.86, 0.72, 0.54)
const SUN := Color(1.0, 0.88, 0.70)

var enabled := true
## Off in headless runs (tests) unless a test turns it on explicitly.
var auto_attach := true

var _world_materials := {}
var _missing := {}
var _swapped: Array = []  # [GeometryInstance3D, original material]
var _env_backup := {}
var _attached: Array = []  # nodes this look added, removed when turned off
var _hidden: Array = []  # graybox meshes a dress replaced, shown again when off
## Dress obstacles as the city (concrete, brick, crates, hoardings). Off
## keeps the color-coded blocks under the weathered look.
var dress_obstacles := true


## Function keys away from F5-F8, which the Godot editor uses to run, pause
## and stop the game. Registered as actions so the rebind menu reserves them.
const KEYS := {"toggle_art_look": KEY_F9, "toggle_chase_cam": KEY_F10}


func _ready() -> void:
	auto_attach = DisplayServer.get_name() != "headless"
	get_tree().node_added.connect(_on_node_added)
	for action: String in KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var k := InputEventKey.new()
			k.physical_keycode = KEYS[action]
			InputMap.action_add_event(action, k)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_art_look") and not event.is_echo():
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


## The weathered, textured material for a map kind ("FLOOR", "WALLRUN",
## "FACADE"... see SURFACES), optionally in another color. Procedural and
## world-space, so any box or curve gets it without UVs. Shared per kind and
## color.
func wasteland_material(kind: String, color := Color.TRANSPARENT, grid := 0.0) -> ShaderMaterial:
	var spec: Array = SURFACES.get(kind, [Surface.PAINTED_CONCRETE, 1.0])
	if color.a == 0.0:
		color = PALETTE.get(kind, PALETTE.NEUTRAL)
	var key := "w/%s/%s/%.2f" % [kind, color.to_html(), grid]
	if not _world_materials.has(key):
		var m := ShaderMaterial.new()
		var shader := _optional(WASTELAND_SHADER_PATH) as Shader
		if shader == null:
			return world_material(color, grid)
		m.shader = shader
		m.set_shader_parameter("base_color", color)
		m.set_shader_parameter("surface", spec[0])
		m.set_shader_parameter("tex_scale", spec[1])
		m.set_shader_parameter("grid_strength", grid)
		# Dust settles on everything flat except steep runnable curves.
		m.set_shader_parameter("dust_amount", 0.25 if kind == "SURFACE" else 0.45)
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
	elif node is DirectionalLight3D:
		_restyle_sun(node)
	elif node is Player:
		attach_to_player(node)


func _restyle_geometry(g: GeometryInstance3D) -> void:
	var m := g.material_override as ShaderMaterial
	if m == null or m.shader != GRAYBOX_SHADER:
		return
	var base: Color = m.get_shader_parameter("base_color")
	var kind := _kind_for(g, base)
	_swapped.append([g, m])
	# A faint meter grid stays on the ground so distances still read.
	var grid := 0.12 if kind == "FLOOR" else 0.0
	var body := g.get_parent()
	if PALETTE.has(kind) and body and body.has_meta("look_color"):
		# A map's own paint on a look (shop signs in brand colors).
		g.material_override = wasteland_material(kind, body.get_meta("look_color"))
	elif PALETTE.has(kind):
		g.material_override = wasteland_material(kind, Color.TRANSPARENT, grid)
	else:
		# Custom colored marks (start/finish lines...): worn paint on concrete.
		g.material_override = wasteland_material("", base)
	if dress_obstacles and body is StaticBody3D and g is MeshInstance3D and DRESSED_KINDS.has(kind) \
			and not body.has_meta("look") and not body.has_node("Dress"):
		_dress(body, g)


## Dresses a gameplay obstacle as part of the city. Visual only.
func _dress(body: Node3D, core: MeshInstance3D) -> void:
	var dresser := _optional(DRESSER_PATH) as Script
	if dresser == null:
		return
	var node: Node = dresser.dress(body, core, self)
	if node != null:
		_attached.append(node)
		if not core.visible:
			_hidden.append(core)


func _kind_for(g: Node, base: Color) -> String:
	var body := g.get_parent()
	# Maps can ask for a look the gameplay kind doesn't say (a skyline
	# building is NEUTRAL to the player but a ruined facade to the eye).
	if body and body.has_meta("look"):
		return body.get_meta("look")
	if body and body.has_meta("kind"):
		return body.get_meta("kind")
	# Floor marks have no body: match the closest graybox color.
	var best := ""
	var best_d := 0.04
	for k: String in PALETTE:
		if not SandboxBuilder.Kind.has(k):
			continue
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
	# Polished, a little more natural than flat cel: sky-tinted ambient with
	# soft contact shadows (AO), filmic tone mapping and a gentle bloom on
	# bright things (sky, muzzle flashes, sparks).
	_look_set(env, "ambient_light_source", Environment.AMBIENT_SOURCE_SKY)
	_look_set(env, "ambient_light_energy", AMBIENT_ENERGY)
	_look_set(env, "ambient_light_sky_contribution", 0.65)
	_look_set(env, "ambient_light_color", AMBIENT)
	_look_set(env, "ssao_enabled", true)
	_look_set(env, "ssao_radius", 1.4)
	_look_set(env, "ssao_intensity", 1.6)
	_look_set(env, "ssao_light_affect", 0.15)
	_look_set(env, "tonemap_mode", Environment.TONE_MAPPER_ACES)
	_look_set(env, "tonemap_exposure", 0.85)
	_look_set(env, "glow_enabled", true)
	_look_set(env, "glow_intensity", 0.55)
	_look_set(env, "glow_bloom", 0.04)
	_look_set(env, "glow_hdr_threshold", 1.1)
	# Dust haze: thicker fog so distant ruins fade into the sky.
	_look_set(env, "fog_light_color", FOG)
	_look_set(env, "fog_density", 0.0045)
	# Keep some sky gradient above the haze, and a glow around the sun.
	_look_set(env, "fog_sky_affect", 0.35)
	_look_set(env, "fog_sun_scatter", 0.25)
	_look_set(env, "adjustment_enabled", true)
	_look_set(env, "adjustment_saturation", 0.98)
	_look_set(env, "adjustment_contrast", 1.12)
	var sky_mat := env.sky.sky_material as ProceduralSkyMaterial if env.sky else null
	if sky_mat:
		_look_set(sky_mat, "sky_top_color", SKY_TOP)
		_look_set(sky_mat, "sky_horizon_color", SKY_HORIZON)
		_look_set(sky_mat, "ground_horizon_color", SKY_HORIZON)
		_look_set(sky_mat, "ground_bottom_color", GROUND_BOTTOM)


## Low, warm sun through the dust, with soft-edged shadows.
func _restyle_sun(sun: DirectionalLight3D) -> void:
	if _env_backup.has(sun):
		return
	_look_set(sun, "light_color", SUN)
	_look_set(sun, "light_energy", 1.55)
	_look_set(sun, "light_angular_distance", 1.2)
	_look_set(sun, "shadow_blur", 1.5)


## Sets a property the look changes, remembering the original for F9.
func _look_set(obj: Object, prop: String, value: Variant) -> void:
	if not _env_backup.has(obj):
		_env_backup[obj] = {}
	if not _env_backup[obj].has(prop):
		_env_backup[obj][prop] = obj.get(prop)
	obj.set(prop, value)


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
	var pistol := player.weapon as Pistol
	if pistol and pistol.view_model:
		var script := _optional(GUN_LOOK_PATH) as Script
		if script and script.can_instantiate():
			var gun: Node3D = script.new()
			gun.name = "GunLook"
			_add(player, gun)
			gun.setup(pistol, player.get_node("RunnerBody"))


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


## Loads an optional resource, or warns once and returns null.
func _optional(path: String) -> Resource:
	if _missing.has(path):
		return null
	var res: Resource = load(path) if ResourceLoader.exists(path) else null
	if res == null or (res is Script and not (res as Script).can_instantiate()):
		push_warning("ArtLook: couldn't load %s, skipping it (reload the project if it was just added)" % path)
		_missing[path] = true
		return null
	return res


func _add(parent: Node, child: Node) -> void:
	parent.add_child(child)
	_attached.append(child)


func _remove_all() -> void:
	for pair in _swapped:
		if is_instance_valid(pair[0]):
			pair[0].material_override = pair[1]
	_swapped.clear()
	for g in _hidden:
		if is_instance_valid(g):
			g.visible = true
	_hidden.clear()
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
			if p != null:
				p.remove_child(n)  # gone now, so turning the look back on can redo it
			n.queue_free()
	_attached.clear()
