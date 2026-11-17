extends SceneTree
## Phase-1 diagnostics: runs a demo mode and reports, per flight, the
## rotation, peak/average spin rate, airtime, tuck, sideways drift from the
## line plane, body roll and twist. Usage: godot --headless -s ... -- <mode> <seconds>
var main; var a; var t := 0.0; var ps := -1; var mode := "classic"; var dur := 90.0
var f := {}
var flights := []
func _initialize():
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: mode = args[0]
	if args.size() > 1: dur = float(args[1])
	main = load("res://scenes/main.tscn").instantiate(); root.add_child(main)
func _physics_process(d) -> bool:
	t += d
	if a == null:
		a = main.get_node("Athlete"); main.demo.mode = mode; main.demo.set_enabled(true)
	var tr = a.tricks
	if a.state == 1:
		if ps != 1:
			f = {"t": t, "from": tr.start_pose, "to": tr.queued_pose, "p0": tr.pitch, "wmax": 0.0, "tuck": 0.0, "lat": 0.0, "roll": 0.0, "yaw": 0.0, "lat_v": a.linear_velocity.dot(main.line.lateral_axis())}
		var w := absf(tr.omega_pitch)
		f["wmax"] = maxf(f["wmax"], w)
		f["tuck"] = maxf(f["tuck"], tr.tuck)
		var lp: Vector3 = main.line.sample_world(clampf(main.line.project_s(a.global_position), 0.3, main.line.chord_length() - 0.3))
		f["lat"] = maxf(f["lat"], absf((a.global_position - lp).dot(main.line.lateral_axis())))
		f["roll"] = maxf(f["roll"], absf(a.balance.theta))
		f["yaw"] = maxf(f["yaw"], absf(wrapf(tr.yaw, -PI, PI)) if tr.l_twist == 0.0 and tr.yaw == 0.0 else 0.0)
		f["p"] = tr.pitch
		f["air"] = a.air_time
	elif ps == 1:
		f["out"] = tr.last_outcome if a.state == 0 else "fell"
		var rot: float = f.get("p", 0.0) - f["p0"]
		f["rot"] = rot
		flights.append(f)
	ps = a.state
	if t > dur:
		var n_fl := 0
		print("  t     from>to        rot(deg) air(s) w_max w_avg  tuck  lat_drift(m) lat_v  roll(deg) outcome")
		for x in flights:
			var rot: float = x.get("rot", 0.0)
			var air: float = x.get("air", 0.0)
			if absf(rot) < 1.0 and x.get("wmax", 0.0) < 3.0:
				continue
			n_fl += 1
			print("%6.1f %-6s>%-6s %7.0f %6.2f %5.1f %5.1f %5.2f %7.2f %7.2f %6.1f   %s" % [x["t"], x["from"], x["to"], rad_to_deg(rot), air, x["wmax"], absf(rot) / maxf(air, 0.01), x["tuck"], x["lat"], x["lat_v"], rad_to_deg(x["roll"]), x["out"]])
		print("flips: %d" % n_fl)
		return true
	return false
