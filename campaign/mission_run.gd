class_name MissionRun
extends Node
## Runs a mission's rules on top of a level: the clock, checkpoints, falls,
## objectives in order, bonus goals, collectible tapes, the pursuer in a
## chase, and the result at the end. Everything ticks with physics (after the player), so a
## run is deterministic: the same input gives the same time and result.
##
## Kill goals never stand between you and the finish: a "shoot" objective
## is a bonus goal (unless it says "optional": false, like the yard's
## lessons), and any objective with "optional": true is one too. The chain
## steps over bonuses, so you win by reaching the end; a bonus opens when
## the chain reaches it, stays open until the next required objective is
## done, and pays BONUS_POINTS if you finish it in time.
##
## Losing (going down to enemies, falling, being caught in the chase) ends
## the attempt: the run stops (Phase.LOST) and emits `lost`, and MissionLevel
## restarts the whole mission from its start. Backspace asks for a restart
## the same way. Checkpoints are progress markers (radio cues, objective
## steps, the dev practice start), not places you come back to.
##
## Only reads the player. Story lines are not played here: it emits `event`
## and the RadioFeed decides what to say.

enum Phase { READY, RUNNING, COMPLETE, LOST }

## A named moment the radio can react to: "start", "go", "objective:N"
## (objective N became active), "done:N", "checkpoint:N", "fall", "caught",
## "tape", "kill", "kill:<enemy type>", "headshot", "combo", "bail", "down"
## (enemies took you down), "fate:spared" / "fate:not_spared" (a boss like
## Juno was beaten and you chose), an enemy's own story events like
## "host:hit" and "host:hit:1" (see _on_story_event), a set piece going off
## ("set_piece:<kind>", counted the same way), "complete".
signal event(name: String)
signal objective_changed(index: int)
signal completed(result: Dictionary)
## The attempt is over: "fall", "caught", "down", or "restart" (Backspace).
signal lost(reason: String)

## Distance from the start that starts the clock.
const START_DISTANCE := 1.5
## How close you need to get to a tape to pick it up.
const TAPE_RADIUS := 1.4
## The player respawns itself below y = -40 (Player._physics_process), so a
## fall has to be noticed well above that (even falling a metre a tick).
const LOWEST_FAIL_Y := -30.0
## Below fail_y or in a pit you've only fallen once nothing but the bare
## ground is under you: anything solid this close below your feet (a
## crate, a kerb, a low roof) holds you up.
const HOLD_DEPTH := 4.0
## The bare ground: the route's ground slab (kind FLOOR) this low.
const GROUND_TOP := 0.5
## A banked combo at this multiplier or more is worth a radio reaction.
const COMBO_REACTION_MULTIPLIER := 4
## Points for each bonus goal finished.
const BONUS_POINTS := 1000
## A delivery's base points, into the running combo (so speed scales it).
const DELIVERY_POINTS := 500
const DROP_OFF_SCRIPT := "res://campaign/drop_off.gd"

var phase := Phase.READY
var ticks := 0
## How this attempt was lost (each is 0 or 1: a loss ends the run).
var falls := 0
var catches := 0
## Times enemies took you down.
var downs := 0
## Attempts before this one (MissionLevel carries it across restarts).
var restarts := 0
## Why the run was lost ("" while it isn't).
var lost_reason := ""
## Started from a checkpoint key, so the result isn't saved.
var practice := false
## Index into builder.spawns: 0 is the start, then each checkpoint.
var checkpoint := 0
## The spawn this run started from (0, or a practice start).
var start_index := 0
## Index of the active (required) objective in `objectives`.
var objective := 0
var objectives: Array = []
## Bonus goals opened this run: objective index -> {"kills_at",
## "headshots_at", "until" (the required objective that closes it), "done",
## "closed"}.
var bonuses := {}
## How often each enemy story event (`_on_story_event`) happened this run.
var event_counts := {}
var tapes_found: Array[String] = []
var kills := 0
var headshots := 0
var best_combo := 0
var best_multiplier := 0
var result := {}

