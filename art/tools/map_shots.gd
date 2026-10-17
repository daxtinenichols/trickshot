extends SceneTree
## Renders overview shots of the maps (art look on), for review:
##   xvfb-run godot --path . -s res://art/tools/map_shots.gd -- <out_dir> [name_prefix]

const SHOTS := [
	# [scene, camera position, look at, name]
	["res://maps/rooftops.tscn", Vector3(-9, 19, 8), Vector3(0, 10, -40), "rooftops_start"],
	["res://maps/rooftops.tscn", Vector3(-10, 20, -42), Vector3(2, 10, -90), "rooftops_middle"],
	["res://maps/rooftops.tscn", Vector3(-12, 17, -112), Vector3(0, 4, -160), "rooftops_end"],
	["res://maps/rooftops.tscn", Vector3(1.5, 11.7, -61), Vector3(6, 11, -80), "rooftops_fp_wallrun"],
	["res://maps/combo_park.tscn", Vector3(0, 55, 62), Vector3(0, 0, -8), "park_overview"],
	["res://maps/combo_park.tscn", Vector3(-18, 9, 26), Vector3(0, 3, 0), "park_tower"],
	["res://maps/combo_park.tscn", Vector3(-22, 6, 14), Vector3(-38, 3, -2), "park_half_pipe"],
	["res://maps/combo_park.tscn", Vector3(16, 6, 20), Vector3(34, 3, -30), "park_loop"],
	["res://maps/combo_park.tscn", Vector3(-26, 5, 50), Vector3(-36, 1, 10), "park_banks"],
	["res://maps/mall.tscn", Vector3(-12, 7, 46), Vector3(0, 4, 8), "mall_outside"],
	["res://maps/mall.tscn", Vector3(-3, 8.2, -6), Vector3(2, 3, -40), "mall_atrium"],
	["res://maps/mall.tscn", Vector3(0, 1.7, -8), Vector3(-4, 3, -28), "mall_escalators"],
	["res://maps/mall.tscn", Vector3(-1, 1.7, -42), Vector3(1, 3, -62), "mall_billboards"],
	["res://maps/mall.tscn", Vector3(15, 7.7, -26), Vector3(17, 6, -46), "mall_collapse"],
	["res://maps/mall.tscn", Vector3(14, 1.7, -14), Vector3(19, 1.6, -40), "mall_shops"],
	["res://maps/mall.tscn", Vector3(-6, 3.2, -71), Vector3(8, 1.5, -86), "mall_food_court"],
	["res://maps/mall.tscn", Vector3(4, 7.9, -71.5), Vector3(-20, 6.6, -73), "mall_camp"],
]

var out := "user://map_shots"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	var only := args[1] if args.size() > 1 else ""
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	var current := ""
	var level: Node = null
	for s: Array in SHOTS:
		if not (s[3] as String).begins_with(only):
			continue
		if s[0] != current:
			if level != null:
				level.queue_free()
				await _frames(2)
			current = s[0]
			level = load(current).instantiate()
			root.add_child(level)
			var p: Node = level.get_node("Player")
			p.use_device_input = false
			await _frames(5)
			for c in level.find_children("*", "CanvasLayer", true, false):
				(c as CanvasLayer).visible = false
		var cam := Camera3D.new()
		cam.cull_mask &= ~4  # skip the first-person gun (Pistol.VIEW_LAYER)
		cam.fov = 75.0
		cam.far = 400.0
		level.add_child(cam)
		cam.look_at_from_position(s[1], s[2])
		cam.make_current()
		await _frames(10)
		root.get_texture().get_image().save_png(out.path_join(s[3] + ".png"))
		print("saved ", s[3])
		cam.queue_free()
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame
