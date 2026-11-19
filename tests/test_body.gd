extends TestCase
## Body dynamics, balance skill, grabs, bounce positions, COM.

const DT := 1.0 / 60.0


func _visual() -> AthleteVisual:
	var v := AthleteVisual.new()
	v._ready()
	return v


func _settle(v: AthleteVisual, ctx: Dictionary, pose := "", pb := 0.0, secs := 1.5) -> void:
	for i in int(secs / DT):
		v.set_body(0.0, 0.0, 0.85, 0.85, 0.0, 1.0)
		v.set_trick_rotation(0.0, 0.0)
		v.set_line_pose(pose, pb, 0.0, 1.0)
		v.apply_body(ctx, DT)
		v.character.update(DT)


func _b(v: AthleteVisual, bn: String) -> Vector3:
	return v.character.position + (v.character.last_pose[v.character._idx[bn]] as Transform3D).origin


func test_balance_needs_the_player() -> void:
	# On a still line: no input -> topples; a player's corrections -> stays up.
	for mode in ["none", "player"]:
		var b := BalanceController.new()
		b.reset(0.02)
		var fell := -1.0
		for i in range(int(20.0 / DT)):
			var inp := 0.0
			if mode == "player":
				inp = clampf(-(2.2 * b.theta_seen + 0.6 * b.omega_seen), -1.0, 1.0)
			b.step(DT, inp, 0.0, 0.0)
			if b.fallen:
				fell = i * DT
				break
		if mode == "none":
			check(fell > 0.0 and fell < 15.0, "no input: falls (after %.1f s)" % fell)
		else:
			check(fell < 0.0, "player corrections keep him up for 20 s")


func test_forward_back_limited_by_the_feet() -> void:
	var b := BalanceController.new()
	b.reset()
	b.phi_dot = 0.3
	for i in range(120):
		b.step_fb(DT, 0.0)
	check(not b.fallen and absf(b.phi) < 0.1, "small forward nudge: the feet hold it (phi %.2f)" % b.phi)
	b.reset()
	b.phi_dot = 2.5
	for i in range(120):
		b.step_fb(DT, 0.0)
	check(b.fallen, "big forward push: beyond what the feet can hold -> falls")


func test_lifted_leg_is_a_counterweight() -> void:
	var b := BalanceController.new()
	b.reset()
	b.leg_lift_l = 1.0
	b.arm_left = b.arm_rest
	b.arm_right = b.arm_rest
	# 20 % of 75 kg x 9.81 x 0.28 m = 41 N m toward the lifted side
	check(b.arm_torque() < -35.0, "left leg out pulls the body left (%.0f N m)" % b.arm_torque())


func test_independent_legs_single_leg() -> void:
	var v := _visual()
	_settle(v, {"state": 0, "lift_l": 1.0, "lift_r": 0.0})
	var l := _b(v, "foot_l")
	var r := _b(v, "foot_r")
	check(l.y - r.y > 0.05, "left foot lifted off the line (%.2f m above the right)" % (l.y - r.y))
	check(absf(r.y - (v.character._rest_v[v.character._idx["foot_r"]] as Transform3D).origin.y) < 0.05, "right foot stays on the line")
	v.free()


func test_back_bounce_legs_45_deg() -> void:
	var v := _visual()
	_settle(v, {"state": 0, "pose": "back", "pose_b": 1.0}, "back", 1.0)
	v.character.contact_target = 0.0
	v.character.contact = 0.0
	_settle(v, {"state": 0, "pose": "back", "pose_b": 1.0}, "back", 1.0, 0.5)
	var hip := (_b(v, "thigh_l") + _b(v, "thigh_r")) * 0.5
	var knee := (_b(v, "calf_l") + _b(v, "calf_r")) * 0.5
	var d := knee - hip
	var elev := rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length()))
	check(elev > 35.0 and elev < 55.0, "legs point up %.0f deg above horizontal (target 45)" % elev)
	var sep := rad_to_deg((_b(v, "calf_l") - _b(v, "thigh_l")).angle_to(_b(v, "calf_r") - _b(v, "thigh_r")))
	check(sep > 10.0 and sep < 70.0, "legs open in a V (%.0f deg apart)" % sep)
	v.free()


