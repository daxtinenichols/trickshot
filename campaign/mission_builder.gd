@tool
class_name MissionBuilder
extends SandboxBuilder
## Builds a mission's layout from its data file (campaign/missions/*.json,
## format in docs/missions.md): optionally an existing map as the base, then
## the mission's own pieces (boxes, buildings, props, doors, windows,
## targets, ramps and loops, labels, tapes, fire, enemy encounters).
##
## In the editor, set `mission_path` on the Builder node of
## campaign/mission.tscn to see a mission's layout; save the JSON and press
## "Rebuild" in the inspector to refresh it. In game the path comes from the
## mission being played (Campaign.current).

const PropKit := preload("res://art/props/prop_kit.gd")
const FIRE_SHADER_PATH := "res://campaign/fire.gdshader"
## A runner standing in the level as a character (Echo in the studio).
const FIGURE_SCRIPT_PATH := "res://art/characters/runner/runner_figure.gd"
## Scripted chase moments (falling beams, the Host's shortcuts, blasts).
const SET_PIECE_SCRIPT_PATH := "res://campaign/set_piece.gd"
# Enemies load by path, not class_name (a stale class cache has broken
# scenes before).
const ENCOUNTER_SCRIPT := preload("res://enemies/enemy_encounter.gd")
const RAIDER_SCRIPT := preload("res://enemies/raider.gd")
const MUTANT_SCRIPT := preload("res://enemies/mutant.gd")
## What stands in for a kind whose script is missing (every type in
## docs/enemies.md has one now; this only guards a missed import).
const STAND_INS := {"trooper": "raider", "shield": "raider", "marksman": "raider", "heavy": "raider",
	"brute": "mutant", "leaper": "mutant", "crawler": "mutant"}

@export_file("*.json") var mission_path := ""
## Rebuilds the layout (editor helper: tick it after editing the JSON).
@export var rebuild := false:
	set(v):
		if v and is_inside_tree():
			build()

## The mission's data, as loaded.
var mission := {}
## Collectible tapes: [{id, position, node}].
var tapes: Array[Dictionary] = []
## Enemy encounters (EnemyEncounter nodes), in the order they appear.
var encounters: Array[Node3D] = []
## Set pieces (campaign/set_piece.gd), in route order. MissionRun ticks them.
var set_pieces: Array[Node3D] = []
## The base map's builder, when the mission builds on one.
var base: SandboxBuilder


func resolved_path() -> String:
	if mission_path != "":
		return mission_path
	return Campaign.entry(Campaign.current).get("file", "")


func build() -> void:
	if _root != null:
		_root.queue_free()
	if base != null:
		base.queue_free()
		base = null
	_root = Node3D.new()
	_root.name = "Generated"
	add_child(_root)
	spawns.clear()
	zone_names.clear()
	tapes.clear()
	encounters.clear()
	set_pieces.clear()
	mission = Campaign.load_mission_file(resolved_path())
	if mission.is_empty():
		_box(Vector3(0, -0.5, 0), Vector3(40, 1, 40), Kind.FLOOR)
		_label("No mission data at '%s'" % resolved_path(), Vector3(0, 2, -6), 1.0)
		spawns.append(Transform3D(Basis.IDENTITY, Vector3(0, 0, 0)))
		zone_names.append("Empty")
		return
	var base_path: String = mission.get("base", "")
	if base_path != "":
		var script: Script = load(base_path)
		base = script.new()
		base.name = "Base"
		if (mission.has("route") or mission.get("open_exit", false)) and "open_exit" in base:
			# The route (or the mission's own pieces) carries on past the
			# base's exit.
			base.open_exit = true
		# Settings the base builder exports (e.g. Rooftops'
		# hide_course_marks), set before it builds.
		var settings: Dictionary = mission.get("base_set", {})
		for key: String in settings:
			if key in base:
				base.set(key, settings[key])
			else:
				push_warning("MissionBuilder: %s has no setting %s" % [base_path, key])
		add_child(base)  # builds itself in _ready
	for piece: Dictionary in mission.get("pieces", []):
		_piece(piece)
	# Spawns: the start, then one per checkpoint (number keys jump there).
	var start: Dictionary = mission.get("start", {})
	if start.is_empty() and base != null:
		spawns.append(base.spawns[0])
	else:
		spawns.append(_spawn_xf(start))
	zone_names.append("1 · " + String(mission.get("title", "START")).to_upper())
	var cps: Array = mission.get("checkpoints", [])
	for i in cps.size():
		spawns.append(_spawn_xf(cps[i]))
		zone_names.append("%d · %s" % [i + 2, String(cps[i].get("name", "Checkpoint")).to_upper()])