var mission: Dictionary
var mission_index := -1
var player: Player
var builder: MissionBuilder
var combo: ComboTracker
var pursuer: Pursuer

## Counters when the active objective began, so it counts from there.
var _kills_at := 0
var _headshots_at := 0
var _multiplier_since := 0
var _respawning := false
## Pursuer gap under which "host_near" fires.
const NEAR_GAP := 6.0
var _host_near := false
var _start_pos := Vector3.ZERO
## "deliver" objective index -> its drop-off (campaign/drop_off.gd).
var drop_offs := {}


func setup(p: Player, b: MissionBuilder, c: ComboTracker = null, index := -1) -> void:
	player = p
	builder = b
	combo = c
	mission = b.mission
	mission_index = index
	objectives = mission.get("objectives", [])
	process_physics_priority = 10  # after the player's tick
	player.respawned.connect(_on_respawned)
	if combo != null:
		combo.banked.connect(_on_banked)
		combo.bailed.connect(func(_points: int, _reason: StringName) -> void: event.emit("bail"))
	for t in b.find_children("*", "ShootingTarget", true, false):
		(t as ShootingTarget).killed.connect(_on_target_killed)
	for enc: Node3D in b.encounters:
		enc.setup(p)
		enc.started.connect(_on_encounter_started)
		enc.reset_done.connect(_on_encounter_reset.bind(enc))
		for e: Node in enc.enemies:
			e.killed.connect(_on_target_killed.bind(String(e.get_meta("enemy_type", ""))))
			if e.has_signal("fate_decided"):
				e.fate_decided.connect(func(fate: String) -> void: event.emit("fate:" + fate))
			if e.has_signal("story_event"):
				e.story_event.connect(_on_story_event)
	var health := p.get_node_or_null("PlayerHealth")
	if health != null:
		health.respawn_on_down = false
		health.died.connect(_on_player_down)
	if mission.has("pursuer"):
		pursuer = Pursuer.new()
		pursuer.name = "Pursuer"
		pursuer.configure(mission.pursuer)
		add_child(pursuer)
	for sp: Node3D in b.set_pieces:
		sp.went.connect(func(kind: String) -> void:
			if kind == "host":
				event.emit("host_close")
			else:
				_on_story_event("set_piece:" + kind))
	# Set pieces that wait for a mission event ("on") rather than a place.
	event.connect(func(e: String) -> void:
		for sp: Node3D in builder.set_pieces:
			if sp.has_method("on_event"):
				sp.on_event(e, self))
	for i in objectives.size():
		if String(objectives[i].get("type", "")) == "deliver":
			var d: Node3D = (load(DROP_OFF_SCRIPT) as Script).new()
			d.name = "DropOff_%d" % i
			b.add_child(d)
			d.setup(objectives[i], carry_object(), b)
			drop_offs[i] = d
	_start_pos = b.spawns[0].origin
	event.connect(_save_choice)
	event.connect(_carry_event)
	_reset_run(0)


## An enemy's own story moment, like the Host's "host:hit" (Head Office): played
## as is and numbered across the run ("host:hit:1", "host:hit:2"), so the
## radio can answer the first and the second differently.
func _on_story_event(e: String) -> void:
	event_counts[e] = int(event_counts.get(e, 0)) + 1
	event.emit(e)
	event.emit("%s:%d" % [e, event_counts[e]])


## A boss's fate ("fate:spared") is a story choice later missions remember
## (not from a practice run). So is whatever the mission's "remember" names
## ({"host:hit": "host_hit"}): "yes" once it happens, "no" from the start.
func _save_choice(e: String) -> void:
	if practice or mission_index < 0:
		return
	if e.begins_with("fate:"):
		Campaign.set_choice(mission_index, "fate", e.substr(5))
	var remember: Dictionary = mission.get("remember", {})
	if e == "start":
		for k: String in remember:
			Campaign.set_choice(mission_index, String(remember[k]), "no")
	elif remember.has(e):
		Campaign.set_choice(mission_index, String(remember[e]), "yes")


## Starts the mission: call after connecting to `event` (the radio).
func begin() -> void:
	event.emit("start")
	_begin_objective(0)


