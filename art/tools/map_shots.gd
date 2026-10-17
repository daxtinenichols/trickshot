extends SceneTree
## Renders overview shots of the maps (art look on), for review:
##   xvfb-run godot --path . -s res://art/tools/map_shots.gd -- <out_dir> [name_prefix]

const SHOTS := [
	# [scene, camera position, look at, name]
	["res://levels/sandbox.tscn", Vector3(-121, 1.7, -2), Vector3(-122, 1.0, -22), "sandbox_range"],
	["res://levels/sandbox.tscn", Vector3(16, 2.2, -4), Vector3(20, 0.6, -24), "sandbox_vaults"],
	["res://levels/sandbox.tscn", Vector3(34, 4.5, 2), Vector3(42, 1.5, -30), "sandbox_mantles"],
	["res://levels/sandbox.tscn", Vector3(66, 2.5, -2), Vector3(70, 3, -30), "sandbox_wallrun"],
	["res://levels/sandbox.tscn", Vector3(-32, 3, 4), Vector3(-20, 3, -25), "sandbox_climb"],
	["res://levels/sandbox.tscn", Vector3(-62, 4, 6), Vector3(-55, 1, -20), "sandbox_slide"],
	["res://maps/rooftops.tscn", Vector3(-9, 19, 8), Vector3(0, 10, -40), "rooftops_start"],
	["res://maps/rooftops.tscn", Vector3(-10, 20, -42), Vector3(2, 10, -90), "rooftops_middle"],
	["res://maps/rooftops.tscn", Vector3(-12, 17, -112), Vector3(0, 4, -160), "rooftops_end"],
	["res://maps/rooftops.tscn", Vector3(1.5, 11.7, -61), Vector3(6, 11, -80), "rooftops_fp_wallrun"],
	["res://maps/rooftops.tscn", Vector3(-10, 14, -180), Vector3(0, 4, -270), "rooftops_sprint"],
	["res://maps/rooftops.tscn", Vector3(-4, 10, -318), Vector3(-14, 7.5, -366), "rooftops_corner"],
	["res://maps/rooftops.tscn", Vector3(-12, 12, -366), Vector3(-60, 8, -369), "rooftops_split"],
	["res://maps/rooftops.tscn", Vector3(-62, 12.5, -378), Vector3(-104, 12, -380), "rooftops_high_line"],
	["res://maps/rooftops.tscn", Vector3(-90, 9, -360), Vector3(-150, 4.5, -360), "rooftops_low_line"],
	["res://maps/rooftops.tscn", Vector3(-150, 12, -372), Vector3(-200, 7.5, -400), "rooftops_second_corner"],
	["res://maps/rooftops.tscn", Vector3(-202, 10, -440), Vector3(-198, 9.5, -500), "rooftops_step_up"],
	["res://maps/rooftops.tscn", Vector3(-201, 13, -520), Vector3(-198, 10, -580), "rooftops_fork"],
	["res://maps/rooftops.tscn", Vector3(-206, 14, -600), Vector3(-196, 4, -700), "rooftops_finish"],
	["res://maps/rooftops.tscn", Vector3(60, 170, 40), Vector3(-90, 0, -400), "rooftops_overview"],
	["res://maps/combo_park.tscn", Vector3(0, 55, 62), Vector3(0, 0, -8), "park_overview"],
	["res://maps/combo_park.tscn", Vector3(5.5, 1.8, 9.5), Vector3(8, 1.1, 6), "park_target"],
	["res://maps/combo_park.tscn", Vector3(28, 2.5, -10), Vector3(26, 3, -28), "park_loop_close"],
	["res://maps/combo_park.tscn", Vector3(-18, 9, 26), Vector3(0, 3, 0), "park_tower"],
	["res://maps/combo_park.tscn", Vector3(-22, 6, 14), Vector3(-38, 3, -2), "park_half_pipe"],
	["res://maps/combo_park.tscn", Vector3(16, 6, 20), Vector3(34, 3, -30), "park_loop"],
	["res://maps/combo_park.tscn", Vector3(-26, 5, 50), Vector3(-36, 1, 10), "park_banks"],
	["res://maps/combo_park.tscn", Vector3(0, 70, 40), Vector3(0, 0, -200), "park_long"],
	["res://maps/combo_park.tscn", Vector3(-3, 2.5, -72), Vector3(0, 1, -130), "park_canal"],
	["res://maps/combo_park.tscn", Vector3(-6, 5, -200), Vector3(2, 2, -260), "park_alley"],
	["res://maps/combo_park.tscn", Vector3(-8, 4, -298), Vector3(0, 1, -360), "park_rollers"],
	["res://maps/combo_park.tscn", Vector3(44, 9, -60), Vector3(56, 4, -110), "park_high_road"],
	["res://maps/combo_park.tscn", Vector3(48, 11, -186), Vector3(58, 8, -240), "park_high_road_wall"],
	["res://maps/combo_park.tscn", Vector3(12, 10, -425), Vector3(-10, 5, -490), "park_overpass"],
	["res://maps/combo_park.tscn", Vector3(-30, 14, -470), Vector3(-25, 5, -510), "park_overpass_gap"],
	["res://maps/mall.tscn", Vector3(0, 2.0, -342), Vector3(-2, 4, -370), "mall_store_well"],
	["res://maps/mall.tscn", Vector3(8, 8.5, -344), Vector3(0, 2, -372), "mall_store_well_above"],
	["res://maps/mall.tscn", Vector3(-12, 7, 46), Vector3(0, 4, 8), "mall_outside"],
	["res://maps/mall.tscn", Vector3(-3, 8.2, -6), Vector3(2, 3, -40), "mall_atrium"],
	["res://maps/mall.tscn", Vector3(0, 1.7, -8), Vector3(-4, 3, -28), "mall_escalators"],
	["res://maps/mall.tscn", Vector3(-1, 1.7, -42), Vector3(1, 3, -62), "mall_billboards"],
	["res://maps/mall.tscn", Vector3(15, 7.7, -26), Vector3(17, 6, -46), "mall_collapse"],
	["res://maps/mall.tscn", Vector3(14, 1.7, -14), Vector3(19, 1.6, -40), "mall_shops"],
	["res://maps/mall.tscn", Vector3(-6, 3.2, -71), Vector3(8, 1.5, -86), "mall_food_court"],
	["res://maps/mall.tscn", Vector3(4, 7.9, -71.5), Vector3(-20, 6.6, -73), "mall_camp"],
	["res://maps/mall.tscn", Vector3(-3, 8.2, -99), Vector3(0, 3, -200), "mall_concourse"],
	["res://maps/mall.tscn", Vector3(0, 1.7, -160), Vector3(3, 2.5, -230), "mall_concourse_ground"],
	["res://maps/mall.tscn", Vector3(-12, 3, -343), Vector3(4, 3.5, -385), "mall_store"],
	["res://maps/mall.tscn", Vector3(-6, 9, -342), Vector3(4, 6, -390), "mall_store_upper"],
	["res://maps/mall.tscn", Vector3(-4, 3, -404), Vector3(2, 1, -450), "mall_dock"],
	["res://maps/mall.tscn", Vector3(14, 15.2, -368), Vector3(0, 14, -430), "mall_roof"],
	["res://maps/mall.tscn", Vector3(-6, 16, -420), Vector3(10, 14, -350), "mall_roof_back"],
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
		cam.far = 1200.0 if (s[3] as String).ends_with("overview") else 400.0
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
