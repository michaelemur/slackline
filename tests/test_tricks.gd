extends TestCase
## Aerial rotation physics: L = I*w, tuck timing, twist, landing outcomes.

const DT := 1.0 / 60.0


func _air(t: TrickController, seconds: float, tuck: float) -> void:
	for i in range(int(seconds / DT)):
		t.update_air(DT, tuck)


func _launch(id: String, v: float) -> TrickController:
	var t := TrickController.new()
	t.request(id, false)
	t._queued_ms -= 2000   # ordinary timing unless a test says otherwise
	t.on_launch(v)
	return t


func test_angular_momentum_conserved_tuck_spins_faster() -> void:
	var t := _launch("backflip", 3.0)
	_air(t, 0.3, 0.0)
	var w_open := absf(t.omega_pitch)
	_air(t, 0.3, 1.0)
	var w_tuck := absf(t.omega_pitch)
	check(w_tuck > w_open * 3.0, "tuck spins faster: %.1f vs %.1f rad/s" % [w_tuck, w_open])
	check(absf(w_tuck * t.i_tuck - w_open * t.i_layout) < 0.5, "L = I*w is the same open and tucked")


func test_direct_flip_control_accelerates_and_reverses_without_auto_tuck() -> void:
	var t := TrickController.new()
	t.on_launch(3.0)
	for i in 60:
		t.update_air(DT, 0.0, "", -1.0, 0.0)
	check(t.l_pitch < 0.0 and t.pitch < 0.0, "held backflip control builds backward rotation")
	check(is_zero_approx(t.tuck), "flip control does not automatically tuck the athlete")
	for i in 120:
		t.update_air(DT, 0.0, "", 1.0, 0.0)
	check(t.l_pitch > 0.0, "frontflip control reverses pitch momentum in flight")
	check(t.omega_pitch > 0.0 and t.pitch < 0.0,
		"reversal changes angular velocity while preserving the accumulated pose")


func test_direct_twist_control_is_reversible_and_body_shape_is_independent() -> void:
	var t := TrickController.new()
	t.on_launch(3.0)
	for i in 60:
		t.update_air(DT, 0.0, "left_knee", 0.0, -1.0)
	check(t.l_twist < 0.0 and t.yaw < 0.0, "left twist control builds leftward angular momentum")
	check(t.grab == "left_knee" and t.grab_w > 0.9, "one-hand grab reaches its held pose")
	check(is_zero_approx(t.tuck), "one-hand grab does not force a body tuck")
	for i in 120:
		t.update_air(DT, 1.0, "", 0.0, 1.0)
	check(t.l_twist > 0.0, "right twist control reverses twist momentum")
	check(t.tuck > 0.9 and t.grab == "", "tuck and grab release remain independent")


func test_direct_control_scores_multiple_flips_by_direction() -> void:
	var t := TrickController.new()
	t.on_launch(3.0)
	for i in 200:
		t.update_air(DT, 1.0, "", 1.0, 0.0)
	check(t.performed.has("Frontflip"), "first continuous full rotation is scored")
	check(t.performed.has("Frontflip x2"), "second continuous rotation is scored as a repeat")


func test_flip_sized_to_flight_time() -> void:
	# Athletes size the flip to the time in the air: a bigger pop means a
	# longer flight, so less spin is needed for the same single flip.
	var a := _launch("backflip", 2.0)
	var b := _launch("backflip", 4.0)
	check(absf(b.l_pitch) < absf(a.l_pitch), "longer flight, less angular momentum (%.0f vs %.0f)" % [b.l_pitch, a.l_pitch])
	for t in [a, b]:
		var steps := int(t.set_T / DT)
		for i in range(steps):
			t.update_air(DT, t.tuck_hint())
	check(b.landing_outcome() == "clean", "big pop: tuck timing lands it (pitch %.2f after %.2f s)" % [b.pitch, b.set_T])
	# A 0.4 s hop can't turn a full backflip: the legs can only make so much
	# angular momentum (l_max), so it under-rotates instead of spinning
	# impossibly fast.
	check(absf(a.l_pitch) <= a.l_max + 0.01, "spin capped by what the body can generate (%.0f)" % a.l_pitch)
	check(a.landing_outcome() != "clean", "weak hop under-rotates (pitch %.2f after %.2f s)" % [a.pitch, a.set_T])