func test_chest_bounce_asymmetric() -> void:
	var v := _visual()
	v.character.contact_target = 0.0
	v.character.contact = 0.0
	var lp := Vector3(-0.02, 0.03, -0.62)
	_settle(v, {"state": 0, "pose": "chest", "pose_b": 1.0, "line_pt": lp}, "chest", 1.0)
	# Brief (Nov 18): left hand grips the line near the head, right hand free,
	# left leg extended, right leg bent, the chest resting ON the line.
	var dl := _b(v, "hand_l").distance_to(lp)
	check(dl < 0.2, "left hand on the line beside the head (%.2f m)" % dl)
	check(_b(v, "hand_r").distance_to(lp) > 0.35, "right hand free")
	var bend_l := (_b(v, "calf_l") - _b(v, "thigh_l")).angle_to(_b(v, "foot_l") - _b(v, "calf_l"))
	var bend_r := (_b(v, "calf_r") - _b(v, "thigh_r")).angle_to(_b(v, "foot_r") - _b(v, "calf_r"))
	check(bend_r > bend_l + 0.6, "right knee bent (%.0f deg), left leg long (%.0f deg)" % [rad_to_deg(bend_r), rad_to_deg(bend_l)])
	check(_b(v, "spine_03").y > 0.05 and _b(v, "pelvis").y > 0.0, "chest and hips rest on top of the line (%.2f / %.2f m)" % [_b(v, "spine_03").y, _b(v, "pelvis").y])
	v.free()


func test_lying_positions_do_not_pin_the_feet_to_the_line() -> void:
	for pose in ["chest", "back"]:
		var v := _visual()
		_settle(v, {"state": 0, "pose": pose, "pose_b": 1.0, "line_pt": Vector3(-0.02, 0.03, -0.62)}, pose, 1.0)
		var feet_on_line := _b(v, "foot_l").length() < 0.15 and _b(v, "foot_r").length() < 0.15
		check(not feet_on_line, "%s: feet are not folded back onto the contact point" % pose)
		v.free()


func test_grab_hands_reach_the_knees() -> void:
	var v := _visual()
	v.character.contact_target = 0.0
	v.character.contact = 0.0
	_settle(v, {"state": 1, "grab": "both_knees", "grab_w": 1.0})
	for side in ["l", "r"]:
		var d := _b(v, "hand_" + side).distance_to(_b(v, "calf_" + side))
		check(d < 0.16, "%s hand on the %s knee (%.2f m)" % [side, side, d])
	v.free()


func test_grab_changes_spin_and_scores() -> void:
	var w := {}
	for mode in ["open", "both_knees", "tuck"]:
		var t := TrickController.new()
		t.queued = "backflip"
		t.on_launch(3.5)
		var peak := 0.0
		for i in range(30):
			t.update_air(DT, 0.0, mode if mode != "open" else "")
			peak = maxf(peak, absf(t.omega_pitch))
		w[mode] = peak
		if mode == "both_knees":
			check(t.performed.has("Double Knee Grab"), "held grab counts as a trick")
	check(w["open"] < w["both_knees"] and w["both_knees"] < w["tuck"] + 0.01,
		"grab spins faster than open, not faster than a full tuck (%.1f / %.1f / %.1f rad/s)" % [w["open"], w["both_knees"], w["tuck"]])


func test_com_is_segment_weighted() -> void:
	var v := _visual()
	_settle(v, {"state": 0})
	var com := v.character.com
	var pel := _b(v, "pelvis")
	check(com.y > 0.85 and com.y < 1.15, "standing COM height %.2f m (~56%% of 1.75 m)" % com.y)
	check(Vector2(com.x - pel.x, com.z - pel.z).length() < 0.08, "standing COM over the pelvis")
	v.free()
