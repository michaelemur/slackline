extends SceneTree
## Renders the butt/chest/back bounce positions (needs a display / xvfb-run).
var main; var a; var t := 0.0; var out := "user://"; var idx := 0; var t0 := 0.0
const POSES := ["butt", "chest", "back"]
func _initialize():
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: out = args[0]
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
func _process(d):
	t += d
	if a == null:
		a = main.get_node("Athlete"); a.input.override_enabled = true
		main.camera_rig.yaw_deg = -70.0
		t0 = 1.0
	if idx < POSES.size():
		if t > t0 and a.pose == "" and a._pose_visual == "":
			a.input.override_trick = POSES[idx]; t0 = 9999.0
		if a.pose != "" and a.pose_blend >= 1.0 and a.foot_velocity.y < -0.2:
			root.get_viewport().get_texture().get_image().save_png(out.path_join("pose_%s.png" % POSES[idx]))
			print("saved ", POSES[idx]); idx += 1; t0 = t + 2.5
	return t > 20 or idx >= POSES.size()
