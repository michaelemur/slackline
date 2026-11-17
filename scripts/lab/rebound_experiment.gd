class_name ReboundExperiment
extends RefCounted
## One deterministic rebound experiment: a slackline + the athlete's LegModel
## (the same classes the game uses) driven by a scripted "athlete technique"
## (protocol). Identical inputs always give identical results.
##
## Phases measured: CONTACT -> LOADING -> MAX DEFORMATION -> RECOIL ->
## TAKEOFF -> FLIGHT -> LANDING (and again).

const DT := 1.0 / 240.0

const PROTOCOLS := {
	"drop": "Drop test: athlete dropped onto the line, legs held in stance (passive). Measures frequency, damping, loading.",
	"slow_deep": "Single slow, deep squat (0.6 m/s to full depth), extend at the bottom of the line.",
	"fast_dip": "Single fast, shallow dip (4 m/s to 0.78 m), extend at the bottom of the line.",
	"rhythm": "Rhythmic pumping in phase with the line (squat high, extend low), then a timed launch; keeps bouncing.",
	"rhythm_wrong": "Same pumping effort but out of phase (squat low, extend high).",
}

# ---- configuration ----
var length: float = 15.0
var params: SlacklineParams
var protocol: String = "drop"
var duration: float = 12.0
var drop_height: float = 0.10       # m, initial oscillation for "drop"
var dip_depth: float = 0.60         # m leg length at the bottom of a squat
var launch_offset: float = 0.0      # m above equilibrium where the launch push starts
var pump_cycles: int = 10           # rhythm: cycles of pumping before the launch
var leg := LegModel.new()
var origin := Vector3.ZERO          # world offset of anchor A (lab scene layout)

# ---- simulation state ----
var solver := SlacklineSolver.new()
var t: float = 0.0
var airborne: bool = false
var s: float = 0.0
var y_eq: float = 0.0               # standing equilibrium height of the contact point
var com_eq: float = 0.0
var l_stance: float = 0.95
var _air_y: float = 0.0             # COM height in flight
var _air_v: float = 0.0
var _prev_feet_dy: float = 1.0
var _ctrl: Dictionary = {}

# ---- measurements ----
var m := {}
var trace_t := PackedFloat32Array()   # for plotting
var trace_y := PackedFloat32Array()
var _crossings: Array[float] = []
var _peaks: Array[float] = []
var _prev_dev: float = 0.0
var _prev_v: float = 0.0
var _takeoff_y: float = 0.0
var _cycle_peak_v: float = 0.0
var _v_smooth: float = 0.0           # 25 ms moving average of contact velocity


func setup() -> void:
	if params == null:
		params = (load("res://resources/presets/trickline.tres") as SlacklineParams).duplicate()
	params = params.duplicate()
	params.length = length
	params.segments = int(clampf(length / 0.32, 40, 100))
	# Same anchor height for every length so the ground never interferes.
	params.anchor_height = 3.5
	solver = SlacklineSolver.new()
	solver.setup(params, origin + Vector3(0, params.anchor_height, 0),
		origin + Vector3(length, params.anchor_height, 0))
	solver.ground_height = 0.0
	s = length * 0.5
	l_stance = leg.l_max - 0.03
	# Static equilibrium: settle with the whole athlete lumped, then put the
	# leg at its own static compression.
	var old := params.damping_mass
	params.damping_mass = 8.0
	for i in range(int(6.0 / DT)):
		solver.clear_loads()
		solver.set_point_load(s, leg.body_mass, 0.0, 0.0)
		solver.step(DT)
	params.damping_mass = old
	for i in range(solver.node_count()):
		solver.vy[i] = 0.0
		solver.vz[i] = 0.0
	leg.target = l_stance
	var static_comp := leg.com_mass() * leg.gravity / leg.k_leg / 0.6
	leg.begin_contact(solver, s, l_stance - static_comp, 0.0)
	# Let the coupled system find its exact rest state.
	for i in range(int(2.0 / DT)):
		_contact_step(DT, true)
	y_eq = solver.world_at(s).y
	com_eq = leg.y_c
	t = 0.0
	airborne = false
	_ctrl = {"phase": "init", "cycles": 0, "bottom": false}
	m = {
		"length": length, "protocol": protocol,
		"static_sag": origin.y + params.anchor_height - y_eq,
		"max_depth": 0.0, "peak_tension": solver.tension, "peak_leg_force": 0.0,
		"rebound_v": 0.0, "takeoff_v": NAN, "jump_height": NAN, "apex_above_chord": NAN,
		"airtime": NAN, "takeoffs": 0, "landings": 0, "landing_peak_force": NAN,
		"freq_hz": NAN, "energy_loss_pct": NAN, "leg_work": 0.0, "cycle_speeds": [],
		"bottomed_out": false,
	}
	if protocol == "drop":
		# Initial oscillation: athlete + line start at the standing equilibrium
		# moving down with the speed of a fall from drop_height (legs in stance).
		var v0 := -sqrt(2.0 * leg.gravity * drop_height)
		leg.v_c = v0
		solver.impart_velocity(s, leg.foot_mass, v0, 0.0)


