extends Node
## Scenario: several tricks into butt bounces on the real main scene. Every
## frame the body is drawn in the butt position, the hips and butt (pelvis and
## both hip joints of the solved skeleton) must be above the line under them.
## Covers: the first plain butt bounce; flips set from the seat and landed
## straight back into it (butt -> flip -> butt, several in a row); the demo's
## video combo (chest -> backflip -> butt, drops from big feet bounces); and
## the line ringing back up right after a takeoff from the seat.

signal finished(passes: int, failures: Array)

const MIN_CLEARANCE := 0.05     # m, hip joints above the line (butt ~ just above it)
## [mode, seconds]: "drop" = one plain butt bounce, "flips" = scripted
## butt -> flip -> butt chain, others = demo pilot modes.
const PHASES := [["drop", 3.0], ["flips", 40.0], ["video", 20.0]]

var main: Node3D
var athlete: Athlete
var passes := 0
var failures: Array = []
var _frames := 0
var _phase := 0
var _phase_t := 0.0
var _t := 0.0
var _worst := {}            # phase -> min clearance
var _frames_checked := {}
var _flips_into_butt := 0
var _butt_after_flip_frames := 0
var _since_flip_landing := INF
# scripted flips pilot
var _pump_t := 0.0
var _flip_set := false
var _flip_n := 0


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	athlete = main.get_node("Athlete")
	athlete.tricks.landed.connect(_on_landed)


func _on_landed(names: Array, _points: int) -> void:
	for n in names:
		if String(n).to_lower().contains("flip") and athlete.tricks.landing_pose == "butt":
			_flips_into_butt += 1
			_since_flip_landing = 0.0
			return


func _check(cond: bool, msg: String) -> void:
	if cond:
		passes += 1
	else:
		failures.append("[butt clearance] " + msg)


func _start_phase() -> void:
	var mode: String = PHASES[_phase][0]
	athlete.reset_to_line(main.get_node("Slackline").chord_length() * 0.5)
	_pump_t = 0.0
	_flip_set = false
	if mode == "drop" or mode == "flips":
		main.demo.set_enabled(false)
		athlete.input.override_enabled = true
		athlete.tricks.skip_weak_flips = false
	else:
		main.demo.mode = mode
		main.demo.set_enabled(true)
		athlete.auto_lock = true


func _physics_process(dt: float) -> void:
	if athlete == null or _phase >= PHASES.size():
		return
	_frames += 1
	_t += dt
	if _frames == 2:
		_start_phase()
	if _frames < 2:
		return
	_phase_t += dt
	_since_flip_landing += dt
	var mode: String = PHASES[_phase][0]
	var inp := athlete.input
	if mode == "drop" or mode == "flips":
		inp.override_balance = clampf(-athlete.balance.theta_seen * 3.0 - athlete.balance.omega_seen * 0.6, -1.0, 1.0)
		inp.override_trick = ""
	if mode == "drop":
		inp.override_trick = "butt" if absf(_phase_t - 0.5) < dt * 0.5 else ""
	elif mode == "flips":
		_fly_flips(dt)
	_measure(mode)
	if _phase_t >= float(PHASES[_phase][1]):
		_phase += 1
		_phase_t = 0.0
		if _phase < PHASES.size():
			_start_phase()
		else:
			_finish()


## A player chaining flips out of the seat: pump on the feet, sit down, set
## a flip while bouncing, land it back in the seat (butt), repeat.
func _fly_flips(dt: float) -> void:
	var a := athlete
	var inp := a.input
	match a.state:
		Athlete.State.ON_LINE:
			if a.pose == "" and a._rising_from == "":
				_flip_set = false
				_pump_t += dt
				if _pump_t < 4.0:
					var dev := a.bounce_dev()
					if absf(dev) > 0.03:
						inp.override_pump = dev > 0.0
				else:
					inp.override_pump = false
					inp.override_trick = "butt"
					_pump_t = 0.0
			elif a.pose == "butt" and a._pose_contacted and a.pose_time > 0.05 and not _flip_set:
				inp.override_pump = false
				if a.tricks.queued_pose != "butt":
					inp.override_trick = "butt"        # land back in the seat
				else:
					inp.override_trick = "backflip" if _flip_n % 2 == 0 else "frontflip"
					_flip_n += 1
					_flip_set = true
		Athlete.State.AIRBORNE:
			_flip_set = false
			inp.override_pump = a.tricks.tuck_hint(0.8) > 0.5 and not a.tricks.locked
			if a.needs_lock:
				# lock the seat late in the jump, like a player
				if not a.tricks.locked and a.land_eta() < 0.4:
					inp.override_trick = "butt"
			elif a.tricks.queued_pose != "butt" and a.air_time < 0.15:
				inp.override_trick = "butt"
		Athlete.State.FALLEN:
			inp.override_pump = false
			_pump_t = 0.0


func _measure(mode: String) -> void:
	if athlete.state == Athlete.State.FALLEN or athlete._pose_visual != "butt" or athlete.pose_blend < 0.5:
		return
	# Airborne frames count while the body is over the line and within reach
	# of it (just after takeoff, and on the final approach).
	if athlete.state == Athlete.State.AIRBORNE and not athlete._seat_guard_active():
		return
	var d := athlete.seat_clearance()
	if d == INF:
		return
	_worst[mode] = minf(_worst.get(mode, INF), d)
	_frames_checked[mode] = int(_frames_checked.get(mode, 0)) + 1
	if _since_flip_landing < 1.5:
		_butt_after_flip_frames += 1


func _finish() -> void:
	main.demo.set_enabled(false)
	for p: Array in PHASES:
		var m: String = p[0]
		var n: int = _frames_checked.get(m, 0)
		_check(n > 20, "%s: butt position was shown (%d frames checked)" % [m, n])
		var w: float = _worst.get(m, INF)
		_check(w >= MIN_CLEARANCE, "%s: hips/butt stay above the line every frame (lowest %.3f m, need %.2f)" % [m, w, MIN_CLEARANCE])
	_check(_flips_into_butt >= 3, "several flips landed straight into a butt bounce (%d)" % _flips_into_butt)
	_check(_butt_after_flip_frames > 60, "seat checked right after flip landings (%d frames)" % _butt_after_flip_frames)
	print("    butt clearance: lowest %s, flips into butt %d (%d frames after them)" % [str(_worst), _flips_into_butt, _butt_after_flip_frames])
	finished.emit(passes, failures)
