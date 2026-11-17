extends SceneTree
## Renders the body-dynamics scenarios (needs xvfb): standing, walking,
## single leg, chest bounce, back bounce, grabs, forward fall. Also measures
## the back-bounce leg angle above horizontal. Args: out_dir
var main; var a; var t := 0.0; var out := "/tmp"; var cam: Camera3D; var shots := {}; var log := []
var phase := 0; var pt := 0.0
const ORDER := ["stand", "walk", "one_leg", "chest", "back", "grab_knees", "grab_cross", "fall_fwd"]
func _initialize():
	var args := OS.get_cmdline_user_args(); if args.size() > 0: out = args[0]
	main = load("res://scenes/main.tscn").instantiate(); root.add_child(main)
func _shot(n: String) -> void:
	if shots.has(n): return
	root.get_viewport().get_texture().get_image().save_png(out.path_join("body_%s.png" % n)); shots[n] = true
func _bone(n: String) -> Vector3:
	var sk: Skeleton3D = a.visual.character.skel
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone(n)).origin
func _physics_process(d) -> bool:
	t += d; pt += d
	if a == null:
		a = main.get_node("Athlete"); a.input.override_enabled = true; a.visual.show_com = true
		main.get_node("LabPanel").visible = false
		cam = Camera3D.new(); cam.fov = 40; root.add_child(cam); cam.current = true
	var b = a.balance
	if phase < 6:
		a.input.override_balance = clampf(-(2.2 * b.theta + 0.6 * b.omega), -1, 1)
	var c := _bone("spine_01")
	var lat: Vector3 = main.line.lateral_axis()
	var side := 3.0
	cam.look_at_from_position(c + lat * side + Vector3.UP * 0.6 + main.line.axis() * 1.4, c)
	match phase:
		0:
			if pt > 1.5: _shot("stand"); phase = 1; pt = 0
		1:
			a.input.override_move = 1.0
			if pt > 3.0 and absf(sin(a.gait_phase)) > 0.9: _shot("walk"); a.input.override_move = 0.0; phase = 2; pt = 0
		2:
			if pt > 2.5:
				a.input.override_leg_lift = 1.0
			if pt > 3.6: _shot("one_leg"); a.input.override_leg_lift = 0.0; phase = 3; pt = 0
		3:
			if pt > 0.6 and a.pose == "" and a.state == 0: a.input.override_trick = "chest"
			if a.pose == "chest" and a._pose_visual == "chest" and a.pose_blend > 0.99 and a._pose_contacted: phase = 31; pt = 0
		31:
			if pt > 0.2: _shot("chest"); phase = 4; pt = 0
		4:
			if a.pose == "" and a.state == 0 and pt > 0.3: a.input.override_trick = "back"
			if a.pose == "back" and a._pose_visual == "back" and a.pose_blend > 0.99 and a._pose_contacted:
				var hip_mid := (_bone("thigh_l") + _bone("thigh_r")) * 0.5
				var knee_mid := (_bone("calf_l") + _bone("calf_r")) * 0.5
				var v := knee_mid - hip_mid
				var elev := rad_to_deg(atan2(v.y, Vector2(v.x, v.z).length()))
				var sep := rad_to_deg((_bone("calf_l") - _bone("thigh_l")).angle_to(_bone("calf_r") - _bone("thigh_r")))
				print("BACK BOUNCE: thighs %.0f deg above horizontal, V opening %.0f deg" % [elev, sep])
				phase = 41; pt = 0
		41:
			if pt > 0.25: _shot("back"); phase = 5; pt = 0
		5:
			# get airborne with the demo, then hold grabs
			main.demo.mode = "rikuto"
			if not main.demo.enabled: main.demo.set_enabled(true)
			if a.state == 1 and a.air_time > 0.15:
				a.input.override_grab = "both_knees" if not shots.has("grab_knees") else "cross"
				if a.tricks.grab_w > 0.99 and a.air_time > 0.45:
					if not shots.has("grab_knees"): _shot("grab_knees")
					elif a.tricks.grab == "cross" and a.air_time > 0.5: _shot("grab_cross")
			else:
				a.input.override_grab = ""
			if shots.has("grab_cross"): main.demo.set_enabled(false); a.input.override_enabled = true; phase = 6; pt = 0
		6:
			a.input.override_grab = ""
			if a.state == 0 and a.pose == "" and pt > 1.0 and pt < 1.1: b.phi_dot = 2.5
			if a.state == 2 and pt > 1.4: _shot("fall_fwd"); phase = 7
		7:
			_sheet(); return true
	return t > 120.0
func _sheet() -> void:
	var tiles: Array[Image] = []
	for n in ORDER:
		var p := out.path_join("body_%s.png" % n)
		if FileAccess.file_exists(p):
			var im := Image.load_from_file(p); im.resize(480, 270); tiles.append(im)
	var sheet := Image.create(480 * 4, 270 * 2, false, Image.FORMAT_RGBA8)
	for i in tiles.size():
		sheet.blit_rect(tiles[i], Rect2i(0, 0, 480, 270), Vector2i((i % 4) * 480, (i / 4) * 270))
	sheet.save_png(out.path_join("body_sheet.png"))
	print("missing: ", ORDER.filter(func(n): return not shots.has(n)))
