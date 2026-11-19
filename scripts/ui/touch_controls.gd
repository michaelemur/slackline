class_name TouchControls
extends Control
## Simple two-hand phone controls: RIGHT hand = power, LEFT hand = position.
##
## RIGHT half: touch-and-hold = pump. Hold = sink into the line (or tuck in
##   the air), release = drive off it (or open out). Works in every position
##   (feet, butt, chest, back). While holding, drag to AIM the takeoff lean:
##   up = backflip, down = frontflip, sideways = twist.
## LEFT half: the position pad. Push the thumb toward a position to choose
##   where he lands: up = FEET, down = BUTT, left = BACK, right = CHEST.
##   In a jump, lock it late - close to the landing. On the line it drops
##   into that position. Slide to another direction to change your mind.
##   Sitting in a butt bounce, keeping the left thumb down grips the line
##   (sticky bounce).
## GRAB / PIKE / SPLIT (small buttons, top right): hold for an air grab or
##   leg shape, any time in the air and with any rotation.
## Every finger is tracked independently, so both hands work at once.

const PAD_RADIUS := 82.0
const PAD_DEADZONE := 16.0
const AIM_RADIUS := 60.0
const EDGE := 24.0
const BUTTON_RADIUS := 30.0
const ACTION_LABELS := ["GRAB", "PIKE", "SPLIT"]
const SHAPE_IDS := ["", "pike", "split"]
## pad direction -> position id (screen directions: up is -y)
const PAD_IDS := {"up": "feet", "down": "butt", "left": "back", "right": "chest"}
const PAD_LABELS := {"up": "FEET", "down": "BUTT", "left": "BACK", "right": "CHEST"}

var athlete_input: AthleteInput
var safe_rect := Rect2()
var _pad_pointer := -1
var _pad_dir := ""            # current pad direction ("" = centre / none)
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


## Small buttons sit along the top of the right half (away from the thumb).
func _button_center(index: int) -> Vector2:
	var r := _button_radius()
	var spacing := r * 2.0 + 12.0
	# as many per row as fit in the right half, then the next row down
	var cols := maxi(1, int((safe_rect.size.x * 0.5 - 16.0) / spacing))
	var col := index % cols
	var row := index / cols
	return Vector2(safe_rect.end.x - r - 8.0 - col * spacing, safe_rect.position.y + r + 56.0 + row * spacing)


func _is_left(position: Vector2) -> bool:
	return position.x < safe_rect.get_center().x


func _pad_radius() -> float:
	return minf(PAD_RADIUS, minf(safe_rect.size.y * 0.22, safe_rect.size.x * 0.12))


## Centre of the position pad (where the left thumb rests).
func pad_center() -> Vector2:
	var r := _pad_radius()
	return Vector2(safe_rect.position.x + r + 36.0, safe_rect.end.y - r - 36.0)


## Screen point for a pad direction (tests and the drawn labels).
func pad_point(dir: String) -> Vector2:
	var v: Vector2 = {"up": Vector2.UP, "down": Vector2.DOWN, "left": Vector2.LEFT, "right": Vector2.RIGHT}[dir]
	return pad_center() + v * _pad_radius()


func _hold_home() -> Vector2:
	return Vector2(safe_rect.end.x - AIM_RADIUS - 50.0, safe_rect.end.y - AIM_RADIUS - 40.0)


## Direction of a left-thumb point from the pad centre ("" inside the dead zone).
func _pad_dir_at(position: Vector2) -> String:
	var d := position - pad_center()
	if d.length() < PAD_DEADZONE:
		return ""
	if absf(d.x) > absf(d.y):
		return "right" if d.x > 0.0 else "left"
	return "down" if d.y > 0.0 else "up"


func _draw() -> void:
	if not is_visible_in_tree():
		return
	# LEFT: position pad
	var pc := pad_center()
	var pr := _pad_radius()
	draw_circle(pc, pr * 1.25, Color(0.03, 0.05, 0.08, 0.22))
	for dir: String in PAD_IDS:
		var p := pad_point(dir)
		var on := dir == _pad_dir and _pad_pointer >= 0
		draw_circle(p, pr * 0.42, Color(0.15, 0.55, 1.0, 0.75) if on else Color(0.04, 0.07, 0.12, 0.45))
		draw_arc(p, pr * 0.42, 0.0, TAU, 32, Color(1, 1, 1, 0.7), 2.0)
		_label(p + Vector2(0, 4.0), PAD_LABELS[dir], 11)
	_label(pc + Vector2(0, pr * 1.25 + 18.0), "LAND / POSITION", 11)
	# RIGHT: pump / aim
	var hc := _hold_origin if _hold_pointer >= 0 else _hold_home()
	var active := _hold_pointer >= 0
	draw_circle(hc, AIM_RADIUS, Color(0.95, 0.45, 0.1, 0.35 if active else 0.18))
	draw_arc(hc, AIM_RADIUS, 0.0, TAU, 48, Color(1, 0.85, 0.6, 0.7), 2.0)
	if active:
		draw_line(hc, hc + _aim_value * AIM_RADIUS, Color(1, 1, 1, 0.9), 4.0)
		draw_circle(hc + _aim_value * AIM_RADIUS, 12.0, Color(1, 1, 1, 0.85))
	_label(hc + Vector2(0, -AIM_RADIUS - 8.0), "BACK", 10)
	_label(hc + Vector2(0, AIM_RADIUS + 18.0), "PUMP  -  FRONT", 10)
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
			_update_buttons()
			queue_redraw()
			return
	if _is_left(position):
		if _pad_pointer < 0:
			_pad_pointer = index
			athlete_input.touch_left_down = true
			_pad_dir = ""
			_set_pad(_pad_dir_at(position))
	elif _hold_pointer < 0:
		_hold_pointer = index
		_hold_origin = position
		_aim_value = Vector2.ZERO
		athlete_input.touch_hold = true
		athlete_input.touch_aim = Vector2.ZERO
	queue_redraw()


func _touch_drag(index: int, position: Vector2) -> void:
	if index == _pad_pointer:
		_set_pad(_pad_dir_at(position))
	elif index == _hold_pointer:
		var v := ((position - _hold_origin) / AIM_RADIUS).limit_length(1.0)
		_aim_value = v
		# screen y grows downward: drag UP = lean back (backflip) = aim.y > 0
		athlete_input.touch_aim = Vector2(v.x, -v.y)
	queue_redraw()


## A new pad direction requests that position once (sliding re-chooses).
func _set_pad(dir: String) -> void:
	if dir == _pad_dir:
		return
	_pad_dir = dir
	if dir != "":
		athlete_input.touch_trick = PAD_IDS[dir]


func _touch_up(index: int) -> void:
	if index == _pad_pointer:
		_pad_pointer = -1
		_pad_dir = ""
		athlete_input.touch_left_down = false
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
	athlete_input.touch_shape = ""
	for i in range(1, SHAPE_IDS.size()):
		if _button_pointers.values().has(i):
			athlete_input.touch_shape = SHAPE_IDS[i]
