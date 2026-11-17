extends Node
## Scripted end-to-end test: loads the real main scene and drives the athlete
## through idle -> walk -> pump/jump -> land -> forced fall -> auto reset ->
## preset switch, checking state at each checkpoint. Uses AthleteInput override.

signal finished(passes: int, failures: Array)

var main: Node3D
var athlete: Athlete
var line: Slackline
var t: float = 0.0
var passes: int = 0
var failures: Array = []
var states_seen: Array = []
var _done := {}
var _s_before_walk: float = 0.0
var _worst_ms: float = 0.0
var _steps_ms: Array[float] = []
var _max_air_y: float = -INF
var _fall_y0: float = 0.0
var _release_t: float = -1.0
var _max_bounce_speed: float = 0.0
var _pump_peak: float = 0.0
var _best_jump: float = 0.0
var _chain_best: int = 0
var _landed_before: int = 0
var _air_steer_jumps: int = 0
var _contact_expected: String = ""
var _contact_jumps_before: int = 0
var _contact_target_recorded: bool = false
var _stall_jumps_before: int = 0
var _stall_score_before: int = 0
var _high_jump_started := false


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	athlete = main.get_node("Athlete")
	line = main.get_node("Slackline")
	athlete.input.override_enabled = true
	athlete.state_changed.connect(func(s): states_seen.append(s))
	# Exercise the real Athlete.launch() -> launched payload -> director path.
	var director: CinematicDirector = main.get_node("CinematicDirector")
	var rebound_speeds: Array[float] = []
	director.super_rebound.connect(func(speed): rebound_speeds.append(speed))
	athlete.contact_debug_enabled = true
	athlete.launch(Vector3.UP * 4.5)
	_check(director.is_super, "real athlete launch signal sees the new takeoff speed")
	_check(rebound_speeds.size() == 1 and is_equal_approx(rebound_speeds[0], 4.5),
		"super rebound signal reports the athlete's new launch velocity")
	var first_jump_count := athlete.jumps
	athlete.launch(Vector3.UP * 9.0)
	_check(athlete.jumps == first_jump_count,
		"duplicate launch request while airborne is ignored")
	var diagnostic: Dictionary = athlete.contact_history[-1] if not athlete.contact_history.is_empty() else {}
	_check(diagnostic.has("event") and diagnostic.has("state") and diagnostic.has("contact")
		and diagnostic.has("point") and diagnostic.has("force") and diagnostic.has("velocity")
		and diagnostic.has("angular_velocity") and diagnostic.has("trick_angular_velocity"),
		"opt-in contact diagnostics capture transition details")
	var diagnostics_count := athlete.contact_history.size()
	athlete.contact_debug_enabled = false
	athlete.reset_to_line(line.chord_length() * 0.5)
	_check(athlete.contact_history.size() == diagnostics_count,
		"contact diagnostics stay idle when disabled")
	var first_landing_count := athlete.landings
	athlete.land(athlete.s, 0.0)
	_check(athlete.landings == first_landing_count,
		"duplicate landing request while on the line is ignored")
	athlete.launch(Vector3.UP * 4.3)
	_check(director.is_super and rebound_speeds.size() == 2
		and is_equal_approx(rebound_speeds[1], 4.3),
		"subsequent super rebound uses its own launch velocity")
	athlete.reset_to_line(line.chord_length() * 0.5)
	athlete.launch(Vector3.UP * 3.8)
	_check(not director.is_super and rebound_speeds.size() == 2,
		"subsequent ordinary jump does not reuse stale super-rebound velocity")
	athlete.reset_to_line(line.chord_length() * 0.5)


## Physical pumping technique: squat while the line is high, push while low.
func _rhythm() -> void:
	var dev := athlete.bounce_dev()
	if absf(dev) > 0.03:
		athlete.input.override_pump = dev > 0.0


func _check(cond: bool, msg: String) -> void:
	if cond:
		passes += 1
	else:
		failures.append("[smoke t=%.2f] %s" % [t, msg])


func _at(time: float, key: String) -> bool:
	if t >= time and not _done.has(key):
		_done[key] = true
		return true
	return false


