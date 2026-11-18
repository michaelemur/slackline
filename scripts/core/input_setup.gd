class_name InputSetup
extends RefCounted
## Registers the keyboard input map in code (robust, diff-friendly, testable).
## Mobile touch controls (v0.2) will feed the same AthleteInput, not these actions.

const BINDINGS := {
	# LEFT hand: balance stick
	"move_forward": [KEY_W],
	"move_back": [KEY_S],
	"balance_left": [KEY_A],
	"balance_right": [KEY_D],
	# RIGHT hand: hold + aim
	"pump": [KEY_SPACE],
	"body_tuck": [KEY_SPACE],
	"aim_back": [KEY_UP, KEY_J],
	"aim_front": [KEY_DOWN, KEY_K],
	"aim_twist_left": [KEY_LEFT, KEY_H],
	"aim_twist_right": [KEY_RIGHT, KEY_L],
	"grab": [KEY_F],
	# line positions (where to land / drop into)
	"trick_butt": [KEY_Z],
	"trick_chest": [KEY_X],
	"trick_back": [KEY_C],
	# body extras
	"arm_left": [KEY_Q],
	"arm_right": [KEY_E],
	"knees": [KEY_SHIFT],
	"leg_lift": [KEY_SEMICOLON],
	# game
	"reset": [KEY_R],
	"toggle_lab": [KEY_F1, KEY_TAB],
	"pause": [KEY_ESCAPE],
	"preset_trickline": [KEY_1],
	"preset_standard": [KEY_2],
	"preset_trickline_30m": [KEY_3],
	"preset_trickline_40m": [KEY_4],
	"cam_orbit_left": [KEY_BRACKETLEFT, KEY_9],
	"cam_orbit_right": [KEY_BRACKETRIGHT, KEY_0],
	"toggle_com": [KEY_F9],
	"toggle_character": [KEY_V],
	"demo_toggle": [KEY_T],
	"slow_motion": [KEY_M],
	"toggle_music": [KEY_N],
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
	_add_joy_button("grab", JOY_BUTTON_X)
	_add_joy_button("trick_butt", JOY_BUTTON_DPAD_DOWN)
	_add_joy_button("trick_chest", JOY_BUTTON_DPAD_RIGHT)
	_add_joy_button("trick_back", JOY_BUTTON_DPAD_LEFT)
	_add_joy_motion("move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_add_joy_motion("move_back", JOY_AXIS_LEFT_Y, 1.0)
	_add_joy_motion("balance_left", JOY_AXIS_LEFT_X, -1.0)
	_add_joy_motion("balance_right", JOY_AXIS_LEFT_X, 1.0)
	_add_joy_motion("aim_back", JOY_AXIS_RIGHT_Y, -1.0)
	_add_joy_motion("aim_front", JOY_AXIS_RIGHT_Y, 1.0)
	_add_joy_motion("aim_twist_left", JOY_AXIS_RIGHT_X, -1.0)
	_add_joy_motion("aim_twist_right", JOY_AXIS_RIGHT_X, 1.0)


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