func seconds() -> float:
	return ticks / float(Engine.physics_ticks_per_second)


func fail_y() -> float:
	return maxf(mission.get("fail_y", -50.0), LOWEST_FAIL_Y)


## Off the course with nothing of it under you: below fail_y or in a pit,
## and not standing on (or just over) anything but the bare ground. Never
## while you're on a prop, a piece or a roof, however low it is.
## `floors`: what you're standing on (Player's floor contacts), if anything.
func is_fall(pos: Vector3, floors: Array = []) -> bool:
	if pos.y < LOWEST_FAIL_Y:
		return true
	if pos.y >= fail_y() and not _in_pit(pos):
		return false
	return not held_up(pos, floors)


## Something other than the bare ground under you: one of `floors`, or
## the first thing straight down within HOLD_DEPTH.
func held_up(pos: Vector3, floors: Array = []) -> bool:
	for b: Object in floors:
		if not is_bare_ground(b, pos.y):
			return true
	if player == null or not player.is_inside_tree():
		return false
	var space := player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.3, 0), pos - Vector3(0, HOLD_DEPTH, 0), 1)
	var hit := space.intersect_ray(q)
	return not hit.is_empty() and not is_bare_ground(hit.collider, (hit.position as Vector3).y)


static func is_bare_ground(body: Object, top: float) -> bool:
	return body != null and body.has_meta("kind") and String(body.get_meta("kind")) == "FLOOR" and top < GROUND_TOP


## What the player is standing on now (walkable contacts of its last move).
func _floor_bodies() -> Array:
	var out: Array = []
	if player == null or not player.is_on_floor():
		return out
	for i in player.get_slide_collision_count():
		var c := player.get_slide_collision(i)
		if c.get_normal().y > 0.6:
			out.append(c.get_collider())
	return out


## Down off the course (low, and not on any of its streets): see "pits"
## in docs/missions.md.
func _in_pit(pos: Vector3) -> bool:
	var pits: Dictionary = mission.get("pits", {})
	if pits.is_empty() or pos.y >= float(pits.y):
		return false
	for r: Dictionary in pits.streets:
		if inside(r, pos):
			return false
	return true


func par_seconds() -> float:
	return mission.get("par_seconds", 0.0)


func current_objective() -> Dictionary:
	return objectives[objective] if objective < objectives.size() else {}


## True for an objective you don't need for the win: kill goals ("shoot")
## unless they say "optional": false, and anything with "optional": true.
static func is_bonus(o: Dictionary) -> bool:
	if o.has("optional"):
		return bool(o.optional)
	return String(o.get("type", "reach")) == "shoot"


## Bonus goals finished this run.
func bonuses_done() -> int:
	return bonuses.values().filter(func(b: Dictionary) -> bool: return b.done).size()


## Bonus goals in the whole mission.
func total_bonuses() -> int:
	return objectives.filter(func(o: Dictionary) -> bool: return is_bonus(o)).size()


## What the HUD shows for the open bonus goals, with progress.
func bonus_text() -> String:
	var lines: Array[String] = []
	for i: int in bonuses:
		var b: Dictionary = bonuses[i]
		if b.closed:
			continue
		var o: Dictionary = objectives[i]
		var text: String = o.get("text", "")
		if String(o.get("type", "")) == "shoot" or String(o.get("type", "")) == "event" and int(o.get("count", 1)) > 1:
			var need: int = o.get("count", 1)
			text = text if text != "" else "Take down %d" % need
			text += "  done" if b.done else "  (%d / %d)" % [mini(_bonus_progress(i), need), need]
		elif b.done:
			text += "  done"
		lines.append("Bonus: " + text)
	return "\n".join(lines)


