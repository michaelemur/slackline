extends TestCase
## Chest / back landings: the position the player chooses wins when the
## rotation is close enough, and chest and back never swap (from the feet,
## the butt and the chest; with and without a half twist).

const DT := 1.0 / 60.0
const STARTS := ["feet", "butt", "chest"]
const LYING := ["chest", "back"]
const OPPOSITE := {"chest": "back", "back": "chest"}


func _start_angle(start: String) -> float:
	return TrickController.POSE_ANGLE.get(start, 0.0)


## A body about to touch down, `miss` rad (facing) off the chosen position.
func _at_touchdown(start: String, target: String, miss: float, half_twist: bool, spin: float) -> TrickController:
	var t := TrickController.new()
	t.queued_pose = target
	t.on_launch(3.5, start if start != "feet" else "", _start_angle(start))
	t.land_target = TrickController.POSE_ANGLE[target]
	t.yaw = PI if half_twist else 0.0
	t.l_pitch = spin
	var facing: float = TrickController.POSE_ANGLE[target] + miss
	t.pitch = TrickController.raw_angle_for(facing, half_twist) + TAU * signf(spin)
	return t


func test_chosen_lying_position_never_swaps_to_the_other() -> void:
	var swaps := 0
	var cases := 0
	for start: String in STARTS:
		for target: String in LYING:
			for tw in [false, true]:
				for spin in [-30.0, 0.0, 30.0]:
					var miss := -2.6
					while miss <= 2.6:
						var t := _at_touchdown(start, target, miss, tw, spin)
						var o := t.landing_outcome()
						cases += 1
						if o == "save_" + OPPOSITE[target]:
							swaps += 1
							failures.append("[%s] %s -> %s miss %.2f twist %s spin %.0f landed %s" % [current, start, target, miss, tw, spin, o])
						miss += 0.1
	check(swaps == 0, "chest/back never swap (%d of %d touchdowns)" % [swaps, cases])


func test_chosen_position_wins_when_close_enough() -> void:
	for start: String in STARTS:
		for target: String in ["butt", "chest", "back"]:
			for tw in [false, true]:
				for miss in [-1.1, -0.8, -0.4, 0.0, 0.4, 0.8, 1.1]:
					var t := _at_touchdown(start, target, miss, tw, 20.0)
					var o := t.landing_outcome()
					check(o == "clean" or o == "save_" + target,
						"%s -> %s, %.1f rad off (twist %s): lands %s (got %s)" % [start, target, miss, tw, target, o])
					var tl := _at_touchdown(start, target, miss, tw, 20.0)
					tl.on_land()
					check(tl.landing_pose == target, "%s -> %s %.1f: queued landing is the chosen one (%s)" % [start, target, miss, tl.landing_pose])


func test_over_rotated_chest_past_upside_down_bails_not_back() -> void:
	# Spinning forward far past face-down: head-down, not lying on the back.
	var t := _at_touchdown("feet", "chest", 2.0, false, 30.0)
	var o := t.landing_outcome()
	check(o == "bail", "far over-rotated onto the chest is a fail, not the back (%s)" % o)
	check(t.bail_kind == "over", "it is an over-rotation (%s)" % t.bail_kind)
	var u := _at_touchdown("butt", "back", 2.0, false, -30.0)
	check(u.landing_outcome() != "save_chest", "under-rotated back never lands on the chest")


func test_half_twist_faces_the_other_way() -> void:
	# Pitched +90 deg with half a twist the face points UP: that is the back.
	var t := TrickController.new()
	t.yaw = PI
	t.pitch = PI * 0.5
	check(is_equal_approx(t.facing_pitch(), -PI * 0.5), "half twist mirrors the facing angle")
	t.queued_pose = "back"
	t.land_target = TrickController.POSE_ANGLE["back"]
	check(t.landing_outcome() == "clean", "face-up after a half twist lands on the back")
	t.queued_pose = "chest"
	t.land_target = TrickController.POSE_ANGLE["chest"]
	check(t.landing_outcome() != "clean" and t.landing_outcome() != "save_back",
		"chest chosen while face-up is not called a chest landing, nor swapped (%s)" % t.landing_outcome())


