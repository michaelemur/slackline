extends SceneTree
## Records a side-on "reference video" of the athlete's first backflip in the
## demo, plus the ground truth (body pitch, phases) per frame, for testing the
## motion-capture pipeline. Run with Godot's movie writer at fixed 30 fps:
##   godot --path . --write-movie /out/ref.png --fixed-fps 30 \
##         -s res://tests/record_reference.gd -- /out
var main; var a; var out := "user://"; var cam: Camera3D
var frame := 0
var log := []
var state := "wait"
var done_at := -1
var _aim := Vector3.ZERO


func _initialize():
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: out = args[0]
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _process(d) -> bool:
	frame += 1
	if a == null:
		a = main.get_node("Athlete")
		a.visual.show_com = false
		main.get_node("LabPanel").visible = false
		cam = Camera3D.new()
		cam.fov = 45
		root.add_child(cam)
		cam.current = true
		main.demo.set_enabled(true)
	var lat: Vector3 = main.line.lateral_axis()
	var c: Vector3 = a.global_position + Vector3.UP * 0.9
	# camera operator: side on, 3.6 m away, panning smoothly with the athlete
	_aim = c if frame < 3 else _aim.lerp(c, 0.15)
	cam.look_at_from_position(_aim + lat * 3.6 + Vector3.UP * 0.2, _aim + Vector3.UP * 0.25)
	log.append({"f": frame, "state": a.state, "pitch": a.tricks.pitch, "tuck": a.tricks.tuck,
		"y": a.global_position.y, "pose": a.pose, "l_pitch": a.tricks.l_pitch})
	if a.state == 1 and a.tricks.l_pitch < 0.0 and state == "wait":
		state = "flip"
	if state == "flip" and a.state == 0:
		state = "after"
		done_at = frame
	if done_at > 0 and frame > done_at + 30:
		var f := FileAccess.open(out.path_join("truth.json"), FileAccess.WRITE)
		f.store_string(JSON.stringify(log))
		return true
	return frame > 3000