static func vec(a: Variant, fallback := Vector3.ZERO) -> Vector3:
	if a is Array and a.size() >= 3:
		return Vector3(a[0], a[1], a[2])
	return fallback


static func _spawn_xf(d: Dictionary) -> Transform3D:
	var at := vec(d.get("spawn", d.get("at", [0, 0, 0])))
	return Transform3D(Basis(Vector3.UP, deg_to_rad(d.get("yaw", 0.0))), at)


# ---------------------------------------------------------------- pieces

func _piece(p: Dictionary) -> void:
	var yaw := deg_to_rad(p.get("yaw", 0.0))
	var basis := Basis(Vector3.UP, yaw)
	if p.has("box"):
		var kind: Kind = Kind.get(p.get("kind", "NEUTRAL"), Kind.NEUTRAL)
		var b := _box_basis(vec(p.box), vec(p.get("size", [1, 1, 1]), Vector3.ONE), basis, kind)
		if p.has("look"):
			b.set_meta("look", p.look)
	elif p.has("building"):
		# A building from the street up to its roof: [x, roof_y, z] and
		# size [width, depth]. Its sides look like a ruined facade.
		var at := vec(p.building)
		var s: Array = p.get("size", [12, 12])
		var b := _box_basis(Vector3(at.x, at.y * 0.5, at.z), Vector3(s[0], at.y, s[1]), basis, Kind.NEUTRAL)
		b.set_meta("look", p.get("look", "FACADE"))
	elif p.has("slab"):
		# A building with any convex footprint: "slab" is its corners
		# [[x, z], ...] in order, "top" its roof height.
		var b := _slab(p.slab, float(p.get("top", 6.0)))
		b.set_meta("look", p.get("look", "FACADE"))
	elif p.has("prop"):
		PropKit.place(_root, p.prop, Transform3D(basis, vec(p.get("at", [0, 0, 0]))), p.get("collide", true))
	elif p.has("row"):
		# A row of the same prop from `from` to `to`.
		var a := vec(p.get("from", [0, 0, 0]))
		var b := vec(p.get("to", [0, 0, 0]))
		var n: int = maxi(p.get("count", 2), 1)
		for i in n:
			var t := 0.0 if n == 1 else i / float(n - 1)
			PropKit.place(_root, p.row, Transform3D(basis, a.lerp(b, t)))
	elif p.has("door"):
		_door(vec(p.door))
		if yaw != 0.0 and not Engine.is_editor_hint():
			_root.get_child(-1).rotation.y = yaw
	elif p.has("window"):
		var s: Array = p.get("size", [2.2, 1.4])
		_window(vec(p.window), Vector2(s[0], s[1]))
		if yaw != 0.0 and not Engine.is_editor_hint():
			_root.get_child(-1).rotation.y = yaw
	elif p.has("target"):
		var motion: ShootingTarget.Motion = ShootingTarget.Motion.get(String(p.get("motion", "STATIC")).to_upper(), ShootingTarget.Motion.STATIC)
		_target(vec(p.target), motion, p.get("amplitude", 3.0), p.get("speed", 4.0))
	elif p.has("ramp"):
		var kind: Kind = Kind.get(p.get("kind", "SLIDE"), Kind.SLIDE)
		_ramp_any(vec(p.ramp), vec(p.get("to", [0, 0, 0])), p.get("width", 4.0), kind)
	elif p.has("loop"):
		_surface(MapPieces.turned(SurfaceShapes.loop(vec(p.loop), p.get("radius", 4.5), p.get("width", 3.5), p.get("shift", 5.5)), vec(p.loop), yaw))
	elif p.has("quarter_pipe"):
		_surface(MapPieces.turned(SurfaceShapes.quarter_pipe(vec(p.quarter_pipe), p.get("radius", 4.0), p.get("angle", 80.0), p.get("straight", 1.0), p.get("width", 8.0)), vec(p.quarter_pipe), yaw))
	elif p.has("bank"):
		_surface(MapPieces.turned(MapPieces.bank(vec(p.bank), p.get("length", 10.0), p.get("side", 1.0), p.get("radius", 3.0), p.get("angle", 60.0), p.get("straight", 1.0)), vec(p.bank), yaw))
	elif p.has("label"):
		_label(p.label, vec(p.get("at", [0, 2, 0])), p.get("size", 0.8))
	elif p.has("mark"):
		var s: Array = p.get("size", [12, 0.8])
		_floor_mark(vec(p.mark), Vector2(s[0], s[1]), Color(p.get("color", "#4de673")))
		if yaw != 0.0:
			_root.get_child(-1).rotation.y = yaw
	elif p.has("tape"):
		_tape(String(p.get("id", "tape_%d" % tapes.size())), vec(p.tape))
	elif p.has("fire"):
		_fire(vec(p.fire), vec(p.get("size", [2, 1.5, 2]), Vector3(2, 1.5, 2)))
	elif p.has("encounter"):
		_encounter(p)
	elif p.has("set_piece"):
		_set_piece(p)
	elif p.has("figure"):
		_figure(String(p.figure), Transform3D(basis, vec(p.get("at", [0, 0, 0]))), String(p.get("pose", "")))
	else:
		push_warning("MissionBuilder: unknown piece %s" % p)


