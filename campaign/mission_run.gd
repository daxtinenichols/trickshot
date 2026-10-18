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
## Points for each bonus goal finished.
const BONUS_POINTS := 1000

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
## Index of the active (required) objective in `objectives`.
var objective := 0
var objectives: Array = []
## Bonus goals opened this run: objective index -> {"kills_at",
## "headshots_at", "until" (the required objective that closes it), "done",
## "closed"}.
var bonuses := {}
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
		enc.reset_done.connect(_on_encounter_reset.bind(enc))
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
	event.connect(_save_choice)
	_reset_run(0)


## A boss's fate ("fate:spared") is a story choice later missions remember
## (not from a practice run).
func _save_choice(e: String) -> void:
	if e.begins_with("fate:") and not practice and mission_index >= 0:
		Campaign.set_choice(mission_index, "fate", e.substr(5))


## Starts the mission: call after connecting to `event` (the radio).
func begin() -> void:
	event.emit("start")
	_begin_objective(0)


func seconds() -> float:
	return ticks / float(Engine.physics_ticks_per_second)


func fail_y() -> float:
	return mission.get("fail_y", -50.0)


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
		if String(o.get("type", "")) == "shoot":
			var need: int = o.get("count", 1)
			text = text if text != "" else "Take down %d" % need
			text += "  done" if b.done else "  (%d / %d)" % [mini(_bonus_progress(i), need), need]
		elif b.done:
			text += "  done"
		lines.append("Bonus: " + text)
	return "\n".join(lines)


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
	if pos.y < fail_y() or _in_pit(pos):
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
		_close_bonuses(objective)
		if _next_required(objective + 1) >= objectives.size():
			_complete()
		else:
			_begin_objective(objective + 1)


func _next_required(i: int) -> int:
	while i < objectives.size() and is_bonus(objectives[i]):
		i += 1
	return i


func _open_bonus(i: int) -> void:
	if bonuses.has(i):
		return
	bonuses[i] = {"kills_at": kills, "headshots_at": headshots, "until": _next_required(i + 1),
		"done": false, "closed": false}
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
		if done:
			b.done = true
			if combo != null:
				combo.score += BONUS_POINTS
			event.emit("done:%d" % i)


func _bonus_progress(i: int) -> int:
	var b: Dictionary = bonuses[i]
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
		"falls": falls,
		"catches": catches,
		"downs": downs,
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
	bonuses.clear()
	for t: Dictionary in builder.tapes:
		if is_instance_valid(t.node):
			(t.node as Node3D).visible = true
	_start_pos = builder.spawns[index].origin
	player.set_spawn(builder.spawns[index])
	if pursuer != null:
		pursuer.reset(_start_pos)
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


## Going down to enemies sends you back to the last checkpoint (the
## encounter has already reset), not to the encounter's entrance.
func _on_encounter_started() -> void:
	var health := player.get_node_or_null("PlayerHealth")
	if health != null:
		health.respawn_point = builder.spawns[checkpoint]


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
	downs += 1
	if pursuer != null:
		pursuer.reset(builder.spawns[checkpoint].origin)
	event.emit("down")
