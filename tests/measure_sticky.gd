extends SceneTree
## Sticky bounce measurement: sit, grip, pump with a given timing, release.
##  -- <pump_mode: good|bad|none> <pump_seconds> [release: up|down]
var main; var a; var t := 0.0
var mode := "good"; var pump_s := 6.0; var rel := "up"
var phase := 0; var t_grip := 0.0; var released := false; var max_amp := 0.0
var y0 := 0.0; var apex := -INF; var launch_v := 0.0; var line_rest := 0.0
func _initialize():
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: mode = args[0]
	if args.size() > 1: pump_s = float(args[1])
	if args.size() > 2: rel = args[2]
	main = load("res://scenes/main.tscn").instantiate(); root.add_child(main)
func _physics_process(dt):
	t += dt
	if a == null:
		a = main.get_node("Athlete"); a.input.override_enabled = true
		a.launched.connect(func(v): launch_v = v.y)
		return false
	var i = a.input
	i.override_balance = clampf(-a.balance.theta_seen * 3.0 - a.balance.omega_seen * 0.6, -1, 1)
	if t < 1.0:
		line_rest = a.line.sample_world(a.s).y
		return false
	if phase == 0:
		i.override_trick = "butt"; phase = 1; return false
	if phase == 1:
		i.override_grab = "leg"     # GRAB held
		if a.sticky:
			phase = 2; t_grip = t
		elif t > 6.0:
			print("FAIL never gripped pose=%s" % a.pose); return true
		return false
	var vf: float = a.line.sample_velocity(a.s).y
	var amp: float = absf(a.line.sample_world(a.s).y - line_rest)
	if phase == 2:
		i.override_grab = "leg"
		match mode:
			"bad": i.override_pump = vf > 0.0      # pull in while the line rises (against it)
			"good": i.override_pump = vf < 0.0     # pull in while the line drops, push away as it recoils (same rhythm as on the feet)
			"none": i.override_pump = false
		max_amp = maxf(max_amp, amp)
		if a.state != 0: print("FAIL left the line while gripping state=%s" % a.state_name()); return true
		if t - t_grip > pump_s:
			# release on the way up (or down) through the middle
			var ok := (vf > 0.5) if rel == "up" else (vf < -0.5)
			if ok:
				i.override_grab = ""; i.override_pump = false; phase = 3; y0 = a.global_position.y
				print("release t=%.2f line_v=%.2f amp_max=%.2f cycles=%d work=%.0fJ" % [t, vf, max_amp, a.sticky_cycles, a.sticky_work])
		return false
	if phase == 3:
		i.override_grab = ""; i.override_pump = false
		if a.state == 1:
			apex = maxf(apex, a.global_position.y - line_rest)
		if t - t_grip > pump_s + 4.0:
			print("RESULT mode=%s pump=%.1fs launch_v=%.2f apex_above_line=%.2f hands=%s sticky=%s state=%s pose=%s" % [mode, pump_s, launch_v, apex, a.leg.grip, a.sticky, a.state_name(), a.pose])
			return true
	return false
