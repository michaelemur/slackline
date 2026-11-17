class_name CameraRig
extends Node3D
## Third-person follow camera. Follows the athlete horizontally tightly and
## vertically loosely (so the line bounce reads on screen without nausea).

@export var target_path: NodePath
@export var distance: float = 6.0
@export var height: float = 2.0
@export var yaw_deg: float = -35.0        # 0 = straight behind, +/- orbits
@export var look_height: float = 1.4
@export var follow_rate_xz: float = 6.0
@export var follow_rate_y: float = 4.5
@export var orbit_speed_deg: float = 70.0

## Optional: the CinematicDirector whose `shot` shapes the framing.
var director: Node = null
## Optional: the line, so high jumps frame both athlete and line.
var line: Node = null
var target: Node3D
var camera: Camera3D
var _rt := 0.0   # real time, for shake noise
var _focus := Vector3.ZERO
var _forward := Vector3.RIGHT


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 62.0
	camera.near = 0.05
	camera.far = 400.0
	add_child(camera)
	camera.make_current()
	if target_path:
		target = get_node_or_null(target_path)
	if target:
		_focus = target.global_position
	snap()


func set_forward(f: Vector3) -> void:
	_forward = Vector3(f.x, 0, f.z).normalized()


func snap() -> void:
	if target:
		_focus = target.global_position
	_place()


func _process(delta: float) -> void:
	if target == null:
		return
	# The camera runs on REAL time so it stays smooth in slow motion.
	delta = delta / maxf(Engine.time_scale, 0.05)
	_rt += delta
	if Input.is_action_pressed("cam_orbit_left"):
		yaw_deg -= orbit_speed_deg * delta
	if Input.is_action_pressed("cam_orbit_right"):
		yaw_deg += orbit_speed_deg * delta
	var t := target.global_position
	var kxz := 1.0 - exp(-follow_rate_xz * delta)
	var ky := 1.0 - exp(-follow_rate_y * delta)
	_focus.x = lerpf(_focus.x, t.x, kxz)
	_focus.z = lerpf(_focus.z, t.z, kxz)
	var ty := t.y
	var pull: float = director.shot["pull"] if director else 0.0
	var sup: float = director.shot["super"] if director else 0.0
	if line != null and (pull > 0.0 or sup > 0.0):
		# frame the whole jump: aim between the athlete and the line
		var s: float = clampf(line.project_s(t), 0.3, line.chord_length() - 0.3)
		var ly: float = line.sample_world(s).y
		ty = lerpf(ty, (ty + ly) * 0.5, maxf(pull, sup) * 0.6)
	_focus.y = lerpf(_focus.y, ty, ky)
	_place()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(2.0, distance - 0.4)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(15.0, distance + 0.4)


func _place() -> void:
	if camera == null:
		return
	var d := distance
	var h := height
	var yaw := yaw_deg
	var lh := look_height
	if director:
		var sh: Dictionary = director.shot
		d *= 1.0 + 0.45 * sh["pull"]          # high jump: pull back
		h += 0.7 * sh["pull"]
		d += 3.0 * sh["super"]                # super rebound: reveal the height
		h += 1.2 * sh["super"]
		yaw += 12.0 * sh["trick"]             # trick: slight orbit
		h -= 0.3 * sh["trick"]
		d = lerpf(d, 3.8, sh["close"])        # super trick: close, low, from the side
		h = lerpf(h, 0.6, sh["close"])
		yaw += 35.0 * sh["close"]
		d *= 1.0 - 0.12 * sh["combo"]         # combo: subtle zoom
		lh -= 0.2 * sh["close"]
	var back := -_forward.rotated(Vector3.UP, deg_to_rad(yaw))
	global_position = _focus + back * d + Vector3.UP * h
	global_position.y = maxf(global_position.y, 0.4)   # never below the sand
	var look := _focus + Vector3.UP * lh
	if global_position.distance_to(look) > 0.01:
		look_at(look, Vector3.UP)
	# shake (trauma^2), on the camera only
	var tr: float = director.shot["trauma"] if director else 0.0
	var a := tr * tr
	camera.position = Vector3(sin(_rt * 37.0) + 0.5 * sin(_rt * 71.0), cos(_rt * 41.0) + 0.5 * sin(_rt * 59.0), 0.0) * 0.08 * a
	camera.rotation = Vector3(0.0, 0.0, sin(_rt * 29.0) * 0.03 * a)
