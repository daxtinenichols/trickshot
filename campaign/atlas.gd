extends RefCounted
## The city atlas: the whole city in one set of world coordinates
## (campaign/atlas.json, written by campaign/tools/make_atlas.py: edit the
## script, not the JSON). A level is a route through it: a mission with
## "atlas": true lays its route from its "route_origin" in atlas
## coordinates, and Route.expand calls here around building the city:
##
##   before_city  adds the landmarks the level runs through ("atlas_pieces":
##                the Line camp's warehouse) as buildings, and leaves the
##                water open (no city on the harbour; a fall in is a fall)
##   after_city   takes city buildings off the water, then adds one
##                "skyline" piece: the atlas beyond the level's own city,
##                out to SKY_RANGE, as merged boxes with no collision, the
##                courses of the levels either side of it (so the district
##                behind you and the next one ahead are the real ones), the
##                water, the Silt's bed and the broadcast tower, which every
##                level shows (campaign/atlas_skyline.gd draws it).
##
## Levels in campaign order meet: each one's "route_origin" is where the
## one before it ends (tests/test_campaign.gd checks it).
##
## Loaded by path (no class_name).

const PATH := "res://campaign/atlas.json"
const CAMPAIGN_PATH := "res://campaign/campaign.json"
const ROUTE_PATH := "res://campaign/route.gd"
const SPEED_GATE_PATH := "res://campaign/speed_gate.gd"
const City := preload("res://campaign/city.gd")
## How far past the level the skyline reaches (the camera sees 600 m).
const SKY_RANGE := 560.0
## The level's own city: its ground plus city.gd's horizon band (48 m
## blocks just past the ground). The skyline starts outside it.
const NEAR_BAND := 52.0
## Sea level as drawn: just over the street, which is the floor under a level.
const WATER_TOP := 0.08
## The tower stays in sight from a level's "tower_views" ([[x, y, z], ...]
## where you stand; its start and end if it has none): city and skyline blocks
## on the line from there to the tower come down below it, aimed this high
## on the tower (its top floors, stripes and mast show). Buildings within
## VIEW_GUARD of the course stay CLEAR above it (they wall the course in).
const VIEW_AT := 190.0
const VIEW_GUARD := 24.0
const VIEW_SLOT := 3.0
const VIEW_FLOOR := 4.0

static var _data := {}
## Course footprints of atlas levels, by mission id (for their neighbours'
## skylines): [[x, z, sx, sz, y0, y1, shade, yaw], ...].
static var _courses := {}
## Atlas levels in campaign order: [[id, file], ...].
static var _order: Array = []


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f == null:
			push_error("Atlas: no %s" % PATH)
			return {}
		var d: Variant = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			_data = d
	return _data


static func landmark(id: String) -> Dictionary:
	for l: Dictionary in data().get("landmarks", []):
		if l.id == id:
			return l
	return {}


## The district a point (x, z) is in, or {}.
static func district_at(x: float, z: float) -> Dictionary:
	for d: Dictionary in data().get("districts", []):
		var r: Array = d.rect
		if x >= r[0] and x < r[2] and z >= r[1] and z < r[3]:
			return d
	return {}


## True if (x, z) is over open water (the harbour, the reservoir).
static func in_water(x: float, z: float) -> bool:
	for w: Dictionary in data().get("water", []):
		if Geometry2D.is_point_in_polygon(Vector2(x, z), _poly(w.poly)):
			return true
	return false


