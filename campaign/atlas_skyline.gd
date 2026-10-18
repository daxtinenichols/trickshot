extends Node3D
## The city beyond a level, from the atlas (campaign/atlas.gd makes the
## "skyline" piece; MissionBuilder loads this by path): every building as
## one merged mesh with no collision, a ground under it, the harbour, the
## Silt's dry bed, and the broadcast tower. Further than the camera sees,
## the tower is drawn as a scaled copy on the line to the real one (same
## size on screen), so it stands on the skyline from every level.
## Visual only.

## Where the far tower's copy stands (the camera sees 600 m).
const PROXY_AT := 520.0
## Far off, the copy looms this much bigger than the real thing would, so
## it reads on the skyline (it is ~5 degrees tall from the Docks).
const LOOM := 1.6
## Ground under the skyline: a little below the street, so the level's own
## floor always wins where they overlap.
const GROUND_Y := -0.35
const SILT_Y := -0.25
const SHADES := [
	Color(0.47, 0.42, 0.37),  # 0 docks brick and render
	Color(0.52, 0.50, 0.47),  # 1 concrete
	Color(0.43, 0.40, 0.36),  # 2 low town
	Color(0.38, 0.40, 0.43),  # 3 towers, glass gone dark
	Color(0.42, 0.30, 0.22),  # 4 rusted steel (cranes, rails)
]
const GROUND := Color(0.30, 0.28, 0.26)
const WATER := Color(0.20, 0.26, 0.28)
const DUST := Color(0.62, 0.53, 0.41)
const HAZE := Color(0.86, 0.72, 0.54)

const BUILDING_SHADER := """
shader_type spatial;
render_mode cull_back;
varying vec3 wp;
varying vec3 wn;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec3 c = COLOR.rgb;
	if (abs(wn.y) < 0.5) {
		// Floors every 3.2 m, a window every 3 m along the wall.
		float along = abs(wn.x) > 0.5 ? wp.z : wp.x;
		float fy = fract(wp.y / 3.2);
		float fx = fract(along / 3.0);
		float win = step(0.35, fy) * step(fy, 0.8) * step(0.2, fx) * step(fx, 0.8) * step(2.5, wp.y);
		c *= mix(1.0, 0.45, win);
	} else {
		c *= 0.9;
	}
	ALBEDO = c;
	ROUGHNESS = 0.95;
}
"""

const PROXY_SHADER := """
shader_type spatial;
render_mode fog_disabled, unshaded;
uniform vec4 color : source_color;
uniform float glow = 0.0;
void fragment() {
	ALBEDO = color.rgb;
	EMISSION = color.rgb * glow;
}
"""

var data := {}
var tower: Node3D
var _tower_at := Vector3.ZERO
var _far := false


func setup(p: Dictionary) -> void:
	data = p


func _ready() -> void:
	name = "Skyline"
	_build_city()
	_build_ground()
	_build_tower()


func _process(_delta: float) -> void:
	if not _far or tower == null:
		return
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	if cam == null:
		return
	_place_proxy(cam.global_position)


## Puts the tower's copy PROXY_AT m from `eye` on the line to the real
## tower, scaled so it covers the same angle.
func _place_proxy(eye: Vector3) -> void:
	var d := _tower_at - eye
	var k := PROXY_AT / maxf(Vector2(d.x, d.z).length(), PROXY_AT)
	# Grown from its foot, which stays on the line to the real one's.
	tower.global_position = eye + d * k
	tower.scale = Vector3.ONE * k * (LOOM if k < 1.0 else 1.0)


# ---------------------------------------------------------------- city

func _build_city() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 0
	for b: Array in data.get("boxes", []):
		var shade: Color = SHADES[clampi(int(b[6]), 0, SHADES.size() - 1)]
		# A little variety per building, the same every time.
		var v := float(hash(Vector2i(int(b[0] * 10.0), int(b[1] * 10.0))) % 1000) / 1000.0
		shade = shade.lightened(v * 0.12) if v > 0.5 else shade.darkened((0.5 - v) * 0.18)
		_box(st, Vector3(b[0], (float(b[4]) + float(b[5])) * 0.5, b[1]), Vector3(b[2], float(b[5]) - float(b[4]), b[3]),
			deg_to_rad(float(b[7])) if b.size() > 7 else 0.0, shade, float(b[4]) > 0.1)
		n += 1
	if n == 0:
		return
	var mi := MeshInstance3D.new()
	mi.name = "Buildings"
	mi.mesh = st.commit()
	var sh := Shader.new()
	sh.code = BUILDING_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## A box (center, size, yaw) as triangles with vertex color; `bottom` also
