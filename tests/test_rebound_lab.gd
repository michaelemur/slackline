extends TestCase
## Acceptance tests for the REBOUND LABORATORY milestone (brief, part 10).
## Each test runs the real solver + LegModel deterministically.

var _cache := {}


func _run(L: float, proto: String, duration: float = 16.0) -> Dictionary:
	var key := "%s_%d_%d" % [proto, L, duration]
	if not _cache.has(key):
		var e := ReboundExperiment.new()
		e.length = L
		e.protocol = proto
		e.duration = duration
		_cache[key] = e.run()
	return _cache[key]


func test_1_15m_and_30m_behave_differently() -> void:
	var a := _run(15.0, "drop", 8.0)
	var b := _run(30.0, "drop", 8.0)
	check(b["static_sag"] > a["static_sag"] * 1.5, "30 m sags more (%.2f vs %.2f m)" % [b["static_sag"], a["static_sag"]])
	check(b["max_depth"] > a["max_depth"], "30 m loads deeper under the same drop")


func test_2_real_time_line_deformation() -> void:
	var e := ReboundExperiment.new()
	e.length = 15.0
	e.protocol = "rhythm"
	e.setup()
	var y0 := e.foot_point().y
	var lo := y0
	var hi := y0
	for i in range(int(4.0 / ReboundExperiment.DT)):
		e.step()
		lo = minf(lo, e.foot_point().y)
		hi = maxf(hi, e.foot_point().y)
	check(hi - lo > 0.5, "line deforms dynamically under the athlete (range %.2f m)" % (hi - lo))


func test_3_different_oscillation_frequencies() -> void:
	var f15: float = _run(15.0, "drop", 8.0)["freq_hz"]
	var f20: float = _run(20.0, "drop", 8.0)["freq_hz"]
	var f30: float = _run(30.0, "drop", 8.0)["freq_hz"]
	check(f15 > f20 and f20 > f30, "frequency falls with length: %.2f > %.2f > %.2f Hz" % [f15, f20, f30])
	check(f15 / f30 > 1.2, "short line clearly faster (ratio %.2f)" % (f15 / f30))


func test_4_athlete_controlled_loading() -> void:
	var slow := _run(15.0, "slow_deep", 6.0)
	var fast := _run(15.0, "fast_dip", 6.0)
	var drop := _run(15.0, "drop", 6.0)
	check(slow["max_depth"] > drop["static_sag"] + 0.3, "squatting loads the line beyond its static sag")
	check(absf(slow["rebound_v"] - fast["rebound_v"]) > 0.3,
		"slow-deep vs fast-dip loading give different rebounds (%.2f vs %.2f m/s)" % [slow["rebound_v"], fast["rebound_v"]])


func test_5_rebound_from_elastic_energy_and_timing() -> void:
	var good := _run(15.0, "rhythm")
	var bad := _run(15.0, "rhythm_wrong")
	check(good["takeoffs"] >= 1, "in-phase technique produces takeoffs")
	check(bad["takeoffs"] == 0, "same effort out of phase does not launch")
	check(good["rebound_v"] > bad["rebound_v"] * 2.0,
		"timing matters: rebound %.2f vs %.2f m/s" % [good["rebound_v"], bad["rebound_v"]])


func test_6_different_takeoff_velocities() -> void:
	var v15: float = _run(15.0, "rhythm")["takeoff_v"]
	var v30: float = _run(30.0, "rhythm")["takeoff_v"]
	check(not is_nan(v15) and v15 > 1.0, "15 m launches (%.2f m/s)" % v15)
	check(is_nan(v30) or absf(v15 - v30) > 0.3, "15 m and 30 m give different takeoffs (%.2f vs %s)" % [v15, str(v30)])


func test_7_repeated_bouncing() -> void:
	var r := _run(15.0, "rhythm")
	check(r["takeoffs"] >= 3 and r["landings"] >= 3,
		"repeated takeoff/landing cycles (%d / %d)" % [r["takeoffs"], r["landings"]])
	var speeds: Array = r["cycle_speeds"]
	check(speeds.size() >= 4 and speeds[3] > speeds[0] * 1.5, "bounce builds over cycles %s" % str(speeds.slice(0, 5)))


func test_8_measurable_outputs_and_energy_bookkeeping() -> void:
	var r := _run(15.0, "drop", 8.0)
	for k in ["static_sag", "max_depth", "peak_tension", "freq_hz", "energy_loss_pct", "rebound_v", "peak_leg_force_bw"]:
		check(r.has(k) and not (r[k] is float and is_nan(r[k])), "output '%s' measured" % k)
	check(r["energy_loss_pct"] > 2.0 and r["energy_loss_pct"] < 40.0,
		"energy loss per cycle physical (%.1f %%)" % r["energy_loss_pct"])
	var g := _run(15.0, "rhythm")
	check(g["leg_work"] > 0.0, "takeoff energy comes from leg work (%.0f J)" % g["leg_work"])


func test_9_identical_conditions_repeat_exactly() -> void:
	var a := ReboundExperiment.new()
	a.length = 20.0
	a.protocol = "rhythm"
	a.duration = 8.0
	var b := ReboundExperiment.new()
	b.length = 20.0
	b.protocol = "rhythm"
	b.duration = 8.0
	var ra := a.run()
	var rb := b.run()
	check(ra["max_depth"] == rb["max_depth"] and ra["takeoffs"] == rb["takeoffs"]
		and str(ra["cycle_speeds"]) == str(rb["cycle_speeds"]), "bit-identical repeat runs")


func test_10_no_free_energy_without_athlete_work() -> void:
	# Passive athlete after an initial drop: the bounce must die out.
	var e := ReboundExperiment.new()
	e.length = 15.0
	e.protocol = "drop"
	e.duration = 20.0
	var r := e.run()
	var sp: Array = r["cycle_speeds"]
	check(sp.size() > 4 and sp[sp.size() - 1] < sp[0] * 0.5, "passive bounce decays %s" % str(sp.slice(0, 6)))
	check(r["takeoffs"] == 0, "no takeoff without leg work")
