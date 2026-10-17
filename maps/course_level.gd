extends "res://levels/sandbox.gd"
## The rooftop course: the sandbox's player, HUD and menu, plus the course
## timer.

var timer: CourseTimer


func _ready() -> void:
	super()
	timer = CourseTimer.new()
	add_child(timer)
	timer.setup(player, builder as RooftopCourseBuilder, hud)
	hud.show_toast("Run toward the green line. 1-4: start and checkpoints", 4.0)