## closes its underside (a crane's beam seen from below).
func _box(st: SurfaceTool, c: Vector3, s: Vector3, yaw: float, col: Color, bottom: bool) -> void:
	var b := Basis(Vector3.UP, yaw)
	var h := s * 0.5
	var faces := [
		[Vector3.UP, Vector3.RIGHT, Vector3.FORWARD, h.y, h.x, h.z],
		[Vector3.RIGHT, Vector3.BACK, Vector3.UP, h.x, h.z, h.y],
		[Vector3.LEFT, Vector3.FORWARD, Vector3.UP, h.x, h.z, h.y],
		[Vector3.BACK, Vector3.LEFT, Vector3.UP, h.z, h.x, h.y],
		[Vector3.FORWARD, Vector3.RIGHT, Vector3.UP, h.z, h.x, h.y],
	]
	if bottom:
		faces.append([Vector3.DOWN, Vector3.LEFT, Vector3.FORWARD, h.y, h.x, h.z])
	for f: Array in faces:
		var nrm: Vector3 = b * (f[0] as Vector3)
		var u: Vector3 = b * (f[1] as Vector3) * float(f[4])
		var w: Vector3 = b * (f[2] as Vector3) * float(f[5])
		var o: Vector3 = c + nrm * float(f[3])
		_quad(st, o - u - w, o + u - w, o + u + w, o - u + w, nrm, col)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, nrm: Vector3, col: Color) -> void:
	# Wound so the face looks out along nrm.
	var flip := (b - a).cross(c - a).dot(nrm) > 0.0
	for p: Vector3 in ([a, c, b, a, d, c] if flip else [a, b, c, a, c, d]):
		st.set_color(col)
		st.set_normal(nrm)
		st.add_vertex(p)


# ---------------------------------------------------------------- ground

func _build_ground() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var g: Array = data.get("ground", [])
	if g.size() == 3:
		var c := Vector3(g[0], GROUND_Y, g[1])
		var r: float = g[2]
		_quad(st, c + Vector3(-r, 0, -r), c + Vector3(r, 0, -r), c + Vector3(r, 0, r), c + Vector3(-r, 0, r), Vector3.UP, GROUND)
	for w: Array in data.get("water", []):
		var y: float = w[4]
		_quad(st, Vector3(w[0], y, w[1]), Vector3(w[2], y, w[1]), Vector3(w[2], y, w[3]), Vector3(w[0], y, w[3]), Vector3.UP, WATER)
	for s: Array in data.get("silt", []):
		var a := Vector3(s[0], SILT_Y, s[1])
		var b := Vector3(s[2], SILT_Y, s[3])
		var side := (b - a).cross(Vector3.UP).normalized() * float(s[4]) * 0.5
		# Run each stretch on a little so the bends close.
		var on := (b - a).normalized() * float(s[4]) * 0.5
		_quad(st, a - on - side, a - on + side, b + on + side, b + on - side, Vector3.UP, DUST)
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# ---------------------------------------------------------------- tower

func _build_tower() -> void:
	var t: Array = data.get("tower", [])
	if t.size() < 5:
		return
	_tower_at = Vector3(t[0], 0.0, t[1])
	var g: Array = data.get("ground", [0, 0, 0])
	_far = Vector2(t[0] - g[0], t[1] - g[1]).length() > PROXY_AT
	tower = Node3D.new()
	tower.name = "Tower"
	add_child(tower)
	var w: float = t[2]
	var h: float = t[3]
	var mast: float = t[4]
	# Far away it is a hazy silhouette whatever the fog says.
	var concrete := HAZE.lerp(Color(0.42, 0.40, 0.38), 0.45) if _far else Color(0.50, 0.48, 0.45)
	var red := HAZE.lerp(Color(0.72, 0.16, 0.12), 0.6) if _far else Color(0.72, 0.16, 0.12)
	var white := HAZE.lerp(Color(0.9, 0.88, 0.84), 0.6) if _far else Color(0.9, 0.88, 0.84)
	_part(Vector3(0, h * 0.5, 0), Vector3(w, h, w), concrete, 0.0)
	for i in 4:
		_part(Vector3(0, h - 3.0 - i * 4.0, 0), Vector3(w + 0.6, 4.0, w + 0.6), red if i % 2 == 0 else white, 0.0)
	_part(Vector3(0, h + 2.0, 0), Vector3(w * 0.7, 4.0, w * 0.7), concrete, 0.0)
	_part(Vector3(0, h + mast * 0.5, 0), Vector3(2.5, mast, 2.5), concrete.darkened(0.2), 0.0)
	_part(Vector3(0, h + mast + 1.0, 0), Vector3(3.0, 3.0, 3.0), Color(1.0, 0.15, 0.1), 4.0)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_part(Vector3(sx * w * 0.5, h + 0.8, sz * w * 0.5), Vector3(1.6, 1.6, 1.6), Color(1.0, 0.15, 0.1), 3.0)
	tower.position = _tower_at
	if _far:
		_place_proxy(Vector3(g[0], 10.0, g[1]))


func _part(c: Vector3, s: Vector3, col: Color, glow: float) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = s
	mi.mesh = bm
	mi.position = c
	if _far or glow > 0.0:
		var sh := Shader.new()
		sh.code = PROXY_SHADER
		var mat := ShaderMaterial.new()
		mat.shader = sh
		mat.set_shader_parameter("color", col)
		mat.set_shader_parameter("glow", glow)
		mi.material_override = mat
	else:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = col
		mat.roughness = 0.9
		mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tower.add_child(mi)