## What the HUD shows for the active objective, with progress.
func objective_text() -> String:
	if phase == Phase.COMPLETE:
		# Not the last goal any more: you're there (the radio may still talk).
		return "Level complete"
	var o := current_objective()
	if o.is_empty():
		return ""
	var text: String = o.get("text", "")
	match String(o.get("type", "reach")):
		"score":
			text = text if text != "" else "Score %d points" % int(o.points)
			text += "  (%d / %d)" % [mini(_score(), int(o.points)), int(o.points)]
		"combo":
			text = text if text != "" else "Land a x%d combo" % int(o.multiplier)
		"shoot":
			var need: int = o.get("count", 1)
			var have := _shoot_progress(o)
			text = text if text != "" else "Take down %d targets" % need
			text += "  (%d / %d)" % [mini(have, need), need]
		"collect":
			text = text if text != "" else "Find the tapes"
			text += "  (%d / %d)" % [tapes_found.size(), int(o.get("count", builder.tapes.size()))]
		_:
			if text == "":
				text = "Reach %s" % o.get("name", "the marker")
	return text


func total_tapes() -> int:
	return builder.tapes.size()


func _physics_process(_delta: float) -> void:
	if player == null:
		return
	if phase == Phase.COMPLETE or phase == Phase.LOST:
		# The chase is over: he stops (or holds you, if he caught you).
		if pursuer != null:
			pursuer.hold(player.global_position, 1.0 / Engine.physics_ticks_per_second)
		if phase == Phase.COMPLETE:
			# An ending set piece (the bridge going) plays out after the win.
			for sp: Node3D in builder.set_pieces:
				if sp.has_method("busy") and sp.busy():
					sp.tick(player.global_position, self)
		return
	var pos := player.global_position
	if phase == Phase.READY:
		if Vector2(pos.x - _start_pos.x, pos.z - _start_pos.z).length() > START_DISTANCE:
			phase = Phase.RUNNING
			event.emit("go")
	if phase == Phase.RUNNING:
		ticks += 1
	if is_fall(pos, _floor_bodies()):
		falls += 1
		_lose("fall")
		return
	_check_checkpoints(pos)
	_check_tapes(pos)
	if pursuer != null and phase == Phase.RUNNING:
		pursuer.tick(pos, 1.0 / Engine.physics_ticks_per_second)
		if pursuer.has_caught():
			catches += 1
			pursuer.catch(pos)
			_lose("caught")
			return
		# He's on your back: the radio can react (once until you pull away).
		if not _host_near and pursuer.gap < NEAR_GAP:
			_host_near = true
			event.emit("host_near")
		elif _host_near and pursuer.gap > NEAR_GAP + 4.0:
			_host_near = false
	if phase == Phase.RUNNING:
		for sp: Node3D in builder.set_pieces:
			sp.tick(pos, self)
	_check_bonuses(pos)
	_check_objective(pos)


# ---------------------------------------------------------------- objectives

## Makes objective i active, stepping over (and opening) any bonus goals on
## the way to the next required one.
func _begin_objective(i: int) -> void:
	while i < objectives.size() and is_bonus(objectives[i]):
		_open_bonus(i)
		i += 1
	objective = i
	_kills_at = kills
	_headshots_at = headshots
	_multiplier_since = 0
	objective_changed.emit(i)
	if i < objectives.size():
		event.emit("objective:%d" % i)


func _check_objective(pos: Vector3) -> void:
	var o := current_objective()
	if o.is_empty() or phase == Phase.READY and o.get("type", "reach") in ["reach", "deliver"]:
		return
	var done := false
	match String(o.get("type", "reach")):
		"reach":
			done = inside(o, pos) or _reached_later(pos)
		"deliver":
			# Only by going through the drop-off: reaching a later goal
			# never counts a delivery you ran past.
			done = inside(o, pos)
		"score":
			done = _score() >= int(o.points)
		"combo":
			done = _multiplier_since >= int(o.multiplier)
		"shoot":
			done = _shoot_progress(o) >= int(o.get("count", 1))
		"clear":
			done = encounter_cleared(String(o.get("encounter", "")))
		"duel":
			done = _duel_done(o, pos)
		"collect":
			done = tapes_found.size() >= int(o.get("count", builder.tapes.size()))
		"event":
			done = int(event_counts.get(String(o.get("event", "")), 0)) >= int(o.get("count", 1))
	if done:
		if drop_offs.has(objective):
			_deliver(objective)
		event.emit("done:%d" % objective)
		_close_bonuses(objective)
		if _next_required(objective + 1) >= objectives.size():
			_complete()
		else:
			_begin_objective(objective + 1)