static func _poly(a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Array in a:
		out.append(Vector2(p[0], p[1]))
	return out


# ---------------------------------------------------------------- the level

## Before the city is built round a level: its landmarks and open water.
static func before_city(mission: Dictionary, ground: Rect2) -> void:
	var pieces: Array = mission.pieces
	for id: String in mission.get("atlas_pieces", []):
		var l := landmark(id)
		if l.is_empty():
			push_error("Atlas: no landmark %s" % id)
			continue
		for b: Array in l.boxes:
			pieces.append({"building": [b[0], b[5], b[1]], "size": [b[2], b[3]], "look": l.get("look", "FACADE"), "atlas": id})
	var open: Array = mission.get("city_open", []).duplicate()
	for w: Dictionary in data().get("water", []):
		var r := _bounds(w.poly).intersection(ground.grow(80.0))
		if r.has_area():
			open.append([r.position.x, r.position.y, r.end.x, r.end.y])
	for o: Dictionary in data().get("open", []):
		var r: Array = o.rect
		if ground.intersects(Rect2(r[0], r[1], r[2] - r[0], r[3] - r[1])):
			open.append(r.duplicate())
	if not open.is_empty():
		mission.city_open = open


## After the city: off the water, and the skyline. `first` is the index of
## the first piece the city added, `course` the level's own footprint.
static func after_city(mission: Dictionary, first: int, ground: Rect2, course: Rect2, lanes: Array = []) -> void:
	var pieces: Array = mission.pieces
	var kept: Array = pieces.slice(0, first)
	for i in range(first, pieces.size()):
		var p: Dictionary = pieces[i]
		var at: Variant = p.get("building", p.get("at", null))
		if at is Array and in_water(float(at[0]), float(at[2])):
			continue
		kept.append(p)
	mission.pieces = kept
	var views := tower_views(mission)
	_open_views(mission, first, views, lanes)
	mission.pieces.append(skyline(mission, ground, course, views))


## Where the tower must be in sight from: eyes over "tower_views", or over
## the start and the end.
static func tower_views(mission: Dictionary) -> Array:
	var out: Array = []
	var pts: Array = mission.get("tower_views", []).duplicate()
	if not mission.has("tower_views"):
		if mission.get("start", {}).has("at"):
			pts.append(mission.start.at)
		if mission.has("route_end"):
			pts.append(mission.route_end)
	for a: Array in pts:
		out.append(Vector3(a[0], float(a[1]) + 1.7, a[2]))
	return out


## Brings city buildings on a view line down under it (and their roof props
## with them), except next to the course.
static func _open_views(mission: Dictionary, first: int, views: Array, lanes: Array) -> void:
	var t: Dictionary = data().get("tower", {})
	if views.is_empty() or t.is_empty() or not mission.get("atlas_tower", true):
		return
	# Next to the course a building keeps city.gd's promise: CLEAR above
	# the course beside it, so nobody climbs out.
	var guard: Array = []
	for a: Dictionary in lanes:
		var c := absf(cos(a.yaw))
		var s := absf(sin(a.yaw))
		var h := Vector2(c * a.h.x + s * a.h.y, s * a.h.x + c * a.h.y)
		guard.append([Rect2(a.c - h, h * 2.0).grow(VIEW_GUARD), maxf(float(a.top), 0.0) + City.CLEAR + 0.5])
	var tower := Vector2(t.at[0], t.at[1])
	var pieces: Array = mission.pieces
	for i in range(first, pieces.size()):
		var p: Dictionary = pieces[i]
		if not p.get("city", false) or not p.has("building"):
			continue
		var r := Rect2(p.building[0] - p.size[0] * 0.5, p.building[2] - p.size[1] * 0.5, p.size[0], p.size[1])
		var low := VIEW_FLOOR
		for gr: Array in guard:
			if (gr[0] as Rect2).intersects(r):
				low = maxf(low, gr[1])
		var h := snappedf(maxf(view_cap(r, views, tower), low), 0.5)
		var old: float = p.building[1]
		if h >= old:
			continue
		p.building[1] = h
		# Its roof prop, if it has one, comes down with it.
		if i + 1 < pieces.size() and pieces[i + 1].has("prop") and pieces[i + 1].at[1] == old \
				and pieces[i + 1].at[0] == p.building[0] and pieces[i + 1].at[2] == p.building[2]:
			pieces[i + 1].at[1] = h


## The highest a box over `r` may stand and keep every view line to the
## tower clear (INF when no line crosses it).
static func view_cap(r: Rect2, views: Array, tower: Vector2) -> float:
	var cap := INF
	for eye: Vector3 in views:
		var a := Vector2(eye.x, eye.z)
		var d := tower - a
		var dd := d.length_squared()
		if dd < 1.0:
			continue
		var tc := clampf((r.get_center() - a).dot(d) / dd, 0.0, 1.0)
		# The slot widens to the tower's width at the tower.
		var g := r.grow(VIEW_SLOT + float(data().tower.size[0]) * 0.5 * tc)
		if not _segment_hits(a, tower, g):
			continue
		var tn := 1.0
		for k in 4:
			var q := g.position + Vector2(g.size.x * (k % 2), g.size.y * (k / 2))
			tn = minf(tn, clampf((q - a).dot(d) / dd, 0.0, 1.0))
		cap = minf(cap, eye.y + (VIEW_AT - eye.y) * tn)
	return cap


static func _segment_hits(a: Vector2, b: Vector2, r: Rect2) -> bool:
	if r.has_point(a) or r.has_point(b):
		return true
	var c := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for k in 4:
		if Geometry2D.segment_intersects_segment(a, b, c[k], c[(k + 1) % 4]) != null:
			return true
	return false


## The "skyline" piece for a level: everything of the atlas between the
## level's own city and SKY_RANGE past its course.
static func skyline(mission: Dictionary, ground: Rect2, course: Rect2, views: Array = []) -> Dictionary:
	var near := ground.grow(NEAR_BAND)
	var reach := course.grow(SKY_RANGE)
	var own: Array = mission.get("atlas_pieces", [])
	var boxes: Array = []
	var courses := _neighbour_courses(String(mission.get("id", "")))
	var course_rects: Array[Rect2] = []
	for b: Array in courses:
		course_rects.append(_rect(b).grow(3.0))
	# The levels either side: their roofs, exactly.
	for b: Array in courses:
		var r := _rect(b)
		if reach.intersects(r) and not near.intersects(r):
			boxes.append(b)
	# Landmarks: whole or not at all. Visual ones (cranes over the water)
	# also stand close to the level, where they touch nothing of it.
	var solid: Array[Rect2] = []
	for p: Dictionary in mission.pieces:
		if p.has("building"):
			solid.append(Rect2(p.building[0] - p.size[0] * 0.5, p.building[2] - p.size[1] * 0.5, p.size[0], p.size[1]))
	for l: Dictionary in data().get("landmarks", []):
		if l.id in own:
			continue
		var parts: Array = []
		var ok := true
		for b: Array in l.boxes:
			var r := Rect2(b[0] - b[2] * 0.5, b[1] - b[3] * 0.5, b[2], b[3])
			if near.intersects(r) and not (l.get("visual", false) and not _hits(r, solid)):
				ok = false
				break
			parts.append([b[0], b[1], b[2], b[3], b[4], b[5], l.get("shade", 1), 0.0])
		if ok and reach.intersects(_bounds_of(parts)):
			boxes.append_array(parts)
	# Every other building, rough.
	for b: Array in data().get("blocks", []):
		var yaw: float = b[6] if b.size() > 6 else 0.0
		var box := [b[0], b[1], b[2], b[3], 0.0, b[4], b[5], yaw]
		var r := _rect(box)
		if not reach.intersects(r) or near.intersects(r) or _hits(r.grow(-1.0), course_rects):
			continue
		if not views.is_empty() and mission.get("atlas_tower", true):
			var cap := view_cap(r, views, Vector2(data().tower.at[0], data().tower.at[1]))
			if cap < float(box[5]):
				box[5] = maxf(cap, VIEW_FLOOR)
		boxes.append(box)
	var waters: Array = []
	for w: Dictionary in data().get("water", []):
		var r := _bounds(w.poly).intersection(reach)
		if r.has_area():
			# Round the level the floor is the street (y 0): the harbour lies
			# just on it.
			var y: float = w.y
			waters.append([r.position.x, r.position.y, r.end.x, r.end.y, WATER_TOP if y < 1.0 else y])
	var silt: Dictionary = data().get("silt", {})
	var bed: Array = []
	var path: Array = silt.get("path", [])
	for i in range(path.size() - 1):
		var a := Vector2(path[i][0], path[i][1])
		var b := Vector2(path[i + 1][0], path[i + 1][1])
		if reach.intersects(Rect2(a, Vector2.ZERO).expand(b).grow(silt.get("width", 60.0))):
			bed.append([a.x, a.y, b.x, b.y, float(silt.get("width", 60.0))])
	var t: Dictionary = data().get("tower", {})
	return {"skyline": true, "boxes": boxes, "water": waters, "silt": bed,
		"ground": [course.get_center().x, course.get_center().y, maxf(course.size.x, course.size.y) * 0.5 + SKY_RANGE + 60.0],
		"tower": [t.at[0], t.at[1], t.size[0], t.height, t.mast] if not t.is_empty() and mission.get("atlas_tower", true) else []}


## The axis-aligned rect round a skyline box [x, z, sx, sz, y0, y1, shade, yaw].
static func _rect(b: Array) -> Rect2:
	var yaw := deg_to_rad(float(b[7])) if b.size() > 7 else 0.0
	var c := absf(cos(yaw))
	var s := absf(sin(yaw))
	var sx: float = c * b[2] + s * b[3]
	var sz: float = s * b[2] + c * b[3]
	return Rect2(b[0] - sx * 0.5, b[1] - sz * 0.5, sx, sz)


static func _bounds_of(boxes: Array) -> Rect2:
	var r := Rect2()
	for i in boxes.size():
		r = _rect(boxes[i]) if i == 0 else r.merge(_rect(boxes[i]))
	return r


static func _bounds(poly: Array) -> Rect2:
	var r := Rect2(poly[0][0], poly[0][1], 0, 0)
	for p: Array in poly:
		r = r.expand(Vector2(p[0], p[1]))
	return r


static func _hits(r: Rect2, rects: Array[Rect2]) -> bool:
	for o: Rect2 in rects:
		if o.intersects(r):
			return true
	return false


# ---------------------------------------------------------------- neighbours

## Atlas levels in campaign order: [[id, file], ...].
static func order() -> Array:
	if _order.is_empty():
		var f := FileAccess.open(CAMPAIGN_PATH, FileAccess.READ)
		var c: Variant = JSON.parse_string(f.get_as_text()) if f != null else null
		if c is Dictionary:
			for act: Dictionary in c.get("acts", []):
				for m: Dictionary in act.get("missions", []):
					var raw := _raw(String(m.get("file", "")))
					if raw.get("atlas", false):
						_order.append([String(m.id), String(m.file)])
	return _order


## A mission file as written (route not laid out).
static func _raw(path: String) -> Dictionary:
	if path == "" or not FileAccess.file_exists(path):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.open(path, FileAccess.READ).get_as_text())
	return d if d is Dictionary else {}