## A prism from the street (y 0) up to `top` over a convex footprint.
func _figure(runner: String, xf: Transform3D, pose: String) -> void:
	if Engine.is_editor_hint():
		return
	var script := load(FIGURE_SCRIPT_PATH) as Script if ResourceLoader.exists(FIGURE_SCRIPT_PATH) else null
	if script == null or not script.can_instantiate():
		push_warning("MissionBuilder: couldn't load %s, skipping the %s figure" % [FIGURE_SCRIPT_PATH, runner])
		return
	var f: Node3D = script.new()
	f.name = "Figure_" + runner
	f.runner = runner
	if pose != "":
		f.pose_name = pose
	f.transform = xf
	_root.add_child(f)


func _set_piece(p: Dictionary) -> void:
	var script := load(SET_PIECE_SCRIPT_PATH) as Script if ResourceLoader.exists(SET_PIECE_SCRIPT_PATH) else null
	if script == null or not script.can_instantiate():
		push_warning("MissionBuilder: couldn't load %s, skipping a set piece" % SET_PIECE_SCRIPT_PATH)
		return
	var sp: Node3D = script.new()
	sp.name = "SetPiece_%s_%d" % [p.set_piece, set_pieces.size()]
	_root.add_child(sp)
	sp.setup(p)
	set_pieces.append(sp)


func _slab(corners: Array, top: float) -> StaticBody3D:
	var ring: PackedVector2Array = []
	for c: Array in corners:
		ring.append(Vector2(c[0], c[1]))
	# Wind the ring counter-clockwise seen from above (x right, z down the
	# screen), so faces point out.
	var area := 0.0
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		area += a.x * b.y - b.x * a.y
	if area > 0.0:
		ring.reverse()
	var center := Vector2.ZERO
	for v in ring:
		center += v
	center /= ring.size()
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = Vector3(center.x, 0, center.y)
	body.set_meta("kind", "NEUTRAL")
	var pts: PackedVector3Array = []
	for v in ring:
		pts.append(Vector3(v.x - center.x, 0, v.y - center.y))
		pts.append(Vector3(v.x - center.x, top, v.y - center.y))
	var shape := CollisionShape3D.new()
	var hull := ConvexPolygonShape3D.new()
	hull.points = pts
	shape.shape = hull
	body.add_child(shape)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := ring.size()
	for i in n:
		var a := Vector3(ring[i].x - center.x, 0, ring[i].y - center.y)
		var b := Vector3(ring[(i + 1) % n].x - center.x, 0, ring[(i + 1) % n].y - center.y)
		var up := Vector3(0, top, 0)
		for v: Vector3 in [a, b + up, b, a, a + up, b + up]:
			st.add_vertex(v)
	for i in range(1, n - 1):
		for v: Vector2 in [ring[0], ring[i + 1], ring[i]]:
			st.add_vertex(Vector3(v.x - center.x, top, v.y - center.y))
	st.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.mesh = st.commit()
	mesh.material_override = _material(Kind.NEUTRAL)
	body.add_child(mesh)
	_root.add_child(body)
	return body