## Live state for visualisation.
func com_y() -> float:
	return _air_y if airborne else leg.y_c


func foot_point() -> Vector3:
	return solver.world_at(s)


func done() -> bool:
	return t >= duration


func step() -> void:
	if done():
		return
	if airborne:
		_air_step(DT)
	else:
		_control()
		_contact_step(DT, false)
	t += DT
	_measure()


func run() -> Dictionary:
	setup()
	while not done():
		step()
	return finish()


# ------------------------------------------------------------- physics

func _contact_step(dt: float, settling: bool) -> void:
	solver.clear_loads()
	leg.pre_substep(solver, dt)
	solver.step(dt)
	leg.post_substep(solver, dt)
	if settling:
		leg.takeoff = false
		return
	if leg.force > leg.f_max * leg.eccentric_ratio * 0.999 and leg.leg_length(solver) < leg.min_len:
		m["bottomed_out"] = true
	if leg.takeoff:
		_takeoff()


func _takeoff() -> void:
	airborne = true
	_air_v = leg.body_velocity(solver)
	_air_y = leg.y_c
	_takeoff_y = _air_y
	_prev_feet_dy = 1.0
	m["takeoffs"] += 1
	m["leg_work"] += leg.work
	_ctrl["flight_t0"] = t
	_ctrl["flight_apex"] = _air_y
	_ctrl["flight_v"] = _air_v


func _air_step(dt: float) -> void:
	solver.clear_loads()
	solver.step(dt)
	_air_v -= leg.gravity * dt
	_air_y += _air_v * dt
	_ctrl["flight_apex"] = maxf(_ctrl.get("flight_apex", _air_y), _air_y)
	# Feet are at full leg length below the COM; land when they cross the line.
	var line_y := solver.world_at(s).y
	var dy := (_air_y - leg.l_max) - line_y
	var closing := _air_v - solver.world_velocity_at(s).y <= 0.0
	if dy < 0.0 and _prev_feet_dy >= -0.02 and closing:
		# Keep the best flight of the run (by height reached).
		var h: float = _ctrl["flight_apex"] - _takeoff_y
		if is_nan(m["jump_height"]) or h > m["jump_height"]:
			m["takeoff_v"] = _ctrl["flight_v"]
			m["airtime"] = t - _ctrl["flight_t0"]
			m["jump_height"] = h
			m["apex_above_chord"] = (_ctrl["flight_apex"] - leg.l_max) - (origin.y + params.anchor_height)
			m["landing_peak_force"] = NAN   # measure the landing of the best flight
		airborne = false
		m["landings"] += 1
		leg.target = l_stance
		leg.land(solver, s, leg.l_max - 0.01, _air_v, 0.0)
		_ctrl["landing_watch"] = 0.35
		_ctrl["just_landed"] = true
		_ctrl["land_peak"] = 0.0
	_prev_feet_dy = dy


# ------------------------------------------------------------- technique

func _control() -> void:
	var fy := solver.world_at(s).y
	var fv := solver.world_velocity_at(s).y
	var squat := leg.l_min + 0.04
	match protocol:
		"drop":
			leg.target = l_stance
		"slow_deep", "fast_dip":
			var spd := 0.6 if protocol == "slow_deep" else 4.0
			var depth := squat if protocol == "slow_deep" else 0.78
			match _ctrl["phase"]:
				"init":
					_ctrl["phase"] = "load"
					_ctrl["tgt"] = l_stance
				"load":
					_ctrl["tgt"] = move_toward(_ctrl["tgt"], depth, spd * DT)
					leg.target = _ctrl["tgt"]
					if _ctrl["tgt"] <= depth + 1e-4 and fv >= 0.0 and _prev_v < 0.0:
						_ctrl["phase"] = "extend"
					elif _ctrl["tgt"] <= depth + 1e-4 and fv >= 0.0 and fy < y_eq - 0.02:
						_ctrl["phase"] = "extend"
				"extend":
					leg.target = leg.l_max + 0.05
					if fv < 0.0 and fy > y_eq:
						_ctrl["phase"] = "stand"
				"stand":
					leg.target = l_stance
		"rhythm", "rhythm_wrong":
			var in_phase := protocol == "rhythm"
			if _ctrl["phase"] == "init":
				_ctrl["phase"] = "pump"
				leg.target = squat   # start by dropping into a squat
			if _ctrl["phase"] == "pump":
				# Small dead band so the technique does not buzz at equilibrium.
				var dev := fy - y_eq
				if absf(dev) > 0.03 and t > 0.4:
					var want_squat := (dev > 0.0) if in_phase else (dev < 0.0)
					leg.target = squat if want_squat else leg.l_max + 0.05
				if fv >= 0.0 and _prev_v < 0.0:
					_ctrl["cycles"] += 1
					if in_phase and _ctrl["cycles"] >= pump_cycles:
						_ctrl["phase"] = "launch"
			elif _ctrl["phase"] == "launch":
				# Stay low through the bottom, drive explosively past launch_offset.
				leg.target = squat
				if fv > 0.0 and fy > y_eq + launch_offset:
					_ctrl["phase"] = "drive"
			elif _ctrl["phase"] == "drive":
				leg.target = leg.l_max + 0.05
				# No separation this cycle (line never rose high enough): keep pumping.
				if fv < 0.0:
					_ctrl["phase"] = "pump"
					_ctrl["cycles"] = pump_cycles - 1
			if _ctrl.get("just_landed", false) and in_phase:
				# After landing: absorb into the next pump cycle (keep the count,
				# the line is already moving).
				_ctrl["phase"] = "pump"
				_ctrl["just_landed"] = false
	_prev_v = fv


