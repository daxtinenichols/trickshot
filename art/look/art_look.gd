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
const TARGET_DRESSER_PATH := "res://art/look/target_dresser.gd"
## Gameplay kinds dressed as part of the city (see obstacle_dresser.gd).
const DRESSED_KINDS := ["PARKOUR", "WALLRUN", "SLIDE", "SURFACE"]
## Looks that are a whole dressed building, not just a surface: body meta
## "look" -> obstacle_dresser.gd style.
const LOOK_DRESSES := {"TOWER": "broadcast_tower", "TOWER_BASE": "tower_base"}
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
	"BRICK": Color(0.42, 0.24, 0.19),
	"CORRUGATED": Color(0.40, 0.47, 0.48),
	"WOOD": Color(0.56, 0.42, 0.29),
	"TOWER": Color(0.50, 0.48, 0.45),
	"TOWER_BASE": Color(0.50, 0.48, 0.45),
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
	"TOWER": [Surface.FACADE, 1.0],
	"TOWER_BASE": [Surface.CONCRETE, 1.0],
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
var _marks := 0  # floor marks laid so far (layer_box)
var _resized: Array = []  # [MeshInstance3D, original mesh, original position]
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
		# Its drawing order (box_grow); a look in a map's own color sits
		# half a step above the plain one.
		var layer := float(LAYERS.find(kind)) if LAYERS.has(kind) else LAYERS.size() * 0.5
		m.set_meta("layer", layer + (0.5 if color != PALETTE.get(kind, PALETTE.NEUTRAL) else 0.0))
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
	elif node is WorldEnvironment or node is DirectionalLight3D:
		# Headless runs (tests) leave the light and sky alone: putting them
		# back when the look turned off hung about one run in two there
		# (the dummy renderer), and nothing draws them anyway.
		if DisplayServer.get_name() == "headless":
			return
		if node is WorldEnvironment:
			_restyle_environment(node)
		else:
			_restyle_sun(node)
	elif node is Player:
		attach_to_player(node)
	elif node is Node3D and node.is_in_group("targets") and dress_obstacles:
		_dress_target(node)


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
	elif dress_obstacles and body is StaticBody3D and g is MeshInstance3D and LOOK_DRESSES.has(kind) \
			and not body.has_node("Dress"):
		_dress(body, g, LOOK_DRESSES[kind])
	if g is MeshInstance3D:
		layer_box(g)


## Drawing order for looks laid flush on each other, lowest first: ground and
## buildings under details. See box_grow.
const LAYERS := ["FLOOR", "TILE", "FACADE", "BRICK", "TOWER", "TOWER_BASE", "NEUTRAL", "CORRUGATED",
	"WOOD", "SURFACE", "WALLRUN", "SLIDE", "PARKOUR", "RUST", "SIGN"]


## How far (m) a box grows on every side when drawn, so boxes laid flush on
## each other (a climb plate on a wall, a slab edge in a wall, two city blocks
## side by side) never share a plane and flicker through each other. The
## look's LAYERS order (`layer`, from the material) decides which draws on
## top, 0.3 mm a step: 1 mm for the ground up to 5.4 mm for a sign. Thinner
## boxes grow a hair more, so two of one look keep apart too. Visual only;
## collision is untouched. A dressed box grows less, under its dress pieces
## (see _layer_dress).
static func box_grow(size: Vector3, layer: float) -> float:
	var thin := maxf(minf(size.x, minf(size.y, size.z)), 0.0)
	return 0.001 + 0.0003 * layer + 0.00008 * clampf(1.0 - thin * 0.5, 0.0, 1.0)


