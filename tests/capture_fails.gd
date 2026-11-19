extends SceneTree
## Frames of every fail type's ragdoll fall + the butt seat after a push
## (needs a display). Usage: godot --path . -s res://tests/capture_fails.gd -- /out/dir
var main; var a; var t := 0.0; var out := "user://"
var cam: Camera3D
var kinds := ["over_rotate", "under_rotate", "feet_miss", "twisted_off", "ejected"]
var ki := 0
var phase := "start"
var pt := 0.0
const SHOTS := [0.12, 0.3, 0.55, 0.85]
var shot_i := 0
var tiles: Array[Image] = []
var _cam_pos := Vector3.ZERO


func _initialize():
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: out = args[0]
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _grab() -> void:
	var im := root.get_viewport().get_texture().get_image()
	im.resize(480, 270)
	tiles.append(im)


var _frames := 0
func _process(d) -> bool:
	t += d
	_frames += 1
	if a == null:
		a = main.get_node("Athlete")
		a.input.override_enabled = true
		a.visual.show_com = false
		cam = Camera3D.new()
		cam.fov = 50
		root.add_child(cam)
		cam.current = true
	var lat: Vector3 = main.line.lateral_axis()
	var c: Vector3 = a.visual.com_global()
	var want: Vector3 = c + lat * 5.0 + Vector3.UP * 0.6 + main.line.axis() * 1.2
	_cam_pos = want if _cam_pos == Vector3.ZERO else _cam_pos.lerp(want, 0.15)
	cam.look_at_from_position(_cam_pos, c)
	pt += d
	a.input.override_balance = 0.0
	match phase:
		"start":
			if t > 1.0:
				a.reset_to_line(main.line.chord_length() * 0.5)
				a.force_fail_kind = kinds[ki]
				a.launch(Vector3.UP * 5.5)
				phase = "air"
				pt = 0.0
		"air":
			if a.state == 0 and pt > 1.5:
				a.launch(Vector3.UP * 5.5)
				pt = 0.0
			if a.state == 2 or (a.state == 1 and a.air_time > 0.45):
				a.fall("capture", "none")
				phase = "fall"
				pt = 0.0
				shot_i = 0
		"fall":
			if shot_i < SHOTS.size() and pt >= SHOTS[shot_i]:
				_grab()
				shot_i += 1
			if shot_i >= SHOTS.size():
				ki += 1
				if ki >= kinds.size():
					phase = "seat"
					a.force_fail_kind = ""
					a.reset_to_line(main.line.chord_length() * 0.5)
					pt = 0.0
				else:
					phase = "start"
					t = 0.5
		"seat":
			# drop into butt, auto push, back in the seat after it (the old glitch)
			if pt > 0.2 and pt < 0.25:
				a.input.override_trick = "butt"
			else:
				a.input.override_trick = ""
			if pt > 2.6 and a.pose == "butt":
				_grab()
				_sheet()
				return true
			if pt > 8.0:
				_sheet()
				return true
	return false


func _sheet() -> void:
	var cols := 4
	var rows := int(ceil(tiles.size() / float(cols)))
	var sheet := Image.create(480 * cols, 270 * rows, false, Image.FORMAT_RGBA8)
	for i in tiles.size():
		sheet.blit_rect(tiles[i], Rect2i(0, 0, 480, 270), Vector2i((i % cols) * 480, (i / cols) * 270))
	sheet.save_png(out.path_join("fails_sheet.png"))
	print("saved sheet with %d frames (rows: %s + seat)" % [tiles.size(), str(kinds)])