# ------------------------------------------------------------- measuring

func _measure() -> void:
	var fy := solver.world_at(s).y
	var fv_raw := solver.world_velocity_at(s).y
	_v_smooth += (fv_raw - _v_smooth) * (DT / 0.025)
	var fv := _v_smooth
	m["max_depth"] = maxf(m["max_depth"], origin.y + params.anchor_height - fy)
	m["peak_tension"] = maxf(m["peak_tension"], solver.tension)
	if not airborne:
		m["peak_leg_force"] = maxf(m["peak_leg_force"], leg.force)
	if not airborne:
		m["rebound_v"] = maxf(m["rebound_v"], fv)
	if not airborne:
		_cycle_peak_v = maxf(_cycle_peak_v, absf(fv))
	if _ctrl.has("landing_watch"):
		_ctrl["landing_watch"] -= DT
		_ctrl["land_peak"] = maxf(_ctrl["land_peak"], leg.force)
		if _ctrl["landing_watch"] <= 0.0:
			if is_nan(m["landing_peak_force"]):
				m["landing_peak_force"] = _ctrl["land_peak"]
			_ctrl.erase("landing_watch")
	# Oscillation of the contact point about the standing equilibrium.
	var dev := fy - y_eq
	if not airborne and _prev_dev < 0.0 and dev >= 0.0:
		_crossings.append(t)
		(m["cycle_speeds"] as Array).append(snappedf(_cycle_peak_v, 0.01))
		_cycle_peak_v = 0.0
	if protocol == "drop" and not airborne and _prev_dev > 0.0 and dev <= 0.0 and _peaks.size() < 12:
		pass
	_prev_dev = dev
	if protocol == "drop" and not airborne:
		_track_peaks(dev)
	if int(t / DT) % 4 == 0:
		trace_t.append(t)
		trace_y.append(fy)


var _last_dev_sign: int = 0
var _extreme: float = 0.0


func _track_peaks(dev: float) -> void:
	var sgn := 1 if dev >= 0.0 else -1
	if sgn != _last_dev_sign:
		if _last_dev_sign != 0:
			_peaks.append(absf(_extreme))
		_last_dev_sign = sgn
		_extreme = 0.0
	if absf(dev) > absf(_extreme):
		_extreme = dev


func finish() -> Dictionary:
	if _crossings.size() >= 3:
		var n := mini(_crossings.size(), 6)
		m["freq_hz"] = (n - 1) / (_crossings[n - 1] - _crossings[0])
		# Above ~2 Hz the crossings come from technique chatter, not the
		# athlete-line bounce mode: report as not applicable.
		if m["freq_hz"] > 2.0:
			m["freq_hz"] = NAN
	if protocol == "drop" and _peaks.size() >= 5:
		# Energy ~ amplitude^2; average loss per full cycle over the first cycles
		# (skip the first half-wave, which includes the impact).
		var losses := []
		for i in range(1, mini(_peaks.size() - 2, 7), 2):
			if _peaks[i] > 1e-4:
				losses.append(1.0 - pow(_peaks[i + 2] / _peaks[i], 2.0))
		if not losses.is_empty():
			var sum := 0.0
			for x in losses:
				sum += x
			m["energy_loss_pct"] = 100.0 * sum / losses.size()
	var bw := leg.body_mass * leg.gravity
	m["peak_leg_force_bw"] = m["peak_leg_force"] / bw
	if not is_nan(m["landing_peak_force"]):
		m["landing_peak_force_bw"] = m["landing_peak_force"] / bw
	m.erase("_t_takeoff")
	return m