## True when you're already in a later "reach" goal than the active one
## (the high line, or a shortcut, ran past the active one's region): the
## goals before it count as reached, so nobody is sent back for them.
func _reached_later(pos: Vector3) -> bool:
	var i := _next_required(objective + 1)
	while i < objectives.size() and String(objectives[i].get("type", "reach")) == "reach":
		if inside(objectives[i], pos):
			return true
		i = _next_required(i + 1)
	return false


func _next_required(i: int) -> int:
	while i < objectives.size() and is_bonus(objectives[i]):
		i += 1
	return i


func _open_bonus(i: int) -> void:
	if bonuses.has(i):
		return
	# "until": "end" keeps a bonus open for the rest of the mission.
	var until := objectives.size() if objectives[i].get("until", "") == "end" else _next_required(i + 1)
	bonuses[i] = {"kills_at": kills, "headshots_at": headshots, "until": until,
		"events_at": event_counts.get(String(objectives[i].get("event", "")), 0), "done": false, "closed": false}
	event.emit("objective:%d" % i)


## The required objective `index` is done: bonuses open until then close.
func _close_bonuses(index: int) -> void:
	for i: int in bonuses:
		if bonuses[i].until == index:
			bonuses[i].closed = true


func _check_bonuses(pos: Vector3) -> void:
	if phase == Phase.READY:
		return
	for i: int in bonuses:
		var b: Dictionary = bonuses[i]
		if b.done or b.closed:
			continue
		var o: Dictionary = objectives[i]
		var done := false
		match String(o.get("type", "reach")):
			"shoot":
				done = _bonus_progress(i) >= int(o.get("count", 1))
			"reach":
				done = inside(o, pos)
			"score":
				done = _score() >= int(o.points)
			"clear":
				done = encounter_cleared(String(o.get("encounter", "")))
			"collect":
				done = tapes_found.size() >= int(o.get("count", builder.tapes.size()))
			"event":
				done = _bonus_progress(i) >= int(o.get("count", 1))
		if done:
			b.done = true
			if combo != null:
				combo.score += BONUS_POINTS
			event.emit("done:%d" % i)


func _bonus_progress(i: int) -> int:
	var b: Dictionary = bonuses[i]
	if objectives[i].get("type", "") == "event":
		return int(event_counts.get(String(objectives[i].get("event", "")), 0)) - int(b.events_at)
	if objectives[i].get("headshots", false):
		return headshots - int(b.headshots_at)
	return kills - int(b.kills_at)


## True once the encounter with this id is cleared (every enemy down, or out
## of the fight like a spared Juno).
func encounter_cleared(id: String) -> bool:
	for enc: Node3D in builder.encounters:
		if enc.get_meta("id", "") == id:
			return enc.phase == enc.Phase.CLEARED
	return false


## A boss duel (Juno) ends when she's shot down or you reach her: within
## `radius` m she concedes. Either way the spare-or-not choice follows.
func _duel_done(o: Dictionary, pos: Vector3) -> bool:
	var boss := duel_boss(String(o.get("encounter", "")))
	if boss == null:
		return true
	if boss.get("is_beaten") or boss.get("is_dead"):
		return true
	if boss.global_position.distance_to(pos) <= float(o.get("radius", 4.0)):
		boss.concede()
		return true
	return false


## The enemy in that encounter who can concede (Juno), or null.
func duel_boss(id: String) -> Node3D:
	for enc: Node3D in builder.encounters:
		if enc.get_meta("id", "") == id:
			for e: Node in enc.enemies:
				if e.has_method("concede"):
					return e
	return null


func _shoot_progress(o: Dictionary) -> int:
	if o.get("headshots", false):
		return headshots - _headshots_at
	return kills - _kills_at


func _score() -> int:
	return combo.score if combo != null else 0


