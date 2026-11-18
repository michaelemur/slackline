extends Node
## Scenario test on the real main scene: Butt Bounce -> two-hand grip ->
## pumping -> voluntary release -> flight -> valid landing state.
## Inputs go through AthleteInput overrides exactly as a player's would.

signal finished(passes: int, failures: Array)

var main: Node3D
var athlete: Athlete
var line: Slackline
var passes := 0
var failures: Array = []
var t := 0.0
var _steps: Array = []
var _step := 0
var _step_t := 0.0
var _rest_y := 0.0
var _amp := 0.0
var _amp_late := 0.0
var _amp_mid := 0.0
var _launch_v := 0.0
var _left_line_while_gripping := false
var _takeoff_flag_while_gripping := false
var _amp_good := 0.0
var _v_good := 0.0
var _release_seen_airborne := false
var _grip_hand_points := false
var _max_tension := 0.0


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	athlete = main.get_node("Athlete")
	line = main.get_node("Slackline")
	athlete.input.override_enabled = true
	athlete.launched.connect(func(v): _launch_v = v.y)
	# [name, seconds, per-frame callable, end callable]
	_steps = [
		["settle", 1.0, func(): _rest_y = line.sample_world(athlete.s).y, Callable()],
		["sit", 2.5, _sit, _check_sit],
		["good pumping", 6.0, _pump.bind("good"), _end_good],
		["release", 3.5, _release, _check_release],
		["reset", 1.0, func(): pass, func(): athlete.reset_to_line(line.chord_length() * 0.5)],
		["sit2", 2.5, _sit, Callable()],
		["bad pumping", 6.0, _pump.bind("bad"), _end_bad],
		["hold still", 5.0, _pump.bind("none"), _end_hold],
		["long pumping", 15.0, _pump.bind("good"), _end_long],
		["recovery", 0.5, func(): pass, _check_recovery],
		["feet grab", 1.0, _feet_grab, _check_feet_grab],
	]


func _check(cond: bool, msg: String) -> void:
	if cond:
		passes += 1
	else:
		failures.append("[sticky] " + msg)


func _physics_process(dt: float) -> void:
	if athlete == null or _step >= _steps.size():
		return
	t += dt
	_step_t += dt
	var i := athlete.input
	i.override_balance = clampf(-athlete.balance.theta_seen * 3.0 - athlete.balance.omega_seen * 0.6, -1.0, 1.0)
	i.override_trick = ""
	_max_tension = maxf(_max_tension, line.tension())
	var st: Array = _steps[_step]
	(st[2] as Callable).call()
	if _step_t >= float(st[1]):
		if (st[3] as Callable).is_valid():
			(st[3] as Callable).call()
		_step += 1
		_step_t = 0.0
		_amp = 0.0
		_amp_mid = 0.0
		_amp_late = 0.0
		if _step >= _steps.size():
			athlete.input.override_enabled = false
			finished.emit(passes, failures)


func _sit() -> void:
	var i := athlete.input
	if _step_t < 0.05:
		i.override_trick = "butt"
	i.override_pump = false
	i.override_grab = "leg" if _step_t > 0.6 else ""


func _check_sit() -> void:
	_check(athlete.pose == "butt", "entered Butt Bounce (pose '%s')" % athlete.pose)
	_check(athlete.sticky and athlete.leg.grip, "two-hand grip established")
	var hg: Array = athlete.visual.character.hand_goal["l"] if athlete.visual.character != null else []
	_grip_hand_points = athlete.visual.character == null or (hg.size() > 0 and hg[0] == "point")
	_check(_grip_hand_points, "both hands drawn on the line")


func _pump(mode: String) -> void:
	var i := athlete.input
	i.override_grab = "leg"
	var vf := line.sample_velocity(athlete.s).y
	match mode:
		"good": i.override_pump = vf < 0.0
		"bad": i.override_pump = vf > 0.0
		_: i.override_pump = false
	var amp := absf(line.sample_world(athlete.s).y - _rest_y)
	_amp = maxf(_amp, amp)
	var dur: float = _steps[_step][1]
	if _step_t > dur - 5.0:
		_amp_late = maxf(_amp_late, amp)
	elif _step_t > dur - 10.0:
		_amp_mid = maxf(_amp_mid, amp)
	if athlete.state != Athlete.State.ON_LINE:
		_left_line_while_gripping = true
	if athlete.leg.takeoff:
		_takeoff_flag_while_gripping = true


func _end_good() -> void:
	_amp_good = _amp
	_check(athlete.sticky, "still gripping after 6 s of pumping")
	_check(not _left_line_while_gripping and not _takeoff_flag_while_gripping, "no automatic launch while gripping")
	_check(athlete.sticky_cycles >= 8, "repeated pumping cycles (%d)" % athlete.sticky_cycles)
	_check(_amp_good > 0.65, "good timing builds the line up (amplitude %.2f m)" % _amp_good)
	_check(athlete.sticky_work > 300.0, "energy came from actuator work (%.0f J)" % athlete.sticky_work)
	_check(athlete.s > 0.0 and absf(athlete.global_position.y - line.sample_world(athlete.s).y) < 0.8,
		"hands and body stay at the contact point")


func _release() -> void:
	var i := athlete.input
	i.override_pump = false
	# keep gripping until the line is coming up through the middle, then let go
	var vf := line.sample_velocity(athlete.s).y
	if athlete.sticky and not (vf > 0.5):
		i.override_grab = "leg"
	else:
		i.override_grab = ""
	if athlete.state == Athlete.State.AIRBORNE:
		_release_seen_airborne = true
		_v_good = maxf(_v_good, _launch_v)


func _check_release() -> void:
	_check(not athlete.sticky and not athlete.leg.grip, "hands let go on release")
	_check(_release_seen_airborne, "release throws the athlete into the air")
	_check(_v_good > 3.0, "powerful takeoff (%.2f m/s)" % _v_good)
	var hg: Array = athlete.visual.character.hand_goal["l"] if athlete.visual.character != null else []
	_check(hg.is_empty() or hg[0] != "point" or athlete.pose == "chest", "hands no longer attached to the line after release")
	_check(athlete.state != Athlete.State.AIRBORNE, "landed back into a valid state (%s)" % athlete.state_name())


func _end_bad() -> void:
	_check(athlete.sticky, "bad timing: still attached")
	_check(_amp < _amp_good * 0.75, "poor timing builds much less (%.2f vs %.2f m)" % [_amp, _amp_good])


func _end_hold() -> void:
	_check(athlete.sticky and athlete.pose == "butt", "holding on without pumping: no stand-up timeout, no launch")
	_check(athlete.state == Athlete.State.ON_LINE, "still on the line")


func _end_long() -> void:
	_check(athlete.sticky, "15 s of pumping: still attached")
	_check(_amp < 1.5, "energy is limited (amplitude %.2f m)" % _amp)
	_check(_amp_late < _amp_mid * 1.12 + 0.02, "amplitude saturates (%.2f -> %.2f m)" % [_amp_mid, _amp_late])
	_check(is_finite(line.tension()) and _max_tension < 40000.0, "line stays stable (max tension %.0f N)" % _max_tension)


func _check_recovery() -> void:
	athlete.reset_to_line(line.chord_length() * 0.5)
	_check(not athlete.sticky and not athlete.leg.grip, "reset clears the grip")


func _feet_grab() -> void:
	athlete.input.override_grab = "leg"
	athlete.input.override_pump = false


func _check_feet_grab() -> void:
	_check(not athlete.sticky and not athlete.leg.grip, "GRAB on the feet does not grip the line")
	athlete.input.override_grab = ""
