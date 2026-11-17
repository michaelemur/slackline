extends TestCase
## Touch controls must feed the same AthleteInput fields as keyboard input.
const TouchControlsScript := preload("res://scripts/ui/touch_controls.gd")

func test_two_finger_axes_are_independent_and_release_cleanly() -> void:
	InputSetup.ensure_actions()
	var input := AthleteInput.new()
	var controls := TouchControlsScript.new()
	controls.athlete_input = input
	controls.safe_rect = Rect2(0, 0, 1280, 720)
	var move_center: Vector2 = controls._pad_center(true)
	var balance_center: Vector2 = controls._pad_center(false)
	controls._touch_down(4, move_center + Vector2(controls.PAD_RADIUS, 0))
	controls._touch_down(9, balance_center - Vector2(controls.PAD_RADIUS, 0))
	check(is_equal_approx(input.touch_move_axis, 1.0), "move pointer sets forward axis")
	check(is_equal_approx(input.touch_balance_axis, -1.0), "second pointer independently sets balance")
	input.poll()
	check(is_equal_approx(input.move_axis, 1.0) and is_equal_approx(input.balance_axis, -1.0),
		"AthleteInput poll receives both simultaneous touch axes")
	controls._touch_up(4)
	check(is_zero_approx(input.touch_move_axis) and is_equal_approx(input.touch_balance_axis, -1.0),
		"releasing movement does not cancel balance pointer")
	controls._touch_up(9)
	check(is_zero_approx(input.touch_balance_axis), "balance returns to neutral on release")
	controls.free()
	input.free()

func test_jump_hold_and_trick_tap_map_to_input() -> void:
	InputSetup.ensure_actions()
	var input := AthleteInput.new()
	var controls := TouchControlsScript.new()
	controls.athlete_input = input
	controls.safe_rect = Rect2(0, 0, 1280, 720)
	controls._touch_down(2, controls._pump_center())
	check(input.touch_pump_held, "jump control holds pump input")
	controls._touch_up(2)
	check(not input.touch_pump_held, "jump control releases pump input")
	controls._touch_down(3, controls._trick_center(0))
	input.poll()
	check(input.flip_axis == -1.0, "held backflip control routes torque input through AthleteInput")
	controls._touch_up(3)
	check(is_zero_approx(input.touch_flip_axis), "releasing rotation control removes torque input")
	controls._touch_down(4, controls._trick_center(4))
	input.poll()
	check(input.grab == "left_knee", "left grab button controls one hand independently")
	controls._touch_down(5, controls._trick_center(5))
	input.poll()
	check(input.grab == "both_knees", "holding both grab buttons controls both hands")
	controls._touch_up(4)
	input.poll()
	check(input.grab == "knee", "releasing one hand preserves the other hand grab")
	controls._touch_up(5)
	controls.free()
	input.free()
