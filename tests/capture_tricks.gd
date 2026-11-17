extends SceneTree
## Renders frames mid-flip and in a butt bounce during demo mode (needs a display / xvfb-run).
var main; var a; var t := 0.0; var out := "user://"; var got := {}
func _initialize():
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: out = args[0]
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
func _shot(n: String) -> void:
	root.get_viewport().get_texture().get_image().save_png(out.path_join(n + ".png")); got[n] = true; print("saved ", n)
func _process(d):
	t += d
	if a == null:
		a = main.get_node("Athlete"); main.demo.set_enabled(true); Engine.time_scale = 0.4
	var p := absf(wrapf(a.tricks.pitch, -PI, PI))
	if not got.has("flip") and a.state == 1 and p > 2.2 and a.tricks.tuck > 0.8: _shot("flip")
	if not got.has("butt") and a.pose == "butt" and a.pose_blend > 0.95: _shot("butt")
	return t > 50 or got.size() >= 2
