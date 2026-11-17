class_name ReboundMeter
extends RefCounted
## Skill-earned reserve spent by the leg actuator during a later push phase.

const CAPACITY := 1.0
var charge: float = 0.0
var total_earned: float = 0.0
var total_spent: float = 0.0

func earn(amount: float) -> float:
	var accepted := clampf(amount, 0.0, CAPACITY - charge)
	charge += accepted
	total_earned += accepted
	return accepted

func is_ready() -> bool:
	return charge >= CAPACITY - 1e-6

func consume() -> float:
	if not is_ready():
		return 0.0
	charge = 0.0
	total_spent += CAPACITY
	return CAPACITY
