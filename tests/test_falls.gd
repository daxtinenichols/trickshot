extends TestCase
## What ends a run as a fall, on every level. A fall is down off the course
## with nothing of it under you; standing on anything (a kerb, a crate, a
## low roof) never is. FallProbe (campaign/tools/fall_probe_core.gd) floods
## each level from its start and checkpoints and checks every top you can
## get to: run `campaign/tools/fall_probe.gd` to see where a failure is.

const MISSION := preload("res://campaign/mission.tscn")
const FallProbe := preload("res://campaign/tools/fall_probe_core.gd")
## Hard landings tried per level (spread over every top you can reach).
const DROPS := 40

var level: Node3D
var player: Player
var run: MissionRun


func before_each() -> void:
	Campaign.persist = false
	Campaign.reset_progress()
	Campaign.unlock_all = true


func after_each() -> void:
	if is_instance_valid(level):
		level.queue_free()
	level = null
	for n: Node in tree.root.get_children():
		if n.scene_file_path == MISSION.resource_path:
			n.queue_free()
	await tree.process_frame


func _load(id: String) -> void:
	level = await FallProbe.load_level(tree, id)
	player = level.get_node("Player")
	player.scripted_input = InputFrame.new()
	player.set_physics_process(true)
	run = level.run


## The Yard's pavement beside a street sits below its pits line: it ended
## the run as a fall the moment you stepped on it.
func test_a_kerb_below_the_pits_line_holds_you_up() -> void:
	await _load("l1_2_the_yard")
	var at := Vector3(3408.5, 0.2, 240.5)
	check(at.y < run.fail_y() or run._in_pit(at), "this kerb is below the line (the old rule called it a fall)")
	player.global_position = at + Vector3(0, 0.05, 0)
	for i in 30:
		await tree.physics_frame
	check(run.phase != MissionRun.Phase.LOST and run.falls == 0, "standing on it isn't a fall (%s, y %.2f)" % [run.lost_reason, player.global_position.y])


## Down on the bare ground off the course still is, and so is the void.
func test_bare_ground_off_the_course_is_still_a_fall() -> void:
	await _load("l1_2_the_yard")
	var report := FallProbe.probe(level)
	check(not report.ground_falls.is_empty(), "the Yard has pits to fall in")
	if report.ground_falls.is_empty():
		return
	var at: Vector3 = report.ground_falls[0]
	check(run.is_fall(at + Vector3(0, 0.05, 0)), "the ground in a pit is a fall (%s)" % at)
	check(run.is_fall(Vector3(at.x, MissionRun.LOWEST_FAIL_Y - 1.0, at.z)), "under the world always is")
	player.global_position = at + Vector3(0, 0.05, 0)
	for i in 3:
		await tree.physics_frame
	check(run.phase == MissionRun.Phase.LOST and run.lost_reason == "fall", "the run ends (%s)" % run.lost_reason)


## Every level: nowhere you can stand counts as a fall, nothing that looks
## like floor is empty, no slot between two floors to drop into, and a
## hard landing never goes through.
func test_no_level_has_false_falls_or_holes() -> void:
	for m: Dictionary in Campaign.missions():
		await _load(m.id)
		var report := FallProbe.probe(level)
		check(report.reached > 500, "%s: the probe gets round the course (%d tops)" % [m.id, report.reached])
		for b: AABB in FallProbe.cluster(report.false_falls):
			check(false, "%s: standing here counts as a fall: %s" % [m.id, b])
		for p: Vector3 in report.no_floor:
			check(false, "%s: floor with nothing solid in it at %s (%s)" % [m.id, p.snapped(Vector3.ONE * 0.1), report.no_floor_what[p]])
		for b: AABB in FallProbe.cluster(report.seams):
			check(false, "%s: a slot between two floors: %s" % [m.id, b])
		var tops: Array = report.standable
		var sample: Array[Vector3] = []
		for i in range(0, tops.size(), maxi(tops.size() / DROPS, 1)):
			sample.append(tops[i])
		for p: Vector3 in await FallProbe.drop_through(tree, level, sample):
			check(false, "%s: a hard landing goes through the floor at %s" % [m.id, p])
		level.queue_free()
		level = null
		await tree.process_frame
