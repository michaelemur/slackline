extends SceneTree
## Jump heights above the line (its resting level under the athlete):
## COM apex and feet apex, per flight. Args: demo mode, seconds.
var main; var a; var t := 0.0; var mode := "video"; var dur := 40.0; var ps := 0
var rest_y := 0.0
var root_apex := -9.0
var roots := []
var coms := []
var v0 := 0.0
var y0 := 0.0
var com_apex := -9.0; var feet_apex := -9.0; var rows := []
func _initialize():
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: mode = args[0]
	if args.size() > 1: dur = float(args[1])
	main = load("res://scenes/main.tscn").instantiate(); root.add_child(main)
func _physics_process(d) -> bool:
	t += d
	if a == null:
		a = main.get_node("Athlete"); a.input.override_enabled = true
		if OS.get_cmdline_user_args().size() > 2: a.impact_brace_gain = float(OS.get_cmdline_user_args()[2])
		return false
	if t < 1.5:
		var b = a.balance
		a.input.override_balance = clampf(-(2.2 * b.theta + 0.6 * b.omega), -1, 1)
		rest_y = a.global_position.y   # line height under a standing athlete
		return false
	if not main.demo.enabled:
		main.demo.mode = mode; main.demo.set_enabled(true)
	if a.state == 1:
		if ps != 1: com_apex = -9.0; feet_apex = -9.0; root_apex = -9.0; v0 = a.linear_velocity.y; y0 = a.global_position.y - rest_y
		root_apex = maxf(root_apex, a.global_position.y - rest_y)
		var sk: Skeleton3D = a.visual.character.skel
		var lo := 99.0
		for bn in ["foot_l", "foot_r", "ball_l", "ball_r"]:
			lo = minf(lo, (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bn)).origin).y)
		com_apex = maxf(com_apex, a.visual.com_global().y - rest_y)
		feet_apex = maxf(feet_apex, lo - rest_y)
	elif ps == 1:
		rows.append([t, a.air_time, com_apex, feet_apex, a.tricks.start_pose])
		if a.air_time > 0.3:
			roots.append(root_apex)
			coms.append(com_apex)
	ps = a.state
	if t > dur:
		var lo := 99.0; var hi := 0.0
		for r in roots:
			lo = minf(lo, r); hi = maxf(hi, r)
		var cl := 99.0; var ch := 0.0
		for c in coms:
			cl = minf(cl, c); ch = maxf(ch, c)
		print("COM apex above line: min %.2f  max %.2f m" % [cl, ch])
		print("ROOTS ", roots)
		print("FEET (body root) apex above line: min %.2f  max %.2f m over %d flights; landed clean %d" % [lo, hi, roots.size(), a.tricks.tricks_landed])
		return true
	return false