## A flat ramp from `top` to `bottom` in any direction (routes turn).
func _ramp_any(top: Vector3, bottom: Vector3, width: float, kind: Kind) -> void:
	var flat := Vector3(bottom.x - top.x, 0.0, bottom.z - top.z)
	var run := flat.length()
	var rise := top.y - bottom.y
	# Facing down the ramp, tipped by its slope.
	var heading := atan2(-flat.x, -flat.z) if run > 0.001 else 0.0
	var basis := Basis(Vector3.UP, heading) * Basis(Vector3.RIGHT, -atan2(rise, run))
	var normal := basis.y
	_box_basis((top + bottom) * 0.5 - normal * 0.5, Vector3(width, 1, sqrt(run * run + rise * rise)), basis, kind)


## A lost broadcast tape: the model floats and spins; MissionRun collects it.
func _tape(id: String, pos: Vector3) -> void:
	var node := PropKit.place(_root, "tape_cassette", Transform3D(Basis.IDENTITY, pos + Vector3(0, 0.9, 0)), false)
	if node == null:
		return
	node.set_meta("tape", id)
	node.add_to_group("mission_tapes")
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.2)
	light.omni_range = 2.5
	light.light_energy = 1.2
	node.add_child(light)
	tapes.append({"id": id, "position": pos, "node": node})


## Fire: a cluster of flickering flames over glowing embers, and a warm
## light. Visual only (no collision).
func _fire(pos: Vector3, size: Vector3) -> void:
	var shader: Shader = load(FIRE_SHADER_PATH) if ResourceLoader.exists(FIRE_SHADER_PATH) else null
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(pos)
	var embers := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(size.x, 0.12, size.z)
	embers.mesh = bm
	embers.position = pos + Vector3(0, 0.06, 0)
	var em := StandardMaterial3D.new()
	em.albedo_color = Color(0.25, 0.08, 0.03)
	em.emission_enabled = true
	em.emission = Color(1.0, 0.3, 0.05)
	em.emission_energy_multiplier = 2.0
	embers.material_override = em
	embers.add_to_group("mission_fire")
	_root.add_child(embers)
	var count := clampi(roundi(size.x * size.z * 1.2), 3, 9)
	for i in count:
		var flame := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(1, 1)
		quad.center_offset = Vector3(0, 0.5, 0)
		flame.mesh = quad
		var h := size.y * rng.randf_range(0.6, 1.3)
		flame.scale = Vector3(h * rng.randf_range(0.5, 0.75), h, 1)
		flame.position = pos + Vector3(rng.randf_range(-0.4, 0.4) * size.x, 0.05, rng.randf_range(-0.4, 0.4) * size.z)
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if shader != null:
			var m := ShaderMaterial.new()
			m.shader = shader
			m.set_shader_parameter("seed", rng.randf())
			m.set_shader_parameter("speed", rng.randf_range(1.3, 2.0))
			flame.material_override = m
		flame.add_to_group("mission_fire")
		_root.add_child(flame)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.5, 0.2)
	light.omni_range = maxf(size.x, size.z) * 3.0
	light.light_energy = 2.0
	light.position = pos + Vector3(0, size.y + 0.5, 0)
	light.add_to_group("mission_fire")
	_root.add_child(light)