func test_spin_rate_is_human() -> void:
	# Peak spin of a tucked backflip: elite gymnasts ~12-15 rad/s.
	var t := _launch("backflip", 3.5)
	var peak := 0.0
	for i in range(int(t.set_T / DT)):
		t.update_air(DT, 1.0)
		peak = maxf(peak, absf(t.omega_pitch))
	check(peak <= 15.0, "peak spin %.1f rad/s within human range" % peak)


func test_timed_tuck_lands_clean_and_scores() -> void:
	var t := _launch("backflip", 3.0)
	# Tuck, then open near the end of the rotation.
	for i in range(120):
		t.update_air(DT, 1.0 if absf(t.pitch) < TAU - 1.2 else 0.0)
		if absf(t.pitch) >= TAU - 0.15:
			break
	check(t.landing_outcome() == "clean", "timed tuck lands upright (pitch %.2f)" % t.pitch)
	check(t.on_land(), "clean landing accepted")
	check(t.score >= 500, "backflip scored (%d)" % t.score)


func test_never_tucking_under_rotates() -> void:
	var t := _launch("backflip", 3.0)
	while t.air_t < t.set_T:
		t.update_air(DT, 0.0)
	check(not t.performed.has("Backflip"), "never tucking = no flip (comes back upright, pitch %.2f)" % t.pitch)


func test_over_rotation_saved_or_bailed() -> void:
	var t := _launch("frontflip", 3.0)
	# held the tuck too long: ~1.3 turns at landing
	while t.pitch < TAU + 1.6:
		t.update_air(DT, 1.0)
	var o := t.landing_outcome()
	check(o != "clean", "holding the tuck too long over-rotates (%s, pitch %.2f)" % [o, t.pitch])
	var e := wrapf(t.pitch, -PI, PI)
	if absf(e) < TrickController.SAVE_MAX and absf(e) >= TrickController.SAVE_MIN:
		check(o == "save_chest" or o == "save_back", "near-horizontal miss is saved on chest/back")


func test_save_queues_body_landing() -> void:
	var t := _launch("frontflip", 3.0)
	t.pitch = TAU + 1.2   # over-rotated, face-down
	check(t.on_land(), "save is not a bail")
	check(t.queued_pose == "chest", "over-rotated frontflip lands on the chest")


func test_upside_down_bails() -> void:
	var t := _launch("backflip", 3.0)
	t.pitch = -PI
	check(not t.on_land(), "upside down is a bail")
	check(t.message.begins_with("BAIL"), "bail message")


func test_twist_about_long_axis_finishes() -> void:
	var t := TrickController.new()
	t.request("spin360", false)
	t.on_launch(3.0)
	_air(t, 0.8, 0.5)
	check(absf(t.yaw - TAU) < 0.01, "full twist completes (yaw %.2f)" % t.yaw)
	check(t.on_land(), "twist lands")


func test_combo_flip_plus_twist() -> void:
	var t := TrickController.new()
	t.request("backflip", false)
	t.request("spin360", false)
	t.on_launch(3.4)
	for i in range(120):
		t.update_air(DT, 1.0 if absf(t.pitch) < TAU - 1.2 else 0.0)
		if absf(t.pitch) >= TAU - 0.1 and t.l_twist == 0.0:
			break
	check(t.performed.size() >= 2, "flip and twist both completed %s" % str(t.performed))
	check(t.on_land(), "flip + twist lands")
	check(t.tricks_landed >= 1 and "Full-Twisting Backflip" in t.message, "J+L together becomes the named combo: %s" % t.message)


func test_full_twisting_backflip_combo() -> void:
	var t := _launch("backflip360", 3.0)
	check(t.l_pitch < 0.0 and t.l_twist != 0.0, "combo sets both flip and twist momentum")
	var twist_done_at := -1.0
	for i in range(int(t.set_T / DT)):
		t.update_air(DT, t.tuck_hint())
		if t.l_twist == 0.0 and twist_done_at < 0.0:
			twist_done_at = i * DT
	check(twist_done_at > 0.0, "full twist completes in the air (%.2f s)" % twist_done_at)
	check(t.landing_outcome() == "clean", "lands upright after backflip 360 (pitch %.2f yaw %.2f)" % [t.pitch, t.yaw])
	t.on_land()
	check(t.score >= 1200 and "Full-Twisting" in t.message, "scored as Full-Twisting Backflip (%d, %s)" % [t.score, t.message])