## The roofs of the atlas levels just before and after `id`.
static func _neighbour_courses(id: String) -> Array:
	var all := order()
	var out: Array = []
	for i in all.size():
		if all[i][0] != id:
			continue
		for j: int in [i - 1, i + 1]:
			if j >= 0 and j < all.size():
				out.append_array(course_of(all[j][0], all[j][1]))
	return out


## A level's own roofs as skyline boxes: its route laid out with no city.
static func course_of(id: String, path: String) -> Array:
	if _courses.has(id):
		return _courses[id]
	var m: Dictionary = (load(SPEED_GATE_PATH) as Script).call("prepare", _raw(path))
	m.skyline = false
	var route: Script = load(ROUTE_PATH)
	route.call("expand", m)
	var out: Array = []
	for p: Dictionary in m.get("pieces", []):
		if p.has("atlas") or p.has("city"):
			continue
		if p.has("building"):
			out.append([p.building[0], p.building[2], p.size[0], p.size[1], 0.0, p.building[1], 1, float(p.get("yaw", 0.0))])
		elif p.has("slab"):
			var r := Rect2(p.slab[0][0], p.slab[0][1], 0, 0)
			for a: Array in p.slab:
				r = r.expand(Vector2(a[0], a[1]))
			out.append([r.get_center().x, r.get_center().y, r.size.x, r.size.y, 0.0, float(p.get("top", 6.0)), 1, 0.0])
	_courses[id] = out
	return out
