class_name TouchControls
extends Control
## Lightweight mobile controls. Each analog pad owns an independent pointer,
## allowing simultaneous movement and balance input with multiple fingers.

const PAD_RADIUS := 62.0
const EDGE := 24.0
const BUTTON_RADIUS := 34.0
const ACTION_LABELS := ["BACK", "FRONT", "TWIST L", "TWIST R", "GRAB L", "GRAB R"]

var athlete_input: AthleteInput
var safe_rect := Rect2()
var _move_pointer := -1
var _balance_pointer := -1
var _pump_pointer := -1
var _trick_pointers: Dictionary = {}
var _move_value := Vector2.ZERO
var _balance_value := Vector2.ZERO

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refresh_safe_rect()
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_WM_SIZE_CHANGED:
		_refresh_safe_rect()
		queue_redraw()

func _refresh_safe_rect() -> void:
	var size := get_viewport_rect().size
	var inset := Vector4(EDGE, EDGE, EDGE, EDGE)
	var screen := DisplayServer.screen_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if screen.x > 0 and screen.y > 0 and safe.size.x > 0 and safe.size.y > 0:
		inset.x = maxf(EDGE, size.x * float(safe.position.x) / screen.x)
		inset.y = maxf(EDGE, size.y * float(safe.position.y) / screen.y)
		inset.z = maxf(EDGE, size.x * float(screen.x - safe.end.x) / screen.x)
		inset.w = maxf(EDGE, size.y * float(screen.y - safe.end.y) / screen.y)
	safe_rect = Rect2(Vector2(inset.x, inset.y), Vector2(size.x - inset.x - inset.z, size.y - inset.y - inset.w))

func _pad_center(left: bool) -> Vector2:
	return Vector2(safe_rect.position.x + PAD_RADIUS + 18.0 if left else safe_rect.end.x - PAD_RADIUS - 18.0,
		safe_rect.end.y - PAD_RADIUS - 20.0)

func _pump_center() -> Vector2:
	return Vector2(safe_rect.get_center().x, safe_rect.end.y - BUTTON_RADIUS - 18.0)

func _trick_center(index: int) -> Vector2:
	return Vector2(safe_rect.end.x - BUTTON_RADIUS - 18.0,
		safe_rect.position.y + BUTTON_RADIUS + 18.0 + index * (BUTTON_RADIUS * 2.0 + 12.0))

func _draw() -> void:
	if not is_visible_in_tree():
		return
	_draw_pad(_pad_center(true), _move_value, "MOVE")
	_draw_pad(_pad_center(false), _balance_value, "BALANCE")
	_draw_button(_pump_center(), "JUMP/TUCK", _pump_pointer >= 0)
	for i in ACTION_LABELS.size():
		_draw_button(_trick_center(i), ACTION_LABELS[i], _trick_pointers.values().has(i))

func _draw_pad(center: Vector2, value: Vector2, label: String) -> void:
	draw_circle(center, PAD_RADIUS, Color(0.03, 0.05, 0.08, 0.28))
	draw_arc(center, PAD_RADIUS, 0.0, TAU, 48, Color(0.85, 0.93, 1.0, 0.55), 2.0)
	draw_circle(center + Vector2(value.x * PAD_RADIUS * 0.55, 0.0), 22.0, Color(0.88, 0.95, 1.0, 0.78))
	draw_string(ThemeDB.fallback_font, center + Vector2(-PAD_RADIUS, PAD_RADIUS + 18.0), label,
		HORIZONTAL_ALIGNMENT_CENTER, PAD_RADIUS * 2.0, 12, Color(1, 1, 1, 0.85))

func _draw_button(center: Vector2, label: String, active: bool) -> void:
	draw_circle(center, BUTTON_RADIUS, Color(0.04, 0.07, 0.12, 0.62 if active else 0.38))
	draw_arc(center, BUTTON_RADIUS, 0.0, TAU, 32, Color(1, 1, 1, 0.7), 2.0)
	draw_string(ThemeDB.fallback_font, center + Vector2(-BUTTON_RADIUS, 5.0), label,
		HORIZONTAL_ALIGNMENT_CENTER, BUTTON_RADIUS * 2.0, 11, Color.WHITE)

func _input(event: InputEvent) -> void:
	if athlete_input == null or not visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_down(event.index, event.position)
		else:
			_touch_up(event.index)
	elif event is InputEventScreenDrag:
		_touch_drag(event.index, event.position)

## Public event handlers are also used by deterministic headless UI tests.
func _touch_down(index: int, position: Vector2) -> void:
	if _move_pointer < 0 and position.distance_to(_pad_center(true)) <= PAD_RADIUS * 1.4:
		_move_pointer = index
		_update_pad(index, position, true)
	elif _balance_pointer < 0 and position.distance_to(_pad_center(false)) <= PAD_RADIUS * 1.4:
		_balance_pointer = index
		_update_pad(index, position, false)
	elif _pump_pointer < 0 and position.distance_to(_pump_center()) <= BUTTON_RADIUS * 1.5:
		_pump_pointer = index
		athlete_input.touch_pump_held = true
	else:
		for i in ACTION_LABELS.size():
			if position.distance_to(_trick_center(i)) <= BUTTON_RADIUS * 1.5:
				_trick_pointers[index] = i
				_update_aerial_actions()
				break
	queue_redraw()

func _touch_drag(index: int, position: Vector2) -> void:
	if index == _move_pointer:
		_update_pad(index, position, true)
	elif index == _balance_pointer:
		_update_pad(index, position, false)
	queue_redraw()

func _update_pad(_index: int, position: Vector2, movement: bool) -> void:
	var center := _pad_center(movement)
	var value := (position - center) / PAD_RADIUS
	value.x = clampf(value.x, -1.0, 1.0)
	value.y = clampf(value.y, -1.0, 1.0)
	if movement:
		_move_value = value
		athlete_input.touch_move_axis = value.x
	else:
		_balance_value = value
		athlete_input.touch_balance_axis = value.x

func _touch_up(index: int) -> void:
	if index == _move_pointer:
		_move_pointer = -1
		_move_value = Vector2.ZERO
		athlete_input.touch_move_axis = 0.0
	if index == _balance_pointer:
		_balance_pointer = -1
		_balance_value = Vector2.ZERO
		athlete_input.touch_balance_axis = 0.0
	if index == _pump_pointer:
		_pump_pointer = -1
		athlete_input.touch_pump_held = false
	_trick_pointers.erase(index)
	_update_aerial_actions()
	queue_redraw()


func _update_aerial_actions() -> void:
	var flip := 0.0
	var twist := 0.0
	for action_index in _trick_pointers.values():
		match int(action_index):
			0: flip -= 1.0
			1: flip += 1.0
			2: twist -= 1.0
			3: twist += 1.0
	athlete_input.touch_flip_axis = clampf(flip, -1.0, 1.0)
	athlete_input.touch_twist_axis = clampf(twist, -1.0, 1.0)
	athlete_input.touch_grab_left = _trick_pointers.values().has(4)
	athlete_input.touch_grab_right = _trick_pointers.values().has(5)
