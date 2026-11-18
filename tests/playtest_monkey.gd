extends SceneTree
## Long randomized "player" sessions on the real main scene. Drives the same
## AthleteInput a player would and records anomalies (stuck states, contact
## loops, NaN, runaway speeds). Not part of the regression suite: it is a
## playtest harness.
##   godot --headless --fixed-fps 60 --path . -s res://tests/playtest_monkey.gd -- <seconds> <seed> [mode]
## mode: "legacy" (current controls) or "intent" (new control scheme, if present)

var main: Node3D
var a
var t := 0.0
var dur := 600.0
var rng := RandomNumberGenerator.new()
var mode := "legacy"
var stats := {"jumps": 0, "landings": 0, "falls": 0, "resets": 0, "clean": 0, "saved": 0,
	"bail": 0, "tricks": 0, "transitions": 0}
var anomalies: Dictionary = {}
var _prev_state := -1
var _state_t := 0.0
var _pose_t := 0.0
var _transitions_window: Array = []
var _plan_t := 0.0
var _plan := {}
var _phase := 0.0
var _last_report := 0.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: dur = float(args[0])
	rng.seed = int(args[1]) if args.size() > 1 else 1
	if args.size() > 2: mode = args[2]
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _flag(kind: String, detail: String) -> void:
	if not anomalies.has(kind):
		anomalies[kind] = {"count": 0, "first": "t=%.1f %s" % [t, detail]}
	anomalies[kind]["count"] += 1


func _new_plan() -> void:
	# a "player intention" lasting 1-4 s
	var kinds := ["pump", "pump", "pump", "flip_back", "flip_front", "twist", "pose", "walk", "idle", "balance_chaos", "grab"]
	_plan = {"kind": kinds[rng.randi() % kinds.size()], "len": rng.randf_range(1.0, 4.0),
		"period": rng.randf_range(0.45, 0.9), "dir": -1.0 if rng.randf() < 0.5 else 1.0,
		"pose": ["butt", "chest", "back"][rng.randi() % 3]}
	_plan_t = 0.0


func _physics_process(dt: float) -> bool:
	t += dt
	if a == null:
		a = main.get_node("Athlete")
		a.input.override_enabled = true
		a.state_changed.connect(_on_state)
		a.tricks.landed.connect(func(n, _p): stats["tricks"] += n.size())
		a.tricks.trick_completed.connect(func(_n): stats["rotations"] = stats.get("rotations", 0) + 1)
		_new_plan()
		return false
	_drive(dt)
	_watch(dt)
	if a.state == 1:
		stats["max_air_h"] = maxf(stats.get("max_air_h", 0.0), a.global_position.y - a.line.sample_world(clampf(a.s, 0.0, a.line.chord_length())).y)
	if a.state == 0 and a.pose != "" and _pose_t < dt * 1.5:
		stats["pose_entries"] = stats.get("pose_entries", 0) + 1
	if t - _last_report > 60.0:
		_last_report = t
		print("  t=%4.0f  %s" % [t, JSON.stringify(stats)])
	if t >= dur:
		print("PLAYTEST mode=%s seed=%d %.0fs  %s" % [mode, rng.seed, t, JSON.stringify(stats)])
		print("ANOMALIES ", JSON.stringify(anomalies, "  "))
		return true
	return false


