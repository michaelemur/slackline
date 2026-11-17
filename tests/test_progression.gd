extends TestCase
## Skill energy must be earned, capped, spent once, and applied through leg force.

const ReboundMeterScript := preload("res://scripts/athlete/rebound_meter.gd")

func test_meter_caps_charge_and_only_spends_when_full() -> void:
	var meter = ReboundMeterScript.new()
	check(is_zero_approx(meter.consume()), "partial meter cannot activate Super Rebound")
	meter.earn(0.6)
	meter.earn(0.7)
	check(is_equal_approx(meter.charge, 1.0), "earned charge is capped at capacity")
	check(meter.is_ready(), "full meter is ready")
	check(is_equal_approx(meter.consume(), 1.0), "ready meter spends one full charge")
	check(is_zero_approx(meter.charge) and not meter.is_ready(), "charge cannot be spent twice")

func test_only_clean_scored_landings_earn_charge() -> void:
	var athlete := Athlete.new()
	athlete.tricks.landed.connect(Callable(athlete, "_on_tricks_landed"))
	athlete.state = Athlete.State.AIRBORNE
	athlete.tricks.last_outcome = "clean"
	athlete.tricks.landed.emit(["Backflip"], 500)
	check(athlete.rebound_meter.charge > 0.0, "clean scored trick earns energy through the real signal")
	var charge: float = athlete.rebound_meter.charge
	athlete.tricks.last_outcome = "save_back"
	athlete.tricks.landed.emit(["Backflip"], 250)
	check(is_equal_approx(athlete.rebound_meter.charge, charge), "saved landing does not earn clean-landing energy")
	athlete.free()

func test_full_charge_activates_only_during_a_push() -> void:
	var athlete := Athlete.new()
	athlete.rebound_meter.earn(1.0)
	athlete._push_left = 0.2
	athlete._update_rebound_boost()
	check(athlete._super_rebound_active and is_zero_approx(athlete.rebound_meter.charge),
		"full meter is consumed at push start")
	check(is_equal_approx(athlete.leg.rebound_boost, 1.0), "push receives the actuator boost")
	athlete._push_left = 0.0
	athlete._update_rebound_boost()
	check(not athlete._super_rebound_active and is_zero_approx(athlete.leg.rebound_boost),
		"boost ends when the push phase ends")
	athlete.free()

func test_boost_increases_the_physical_leg_force_limit() -> void:
	var params := SlacklineParams.new()
	var solver := SlacklineSolver.new()
	solver.setup(params, Vector3.ZERO, Vector3(10, 0, 0))
	var base := _leg_force(solver, 0.0)
	var boosted := _leg_force(solver, 1.0)
	check(boosted > base, "Super Rebound increases the actuator force limit, not launch velocity")

func _leg_force(solver: SlacklineSolver, boost: float) -> float:
	var leg := LegModel.new()
	leg.rebound_boost = boost
	leg.begin_contact(solver, 5.0, 0.8, 0.0)
	leg.target = 0.96
	leg.active_target = 0.96
	leg.pre_substep(solver, 0.001)
	return leg.force