func layer_box(g: MeshInstance3D) -> void:
	if g.has_meta("box_grow") or g.has_meta("face_lift"):
		return
	if g.mesh is PlaneMesh or g.mesh is QuadMesh:
		# Floor marks lie on the floor and on each other: each one lifts
		# 0.5 mm more than the last, in a cycle of 8.
		var lift := 0.0005 * (1 + _marks % 8)
		_marks += 1
		_resized.append([g, g.mesh, g.position])
		var up := Vector3.UP if g.mesh is PlaneMesh else Vector3.BACK
		g.position += (g.basis * up).normalized() * lift
		g.set_meta("face_lift", lift)
	elif g.mesh is BoxMesh and g.material_override:
		var layer: float = g.material_override.get_meta("layer", LAYERS.size() * 0.5)
		var grow := box_grow((g.mesh as BoxMesh).size, layer)
		if g.get_parent().has_node("Dress"):
			# A dressed box stays under its dress pieces (2 mm and up) but
			# apart from other dressed boxes it touches.
			grow = 0.0005 + 0.0001 * layer
		_grow(g, grow)
		var s := (g.mesh as BoxMesh).size
		if minf(s.x, minf(s.y, s.z)) < 0.6 and g.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
			# Thin walls and ceilings cast from both faces, so the sun
			# doesn't leak through them at a low angle.
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED


## Draws a box `grow` m bigger on every side: its own copy of the mesh, put
## back when the look turns off.
func _grow(g: MeshInstance3D, grow: float) -> void:
	var bm := g.mesh as BoxMesh
	var grown := bm.duplicate() as BoxMesh
	grown.size = bm.size + Vector3.ONE * grow * 2.0
	_resized.append([g, bm, g.position])
	g.mesh = grown
	g.set_meta("box_grow", grow)


## Dresses a gameplay obstacle (or a whole building) as part of the city.
## Visual only.
func _dress(body: Node3D, core: MeshInstance3D, style := "") -> void:
	var dresser := _optional(DRESSER_PATH) as Script
	if dresser == null:
		return
	var node: Node = dresser.dress(body, core, self, style)
	if node != null:
		_attached.append(node)
		_layer_dress(node)
		if not core.visible:
			_hidden.append(core)


## A dress lays its pieces on the box and on each other, often flush, base
## first and details after. Each piece grows (see box_grow) 0.25 mm more than
## the one before, in a cycle of 16 (each other cycle half a step up), all
## above the box itself (2 to 5.9 mm),
## so a later piece always draws over an earlier one in the same plane.
func _layer_dress(dress: Node) -> void:
	var i := 0
	for mi: Node in dress.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).mesh is BoxMesh:
			# Dress pieces are the dress's own: grown in place, for good.
			var bm := (mi as MeshInstance3D).mesh as BoxMesh
			var grow := 0.002 + 0.00025 * (i % 16) + 0.000125 * (i / 16 % 2)
			bm.size += Vector3.ONE * grow * 2.0
			mi.set_meta("box_grow", grow)
			i += 1


## Dresses a practice target as junk to shoot at. Visual only.
func _dress_target(target: Node3D) -> void:
	var dresser := _optional(TARGET_DRESSER_PATH) as Script
	if dresser == null:
		return
	var node: Node = dresser.dress(target, self, _hidden)
	if node != null:
		_attached.append(node)
		_layer_dress(node)


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
	# Soft but clean edges: a wider sun and more blur made the edges grainy.
	_look_set(sun, "light_angular_distance", 0.6)
	_look_set(sun, "shadow_blur", 1.0)
	# Less bias: shadows stayed off their walls' feet (peter-panning) and
	# light crept through thin walls and ceilings; thin boxes also cast
	# from both sides (layer_box).
	_look_set(sun, "shadow_bias", 0.04)
	_look_set(sun, "shadow_normal_bias", 0.6)
	# Sharper near shadows, cascades that blend instead of popping, and far
	# enough out that shadows don't appear just ahead at a full sprint.
	_look_set(sun, "directional_shadow_split_1", 0.05)
	_look_set(sun, "directional_shadow_split_2", 0.15)
	_look_set(sun, "directional_shadow_split_3", 0.4)
	_look_set(sun, "directional_shadow_blend_splits", true)
	_look_set(sun, "directional_shadow_max_distance", 220.0)
	_look_set(sun, "directional_shadow_fade_start", 0.9)


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
	for r in _resized:
		if is_instance_valid(r[0]):
			r[0].mesh = r[1]
			r[0].position = r[2]
			r[0].remove_meta("box_grow")
			r[0].remove_meta("face_lift")
	_resized.clear()
	# Iterate a copy of the keys: walking a Dictionary keyed by an object that
	# has since been freed (a sun from an unloaded level) can loop forever.
	for res: Variant in _env_backup.keys():
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