func _physics_process(delta: float) -> void:
	t += delta
	if _contact_expected != "" and athlete.jumps > _contact_jumps_before and not _contact_target_recorded:
		_contact_target_recorded = true
		_check(athlete.state == Athlete.State.AIRBORNE and athlete.tricks.queued_pose == _contact_expected,
			"%s takeoff defaults to a %s landing target" % [_contact_expected, _contact_expected])
	# Balance is a player skill now: correct like a player would (on what
	# the body felt ~150 ms ago), unless a check sets the lean on purpose.
	if not main.demo.enabled:
		var b := athlete.balance
		athlete.input.override_balance = clampf(-(2.2 * b.theta_seen + 0.6 * b.omega_seen), -1.0, 1.0)
	_worst_ms = maxf(_worst_ms, line.last_step_ms)
	_steps_ms.append(line.last_step_ms)
	_best_jump = maxf(_best_jump, athlete.last_jump_height)
	if athlete.state == Athlete.State.AIRBORNE:
		_max_air_y = maxf(_max_air_y, athlete.global_position.y)

	if _at(2.0, "idle"):
		var sag := -line.solver.offset_at(athlete.s).x
		_check(athlete.state == Athlete.State.ON_LINE, "on line after 2 s idle (state %s)" % athlete.state_name())
		_check(sag > 0.5 and sag < 1.2, "trickline sag at feet plausible: %.3f m" % sag)
		_check(line.tension() > line.params.pretension, "tension rises under athlete: %.0f N" % line.tension())
		var foot := line.sample_world(athlete.s)
		_check(athlete.global_position.distance_to(foot) < 0.05, "athlete stands on the simulated line")
		var r: SlacklineRenderer = line.renderer
		_check(r.mesh != null and r.mesh.get_surface_count() == 1, "line renderer produced a mesh")
		_s_before_walk = athlete.s
		athlete.input.override_move = 1.0
	if _at(3.0, "walk"):
		athlete.input.override_move = 0.0
		var moved := athlete.s - _s_before_walk
		# walking speed builds up over the steps (0.4 m/s^2): ~0.2 m in 1 s
		_check(moved > 0.12 and moved < 1.1, "walked forward: %.2f m in 1 s" % moved)
		athlete.input.override_pump = true
	# Pump with the physical rhythm technique until the line throws us off.
	if t > 3.3 and t < 6.5:
		_rhythm()
		_max_bounce_speed = maxf(_max_bounce_speed, absf(athlete.foot_velocity.y))
	elif t >= 6.5 and t < 9.5:
		# Launch technique: stay loaded through the bottom, drive on the way up.
		if athlete.foot_velocity.y < 0.0:
			athlete.input.override_pump = true
		elif athlete.bounce_dev() > 0.0:
			athlete.input.override_pump = false
	if _at(9.5, "airborne"):
		_check(_max_bounce_speed > 2.0, "pumping built up bounce: peak line speed %.2f m/s" % _max_bounce_speed)
		_check(states_seen.has(Athlete.State.AIRBORNE), "line launched athlete into the air (physical takeoff)")
	if _at(10.0, "landed"):
		_check(athlete.landings >= 1, "athlete landed back on the line (landings=%d)" % athlete.landings)
		var i_air := states_seen.find(Athlete.State.AIRBORNE)
		_check(i_air >= 0 and states_seen.find(Athlete.State.ON_LINE, i_air) > i_air,
			"AIRBORNE -> ON_LINE transition recorded %s" % str(states_seen))
		_check(_best_jump > 0.0, "best jump left the line: %.2f m above launch" % _best_jump)
		athlete.reset_to_line(line.chord_length() * 0.5)
	if _at(10.2, "force_fall"):
		athlete.balance.theta = 1.2
	if _at(10.4, "fallen"):
		_check(athlete.state == Athlete.State.FALLEN, "over-lean triggers fall (state %s)" % athlete.state_name())
		_fall_y0 = athlete.global_position.y
	if _at(11.5, "on_ground"):
		_check(athlete.global_position.y < 0.6, "fallen body dropped via Godot physics: y=%.2f" % athlete.global_position.y)
	if _at(13.6, "auto_reset"):
		_check(athlete.state == Athlete.State.ON_LINE, "auto reset back onto line")
		main.load_preset("res://resources/presets/standard.tres")
	if _at(15.5, "standard"):
		_check(absf(line.chord_length() - 18.0) < 0.01, "standard preset rebuilt 18 m line")
		var sag2 := -line.solver.offset_at(athlete.s).x
		_check(sag2 > 0.9 and sag2 < 1.5, "standard sag plausible: %.3f m" % sag2)
		_check(athlete.state == Athlete.State.ON_LINE, "standing on standard line")
	# --- v0.2: reactive pump, line tricks, forgiving air control -----------
	if _at(16.0, "pump_start"):
		main.load_preset("res://resources/presets/trickline.tres")
		_pump_peak = 0.0
		athlete.input.override_pump = true
	if t > 16.0 and t < 18.0:
		if t > 16.3:
			_rhythm()
		_pump_peak = maxf(_pump_peak, absf(athlete.foot_velocity.y))
	if _at(18.0, "pump_check"):
		athlete.input.override_pump = false
		_check(_pump_peak > 1.5, "rhythm pumping from rest reaches >1.5 m/s line speed within 2 s (got %.2f)" % _pump_peak)
		athlete.reset_to_line(line.chord_length() * 0.5)
	for trick in ["butt", "chest", "back"]:
		var t0: float = {"butt": 18.5, "chest": 21.0, "back": 23.5}[trick]
		if _at(t0, "pose_" + trick):
			_landed_before = athlete.tricks.tricks_landed
			_contact_jumps_before = athlete.jumps
			_contact_expected = trick
			_contact_target_recorded = false
			athlete.input.override_trick = trick
		if _at(t0 + 0.2, "pose_in_" + trick):
			_check(athlete.pose == trick, "%s bounce: athlete drops into position" % trick)
		if _at(t0 + 2.2, "pose_out_" + trick):
			_check(athlete.jumps > _contact_jumps_before, "%s contact produced a physical takeoff" % trick)
			_check(_contact_target_recorded, "%s takeoff-contact memory was observed" % trick)
			_check(athlete.tricks.tricks_landed >= _landed_before + 1, "%s bounce scored after takeoff" % trick)
			_check(athlete.state != Athlete.State.FALLEN, "%s bounce: rode the line back up without falling (%s)" % [trick, athlete.state_name()])
			_contact_expected = ""
			athlete.reset_to_line(line.chord_length() * 0.5)
	# Steer hard in the air, then land: should stay on.
	if _at(26.0, "air_steer_pump"):
		athlete.input.override_pump = true
		_air_steer_jumps = athlete.jumps
	if t > 26.0 and t < 34.0 and athlete.state == Athlete.State.AIRBORNE:
		athlete.input.override_pump = false
		athlete.input.override_balance = 1.0
	elif t > 26.0 and t < 34.0 and athlete.jumps > _air_steer_jumps:
		athlete.input.override_balance = 0.0
		athlete.input.override_pump = false
	elif t > 26.3 and t < 34.0:
		_rhythm()
	if _at(34.0, "air_steer_check"):
		athlete.input.override_balance = 0.0
		athlete.input.override_pump = false
		_check(athlete.jumps > _air_steer_jumps, "got airborne for the air-steer test")
		_check(athlete.state != Athlete.State.FALLEN, "steering hard in the air still lands on the line (state %s)" % athlete.state_name())
	if _at(35.0, "demo_start"):
		athlete.reset_to_line(line.chord_length() * 0.5)
		main.demo.set_enabled(true)
	if _at(65.0, "demo_end"):
		var tr: TrickController = athlete.tricks
		print("    demo: score %d, tricks landed %d, jumps %d, landings %d, msg '%s'"
			% [tr.score, tr.tricks_landed, athlete.jumps, athlete.landings, tr.message])
		_check(tr.tricks_landed >= 3, "demo landed at least 3 tricks in 30 s (got %d)" % tr.tricks_landed)
		_check(tr.score > 0, "demo scored points")
		main.demo.set_enabled(false)
	# Chaining line tricks: Z from the feet, then Z in the air every time.
	if _at(66.0, "chain_start"):
		main.demo.set_enabled(false)
		athlete.input.override_enabled = true
		athlete.reset_to_line(line.chord_length() * 0.5)
		_chain_best = 0
		athlete.input.override_trick = "butt"
	if t > 66.0 and t < 74.0:
		if athlete.state == Athlete.State.AIRBORNE and athlete.tricks.queued_pose == "":
			athlete.input.override_trick = "butt"
		_chain_best = maxi(_chain_best, athlete._line_combo)
	if _at(74.0, "chain_check"):
		_check(_chain_best >= 2, "butt bounces chain from the air (best combo x%d)" % _chain_best)
		_check(athlete.state != Athlete.State.FALLEN, "chained butt bounces stay on the line")
	if _at(74.5, "stalled_push_start"):
		athlete.reset_to_line(line.chord_length() * 0.5)
		athlete.pose_push_reach = 0.02  # deterministically force the push to stall
		_stall_jumps_before = athlete.jumps
		_stall_score_before = athlete.tricks.tricks_landed
		athlete.input.override_trick = "chest"
	if _at(76.8, "stalled_push_recovery"):
		_check(athlete.pose == "" and athlete._rising_from == "",
			"stalled chest push exits the contact state")
		_check(is_equal_approx(athlete.leg.contact_max, athlete.leg.l_max),
			"stalled chest push restores full stance reach")
		_check(athlete.jumps == _stall_jumps_before,
			"failed chest push does not create an unintended takeoff")
		_check(athlete.tricks.tricks_landed == _stall_score_before,
			"failed chest push is not scored as a completed bounce")
		_check(athlete.last_landing_failure_reason.contains("did not reach takeoff"),
			"stalled push records a specific recovery reason")
		_check(athlete.state != Athlete.State.FALLEN,
			"failed chest push recovers to a supported state")
		athlete.pose_push_reach = 0.35
	if _at(77.0, "line_30m"):
		main.load_preset("res://resources/presets/trickline_30m.tres")
		var beach := main.get_node("Beach")
		_check(absf(line.chord_length() - 30.0) < 0.01 and absf(beach.line_length - 30.0) < 0.01,
			"selecting 30 m rebuilds both the physical span and beach layout")
	if _at(77.2, "line_40m"):
		main.load_preset("res://resources/presets/trickline_40m.tres")
		var beach := main.get_node("Beach")
		_check(absf(line.chord_length() - 40.0) < 0.01 and absf(beach.line_length - 40.0) < 0.01,
			"selecting 40 m rebuilds both the physical span and beach layout")
	if _at(77.4, "line_15m"):
		main.load_preset("res://resources/presets/trickline.tres")
		var beach := main.get_node("Beach")
		_check(absf(line.chord_length() - 15.0) < 0.01 and absf(beach.line_length - 15.0) < 0.01,
			"returning to 15 m restores the matching beach layout")
	if _at(77.6, "end"):
		_check(line.solver.is_finite_state(), "solver state finite")
		# 99th percentile: single spikes on a shared/loaded machine are not the solver
		_steps_ms.sort()
		var p99: float = _steps_ms[int(_steps_ms.size() * 0.99)]
		_check(p99 < 8.0, "solver step under 8 ms (p99 %.2f ms, worst %.2f ms)" % [p99, _worst_ms])
		print("    smoke: apex %.2f m, worst solver %.2f ms, jumps %d, landings %d"
			% [_max_air_y, _worst_ms, athlete.jumps, athlete.landings])
		# A deliberate 35 m/s launch verifies that the former 6 s watchdog no
		# longer imposes an artificial maximum on physically valid flight.
		main.demo.enabled = false
		athlete.reset_to_line(line.chord_length() * 0.5)
		athlete.launch(Vector3.UP * 35.0)
		_high_jump_started = true
	if _high_jump_started and athlete.air_time >= 6.05:
		_check(athlete.state == Athlete.State.AIRBORNE
			and athlete.global_position.y > line.ground_height + 5.0,
			"valid high rebound remains airborne beyond six seconds (state %s, y %.2f)"
			% [athlete.state_name(), athlete.global_position.y])
		finished.emit(passes, failures)