## True when `pos` is inside a region: {"at", "size"} is a box (turned
## `area_yaw` degrees, if set), {"at", "radius"} a cylinder 3 m up and down.
static func inside(region: Dictionary, pos: Vector3) -> bool:
	var at := MissionBuilder.vec(region.get("at", [0, 0, 0]))
	if region.has("size"):
		var half := MissionBuilder.vec(region.size) * 0.5
		# A region on a diagonal leg of a route is turned by area_yaw.
		var d := (Basis(Vector3.UP, -deg_to_rad(float(region.get("area_yaw", 0.0)))) * (pos - at)).abs()
		return d.x <= half.x and d.y <= half.y and d.z <= half.z
	var r: float = region.get("radius", 6.0)
	return Vector2(pos.x - at.x, pos.z - at.z).length() <= r and absf(pos.y - at.y) <= 3.0


func _complete() -> void:
	phase = Phase.COMPLETE
	result = {
		"ticks": ticks,
		"seconds": seconds(),
		"score": _score(),
		"best_combo": best_combo,
		"restarts": restarts,
		"tapes": tapes_found.duplicate(),
		"total_tapes": total_tapes(),
		"bonuses": bonuses_done(),
		"total_bonuses": total_bonuses(),
		"par_seconds": par_seconds(),
		"practice": practice,
		"records": {},
	}
	if not practice and mission_index >= 0:
		result.records = Campaign.record(mission_index, result)
	event.emit("complete")
	completed.emit(result)


# ---------------------------------------------------------------- checkpoints

func _check_checkpoints(pos: Vector3) -> void:
	var cps: Array = mission.get("checkpoints", [])
	# Checkpoints are in order; reaching a later one skips the ones before.
	for i in range(checkpoint, cps.size()):
		if inside(cps[i], pos):
			checkpoint = i + 1
			event.emit("checkpoint:%d" % i)
			break


func _check_tapes(pos: Vector3) -> void:
	for t: Dictionary in builder.tapes:
		if t.id in tapes_found:
			continue
		if pos.distance_to((t.position as Vector3) + Vector3(0, 0.9, 0)) <= TAPE_RADIUS:
			tapes_found.append(t.id)
			if is_instance_valid(t.node):
				(t.node as Node3D).visible = false
			event.emit("tape")


## Ends the attempt: the radio hears `reason` (as an event, except a
## restart), and MissionLevel restarts the mission (see `lost`).
func _lose(reason: String) -> void:
	if phase == Phase.LOST or phase == Phase.COMPLETE:
		return
	phase = Phase.LOST
	lost_reason = reason
	if reason != "restart":
		event.emit(reason)
	lost.emit(reason)


func _on_respawned() -> void:
	if phase == Phase.LOST or phase == Phase.COMPLETE:
		return
	# Backspace (or the player's own fall respawn) lands on this run's start:
	# restart the level. A zone key that lands on another spawn starts a
	# practice run from there.
	var index := 0
	var best := INF
	for i in builder.spawns.size():
		var d := builder.spawns[i].origin.distance_to(player.global_position)
		if d < best:
			best = d
			index = i
	if index == start_index:
		if phase != Phase.READY:
			_lose("restart")
		return
	start_practice(index)


## Starts a run from spawn `index` (0: the real start; later: a practice
## run that saves nothing), on that checkpoint's objective.
func start_practice(index: int) -> void:
	_reset_run(index)
	if index > 0:
		var cps: Array = mission.get("checkpoints", [])
		_begin_objective(cps[index - 1].get("objective", objective) if index - 1 < cps.size() else objective)
		# A practice start past a drop-off: already delivered.
		for i: int in drop_offs:
			if i < objective:
				_set_held(carry_then())
				drop_offs[i].show_delivered()
	else:
		_begin_objective(0)


