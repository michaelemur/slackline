extends TestCase
## Free aerial control: flip, flip speed, twist, twist speed, tuck/open, leg
## shapes and grabs are all independent and available the whole flight.
## Angular momentum carries over smoothly when inputs change.

const DT := 1.0 / 60.0


func _flight(v: float = 5.0) -> TrickController:
	var t := TrickController.new()
	t.on_launch(v)
	return t


func _step(t: TrickController, n: int, tuck: float = 0.0, grab: String = "", flip: float = 0.0, twist: float = 0.0) -> void:
	for i in n:
		t.update_air(DT, tuck, grab, flip, twist)


func test_flip_can_start_any_time_in_the_air() -> void:
	for start_at in [0.05, 0.4, 0.7]:
		var t := _flight()
		_step(t, int(start_at / DT))
		check(absf(t.omega_pitch) < 0.05, "no rotation before the player asks (%.2f s)" % start_at)
		_step(t, 20, 0.0, "", 1.0)
		check(t.omega_pitch > 1.0, "frontflip starts %.2f s into the jump (%.1f rad/s)" % [start_at, t.omega_pitch])


func test_flip_direction_reverses_smoothly() -> void:
	var t := _flight()
	_step(t, 30, 0.0, "", -1.0)
	var w0 := t.omega_pitch
	check(w0 < -1.0, "backflip rotation built (%.1f rad/s)" % w0)
	var max_jump := 0.0
	var prev := t.pitch
	var prev_w := t.omega_pitch
	var max_dw := 0.0
	for i in 60:
		t.update_air(DT, 0.0, "", 1.0, 0.0)
		max_jump = maxf(max_jump, absf(t.pitch - prev))
		max_dw = maxf(max_dw, absf(t.omega_pitch - prev_w))
		prev = t.pitch
		prev_w = t.omega_pitch
	check(t.omega_pitch > 0.0, "rotation reversed into a frontflip (%.1f rad/s)" % t.omega_pitch)
	check(max_jump < 0.3, "no snap in the body angle (max %.3f rad per frame)" % max_jump)
	check(max_dw < 1.0, "spin changes gradually, momentum carried over (max %.2f rad/s per frame)" % max_dw)


func test_flip_speed_from_tuck_and_shapes() -> void:
	var t := _flight()
	_step(t, 30, 0.0, "", 1.0)
	var l := t.l_pitch
	_step(t, 1)
	var w_open := t.omega_pitch
	_step(t, 30, 1.0)
	var w_tuck := t.omega_pitch
	check(w_tuck > w_open * 2.5, "tuck spins faster (%.1f vs %.1f)" % [w_tuck, w_open])
	check(absf(t.l_pitch - l) < 0.5, "tucking keeps the angular momentum (L %.1f -> %.1f)" % [l, t.l_pitch])
	_step(t, 30, 0.0)
	check(absf(t.omega_pitch - w_open) < 0.5, "opening again slows it back down")
	_step(t, 30, 1.0)
	check(t.omega_pitch > w_open * 2.5, "and tucking again speeds it up (repeatable)")
	_step(t, 30, 0.0)
	var w_layout := t.omega_pitch
	_step(t, 30, 0.0, "pike")
	var w_pike := t.omega_pitch
	_step(t, 30, 0.0, "split")
	var w_split := t.omega_pitch
	check(w_pike > w_layout * 1.4 and w_split < w_pike, "leg shapes change the spin: layout %.1f, pike %.1f, split %.1f" % [w_layout, w_pike, w_split])


func test_twist_added_removed_and_reversed_any_time() -> void:
	var t := _flight()
	_step(t, 20, 0.0, "", 1.0)          # flipping
	_step(t, 20, 0.0, "", 1.0, 1.0)     # add right twist while flipping
	check(t.l_twist > 0.5 and t.omega_pitch > 1.0, "twist added during a flip, flip continues")
	var tw := t.l_twist
	_step(t, 40, 0.0, "", 0.0, -1.0)    # reverse the twist
	check(t.l_twist < 0.0 and t.l_twist < tw, "twist reversed to the left (%.1f)" % t.l_twist)
	var y0 := t.yaw
	_step(t, 30, 0.0, "", 0.0, 1.0)     # and back toward zero
	var it := lerpf(t.i_twist_open, t.i_twist_in, 0.5)
	check(absf(t.l_twist) < 3.0, "twist can be taken out again (L %.1f)" % t.l_twist)
	check(absf(t.yaw - y0) < 10.0, "yaw stays continuous (%.2f -> %.2f, I %.2f)" % [y0, t.yaw, it])


func test_grabs_independent_of_rotation() -> void:
	var t := _flight()
	_step(t, 20, 0.0, "", -1.0)
	var l := t.l_pitch
	_step(t, 20, 0.0, "both_knees", -1.0)
	check(t.grab == "both_knees" and t.grab_w > 0.9, "grab taken while flipping")
	check(t.l_pitch < l, "flip input still works while grabbing")
	_step(t, 30, 0.0, "", 0.0)
	check(t.grab_w < 0.05, "grab released, rotation continues (%.1f rad/s)" % t.omega_pitch)
	check(absf(t.omega_pitch) > 0.5, "released grab does not stop the spin")
	_step(t, 20, 1.0, "cross", 0.0, 1.0)
	check(t.grab == "cross" and t.tuck > 0.9 and t.l_twist > 0.0, "grab + tuck + twist all at once")


func test_control_kept_until_landing_even_when_locked() -> void:
	var t := _flight(5.0)
	var steps := int(t.set_T / DT)
	for i in steps:
		var left := t.set_T - t.air_t
		t.land_eta = left
		if not t.locked and left < 0.6:
			t.lock_landing("feet", left)
		# the player keeps spinning him through the lock
		t.update_air(DT, 0.0, "", 1.0 if left < 0.6 else 0.0)
	check(t.locked, "landing was locked")
	check(t.omega_pitch > 2.0, "a lock never overrides the player's rotation (%.1f rad/s)" % t.omega_pitch)


func test_settle_assist_after_letting_go() -> void:
	# Spin a bit, let go: the open body settles onto a landable angle.
	var t := _flight(5.5)
	_step(t, 18, 0.0, "", 1.0)
	while t.air_t < t.set_T:
		t.update_air(DT, 0.0)
	check(t.landing_outcome() != "bail", "let go after a short spin: lands (%s, pitch %.2f)" % [t.landing_outcome(), t.pitch])
