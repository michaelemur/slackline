extends TestCase
## Cinematic director: camera shot weights and earned slow motion.
## Driven with synthetic jumps (the director only reads the athlete).

const DT := 1.0 / 60.0


func _dir() -> CinematicDirector:
	var d := CinematicDirector.new()
	d.slowmo_enabled = true
	Engine.time_scale = 1.0
	return d


func _run(d: CinematicDirector, seconds: float, airborne: bool, vy: float, h: float, rot: bool) -> void:
	for i in range(int(seconds / DT)):
		d.on_air(airborne, vy, h, rot)
		d.update(DT)


func _fly(d: CinematicDirector, v0: float, rot: bool) -> Dictionary:
	# ballistic flight; returns the max of each shot weight and min time scale
	var best := {"pull": 0.0, "super": 0.0, "close": 0.0, "trick": 0.0, "ts": 1.0}
	var vy := v0
	var h := 0.0
	d.on_launch(v0)
	while h >= 0.0:
		d.on_air(true, vy, h + 0.9, rot)
		d.update(DT)
		vy -= 9.81 * DT
		h += vy * DT
		for k in ["pull", "super", "close", "trick"]:
			best[k] = maxf(best[k], d.shot[k])
		best["ts"] = minf(best["ts"], d.time_scale)
	return best


func test_normal_bouncing_is_calm() -> void:
	var d := _dir()
	var prev := 0.0
	var max_step := 0.0
	for i in range(240):
		var h := 0.15 * sin(i * DT * 6.0)
		d.on_air(false, 0.0, h, false)
		d.update(DT)
		max_step = maxf(max_step, absf(d.shot["pull"] - prev))
		prev = d.shot["pull"]
	check(d.shot["pull"] < 0.01 and d.time_scale == 1.0, "bouncing on the line: no pull-back, normal speed")
	check(max_step < 0.01, "no sudden camera moves (max step %.3f)" % max_step)
	d.free()


func test_high_jump_pulls_back_smoothly() -> void:
	var d := _dir()
	d.best_launch = 10.0   # not a super rebound
	var b := _fly(d, 4.0, false)
	check(b["pull"] > 0.4, "high jump pulls the camera back (pull %.2f)" % b["pull"])
	check(b["ts"] == 1.0, "an ordinary high jump has no slow motion")
	_run(d, 3.0, false, 0.0, 0.0, false)
	check(d.shot["pull"] < 0.05, "camera returns after landing (%.2f)" % d.shot["pull"])
	d.free()


func test_camera_framing_distance_scales_without_an_altitude_ceiling() -> void:
	var low := CameraRig.altitude_framing_distance(6.0, 2.0)
	var high := CameraRig.altitude_framing_distance(6.0, 20.0)
	var higher := CameraRig.altitude_framing_distance(6.0, 200.0)
	check(is_equal_approx(low, 6.0), "ordinary jumps retain the normal follow distance")
	check(high > low and higher > high, "camera framing keeps expanding for high jumps")


func test_trick_moves_camera_slightly() -> void:
	var d := _dir()
	d.best_launch = 10.0
	var b := _fly(d, 3.5, true)
	check(b["trick"] > 0.5 and b["close"] == 0.0, "trick: slight orbit, no close-up without a super rebound")
	d.free()


func test_hard_trick_triggers_hero_shot_and_returns_to_gameplay() -> void:
	var d := _dir()
	d.on_hard_trick("Double Backflip")
	check(d._targets["hero"] == 1.0, "hard tricks request a short Hero Sky Shot")
	_run(d, 0.5, true, 1.0, 5.0, true)
	check(d.shot["hero"] > 0.3, "hero shot blends in instead of snapping")
	_run(d, 2.0, false, 0.0, 0.0, false)
	check(d.shot["hero"] < 0.1, "hero shot returns to normal camera framing")
	d.free()


func test_slow_motion_exits_before_a_near_landing() -> void:
	var d := _dir()
	check(d.request_slowmo("test", 2.0), "slow motion starts")
	for i in 20:
		d.update(DT)
	var before := d.time_scale
	d.on_air(true, -5.0, 0.6, false)
	check(d._forced_out_t >= 0.0, "near-landing descent starts the smooth exit")
	_run(d, 0.6, false, 0.0, 0.0, false)
	check(d.time_scale == 1.0 and not d.is_slowmo(), "slow motion reaches normal speed before contact")
	Engine.time_scale = 1.0
	d.free()


func test_super_rebound_reveal_then_close_and_slowmo() -> void:
	var d := _dir()
	var got := []
	d.super_rebound.connect(func(v): got.append(v))
	var b := _fly(d, 8.0, true)
	check(got.size() == 1, "super rebound detected on a big launch")
	check(b["super"] > 0.5, "camera pulls back to reveal the height (%.2f)" % b["super"])
	check(b["close"] > 0.3, "moves to a close cinematic angle during the trick (%.2f)" % b["close"])
	check(absf(b["ts"] - 0.3) < 0.05, "slow motion reaches ~30%% (%.2f)" % b["ts"])
	Engine.time_scale = 1.0
	d.free()


func test_slowmo_eases_in_and_out_and_returns() -> void:
	var d := _dir()
	check(d.request_slowmo("test", 0.5), "slow motion starts")
	var prev := 1.0
	var max_jump := 0.0
	var t := 0.0
	while d.is_slowmo() and t < 5.0:
		d.update(DT)
		max_jump = maxf(max_jump, absf(d.time_scale - prev))
		prev = d.time_scale
		t += DT
	check(max_jump < 0.06, "smooth transitions (max step %.3f per frame)" % max_jump)
	check(d.time_scale == 1.0 and Engine.time_scale == 1.0, "back to normal speed after the moment")
	check(t < 1.6, "short cinematic moment (%.2f s)" % t)
	check(not d.request_slowmo("again", 0.5), "cooldown: not constant")
	d.free()


func test_combo_landing_zoom_shake_slowmo() -> void:
	var d := _dir()
	d.on_land(5.5, 3)
	d.update(DT)
	check(d.shot["trauma"] > 0.3, "powerful combo landing shakes the camera (%.2f)" % d.shot["trauma"])
	check(d.is_slowmo(), "big combo earns slow motion")
	_run(d, 0.5, false, 0.0, 0.0, false)
	check(d.shot["combo"] > 0.5, "subtle combo zoom")
	_run(d, 4.0, false, 0.0, 0.0, false)
	check(d.shot["trauma"] == 0.0 and d.shot["combo"] < 0.05 and Engine.time_scale == 1.0, "everything settles back to normal play")
	d.free()


func test_two_trick_landing_no_slowmo() -> void:
	var d := _dir()
	d.on_land(3.0, 2)
	check(not d.is_slowmo(), "a 2-trick combo shakes/zooms but keeps normal speed")
	d.free()