func _reset_run(index: int) -> void:
	phase = Phase.READY
	ticks = 0
	falls = 0
	catches = 0
	downs = 0
	checkpoint = index
	start_index = index
	practice = index != 0
	lost_reason = ""
	tapes_found.clear()
	bonuses.clear()
	event_counts.clear()
	for t: Dictionary in builder.tapes:
		if is_instance_valid(t.node):
			(t.node as Node3D).visible = true
	_start_pos = builder.spawns[index].origin
	player.set_spawn(builder.spawns[index])
	if pursuer != null:
		pursuer.reset(_start_pos)
	_reset_set_pieces()
	_set_held(carry_object())
	for i: int in drop_offs:
		drop_offs[i].reset()
	# A fresh run: everyone is back, even the ones killed last time.
	for enc: Node3D in builder.encounters:
		enc.reset(true)


func _on_banked(_points: int, multiplier: int, total: int) -> void:
	best_combo = maxi(best_combo, total)
	best_multiplier = maxi(best_multiplier, multiplier)
	_multiplier_since = maxi(_multiplier_since, multiplier)
	if multiplier >= COMBO_REACTION_MULTIPLIER:
		event.emit("combo")


func _on_target_killed(info: Dictionary, type := "") -> void:
	kills += 1
	if type != "":
		# "kill:camera_drone": the radio can react to one kind of enemy.
		event.emit("kill:" + type)
	if info.get("zone", &"body") == &"head":
		headshots += 1
		event.emit("headshot")
	else:
		event.emit("kill")


## Going down to enemies loses the attempt; PlayerHealth leaves you where
## you fell (respawn_on_down is off) while the level fades and restarts.
func _on_encounter_started() -> void:
	var health := player.get_node_or_null("PlayerHealth")
	if health != null:
		health.respawn_on_down = false


## An encounter's enemies came back: a shoot objective (or an open kill
## bonus) counts again from here, so kills from before don't count twice.
## Killed enemies that stayed dead keep counting.
func _on_encounter_reset(enc: Node3D) -> void:
	if not enc.revived:
		return
	if current_objective().get("type", "") == "shoot":
		_kills_at = kills
		_headshots_at = headshots
	for i: int in bonuses:
		if not bonuses[i].done:
			bonuses[i].kills_at = kills
			bonuses[i].headshots_at = headshots


func _on_player_down() -> void:
	if phase == Phase.LOST or phase == Phase.COMPLETE:
		return
	downs += 1
	_lose("down")


## Set pieces play again on a new run.
func _reset_set_pieces() -> void:
	_host_near = false
	for sp: Node3D in builder.set_pieces:
		sp.reset()


# ---------------------------------------------------------------- carrying

## What the mission has you carry instead of the gun: its "carry" key, a
## kind ("parcel") or {"object", "until", "then"}. "gun" when there's none.
func carry_object() -> String:
	var c: Variant = mission.get("carry", "gun")
	return String(c.get("object", "gun")) if c is Dictionary else String(c)


## What the hands hold after a delivery or the "until" event: "hands"
## (nothing; Dawn Run runs home empty-handed) unless "then" says ("gun").
func carry_then() -> String:
	var c: Variant = mission.get("carry", "gun")
	return String(c.get("then", "hands")) if c is Dictionary else "hands"


## What's in the player's hands now ("gun" without a weapon node).
func held() -> String:
	var w: Node = player.weapon if player != null else null
	return String(w.held) if w != null and "held" in w else "gun"


func _set_held(kind: String) -> void:
	var w: Node = player.weapon if player != null else null
	if w != null and "held" in w:
		w.held = kind


## The carry's "until" event (e.g. "set_piece:handoff") swaps to "then".
func _carry_event(e: String) -> void:
	var c: Variant = mission.get("carry", null)
	if c is Dictionary and c.has("until") and e == String(c.until) and phase != Phase.READY:
		_set_held(carry_then())


## The object leaves your hands at drop-off `i`, tossed in on the run: you
## keep every bit of speed, the combo gets DELIVERED, the radio "delivered".
func _deliver(i: int) -> void:
	var from := player.global_position + Vector3.UP * 1.2
	if player.camera != null:
		from = player.camera.global_position - player.camera.global_basis.z * 0.4 + Vector3.DOWN * 0.25
	drop_offs[i].deliver(from, held())
	_set_held(carry_then())
	if combo != null:
		combo.add(&"delivered", DELIVERY_POINTS, player.horizontal_speed())
	event.emit("delivered")
