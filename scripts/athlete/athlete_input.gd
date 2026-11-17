class_name AthleteInput
extends Node
## Input abstraction: gameplay reads ONLY from here. Keyboard today; the
## mobile virtual joystick (move) + balance pad + trick buttons will write into
## the same fields later. Movement and balance are deliberately independent.

var move_axis: float = 0.0       # +1 forward along line, -1 back
var balance_axis: float = 0.0    # +1 throw weight right, -1 left
var pump_held: bool = false      # hold = sink/pump the line
var jump_released: bool = false  # true on the tick pump is released
var trick: String = ""           # trick id requested this tick ("" = none)
var knees: float = 0.0           # 0..1 bend knees (lower the centre of mass)
var tuck: float = 0.0            # in the air: hold flip key or SPACE = tuck
var arm_left: float = 0.0        # 0..1 raise left arm
var arm_right: float = 0.0       # 0..1 raise right arm
var leg_lift: float = 0.0        # on the line: hold F = balance on one leg
var grab: String = ""            # in the air: grab held ("" = none)
var flip_axis: float = 0.0       # -1 backflip, +1 frontflip; held torque
var twist_axis: float = 0.0      # -1 left, +1 right; held torque

## Touch controls feed these alongside keyboard input. Axes are combined and
## clamped so a touch player can still use a keyboard during desktop testing.
var touch_move_axis: float = 0.0
var touch_balance_axis: float = 0.0
var touch_pump_held: bool = false
var touch_trick: String = ""
var touch_flip_axis: float = 0.0
var touch_twist_axis: float = 0.0
var touch_grab_left: bool = false
var touch_grab_right: bool = false

const GRAB_ACTIONS := {
	"grab_both_knees": "both_knees",   # B
	"grab_knee": "knee",               # N
	"grab_leg": "leg",                 # O
	"grab_cross": "cross",             # P
	"grab_tuck": "tuck",               # F (in the air)
	"grab_left": "left_knee",
	"grab_right": "knee",
}

const TRICK_ACTIONS := {
	"trick_backflip": "backflip",
	"trick_frontflip": "frontflip",
	"trick_spin360": "spin360",
	"trick_spin180": "spin180",
	"trick_backflip360": "backflip360",
	"trick_frontflip360": "frontflip360",
	"trick_backflip180": "backflip180",
	"trick_butt": "butt",
	"trick_chest": "chest",
	"trick_back": "back",
}

## Tests / replays / AI can drive the athlete by enabling the override.
var override_enabled: bool = false
var override_move: float = 0.0
var override_balance: float = 0.0
var override_pump: bool = false
var override_trick: String = ""   # consumed after one poll
var override_knees: float = 0.0
var override_arm_left: float = 0.0
var override_arm_right: float = 0.0
var override_leg_lift: float = 0.0
var override_grab: String = ""
var override_flip_axis: float = 0.0
var override_twist_axis: float = 0.0
var override_tuck: float = -1.0       # -1 preserves older test/replay inputs

var _prev_pump: bool = false


func poll() -> void:
	if override_enabled:
		move_axis = override_move
		balance_axis = override_balance
		pump_held = override_pump
		trick = override_trick
		override_trick = ""
		knees = override_knees
		tuck = 1.0 if override_pump else 0.0
		arm_left = override_arm_left
		arm_right = override_arm_right
		leg_lift = override_leg_lift
		grab = override_grab
		flip_axis = clampf(override_flip_axis, -1.0, 1.0)
		twist_axis = clampf(override_twist_axis, -1.0, 1.0)
		tuck = 1.0 if override_pump else 0.0
		if override_tuck >= 0.0:
			tuck = clampf(override_tuck, 0.0, 1.0)
	else:
		move_axis = clampf(Input.get_axis("move_back", "move_forward") + touch_move_axis, -1.0, 1.0)
		balance_axis = clampf(Input.get_axis("balance_left", "balance_right") + touch_balance_axis, -1.0, 1.0)
		pump_held = Input.is_action_pressed("pump") or touch_pump_held
		knees = 1.0 if Input.is_action_pressed("knees") else 0.0
		tuck = 1.0 if pump_held or Input.is_action_pressed("body_tuck") else 0.0
		flip_axis = clampf(Input.get_axis("flip_back", "flip_front") + touch_flip_axis, -1.0, 1.0)
		twist_axis = clampf(Input.get_axis("twist_left", "twist_right") + touch_twist_axis, -1.0, 1.0)
		arm_left = 1.0 if Input.is_action_pressed("arm_left") else 0.0
		arm_right = 1.0 if Input.is_action_pressed("arm_right") else 0.0
		leg_lift = 1.0 if Input.is_action_pressed("grab_tuck") else 0.0
		grab = ""
		for action in GRAB_ACTIONS:
			if Input.is_action_pressed(action):
				grab = GRAB_ACTIONS[action]
		if touch_grab_left and touch_grab_right:
			grab = "both_knees"
		elif touch_grab_left:
			grab = "left_knee"
		elif touch_grab_right:
			grab = "knee"
		trick = ""
		for action in TRICK_ACTIONS:
			if Input.is_action_just_pressed(action):
				trick = TRICK_ACTIONS[action]
		if touch_trick != "":
			trick = touch_trick
			touch_trick = ""
	jump_released = _prev_pump and not pump_held
	_prev_pump = pump_held
