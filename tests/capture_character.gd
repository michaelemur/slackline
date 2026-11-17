extends SceneTree
## Close-up frames of the skinned athlete in every movement (needs a display /
## xvfb-run). Runs the demo pilot and grabs one frame per event, then forces a
## fall. Usage: godot --path . -s res://tests/capture_character.gd -- /out/dir
var main; var a; var t := 0.0; var out := "user://"; var got := {}
var cam: Camera3D
var side := 1.0
var _fell := false
var _prev_pitch := 0.0
var demo_mode := "rikuto"
const ORDER := ["stand", "arms", "crouch", "takeoff", "flip_90", "flip_180", "flip_270",
	"landing", "butt", "chest", "back", "twist", "fall"]


func _initialize():
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: out = args[0]
	if args.size() > 1: side = float(args[1])
	if args.size() > 2: demo_mode = args[2]
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _shot(n: String) -> void:
	if got.has(n):
		return
	root.get_viewport().get_texture().get_image().save_png(out.path_join("char_%s.png" % n))
	got[n] = true
	print("saved ", n, " t=", snappedf(t, 0.01))


func _process(d) -> bool:
	t += d
	if a == null:
		a = main.get_node("Athlete")
		a.visual.show_com = false
		cam = Camera3D.new()
		cam.fov = 38
		root.add_child(cam)
		cam.current = true
	# side-on close camera following the athlete
	var lat: Vector3 = main.line.lateral_axis()
	var sk: Skeleton3D = a.visual.character.skel
	var c: Vector3 = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("spine_01")).origin
	cam.look_at_from_position(c + lat * 3.4 * side + Vector3.UP * 0.35 + main.line.axis() * 0.8, c)
	var inp = a.input
	if t < 2.0:
		inp.override_enabled = true
		if t > 1.6: _shot("stand")
		return false
	if t < 3.6:
		inp.override_arm_left = 1.0
		inp.override_arm_right = 0.0
		inp.override_balance = 0.6
		if t > 3.3: _shot("arms")
		return false
	if not main.demo.enabled and not _fell:
		inp.override_arm_left = 0.0
		inp.override_balance = 0.0
		main.demo.mode = demo_mode
		main.demo.set_enabled(true)
		Engine.time_scale = 0.5
	if a.state == 0 and a.balance.crouch > 0.7 and a.pose == "" and t > 5.0: _shot("crouch")
	if a.state == 1 and a.air_time < 0.06 and a.tricks.l_pitch != 0.0: _shot("takeoff")
	var p := absf(a.tricks.pitch)
	if a.state == 1 and a.tricks.l_pitch != 0.0:
		var rel := absf(a.tricks.pitch - a.tricks.pitch0)
		if rel > 1.4 and rel < 1.9: _shot("flip_90")
		if rel > 2.9 and rel < 3.4: _shot("flip_180")
		if rel > 4.5 and rel < 5.0: _shot("flip_270")
	if a.state == 0 and got.has("flip_270") and not got.has("landing") and a.pose == "": _shot("landing")
	if a.pose == "butt" and a.pose_blend > 0.95: _shot("butt")
	if a.pose == "chest" and a.pose_blend > 0.95: _shot("chest")
	if a.pose == "back" and a.pose_blend > 0.95: _shot("back")
	if a.state == 1 and absf(wrapf(a.tricks.yaw, -PI, PI)) > 1.2 and absf(wrapf(a.tricks.yaw, -PI, PI)) < 2.0: _shot("twist")
	if (got.size() >= ORDER.size() - 1 or t > 90.0) and not _fell and a.state == 0 and a.pose == "":
		main.demo.set_enabled(false)
		a.balance.omega = 3.0
		a.fall()
		_fell = true
		_fall_t = t
	if _fell and t - _fall_t > 0.45:
		_shot("fall")
		_sheet()
		return true
	return t > 120.0


var _fall_t := 0.0


func _sheet() -> void:
	var tiles: Array[Image] = []
	for n in ORDER:
		var path := out.path_join("char_%s.png" % n)
		if FileAccess.file_exists(path):
			var im := Image.load_from_file(path)
			im.resize(640, 360)
			tiles.append(im)
	var cols := 4
	var rows := int(ceil(tiles.size() / float(cols)))
	var sheet := Image.create(640 * cols, 360 * rows, false, Image.FORMAT_RGBA8)
	for i in tiles.size():
		sheet.blit_rect(tiles[i].duplicate(), Rect2i(0, 0, 640, 360), Vector2i((i % cols) * 640, (i / cols) * 360))
	sheet.save_png(out.path_join("char_sheet.png"))
	print("missing: ", ORDER.filter(func(n): return not got.has(n)))
