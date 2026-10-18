class_name MissionRun
extends Node
## Runs a mission's rules on top of a level: the clock, checkpoints, falls,
## objectives in order, collectible tapes, the pursuer in a chase, and the
## result at the end. Everything ticks with physics (after the player), so a
## run is deterministic: the same input gives the same time and result.
##
## Only reads the player, apart from respawning it at a checkpoint after a
## fall or a catch. Story lines are not played here: it emits `event` and the
## RadioFeed decides what to say.

enum Phase { READY, RUNNING, COMPLETE }

## A named moment the radio can react to: "start", "go", "objective:N"
## (objective N became active), "done:N", "checkpoint:N", "fall", "caught",
## "tape", "kill", "kill:<enemy type>", "headshot", "combo", "bail", "down"
## (enemies took you down), "fate:spared" / "fate:not_spared" (a boss like
## Juno was beaten and you chose), "complete".
signal event(name: String)
signal objective_changed(index: int)
signal completed(result: Dictionary)

## Distance from the start that starts the clock.
const START_DISTANCE := 1.5
## How close you need to get to a tape to pick it up.
const TAPE_RADIUS := 1.4
## A banked combo at this multiplier or more is worth a radio reaction.
const COMBO_REACTION_MULTIPLIER := 4

var phase := Phase.READY
var ticks := 0
var falls := 0
var catches := 0
## Times enemies took you down.
var downs := 0
## Started from a checkpoint key, so the result isn't saved.
var practice := false
## Index into builder.spawns: 0 is the start, then each checkpoint.
var checkpoint := 0
## Index of the active objective in `objectives`.
var objective := 0
var objectives: Array = []
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
var _start_pos := Vector3.ZERO


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
		enc.reset_done.connect(_on_encounter_reset)
		for e: Node in enc.enemies:
			e.killed.connect(_on_target_killed.bind(String(e.get_meta("enemy_type", ""))))
			if e.has_signal("fate_decided"):
				e.fate_decided.connect(func(fate: String) -> void: event.emit("fate:" + fate))
	var health := p.get_node_or_null("PlayerHealth")
	if health != null:
		health.died.connect(_on_player_down)
	if mission.has("pursuer"):
		pursuer = Pursuer.new()
		pursuer.name = "Pursuer"
		pursuer.configure(mission.pursuer)
		add_child(pursuer)
	_start_pos = b.spawns[0].origin
	_reset_run(0)


## Starts the mission: call after connecting to `event` (the radio).
func begin() -> void:
	event.emit("start")
	_begin_objective(0)


func seconds() -> float:
	return ticks / float(Engine.physics_ticks_per_second)


func fail_y() -> float:
	return mission.get("fail_y", -50.0)


func par_seconds() -> float:
	return mission.get("par_seconds", 0.0)


func current_objective() -> Dictionary:
	return objectives[objective] if objective < objectives.size() else {}


## What the HUD shows for the active objective, with progress.
func objective_text() -> String:
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
	if player == null or phase == Phase.COMPLETE:
		return
	var pos := player.global_position
	if phase == Phase.READY:
		if Vector2(pos.x - _start_pos.x, pos.z - _start_pos.z).length() > START_DISTANCE:
			phase = Phase.RUNNING
			event.emit("go")
	if phase == Phase.RUNNING:
		ticks += 1
	if pos.y < fail_y():
		falls += 1
		_back_to_checkpoint()
		event.emit("fall")
		return
	_check_checkpoints(pos)
	_check_tapes(pos)
	if pursuer != null and phase == Phase.RUNNING:
		pursuer.tick(pos, 1.0 / Engine.physics_ticks_per_second)
		if pursuer.has_caught():
			catches += 1
			_back_to_checkpoint()
			event.emit("caught")
			return
	_check_objective(pos)


# ---------------------------------------------------------------- objectives

func _begin_objective(i: int) -> void:
	objective = i
	_kills_at = kills
	_headshots_at = headshots
	_multiplier_since = 0
	objective_changed.emit(i)
	if i < objectives.size():
		event.emit("objective:%d" % i)


func _check_objective(pos: Vector3) -> void:
	var o := current_objective()
	if o.is_empty() or phase == Phase.READY and o.get("type", "reach") == "reach":
		return
	var done := false
	match String(o.get("type", "reach")):
		"reach":
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
	if done:
		event.emit("done:%d" % objective)
		if objective + 1 >= objectives.size():
			_complete()
		else:
			_begin_objective(objective + 1)


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
		"falls": falls,
		"catches": catches,
		"downs": downs,
		"tapes": tapes_found.duplicate(),
		"total_tapes": total_tapes(),
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
			player.set_spawn(builder.spawns[checkpoint])
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


func _back_to_checkpoint() -> void:
	_respawning = true
	player.respawn(builder.spawns[checkpoint])
	_respawning = false
	if pursuer != null:
		pursuer.reset(builder.spawns[checkpoint].origin)


func _on_respawned() -> void:
	if _respawning:
		return
	# Backspace goes back to the last checkpoint: the run carries on. A zone
	# key that lands somewhere else starts a practice run from there.
	var index := 0
	var best := INF
	for i in builder.spawns.size():
		var d := builder.spawns[i].origin.distance_to(player.global_position)
		if d < best:
			best = d
			index = i
	if index == checkpoint and phase != Phase.READY:
		if pursuer != null:
			pursuer.reset(builder.spawns[checkpoint].origin)
		return
	_reset_run(index)
	if index > 0:
		var cps: Array = mission.get("checkpoints", [])
		_begin_objective(cps[index - 1].get("objective", objective) if index - 1 < cps.size() else objective)
	else:
		_begin_objective(0)


func _reset_run(index: int) -> void:
	phase = Phase.READY
	ticks = 0
	falls = 0
	catches = 0
	downs = 0
	checkpoint = index
	practice = index != 0
	tapes_found.clear()
	for t: Dictionary in builder.tapes:
		if is_instance_valid(t.node):
			(t.node as Node3D).visible = true
	_start_pos = builder.spawns[index].origin
	player.set_spawn(builder.spawns[index])
	if pursuer != null:
		pursuer.reset(_start_pos)
	for enc: Node3D in builder.encounters:
		enc.reset()


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


## Going down to enemies sends you back to the last checkpoint (the
## encounter has already reset), not to the encounter's entrance.
func _on_encounter_started() -> void:
	var health := player.get_node_or_null("PlayerHealth")
	if health != null:
		health.respawn_point = builder.spawns[checkpoint]


## An encounter's enemies came back: a shoot objective counts again from
## here, so kills from before don't count twice.
func _on_encounter_reset() -> void:
	if current_objective().get("type", "") == "shoot":
		_kills_at = kills
		_headshots_at = headshots


func _on_player_down() -> void:
	downs += 1
	if pursuer != null:
		pursuer.reset(builder.spawns[checkpoint].origin)
	event.emit("down")
