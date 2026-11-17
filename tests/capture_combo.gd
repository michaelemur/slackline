extends SceneTree
## Renders the "video combo" demo (T twice) side-on, every 4th frame, into a
## contact sheet. Run with --fixed-fps 30 under xvfb-run.
var main; var a; var n := 0; var out := "/tmp"; var cam: Camera3D; var aim := Vector3.ZERO
var shots: Array[Image] = []
var labels: Array[String] = []
func _initialize():
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: out = args[0]
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
func _process(d) -> bool:
	n += 1
	if a == null:
		a = main.get_node("Athlete"); a.visual.show_com = false
		main.get_node("LabPanel").visible = false
		main.demo.mode = "video"; main.demo.set_enabled(true)
		cam = Camera3D.new(); cam.fov = 50; root.add_child(cam); cam.current = true
	var c: Vector3 = a.global_position + Vector3.UP * 0.8
	aim = c if n < 3 else aim.lerp(c, 0.5)
	cam.look_at_from_position(aim + main.line.lateral_axis() * 5.0 + Vector3.UP * 0.3, aim + Vector3.UP * 0.2)
	if n > 40 and n % 4 == 0 and n < 40 + 4 * 96:
		var im := root.get_viewport().get_texture().get_image()
		im.resize(240, 180)
		shots.append(im)
	if n >= 40 + 4 * 96:
		var cols := 16
		var sheet := Image.create(240 * cols, 180 * 6, false, Image.FORMAT_RGBA8)
		for i in shots.size():
			sheet.blit_rect(shots[i], Rect2i(0, 0, 240, 180), Vector2i((i % cols) * 240, (i / cols) * 180))
		sheet.save_png(out.path_join("combo_sheet.png"))
		return true
	return false
