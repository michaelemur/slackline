extends SceneTree
## Measures the takeoff rotation made by the AIM lean (two-zone controls).
var main; var a; var t := 0.0
var aim_y := 1.0
var tuck_air := true
var res := []
var launched := false
var _cycle := 0
var rot_now := 0.0
func _initialize():
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: aim_y = float(args[0])
	if args.size() > 1: tuck_air = args[1] == "tuck"
	main = load("res://scenes/main.tscn").instantiate(); root.add_child(main)
func _physics_process(dt):
	t += dt
	if a == null:
		a = main.get_node("Athlete"); a.input.override_enabled = true
		a.state_changed.connect(_on_state)
		return false
	var i = a.input
	i.override_balance = clampf(-a.balance.theta_seen * 3.0 - a.balance.omega_seen * 0.6, -1, 1)
	if a.state == 0:
		# rhythm pumping: hold while line is going down, release on the way up
		var dev: float = a.bounce_dev()
		if t > 1.0 and t < 1.5:
			i.override_pump = true
		elif t < 4.0 and absf(dev) > 0.03:
			i.override_pump = dev > 0.0
		elif t >= 4.0:
			# launch technique: stay loaded through the bottom, drive on the way up
			if a.foot_velocity.y < 0.0: i.override_pump = true
			elif dev > 0.0: i.override_pump = false
		i.override_aim = Vector2(0, aim_y) if t > 6.0 else Vector2.ZERO
		i.override_tuck = -1.0
	elif a.state == 1:
		rot_now = a.tricks.pitch - a.tricks.pitch0
		i.override_pump = false
		i.override_tuck = 1.0 if tuck_air and absf(a.tricks.pitch - a.tricks.pitch0) < TAU - 1.0 and absf(a.tricks.l_pitch) > 2.0 else 0.0
	return t > 30.0
func _on_state(s):
	if s == 2 and t > 6.0: print("  FELL t=%.2f phi=%.2f theta=%.2f" % [t, a.balance.phi, a.balance.theta])
	if s == 1 and t > 6.0:
		await process_frame
		print("launch t=%.2f vy=%.2f phi=%.3f Lp=%.1f" % [t, a.linear_velocity.y, a.balance.phi, a.tricks.l_pitch])
	elif s != 1 and a.tricks.air_t > 0.0 and t > 6.0:
		print("  land state=%d rot=%.2f rad outcome=%s air=%.2fs performed=%s" % [s, rot_now, a.tricks.last_outcome, a.tricks.air_t, a.tricks.performed])
