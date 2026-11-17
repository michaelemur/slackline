extends TestCase
## BalanceController behaviour tests.

const DT := 1.0 / 60.0


func _sim(b: BalanceController, seconds: float, input_fn: Callable = Callable()) -> float:
	var worst := 0.0
	for i in range(int(seconds / DT)):
		var u := 0.0
		if input_fn.is_valid():
			u = input_fn.call(b)
		b.step(DT, u, 0.0, 0.0)
		worst = maxf(worst, absf(b.theta))
		if b.fallen:
			break
	return worst


func test_assist_recovers_small_lean() -> void:
	var b := BalanceController.new()
	b.assist = 0.8
	b.reset(0.08)
	_sim(b, 6.0)
	check(not b.fallen, "assisted athlete does not fall")
	check(absf(b.theta) < 0.01, "assisted lean settles, theta=%.4f" % b.theta)


func test_no_assist_no_input_falls() -> void:
	var b := BalanceController.new()
	b.assist = 0.0
	b.reset(0.05)
	_sim(b, 4.0)
	check(b.fallen, "unassisted, uncontrolled athlete falls (inverted pendulum)")


func test_player_can_balance_without_assist() -> void:
	var b := BalanceController.new()
	b.assist = 0.0
	b.reset(0.1)
	# A competent "player": PD on lean with saturated stick input.
	var player := func(bc: BalanceController) -> float:
		return clampf(-(2.5 * bc.theta + 0.7 * bc.omega), -1.0, 1.0)
	_sim(b, 8.0, player)
	check(not b.fallen, "skilled input keeps balance with zero assist")


func test_lateral_foot_accel_tips_athlete() -> void:
	var b := BalanceController.new()
	b.assist = 0.6
	b.reset(0.0)
	b.step(DT, 0.0, 3.0, 0.0)  # line jerks toward +lateral
	check(b.omega < 0.0, "foot accelerating right tips body left")


func test_bouncing_changes_effective_gravity() -> void:
	var a := BalanceController.new()
	var c := BalanceController.new()
	a.assist = 0.0
	c.assist = 0.0
	a.reset(0.1)
	c.reset(0.1)
	a.step(DT, 0.0, 0.0, 0.0)
	c.step(DT, 0.0, 0.0, 8.0)   # line accelerating up = heavier
	check(c.omega > a.omega, "upward line acceleration increases toppling torque")


func test_reaction_force_opposes_correction() -> void:
	var b := BalanceController.new()
	b.reset(0.0)
	b.step(DT, 1.0, 0.0, 0.0)  # throw body toward +lateral
	check(b.reaction_lateral_force(75.0) < 0.0, "line is pushed opposite to body correction")
