extends SceneTree
## Jump height per Line Explosiveness preset (scripted rhythmic pumping).
##  -- <preset> <height_m>
var main; var a; var t := 0.0; var best := 0.0; var best_air := 0.0; var air_t := 0.0; var rest := 0.0
var maxT := 0.0
var preset := "balanced"; var h := 2.2; var jumps := 0; var falls := 0
func _initialize():
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: preset = args[0]
	if args.size() > 1: h = float(args[1])
	var gs = root.get_node("GameSettings")
	gs.explosiveness = preset; gs.line_height = h; gs.from_menu = true
	main = load("res://scenes/main.tscn").instantiate(); root.add_child(main)
func _physics_process(dt):
	t += dt
	if a == null:
		a = main.get_node("Athlete"); a.input.override_enabled = true
		a.state_changed.connect(_on_state)
		return false
	var i = a.input
	i.override_balance = clampf(-a.balance.theta_seen * 3.0 - a.balance.omega_seen * 0.6, -1, 1)
	if t < 1.0: rest = a.line.sample_world(a.s).y
	if a.state == 0:
		var dev: float = a.bounce_dev()
		if t > 1.0 and t < 1.5: i.override_pump = true
		elif t < 4.0 and absf(dev) > 0.03: i.override_pump = dev > 0.0
		elif t >= 4.0:
			if a.foot_velocity.y < 0.0: i.override_pump = true
			elif dev > 0.0: i.override_pump = false
		air_t = 0.0
	elif a.state == 1:
		i.override_pump = false
		air_t += dt
		best_air = maxf(best_air, air_t)
		var feet: float = a.global_position.y - rest
		best = maxf(best, feet)
	maxT = maxf(maxT, a.line.tension())
	return t > float(OS.get_environment("ARC_T") if OS.get_environment("ARC_T") != "" else "25")
func _on_state(s):
	if s == 1: jumps += 1
	elif s == 2: falls += 1
func _finalize():
	print("ARCADE preset=%s height=%.1f  best_feet_above_line=%.2f m  best_airtime=%.2f s  jumps=%d falls=%d maxT=%.0f" % [preset, h, best, best_air, jumps, falls, maxT])