## A whole flight: launch from a position, an optional flip / lean set, the
## player opens the tuck, then locks the landing late in the jump.
func _fly_and_lock(start: String, target: String, flip: String, lean_l: float, lock_at: float, twist_l: float = 0.0) -> TrickController:
	var t := TrickController.new()
	if flip != "":
		t.request(flip, false)
		t._queued_ms -= 2000
	t.queued_pose = start if start != "feet" else ""
	t.on_launch(4.0, start if start != "feet" else "", _start_angle(start))
	if lean_l != 0.0 or twist_l != 0.0:
		t.launch_spin(lean_l, twist_l)
	var did_lock := false
	while t.air_t < t.set_T:
		var left := t.set_T - t.air_t
		t.land_eta = left
		if not did_lock and left <= lock_at:
			t.lock_landing(target, left)
			did_lock = true
		t.update_air(DT, t.tuck_hint() if flip != "" and not t.locked else 0.0)
	return t


func test_locked_chest_and_back_land_from_feet_butt_and_chest() -> void:
	for start: String in STARTS:
		for target: String in LYING:
			for flip in ["", "frontflip", "backflip"]:
				var t := _fly_and_lock(start, target, flip, 0.0, 0.45)
				var o := t.landing_outcome()
				check(o != "save_" + OPPOSITE[target], "%s %s -> %s never lands on the %s (%s)" % [start, flip, target, OPPOSITE[target], o])
				if flip == "":
					check(o == "clean", "%s -> %s locked 0.45 s before touchdown lands clean (%s, facing %.2f)" % [start, target, o, t.facing_pitch()])
				t.on_land()


func test_lean_against_the_set_still_lands_the_chosen_position() -> void:
	# Jumping to chest from the feet while leaning back (the pumping lean)
	# used to cancel the forward quarter turn and drop him on his back.
	for lean in [-25.0, -12.0, 12.0, 25.0]:
		for target: String in LYING:
			var t := _fly_and_lock("feet", target, "", lean, 0.5)
			var o := t.landing_outcome()
			check(o == "clean" or o == "save_" + target, "feet -> %s with lean L %.0f lands the %s (%s, facing %.2f)" % [target, lean, target, o, t.facing_pitch()])


func test_half_twist_jump_to_chest_lands_face_down() -> void:
	for target: String in LYING:
		var t := _fly_and_lock("butt", target, "", 0.0, 0.5, 3.5)
		check(t.twisted(), "the jump twisted half a turn (yaw %.2f)" % t.yaw)
		var o := t.landing_outcome()
		check(o == "clean", "half-twisted jump locked to %s lands it (%s, facing %.2f)" % [target, o, t.facing_pitch()])


func test_lock_window_and_timing() -> void:
	var t := TrickController.new()
	t.on_launch(4.0)
	check(t.lock_landing("chest", TrickController.LOCK_WINDOW + 0.2) == "early", "too early is not a lock")
	check(not t.locked, "early press leaves the landing open")
	check(t.lock_landing("chest", 0.2) == "locked" and t.lock_quality == "perfect", "last moment = perfect lock")
	var u := TrickController.new()
	u.on_launch(4.0)
	u.lock_landing("feet", 0.6)
	check(u.locked and u.queued_pose == "" and u.lock_quality == "ok", "feet lock, ordinary timing")


func test_tuck_held_too_long_over_rotates_even_when_locked() -> void:
	# Locking does not save a flip the player never opened.
	var t := TrickController.new()
	t.request("backflip", false)
	t._queued_ms -= 2000
	t.on_launch(4.0)
	var locked := false
	while t.air_t < t.set_T:
		var left := t.set_T - t.air_t
		t.land_eta = left
		if not locked and left < 0.4:
			t.lock_landing("feet", left)
			locked = true
		t.update_air(DT, 1.0)      # never opens
	var o := t.landing_outcome()
	check(o != "clean", "tuck held the whole flight is not clean (%s, pitch %.2f)" % [o, t.pitch])