func _drive(dt: float) -> void:
	var i = a.input
	_plan_t += dt
	_phase += dt
	if _plan_t > _plan["len"]:
		_new_plan()
	i.override_trick = ""
	i.override_move = 0.0
	i.override_flip_axis = 0.0
	i.override_twist_axis = 0.0
	i.override_grab = ""
	i.override_aim = Vector2.ZERO
	i.override_stick_y = 0.0
	# a player keeps correcting balance (noisy PD on the felt lean)
	var corr: float = clampf(-a.balance.theta_seen * 3.0 - a.balance.omega_seen * 0.6 + rng.randf_range(-0.25, 0.25), -1.0, 1.0)
	i.override_balance = corr
	var k: String = _plan["kind"]
	var period: float = _plan["period"]
	var pumping: bool = fmod(_phase, period) < period * 0.5
	var airborne: bool = a.state == 1
	match k:
		"pump", "flip_back", "flip_front", "twist", "grab":
			i.override_pump = pumping and not airborne
			if not airborne:
				if k == "flip_back": i.override_aim = Vector2(0, 1)
				if k == "flip_front": i.override_aim = Vector2(0, -1)
				if k == "twist": i.override_aim = Vector2(_plan["dir"], 0.3)
			if airborne:
				if k == "grab": i.override_grab = "both_knees"
				# tuck until about one turn, then open (a learning player)
				var turned: float = absf(a.tricks.pitch - a.tricks.pitch0)
				i.override_tuck = 1.0 if turned < TAU - rng.randf_range(0.6, 1.8) and absf(a.tricks.l_pitch) > 2.0 else 0.0
				i.override_stick_y = rng.randf_range(-1, 1) * 0.5
			else:
				i.override_tuck = -1.0
		"pose":
			i.override_pump = pumping
			if rng.randf() < 0.02:
				i.override_trick = _plan["pose"]
		"walk":
			i.override_pump = false
			i.override_move = _plan["dir"] * 0.7
		"idle":
			i.override_pump = false
		"balance_chaos":
			i.override_pump = pumping
			i.override_balance = rng.randf_range(-1, 1)


func _on_state(s: int) -> void:
	_transitions_window.append(t)
	stats["transitions"] += 1
	if s == 1: stats["jumps"] += 1
	elif s == 0 and _prev_state == 1:
		stats["landings"] += 1
		var o: String = a.tricks.last_outcome
		if o == "clean": stats["clean"] += 1
		elif o.begins_with("save"): stats["saved"] += 1
	elif s == 2:
		stats["falls"] += 1
		var why: String = "%s|%s|phi%.2f|th%.2f" % [a.last_landing_failure_reason, _plan["kind"], a.balance.phi, a.balance.theta]
		var axis: String = "fb" if absf(a.balance.phi) > 0.5 else "lat"
		var key: String = a.last_landing_failure_reason + "/" + _plan["kind"] + "/" + axis
		stats["why"] = stats.get("why", {})
		stats["why"][key] = stats["why"].get(key, 0) + 1
		if _prev_state == 1 and a.tricks.last_outcome == "bail": stats["bail"] += 1
	if _prev_state == 2 and s == 0: stats["resets"] += 1
	_prev_state = s
	_state_t = 0.0


func _watch(dt: float) -> void:
	_state_t += dt
	var p: Vector3 = a.global_position
	if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)):
		_flag("nan_position", str(p))
		a.reset_to_line(a.line.chord_length() * 0.5)
		return
	var v: Vector3 = a.linear_velocity
	if v.length() > 30.0:
		_flag("runaway_speed", "%.1f m/s state %s" % [v.length(), a.state_name()])
	match a.state:
		0:
			var lp: Vector3 = a.line.sample_world(clampf(a.s, 0.0, a.line.chord_length()))
			if p.distance_to(lp) > 1.6:
				_flag("on_line_but_far_from_line", "%.2f m pose '%s'" % [p.distance_to(lp), a.pose])
			if a.pose != "":
				_pose_t += dt
				if _pose_t > 8.0:
					_flag("stuck_in_pose", "'%s' %.0fs" % [a.pose, _pose_t])
					_pose_t = -1000.0
			else:
				_pose_t = 0.0
		1:
			if _state_t > 5.0:
				_flag("airborne_too_long", "%.1fs y=%.2f vy=%.2f" % [_state_t, p.y, v.y])
				_state_t = -1000.0
		2:
			if _state_t > a.fallen_reset_time + 3.0:
				_flag("fallen_no_reset", "%.1fs" % _state_t)
				_state_t = -1000.0
	while _transitions_window.size() > 0 and t - _transitions_window[0] > 1.0:
		_transitions_window.pop_front()
	if _transitions_window.size() > 6:
		_flag("contact_loop", "%d transitions in 1 s, pose '%s'" % [_transitions_window.size(), a.pose])
		_transitions_window.clear()
