extends TestCase
## Two-zone touch controls feed the same AthleteInput intents as the keyboard.
const TouchControlsScript := preload("res://scripts/ui/touch_controls.gd")


func _make(rect: Rect2) -> Array:
	InputSetup.ensure_actions()
	var input := AthleteInput.new()
	var controls := TouchControlsScript.new()
	controls.athlete_input = input
	controls.safe_rect = rect
	return [input, controls]


func _free(pair: Array) -> void:
	pair[1].free()
	pair[0].free()


func test_both_hands_work_at_the_same_time() -> void:
	var p := _make(Rect2(0, 0, 1280, 720))
	var input: AthleteInput = p[0]
	var c = p[1]
	c._touch_down(1, c.pad_point("right"))     # left thumb: CHEST on the position pad
	c._touch_down(2, Vector2(1000, 550))       # right thumb: hold (pump)
	c._touch_drag(2, Vector2(1000, 490))       # drag up: aim back
	input.poll()
	check(input.hold and input.pump_held and input.tuck == 1.0, "right thumb hold = pump / tuck")
	check(input.trick == "chest", "left thumb toward the right = chest (%s)" % input.trick)
	check(input.aim.y > 0.9, "drag up while holding aims a backflip (%.2f)" % input.aim.y)
	c._touch_up(1)
	input.poll()
	check(input.hold, "lifting the left thumb keeps the right hold")
	c._touch_up(2)
	input.poll()
	check(not input.hold and input.aim == Vector2.ZERO, "lifting the right thumb releases (= drive / open)")
	check(input.jump_released, "release is seen as the push")
	_free(p)


func test_drag_down_is_frontflip_and_sideways_is_twist() -> void:
	var p := _make(Rect2(0, 0, 1280, 720))
	var input: AthleteInput = p[0]
	var c = p[1]
	c._touch_down(3, Vector2(1000, 500))
	c._touch_drag(3, Vector2(1060, 560))
	input.poll()
	check(input.aim.y < -0.5 and input.aim.x > 0.5, "down-right drag: frontflip lean with right twist (%s)" % input.aim)
	check(input.aim.length() <= 1.0001, "aim is bounded")
	c._touch_up(3)
	_free(p)


func test_position_pad_directions_choose_the_landing() -> void:
	var p := _make(Rect2(0, 0, 1280, 720))
	var input: AthleteInput = p[0]
	var c = p[1]
	for dir in ["up", "down", "left", "right"]:
		c._touch_down(1, c.pad_point(dir))
		input.poll()
		check(input.trick == c.PAD_IDS[dir], "pad %s = %s (%s)" % [dir, c.PAD_IDS[dir], input.trick])
		input.poll()
		check(input.trick == "", "holding the thumb does not repeat the choice")
		c._touch_up(1)
	# slide from FEET to BACK: re-chooses once per new direction
	c._touch_down(2, c.pad_point("up"))
	input.poll()
	c._touch_drag(2, c.pad_point("left"))
	input.poll()
	check(input.trick == "back", "sliding to the left re-chooses the back (%s)" % input.trick)
	c._touch_drag(2, c.pad_center())
	input.poll()
	check(input.trick == "", "back to the centre chooses nothing")
	c._touch_up(2)
	check(c.pad_center().x < c.safe_rect.get_center().x, "pad is on the left-hand side")
	check(c.PAD_IDS.values().size() == 4 and c.PAD_IDS.values().has("feet"), "feet, butt, chest and back on the pad")
	_free(p)


func test_grab_and_positions_are_independent_buttons() -> void:
	var p := _make(Rect2(0, 0, 1280, 720))
	var input: AthleteInput = p[0]
	var c = p[1]
	c._touch_down(4, c._button_center(0))
	input.poll()
	check(input.grab_held and input.grab == "leg", "grab while straight holds the legs")
	c._touch_down(5, Vector2(1000, 550))
	input.poll()
	check(input.grab == "both_knees" and input.tuck == 1.0, "grab while tucked holds the knees")
	c._touch_up(5)
	c._touch_up(4)
	input.poll()
	check(input.grab == "", "grab released")
	c._touch_down(6, c.pad_point("down"))
	input.poll()
	check(input.trick == "butt" and not input.hold, "position pad never starts a hold")
	c._touch_up(6)
	_free(p)


func test_buttons_stay_inside_small_and_tall_safe_areas() -> void:
	for rect in [Rect2(24, 24, 792, 327), Rect2(20, 24, 350, 790), Rect2(44, 0, 2400, 1080)]:
		var p := _make(rect)
		var c = p[1]
		var r: float = c._button_radius()
		for i in c.ACTION_LABELS.size():
			var center: Vector2 = c._button_center(i)
			check(rect.grow(0.5).encloses(Rect2(center - Vector2(r, r), Vector2(r, r) * 2.0)),
				"%s inside safe area %s" % [c.ACTION_LABELS[i], rect])
			check(not c._is_left(center), "%s is on the right-hand side" % c.ACTION_LABELS[i])
		var pr: float = c._pad_radius() * 0.42
		for dir in ["up", "down", "left", "right"]:
			var pp: Vector2 = c.pad_point(dir)
			check(rect.grow(0.5).encloses(Rect2(pp - Vector2(pr, pr), Vector2(pr, pr) * 2.0)),
				"pad %s inside safe area %s" % [dir, rect])
			check(c._is_left(pp), "pad %s is on the left-hand side" % dir)
		_free(p)


func test_left_thumb_down_is_the_sticky_grip() -> void:
	var p := _make(Rect2(0, 0, 1280, 720))
	var input: AthleteInput = p[0]
	var c = p[1]
	c._touch_down(1, c.pad_point("down"))
	input.poll()
	check(input.grip_held and not input.grab_held, "left thumb down = grip the line (not an air grab)")
	c._touch_up(1)
	input.poll()
	check(not input.grip_held, "lifting the left thumb lets go")
	_free(p)
