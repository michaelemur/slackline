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
var flip_axis: float = 0.0       # legacy/test only: held in-air torque
var twist_axis: float = 0.0      # legacy/test only: held in-air torque

## --- Two-zone control intents (Flip Master-inspired) ---------------------
## RIGHT hand: one touch-and-hold. On the line: hold = load (sink), release =
## drive. In the air: hold = tuck, release = open/straight. While holding, the
## drag direction is the AIM: y > 0 lean back (backflip), y < 0 lean forward
## (frontflip), x = twist direction. The aim only matters during the push: the
## lean of the body at takeoff is what makes the rotation.
var hold: bool = false
var aim: Vector2 = Vector2.ZERO
## LEFT hand: balance stick. x = weight shift left/right (on the line and in
## the air); y = walk along the line (on feet) / small attitude correction of
## the arms and hips in the air (no new angular momentum).
var stick: Vector2 = Vector2.ZERO
var grab_held: bool = false      # independent of tuck/straight
## Sticky bounce grip (hands on the line while sitting): F / GRAB button, or on
## a phone simply keeping the LEFT thumb down (balance is not needed while
## seated, so the left hand holds on and the right hand pumps).
var grip_held: bool = false
var touch_left_down: bool = false

var touch_aim: Vector2 = Vector2.ZERO
var touch_hold: bool = false
var touch_stick: Vector2 = Vector2.ZERO
var touch_grab: bool = false
var override_aim: Vector2 = Vector2.ZERO
var override_stick_y: float = 0.0

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
var touch_shape: String = ""      # phone: leg shape button held ("pike" / "split")

const GRAB_ACTIONS := {
	"grab_both_knees": "both_knees",   # B
	"grab_knee": "knee",               # N
	"grab_leg": "leg",                 # O
	"grab_cross": "cross",             # P
	"grab_tuck": "tuck",               # F (in the air)
	"grab_left": "left_knee",
	"grab_right": "knee",
	"air_pike": "pike",
	"air_straddle": "straddle",
	"air_split": "split",
}

const TRICK_ACTIONS := {
	"trick_backflip": "backflip",
	"trick_frontflip": "frontflip",
	"trick_spin360": "spin360",
	"trick_spin180": "spin180",
	"trick_backflip360": "backflip360",
	"trick_frontflip360": "frontflip360",
	"trick_backflip180": "backflip180",
	"trick_feet": "feet",
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
		hold = pump_held
		aim = override_aim.limit_length(1.0)
		stick = Vector2(balance_axis, override_stick_y)
		grab_held = grab != ""
		grip_held = grab_held
	else:
		# LEFT: balance stick (A/D weight, W/S walk / air attitude; left stick)
		stick = Vector2(Input.get_axis("balance_left", "balance_right"),
			Input.get_axis("move_back", "move_forward")) + touch_stick + Vector2(touch_balance_axis, touch_move_axis)
		stick = stick.limit_length(1.0)
		balance_axis = stick.x
		move_axis = stick.y if absf(stick.y) > 0.25 else 0.0
		# RIGHT: hold (SPACE / A button / touch) + aim (arrows, J/K/H/L, right stick)
		hold = Input.is_action_pressed("pump") or touch_pump_held or touch_hold
		aim = Vector2(Input.get_axis("aim_twist_left", "aim_twist_right"),
			Input.get_axis("aim_front", "aim_back")) + touch_aim
		aim = aim.limit_length(1.0)
		pump_held = hold
		knees = 1.0 if Input.is_action_pressed("knees") else 0.0
		tuck = 1.0 if hold or Input.is_action_pressed("body_tuck") else 0.0
		# legacy in-air torque is no longer on the default controls
		flip_axis = clampf(touch_flip_axis, -1.0, 1.0)
		twist_axis = clampf(touch_twist_axis, -1.0, 1.0)
		arm_left = 1.0 if Input.is_action_pressed("arm_left") else 0.0
		arm_right = 1.0 if Input.is_action_pressed("arm_right") else 0.0
		leg_lift = 1.0 if Input.is_action_pressed("leg_lift") else 0.0
		grab_held = Input.is_action_pressed("grab") or touch_grab or touch_grab_left or touch_grab_right
		grip_held = grab_held or touch_left_down
		# grabs are independent of the body shape: the same grab button holds
		# the knees when tucked, the shins/legs when straight
		grab = ("both_knees" if tuck > 0.5 else "leg") if grab_held else ""
		for action in GRAB_ACTIONS:
			if InputMap.has_action(action) and Input.is_action_pressed(action):
				grab = GRAB_ACTIONS[action]
		if touch_shape != "":
			grab = touch_shape
		trick = ""
		for action in TRICK_ACTIONS:
			if InputMap.has_action(action) and Input.is_action_just_pressed(action):
				trick = TRICK_ACTIONS[action]
		if touch_trick != "":
			trick = touch_trick
			touch_trick = ""
	jump_released = _prev_pump and not pump_held
	_prev_pump = pump_held