func _fly(t: TrickController) -> void:
	for i in range(int(t.set_T / DT)):
		t.update_air(DT, t.tuck_hint())


func test_flips_from_and_to_body_positions() -> void:
	# The video combo: start position -> flip -> landing position.
	var cases := [["chest", "frontflip", "chest", 360.0], ["chest", "backflip", "butt", -450.0],
		["butt", "backflip", "", -360.0], ["butt", "frontflip", "chest", 450.0], ["chest", "backflip", "", -450.0]]
	for c in cases:
		var t := TrickController.new()
		t.request(c[1], false)
		t.queued_pose = c[2]
		var a0: float = TrickController.POSE_ANGLE[c[0]]
		t.on_launch(3.5, c[0], a0)
		_fly(t)
		var turned := rad_to_deg(t.pitch - a0)
		check(t.landing_outcome() == "clean", "%s %s to %s lands clean (turned %.0f deg, expected %.0f)" % [c[0], c[1], c[2] if c[2] != "" else "feet", turned, c[3]])
		check(absf(turned - c[3]) < 40.0, "%s->%s rotation %.0f deg" % [c[0], c[2], turned])
		t.on_land()
		check(t.message.contains(TrickController.POSE_NAMES[c[0]]), "named after the start position: %s" % t.message)


func test_set_rotation_without_flip() -> void:
	# butt -> chest with no flip: a quarter turn forward from the set alone
	var t := TrickController.new()
	t.queued_pose = "chest"
	t.on_launch(2.5, "butt", 0.0)
	_fly(t)
	check(absf(t.pitch - PI * 0.5) < 0.3, "set turns the body face-down (%.2f rad)" % t.pitch)


func test_landing_target_change_is_atomic_when_too_late() -> void:
	var t := TrickController.new()
	t.queued_pose = "back"
	t.on_launch(3.5, "back", TrickController.POSE_ANGLE["back"])
	t.air_t = t.set_T * 0.6
	var target_before := t.land_target
	check(not t.set_landing("chest"), "late target change is rejected")
	check(is_equal_approx(t.land_target, target_before), "rejected target does not change rotation target")
	check(t.set_landing("back"), "reselecting the current target is accepted")


## Hold to spin, release to open: the partial assist brings an opened-out
## rotation to the nearest landable orientation by touchdown.
func _hold_until(t: TrickController, release_at: float) -> float:
	while absf(t.pitch) < release_at and t.air_t < t.set_T:
		t.update_air(DT, 1.0)
	while t.air_t < t.set_T:
		t.update_air(DT, 0.0)
	return t.pitch


func test_hold_release_full_flip_lands() -> void:
	var p := _hold_until(_launch("backflip", 3.0), TAU - 1.6)
	check(absf(absf(p) - TAU) < TrickController.LAND_TOLERANCE, "held most of the turn, released: lands the full flip (pitch %.2f)" % p)


func test_hold_release_little_bit_lands_back_upright() -> void:
	var p := _hold_until(_launch("backflip", 3.0), 0.8)
	check(absf(p) < TrickController.LAND_TOLERANCE, "released after a little bit: back to upright (pitch %.2f)" % p)


func test_perfect_timing_spins_faster() -> void:
	var a := TrickController.new()
	a.request("backflip", false)
	a.on_launch(4.5)
	var b := TrickController.new()
	b.request("backflip", false)
	b._queued_ms -= 2000   # pressed long before takeoff
	b.on_launch(4.5)
	check(a.timing == "perfect" and b.timing == "ok", "timing graded (%s / %s)" % [a.timing, b.timing])
	check(absf(a.l_pitch) > absf(b.l_pitch) * 1.1, "perfect timing gives more spin (%.1f vs %.1f)" % [absf(a.l_pitch), absf(b.l_pitch)])
