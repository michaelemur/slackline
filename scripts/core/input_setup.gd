class_name InputSetup
extends RefCounted
## Registers the keyboard input map in code (robust, diff-friendly, testable).
## Mobile touch controls (v0.2) will feed the same AthleteInput, not these actions.

const BINDINGS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"balance_left": [KEY_A, KEY_LEFT],
	"balance_right": [KEY_D, KEY_RIGHT],
	"pump": [KEY_SPACE],
	"body_tuck": [KEY_SPACE],
	"flip_back": [KEY_J],
	"flip_front": [KEY_K],
	"twist_left": [KEY_H],
	"twist_right": [KEY_L],
	"grab_left": [KEY_COMMA],
	"grab_right": [KEY_PERIOD],
	"reset": [KEY_R],
	"toggle_lab": [KEY_F1, KEY_TAB],
	"preset_trickline": [KEY_1],
	"preset_standard": [KEY_2],
	"cam_orbit_left": [KEY_BRACKETLEFT, KEY_9],
	"cam_orbit_right": [KEY_BRACKETRIGHT, KEY_0],
	"arm_left": [KEY_Q],
	"arm_right": [KEY_E],
	"knees": [KEY_SHIFT],
	"toggle_com": [KEY_G],
	"toggle_character": [KEY_V],
	"grab_both_knees": [KEY_B],
	"grab_knee": [KEY_N],
	"grab_leg": [KEY_O],
	"grab_cross": [KEY_P],
	"grab_tuck": [KEY_F],
	"trick_backflip": [KEY_J],
	"trick_frontflip": [KEY_K],
	"trick_spin360": [KEY_L],
	"trick_spin180": [KEY_H],
	"trick_backflip360": [KEY_U],
	"trick_frontflip360": [KEY_I],
	"trick_backflip180": [KEY_Y],
	"trick_butt": [KEY_Z],
	"trick_chest": [KEY_X],
	"trick_back": [KEY_C],
	"demo_toggle": [KEY_T],
	"slow_motion": [KEY_M],
}


static func ensure_actions() -> void:
	for action in BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for key in BINDINGS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			if not InputMap.action_has_event(action, ev):
				InputMap.action_add_event(action, ev)
	_add_joy_button("pump", JOY_BUTTON_A)
	_add_joy_button("body_tuck", JOY_BUTTON_A)
	_add_joy_button("flip_back", JOY_BUTTON_LEFT_SHOULDER)
	_add_joy_button("flip_front", JOY_BUTTON_RIGHT_SHOULDER)
	_add_joy_button("twist_left", JOY_BUTTON_DPAD_LEFT)
	_add_joy_button("twist_right", JOY_BUTTON_DPAD_RIGHT)
	_add_joy_button("grab_left", JOY_BUTTON_X)
	_add_joy_button("grab_right", JOY_BUTTON_Y)
	_add_joy_motion("move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_add_joy_motion("move_back", JOY_AXIS_LEFT_Y, 1.0)
	_add_joy_motion("balance_left", JOY_AXIS_RIGHT_X, -1.0)
	_add_joy_motion("balance_right", JOY_AXIS_RIGHT_X, 1.0)


static func _add_joy_button(action: String, button: int) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	if not InputMap.action_has_event(action, ev):
		InputMap.action_add_event(action, ev)


static func _add_joy_motion(action: String, axis: int, value: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	if not InputMap.action_has_event(action, ev):
		InputMap.action_add_event(action, ev)
