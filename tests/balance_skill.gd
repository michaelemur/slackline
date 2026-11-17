extends SceneTree
## Balance must need the player: no input -> falls; skilled input -> stays up.
## Prints time to fall and the arm/leg activity seen.
var main; var a; var t := 0.0; var mode := "none"; var fell := -1.0
var max_leg := 0.0; var arm_lo := 9.0; var arm_hi := -9.0; var max_phi := 0.0
func _initialize():
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: mode = args[0]
	main = load("res://scenes/main.tscn").instantiate(); root.add_child(main)
func _physics_process(d) -> bool:
	t += d
	if a == null:
		a = main.get_node("Athlete"); a.input.override_enabled = true; a.balance.omega = 0.25
	var b = a.balance
	if mode == "skilled":
		a.input.override_balance = clampf(-(2.2 * b.theta_seen + 0.6 * b.omega_seen), -1, 1)
	if mode == "walk":
		a.input.override_balance = clampf(-(2.2 * b.theta_seen + 0.6 * b.omega_seen), -1, 1)
		a.input.override_move = 1.0 if fmod(t, 8.0) < 4.0 else -1.0
	if mode == "oneleg":
		a.input.override_balance = clampf(-(2.2 * b.theta_seen + 0.6 * b.omega_seen), -1, 1)
		a.input.override_leg_lift = 1.0
	max_leg = maxf(max_leg, maxf(b.leg_lift_l, b.leg_lift_r))
	arm_lo = minf(arm_lo, minf(b.arm_left, b.arm_right)); arm_hi = maxf(arm_hi, maxf(b.arm_left, b.arm_right))
	max_phi = maxf(max_phi, absf(b.phi))
	if a.state == 2 and fell < 0.0:
		fell = t
	if t > 30.0 or fell > 0.0:
		print("BALANCE[%s]: %s | arms %.2f..%.2f rad | leg out max %.2f | fwd/back lean max %.1f deg" % [mode, ("fell after %.1f s" % fell) if fell > 0 else "standing after 30 s", arm_lo, arm_hi, max_leg, rad_to_deg(max_phi)])
		return true
	return false
