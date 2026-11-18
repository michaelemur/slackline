class_name TouchControls
extends Control
## Two-zone mobile controls (Flip Master-inspired, adapted to a trickline).
##
## LEFT half: floating balance stick. Touch anywhere, drag: x = weight shift,
##   y = walk along the line (on the feet) / small air attitude correction.
## RIGHT half: touch-and-hold. Hold = load the line (or tuck in the air),
##   release = drive (or open/straight). While holding, drag from where the
##   finger went down to AIM the takeoff lean: up = backflip, down = frontflip,
##   sideways = twist.
## Small buttons (top right): GRAB (hold, works tucked or straight) and the
##   line positions BUTT / CHEST / BACK (tap).
## Every finger is tracked independently, so both hands work at once.

const STICK_RADIUS := 70.0
const AIM_RADIUS := 60.0
const EDGE := 24.0
const BUTTON_RADIUS := 30.0
const ACTION_LABELS := ["GRAB", "BUTT", "CHEST", "BACK"]
const POSITION_IDS := ["", "butt", "chest", "back"]

var athlete_input: AthleteInput
var safe_rect := Rect2()
var _stick_pointer := -1
var _stick_origin := Vector2.ZERO
var _stick_value := Vector2.ZERO
var _hold_pointer := -1
var _hold_origin := Vector2.ZERO
var _aim_value := Vector2.ZERO
var _button_pointers: Dictionary = {}


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


func _button_radius() -> float:
	return 22.0 if safe_rect.size.y < 420.0 else BUTTON_RADIUS


## Buttons sit in a row along the top of the right half (away from the thumb).
func _button_center(index: int) -> Vector2:
	var r := _button_radius()
	var spacing := r * 2.0 + 12.0
	var cols := 4 if safe_rect.size.x >= 600.0 else 2
	var col := index % cols
	var row := index / cols
	return Vector2(safe_rect.end.x - r - 8.0 - col * spacing, safe_rect.position.y + r + 56.0 + row * spacing)


func _is_left(position: Vector2) -> bool:
	return position.x < safe_rect.get_center().x


## Idle hints: where the thumbs usually rest.
func _stick_home() -> Vector2:
	return Vector2(safe_rect.position.x + STICK_RADIUS + 30.0, safe_rect.end.y - STICK_RADIUS - 30.0)


func _hold_home() -> Vector2:
	return Vector2(safe_rect.end.x - AIM_RADIUS - 50.0, safe_rect.end.y - AIM_RADIUS - 40.0)


func _draw() -> void:
	if not is_visible_in_tree():
		return
	var sc := _stick_origin if _stick_pointer >= 0 else _stick_home()
	draw_circle(sc, STICK_RADIUS, Color(0.03, 0.05, 0.08, 0.25))
	draw_arc(sc, STICK_RADIUS, 0.0, TAU, 48, Color(0.85, 0.93, 1.0, 0.5), 2.0)
	draw_circle(sc + _stick_value * STICK_RADIUS, 24.0, Color(0.88, 0.95, 1.0, 0.75))
	_label(sc + Vector2(0, STICK_RADIUS + 18.0), "BALANCE", 12)
	var hc := _hold_origin if _hold_pointer >= 0 else _hold_home()
	var active := _hold_pointer >= 0
	draw_circle(hc, AIM_RADIUS, Color(0.95, 0.45, 0.1, 0.35 if active else 0.18))
	draw_arc(hc, AIM_RADIUS, 0.0, TAU, 48, Color(1, 0.85, 0.6, 0.7), 2.0)
	if active:
		draw_line(hc, hc + _aim_value * AIM_RADIUS, Color(1, 1, 1, 0.9), 4.0)
		draw_circle(hc + _aim_value * AIM_RADIUS, 12.0, Color(1, 1, 1, 0.85))
	_label(hc + Vector2(0, -AIM_RADIUS - 8.0), "BACK", 10)
	_label(hc + Vector2(0, AIM_RADIUS + 18.0), "HOLD  -  FRONT", 10)
	var r := _button_radius()
	for i in ACTION_LABELS.size():
		var c := _button_center(i)
		var on := _button_pointers.values().has(i)
		draw_circle(c, r, Color(0.04, 0.07, 0.12, 0.62 if on else 0.38))
		draw_arc(c, r, 0.0, TAU, 32, Color(1, 1, 1, 0.7), 2.0)
		_label(c + Vector2(0, 4.0), ACTION_LABELS[i], 9 if r < BUTTON_RADIUS else 10)


func _label(center: Vector2, text: String, size: int) -> void:
	draw_string(ThemeDB.fallback_font, center + Vector2(-60.0, 0.0), text,
		HORIZONTAL_ALIGNMENT_CENTER, 120.0, size, Color(1, 1, 1, 0.85))


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
	var r := _button_radius()
	for i in ACTION_LABELS.size():
		if position.distance_to(_button_center(i)) <= r * 1.3:
			_button_pointers[index] = i
			if POSITION_IDS[i] != "":
				athlete_input.touch_trick = POSITION_IDS[i]
			_update_buttons()
			queue_redraw()
			return
	if _is_left(position):
		if _stick_pointer < 0:
			_stick_pointer = index
			_stick_origin = position
			_set_stick(Vector2.ZERO)
	elif _hold_pointer < 0:
		_hold_pointer = index
		_hold_origin = position
		_aim_value = Vector2.ZERO
		athlete_input.touch_hold = true
		athlete_input.touch_aim = Vector2.ZERO
	queue_redraw()


func _touch_drag(index: int, position: Vector2) -> void:
	if index == _stick_pointer:
		_set_stick((position - _stick_origin) / STICK_RADIUS)
	elif index == _hold_pointer:
		var v := ((position - _hold_origin) / AIM_RADIUS).limit_length(1.0)
		_aim_value = v
		# screen y grows downward: drag UP = lean back (backflip) = aim.y > 0
		athlete_input.touch_aim = Vector2(v.x, -v.y)
	queue_redraw()


func _set_stick(v: Vector2) -> void:
	_stick_value = v.limit_length(1.0)
	# screen up = walk forward
	athlete_input.touch_stick = Vector2(_stick_value.x, -_stick_value.y)


func _touch_up(index: int) -> void:
	if index == _stick_pointer:
		_stick_pointer = -1
		_set_stick(Vector2.ZERO)
	if index == _hold_pointer:
		_hold_pointer = -1
		_aim_value = Vector2.ZERO
		athlete_input.touch_hold = false
		athlete_input.touch_aim = Vector2.ZERO
	_button_pointers.erase(index)
	_update_buttons()
	queue_redraw()


func _update_buttons() -> void:
	athlete_input.touch_grab = _button_pointers.values().has(0)