## An enemy encounter: raiders and mutants that wake when you step into its
## area and fight until you clear it, leave it for a few seconds or go down
## (then they reset). Cover rows give raiders spots to hide behind. MissionRun
## hands it the player. In the editor the enemies show as labels.
func _encounter(p: Dictionary) -> void:
	var area: Dictionary = p.get("area", {})
	var center := vec(area.get("at", [0, 0, 0]))
	var size := vec(area.get("size", [20, 10, 20]), Vector3(20, 10, 20))
	if Engine.is_editor_hint():
		for kind: String in ["raiders", "mutants"]:
			for e: Dictionary in p.get(kind, []):
				_label(kind.trim_suffix("s").to_upper(), vec(e.get("at", [0, 0, 0])) + Vector3(0, 1.6, 0), 0.5)
		for e: Dictionary in p.get("enemies", []):
			_label(String(e.get("type", "enemy")).to_upper(), vec(e.get("at", [0, 0, 0])) + Vector3(0, 1.6, 0), 0.5)
		return
	var enc: Node3D = ENCOUNTER_SCRIPT.new()
	enc.name = "Encounter_" + String(p.encounter).validate_node_name()
	enc.set_meta("id", p.encounter)
	enc.add_to_group("mission_encounters")
	_root.add_child(enc)
	enc.bounds = AABB(center - size * 0.5, size)
	enc.entry = Transform3D(Basis.IDENTITY, center)
	# A mission's encounter stays cleared; the sandbox arena's restarts.
	enc.restart_time = p.get("restart", INF)
	enc.max_aiming = p.get("max_aiming", enc.max_aiming)
	for k: String in ["hear_shots", "hearing_radius", "wake_distance"]:
		if p.has(k):
			enc.set(k, p[k])
	for c: Dictionary in p.get("cover", []):
		enc.add_cover_wall(vec(c.get("at", [0, 0, 0])), c.get("length", 2.0), c.get("thickness", 0.55),
				deg_to_rad(c.get("yaw", 0.0)), c.get("spacing", 2.2))
	for e: Dictionary in p.get("raiders", []):
		enc.add_enemy(_enemy(RAIDER_SCRIPT.new(), e), _enemy_xf(e))
	for e: Dictionary in p.get("mutants", []):
		var m: Node3D = _enemy(MUTANT_SCRIPT.new(), e)
		for k: String in ["leash_radius", "aggro_radius"]:
			if e.has(k):
				m.set(k, e[k])
		enc.add_enemy(m, _enemy_xf(e))
	for e: Dictionary in p.get("enemies", []):
		var other := enemy_of_type(String(e.get("type", "")))
		if other == null:
			continue
		other.set_meta("enemy_type", String(e.get("type", "")))
		for k: String in e:
			if k not in ["type", "at", "yaw", "wake"] and k in other:
				other.set(k, e[k])
		enc.add_enemy(_enemy(other, e), _enemy_xf(e))
	encounters.append(enc)


## A new enemy of `type` ("raider", "mutant", or any kind enemies/ adds
## later, like "drone" or "trooper": res://enemies/<type>.gd, same contract
## as Raider). Until a kind exists, troopers stand in as raiders and the
## rest are left out. Null if there's nothing to spawn.
static func enemy_of_type(type: String) -> Node3D:
	if type == "raider":
		return RAIDER_SCRIPT.new()
	if type == "mutant":
		return MUTANT_SCRIPT.new()
	var path := "res://enemies/%s.gd" % type
	if type != "" and ResourceLoader.exists(path):
		var script: Script = load(path)
		var e: Object = script.new()
		if e is Node3D:
			return e
		push_warning("MissionBuilder: %s is not a 3D enemy" % path)
		return null
	if type in STAND_INS:
		return enemy_of_type(STAND_INS[type])
	return null


static func _enemy(e: Node3D, d: Dictionary) -> Node3D:
	e.wake_delay = d.get("wake", 0.0)
	return e


static func _enemy_xf(d: Dictionary) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(d.get("yaw", 0.0))), vec(d.get("at", [0, 0, 0])))
